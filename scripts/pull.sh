#!/bin/bash
set -e

cd "${0%/*}/../"
docker pull maximdanilov/subscity:$(git rev-parse --abbrev-ref HEAD)-latest
