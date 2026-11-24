#!/bin/bash
set -e
cd "$(dirname "$0")"

./build-libogg.sh
./build-libopus.sh
./build-libopusenc.sh
./build-libopusfile.sh