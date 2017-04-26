#!/bin/sh
# Test the CI locally, using docker-compose.
set -eux
[ -d local ] || mkdir local
[ -d local/builder-ssh ] || mkdir local/builder-ssh
[ -d local/linuxkit ] || git -C local clone https://github.com/linuxkit/linuxkit.git
make docker
docker-compose build
docker-compose up
