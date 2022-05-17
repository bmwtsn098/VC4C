# Build Stage:
FROM --platform=linux/amd64 ubuntu:20.04 as builder

## Install build dependencies.
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential make cmake git clang

## Add Source Code
ADD . /VC4C
WORKDIR /VC4C

## Build Step
RUN rm -rf build
RUN mkdir build
WORKDIR build
RUN cmake ..
RUN make
WORKDIR src

# Package Stage
#FROM --platform=linux/amd64 ubuntu:20.04
#COPY --from=builder /fuzzme /
