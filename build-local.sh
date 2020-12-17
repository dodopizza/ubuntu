#!/bin/bash
set -eu

docker build --pull --cache-from ubuntu-test --rm -f "Dockerfile" -t ubuntu-test "."
docker run -it --rm ubuntu-test