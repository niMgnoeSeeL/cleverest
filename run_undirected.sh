#!/bin/bash

# usage: run.sh <path-to-config-file> 
# eg. run.sh poppler.env

# Default configurations
SCENARIO=${SCENARIO:-BIC}
# undirected version without git commit info
GIT_INFO=${GIT_INFO:-NONE}
MAX_ITER=${MAX_ITER:-5}
LLM=${LLM:-"gpt-4o-2024-08-06"}
LLM_TEMP=${LLM_TEMP:-0.5}
NOFEEDBACK=${NOFEEDBACK:-""}
GENCMD=${GENCMD:-""}
RUNFUZZ=${RUNFUZZ:-""}

# https://github.com/janlay/openai-cli should be put in CWD
openai=openai

source utils.sh
# load proj-specific config file
conf=$1
source $conf

print_configurations() {
    echo "SCENARIO: $SCENARIO"
    echo "GIT_INFO: $GIT_INFO"
    echo "MAX_ITER: $MAX_ITER"
    echo "LLM: $LLM"
    echo "LLM_TEMP: $LLM_TEMP"
    echo "NOFEEDBACK: $NOFEEDBACK"
    echo "GENCMD: $GENCMD"
    echo "RUNFUZZ: $RUNFUZZ"
}

suffix=$(date +"%y%m%d-%H%M")
conf_suffix=${PROJ_NAME}_${SCENARIO}_GIT${GIT_INFO}_ITER${MAX_ITER}_${LLM}_TEMP${LLM_TEMP}
conf_suffix+=$( [ -n "$GENCMD" ] && echo "_GENCMD" )$( [ -n "$NOFEEDBACK" ] && echo "_NOFEEDBACK")$( [ -n "$RUNFUZZ" ] && echo "_RUNFUZZ")
full_suffix=${conf_suffix}_${suffix}

git_commit_info () {
    local commit=$1
    # if GIT_INFO is set to MSGONLY, call git_commit_msgonly
    # if GIT_INFO is set to DIFFONLY, call git_commit_diffonly
    # otherwise, call git_commit_content
    if [ "$GIT_INFO" = "MSGONLY" ]; then
        git_commit_msgonly $commit
    elif [ "$GIT_INFO" = "DIFFONLY" ]; then
        git_commit_diffonly $commit
    else
        git_commit_content $commit
    fi
}

collect_exp () {
    set -x
    # collect all generated files and logs to a folder
    local proj_dir=$1
    local target_dir=$2
    mkdir -p $target_dir
    pushd $proj_dir
    mv *$LLM* *.gcov* ../$target_dir
    popd
    set +x
}

