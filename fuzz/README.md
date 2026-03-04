This folder contains scripts related to fuzzing, either ClevFuzz or WAFLGo baseline experiment.

- `clevfuzz.sh`: Script to run ClevFuzz for target program, given a finished Cleverest experiment.
- `batchfuzz.sh`: Script that calls `clevfuzz.sh` to run ClevFuzz for all default Cleverest experiments of target program, given an experiment root containing individual experiment directories.
- `checkfuzz.sh`: Script to check the results of ClevFuzz for target program under all experiments found, results dumped as table in `postfuzz_*.csv`.
- `checkseeds.sh`: Scripts to check closeness of initial seeds used for baseline fuzzing (WAFGo), results dumped as table in `seeds_*.csv`.
- `waflgo`: Folder containing scripts to run WAFLGo baseline experiment, see README.md inside for more details.