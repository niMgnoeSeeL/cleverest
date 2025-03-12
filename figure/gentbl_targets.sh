#!/bin/bash

# accept multiple *.env files as argument, then generate CSV file with columns:
# software, description, command, issue, BIC, BFC
# each *.env file has array variable $ISSUES, $COMMANDS, $COMMITS_BIC, $COMMITS_FIX

# usage: ./targets_tbl.sh <path-to-env-files>
# output: targets.csv

# read all env files
env_files=$@
# exit if no env files
if [ -z "$env_files" ]; then
    echo "No env files passed."
    exit 1
fi

echo "software,description,command,issue,BIC,BFC,url" > targets.csv
for env_file in $env_files; do
    # check if env file exists
    if [ ! -f $env_file ]; then
        echo "File $env_file not found." 2>&1
        continue
    fi
    source $env_file
    for i in "${!ISSUES[@]}"; do
        issue_url=$PROJ_REPO/issues/${ISSUES[$i]}
        echo "$PROJ_NAME,$PROJ_DESC,${COMMANDS[$i]},${ISSUES[$i]},${COMMITS_BIC[$i]},${COMMITS_FIX[$i]},$issue_url" >> targets.csv
    done
done
