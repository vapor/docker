FROM swift:5.1

RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true && apt-get -q update && \
    apt-get -q install -y \
    libssl-dev \
    zlib1g-dev \
    && rm -r /var/lib/apt/lists/*

RUN swift --version
