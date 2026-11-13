# Poly World CVC

A standalone Nim FourScore game with four teams of eight Cogs, a fixed
120 by 120 map, and 10,000-tick matches. The simulation
uses integer state and Poly World action tapes. Native and browser clients
share the same simulation and copied CoGames 2D sprites.

The cooperative build adds eight Cogs against automated Clips, daily seeded maps,
and mixed BASIC/container seats. See [league and qualification guide](docs/cooperative-migration.md)
for builds, policy qualification, league settings, and release gates.
The existing [Cogs vs Clips Coworld](https://github.com/softmax-universe/coworld-cogs-vs-clips)
consumes this repository from its `main` branch. That repository owns the
shared manifest, league variants, release packaging, and legacy MettaGrid runtime.
This repository owns Polyworld rules, policy adaptation, native builds, and viewers.
Both Polyworld modes are deployed through that shared Coworld; the original
MettaGrid variants and historical recordings remain available.

## Run

With the sibling dependencies already installed in `/Users/me/p`:

```sh
./tools/build_native.sh
./out/cvc --seed 1
./out/cvc-headless --seed 1 --record out/match.replay
./out/cvc --replay out/match.replay
```

Run commands from this repository. For an independent checkout, install
Nim 2.2.10 or newer, then fetch dependencies (`polyworld` follows `main`):

```sh
python3 tools/setup_dependencies.py
export POLYWORLD_DEPS="$PWD/.deps"
./tools/build_native.sh
```

The setup script uses its own dependency directory and leaves sibling
repositories alone. Each run refreshes Polyworld and records exact revisions in
`.deps/dependencies.lock`. Set `POLYWORLD_REVISION` to a commit when reproducing a
release. Docker requires this build argument, resolved to a commit, so its cache
refreshes when Polyworld changes. Export the revision from
`git -C "$POLYWORLD_DEPS/polyworld" rev-parse HEAD` before standalone Compose builds. Other Nim library revisions and
compiler versions remain fixed. Emscripten is required for the browser build:

```sh
./tools/build_browser.sh
python3 -m http.server 8128 --bind 127.0.0.1 --directory out/browser
```

Open `http://127.0.0.1:8128`. Add `?seed=42` to change simulation randomness.
The current map geometry stays fixed.

## Play and inspect

- Click a Cog or roster entry to select it, and a station to inspect it.
- Scroll to zoom, right-drag to pan, or click the minimap to navigate.
- Click Control to take over the selected Cog. Use WASD or arrow keys.
- Move into stations to gather, deposit, equip, obtain hearts, or capture.
- Space pauses and the period key advances one tick.
- The HUD scales automatically for embedded replays. Ctrl/Cmd +/− changes its
  scale, Ctrl/Cmd 0 restores automatic sizing, and F11 toggles fullscreen.
  Manual scale preferences persist; changing UI scale does not change camera zoom.
- Save replay writes a file on native and downloads it in the browser.
- Watch tape switches the current recording to read-only playback.
- Click the timeline to seek in playback. Drop a replay onto the client to load it.

One simulation tick is a grid turn. Display interpolation, camera movement,
and playback speed never change simulation results.

## Policies

`--bot players/base.bas` supplies a BASIC program to 32 independent policy
runtimes. Programs can use `self(0)` to specialize by seat. See
[the policy interface](docs/policies.md) for observation and action functions.
The bundled baseline is intentionally simple and uses remembered local vision.

## PufferLib training

Training runs the compiled Nim simulation directly and uses PyTorch for neural
inference and PufferLib PPO. It does not run the learned policy through BASIC.
The simulation rules and official scores stay unchanged.

Use a Python environment with the dependencies in `training/requirements.txt`.
PufferLib's native advantage extension must be built against the installed
Torch version. See [training setup](docs/training.md) for the tested versions.
After installing the Nim dependencies above, run from this repository:

```sh
sh tools/build_training.sh
python tools/train_safa.py --seconds 600 --output out/safa-train
```

This trains Safa's CNN/LSTM from scratch with the active FourScore curriculum:
per-team generalist and idle roles, individual reward shaping, random idle
actions, and idle-agent loss masking. CPU is the default. `--device cuda`
selects GPU learning on a compatible machine. GPU execution has not been
validated here.

Use a new output directory for each run. It contains initial weights, final
model and optimizer checkpoints, metrics, source snapshots, and `summary.json`.
Training stops at the first of `--seconds` or `--steps`, after finishing the
current update. `--checkpoint PATH` loads weights with a fresh optimizer, not
an exact training resume.

Evaluate the checkpoint path recorded in `summary.json` against `base.bas`:

```sh
python tools/evaluate_safa_training.py PATH_TO_MODEL.pt \
  --output out/safa-train/evaluation.json
```

Evaluation plays four full games with eight neural cogs against 24 baseline
cogs, rotating the neural team through the corners. Evaluate `initial.pt` with
the same settings to compare before and after training.

A smaller MLP baseline is also available:

```sh
python tools/train_puffer.py --seconds 600 --evaluate --output out/puffer-train
```

The 10-minute CPU curriculum test completed 663,552 agent steps and 648 PPO
updates. It scored zero in all four held-out games, so it did not demonstrate
useful learned play. See [curriculum details and results](docs/safa-curriculum.md)
and [Safa's training notes](docs/safa-training-research.md) for the source recipe
and the port's observation differences.

## Validation

```sh
./tools/verify.sh
nim r -d:release tests/bench_matches.nim
```

Verification checks rules, replay corruption and seeking, native to WebAssembly
replay compatibility, and every tick hash across three complete native and
WebAssembly matches. The browser and native builds do not need Python at runtime.

## Rules and provenance

See [the fixed rules](docs/rules.md) and [asset provenance](docs/provenance.md).
This is a standalone adaptation, not a drop-in MettaGrid replacement. Its compact
map generator and deterministic resolution order define a new replay version.
It does not reproduce original Python map seeds, policies, or replay files.

## Live spectating

Hosted Cooperative and FourScore games serve their matching WebAssembly viewer
at `/client/global`. `/global` accepts read-only spectator WebSockets; the
platform-provided `address` query parameter preserves proxy routing. Player
sockets remain separately authenticated at `/player`.

Spectators receive the ordinary replay envelope as a binary snapshot on connect
and in response to `snapshot`. The game publishes at most once per second plus
initial/final state. One bounded current tape is retained, so slow or disconnected
viewers do not block the simulation or accumulate tick queues. Snapshots contain
public match names and actions, never player tokens or private logs.

The viewer verifies each appended tape against the same rules and hashes as
completed replays. Late joins and reconnects recover from the current tape;
pause/seek remains read-only, and Play catches up to the live edge. Waiting and
reconnecting states preserve the last rendered game. Completed recordings keep
their existing file format and ordinary replay controls.

Local hosted checks require the matching browser build (`./tools/build_browser.sh
cooperative`, or `fourscore`). `CVC_VIEWER_DIR` selects that build directory when
launching the native host; Docker includes the matching assets at `/app/viewer`.
Run `python tests/system/cooperative_hosted.py` (also `--fourscore`) to verify
mixed player execution, live progress, reconnect, and final replay equality.

Combined replay bundles retain the exact Cooperative v4 viewer shipped in Coworld
0.2.49. Its action tapes encode different rules from v5 and must use their original
simulation. `coworld/retained-viewers.json` pins the source revision, published
bundle, and asset checksums; packaging downloads and verifies those immutable
assets. The header router selects the matching reader. Future rules changes must
retain readers for published tapes before replacing the current viewer.
