ARG UBUNTU_OS_IMAGE_VERSION
FROM ubuntu:${UBUNTU_OS_IMAGE_VERSION}

ARG UBUNTU_VERSION_SPECIFIC_APT_DEPENDENCIES
# DEBIAN_FRONTEND=noninteractive for automatic UTC configuration in tzdata
RUN apt-get -qq update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
  libatomic1 libxml2 libz-dev libbsd0 tzdata ${UBUNTU_VERSION_SPECIFIC_APT_DEPENDENCIES} \
  && rm -r /var/lib/apt/lists/*
