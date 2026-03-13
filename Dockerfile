FROM aflplusplus/aflplusplus:v4.21c

# Install necessary dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    gawk \
    jq \
    tmux

# Install useful tools
RUN apt-get install -y \
    bat \
    htop \
    ranger

RUN apt-get install -y \
    libreadline-dev \
    libfreetype-dev \
    libfontconfig-dev \
    libnss3-dev \
    libtiff-dev

RUN apt-get install -y \
    libsqlite3-dev \
    libbz2-dev \
    libcurl4-gnutls-dev \ 
    libenchant-2-dev \
    libldap-dev \
    libonig-dev \
    libedit-dev \ 
    libsnmp-dev \
    libsodium-dev \
    libxslt-dev \
    libzip-dev

# Set user
ARG UNAME=$(whoami)
ARG UID=1000
ARG GID=1000
RUN groupadd -g $GID -o $UNAME
RUN useradd -m -u $UID -g $GID -o -s /bin/bash $UNAME

# Install yq
RUN wget https://github.com/mikefarah/yq/releases/download/v4.52.2/yq_linux_amd64.tar.gz && \
    tar xf yq_linux_amd64.tar.gz && \
    mkdir -p /home/$UNAME/.local/bin && \
    mv yq_linux_amd64 /home/$UNAME/.local/bin/yq && \
    rm yq_linux_amd64.tar.gz install-man-page.sh yq.1 && \
    chown -R $UNAME:$UNAME /home/$UNAME/.local

# do not change user here, exec -u instead
# USER $UNAME

# Copy scripts and environment files
# COPY openai .
# COPY *.sh .
# COPY *.env .
WORKDIR /clever
