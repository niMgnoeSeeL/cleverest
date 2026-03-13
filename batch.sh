#!/bin/bash

config=${1:-libxml2.env}
conf=$config

# 10 repetitions of run.sh
for i in {1..10}; do
   SCENARIO=BIC ./run.sh $config
   SCENARIO=FIX ./run.sh $config
done

for i in {1..10}; do
   SCENARIO=BIC GENCMD=1 ./run.sh $config
   SCENARIO=FIX GENCMD=1 ./run.sh $config
done

for i in {1..10}; do
   GIT_INFO=MSGONLY ./run.sh $conf
   GIT_INFO=DIFFONLY ./run.sh $conf
   LLM_TEMP=1.0 ./run.sh $conf
   LLM=gpt-4o-mini ./run.sh $conf
   NOFEEDBACK=1 ./run.sh $conf
   MAX_ITER=10 ./run.sh $conf
done

for i in {1..10}; do
  SCENARIO=FIX GIT_INFO=ENHANCED ./run.sh $config
  SCENARIO=FIX GIT_INFO=REDUCED ./run.sh $config
done

# DeepSeek API
# export OPENAI_API_KEY=
for i in {1..10}; do
  SCENARIO=BIC LLM=deepseek-r1 ./run.sh $config
  SCENARIO=FIX LLM=deepseek-r1 ./run.sh $config
done
