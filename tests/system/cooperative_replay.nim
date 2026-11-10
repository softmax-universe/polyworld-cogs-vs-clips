## Full matches must retain their map and actions across native/WASM replay.
## Build with -d:cooperative -d:headless. Compare stdout between native and WASM.
import cvc/[sims, replays, bots]

var previousTiles: array[TileCount, Tile]
for mapSeed in [20261110'i32, 20261111'i32, 20261112'i32]:
  let session = newSession(42, mapSeed)
  let alternate = initWorld(-9, mapSeed)
  doAssert session.world.tiles == alternate.tiles
  doAssert session.world.stations == alternate.stations
  if mapSeed > 20261110:
    doAssert session.world.tiles != previousTiles
  previousTiles = session.world.tiles
  # Walk the complete generated arena: every spawn and station must be accessible.
  var reachable: array[TileCount, bool]
  var queue = @[session.world.cogs[0].tile]
  reachable[queue[0]] = true
  var head = 0
  while head < queue.len:
    let tile = queue[head]
    inc head
    for direction in North .. West:
      let next = tile.neighbor(direction)
      if next >= 0 and not reachable[next] and not session.world.tiles[next].wall and
        session.world.tiles[next].station < 0:
          reachable[next] = true
          queue.add(next)
  for cog in session.world.cogs:
    doAssert cog.team == Red and reachable[cog.tile]
  for station in session.world.stations:
    var accessible = false
    for direction in North .. West:
      let next = station.tile.neighbor(direction)
      if next >= 0 and reachable[next]:
        accessible = true
    doAssert accessible
  let policies = newBots()
  while session.world.tick < MaxTicks:
    session.advance(policies.decide(session.world))
    echo mapSeed, ",", session.world.tick, ",", session.world.stateHash
  doAssert session.world.scores[Red] > 0
  doAssert session.world.scores[Blue] > 0
  let replay = loadBytes(session.replayBytes())
  replay.seek(MaxTicks)
  doAssert replay.world.stateHash == session.world.stateHash
  doAssert replay.world.mapSeed == mapSeed
  replay.seek(999)
  replay.seek(MaxTicks)
  doAssert replay.world.stateHash == session.world.stateHash
