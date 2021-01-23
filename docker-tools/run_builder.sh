#! /bin/bash

set -e

# Required to make buildx work
export DOCKER_CLI_EXPERIMENTAL=enabled

# If a builder is running exit
docker buildx inspect | grep running && exit 0

# Use qemu-user-static to create a multi-arch Docker env
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes

# Start a builder and use it
docker buildx create --use
