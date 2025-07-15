#!/bin/bash

SCENARIO=${SCENARIO:-BIC}
LLM=${LLM:-"gpt-4o-mini"}

# Main script logic
if [ $# -lt 1 ]; then
    echo "Usage: $0 <path-to-config-file>"
    exit 1
fi

config_file=$1
source $config_file
source utils.sh

if [ -z "$COMMITS" ]; then
    echo "No commits found in the configuration file."
    exit 1
fi

# Function to generate manipulated commit messages
generate_commit_msg() {
    local commit=$1
    local mode=$2
    local llm=${LLM}
    commit_raw=$(git show --first-parent --format=%B $commit -- '*.c' '*.cpp' '*.cc' '*.h')
    if [ -z "$commit_raw" ]; then
        echo "No commit content found for $commit"
        return 1
    fi

    case $mode in
        ENHANCED)
            msg="Enhance this commit by generating a more informative message to show developer's intent. Focus on describing how the commit modify the program's behavior such that it now handles input X or performs action A in a new or different way Y, without mentioning code details."
            ;;
        REDUCED)
            msg="Reduce this commit by generating a less informative message that hides developer's intention. Keep only technical changes without revealing the purpose."
            ;;
        FEATUREONLY)
            msg="Extract only the high-level feature information from this commit. Your output should be a short paragraph describing only the general feature area this commit affects."
            ;;
        *)
            echo "Invalid mode: $mode"
            return 1
            ;;
    esac

    >&2 echo -e "Querying with prompt: $msg" 
    ans=$(echo "$msg\nJust show the message without any additional text.\n\n$commit_raw" | timeout 30s ../openai +model=$llm)
    echo "$ans"
}

# Function to generate JSON object for manipulated messages
generate_json() {
    local commits=("$@")
    local modes=("ENHANCED" "REDUCED" "FEATUREONLY")

    echo "{"
    for commit in "${commits[@]}"; do
        msg_raw=$(git_commit_msgonly $commit | jq -Rs .)
        echo "  \"$commit\": {"
        echo "    \"msg_raw\": $msg_raw,"
        for mode in "${modes[@]}"; do
            msg=$(generate_commit_msg $commit $mode | jq -Rs .)
            echo -n "    \"msg_${mode,,}\": $msg"
            if [ "$mode" != "${modes[-1]}" ]; then
                echo ","
            else
                echo ""
            fi
        done
        if [ "$commit" != "${commits[-1]}" ]; then
            echo "  },"
        else
            echo "  }"
        fi
    done
    echo "}"
}

# get both COMMITS_BIC and COMMITS_FIX into one bash array
COMMITS_ALL=("${COMMITS_BIC[@]}" "${COMMITS_FIX[@]}")
pushd $PROJ_NAME
generate_json "${COMMITS_ALL[@]}"
