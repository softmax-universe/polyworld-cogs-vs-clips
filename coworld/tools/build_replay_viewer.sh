#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
mode=${2:-fourscore}
case "$mode" in
  both) ./tools/build_browser.sh fourscore; ./tools/build_browser.sh cooperative ;;
  fourscore|cooperative) ./tools/build_browser.sh "$mode" ;;
  *) echo "Expected fourscore, cooperative, or both" >&2; exit 1 ;;
esac
python3 coworld/tools/package_viewer.py "$1" "$mode"
