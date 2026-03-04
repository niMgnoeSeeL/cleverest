
#!/bin/bash

# Determine the directory of the current script
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Default configurations
SCENARIO=${SCENARIO:-BIC}
GIT_INFO=${GIT_INFO:-FULL}
MAX_ITER=${MAX_ITER:-5}
LLM=${LLM:-"gpt-4o-2024-08-06"}
LLM_TEMP=${LLM_TEMP:-0.5}
NOFEEDBACK=${NOFEEDBACK:-""}
GENCMD=${GENCMD:-""}
RUNFUZZ=${RUNFUZZ:-""}

# dirname: exp_${PROJ_NAME}_${SCENARIO}_GIT${GIT_INFO}_ITER${MAX_ITER}_${LLM}_TEMP${LLM_TEMP}_*

# find default exp dirs under $exp_root, call clevfuzz.sh for each
conf=$1
exp_root=$2
source $conf

commands=()

for exp_dir in $exp_root/exp_*; do
  if [ -d "$exp_dir" ]; then
    # check if exp_dir match default
    basedir=$(basename "$exp_dir")
    if [[ "$basedir" == "exp_${PROJ_NAME}_BIC_GIT${GIT_INFO}_ITER${MAX_ITER}_${LLM}_TEMP${LLM_TEMP}_2"* || \
        "$basedir" == "exp_${PROJ_NAME}_FIX_GIT${GIT_INFO}_ITER${MAX_ITER}_${LLM}_TEMP${LLM_TEMP}_2"* ]]; then
        commands+=("$SCRIPT_DIR/clevfuzz.sh $conf $exp_dir")
    fi
  fi
done

# Dry run: print all commands
echo "The following commands will be executed:"
for cmd in "${commands[@]}"; do
  echo "$cmd"
done

# Ask for confirmation
read -p "Do you want to execute these commands? (y/n): " confirm
if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
  for cmd in "${commands[@]}"; do
    eval "$cmd"
  done
else
  echo "Execution aborted."
fi

# Check fuzzer sessions who fail to launch due to some race condition when launching too many
while true; do
    for sn in $(tmux list-sessions -F '#S' | grep fuzz | grep "$PROJ_NAME"); do
        content=$(tmux capture-pane -pt "$sn")

        if echo "$content" | grep -q "saved crashes"; then
            echo "[+] $sn: Fuzzing in progress."
        elif echo "$content" | grep -q "least one valid input seed"; then
            echo "[~] $sn: Stopped (Expected seed crash). Not restarting."
        else
            echo "[!] $(date +%T) - $sn: Initialization failure. Restarting..."
            tmux send-keys -t "$sn" C-c
            sleep 0.5
            tmux send-keys -t "$sn" Up Enter
            sleep 5
        fi
    done
done
