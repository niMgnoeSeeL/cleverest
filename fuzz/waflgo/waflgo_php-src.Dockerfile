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

FROM base AS waflgo_php

# Clone php to /home/
RUN git clone https://github.com/php/php-src

# Uninstall cmake from apt and install latest cmake with pip
RUN apt-get remove -y cmake && \
    pip install --upgrade cmake

# Install dependencies for php
RUN apt-get update && apt-get install -y re2c libsqlite3-dev

# Copy seeds from php-src/tests to /home/seeds/php
RUN mkdir -p /home/seeds/php && \
    cp php-src/tests/basic/* /home/seeds/php/

# Copy php.env to /home/
COPY php.env ./

# Copy scripts
COPY utils.sh ./
COPY bwaflgo.sh ./

# Specify commit as each Docker can only test one commit
ARG commit=5cb38e9
ENV commit=$commit

# Build php-src with WAFLGo under /home/php-src/buildwaflgo_$commit
RUN ./bwaflgo.sh php.env $commit

# avoid git permission problem on start
RUN git config --global --add safe.directory /home/php-src
# avoid WAFLGo exit when seeds crash
ENV AFL_SKIP_CRASHES=1
# Run fuzz in tmux session
WORKDIR /home/php-src
CMD tmux new-session -d -s fuzz_$commit && tmux send-keys -t fuzz_$commit "timeout 24h bash -c 'source ../php.env && run_waflgo'" Enter && bash