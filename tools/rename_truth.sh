#!/bin/bash

set -xe

conf=$1
source $conf

truth_dir="truthdata/$PROJ_NAME"
for issue_id in "${ISSUES[@]}"; do
  commit_bic=${IID2BIC[$issue_id]}
  commit_fix=${IID2FIX[$issue_id]}
  truth_file=$(find $truth_dir -name "*$issue_id*" | head -1)
  if [ ! -f "$truth_file" ]; then
    echo "ERROR: PoC file $truth_file not found in $truth_dir"
    exit 1
  fi
  ext=$(echo $truth_file | grep -oP "\.\w+$")
  echo "Soft link $truth_file to TRUTH_FIX_$commit_fix$ext"
  ln -s $(basename $truth_file) $truth_dir/TRUTH_FIX_$commit_fix$ext
  echo "Soft link $truth_file to TRUTH_BIC_$commit_bic$ext"
  ln -s $(basename $truth_file) $truth_dir/TRUTH_BIC_$commit_bic$ext
done