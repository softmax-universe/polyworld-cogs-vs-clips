## Authenticated, bounded transport for platform-hosted Coworld seats.
## Game messages are opaque. Only the simulation thread interprets them.
import std/[locks, monotimes, os, parseutils, times], mummy, webby

const MaximumSeats = 64

type
  PlayerEventKind* = enum
    PlayerConnected, PlayerMessage, PlayerDisconnected, PlayerOverflow, PlayerTimeout
  PlayerEvent* = object
    kind*: PlayerEventKind
    slot*: int
    data*: string
    receivedAt*: MonoTime

var
  playerTokens: seq[string]
  remoteSeats: array[MaximumSeats, bool]
  sockets: array[MaximumSeats, WebSocket]
  occupied, accepting, overflowed: array[MaximumSeats, bool]
  socketLock: Lock
  events: Channel[PlayerEvent]

proc initPlayerTransport*(tokens: seq[string], remote: openArray[bool]) =
  ## Called once before starting the server; identity is immutable thereafter.
  assert tokens.len == remote.len and tokens.len in 1 .. MaximumSeats
  playerTokens = tokens
  for slot, enabled in remote:
    remoteSeats[slot] = enabled
  initLock(socketLock)
  events.open(MaximumSeats * 2)

proc handlePlayerRequest*(request: Request): bool {.gcsafe.} =
  ## Claims /player and binds a token to its original episode slot.
  if request.path != "/player":
    return false
  result = true
  let rawSlot = request.queryParams["slot"]
  var slot: int
  if rawSlot.len notin 1 .. 2 or parseInt(rawSlot, slot) != rawSlot.len or slot notin 0 ..< MaximumSeats:
    request.respond(400, body = "Invalid slot")
    return
  # Tokens are assigned before the server starts and never modified by workers.
  {.cast(gcsafe).}:
    if slot >= playerTokens.len or not remoteSeats[slot] or
      request.queryParams["token"] != playerTokens[slot]:
        request.respond(403, body = "Invalid player credentials")
        return
  withLock socketLock:
    if occupied[slot]:
      request.respond(409, body = "Player slot already connected")
      return
    sockets[slot] = request.upgradeToWebSocket()
    occupied[slot] = true

proc handlePlayerEvent*(socket: WebSocket, event: WebSocketEvent, message: Message): bool {.gcsafe.} =
  ## Transfers bounded packets to the simulation thread without touching game state.
  withLock socketLock:
    for slot in 0 ..< MaximumSeats:
      if not occupied[slot] or sockets[slot] != socket:
        continue
      result = true
      var incoming = PlayerEvent(slot: slot, receivedAt: getMonoTime())
      case event
      of OpenEvent:
        incoming.kind = PlayerConnected
      of MessageEvent:
        if message.kind == Ping:
          socket.send(message.data, Pong)
          return
        if message.kind == Pong:
          return
        if message.kind != TextMessage or not accepting[slot]:
          overflowed[slot] = true
          return
        incoming.kind = PlayerMessage
        incoming.data = message.data
      of CloseEvent, ErrorEvent:
        incoming.kind = PlayerDisconnected
        # A disconnected seat remains claimed. Reconnection needs a game protocol,
        # not a second controller silently replacing the episode's original one.
      if not events.trySend(incoming):
        overflowed[slot] = true
      return

proc sendPlayer*(slot: int, message: string, expectReply = false) =
  ## Sends from the simulation thread to the authenticated socket.
  withLock socketLock:
    assert slot in 0 ..< MaximumSeats and occupied[slot]
    accepting[slot] = expectReply
    sockets[slot].send(message)

proc completePlayerReply*(slot: int) =
  ## Only the simulation can distinguish a stale reply from the current action.
  withLock socketLock:
    accepting[slot] = false

proc nextPlayerEvent*(timeoutMs: int): PlayerEvent =
  ## Bounds a wait using monotonic time; timeout is an explicit result.
  let deadline = getMonoTime() + initDuration(milliseconds = timeoutMs)
  while true:
    withLock socketLock:
      for slot in 0 ..< MaximumSeats:
        if overflowed[slot]:
          return PlayerEvent(kind: PlayerOverflow, slot: slot)
    let received = events.tryRecv()
    if received.dataAvailable:
      result = received.msg
      return
    if getMonoTime() >= deadline:
      return PlayerEvent(kind: PlayerTimeout, slot: -1)
    sleep(1)
