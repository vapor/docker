ARG SWIFT_BASE_IMAGE

FROM ${SWIFT_BASE_IMAGE}

RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true && apt-get -q update

ARG ADDITIONAL_APT_DEPENDENCIES=

RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true && \
    apt-get -q install -y \
    zlib1g-dev \
    ${ADDITIONAL_APT_DEPENDENCIES} \
    && rm -r /var/lib/apt/lists/*

RUN swift --version
