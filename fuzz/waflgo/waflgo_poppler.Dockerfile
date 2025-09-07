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

FROM base AS waflgo_poppler

# Clone poppler to /home/
RUN git clone https://gitlab.freedesktop.org/poppler/poppler/

# Clone unifuzz/seeds
RUN git clone https://github.com/unifuzz/seeds

# NOTE: cmake from pip too new >4.0, incompatible with old cmakefile
# Uninstall cmake from apt and install latest cmake with pip
# RUN apt-get remove -y cmake && \
#     pip install --upgrade cmake

# Install dependencies for poppler
RUN apt-get update && apt-get install -y libfreetype-dev libfontconfig-dev libjpeg-dev libopenjp2-7-dev liblcms2-dev libpng-dev libcurl4-nss-dev libnss3-dev libnspr4-dev

# Copy poppler.env to /home/
COPY poppler.env ./

# Copy scripts
COPY utils.sh ./
COPY bwaflgo.sh ./

# Specify commit as each Docker can only test one commit
ARG commit=3d35d20
ENV commit=$commit

# Build poppler with WAFLGo under /home/poppler/buildwaflgo_$commit
# BUG: has to build 3cae777 first, otherwise commits like e674ca6 and aaf2e80 always fail, why?
RUN ./bwaflgo.sh poppler.env 3cae777
RUN ./bwaflgo.sh poppler.env $commit

# avoid git permission problem on start
RUN git config --global --add safe.directory /home/poppler
# avoid WAFLGo exit when seeds crash
ENV AFL_SKIP_CRASHES=1
# Run fuzz in tmux session
WORKDIR /home/poppler
CMD tmux new-session -d -s fuzz_$commit && tmux send-keys -t fuzz_$commit "timeout 24h bash -c 'source ../poppler.env && run_waflgo'" Enter && bash
