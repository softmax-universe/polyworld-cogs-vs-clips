"""Real game/WS/replay flow: mixed seats must preserve actions and private outputs.

Run with Python providing websockets, after tools/build_cooperative.sh (add --fourscore for the 32-seat build):
    python tests/system/cooperative_hosted.py
"""

import asyncio
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import websockets

ROOT = Path(__file__).resolve().parents[2]
COOPERATIVE = "--fourscore" not in sys.argv
SEATS = 8 if COOPERATIVE else 32
HOSTED = ROOT / ("out/cvc-cooperative-hosted" if COOPERATIVE else "out/cvc-hosted")
NATIVE_GAME = ROOT / ("out/cvc-cooperative" if COOPERATIVE else "out/cvc-headless")
NAMES = ["noop", "move_north", "move_south", "move_west", "move_east"]
NATIVE = [0, 1, 3, 4, 2]


async def run_case(
    directory: Path, remote: set[int], failure: str = "", docker_reference: bool = False
) -> None:
    directory.mkdir()
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    player_names = [{"name": f"Cog {slot}"} for slot in range(SEATS)]
    config = {
        "tokens": [f"secret-{slot}" for slot in range(SEATS)],
        "players": player_names,
        "seed": 42,
        "map_seed": 20261110,
        "max_ticks": 10000,
    }
    if not COOPERATIVE:
        del config["map_seed"]
    roster = []
    native_args: list[str] = []
    for slot in range(SEATS):
        source = directory / f"player-{slot}.bas"
        source.write_text(
            f'print "private-{slot}"\nact({(0 if docker_reference and slot in remote else NATIVE[slot % 5])})\n'
        )
        native_args.append(f"--bots:{source}:1")
        if slot in remote:
            roster.append({"slot": slot, "kind": "container"})
        else:
            if failure == "basic" and slot == 2:
                source.write_text("this is invalid BASIC")
            roster.append(
                {
                    "slot": slot,
                    "kind": "policy",
                    "file_uri": source.as_uri(),
                    "content_hash": "",
                    "size_bytes": source.stat().st_size,
                    "log_uri": (directory / f"private-{slot}.log").as_uri(),
                    "artifact_uri": (directory / f"artifact-{slot}.zip").as_uri(),
                }
            )
    (directory / "config.json").write_text(json.dumps(config))
    (directory / "seats.json").write_text(
        json.dumps(
            {
                "schema": "coworld-play-seats/2",
                "seats": roster,
                "player_status_uri": (directory / "status.json").as_uri(),
            }
        )
    )
    env = dict(os.environ, COGAME_PORT=str(port), COGAME_HOST="127.0.0.1")
    env["CVC_VIEWER_DIR"] = str(ROOT / ("out/browser-cooperative" if COOPERATIVE else "out/browser"))
    for key, filename in [
        ("CONFIG", "config.json"),
        ("PLAYER_SEATS", "seats.json"),
        ("RESULTS", "results.json"),
        ("SAVE_REPLAY", "episode.replay"),
        ("PLAYER_FAILURE", "failure.json"),
    ]:
        env[f"COGAME_{key}_URI"] = (directory / filename).as_uri()
    with (directory / "game.log").open("w") as log:
        process = await asyncio.to_thread(
            subprocess.Popen,
            [HOSTED],
            env=env,
            stdout=log,
            stderr=log,
        )
        try:
            deadline = time.monotonic() + 120
            async with asyncio.timeout(120):
                while True:
                    assert process.poll() is None, (directory / "game.log").read_text()
                    # A real TCP connection avoids startup sleeps tied to machine speed.
                    ready = await asyncio.to_thread(
                        subprocess.run,
                        [
                            "curl",
                            "--silent",
                            "--fail",
                            f"http://127.0.0.1:{port}/healthz",
                        ],
                        capture_output=True,
                    )
                    if ready.returncode == 0:
                        break
                    await asyncio.sleep(0.01)

                async def spectator() -> list[bytes]:
                    snapshots = []
                    async with websockets.connect(f"ws://127.0.0.1:{port}/global", max_size=2**22) as ws:
                        while not (directory / "results.json").exists():
                            packet = await ws.recv()
                            if isinstance(packet, bytes):
                                assert b"secret-" not in packet and b"private-" not in packet
                                if not snapshots or snapshots[-1] != packet:
                                    snapshots.append(packet)
                            else:
                                assert json.loads(packet) == {"type": "waiting"}, "Missing live tape protocol"
                            await asyncio.sleep(0.1)
                            await ws.send("snapshot")
                    # Reconnect without cursor state and recover the final authoritative tape.
                    async with websockets.connect(f"ws://127.0.0.1:{port}/global", max_size=2**22) as ws:
                        final = await ws.recv()
                        assert final == (directory / "episode.replay").read_bytes()
                    if remote:
                        assert len(snapshots) >= 2, "spectator never saw the running game advance"
                        partial = directory / "live.replay"
                        partial.write_bytes(snapshots[1])
                        played = await asyncio.to_thread(subprocess.check_output,
                            [str(NATIVE_GAME), "--replay:" + str(partial)], text=True)
                        assert "tick=0 " not in played and "tick=10000 " not in played
                    return snapshots

                watching = asyncio.create_task(spectator()) if not failure else None

                async def player(slot: int) -> None:
                    url = (
                        f"ws://127.0.0.1:{port}/player?slot={slot}&token=secret-{slot}"
                    )
                    async with websockets.connect(url) as ws:
                        configured = json.loads(await ws.recv())
                        assert (
                            configured["type"] == "player_config"
                            and configured["slot"] == slot
                        )
                        assert configured["policy_env"]["num_agents"] == SEATS
                        assert configured["action_names"] == NAMES
                        assert len(configured["policy_env"]["obs_features"]) == 74
                        friendly = configured["policy_env"]["tags"].index("team:cogs")
                        if slot == min(remote):
                            duplicate = await asyncio.to_thread(
                                subprocess.check_output,
                                [
                                    "curl",
                                    "--silent",
                                    "--output",
                                    os.devnull,
                                    "--write-out",
                                    "%{http_code}",
                                    url.replace("ws://", "http://"),
                                ],
                                text=True,
                            )
                            assert duplicate == "409"
                        for step in range(10000):
                            message = json.loads(await ws.recv())
                            assert (
                                message["type"] == "observation"
                                and message["step"] == step
                            )
                            assert (
                                message["slot"] == slot
                                and len(message["observation"]) == 500
                            )
                            own_tags = {
                                value
                                for location, feature, value in message["observation"]
                                if location == 102 and feature == 6
                            }
                            assert friendly in own_tags, (slot, step, own_tags)
                            if step % 100 == 0:
                                await ws.send(
                                    json.dumps(
                                        {
                                            "type": "action",
                                            "request_id": f"step-{step - 1}",
                                            "action_index": (slot + 1) % 5,
                                        }
                                    )
                                )
                            action: dict[str, str | int] = {
                                "type": "action",
                                "request_id": f"step-{step}",
                            }
                            if failure == "json":
                                await ws.send("{malformed")
                                return
                            if failure == "action":
                                action["action_index"] = 99
                                await ws.send(json.dumps(action))
                                return
                            if step % 2:
                                action["action_name"] = NAMES[slot % 5]
                            else:
                                action["action_index"] = slot % 5
                            await ws.send(json.dumps(action))
                        final = json.loads(await ws.recv())
                        assert final["type"] == "final" and final["step"] == 10000

                if remote and failure != "basic":
                    bad = f"ws://127.0.0.1:{port}/player?slot={min(remote)}&token=wrong"
                    rejected = await asyncio.to_thread(
                        subprocess.check_output,
                        [
                            "curl",
                            "--silent",
                            "--output",
                            os.devnull,
                            "--write-out",
                            "%{http_code}",
                            bad.replace("ws://", "http://"),
                        ],
                        text=True,
                    )
                    assert rejected == "403"
                    if docker_reference:
                        assert remote == {7}
                        completed = await asyncio.to_thread(
                            subprocess.run,
                            [
                                "docker",
                                "run",
                                "--rm",
                                "--platform",
                                "linux/amd64",
                                "--env",
                                f"COWORLD_PLAYER_WS_URL=ws://host.docker.internal:{port}/player?slot=7&token=secret-7",
                                "coworld-cogs-vs-clips-reference-player:latest",
                            ],
                            capture_output=True,
                            text=True,
                            timeout=120,
                        )
                        assert completed.returncode == 0, completed.stderr
                    else:
                        await asyncio.gather(*(player(slot) for slot in sorted(remote)))
                marker = directory / ("failure.json" if failure else "results.json")
                while not marker.exists():
                    assert process.poll() is None, (directory / "game.log").read_text()
                    assert time.monotonic() < deadline
                    await asyncio.sleep(0.01)
                if watching is not None:
                    await watching
                result = json.loads(marker.read_text())
                statuses = json.loads((directory / "status.json").read_text())[
                    "players"
                ]
                assert {row["slot"] for row in statuses} == set(range(SEATS)) - remote
                assert "private-" not in (directory / "game.log").read_text()
                if failure:
                    assert result["failed_policy_index"] == (
                        2 if failure == "basic" else min(remote)
                    )
                    assert not (directory / "results.json").exists()
                else:
                    assert result["ticks"] == 10000 and len(result["scores"]) == SEATS
                    timings = [
                        json.loads(line)
                        for line in (directory / "game.log").read_text().splitlines()
                        if line.startswith('{"event":"player_timing"')
                    ]
                    assert {
                        row["slot"] for row in timings if row["actions"] == 10000
                    } == remote
                    assert all(
                        0 <= row["maximum_reply_wait_ms"] <= row["reply_wait_ms"]
                        for row in timings
                    )
                    for first in range(0, SEATS, 8):
                        assert len(set(result["scores"][first : first + 8])) == 1
                    replay_bytes = (directory / "episode.replay").read_bytes()
                    for name in player_names:
                        assert name["name"].encode() in replay_bytes
                    replay = await asyncio.to_thread(
                        subprocess.check_output,
                        [
                            str(NATIVE_GAME),
                            "--replay:" + str(directory / "episode.replay"),
                        ],
                        text=True,
                    )
                    expected = await asyncio.to_thread(
                        subprocess.check_output,
                        [
                            str(NATIVE_GAME),
                            "--seed:42",
                            *(["--map-seed:20261110"] if COOPERATIVE else []),
                            *native_args,
                        ],
                        text=True,
                    )
                    assert replay == expected, (replay, expected)
                    for slot in set(range(SEATS)) - remote:
                        private = (
                            (directory / f"private-{slot}.log").read_text().splitlines()
                        )
                        assert f"private-{slot}" in private
                        assert all(
                            f"private-{other}" not in private
                            for other in range(SEATS)
                            if other != slot
                        )
                    assert all(
                        not (directory / f"private-{slot}.log").exists()
                        for slot in remote
                    )
        finally:
            process.terminate()
            process.wait(timeout=10)
    print("PASS", directory.name, flush=True)


async def main() -> None:
    directory = Path(tempfile.mkdtemp(prefix="cvc-hosted-system-"))
    print("Evidence:", directory, flush=True)
    if "--docker-reference" in sys.argv:
        await run_case(directory / "docker-reference", {7}, docker_reference=True)
        return
    await run_case(directory / "all-files", set())
    await run_case(directory / "mixed", {1, 3, 5, 7})
    await run_case(directory / "all-containers", set(range(SEATS)))
    await run_case(directory / "invalid-basic", {1}, "basic")
    await run_case(directory / "invalid-action", {1}, "action")
    await run_case(directory / "invalid-json", {1}, "json")


if __name__ == "__main__":
    asyncio.run(main())
