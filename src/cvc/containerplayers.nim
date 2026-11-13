import std/[parsejson, streams, json, monotimes, times], coworldhost, common, mettagridview

const
  ActionNames = ["noop", "move_north", "move_south", "move_west", "move_east"]
  ConnectionTimeoutMs = 300_000
  ActionTimeoutMs = 30_000
  SourceEnvironment = staticRead("../../data/policies/cooperative_environment.json")
  Protocol = "coworld.player.v1"
  Mission = (when defined(cooperative): "machina_1" else: "four_score")

type ContainerPlayers* = object
  remote: array[CogCount, bool]
  view: ContainerView
  replyWaitNs, maximumReplyWaitNs: array[CogCount, int64]

proc connectPlayers*(): ContainerPlayers =
  ## Preserves the published wire exchange while declaring reconstructed inputs.
  var environment = parseJson(SourceEnvironment)
  environment["num_agents"] = %CogCount
  environment["vibe_action_names"] = newJArray()
  var remaining = 0
  for slot, seat in seats.seats:
    result.remote[slot] = seat.kind != policy
    if result.remote[slot]:
      inc remaining
  let deadline = getMonoTime() + initDuration(milliseconds = ConnectionTimeoutMs)
  var connected: array[CogCount, bool]
  while remaining > 0:
    let event = nextPlayerEvent(max(0, int((deadline - getMonoTime()).inMilliseconds)))
    if event.kind == PlayerTimeout:
      for slot, remote in result.remote:
        if remote and not connected[slot]:
          rejectPlayer(slot, "Player did not connect before the startup deadline")
    if event.kind != PlayerConnected or connected[event.slot]:
      rejectPlayer(event.slot, "Unexpected player traffic before match start")
    connected[event.slot] = true
    dec remaining
    sendPlayer(event.slot, $(%*{
      "type": "player_config", "protocol": Protocol,
      "mission": Mission, "slot": event.slot,
      "connection_id": "player-" & $event.slot,
      "num_agents": CogCount, "max_steps": MaxTicks,
      "action_names": ActionNames, "observation_shape": [500, 3],
      "policy_env": environment, "observation_contract": "polyworld-machina-74/v1",
      "observation": {"width": 13, "height": 13,
        "features": environment["obs_features"], "tags": environment["tags"],
        "global_location": 254, "empty_location": 255},
      "control_state": {"control_mode": "policy", "human_controller_connection_id": nil,
        "tick_mode": "lockstep", "human_action_timeout_seconds": 30}
    }))

proc decide*(players: var ContainerPlayers, world: World, actions: var Actions) =
  ## Requests one action per remote seat against the same frozen pre-tick state.
  var remaining = 0
  var pending: array[CogCount, bool]
  var sentAt: array[CogCount, MonoTime]
  var scores: array[CogCount, float64]
  for slot, cog in world.cogs:
    scores[slot] = world.scores[cog.team].float64 / MaxTicks.float64
  for slot in 0 ..< CogCount:
    if not players.remote[slot]:
      continue
    pending[slot] = true
    inc remaining
    let observation = players.view.observe(world, slot)
    sentAt[slot] = getMonoTime()
    sendPlayer(slot, $(%*{
      "type": "observation", "protocol": Protocol, "mission": Mission,
      "slot": slot, "step": world.tick, "observation": observation,
      "terminated": false, "truncated": false, "scores": scores,
      "is_human_controlled": false, "visible_talk": [],
      "control_state": {"control_mode": "policy", "human_controller_connection_id": nil,
        "tick_mode": "lockstep", "human_action_timeout_seconds": 30}
    }), expectReply = true)
  let deadline = getMonoTime() + initDuration(milliseconds = ActionTimeoutMs)
  while remaining > 0:
    let event = nextPlayerEvent(max(0, int((deadline - getMonoTime()).inMilliseconds)))
    if event.kind == PlayerTimeout:
      for slot, waiting in pending:
        if waiting:
          stderr.writeLine $(%*{"event": "player_action_timeout", "slot": slot,
            "step": world.tick, "reply_wait_ms": (getMonoTime() - sentAt[slot]).inMilliseconds})
          rejectPlayer(slot, "Player action deadline exceeded")
    if event.kind != PlayerMessage:
      rejectPlayer(event.slot, "Player disconnected or sent unsolicited traffic")
    # Validate untrusted JSON without exceptions before constructing its tree.
    # Bound nesting and integers so malformed policy traffic is attributed to its seat.
    var parser: JsonParser
    parser.open(newStringStream(event.data), "player action")
    parser.next()
    if parser.kind != jsonObjectStart:
      rejectPlayer(event.slot, "Expected an action object")
    var depth = 1
    while true:
      parser.next()
      case parser.kind
      of jsonError:
        rejectPlayer(event.slot, "Malformed action JSON")
      of jsonEof:
        break
      of jsonObjectStart, jsonArrayStart:
        inc depth
        if depth > 16:
          rejectPlayer(event.slot, "Action JSON nesting exceeds 16")
      of jsonObjectEnd, jsonArrayEnd:
        dec depth
      of jsonInt:
        if parser.str.len > 18:
          rejectPlayer(event.slot, "Action integer exceeds supported range")
      else: discard
    parser.close()
    let action = parseJson(event.data)
    if action.kind != JObject or not action.hasKey("type") or action["type"] != %"action":
      rejectPlayer(event.slot, "Expected an action message")
    if action.hasKey("request_id"):
      if action["request_id"].kind != JString:
        rejectPlayer(event.slot, "Expected a string request_id")
      let requestId = action["request_id"].getStr()
      if requestId.len > 0 and requestId != "step-" & $world.tick:
        continue
    if not pending[event.slot]:
      rejectPlayer(event.slot, "Duplicate action for current observation")
    var index = -1
    if action.hasKey("action_name") and action["action_name"].kind == JString:
      index = ActionNames.find(action["action_name"].getStr())
    elif action.hasKey("action_index") and action["action_index"].kind == JInt:
      let value = action["action_index"].getBiggestInt()
      if value in 0 .. 4:
        index = int(value)
    if index notin 0 .. 4:
      rejectPlayer(event.slot, "Invalid movement action")
    actions[event.slot] = LegacyToAction[index]
    let elapsed = (event.receivedAt - sentAt[event.slot]).inNanoseconds
    players.replyWaitNs[event.slot] += elapsed
    players.maximumReplyWaitNs[event.slot] = max(players.maximumReplyWaitNs[event.slot], elapsed)
    if (world.tick + 1) mod 1000 == 0:
      stderr.writeLine $(%*{"event": "player_timing", "slot": event.slot,
        "step": world.tick, "actions": world.tick + 1,
        "reply_wait_ms": players.replyWaitNs[event.slot].float64 / 1_000_000.0,
        "maximum_reply_wait_ms": players.maximumReplyWaitNs[event.slot].float64 / 1_000_000.0})
    completePlayerReply(event.slot)
    pending[event.slot] = false
    dec remaining
  players.view.last = actions

proc finish*(players: ContainerPlayers, world: World) =
  ## Sends completion after the final tick; artifacts remain the runner's truth.
  var scores: array[CogCount, float64]
  for slot, cog in world.cogs:
    scores[slot] = world.scores[cog.team].float64 / MaxTicks.float64
  for slot, remote in players.remote:
    if remote:
      sendPlayer(slot, $(%*{"type": "final", "protocol": Protocol,
        "slot": slot, "step": world.tick, "scores": scores}))
