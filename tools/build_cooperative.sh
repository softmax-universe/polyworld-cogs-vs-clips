#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p out
nim c -d:release -d:headless -d:cooperative --nimcache:out/cache-cooperative \
  -o:out/cvc-cooperative src/cvc.nim
nim c -d:release -d:headless -d:cooperative -d:coworld --nimcache:out/cache-cooperative-hosted \
  -o:out/cvc-cooperative-hosted src/cvc.nim
