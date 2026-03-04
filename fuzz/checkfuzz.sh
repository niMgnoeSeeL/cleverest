#!/bin/bash

# usage: checkfuzz.sh <path-to-project-config>
# precondition: AFL++ fuzzing result in exp_*/fuzzout_* dirs, may have multiple experiments
# process: read config file to get envs and commits, locate exp_${conf_suffix}* dirs, find fuzzing results for each commit, and check if there are new crashes found
# output: for each commit, get count of experiments that found crashes, and avg time used to find the first crash

# Determine the directory of the current script
SCRIPT_DIR=$(dirname "$(realpath "$0")")

conf=${1-"mujs.env"}
exproot=${2-"."}
source $conf
source utils.sh

# Default configurations
PROJ_NAME=${PROJ_NAME%.env}
PROJ_NAME=${PROJ_NAME:-"mujs"}
SCENARIO=${SCENARIO:-BIC}
GIT_INFO=${GIT_INFO:-FULL}
MAX_ITER=${MAX_ITER:-5}
LLM=${LLM:-"gpt-4o-2024-08-06"}
LLM_TEMP=${LLM_TEMP:-0.5}
NOFEEDBACK=${NOFEEDBACK:-""}
GENCMD=${GENCMD:-""}
RUNFUZZ=${RUNFUZZ:-""}

conf_suffix=${PROJ_NAME}_${SCENARIO}_GIT${GIT_INFO}_ITER${MAX_ITER}_${LLM}_TEMP${LLM_TEMP}
conf_suffix+=$( [ -n "$GENCMD" ] && echo "_GENCMD" )$( [ -n "$NOFEEDBACK" ] && echo "_NOFEEDBACK")$( [ -n "$RUNFUZZ" ] && echo "_RUNFUZZ")


# exp_dirs=$(find * -maxdepth 1 -type d -name "exp_${conf_suffix}_*" | sort)
exp_dirs=$(find $exproot -maxdepth 3 -type d -regex ".*/exp_${conf_suffix}_[0-9].*" | sort)  # strict match
echo "$exp_dirs"

# print number of exp_dirs found and abort if zero
if [ -z "$exp_dirs" ]; then
    echo "No exp dirs found for $conf_suffix"
    exit 1
else
    echo "Found $(echo $exp_dirs | wc -w) exp dirs for $conf_suffix"
fi

