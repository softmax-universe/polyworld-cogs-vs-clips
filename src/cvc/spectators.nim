## Read-only spectators consume the same authoritative tape as saved replays.
import std/[locks, os], mummy

const AssetNames = ["index.html", "cvc.js", "cvc.wasm", "cvc.data"]
const AssetTypes = ["text/html; charset=utf-8", "text/javascript", "application/wasm", "application/octet-stream"]
var
  assets: array[4, string]
  snapshot: string
  snapshotLock: Lock

proc initSpectators*() =
  ## Load this game image's matching viewer before accepting requests.
  let directory = getEnv("CVC_VIEWER_DIR", "/app/viewer")
  for i, name in AssetNames:
    assets[i] = readFile(directory / name)
  initLock(snapshotLock)

proc publishSpectatorTape*(bytes: string) =
  ## Replace one bounded snapshot; slow spectators never queue simulation ticks.
  withLock snapshotLock:
    snapshot = bytes

proc handleSpectatorRequest*(request: Request): bool {.gcsafe.} =
  ## Serve only bundled assets, without exposing paths or player credentials.
  if request.path == "/global":
    discard request.upgradeToWebSocket()
    return true
  var index = -1
  case request.path
  of "/client/global", "/client/player", "/client/replay": index = 0
  of "/client/cvc.js": index = 1
  of "/client/cvc.wasm": index = 2
  of "/client/cvc.data": index = 3
  else: return false
  {.cast(gcsafe).}:
    request.respond(200, @[("Content-Type", AssetTypes[index]),
      ("Cache-Control", "no-store")], assets[index])
  true

proc handleSpectatorEvent*(socket: WebSocket, event: WebSocketEvent, message: Message) {.gcsafe.} =
  ## Pull at most one current tape per request; reconnect starts from that tape.
  case event
  of OpenEvent, MessageEvent:
    if event == MessageEvent:
      if message.kind == Ping:
        socket.send(message.data, Pong)
        return
      if message.kind != TextMessage or message.data != "snapshot":
        return
    withLock snapshotLock:
      {.cast(gcsafe).}:
        if snapshot.len == 0:
          socket.send("{\"type\":\"waiting\"}")
        else:
          socket.send(snapshot, BinaryMessage)
  of CloseEvent, ErrorEvent: discard
