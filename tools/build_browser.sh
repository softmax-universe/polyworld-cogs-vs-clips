#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mode=${1:-fourscore}
case "$mode" in
  fourscore) define=; output=out/browser ;;
  cooperative) define=-d:cooperative; output=out/browser-cooperative ;;
  *) echo "Expected fourscore or cooperative" >&2; exit 1 ;;
esac
mkdir -p "$output"
nim c $define -d:release -d:emscripten --threads:off \
  --nimcache:out/cache-browser-$mode -o:$output/cvc.js src/cvc.nim
python3 - "$output" "$mode" <<'PYBUILD'
import sys
from pathlib import Path
from hashlib import sha256
output = Path(sys.argv[1])
version = sha256((output / 'cvc.wasm').read_bytes()).hexdigest()[:16]
html = Path('tools/browser.html').read_text().replace('__BUILD_ID__', version)
cooperative = sys.argv[2] == 'cooperative'
html = html.replace('__MAP_ARGUMENTS__', "['--map-seed',query.get('map_seed')||'1']" if cooperative else '[]')
if cooperative:
    html = html.replace('FourScore', 'Cooperative Cogs vs Clips')
(output / 'index.html').write_text(html)
PYBUILD
