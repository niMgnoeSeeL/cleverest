#!/bin/bash

# launch AFL instances with LLM-generated seeds from given Cleverest experiment
# precondition: $exp_dir contains INPUT_* files, AFL-instrumented programs in buildafl_*
# postcondition: create tmux sessions for fuzzing each commit, results in fuzzout_* directories

# if argc <= 2, print usage
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <path-to-project-config> <exp_dir> [hours]"
    exit 1
fi

conf=$1
exp_dir=$2
hours=${3-"24"}
# full_suffix = remove "exp_" from $exp_dir
full_suffix=${exp_dir#"exp_"}

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

    cmd_before="../$PROJ_NAME/$buildafl_before/$DIR_REL/$command"
    cmd_after="../$PROJ_NAME/$buildafl_after/$DIR_REL/$command"
    fuzzcmd_before="afl-fuzz -i $indir -o $outdir_before -- $cmd_before"
    fuzzcmd_after="afl-fuzz -i $indir -o $outdir_after -- $cmd_after"

    mkdir -p $indir
    cp INPUT_${id}_* $indir
    
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

    # fuzz after commit for both BIC/FIX, hope to find new bug after FIX
    tmux new-session -d -s $session_after
    tmux send-keys -t $session_after "timeout ${hours}h $fuzzcmd_after" Enter
    set +x
done    
popd