gcov_all () {
# adapter function, call gcovr_tree if proj is mujs or poppler, otherwise call gcov_tree
    local builddir=$1
    local proj=${2:-$PROJ_NAME}
    if [ "$proj" = "mujs" ] || [ "$proj" = "poppler" ]; then
        echo "Using gcovr to get all coverage for $proj in $builddir." >&2
        gcovr_tree $builddir $proj
        # some commits in mujs fails with gcovr with retcode 1, use gcov instead
        if [ $? -ne 0 ]; then
            echo "gcovr failed, using gcov instead." >&2
            gcov_tree $builddir $proj
        fi
    else
        echo "Using gcov to get all coverage for $proj in $builddir." >&2
        gcov_tree $builddir $proj
    fi
    rm -f *.gcov; rm -f $builddir/*.gcov
}

export ASAN_OPTIONS=detect_leaks=0
PROMPT_SYS_PROJ="You are a software expert testing $PROJ_NAME, $PROJ_DESC"
PROMPT_SYS_FORMAT="You must respond only ONE answer with following format:
\`\`\`
input you construct, not too long, can be valid/broken format
\`\`\`
A very brief explanation of how your input can trigger bug for this program."

PROMPT_SYS_GOAL_BIC="I will show a commit that introduces potential new bug, please review carefully and construct a input to trigger bug, or cause behavior difference, or at least reach lines affected by this commit.
Since the bug is introduced by commit, it should be triggered for program after the commit, not before the commit."
PROPMT_SYS_GOAL_FIX="I will show a commit that fixs known bug, please review carefully and construct a input to reproduce bug, or cause behavior difference, or at least reach lines affected by this commit.
Since the bug is fixed by the commit, it should be triggered for program before the commit, not after the commit."
PROMPT_SYS_GOAL_UNDIRECTED="I want you to construct a input as regression test for a commit that we do not know details. I will execute it to see if it trigger/reproduce the bug, then give you feedback about program output and coverage."

construct_prompt () {
    local commit=$1
    local command=$2
    local exes=$3
    local help_msg=$4
    local prompt_sys_goal="$PROMPT_SYS_GOAL_UNDIRECTED"
    
    local prompt_sys_format="$PROMPT_SYS_FORMAT"

    # if GENCMD is set or command is empty
    if [ "$GENCMD" ] || [ -z "$command" ]; then
        prompt_sys_goal+="\nNote you also need to figure out correct executable and command line options to execute the input."
        if [ "$help_msg" ]; then
            prompt_sys_goal+="\n$help_msg"
        else
            prompt_sys_goal+="\nExecutables avaialble:$exes"
        fi
        prompt_sys_format+="\nCommand: \`executable (NO path contained) with command line options that can trigger bug, use @@ to refer generated input file\`
A very brief explanation of how your command line options can enabling trigger of bug."
    else 
        prompt_sys_goal+="\nCommand used to execute input: $command (@@ refers to input file)"
    fi

    echo "$PROMPT_SYS_PROJ\n$prompt_sys_goal\n$prompt_sys_format\n\n"
}

# PROMPT_SHOWCOV="As your previous generated input failed to regressively test the commit, I will show you program output and coverage information below to help you generate new input:"
PROMPT_SHOWPREV="I tried to ask you to generate some input(s) but they FAILED to trigger intended bug, I will show previous generated input(s) with corresponding program output, retcode and coverage below for your reference:"
PROMPT_GENNEW="You should generate a new and better answer. If you think previous answer(s) are on the right track, you can improve based on them. If you think they are useless or misleading, feel free to generate a completely different diverse answer."

clone_repo
pushd $PROJ_NAME
success_total=()  # success count for each commit
finals=()  # final result for each commit
st_exp=$SECONDS
summary_file=SUMMARY_${full_suffix}.txt
print_configurations | tee -a $summary_file
summary_table="issue | commit |$(printf " result%d" $(seq 1 $MAX_ITER)) | final | time(seconds)"
echo -e "\nSummary table of $PROJ_NAME:\n$summary_table" | tee -a $summary_file
for i in "${!COMMITS[@]}"; do
    issue=${ISSUES[$i]:-$i}
    commit=${COMMITS[$i]}   
    id="#${issue}_${commit}"
    command=${COMMANDS[$i]}
    chat_log=chat_${SCENARIO}_${id}_${LLM}_${suffix}.log
    builddir_before=build_before_$commit
    builddir_after=build_after_$commit
    success_total[$i]=0
    finals[$i]="N"

    # Build two versions of the program before and after the commit, if not exist
    if [ ! -d $builddir_before ]; then
        git checkout --force $commit^ || { echo "Failed to checkout commit_before $commit^, exiting."; exit 1;}
        (set -x; pre_build $builddir_before)
        build_target $builddir_before > build_before_$commit.log 2>&1 || echo "Build failed with code $?"
        (set -x; post_build $builddir_before)
    fi
    if [ ! -d $builddir_after ]; then
        git checkout --force $commit || { echo "Failed to checkout commit_after $commit, exiting."; exit 1;}
        (set -x; pre_build $builddir_after)
        build_target $builddir_after > build_after_$commit.log 2>&1 || echo "Build failed with code $?"
        (set -x; post_build $builddir_after)
    fi

    exes=$(find $builddir_after/$DIR_REL -type f -executable -printf " %f")
    if [ "$EXE" ]; then
        cmd_help="$builddir_after/$DIR_REL/$EXE --help"
        help_msg=$(eval "$cmd_help" 2>&1)
        find $builddir_after -name "*.gcda" -delete
    fi
    changed_files=$(git diff --name-only $commit^ $commit | grep -E '\.(c|cpp|cc|h)$')
    cnt=0
    msg_prev=""
    msg_prev_inputs=""
    results_this=()  # result status each iter for this commit
    st_commit=$SECONDS
    while true; do  # loop for MAX_ITER time
        msg=$(construct_prompt "$commit" "$command" "$exes" "$help_msg")
        if [ $cnt -ne 0 ]; then
            # Execute the two versions of the program with the generated input
            # export GCOV_PREFIX=$builddir_before
            git checkout --force $commit^ || { echo "Failed to checkout commit $commit^, exiting."; exit 1; }
            cmd_before=$(get_cmd "$builddir_before/$DIR_REL/$command" "$input_file")
            echo "Executing command: $cmd_before" | tee -a $chat_log
            output_before=$(script -aeq -c "echo 'C' | $cmd_before")
            retcode_before=$?
            # # first, gen gcov with gcda files containing $PROJ_NAME
            # gcda_before=$(find $builddir_before -name "*${PROJ_NAME}*.gcda")
            # # gcda_before may contain multiple files seperated by newline, -o for each file
            # for gcda in $gcda_before; do
            #     (set -x; gcov -r -H -o $gcda $changed_files)
            # done
            # then, gen gcov with gcda files containing each changed file name
            for file in $changed_files; do
                filename=$(basename $file)
                # find gcda object file in $builddir_before by file name (with or without extension)
                gcda_before=$(find $builddir_before -name "${filename%.*}.gcda" -o -name "$filename.gcda")
                if [[ "$gcda_before" ]]; then
                    gcov_err=$(gcov -H -o $gcda_before $file 2>&1 >/dev/null)
                    if [[ "$gcov_err" =~ "Cannot open source file" ]]; then
                        (cd $builddir_before && gcov -H -o ${gcda_before#$builddir_before/} $file; mv $filename.gcov ../$filename.gcov.before_${id}.$cnt)
                    else
                        mv $filename.gcov $filename.gcov.before_${id}.$cnt
                    fi
                else
                    echo "No ${filename%.*}.gcda or $filename.gcda found for $file in $builddir_before."
                fi
            done
            (set -x; rm -f *.gcov; rm -f $builddir_before/*.gcov)

            # export GCOV_PREFIX=$builddir_after
            git checkout --force $commit || { echo "Failed to checkout commit $commit, exiting."; exit 1; }
            cmd_after=$(get_cmd "$builddir_after/$DIR_REL/$command" $input_file)
            echo "Executing command: $cmd_after" | tee -a $chat_log
            output_after=$(script -aeq -c "echo 'C' | $cmd_after")
            retcode_after=$?
            # gcda_after=$(find $builddir_after -name "*${PROJ_NAME}*.gcda")
            # for gcda in $gcda_after; do
            #     (set -x; gcov -r -H -o $gcda $changed_files)
            # done
            for file in $changed_files; do
                filename=$(basename $file)
                # find gcda object file in $builddir_after by file name (with or without extension)
                gcda_after=$(find $builddir_after -name "${filename%.*}.gcda" -o -name "$filename.gcda")
                if [[ "$gcda_after" ]]; then
                    gcov_err=$(gcov -H -o $gcda_after $file 2>&1 >/dev/null)
                    if [[ "$gcov_err" =~ "Cannot open source file" ]]; then
                        (cd $builddir_after && gcov -H -o ${gcda_after#$builddir_after/} $file; mv $filename.gcov ../$filename.gcov.after_${id}.$cnt)
                    else
                        mv $filename.gcov $filename.gcov.after_${id}.$cnt
                    fi
                else
                    echo "No ${filename%.*}.gcda or $filename.gcda found for $file in $builddir_after."
                fi
            done
            (set -x; rm -f *.gcov; rm -f $builddir_after/*.gcov)

            # Execution Analyzer
            echo "Output before commit $commit: $output_before, return code: $retcode_before" | tee -a $chat_log
            echo "Output after commit $commit: $output_after, return code: $retcode_after" | tee -a $chat_log
            bug_before=$(check_output_bug "$output_before")
            bug_after=$(check_output_bug "$output_after")
            msg_prev_fail="Previous try #$cnt failed to trigger intended bug:\n"
            if [[ "$bug_before" || "$bug_after" ]]; then  # bug triggered, different feedback based on scenario
                status="bug_$bug_before^$bug_after"
                finals[$i]="X"
                if [[ "$bug_before" && "$bug_after" ]]; then
                    echo "🐛Unintended Bug unrelated to commit $commit with $input_file! Interesting :)" | tee -a $chat_log
                    # msg_prev+="Previous try #$cnt found unintended bug unrelated to commit:\n"
                    msg_prev+=$msg_prev_fail
                elif [[ "$bug_before" ]]; then
                    echo "🐛Bug triggered before commit $commit with $input_file!" | tee -a $chat_log
                    # msg_prev+="Previous try #$cnt triggered bug before commit:\n"
                    if [ "$SCENARIO" = "FIX" ]; then
                        ((success_total[$i]+=1))
                        finals[$i]="B"
                        echo "Success for scenario of reproducing known bug fixed by commit!" | tee -a $chat_log
                    else
                        msg_prev+=$msg_prev_fail
                        # msg_prev+="(But you should focus on triggering bug **introduced** by commit, so bug should be after commit!)\n"
                    fi
                else
                    echo "🐛Bug triggered after commit $commit with $input_file!" | tee -a $chat_log
                    # msg_prev+="Previous try #$cnt triggered bug after commit:\n"
                    if [ "$SCENARIO" = "BIC" ]; then
                        ((success_total[$i]+=1))
                        finals[$i]="B"
                        echo "Success for scenario of detecting unknown bug introduced by commit!" | tee -a $chat_log
                    else
                        msg_prev+=$msg_prev_fail
                        # msg_prev+="(But you should focus on reproducing bug **fixed** by commit, so bug should be before commit!)\n"
                    fi
                fi
                # break
            elif check_output_invalid "$output_before" || check_output_invalid "$output_after"; then  # invalid output
                status="invalid"
                echo "Invalid output in commit $commit with $input_file. Failed!" | tee -a $chat_log
                msg_prev+="Previous try #$cnt seems to not execute correctly and have invalid output:\n"
            elif [ "$output_before" != "$output_after" ] || [ "$retcode_before" != "$retcode_after" ]; then  # behavior difference
                status="behave"
                [ "${finals[$i]}" != "B" ] && finals[$i]="D"
                echo "The programs B/A commit $commit behave differently with $input_file!\n" | tee -a $chat_log
                # msg_prev+="Previous try #$cnt caused program behavior difference related to commit but FAILED to trigger bug:\n"
                msg_prev+=$msg_prev_fail
                # break
            else  # behave same, check coverage overlap
                echo "The programs B/A $commit behave the same with $input_file." | tee -a $chat_log
                # semi-success if the input reached any of the changed lines
                cover_before=""
                cover_after=""
                for file in $changed_files; do
                    filename=$(basename $file)
                    gcov_before=$filename.gcov.before_${id}.$cnt
                    gcov_after=$filename.gcov.after_${id}.$cnt
                    if [ ! -f $gcov_before ] && [ ! -f $gcov_after ]; then
                        echo "No gcov report found for $file before/after commit $commit, skipping." | tee -a $chat_log
                        continue
                    else
                        echo "Checking covered lines in $gcov_before and $gcov_after." | tee -a $chat_log
                    fi
                    changed_lines=$(commit_affected_lines "$commit" "$file")
                    lines_before=$(echo "$changed_lines" | sed -n 's/^lines_before://p')
                    lines_after=$(echo "$changed_lines" | sed -n 's/^lines_after://p')
                    echo "commit $commit^ affected lines in $file: $lines_before" | tee -a $chat_log
                    echo "commit $commit affected lines in $file: $lines_after" | tee -a $chat_log
                    cover_lines_before=()
                    # read -p "Pause for debug. Press any key to continue..."
                    for line in ${lines_before//,/ }; do
                        # determine if line is coveraged in pre-commit gcov report
                        covered_lines=$(cat $gcov_before | grep -v '^\s*-' | grep -v '^\s*#####')
                        pat="^\s.*:\s*$line:.*$"  # before second colon in each line
                        if [[ $covered_lines =~ $pat ]]; then
                            cover_lines_before+=($line)
                            # echo "Line $line in $file is covered before commit $commit." | tee -a $chat_log
                        fi
                    done
                    if [ ${#cover_lines_before[@]} -gt 0 ]; then
                        cover_before+="$filename:${cover_lines_before[@]}\n"
                    fi
                    cover_lines_after=()
                    for line in ${lines_after//,/ }; do
                        # determine if line is coveraged in post-commit gcov report
                        covered_lines=$(cat $gcov_after | grep -v '^\s*-' | grep -v '^\s*#####')
                        pat="^\s.*:\s*$line:.*$"  # before second colon in each line
                        if [[ $covered_lines =~ $pat ]]; then
                            cover_lines_after+=($line)
                            # echo "Line $line in $file is covered after commit $commit." | tee -a $chat_log
                        fi
                    done
                    if [ ${#cover_lines_after[@]} -gt 0 ]; then
                        cover_after+="$filename:${cover_lines_after[@]}\n"
                    fi
                done
                if [[ "$cover_before" || "$cover_after" ]]; then
                    status="reach"
                    # set finals[$i] to R if it is not "B","D" already
                    [ "${finals[$i]}" != "B" ] && [ "$finals[$i]" != "D" ] && finals[$i]="R"
                    echo "$input_file reach changed lines B/A commit $commit!" | tee -a $chat_log
                    msg_cov_before="Covered changed lines before commit:\n${cover_before}"
                    msg_cov_after="Covered changed lines after commit:\n${cover_after}"
                    echo -e "$msg_cov_before" | tee -a $chat_log
                    echo -e "$msg_cov_after" | tee -a $chat_log
                    msg_prev+=$msg_prev_fail
                    # msg_prev+="Previous try #$cnt can reach code changed by commit but FAILED to trigger bug:\n"
                    # msg_prev+="$msg_cov_before\n$msg_cov_after\n"
                    # break
                else
                    status="fail"
                    echo "$input_file didn't reach any changed lines B/A commit $commit. Failed." | tee -a $chat_log
                    # msg_prev+="Previous try #$cnt FAILED to reach code changed by commit:\n"
                    msg_prev+=$msg_prev_fail
                fi
            fi  # status check done
            results_this[$cnt]=$status
            echo "Execution status for $commit in #$cnt: $status" | tee -a $chat_log
            if [[ "$status" != "invalid" && "$status" != "fail" ]]; then
                cp $input_file TRIGGER_${id}_${cnt}_${LLM}_${status}
            fi
            if [ $cnt -ge $MAX_ITER ]; then
                echo "Already tested $commit for $MAX_ITER tries, moving to next commit.\n" | tee -a $chat_log
                break
            fi
            # if finals[$i] is "B", count as success and also move to next commit
            if [ "${finals[$i]}" = "B" ]; then
                echo "Successfully trigger intended bug for commit $commit, moving to next commit.\n" | tee -a $chat_log
                break
            fi
            # incremental prompting
            msg_prev+="Program execution command:\n$command\n"
            msg_prev+="Input:\n$input\n"
            msg_prev_inputs+="Previous Input #$cnt:\n$input\n"
            # $output_before and $output_after may be too long, cut to 4096 characters before sending to LLM
            
            # for SCENARIO of FIX, output/retcode is before, otherwise after
            if [ "$SCENARIO" = "FIX" ]; then
                output=$output_before
                retcode=$retcode_before
                git checkout --force $commit^ || { echo "Failed to checkout commit $commit^, exiting."; exit 1; }
                covall=$(gcov_all $builddir_before)
            else
                output=$output_after
                retcode=$retcode_after
                git checkout --force $commit || { echo "Failed to checkout commit $commit, exiting."; exit 1; }
                covall=$(gcov_all $builddir_after)
            fi
            msg_prev+="Program output (cut to 4096 characters):\n${output:0:4096}\nReturn code: $retcode\n"
            msg_prev+="Program coverage:\n$covall\n\n"
            if [ "$NOFEEDBACK" ]; then
                msg+="I will show previous generated inputs to test the commit:\n$msg_prev_inputs\n$PROMPT_GENNEW\n"
            else
                msg+="$PROMPT_SHOWPREV\n\n$msg_prev\n$PROMPT_GENNEW\n"
            fi
        fi

        echo -e "$msg" > MSG_${id}_${cnt}_${LLM}.txt
        echo -e ">>>>>>>>👨🏻‍💻User msg #$cnt:\n$msg\n\n<<<<<<<<\n" >> $chat_log

        input_file="INPUT_${id}_$((cnt+1))_${LLM}"
        ans=$(echo "$msg" | timeout 300s ../$openai +model=$LLM +temperature=$LLM_TEMP)
        # ans=$(echo "$msg" | timeout 600s ../$openai +model=deepseek-ai/$LLM +temperature=$LLM_TEMP)
        input=$(parse_llm_input "$ans")
        [ -z "$input" ] && echo "Parsed empty input from LLM response, skipping." | tee -a $chat_log && continue
        echo "AI response: $ans"
        echo "Input parsed: $input"
        echo -e "$ans" > ANS_${id}_${cnt}_${LLM}.txt
        echo -e ">>>>>>>>🤖$LLM ans #$cnt:\n$ans\n<<<<<<<<\n\n" >> $chat_log
        echo -e "$input" > $input_file
        if [ "$GENCMD" ]; then
            command=$(parse_llm_cmd "$ans")
            [ -z "$command" ] && echo "Parsed empty command from LLM response, skipping." | tee -a $chat_log && continue
            abort_if_cmd_danger $cmd
            echo "Command parsed: $command"
            echo -e "$command" > CMD_${id}_${cnt}_${LLM}.txt
        fi
        cnt=$((cnt+1))
        
        find $builddir_before -name "*.gcda" -delete
        find $builddir_after -name "*.gcda" -delete
    done
    duration=$(($SECONDS-$st_commit))

    # print summary as table, each line shows commit, result for each iteration, and sum
    # commit $commit: ${results_this[@] $success_total
    summary_this="$issue | $commit | ${results_this[@]} | ${finals[$i]} | ${duration}"
    echo "$summary_this" | tee -a $chat_log $summary_file
    summary_table+="$summary_this\n"
done
duration_exp=$(($SECONDS-$st_exp))
echo -e "Total time used: $duration_exp seconds\n" | tee -a $summary_file
find . -name "*.gcda" -delete
popd

exp_folder=exp_${full_suffix}
collect_exp $PROJ_NAME $exp_folder
cp $exp_folder/$summary_file .

if [ "$RUNFUZZ" ]; then
    nohup ./fuzz.sh $conf $exp_folder $RUNFUZZ > fuzz_${full_suffix}.log 2>&1 &
fi