# loop over commits in ${COMMITS[@]}
# for each commit, check if there are crashes found in each exp_dir
# print commit, count of exp_dirs containing crashes, avg time to find first crash, paths for each exp_dir containing crash, and first crash time for each exp_dir
# output in format: commit | count of exp containing crash | avg_time | paths for each exp containing crash | first_file_time for each exp
# tbl="commit | count of exp containing crash | avg_time to find first crash | first_filees in all exps"
tbl="issue | commit | idx | status | final | first crash | time to find first crash"
tbl_file="postfuzz_${PROJ_NAME}_${SCENARIO}.csv"
for i in "${!COMMITS[@]}"; do
    issue=${ISSUES[$i]:-$i}
    commit=${COMMITS[$i]}   
    id="#${issue}_${commit}"
    [ "$PROJ_NAME" = "libxml2" ] && id="${issue}_${commit}"  # filename containing # affect libxml2 #550 bug-triggering
    command=${COMMANDS[$i]}
    echo "Checking commit $commit"
    builddir_before=buildafl_before_$commit
    builddir_after=buildafl_after_$commit

    cnt_success=0
    cnt_exps=0
    time_sum=0
    for exp_dir in $exp_dirs; do
        status=none
        finals[$i]="N"
        first_file=""
        time_this=""
        # iter and enter all fuzzout_{commit} dirs
        fuzzout_dir_before=fuzzout_${id}_before
        fuzzout_dir_after=fuzzout_${id}_after
        if [ "$SCENARIO" = "FIX" ]; then
            fuzzout_dir=$exp_dir/$fuzzout_dir_before
        else
            fuzzout_dir=$exp_dir/$fuzzout_dir_after
        fi
        # one line to make sure fuzzout_dir exists, otherwise skip
        [ -d $fuzzout_dir ] || { echo "No $fuzzout_dir found in $exp_dir"; continue; }
        # j is removing $conf_suffix from $exp_dir
        exp_base=$(basename $exp_dir)
        j=${exp_base#"exp_${conf_suffix}_"}
        ((cnt_exps++))
        echo "Checking $fuzzout_dir"
        # iter over all files in default/crashes, if empty, use queue
        crashes=$(find $fuzzout_dir/default/crashes* -maxdepth 1 -type f -name "id*" | sort)
        queues=$(find $fuzzout_dir/default/queue -maxdepth 1 -type f -name "id:*" | sort)
        if [ -z "$crashes" ]; then
            # echo "No crashes found in $exp_dir/$fuzzout_dir."
            echo "No crashes found in $exp_dir/$fuzzout_dir, will check queues then"
            crashes=$queues
            echo "$(echo -e "$crashes" | wc -l) testcases found in queues"
        fi
        for input_file in $crashes; do
            fileid=$(echo $input_file | grep -oP "id:\K[0-9]+")
            status=none
            cmd_before=$(get_cmd "./$PROJ_NAME/$builddir_before/$DIR_REL/$command" "$input_file")
            cmd_after=$(get_cmd "./$PROJ_NAME/$builddir_after/$DIR_REL/$command" "$input_file")
            
            # echo "Checking $input_file"
            # echo "Running $cmd_before"
            # echo "Running $cmd_after"

            export ASAN_OPTIONS=detect_leaks=0
            output_before=$(script -aeq -c "echo 'C' | $cmd_before")
            retcode_before=$?
            output_after=$(script -aeq -c "echo 'C' | $cmd_after")
            retcode_after=$?
            bug_before=$(check_output_bug "$output_before")
            bug_after=$(check_output_bug "$output_after")
            

            # if [[ "$bug_before" && "$bug_after" ]]; then
            #     echo "🐛Unintended Bug unrelated to commit $commit with $input_file! Interesting :)" | tee -a $chat_log
            # else
            #     echo "🐞Intended Bug related to commit $commit with $input_file! Good :)" | tee -a $chat_log
            #     cnt_success=$((cnt_success+1))
            #     seconds=$(afl_testcase_ms "$input_file")
            #     sum_seconds=$(echo "$sum_seconds + $seconds" | bc)
            #     first_filees+=" $exp_dir/$input_file"
            #     break
            # fi
            if [[ "$bug_before" || "$bug_after" ]]; then  # bug triggered
                status="bug_$bug_before^$bug_after"
                [ "${finals[$i]}" = "N" ] && finals[$i]="X" && first_file=$input_file && time_this=$(afl_testcase_ms "$first_file")
                if [[ "$bug_before" && "$bug_after" && "$bug_before" == "$bug_after" ]]; then
                    echo "🐛Unintended Bug unrelated to commit $commit with $input_file! Interesting :)" | tee -a $chat_log
                elif [[ "$bug_before" && "$SCENARIO" = "FIX" ]]; then
                    echo "🐞Intended $status triggered before commit $commit with $input_file!" | tee -a $chat_log
                    [ "${finals[$i]}" != "B" ] && finals[$i]="B" && first_file=$input_file && time_this=$(afl_testcase_ms "$first_file")
                    break
                elif [[ "$bug_after" && "$SCENARIO" = "BIC" ]]; then
                    echo "🐞Intended $status triggered after commit $commit with $input_file!" | tee -a $chat_log
                    [ "${finals[$i]}" != "B" ] && finals[$i]="B" && first_file=$input_file && time_this=$(afl_testcase_ms "$first_file")
                    break
                fi
            elif [ "$output_before" != "$output_after" ] || [ "$retcode_before" != "$retcode_after" ]; then  # behavior difference
                status="behave"
                [ "${finals[$i]}" != "B" ] && [ "${finals[$i]}" != "D" ] && finals[$i]="D" && first_file=$input_file
                echo "The programs B/A commit $commit behave differently with $input_file!\n" | tee -a $chat_log
                echo "output before: $output_before"
                echo "output after: $output_after"
                echo "retcode before: $retcode_before"
                echo "retcode after: $retcode_after"
            fi
        done
        # if cnt_success not zero, calculate avg time, otherwise assign as "-"
        # [ $cnt_success -gt 0 ] && avg_time=$(echo "scale=2; $sum_seconds / $cnt_success" | bc) || avg_time="-"
        # tbl+="\n$commit | $cnt_success/$cnt_exps | $avg_time | $first_filees"
        tbl+="\n$issue | $commit | $j | $status | ${finals[$i]} | $(basename $first_file) | $time_this"
        echo -e "$tbl" >$tbl_file
    done
done
echo -e "$tbl"