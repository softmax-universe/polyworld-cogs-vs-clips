"""Package compiled viewers for standalone or downstream Coworld builds."""

import shutil
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[2]
output = Path(sys.argv[1]).resolve()
mode = sys.argv[2] if len(sys.argv) > 2 else "fourscore"
builds = {"fourscore": "out/browser", "cooperative": "out/browser-cooperative"}
if mode == "both":
    output.mkdir(parents=True, exist_ok=False)
    for name, source in builds.items():
        shutil.copytree(root / source, output / name)
    shutil.copytree(root / "coworld/viewer", output, dirs_exist_ok=True)
else:
    shutil.copytree(root / builds[mode], output)
