## Container players use the original Cogs vs Clips wire protocol over PW state.
import
  std/[locks, monotimes, options, os, parseutils, times],
  jsony, mummy,
  polyworld/coworld,
  sims, mettagridview

const
  PlayerProtocol* = "coworld.player.v1"
  ActionNames = ["noop", "move_north", "move_south", "move_west", "move_east"]
  ConnectionDeadlineMs = 120_000
  ActionDeadlineMs = 1000

type
  Connection = object
    socket: WebSocket
    claimed, opened, disconnected, replied: bool
    step: int = -1
    action: int
  ActionMessage = object
    `type`: string
    action_index: int = -1
    action_name, request_id: string
  FeatureDescription = object
    id: int
    name: string
    normalization: float64
  TalkConfig = object
    enabled: bool
    max_length, cooldown_steps: int
    broadcast_resource: Option[string]
  PolicyEnvironment = object
    obs_features: seq[FeatureDescription]
    tags, action_names, vibe_action_names: seq[string]
    move_energy_cost, num_agents: int
    observation_kind, observation_dtype: string
    observation_low, observation_high: float64
    observation_shape, egocentric_shape: array[2, int]
    talk: TalkConfig
  ObservationMetadata = object
    width, height: int
    features: seq[FeatureDescription]
    tags: seq[string]
    global_location: int = 254
    empty_location: int = 255
  ControlState = object
    control_mode: string = "policy"
    human_controller_connection_id: Option[string]
    tick_mode: string = "fixed"
    human_action_timeout_seconds: float64 = 5
  PlayerConfig = object
    `type`, protocol, connection_id: string
    mission: string = "four_score"
    slot, num_agents, max_steps: int
    action_names: array[5, string]
    observation_shape: array[2, int]
    policy_env: PolicyEnvironment
    observation: ObservationMetadata
    control_state: ControlState
  ObservationMessage = object
    `type`, protocol: string
    mission: string = "four_score"
    slot, step: int
    observation: ContainerObservation
    terminated, truncated, is_human_controlled: bool
    scores: array[CogCount, float64]
    control_state: ControlState
    visible_talk: seq[string]
  EndMessage = object
    `type`, protocol: string
    mission: string = "four_score"
    step: int
    done: bool = true
    scores: array[CogCount, float64]

const PolicyMetadata = staticRead("../../data/protocols/machina_compat.json")

var
  connections: array[CogCount, Connection]
  connectionLock: Lock
  finished: bool
  view: ContainerView

proc newHook(action: var ActionMessage) =
  ## Jsony needs an explicit initializer for absent optional action fields.
  action.action_index = -1

proc initSocketPlayers*() =
  ## Called before starting the contract server; state is guarded by one lock.
  initLock(connectionLock)

proc playerRequest*(request: Request) {.gcsafe.} =
  ## Claims one authenticated non-file seat. Tokens never enter diagnostics.
  {.cast(gcsafe).}:
    var slot: int
    let text = request.queryParams["slot"]
    if text.len == 0 or parseInt(text, slot) != text.len or
      slot notin 0 ..< CogCount:
        request.respond(400, body = "Invalid slot")
        return
    withLock connectionLock:
      if seats.seats[slot].kind != "container" or playerTokens[slot].len == 0 or
        request.queryParams["token"] != playerTokens[slot]:
          request.respond(403, body = "Invalid player credentials")
      elif finished or connections[slot].claimed:
        request.respond(409, body = "Seat unavailable")
      else:
        connections[slot].socket = request.upgradeToWebSocket()
        connections[slot].claimed = true

