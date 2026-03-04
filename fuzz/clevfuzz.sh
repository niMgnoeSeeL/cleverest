#!/bin/bash

# launch AFL instances with LLM-generated seeds from given Cleverest experiment
# precondition: $exp_dir contains INPUT_* files, AFL-instrumented programs in buildafl_*
# postcondition: create tmux sessions for fuzzing each commit, results in fuzzout_* directories

# if argc <= 2, print usage
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <path-to-project-config> <exp_dir> [hours]"
    exit 1
fi

# Determine the directory of the current script
SCRIPT_DIR=$(dirname "$(realpath "$0")")

conf=$1
exp_dir=$2
hours=${3-"24"}
exp_base=$(basename "$exp_dir")
# full_suffix = remove "exp_" from $exp_base
full_suffix=${exp_base#"exp_"}

# full_suffix construction: ${PROJ_NAME}_${SCENARIO}_GIT${GIT_INFO}_ITER${MAX_ITER}_${LLM}_TEMP${LLM_TEMP}
# parse $SCENARIO from $full_suffix
SCENARIO=$(echo $full_suffix | cut -d'_' -f2)
LLM=$(echo $full_suffix | cut -d'_' -f5)

# if GENCMD in $full_suffix, set GENCMD
if [[ $full_suffix == *"GENCMD"* ]]; then
    GENCMD="1"
fi

source utils.sh
source $conf

unset ASAN_OPTIONS
pushd $exp_dir
for i in "${!COMMITS[@]}"; do
    issue=${ISSUES[$i]}
    commit=${COMMITS[$i]}   
    id="#${issue}_${commit}"
    [ "$PROJ_NAME" = "libxml2" ] && id="${issue}_${commit}"  # filename containing # affect libxml2 #550 bug-triggering
    buildafl_before=buildafl_before_$commit
    buildafl_after=buildafl_after_$commit
    indir=fuzzin_${id}
    outdir_before=fuzzout_${id}_before
    outdir_after=fuzzout_${id}_after
    command=${COMMANDS[$i]}

    if [ "$GENCMD" ]; then
        # iter cnt from MAX_ITER-1 to 0, cmdfile=CMD_${commit}_${cnt}_${LLM}.txt
        # read command from cmdfile if exists and not empty
        unset command
        for cnt in $(seq $(($MAX_ITER-1)) -1 0); do
            cmdfile=CMD_${id}_${cnt}_${LLM}.txt
            if [ -s $cmdfile ]; then
                command=$(cat $cmdfile)
                echo "fuzz $commit with command from $cmdfile: $command"
                break
            fi
        done
        # abort if no command found
        if [ -z "$command" ]; then
            echo "No generated command found for fuzzing $commit, abort."
            exit 1
        fi
    fi 

    # if TRIGGER_${id}_* not exist, skip, no fuzz
    if ! ls TRIGGER_${id}_* 1> /dev/null 2>&1; then
        echo "No TRIGGER_${id}_* files found, skip fuzzing $commit"
        continue
    fi
    mkdir -p $indir
    cp TRIGGER_${id}_* $indir

    proj_path=$(realpath "$SCRIPT_DIR/../$PROJ_NAME")
    cmd_before="$proj_path/$buildafl_before/$DIR_REL/$command"
    cmd_after="$proj_path/$buildafl_after/$DIR_REL/$command"
    fuzzcmd_before="afl-fuzz -i $indir -o $outdir_before -- $cmd_before"
    fuzzcmd_after="afl-fuzz -i $indir -o $outdir_after -- $cmd_after"
    
    session_before="fuzz${hours}h_${id}_before_${full_suffix}"
    session_after="fuzz${hours}h_${id}_after_${full_suffix}"
    # replace . with _ in session name as tmux does not allow .
    session_before=${session_before//./_}
    session_after=${session_after//./_}
    
    set -x
    # fuzz before commit only for FIX
    if [ "$SCENARIO" = "FIX" ]; then
        tmux new-session -d -s $session_before
        tmux send-keys -t $session_before "timeout ${hours}h $fuzzcmd_before" Enter
    fi
    # fuzz after commit for BIC
    if [ "$SCENARIO" = "BIC" ]; then
        tmux new-session -d -s $session_after
        tmux send-keys -t $session_after "timeout ${hours}h $fuzzcmd_after" Enter
    fi
    set +x
done    
popd
