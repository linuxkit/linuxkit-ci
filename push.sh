#!/bin/bash -eux
set -eux
LOCAL_DOCKER="DOCKER_HOST=unix:///var/run/docker.sock DOCKER_TLS_VERIFY="
make docker $LOCAL_DOCKER
env $LOCAL_DOCKER docker push linuxkitci/ci
IMAGE=$(env $LOCAL_DOCKER docker image inspect linuxkitci/ci -f '{{index .RepoDigests 0}}')
docker service update linuxkit_ci --image $IMAGE
