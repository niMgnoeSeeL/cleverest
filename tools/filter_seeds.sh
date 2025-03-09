#!/bin/bash

# AFL reject slow some slow seeds taking more than 1s to run, this script removes them

SEED_DIR="/clever/seeds/php"
TARGET="/clever/php-src/buildafl_after_998bce1/sapi/cli/php"

for seed in "$SEED_DIR"/*; do
  # echo "$seed"
  # Run the target with the seed, timeout set to 1s
  timeout 1s $TARGET $seed
  exit_code=$?
  
  # Check if the command timed out (exit code 124)
  if [ $exit_code -eq 124 ]; then
    echo "Removing slow seed: $seed"
    rm "$seed"
  fi
done