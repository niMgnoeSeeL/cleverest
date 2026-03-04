#!/bin/bash

# usage: cpdocker.sh <path-to-project-config> <commit>
# copy fuzzing results from ${dockername}:/home/out to ${dockername}/

SCRIPT_DIR=$(dirname "$(realpath "$0")")
SCENARIO=${SCENARIO:-BIC}
conf=${1-"jerryscript.env"}
outroot=${2-"$SCRIPT_DIR/out"}
mkdir -p $outroot
source $conf

# merge COMMITS_BIC and COMMITS_FIX into one array commits
for i in "${!COMMITS[@]}"; do
    commit=${COMMITS[$i]}   
    issue=${ISSUES[$i]}   
    for j in {1..10}; do
        container_name="runwaflgo_${PROJ_NAME}_${commit}_$j"
        foldername="waflgo_${PROJ_NAME}_${commit}_$j"
        docker cp $container_name:/home/out $outroot/$foldername
        # run_waflgo should consider different issues with same BIC commit like jq
        container_name="runwaflgo_${PROJ_NAME}_${issue}_${commit}_$j"
        foldername="waflgo_${PROJ_NAME}_${issue}_${commit}_$j"
        docker cp $container_name:/home/out $outroot/$foldername
    done
done
