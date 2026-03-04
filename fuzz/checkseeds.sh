#!/bin/bash

# check seeds used for baseline fuzzing (WAFGo) can already trigger bug, behavior difference, or code reach
# usage: checkseeds.sh <path-to-project-config>

conf=${1-"php.env"}
source $conf
source utils.sh
seeds_dir=${2-"$SEEDS_DIR"}

# Default configurations
PROJ_NAME=${PROJ_NAME%.env}
PROJ_NAME=${PROJ_NAME:-"php-src"}
SCENARIO=${SCENARIO:-BIC}
GIT_INFO=${GIT_INFO:-FULL}
MAX_ITER=${MAX_ITER:-5}
LLM=${LLM:-"gpt-4o-2024-08-06"}
LLM_TEMP=${LLM_TEMP:-0.5}
NOFEEDBACK=${NOFEEDBACK:-""}
GENCMD=${GENCMD:-""}
RUNFUZZ=${RUNFUZZ:-""}

# loop over commits in ${COMMITS[@]}
# for each commit, execute all seeds and check bug-triggering, behavior difference, and code reach

# output in format: issue | commit | result | first file
tbl="issue | commit | # of files | # of (B,D,R,X,N) | final | first file | bug_types"
# suffix=$(echo "$seeds_dir" | tr '/' '_')
suffix=$PROJ_NAME
tbl_file=seedscheck_${suffix}_${SCENARIO}.csv
logfile=seedscheck_${suffix}_${SCENARIO}.log
echo -e "$tbl" > $tbl_file
finals=()  # final result for each commit
for i in "${!COMMITS[@]}"; do
    issue=${ISSUES[$i]}
    commit=${COMMITS[$i]}   
    command=${COMMANDS[$i]}
    # # skip if $commit is not 832e069
    # [ "$commit" = "832e069" ] || continue
    echo "Checking commit $commit"
    builddir_before=build_before_$commit
    builddir_after=build_after_$commit
    
    files=$(find $seeds_dir -maxdepth 2 -type f | sort)
    # # keep only *.fuzz files
    # files=$(echo "$files" | grep -P "\.fuzz$")
    # # keep only file with $commit in name
    # files=$(echo "$files" | grep -P "$commit")
    file_tot=$(echo "$files" | wc -l)
    echo "Found $file_tot files in $seeds_dir"
    cnt_B=0
    cnt_D=0
    cnt_R=0
    cnt_X=0
    cnt_N=0
    cnt_tot=$(echo "$files" | wc -l)
    time_sum=0
    first_file=""
    finals[$i]="N"
    declare -A bug_types=()
    fileid=0
    for input_file in $files; do
        # fileid=$(echo $input_file | grep -oP "id:\K[0-9]+")
        ((fileid++))
        status=none
        # DEBUG: only run every 1000 file to quickly check output
        # [ $((10#$fileid % 1000)) -eq 0 ] || continue
        echo "Checking #$fileid/$file_tot file $input_file"
        cmd_before=$(get_cmd "$PROJ_NAME/$builddir_before/$DIR_REL/$command" "$input_file")
        cmd_after=$(get_cmd "$PROJ_NAME/$builddir_after/$DIR_REL/$command" "$input_file")
        
        # echo "Running $cmd_before"
        # echo "Running $cmd_after"
        # break

        export ASAN_OPTIONS=detect_leaks=0
        output_before=$(script -aeq -c "echo 'C' | $cmd_before")
        retcode_before=$?
        output_after=$(script -aeq -c "echo 'C' | $cmd_after")
        retcode_after=$?

        # echo "output before: $output_before"
        # echo "output after: $output_after"

        bug_before=$(check_output_bug "$output_before")
        bug_after=$(check_output_bug "$output_after")

        if [[ "$bug_before" || "$bug_after" ]]; then  # bug triggered
            status="bug_$bug_before^$bug_after"
            ((bug_types["$status"]++))
            [ "${finals[$i]}" = "N" ] && finals[$i]="X" && first_file=$input_file
            if [[ "$bug_before" && "$bug_after" ]]; then
                echo "🐛Unintended $status unrelated to commit $commit with $input_file! Interesting :)" | tee -a $logfile
                cnt_X=$((cnt_X+1))
            elif [[ "$bug_before" && "$SCENARIO" = "FIX" ]]; then
                echo "🐞Intended $status triggered before commit $commit with $input_file!" | tee -a $logfile
                [ "${finals[$i]}" != "B" ] && finals[$i]="B" && first_file=$input_file
                cnt_B=$((cnt_B+1))
                break
            elif [[ "$bug_after" && "$SCENARIO" = "BIC" ]]; then
                echo "🐞Intended $status triggered after commit $commit with $input_file!" | tee -a $logfile
                [ "${finals[$i]}" != "B" ] && finals[$i]="B" && first_file=$input_file
                cnt_B=$((cnt_B+1))
                break
            else
                echo "🐛Wrong $status related to commit $commit with $input_file!" | tee -a $logfile
                cnt_X=$((cnt_X+1))
            fi
        elif [ "$output_before" != "$output_after" ] || [ "$retcode_before" != "$retcode_after" ]; then  # behavior difference
            status="behave"
            cnt_D=$((cnt_D+1))
            [ "${finals[$i]}" != "B" ] && [ "${finals[$i]}" != "D" ] && finals[$i]="D" && first_file=$input_file
            echo "The programs B/A commit $commit behave differently with $input_file!" | tee -a $logfile
            echo "output before: $output_before" | head
            echo "output after: $output_after" | head
            echo "retcode before: $retcode_before"
            echo "retcode after: $retcode_after"
        else
            # check code reach only when final is not B/D/R, so we only check once for the first time
            if [ "${finals[$i]}" != "B" ] && [ "${finals[$i]}" != "D" ] && [ "${finals[$i]}" != "R" ]; then
                pushd $PROJ_NAME
                changed_files=$(git diff --name-only $commit^ $commit | grep -E '\.(c|cpp|cc|h)$')
                git checkout $commit^
                gen_cov $builddir_before "$changed_files" $fileid
                git checkout $commit
                gen_cov $builddir_after "$changed_files" $fileid
                check_cov $commit "$changed_files" $fileid
                # if check_cov returns 0, means code reached
                if [ $? -eq 0 ]; then
                    status="reach"
                    cnt_R=$((cnt_R+1))
                    [ "${finals[$i]}" != "B" ] && [ "${finals[$i]}" != "D" ] && [ "${finals[$i]}" != "R" ] && finals[$i]="R" && first_file=$input_file
                    echo "The commit $commit have code reached with $input_file!\n" | tee -a $logfile
                else
                    cnt_N=$((cnt_N+1))
                fi
                popd
            fi
        fi
        
        if [ "$status" != "none" ]; then
            echo "status of $input_file: $status"
        fi
    done
    bug_types_str=""
    for key in "${!bug_types[@]}"; do
        bug_types_str+="$key:${bug_types[$key]} "
    done
    tbl+="\n$issue | $commit | $cnt_tot | ($cnt_B,$cnt_D,$cnt_R,$cnt_X,$cnt_N) | ${finals[$i]} | $first_file | $bug_types_str"
    echo -e "$tbl" | tee $tbl_file
    find $PROJ_NAME/$builddir_before -name '*.gcda' -delete
    find $PROJ_NAME/$builddir_after -name '*.gcda' -delete
done
echo -e "$tbl"
