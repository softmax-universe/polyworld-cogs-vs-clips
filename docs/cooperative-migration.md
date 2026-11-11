# Cooperative league migration

Status: implemented preparation, pending qualification and hosted certification. No production league has changed.
The disabled [settings](../coworld/cooperative-league.settings.json) contain no division IDs and are not a cutover payload.

## Preserved league behavior

- Eight independently submitted Cogs cooperate against automated Clips for 10,000 ticks.
- All eight receive the same mean held-junction count across the episode.
- Daily geometry varies independently of simulation randomness.
- BASIC, tensor ZIP, and qualified container policies can share an episode.
- FourScore remains a separate 32-seat, four-team build with its fixed map.

The cooperative generator produces an 88×88 arena with a central compound, four Clips roots,
junctions, resources, and connected corridors. Clips start expanding at tick 100 and repeat every 200 ticks.
This is a Polyworld adaptation, not the original Python map generator or exact MettaGrid simulation parity.
Qualification must assess the resulting gameplay before moving the official league.

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
automatic daily variation requires deploying the companion planner change before enabling this league.

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

The existing reference-player Docker image completed a full match alongside seven BASIC players.
That verifies the published wire exchange, not the behavior of imported champion policies.
For each imported policy, run all eight positions across multiple daily maps with frozen teammates and seeds.
Record crashes, action distribution, score, runtime, and paired changes; reject incomplete suites.

## Build and verify

Install the pinned dependencies, then build using Nim 2.2.10:

```sh
python3 tools/setup_dependencies.py
export POLYWORLD_DEPS="$PWD/.deps"
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
belongs to `coworld-cogs-vs-clips`, which pins this repository as a source dependency.
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

## Release gates

1. Merge this game-local host and the Observatory daily-map planner, then update the shared Coworld's game-source pin.
   The engine dependency uses unchanged Polyworld main; no shared transport PR is required.
2. Review the adapted map distribution, Clips behavior, and 74-feature observation semantics with the game owners.
3. Qualify all imported policy images; retain per-policy failures instead of claiming blanket compatibility.
4. Build the cooperative image and viewer; validate the final manifest and certify real all-file, all-container, and mixed rosters.
5. Run a real local Observatory round through Postgres, object storage, Kubernetes, and settlement, including worker restart.
6. Run a fresh hosted mixed episode before enabling a new division and score season. Obtain owner approval for the official switch.

The current preparation has native/browser and cached-Docker evidence. Full local hosted-stack certification is outstanding.
No source league is archived, resumed, repointed, or enrolled by these files.

## Prior lab-container evidence

[The retained verification record](docker-verification.json) describes the earlier non-canonical `0.1.6rc2` candidate,
not a certification of this consolidated source. Its immutable source and image hashes remain unchanged.
Doug's v5 and Hananel's v11 uploads completed 32 container runs of 10,000 observations across two FourScore matches,
alongside BASIC and neural file policies. All 16 Hananel runs reported zero step gaps.
Those runs established the named observation vocabulary and protocol fixes carried into this host.
They did not qualify cooperative maps, all imported policies, or MettaGrid-equivalent rankings.

Before release, rebuild and certify the consolidated source and repeat unchanged lab-image matches in both modes.
Update the game pin in `coworld-cogs-vs-clips` only after this follow-up merges; retain separate variant standings.
The closed PW #2 and Polyworld #115 branches preserve the earlier implementation and evidence.
