FROM ubuntu:18.04

# DEBIAN_FRONTEND=noninteractive for automatic UTC configuration in tzdata
RUN apt-get -qq update && DEBIAN_FRONTEND=noninteractive apt-get install -y \ 
  libatomic1 libicu60 libxml2 libcurl4 libz-dev libbsd0 tzdata \
  && rm -r /var/lib/apt/lists/*
