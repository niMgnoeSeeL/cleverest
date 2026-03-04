#!/bin/bash

# usage: b.sh <path-to-project-config> <commit>

SCENARIO=${SCENARIO:-BIC}
conf=${1-"mujs.env"}
source $conf

pushd $PROJ_NAME

commit=$2
# if $commit is not set, build all commits
if [ -z "$commit" ]; then
    for i in "${!COMMITS[@]}"; do
        commit=${COMMITS[$i]}   
        builddir=buildwaflgo_$commit
        if [ ! -d $builddir ]; then
            git checkout --force $commit || { echo "Failed to checkout commit $commit, exiting."; exit 1;}
            pre_build $builddir
            buildwaflgo_target $builddir 2>&1 | tee build_$commit.log || echo "Build failed with code $?"
            post_buildwaflgo $builddir
        fi
    done
    exit 0
fi

builddir=buildwaflgo_$commit
if [ ! -d $builddir ]; then
    git checkout --force $commit || { echo "Failed to checkout commit $commit, exiting."; exit 1;}
    pre_build $builddir
    buildwaflgo_target $builddir 2>&1 | tee build_$commit.log || echo "Build failed with code $?"
    post_buildwaflgo $builddir
fi
popd
