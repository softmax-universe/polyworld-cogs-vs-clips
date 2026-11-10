# Docker players

PW accepts BASIC/tensor files and Docker players in the same 32-seat match.
The game still runs the fixed 10,000-tick FourScore rules. Docker execution does
not convert PW into MettaGrid or preserve the original league's scores.

## Connection and actions

Connect to `COWORLD_PLAYER_WS_URL`, supplied by the runner. It includes the
seat and token. A seat accepts one connection. Invalid credentials return 403;
a second connection returns 409. File seats do not accept socket connections.

The first message is `player_config`, with protocol `coworld.player.v1`, mission
`four_score`, `policy_env`, observation metadata, and the five action names:

| Index | Name | PW action |
| --- | --- | --- |
| 0 | `noop` | Rest |
| 1 | `move_north` | North |
| 2 | `move_south` | South |
| 3 | `move_west` | West |
| 4 | `move_east` | East |

Every `observation` contains a step, 500 `[location, feature, value]` tokens,
and current team scores in seat order. Reply with `type: action` and either
`action_index` or `action_name`. An optional `request_id: step-N` rejects late
responses. Without it, the next action applies to the outstanding observation.
Only one response is accepted per step. The terminal message is `final`.

The game waits 120 seconds for players to connect, then allows one second for
all container responses each tick. Invalid actions, disconnection, or expiry
stop the episode with the responsible seat's failure marker. Container logs
remain runner-owned; BASIC logs remain game-owned. Human control is not implemented.

## Observation projection

`data/protocols/machina_compat.json` records the named 74-feature interface from
`coworld-cogs-vs-clips` revision `d559d2ae21aa56633941700cfd135ecff3416c1d`,
using MettaGrid 0.26.21 and `make_env("machina_1", num_agents=8,
max_steps=10000, seed=1)`. `PolicyEnvInterface.from_mg_cfg` generated the metadata.
PW sets `num_agents` to 32 and disables vibe actions and talk. It retains
the original five movement actions.

`mettagridview.nim` projects PW's visible state into that interface. Globals use
location 254; padding uses 255. Spatial tokens use a 13×13 egocentric window,
with row in the upper nibble and column in the lower nibble. Globals precede
nearby objects; tokens beyond 500 are truncated. Metadata defines feature and
tag names. Each observer sees its own team as `team:cogs` / `net:cogs`
and every opposing team as `team:clips` / `net:clips`. Agent groups similarly
encode friendly as 0 and enemy as 1. Physical seat IDs remain 0–31.
This preserves the lab containers' Machina 1 vocabulary without changing
the four teams in the simulation. Opposing factions are intentionally merged
in this compatibility view; BASIC and tensor views retain their existing APIs.

PW supplies its own inventories, team banks, roles, station recipes, local
position, last movement, and territory. Reward is zero: PW has no equivalent
per-agent shaped reward. Station protocol hints reflect the fixed PW recipes.
The projection does not promise MettaGrid's observation ordering, truncation,
map seeds, initial energy, timing, or simulation behavior.

## Hosted verification

Release `0.1.6rc2` passed all ten hosted certification checks on 2026-11-10.
Two full episodes used unchanged `doug-cvc-hybrid:v5` and `quietcog-seat:v11`
containers, rotating their eight-seat teams between the lower and upper halves.
Every one of the 32 container runs logged 10,000 observations. All 16 Hananel
runs reported zero step gaps. The existing Safa tensor player completed
10,000 inference steps in each episode alongside the BASIC fillers.

The [lower-seat episode](https://softmax.com/observatory/v2/episode-requests/ereq_92fa1fc7-1b95-4d33-b60f-6964d2c44906/watch)
and [upper-seat episode](https://softmax.com/observatory/v2/episode-requests/ereq_7930040e-7b57-4494-8a68-250d65d109d4/watch)
verify execution and faction recognition. They do not establish ranking or
MettaGrid simulation equivalence. Source revisions, image digests, certification,
scores, and per-seat checks are recorded in [the verification artifact](docker-verification.json).

The release remains non-canonical. Listing and participant migration were not
changed. Doug's selection setting permits requests visible to him, so these
tests use public Experience Requests. Elevated access does not waive that setting.

## Repeatable local check

After building the Coworld, run `python tests/system/docker_players.py`.
It builds a small Docker player and uses the real Coworld runner for two full
matches. Four container seats, one in each corner, must match an all-BASIC
north-moving roster byte for byte. The players also check their friendly-team
vocabulary and send stale actions that must not enter the replay.
Artifacts remain under `out/docker-system-*` for inspection.
