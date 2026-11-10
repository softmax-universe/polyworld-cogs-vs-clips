#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
./tools/build_browser.sh "${2:-fourscore}"
python3 coworld/tools/package_viewer.py "$1" "${2:-fourscore}"
