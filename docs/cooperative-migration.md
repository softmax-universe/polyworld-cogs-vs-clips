# Cooperative league migration

The canonical [Cogs vs Clips](https://softmax.com/cogs-vs-clips) Coworld publishes both Polyworld modes.
[Cooperative](https://softmax.com/cogs-vs-clips/cooperative) uses daily maps and team scores;
[FourScore](https://softmax.com/cogs-vs-clips/fourscore) uses four teams on the fixed map.
The [settings fixture](../coworld/cooperative-league.settings.json) is a disabled authoring example, not live configuration.

## Preserved league behavior

- Eight independently submitted Cogs cooperate against automated Clips for 10,000 ticks.
- All eight receive the same mean held-junction count across the episode.
- Daily geometry varies independently of simulation randomness.
- BASIC, tensor ZIP, and qualified container policies can share an episode.
- FourScore remains a separate 32-seat, four-team build with its fixed map.

The cooperative generator produces an 88×88 arena with a central compound, four Clips roots,
junctions, resources, and connected corridors. Gameplay version 5 restores the original
21×21 compound at (43,43): four five-wide gates, a three-tile clear apron,
four corner extractors, the southern gear row, and cardinal spawn pads.
Seeded triangular edge cuts follow MettaGrid's AsteroidMask dimensions. Outer
buildings and station placements remain the independent Polyworld generator.
Previously published Coworlds retain their immutable version-4 replay viewers.
Clips start expanding at tick 100 and repeat every 200 ticks.
This is a Polyworld adaptation, not the original Python map generator or exact MettaGrid simulation parity.
Policy qualification must assess the resulting gameplay; protocol compatibility alone does not establish strategic parity.

## Why the league needs different ratings

Cooperative teammates receive equal scores within an episode. Within-episode Elo supplies draws, not evidence of individual contribution.

Use the prepared **Team score** board: random balanced rotation, at least eight appearances per entrant,
mean team score per round, and the latest completed round as the displayed standing.
Participation balance does not guarantee identical teammates or all eight positions for every entrant.
This measures observed team outcomes, not isolated individual skill. Preserve the old ratings and replays as history.

The configuration requires full round fulfillment, allows two retries, and uses registered fillers for empty seats.
Choose round cadence and budget after measuring container startup, full matches, and paired evaluations.

Use the platform's paired counterfactual evaluations for policy updates after collecting compatible new-engine history.
Freeze the Coworld version, map, simulation seed, seat, and seven teammate policy versions; replace only the focal policy.
Report complete-pair count, mean change, and wins/ties/losses. Do not compare against old-engine rewards.
The automated check does not rerun both arms or remove stochastic inference variance.

## Daily map contract

The companion Observatory change adds `ladder.scheduler.daily_map_seed: true`.
At planning, `map_seed` becomes the round creation date in UTC, expressed as integer `YYYYMMDD`.
Every episode in that round receives the same map seed. The planner persists it with the episode configuration.
A round created before midnight keeps its map through late planning, execution, retries, and paired evaluations.
Simulation `seed` remains independent. The simulator never reads the clock.

Cooperative hosted games require an explicit signed 32-bit `map_seed`.
Replays carry that seed, a source-derived content hash, map fingerprint, actions, and per-tick hashes.
The viewer rejects mismatched rules or maps. The manifest's dated map is a reproducible preview fixture;
the live platform planner supplies daily variation.

## Mixed policies and old containers

The game-owned host in `src/cvc/coworldhost.nim` accepts `coworld-play-seats/2` with explicit `policy`, `container`, or `human` seat kinds.
Only file seats are loaded into BASIC runtimes. The platform still owns container launch, resources, secrets, and logs.
The game authenticates `/player?slot=N&token=TOKEN`, rejects duplicates, waits up to 300 seconds for connections,
and allows 30 seconds for each action. All seats decide against the same pre-tick world.
Malformed messages and invalid actions produce an attributed player failure; file logs remain private per seat.

Both game modes use one container adapter speaking the original `coworld.player.v1` exchange:
`player_config`, sparse 500×3 observations, action replies, and final results.
Its 74-feature metadata comes from the ordinary Machina interface. Vibe actions are unsupported.
The explicit observation contract is `polyworld-machina-74/v1`.
Every Docker observer sees its own team as Cogs and opponents as Clips, including all four FourScore corners.
The projection includes visible bank and hub-heart stocks and keeps globals and nearby objects before truncating to 500 tokens.
Cooperative ships retain their lane tags. The simulator still owns all rules and scores.
A nonempty action `request_id` must match `step-N`; stale replies are discarded within the same bounded action deadline.
Actions without a request ID use the existing one-action-per-observation exchange.
Actions map by name: noop/north/south/west/east correspond to native rest/north/south/west/east,
whose numeric order differs. Both action names and indices are exercised by the system test.

Feature IDs and tags match ordinary Machina, but values, object ordering, truncation, and game dynamics are reconstructed.
The existing FourScore dense tensor view remains 134 features. Do not describe either interface as universal checkpoint parity.
Human transport is available, but this preparation does not supply a browser control client for remote human seats.

Keep a private migration inventory of policy versions, artifact references, environment configuration, and qualification outcomes.
Preserve those references during enrollment; do not copy secret values into a manifest or convert weights merely to enroll containers.
Each imported policy remains unqualified until its actual image completes the new-engine suite.

Release certification runs the reference Docker player alongside seven BASIC players.
That verifies the published wire exchange; imported champions require their own qualification.
For each imported policy, run all eight positions across multiple daily maps with frozen teammates and seeds.
Record crashes, action distribution, score, runtime, and paired changes; reject incomplete suites.

## Build and verify

Resolve the dependencies, then build using Nim 2.2.10:

```sh
python3 tools/setup_dependencies.py
export POLYWORLD_DEPS="$PWD/.deps"
export POLYWORLD_REVISION="$(git -C "$POLYWORLD_DEPS/polyworld" rev-parse HEAD)"
./tools/build_cooperative.sh
./out/cvc-cooperative --seed 42 --map-seed 20261110 --record out/cooperative.replay
./tools/build_browser.sh cooperative
python3 -m http.server 8128 --directory out/browser-cooperative
```

Open `http://localhost:8128/?seed=42&map_seed=20261110`. Pass another explicit date for a different preview map.
Package the cooperative viewer with
`coworld/tools/build_replay_viewer.sh coworld/dist/replay-viewer cooperative`.
Use [the cooperative manifest template](../coworld/cooperative_manifest_template.json) and
`docker compose -f coworld/compose.cooperative.yaml build` for the cooperative image.
The ordinary compose file and template build FourScore with mixed-policy support.
These manifests are standalone qualification fixtures. The shared release manifest
belongs to `coworld-cogs-vs-clips`, which tracks this repository's `main` branch.
Resolve `{{GAME_IMAGE}}` during normal Coworld packaging.

To package both decoders for downstream use, run
`coworld/tools/build_replay_viewer.sh /absolute/new/bundle both`.
The output must not exist. Its entry point reads the replay header and selects
cooperative CvC or FourScore; unsupported game/version headers fail visibly.
The exported `replayMode(url)` in `route.js` also lets the downstream viewer
route MettaGrid replays to its own renderer without copying Polyworld decoding rules.

System verification:

```sh
python tests/system/cooperative_hosted.py
# Requires the original reference-player image in the local Docker cache:
python tests/system/cooperative_hosted.py --docker-reference
nim c -r -d:release -d:headless -d:cooperative --path:src \
  -o:out/cooperative-system tests/system/cooperative_replay.nim
```

The hosted suite runs real server processes and WebSocket clients, checks full replay agreement,
private file logs, authentication, duplicate connections, stale replies, friendly-team vocabulary, malformed actions, and attributed failures.
The replay suite runs three full daily-map matches and checks map connectivity and seeking.
Native and WebAssembly outputs matched for all 30,000 ticks. The previously published FourScore replay also retained its final hash and scores.

## Release and policy qualification

The shared Coworld repository owns release packaging and league-facing documentation.
Its build follows this repository and Polyworld `main`, resolves revisions once, and
records exact source hashes with immutable images and replay viewers.

For each release:

1. Run the native/browser replay suites and real hosted mixed-seat system tests.
2. Certify the shared Coworld and exercise both variants at the full 10,000 ticks.
3. Qualify changed container policies across daily maps or all four FourScore corners.
4. Verify completed hosted rounds and decode their replays before retiring a predecessor.

Keep old league results and immutable replay viewers. New engines and formats need
separate standings; do not merge historical MettaGrid scores into Polyworld rankings.
Record qualification evidence outside the source tree rather than committing workflow histories.

## Container runtime diagnostics

Use explicit CPU requests and limits, with inference thread pools sized to the allocation.
The shared [reference player and upload guide](https://github.com/softmax-universe/coworld-cogs-vs-clips/blob/main/coworld/game/docs/player_protocol_spec.md#cpu-player-defaults)
uses one CPU and one inference thread. Measure multiple concurrent containers, not
only an isolated process. Models and their original ownership remain unchanged when
publishing a separately attributed runtime repair.

Every 1,000 actions, the game emits one `player_timing` JSON record per remote seat:
`slot`, `step`, `actions`, cumulative `reply_wait_ms`, and `maximum_reply_wait_ms`.
The interval starts before sending the observation and ends when transport receives
the valid reply. It includes network and worker scheduling delays, but excludes game
event-queue delay. It is not CPU time. No private payloads are logged.

Use the episode roster to map slots to policies. A 30-second action deadline emits
`player_action_timeout` and an attributed player failure. Timing telemetry does not
change deadlines, rankings, or game rules; cumulative slow responses can still exhaust
the platform's episode deadline.
