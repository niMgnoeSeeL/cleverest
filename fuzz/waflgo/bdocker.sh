#!/bin/bash

# build waflgo docker image for project
# usage: bdocker.sh <path-to-project-config> <commit>
set -e

SCENARIO=${SCENARIO:-BIC}
conf=${1-"jerryscript.env"}
source $conf

mkdir -p logs/
# if $commit is not set, build all commits
if [ -n "$2" ]; then
    commits=("$2")
else
    commits=("${COMMITS[@]}")
fi

for commit in "${commits[@]}"; do
    docker build -t waflgo_$PROJ_NAME:$commit -f waflgo_$PROJ_NAME.Dockerfile --build-arg commit=$commit . --progress=plain 2>&1 | tee logs/bwaflgo_${PROJ_NAME}_$commit.log
    ret=${PIPESTATUS[0]}
    [ $ret -ne 0 ] && mv logs/bwaflgo_${PROJ_NAME}_$commit.log logs/bwaflgo_${PROJ_NAME}_$commit.err$ret
done