#!/bin/bash
set -eux
cd $(dirname $0)
docker stack deploy linuxkit --with-registry-auth -c prod.yml
