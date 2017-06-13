#!/bin/bash
set -eux
mkdir -p /tmp/build/test/_results /tmp/build/artifacts
sysctl vm.overcommit_memory=1
