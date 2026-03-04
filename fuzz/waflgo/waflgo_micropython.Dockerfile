FROM he1lonice/waflgo:v1 AS base

SHELL ["/bin/bash", "-c"]

WORKDIR /home/

# Set environment variables
ENV PATH=$PATH:/home/llvm-project-llvmorg-13.0.0/build/bin
ENV PATH=$PATH:/root/go/bin
ENV PATH=$PATH:/usr/local/go/bin
ENV SVF_DIR=/home/SVF
ENV LLVM_DIR=/home/SVF/llvm-13.0.0.obj
ENV Z3_DIR=/home/SVF/z3.obj
ENV SVF_HOME=/home/SVF
ENV SVF_HEADER=$SVF_HOME/include
ENV SVF_LIB=$SVF_HOME/Release-build/lib
ENV LD_LIBRARY_PATH=$SVF_LIB
ENV LLVM_CONFIG=llvm-config

# Clone WAFLGo to /home/
RUN git clone https://github.com/He1loNice/WAFLGo

# Build WAFLGo
RUN cd WAFLGo && \
    make -j8 && \
    make -C llvm_mode -j8 && \
    cd instrument/ && \
    cmake . && \
    make -j8

# Install useful tools
RUN apt-get update && apt-get install -y \
    bat \
    htop \
    tmux \
    ranger

FROM base AS waflgo_micropython

# Clone micropython to /home/
RUN git clone https://github.com/micropython/micropython 

# Clone unifuzz/seeds
RUN git clone https://github.com/unifuzz/seeds

# Use built-in tests as pyseeds
RUN mkdir -p /home/pyseeds/ && cp -r micropython/tests/misc/*.py /home/pyseeds/

# Copy micropython.env to /home/
COPY micropython.env ./

# Copy scripts
COPY utils.sh ./
COPY bwaflgo.sh ./

# Specify commit as each Docker can only test one commit
ARG commit=4c93955
ENV commit=$commit

# Build micropython with WAFLGo under /home/micropython/buildwaflgo_$commit
RUN ./bwaflgo.sh micropython.env $commit

# avoid git permission problem on start
RUN git config --global --add safe.directory /home/micropython
# avoid WAFLGo exit when seeds crash
ENV AFL_SKIP_CRASHES=1
# Run fuzz in tmux session
WORKDIR /home/micropython
CMD tmux new-session -d -s fuzz_$commit && tmux send-keys -t fuzz_$commit "timeout 24h bash -c 'source ../micropython.env && run_waflgo'" Enter && bash
