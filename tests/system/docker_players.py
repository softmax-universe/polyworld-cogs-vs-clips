"""Protect mixed-seat action delivery and the lab players' team vocabulary.

Run after `coworld build --project coworld --version VERSION`:
    python tests/system/docker_players.py

Uses the real Coworld Docker runner, BASIC VMs, socket players, and replay writer.
"""

from __future__ import annotations

import argparse
import asyncio
import hashlib
import json
import os
import subprocess
import tempfile
from pathlib import Path


async def player() -> None:
    import websockets

    steps = 0
    async with websockets.connect(os.environ["COWORLD_PLAYER_WS_URL"]) as socket:
        config = json.loads(await socket.recv())
        assert config["protocol"] == "coworld.player.v1"
        tags = config["observation"]["tags"]
        friendly = tags.index("team:cogs")
        agent = tags.index("type:agent")
        async for raw in socket:
            message = json.loads(raw)
            if message["type"] == "final":
                assert steps == 10000
                print(f"Completed {steps} observations", flush=True)
                return
            assert message["step"] == steps
            assert [102, 6, friendly] in message["observation"]
            assert [102, 6, agent] in message["observation"]
            # A stale west action must never replace the current north action.
            for step, action in [(steps - 1, 3), (steps, 1)]:
                await socket.send(
                    json.dumps(
                        {
                            "type": "action",
                            "request_id": f"step-{step}",
                            "action_index": action,
                        }
                    )
                )
            steps += 1
    raise AssertionError("Player disconnected before final")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--player", action="store_true")
    parser.add_argument(
        "--manifest", type=Path, default=Path("coworld/dist/coworld_manifest.json")
    )
    args = parser.parse_args()
    if args.player:
        asyncio.run(player())
        return

    root = Path(__file__).resolve().parents[2]
    manifest = root / args.manifest
    assert manifest.is_file(), "Build the Coworld first"
    image = "cvc-pw-system-player:local"
    subprocess.run(
        [
            "docker",
            "build",
            "--platform",
            "linux/amd64",
            "-f",
            "tests/system/Dockerfile",
            "-t",
            image,
            ".",
        ],
        cwd=root,
        check=True,
    )
    (root / "out").mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="docker-system-", dir=root / "out"))
    policy = work / "north.bas"
    policy.write_text("act(1)\n")
    for name, socket_seats in [("files", set()), ("mixed", {0, 8, 16, 24})]:
        command = ["coworld", "run-episode", str(manifest)]
        if socket_seats:
            command.append(image)
        for slot in range(32):
            if slot not in socket_seats:
                command += ["--player-file", f"{slot}={policy}"]
        command += ["--output-dir", str(work / name), "--timeout-seconds", "600"]
        subprocess.run(
            command,
            cwd=root,
            env=os.environ | {"DOCKER_DEFAULT_PLATFORM": "linux/amd64"},
            check=True,
        )
    file_results = json.loads((work / "files/results.json").read_text())
    mixed_results = json.loads((work / "mixed/results.json").read_text())
    assert file_results == mixed_results and mixed_results["ticks"] == 10000
    assert (work / "files/replay").read_bytes() == (work / "mixed/replay").read_bytes()
    for slot in [0, 8, 16, 24]:
        assert (
            "Completed 10000 observations"
            in (work / f"mixed/logs/policy_agent_{slot}.log").read_text()
        )
    print(
        "Matching 10000-tick results and replay:",
        hashlib.sha256((work / "mixed/replay").read_bytes()).hexdigest(),
    )
    print("Artifacts:", work)


if __name__ == "__main__":
    main()
