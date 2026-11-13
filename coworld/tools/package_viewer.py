"""Package compiled viewers for standalone or downstream Coworld builds."""

import hashlib
import json
import shutil
import subprocess
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
    # Stored action tapes require the simulation that originally produced them.
    retained = json.loads((root / "coworld/retained-viewers.json").read_text())
    for name, release in retained.items():
        directory = output / name
        directory.mkdir()
        for filename, expected in release["files"].items():
            path = directory / filename
            subprocess.run(
                ["curl", "--fail", "--silent", "--show-error", "--location",
                 release["base_url"] + filename, "--output", str(path)],
                check=True,
            )
            actual = hashlib.sha256(path.read_bytes()).hexdigest()
            if actual != expected:
                raise ValueError(f"Retained viewer checksum mismatch: {name}/{filename}")
    shutil.copytree(root / "coworld/viewer", output, dirs_exist_ok=True)
else:
    shutil.copytree(root / builds[mode], output)
