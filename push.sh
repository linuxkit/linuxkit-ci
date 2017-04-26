#!/bin/bash -eux
set -eux
make docker DOCKER_HOST=unix:///var/run/docker.sock
docker -H unix:///var/run/docker.sock push linuxkitci/ci
IMAGE=$(docker -H unix:///var/run/docker.sock image inspect linuxkitci/ci -f '{{index .RepoDigests 0}}')
docker service update linuxkit_ci --image $IMAGE
