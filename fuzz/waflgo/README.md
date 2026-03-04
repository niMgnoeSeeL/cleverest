This folder contains Dockerfile for set up Docker environment for building/fuzzing target programs with WAFLGo, along with helper scripts for building and running the Docker container.

- `waflgo_${PROJ_NAME}.Dockerfile`: Dockerfile for building Docker image for fuzzing target program with WAFLGo.
- `bdocker.sh`: Helper script for building WAFLGo Docker images for specific target program.
- `rdocker.sh`: Helper script for running WAFLGo Docker container with fuzzing for specific target program.
- `checkwaflgo.sh`: Helper script for checking WAFLGo fuzzing result for specific target program, print table of bug-triggering status for each commmit and first file that triggers the bug.
- `bwaflgo.sh`: only used when building images from Dockerfile

Usage:

Copy `*.env` and `utils.sh` from top-level directory to here, then run `bdocker.sh` to build WAFLGo Docker image for target program. If build fails due to WAFLGo instrumentation error, try to modify `buildwaflgo_target` in `*.env`.