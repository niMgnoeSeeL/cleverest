# Anonymous Artifact for Cleverest

Cleverest is a feedback-directed, zero-shot LLM-based regression test generation technique proposed in the paper "[Paper Title]". We evaluate its effectiveness on 46 commits of six subject programs: three already in WAFLGo dataset (Mujs, Libxml2, and Poppler) and three newly added programs (JerryScript, Z3, PHP). This repository contains the implementation of Cleverest along with the dataset and instructions to reproduce the main results in the paper.

## Citation

If you want to use Cleverest in your research or refer it, please use the following citation:

```bibtex
[bibtext]
```

The supplementary material is available at **[supp/supplementary.pdf](supp/supplementary.pdf)**.

## Data Replication

In the paper, we run experiments on 6 software (mujs, libxml2, poppler, jerryscript, z3, php) for 2 scenarios (bug-finding and bug-reproduction) under 10 different ablation settings (default, MSGONLY, DIFFONLY, GENCMD, TEMP1.0, gpt-4o-mini, deepseek-r1, ITER10, NOFEEDBACK, ENHANCED/REDUCED for FIX scenario) and repeat 10 times. Each software has 180 experiments (200 for libxml2 and poppler becuase only these two have CLI options to test with GENCMD).

The result of all experiments on all commits is aggregated as a CSV file in `figure/aggregated_results.csv` with 4280 data rows. The tables in the paper are then drawed from this CSV file.

The data of experiments in the paper is available at `repdata.tar.xz` (uncompressed size 1.2 GB), which contains 1120 text files prefixed by `SUMMARY_` and 1120 folders prefixed by `exp_`. For each software, there are 180 (200 for libxml2 and poppler) `SUMMARY_*` files and `exp_*` folders corresponding to different ablation settings. The `SUMMARY_*` file contains the configuration of a experiment and the result for each commit in a table format. The `exp_*` folder contains intemidiate data containing full history of interacting with LLM (`chat_*.log`), all generated test cases (`INPUT_*`), non-trival test cases that trigger bugs, cause output difference or reach commit-changed code (`TRIGGER_*`) and other useful intermediate files.

## Evaluation Setup

The system is tested on Docker container [aflplusplus/aflplusplus:v4.21c](https://hub.docker.com/layers/aflplusplus/aflplusplus/v4.21c/images/sha256-2c445346a9f5c4e321a08c5d3ae77282ca61ad332dd2ddb7683a724f91d0e136) running Ubuntu 22.04, with following dependencies installed:

```bash
# necessary dependencies for Cleverest to run
apt-get install -y curl gawk jq tmux
# dependencies for building mujs, libxml2, and poppler
apt-get install -y libreadline-dev libfreetype-dev libfontconfig-dev libnss3-dev libtiff-dev
```

You will need to specify OpenAI API key in environment variable before running experiments, or set it in `openai` Bash script.

```bash
export OPENAI_API_KEY=your_api_key
```

Before running full experiments, you can run a very basic test for only one [bug-introducing commit 8c27b12](https://github.com/ccxvii/mujs/commit/8c27b12) of MuJS with only one LLM query by running the following command:

```bash
# $conf is the file containing information about program and commit under test
export conf=mujs1.env
MAX_ITER=1 ./run.sh $conf
```

The script should take less than 20 seconds to execute and print some debug information. If Cleverest successfully found the bug, you should see "Bug triggered after commit 8c27b12" along with some AddressSanitizer output.

You should also get a text file prexied by `SUMMARY_` and a folder prefixed by `exp_` in current directory. The `SUMMARY_*` file contains the configuration of experiment and the result for each commit in a table format. The `exp_*` folder contains full history of interacting with LLM (`chat_*.log`), all generated test cases (`INPUT_*`), non-trival test cases that trigger bugs, cause output difference or reach commit-changed code (`TRIGGER_*`) and other useful intermediate files.

## Build Subject Programs

Even though `run.sh` will automatically build the subject programs if they do not exist, it's recommended to build them before running experiments to accurately measure the execution time needed by Cleverest. You can build all subject programs for commits under test by running the following command:

```bash
export conf=mujs.env  # or libxml2.env, poppler.env, jerryscript.env, z3.env, php.env
SCENARIO=BIC ./b.sh $conf  # build bug-introducing commits for bug-finding scenario
SCENARIO=FIX ./b.sh $conf  # build bug-fixing commits for bug-reproduction scenario
```

## Reproducing Results

### RQ1: Evaluation of Capabilities

Run the following command to run experiment under default setting:

```bash
./run.sh $conf
# same as setting the default configuration
SCENARIO=BIC GIT_INFO=FULL MAX_ITER=5 LLM_TEMP=0.5 LLM=gpt-4o ./run.sh $conf
```

### RQ2: Ablation Study

#### Prompt Synthesizer

```bash
GIT_INFO=MSGONLY ./run.sh $conf
GIT_INFO=DIFFONLY ./run.sh $conf
GENCMD=1 ./run.sh $conf
```

#### LLM Module

```bash
LLM_TEMP=1.0 ./run.sh $conf
LLM=gpt-4o-mini ./run.sh $conf
LLM=deepseek-r1 ./run.sh $conf
```

#### Execution Analyzer

```bash
NOFEEDBACK=1 ./run.sh $conf
MAX_ITER=10 ./run.sh $conf
```

### RQ3: Effectiveness of Commit Messages

The enhanced/reduced commit messages produced by gemini-2.5-flash are stored in `msg/gemini.yaml` for reference.
To run experiments with enhanced/reduced commit messages, run the following commands:

```bash
SCENARIO=FIX GIT_INFO=ENHANCED ./run.sh $conf
SCENARIO=FIX GIT_INFO=REDUCED ./run.sh $conf
```

### RQ4: Comparison to the State-of-the-Art

Follow instructions in [`fuzz/README.md`](fuzz/README.md) to run WAFLGo and ClevFuzz experiments.