proc playerEvent*(socket: WebSocket, event: WebSocketEvent,
    message: Message): bool {.gcsafe.} =
  ## Keeps all network mutation outside the simulation; stale actions never apply.
  {.cast(gcsafe).}:
    withLock connectionLock:
      for slot in 0 ..< CogCount:
        if not connections[slot].claimed or connections[slot].socket != socket:
          continue
        result = true
        case event
        of OpenEvent:
          var environment = PolicyMetadata.fromJson(PolicyEnvironment)
          # PW has no vibe actions or talk; describe the runtime actually offered.
          environment.vibe_action_names = @[]
          socket.send(PlayerConfig(`type`: "player_config", protocol: PlayerProtocol,
            connection_id: "pw-seat-" & $slot, slot: slot, num_agents: CogCount,
            max_steps: MaxTicks, action_names: ActionNames,
            observation_shape: [ContainerTokens, 3], policy_env: environment,
            observation: ObservationMetadata(width: 13, height: 13,
              features: environment.obs_features, tags: environment.tags)).toJson())
          connections[slot].opened = true
        of MessageEvent:
          if message.kind == Ping:
            socket.send(message.data, Pong)
          elif message.kind == TextMessage and not finished:
            let action = message.data.fromJson(ActionMessage)
            var index = action.action_index
            if action.action_name.len > 0:
              index = -1
              for i, name in ActionNames:
                if name == action.action_name:
                  index = i
            if action.`type` != "action" or index notin 0 .. 4:
              connections[slot].disconnected = true
              socket.close()
            elif connections[slot].step >= 0 and not connections[slot].replied and
              (action.request_id.len == 0 or
                action.request_id == "step-" & $connections[slot].step):
                  connections[slot].action = index
                  connections[slot].replied = true
        of ErrorEvent, CloseEvent:
          connections[slot].disconnected = true
        return

proc awaitSocketPlayers*() =
  ## A missing player cannot silently become a resting baseline.
  let deadline = getMonoTime() + initDuration(milliseconds = ConnectionDeadlineMs)
  while true:
    var waiting = -1
    withLock connectionLock:
      for slot in 0 ..< CogCount:
        if seats.seats[slot].kind != "policy" and not connections[slot].opened:
          waiting = slot
          break
    if waiting < 0:
      return
    if getMonoTime() >= deadline:
      rejectPlayer(waiting, "Connection deadline exceeded")
    sleep(1)

proc socketActions*(world: World, actions: var Actions) =
  ## Broadcasts one immutable tick, then collects one action per socket seat.
  var scores: array[CogCount, float64]
  for slot, cog in world.cogs:
    scores[slot] = world.scores[cog.team].float64 / MaxTicks.float64
  withLock connectionLock:
    for slot in 0 ..< CogCount:
      if seats.seats[slot].kind == "policy":
        continue
      let observation = view.observe(world, slot)
      connections[slot].step = int(world.tick)
      connections[slot].replied = false
      connections[slot].socket.send(ObservationMessage(`type`: "observation",
        protocol: PlayerProtocol, slot: slot, step: int(world.tick),
        observation: observation, scores: scores).toJson())
  let deadline = getMonoTime() + initDuration(milliseconds = ActionDeadlineMs)
  while true:
    var waiting = -1
    var disconnected = -1
    withLock connectionLock:
      for slot in 0 ..< CogCount:
        if seats.seats[slot].kind == "policy":
          continue
        if connections[slot].disconnected:
          disconnected = slot
          break
        if not connections[slot].replied:
          waiting = slot
        else:
          actions[slot] = LegacyToAction[connections[slot].action]
          view.last[slot] = actions[slot]
    if disconnected >= 0:
      rejectPlayer(disconnected, "Player disconnected or sent an invalid action")
    if waiting < 0:
      return
    if getMonoTime() >= deadline:
      rejectPlayer(waiting, "Action deadline exceeded")
    sleep(1)

proc finishSocketPlayers*(world: World) =
  ## Delivers the terminal score before the runner collects results.
  var scores: array[CogCount, float64]
  for slot, cog in world.cogs:
    scores[slot] = world.scores[cog.team].float64 / MaxTicks.float64
  withLock connectionLock:
    finished = true
    for slot in 0 ..< CogCount:
      if seats.seats[slot].kind != "policy":
        connections[slot].socket.send(EndMessage(`type`: "final",
          protocol: PlayerProtocol, step: int(world.tick),
          scores: scores).toJson())
