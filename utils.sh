#!/bin/bash

get_cmd () {
    local cmd="$1"
    local input_file="$2"
    local timeout="timeout 30s"
    # replace @@ in cmd with input_file and execute
    echo "$timeout $cmd" | sed "s|@@|$input_file|g"  # use | because $input_file may contain /
}

check_output_invalid() {
    # if $1 contains $BASH_SOURCE, "No such", means execution is unusual and not valid
    if [[ "$1" == *"$BASH_SOURCE"* || "$1" == *"No such"* || "$1" == *"Usage"* || "$1" == *"Is a directory"* || "$1" == *"failed to run command"* ]]; then
        return $(true)
    fi
    return $(false)
}

check_output_bug() {
    # input can be passed from $1, if empty, try to read from stdin, which can still be empty
    local input="$1"
    [ -z "$input" ] && ! test -t 0 && input=$(cat)
    # check existence of bug, currently support parse bug from AddressSanitizer and "^Error: JERRY_FATAL_FAILED_ASSERTION"
    # example input: multi-line string containing "ERROR: AddressSanitizer: global-buffer-overflow"
    # should return: "global-buffer-overflow"
    # find lines containing "ERROR: AddressSanitizer" and extract the bug type after ": "
    # for pattern in "ERROR: AddressSanitizer: " "ERROR: UndefinedBehaviorSanitizer: " "^Error: "; do
    for pattern in "ERROR: AddressSanitizer: " "ERROR: UndefinedBehaviorSanitizer: "; do
        if bug=$(echo "$input" | grep -oP "${pattern}\K[a-zA-Z_-]+" | head -1); then
            [ ! -z "$bug" ] && echo "$bug" && return 1
        fi
    done
    # Check for Aborted
    for pattern in "AddressSanitizer:DEADLYSIGNAL" "Aborted" "Segmentation fault" "core dumped" "dumped core"; do
        if bug=$(echo "$input" | grep -o "${pattern}" | head -1); then
            [ ! -z "$bug" ] && echo "$bug" && return 1
        fi
    done
}

parse_llm_input() {
    local ans=$1
    local input=$(echo "$ans" | sed -n '/^```/,/^```/ p' | sed '1d;$d')
    echo "$input"
}

