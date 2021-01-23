#!/bin/bash

set -e

if [ -z "$1" ];then
    echo 'Please provide a version' && exit 1
fi

VERSION=$1
export DOCKER_CLI_EXPERIMENTAL=enabled
IMAGES=$(docker manifest inspect litcodes/rmp:latest | jq '.manifests| .[].digest | "litcodes/rmp@" + .')
docker manifest create litcodes/rmp:$VERSION $IMAGES
docker manifest push litcodes/rmp:$VERSION
