#!/bin/bash

# usage: checkafl.sh <path-to-project-config>
# precondition: AFL++ fuzzing result in exp_${PROJ_NAME}_* dirs, may have repeated experiments
# process: read config file to get envs and commits, locate exp_${conf_suffix}* dirs, find fuzzing results for each commit, and check if there are new crashes found
# output: for each commit, get count of experiments that found crashes, and avg time used to find the first crash

SCRIPT_DIR=$(dirname "$(realpath "$0")")

conf=$1
# suffix=${2-"1"} # just 1-5 repitition
outdir_base=${2-"$SCRIPT_DIR/out"}
SCENARIO=${SCENARIO:-BIC}

source utils.sh
source $conf

# loop over commits in ${COMMITS[@]}
# for each commit, check if there are crashes found in each exp_dir
# print commit, count of exp_dirs containing crashes, avg time to find first crash, paths for each exp_dir containing crash, and first crash time for each exp_dir
# output in format: commit | count of exp containing crash | avg_time | paths for each exp containing crash | first_crash_time for each exp
# tbl="commit | count of exp containing crash | avg_time to find first crash | first_crashes in all exps"
tbl="issue | commit | idx | status | final | first crash | time to find first crash"
tbl_file="waflgo_${PROJ_NAME}_${SCENARIO}.csv"
for i in "${!COMMITS[@]}"; do
    issue=${ISSUES[$i]:-$i}
    commit=${COMMITS[$i]}   
    id="#${issue}_${commit}"
    command=${COMMANDS[$i]}
    echo "Checking commit $id"
    # NOTE: use buildafl as we do not measure reachability for fuzzing
    builddir_before=buildafl_before_$commit
    builddir_after=buildafl_after_$commit

    cnt_success=0
    cnt_exps=0
    time_sum=0
    fuzzout_dir_pat="waflgo_${PROJ_NAME}_${commit}_*"
    fuzzout_dirs=$(find $outdir_base -maxdepth 2 -type d -name "$fuzzout_dir_pat" | sort -V)
    # if not found, use "waflgo_${PROJ_NAME}_${issue}_${commit}_*"
    [[ -z $fuzzout_dirs ]] && fuzzout_dir_pat="waflgo_${PROJ_NAME}_${issue}_${commit}_*"
    fuzzout_dirs=$(find $outdir_base -maxdepth 2 -type d -name "$fuzzout_dir_pat" | sort -V)
    # one line to make sure fuzzout_dir exists, otherwise skip
    [[ -z $fuzzout_dirs ]] && { echo "No $fuzzout_dir_pat found in $outdir_base"; continue; }
    for fuzzout_dir in $fuzzout_dirs; do
        status=none
        finals[$i]="N"
        first_file=""
        time_this=""
        # iter and enter all fuzzout_{commit} dirs
        j=${fuzzout_dir##*_}
        ((cnt_exps++))
        echo "Checking $fuzzout_dir"
        # iter over all files in default/crashes, if empty, use queue
        crashes=$(find $fuzzout_dir/crashes* -maxdepth 1 -type f -name "id*" | sort)
        if [ -z "$crashes" ]; then
            echo "No crashes found in $fuzzout_dir, check queues then."
            queues=$(find $fuzzout_dir/queue* -maxdepth 1 -type f -name "id:*" | sort)
            crashes=$queues
            echo "$(echo -e "$crashes" | wc -l) testcases found in queues"
        else
            echo "Found $(echo -e "$crashes" | wc -l) crashes in $fuzzout_dir"
        fi
        for input_file in $crashes; do
            fileid=$(echo $input_file | grep -oP "id:\K[0-9]+")
            status=none
            cmd_before=$(get_cmd "$PROJ_NAME/$builddir_before/$DIR_REL/$command" "$input_file")
            cmd_after=$(get_cmd "$PROJ_NAME/$builddir_after/$DIR_REL/$command" "$input_file")
            
            echo "Checking $input_file"
            # echo "Running $cmd_before"
            # echo "Running $cmd_after"

            export ASAN_OPTIONS=detect_leaks=0
            output_before=$(script -aeq -c "echo 'C' | $cmd_before")
            retcode_before=$?
            output_after=$(script -aeq -c "echo 'C' | $cmd_after")
            retcode_after=$?
            bug_before=$(check_output_bug "$output_before")
            bug_after=$(check_output_bug "$output_after")
            

            if [[ "$bug_before" || "$bug_after" ]]; then  # bug triggered
                status="bug_$bug_before^$bug_after"
                [ "${finals[$i]}" = "N" ] && finals[$i]="X" && first_file=$input_file
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
        tbl+="\n$issue | $commit | $j | $status | ${finals[$i]} | $first_file | $time_this"
        echo -e "$tbl" >$tbl_file
    done
done
echo -e "$tbl"