parse_llm_cmd() {
    local ans=$1
    # NOTE: LLM may still return cmd with relative path if --help show path to exe
    local full_cmd=$(echo "$ans" | sed -n 's/Command: `\([^`]*\)`/\1/p')
    local exe_path=${full_cmd%% *}  # Extract the first word (the path/executable)
    local exe_name=${exe_path##*/}  # Strip directory to get just the filename
    local cmd="$exe_name ${full_cmd#* }" # Reconstruct the command with the rest of the arguments
    echo "$cmd"
}

# if cmd contain 'rm' or 'sudo', complain and abort
abort_if_cmd_danger() {
    local cmd=$1
    if [[ $cmd =~ "rm" ]] || [[ $cmd =~ "sudo" ]]; then
        echo "Command $cmd contains dangerous operation, aborting."
        exit 1
    fi
}

commit_affected_lines() {
    local commit=$1
    local file=$2
    local lines_before=()
    local lines_after=()

    local diff_output=$(git diff -U0 ${commit}^ ${commit} -- $file)

    echo "$diff_output" | gawk '
        BEGIN {
            PROCINFO["sorted_in"]="@ind_num_asc"
            # Initialize arrays to avoid undefined errors
            split("", lines_before);
            split("", lines_after);
        }
        /^\@\@/ {
            split($0, parts, " ");
            split(parts[2], range_before, ",");
            split(parts[3], range_after, ",");
            
            # Remove "+" or "-" from start
            sub(/^[-+]/, "", range_before[1]);
            sub(/^[-+]/, "", range_after[1]);
            
            # Calculate line ranges and populate arrays
            start_before = range_before[1];
            num_lines_before = range_before[2] == "" ? 1 : range_before[2];
            start_after = range_after[1];
            num_lines_after = range_after[2] == "" ? 1 : range_after[2];
            
            for (i = 0; i < num_lines_before; i++) {
                lines_before[start_before + i] = 1; # Use associative array to avoid duplicates
            }
            for (i = 0; i < num_lines_after; i++) {
                lines_after[start_after + i] = 1;
            }
        }
        END {
            # Print lines_before and lines_after without duplicates
            printf "lines_before:";
            for (line in lines_before) {
                printf "%s,", line;
            }
            printf "\nlines_after:";
            for (line in lines_after) {
                printf "%s,", line;
            }
            printf "\n";
        }
    ' | sed 's/,\n/\n/g'
}

git_commit_content() {
    local commit=$1
    git show --first-parent --format=%B $commit -- '*.c' '*.cpp' '*.cc' '*.h' # handle merge commit
}

git_commit_full() {  # same as git_commit_content
    local commit=$1
    git show --first-parent --format=%B $commit -- '*.c' '*.cpp' '*.cc' '*.h' # handle merge commit
}

git_commit_msgonly() {
    local commit=$1
    git show -s --format=%B $commit
}

git_commit_diffonly() {
    local commit=${1-"HEAD"}
    git diff ${commit}^ ${commit} -- '*.c' '*.cpp' '*.cc' '*.h'
}

get_commit_msg_from_json() {
    local commit=$1
    local mode=$2
    local json_file="../data/msgs.json"

    if [ ! -f "$json_file" ]; then
        echo "Error: JSON file $json_file not found."
        return 1
    fi

    jq -r ".\"$commit\".\"msg_${mode,,}\"" "$json_file"
}

get_commit_msg_from_yaml() {
    local commit=$1
    local mode=${2,,}
    local yaml_file="../msg/gemini.yaml"

    if [ ! -f "$yaml_file" ]; then
        echo "Error: YAML file $yaml_file not found."
        return 1
    fi

    # Use yq to extract the message, assuming yq is installed
    msg=$(yq ".[] | select(.commit == \"$commit\") | .msg_$mode" "$yaml_file")
    # if msg is "null", fall back to git_commit_msgonly
    if [ "$msg" == "null" ]; then
        msg=$(git_commit_msgonly "$commit")
    fi
    echo "$msg"
}

git_commit_enhanced() {
    local commit=$1
    get_commit_msg_from_yaml "$commit" "ENHANCED"
}

git_commit_reduced() {
    local commit=$1
    get_commit_msg_from_yaml "$commit" "REDUCED"
}

git_commit_featureonly() {
    local commit=$1
    get_commit_msg_from_json "$commit" "FEATUREONLY"
}

is_commit_codechange() {
# return $(true) if commit change c/cpp/cc/h source file, $(false) otherwise
    local commit=${1:-"HEAD"}
    git diff --name-only ${commit}^ ${commit} | grep -E "\.(c|cpp|cc|h)$"
}

commit_oneline() {
# [githash] # one-line commit message
    local commit=$1
    git show -s --format="%h # %s" --abbrev=7 $commit
}

recent_codechange_commits() {
    local n=${1:-"10"}
    local pat=${2:-""}
    local count=0
    git log --format="%h" | while read commit; do
        if git show --name-only "$commit" | grep -qE '\.(c|cc|cpp)$' > /dev/null; then
            if ! git log -1 --format="%s" "$commit" | grep -iqE "doc:|build:|windows:|fuzz:|example:|test:|tests:|html:"; then
                # skip if $pat is not empty and commit message doesn't match $pat regex 
                if [ ! -z "$pat" ] && ! git log -1 --format="%s" "$commit" | grep -qE "$pat"; then
                    continue
                fi
                git log -1 --format="%h # %s" --abbrev=7 "$commit" # --shortstat
                count=$((count + 1))
                if [ $count -ge $n ]; then
                    break
                fi
            fi
        fi
    done
}

gcov_tree() {
    local builddir=$1
    local proj=${2:-$PROJ_NAME}
    
    # Check if builddir is provided
    if [ -z "$builddir" ]; then
        echo "Error: Please provide a build directory as argument"
        return 1
    fi

    # Check if directory exists
    if [ ! -d "$builddir" ]; then
        echo "Error: Directory $builddir does not exist"
        return 1
    fi

    # Find all .gcda files in builddir recursively
    find "$builddir" -type f -name "*.gcda" | while read -r gcda_file; do
        # Run gcov and capture stdout
        coverage_output=$(gcov -fm -H "$gcda_file" 2>/dev/null)
        # echo -e "$gcda_file:\n$coverage_output"; continue
        # echo "Parsing $gcda_file"
        
        # Skip if gcov failed or no output
        if [ -z "$coverage_output" ]; then
            continue
        fi

        excluded_filepat="(^/usr/|\.h$|\.hpp$)"
        keeped_filepat="(\.c$|\.cpp$|\.cc$)"
        # Extract file coverage
        echo "$coverage_output" | grep -B1 "Lines executed" | grep "File " | while read -r file_line; do
            file_name=$(echo "$file_line" | sed "s/File '//" | sed "s/'//")
            # Skip if file matches excluded pattern or not matches keeped pattern
            if [[ "$file_name" =~ $excluded_filepat ]] || [[ ! "$file_name" =~ $keeped_filepat ]]; then
                echo "Skip $file_name because it's excluded or not keeped" >&2
                continue
            fi
            coverage_line=$(echo "$coverage_output" | grep -F -A1 "$file_line" | tail -n1)
            file_percent=$(echo "$coverage_line" | grep -o '[0-9]\+\.[0-9]\+%' | head -1)
            file_linetot=$(echo "$coverage_line" | grep -o 'of [0-9]\+' | cut -d' ' -f2)
            
            # $file_percent could empty, eg. "No executable lines"
            if [ -z "$file_percent" ]; then
                echo "empty file percent for $file_line $coverage_line" >&2
                return 1
            fi
            # Skip if file coverage is 0.00%
            if [ "$file_percent" = "0.00%" ]; then
                continue
            fi

            echo "Coverage of $file_name: $file_percent of $file_linetot"
        done

        # Extract function coverage
        # NOTE: skip if $proj is z3 or php-src, because they have too many functions, exceeding LLM context
        if [[ "$proj" == "z3" || "$proj" == "php-src" ]]; then
            continue
        fi
        echo "$coverage_output" | grep -B1 "Lines executed" | grep "Function " | while read -r func_line; do
            func_name=$(echo "$func_line" | sed "s/Function '//" | sed "s/'//")
            # Get next line with coverage info
            coverage_line=$(echo "$coverage_output" | grep -F -A1 "$func_line" | tail -n1)
            func_percent=$(echo "$coverage_line" | grep -o '[0-9]\+\.[0-9]\+%' | head -1)
            func_linetot=$(echo "$coverage_line" | grep -o 'of [0-9]\+' | cut -d' ' -f2)
            
            # skip if $func_percent is empty
            if [ -z "$func_percent" ]; then
                echo "empty func percent for $func_line $coverage_line"
                return 1
            fi
            # Only print functions with coverage > 0.00%
            if [ "$func_percent" != "0.00%" ]; then
                echo "  $func_name: $func_percent of $func_linetot"
            fi
        done
    done
}

gcovr_tree() {
# NOTE: modifed gcovr to add --functions flag, printing all function coverage with human-readable format
    local builddir="$1"
    
    # Check if builddir is provided
    if [ -z "$builddir" ]; then
        echo "Error: Please provide a build directory as argument"
        return 1
    fi

    # Check if directory exists
    if [ ! -d "$builddir" ]; then
        echo "Error: Directory $builddir does not exist"
        return 1
    fi

    # Run gcovr and capture stdout
    coverage_output=$(gcovr -o /tmp/a --functions "$builddir" 2>/dev/null)
    
    # Skip if gcovr failed or no output
    if [ -z "$coverage_output" ]; then
        echo "No coverage data found" >&2
        return 1
    fi

    # First, filter out lines with 0.00%
    filtered_output=$(echo "$coverage_output" | grep -v "0.00%")

    # Process the filtered output to only keep file headers with functions
    echo "$filtered_output" | awk '
    /^Function Coverage of/ { 
        file_line = $0; 
        has_functions = 0; 
        next; 
    }
    /^  / { 
        if (!has_functions) { 
            print file_line; 
        } 
        print $0; 
        has_functions = 1; 
    }'
}

afl_testcase_ms() {
    # example input from AFL++: fuzzout_8c27b12_after/default/crashes/id:000005,sig:06,src:002721+000002,time:40439616,execs:2445419,op:splice,rep:1
    # example input from WAFLGO: out_mujs_4c7f6be_1/crashes/target_id:000000,1197472,sig:11,src:000524,op:havoc,rep:4
    # should return time in milliseconds
    local testcase=$1
    time=$(echo "$testcase" | grep -oP "time:\K[0-9]+" | awk '{print $1}')
    # if time is empty, try WAFLGo pattern, parse second column split by comma
    [ -z "$time" ] && time=$(echo "$testcase" | awk -F, '{print $2}')
    echo "$time"
}

repeat() {
# usgae: repeat <n> <command>
    # if $1 is number, n=$1 and shift, otherwise n=1
    if [[ $1 =~ ^[0-9]+$ ]]; then
        n=$1
        shift
    else
        n=1
    fi
    for i in $(seq $n); do
        $@
    done
}
