#!/bin/bash

# usage: rdocker.sh <path-to-project-config> <commit>

SCENARIO=${SCENARIO:-BIC}
conf=${1-"jerryscript.env"}
source $conf
source utils.sh

# if $commit is not set, build all commits
if [ -z "$2" ]; then
    for i in "${!COMMITS[@]}"; do
        commit=${COMMITS[$i]}   
        for j in {1..10}; do
            docker run --name runwaflgo_${PROJ_NAME}_${commit}_$j -dit waflgo_$PROJ_NAME:$commit
            # docker stop runwaflgo_${PROJ_NAME}_${commit}_$j
            # docker rm runwaflgo_${PROJ_NAME}_${commit}_$j
            # builddir=buildwaflgo_$commit
            
            # cmd_resume="tmux send-keys -t fuzz_$commit 'timeout 8h /home/WAFLGo/afl-fuzz -T waflgo-mujs -t 1000+ -m none -z exp -c 45m -q 1 -i - -o /home/out -- /home/mujs/$builddir/$DIR_REL/$EXE.ci @@' Enter && bash"
            # echo "$cmd_resume"
            # docker start runwaflgo_${PROJ_NAME}_${commit}_$j 
            # docker exec -dit runwaflgo_${PROJ_NAME}_${commit}_$j bash -c "$cmd_resume"
        done
    done
    exit 0
fi

commit=$2
container_name="runwaflgo_${PROJ_NAME}_${commit}"
docker run --name $container_name -v $PWD:/clever -dit waflgo_$PROJ_NAME:$commit /bin/bash
for j in {1..5}; do
    tmux_name="fuzz_${commit}_$j"
    fuzzcmd="timeout 24h bash -c 'source ../$PROJ_NAME.env && run_waflgo buildwaflgo_$commit $SEEDS_DIR $j'"
    cmd="tmux new-session -d -s $tmux_name && tmux send-keys -t $tmux_name \"$fuzzcmd\" Enter && bash"
    docker exec -dit $container_name bash -c "$cmd"
    echo "fuzzcmd: $fuzzcmd"
    echo "cmd: $cmd"
done
