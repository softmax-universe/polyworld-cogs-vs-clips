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

## Release gate

Transport checks alone do not establish unchanged-container compatibility.
Before listing this release or transferring policies, run Doug's and Hananel's
registered versions through complete hosted episodes and inspect their logs,
actions, failures, and scores. A full episode can still hide a semantic mismatch:
inspect recognized teams and action diversity as well as step counts. Keep the
release non-canonical until that check passes.

## Repeatable local check

After building the Coworld, run `python tests/system/docker_players.py`.
It builds a small Docker player and uses the real Coworld runner for two full
matches. Four container seats, one in each corner, must match an all-BASIC
north-moving roster byte for byte. The players also check their friendly-team
vocabulary and send stale actions that must not enter the replay.
Artifacts remain under `out/docker-system-*` for inspection.
