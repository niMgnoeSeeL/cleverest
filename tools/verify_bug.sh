#!/bin/bash

# verify collected bugs can be reproduced with ground truth poc files
# for FIX scenario, should trigger bug before FIX commit and not after FIX commit
# for BIC scenario, should trigger bug after BIC commit and not before BIC commit

SCENARIO=${SCENARIO:-"FIX"}
conf=$1
source $conf
source utils.sh

# quit if #COMMITS is not defined
if [ -z ${#COMMITS[@]} ]; then
  echo "ERROR: COMMITS not defined, please source proj-specific env"
  exit 1
fi

cmds_before=""
cmds_after=""
reproduce_bug() {
  local truth_dir=$1
  local issue_id=$2
  if [ $SCENARIO = "FIX" ]; then
    local commit=${IID2FIX[$issue_id]}
  else
    local commit=${IID2BIC[$issue_id]}
  fi
  local truth_poc=$(find $truth_dir -name "*$issue_id*" | head -1)
  local builddir_before="build_before_$commit"
  local builddir_after="build_after_$commit"
  local exe_before="$builddir_before/$DIR_REL/$EXE"
  local exe_after="$builddir_after/$DIR_REL/$EXE"
  local cmd_before="$exe_before ../$truth_poc"
  local cmd_after="$exe_after ../$truth_poc"
  cmds_before+="\n$cmd_before"
  cmds_after+="\n$cmd_after"

  if [ ! -f "$truth_poc" ]; then
    echo "ERROR: PoC file $truth_poc not found in $truth_dir" 1>&2
    exit 1
  fi
  
  pushd $PROJ_NAME
  if [[ ! -f "$exe_before" || ! -f "$exe_after" ]]; then
    echo "ERROR: Executable $exe_before / $exe_after not found" 1>&2
    exit 1
  fi
  echo "Reproducing bug issue $issue_id with $SCENARIO commit $commit and PoC $truth_poc" 1>&2

  output_before=$(script -aeq -c "echo 'C' | $cmd_before")
  output_after=$(script -aeq -c "echo 'C' | $cmd_after")
  bug_before=$(check_output_bug "$output_before")
  bug_after=$(check_output_bug "$output_after")

  # bug is verified only if bug_before is not empty and bug_after is empty
  if [[ $SCENARIO = "FIX" && ! -z "$bug_before" && -z "$bug_after" ]]; then
    echo "Bug $bug_before is verified before $SCENARIO commit $commit!" 1>&2
    verified="Yes"
  elif [[ $SCENARIO = "BIC" && -z "$bug_before" && ! -z "$bug_after" ]]; then
    echo "Bug $bug_after is verified after $SCENARIO commit $commit!" 1>&2
    verified="Yes"
  else
    echo "Bug is not verified. before: $bug_before, after: $bug_after" 1>&2
    verified="No"
  fi
  popd
  summary_table+="\n$issue_id | $commit | $bug_before | $bug_after | $verified "
}

summary_table="issue | commit | before$SCENARIO | after$SCENARIO | bug verified?"
truth_dir="truthdata/$PROJ_NAME"
for issue_id in "${ISSUES[@]}"; do
  reproduce_bug $truth_dir $issue_id
done

echo -e $summary_table
echo -e "Commands before: $cmds_before"
echo -e "Commands after: $cmds_after"