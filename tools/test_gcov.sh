#!/bin/bash

# test if our approach can find gcda file and generate gcov as expected

set -xe

SCENARIO=${SCENARIO:-BIC}
conf=$1
source $conf
source utils.sh

truth_dir="truthdata/$PROJ_NAME"
# commit is last element in array COMMITS
commit=${COMMITS[-1]}
issue_id=${ISSUES[-1]}
command=${COMMANDS[-1]}
cnt=0

pushd $PROJ_NAME
changed_files=$(git diff --name-only $commit^ $commit | grep -E '\.(c|cc|cpp)$')
echo "commit $commit changed_files: $changed_files"
# pick file = first of changed_files
file=$(echo $changed_files | cut -d' ' -f1)
filename=$(basename $file)
echo "Checking file: $file, filename: $filename"

# Execute program to generate gcda file
if [[ "$SCENARIO" == "FIX" ]]; then
    builddir="build_after_$commit"
    git checkout $commit
else
    builddir="build_before_$commit"
    git checkout $commit^
fi
input_file=$(find ../$truth_dir -name "*$issue_id*" | head -1)
cmd=$(get_cmd "$builddir/$DIR_REL/$command" $input_file)
echo "Executing $cmd"
output=$(script -aeq -c "echo 'C' | $cmd" || true)
gcda_obj=$(find $builddir -name "${filename%.*}.gcda" -o -name "$filename.gcda")

if [[ "$SCENARIO" == "FIX" ]]; then
    gcov_file=$filename.gcov.after_$commit.$cnt
else
    gcov_file=$filename.gcov.before_$commit.$cnt
fi
# Check if gcda file can be found, generate gcov
if [[ "$gcda_obj" ]]; then
    echo "Found $gcda_obj for $file in $builddir, generate gcov"
    gcov_err=$(gcov -H -o $gcda_obj $file 2>&1 >/dev/null)
    # if "Cannot open source file", run gcov in $builddir
    if [[ "$gcov_err" =~ "Cannot open source file" ]]; then
      (cd $builddir && gcov -H -o ${gcda_obj#$builddir/} $file; mv $filename.gcov ../$gcov_file)
    else
        mv $filename.gcov $gcov_file
    fi
else
    echo "ERROR: No ${filename%.*}.gcda or $filename.gcda found for $file in $builddir."
    exit 1
fi

# Checking gcov generated
if [ ! -f $gcov_file ]; then
    echo "ERROR: $gcov_file not found"
    exit 1
fi

echo "gcov $gcov_file generated!"
wc -l $gcov_file