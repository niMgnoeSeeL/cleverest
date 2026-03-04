#!/bin/bash

# locate bug-introducing commit for each issue given bug-fixing commit and ground truth PoC
# bisect between the bug-fixing commit and the earliest commit in 2020
# NOTE: some commits may fail to build, they should return 125 so git bisect handle them as untestable instead of bad

set -e

conf=$1
source $conf
source utils.sh

# quit if #COMMIT_FIX is not defined
if [ -z ${#COMMITS_FIX[@]} ]; then
  echo "ERROR: COMMITS_FIX is not defined, please source proj-specific env"
  exit 1
fi

COMMITS_BIC=()
export ASAN_OPTIONS=detect_leaks=0

locate_bic() {
  local truth_dir=$1
  local issue_id=$2
  local fix_commit=${IID2FIX[$issue_id]}
  local command=${COMMANDS_MAP[$fix_commit]}
  local builddir="build_bisect"
  local truth_poc=$(find $truth_dir -name "*$issue_id*" | head -1)

  if [ ! -f "$truth_poc" ]; then
    echo "ERROR: PoC file $truth_poc not found in $truth_dir"
    exit 1
  fi
  echo "Locating BIC for issue $issue_id with fix commit $fix_commit and PoC $truth_poc"

  pushd $PROJ_NAME

  # assume BIC commit is after 2020, starting bisect with bad being fix^, good being earliest commit
  local first_commit=$(git rev-list --before="2020-01-01" --max-count=1 HEAD)

  type build_target >/dev/null 2>&1 || { echo "ERROR: build_target function not defined"; exit 1; }

  # get bug_intended by executing build_before_$fix_commit
  local cmd_before_fix=$(get_cmd "build_before_$fix_commit/$DIR_REL/$command" ../$truth_poc)
  bug_intended=$(script -aeq -c "echo C | $cmd_before_fix" | check_output_bug || true)
  local runcmd=$(get_cmd "$builddir/$DIR_REL/$command" ../$truth_poc)
  
  echo "Bug intended by fix commit $fix_commit: $bug_intended"
  git bisect start $fix_commit^ $first_commit
  # NOTE: when `rm -rf $builddir`, sleep 1 to avoid error like rm: cannot remove 'build_bisect/math/polynomial/.nfs00000000124d18d600003294': Device or resource bus
  # NOTE: sometimes check_output_bug return other bug, so we need to check existence of $bug_intended
  bisect_runcmd="set -x; while ! rm -rf $builddir 2>/dev/null; do sleep 1; done && source ../$conf && source ../utils.sh && pre_build $builddir && build_target $builddir && script -aeq -c 'echo C | $runcmd' bisect_run.log | check_output_bug | (! grep \"$bug_intended\") "
  git bisect run bash -c "$bisect_runcmd"
  git bisect visualize
  local bic_commit=$(git rev-parse --short=7 refs/bisect/bad)
  # $bic_commit may not be accurate, build to check again
  builddir_bic_after=build_BICafter_$bic_commit
  builddir_bic_before=build_BICbefore_$bic_commit
  echo "Seems BIC commit for issue $issue_id is $bic_commit, build it in $builddir_bic_after and $builddir_bic_before"
  git checkout $bic_commit^ && pre_build $builddir_bic_before && build_target $builddir_bic_before
  git checkout $bic_commit && pre_build $builddir_bic_after && build_target $builddir_bic_after
  local cmd_before=$(get_cmd "$builddir_bic_before/$DIR_REL/$command" ../$truth_poc)
  local cmd_after=$(get_cmd "$builddir_bic_after/$DIR_REL/$command" ../$truth_poc)
  local bug_before=$(script -aeq -c "$cmd_before" | check_output_bug || true)
  local bug_after=$(script -aeq -c "$cmd_after" | check_output_bug || true)
  # bic is verified only if bug_after == $bug_intended and bug_before != $bug_intended
  if [[ "$bug_after" == "$bug_intended" && "$bug_before" != "$bug_intended" ]]; then
    echo "Issue $issue_id BIC $bic_commit is verified! before: $bug_before, after: $bug_after"
    verified="Yes"
  else
    echo "Issue $issue_id BIC $bic_commit is not verified. before: $bug_before, after: $bug_after"
    verified="No"
  fi
  git bisect reset
  popd
  IID2BIC[$issue_id]=$bic_commit
  COMMITS_BIC+=($bic_commit)
  summary_table+="\n$issue_id | $fix_commit | $bic_commit | $bug_before | $bug_after | $verified"
}

summary_table="issue | bugfix commit | potential BIC commit | beforebic | afterbic | bic verified?"
truth_dir="truthdata/$PROJ_NAME"
for issue_id in "${ISSUES[@]}"; do
  locate_bic $truth_dir $issue_id
done

echo -e $summary_table
echo "COMMITS_BIC=(${COMMITS_BIC[@]})"

pushd $PROJ_NAME
for commit in "${COMMITS_BIC[@]}"; do
  commit_oneline $commit
done
popd