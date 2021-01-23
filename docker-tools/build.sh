#! /bin/bash

set -e

SCRIPT_DIR=`dirname $0`

# Read the archs file
ARCHS=`cat $SCRIPT_DIR/archs`

# Required to make buildx work
export DOCKER_CLI_EXPERIMENTAL=enabled

$SCRIPT_DIR/run_builder.sh

if [ -z "$DO_NOT_PUSH" ]; then
    FLAGS="--platform $ARCHS --push"
else
    FLAGS="--load"
fi
docker buildx build $FLAGS -t $@
