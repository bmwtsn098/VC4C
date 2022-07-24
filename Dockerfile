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
FROM debian:bookworm-slim
COPY --from=builder /VC4C/build/src/vc4c /
COPY --from=builder /VC4C/build/src/libVC4CC.so /
COPY --from=builder /VC4C/build/src/libVC4CC.so.1.2 /
COPY --from=builder /VC4C/build/src/libVC4CC.so.0.4.9999 /
COPY --from=builder /usr/lib/x86_64-linux-gnu/libLLVM-10.so.1 /
RUN apt-get update && apt-get install -y wget libedit-dev
RUN wget http://es.archive.ubuntu.com/ubuntu/pool/main/libf/libffi/libffi7_3.3-4_amd64.deb
RUN dpkg -i libffi7_3.3-4_amd64.deb
ENV LD_LIBRARY_PATH=/