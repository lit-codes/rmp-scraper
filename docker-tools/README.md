# Docker images

Docker is used to build containerized applications that have everything they need to run in a system.

Our applications run in a multi-architecture environment, that means to run them we will need to create multi-arch Docker images.
Docker is smart enough to pull the correct image for each architecture, therefore we can run our instances on AMD64, ARM32v7, and if needed we can add more architecture support.

Our build process currently relies on `qemu-user-static` which only supports running on x86, therefore the images should be built in an x86 machine, but can be used on ARM and x86.

# Building an image

Every repository that is supposed to run as a Docker image comes with a `build.sh` script which you can run to automatically build that image for all the supported architectures (see `docker/archs`) and push them to the dockerhub.

## Not pushing the image

If you don't want to push the docker image, set `DO_NOT_PUSH` environment variable before running `build.sh`.

```bash
DO_NOT_PUSH=true ./build.sh
```

# Docker manifests and multi-arch

We have a multi-arch design, meaning that our code should be able to run on
multiple CPU architectures. That's why we make use of multi-arch manifests that
tell Docker which image to use for which architecture. When you pull an image
on an ARM machine, you won't be pulling the AMD64 files anymore.

## Creating manifest lists

In order to create a manifests list you can use the experimental `docker
manifest`. A manifests list is a list of images with the information about
which architecture is the image suitable for.

The following example shows how to create a manifests list called
`image_name:latest` using the images built for `arm64` and `amd64` CPUs.

```bash
DOCKER_CLI_EXPERIMENTAL=enabled docker manifest create image_name:latest image_name:arm64 image_name:amd64
```

In reality though, we don't use the above script for creating latest images, we
use `docker buildx` for that.

We use `docker manifest` to create version manifests, for example the following
shows how we created version `v0.1` using two images and their `sha256` code:

```
DOCKER_CLI_EXPERIMENTAL=enabled docker manifest create litcodes/rmp:v0.1 litcodes/rmp@sha256:07ac4a61cbb19e628a2f001b9f2fc65c6ab3d9c9692c4864ab6b5be6b9d3b8b6 litcodes/rmp@sha256:38b944e53eb8696c2e093e227fddeb2a64e733654561abcf73824ae35f228146
```

The manifests can then be pushed to Docker hub using the following command:

```bash
DOCKER_CLI_EXPERIMENTAL=enabled docker manifest push litcodes/rmp:v0.1
```

There is a shortcut for the above steps, simply use the `version.sh` script:

```bash
./version.sh v0.2
```

Creates a new version based on the images listed under the
`litcodes/rmp:latest` manifests list.
