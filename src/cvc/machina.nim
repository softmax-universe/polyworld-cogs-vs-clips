import polyworld/rngs, common

proc generate*(seed, mapSeed: int32): World =
  ## Generates the cooperative arena without consuming simulation randomness.
  result.seed = seed
  result.mapSeed = mapSeed
  result.rng = initRng(seed)
  var terrain = initRng(mapSeed)
  let hub = Red.home
  for tile in 0 ..< TileCount:
    result.tiles[tile].station = -1
    let x = tile mod Width
    let y = tile div Width
    result.tiles[tile].wall = x == 0 or y == 0 or x == Width - 1 or y == Height - 1
    result.tiles[tile].biome = uint8((x div 22 + y div 22) mod 4)
  # Match MettaGrid's AsteroidMask: seeded triangular cuts, 2-8 tiles deep,
  # along all four edges. Integer rounding keeps native and WASM maps identical.
  for axis in 0 .. 1:
    for anchor in countup(0'i32, Width.int32 - 1, 3):
      for reverse in [false, true]:
        if terrain.between(0, 9) >= 6:
          continue
        let depth = terrain.between(2, 8)
        let halfWidth = terrain.between(2, 6)
        for offset in 0'i32 ..< depth:
          let span = (halfWidth * (depth - offset) * 2 + depth) div (depth * 2)
          if span == 0:
            continue
          let edge = if reverse: Width.int32 - 1 - offset else: offset
          for along in max(0'i32, anchor - span) .. min(Width.int32 - 1, anchor + span):
            let tile = if axis == 0: tileAt(along, edge) else: tileAt(edge, along)
            result.tiles[tile].wall = true
  # Small outer buildings vary daily; the compound and four Clips roots stay fixed.
  for building in 0 ..< 100:
    let x = terrain.between(4, Width - 7)
    let y = terrain.between(4, Height - 7)
    if abs(x - hub.x) <= 15 and abs(y - hub.y) <= 15:
      continue
    for dx in 0'i32 .. 2:
      for dy in 0'i32 .. 2:
        result.tiles[tileAt(x + dx, y + dy)].wall = true
  result.addStation(Station(kind: Hub, tile: Red.home, owner: Red))
  for role in [Miner, Aligner, Scrambler, Scout]:
    result.addStation(Station(kind: Gear, tile: Red.gearTile(role), owner: Red, role: role))
  for element, offset in [(x: -8'i32, y: -8'i32), (x: 8'i32, y: -8'i32),
      (x: -8'i32, y: 8'i32), (x: 8'i32, y: 8'i32)]:
    result.addStation(Station(kind: Extractor, tile: tileAt(hub.x + offset.x, hub.y + offset.y),
      element: Element(element), stock: 200))
  result.addStation(Station(kind: Junction, tile: tileAt(hub.x, hub.y + 4)))
  for i, tile in [tileAt(2, 2), tileAt(85, 2), tileAt(2, 85), tileAt(85, 85)]:
    result.addStation(Station(kind: Ship, tile: tile, owner: Blue, lane: int8(i + 1)))
  for row in 0 ..< 9:
    for column in 0 ..< 9:
      let tile = tileAt(int32(10 + column * 8) + terrain.between(-1, 1),
        int32(10 + row * 8) + terrain.between(-1, 1))
      if abs(tile.x - hub.x) > 13 or abs(tile.y - hub.y) > 13:
        result.addStation(Station(kind: Junction, tile: tile))
  for element in Element:
    for resource in 0 ..< 60:
      var placed = false
      for attempt in 0 ..< 1000:
        let tile = tileAt(terrain.between(10, Width - 11), terrain.between(10, Height - 11))
        if result.tiles[tile].station >= 0 or
          (abs(tile.x - hub.x) <= 13 and abs(tile.y - hub.y) <= 13):
          continue
        var clear = true
        for direction in North .. West:
          if result.tiles[tile.neighbor(direction)].station >= 0:
            clear = false
        if clear:
          result.addStation(Station(kind: Extractor, tile: tile, element: element, stock: 200))
          placed = true
          break
      if not placed:
        fail("cooperative map cannot place its resource population")
  # Join every station to the compound with two-wide corridors. Stations never
  # block both lanes, and the seed still controls buildings and station geometry.
  for station in result.stations:
    # Bring corner ships inland before crossing the map; horizontal paths along
    # the outermost rows would flatten the asteroid cuts into a square again.
    let corridorY = clamp(station.tile.y, 10'i32, Height.int32 - 11)
    for y in min(station.tile.y, corridorY) .. max(station.tile.y, corridorY):
      for dx in 0'i32 .. 1:
        result.tiles[tileAt(station.tile.x + dx, y)].wall = false
    for x in min(station.tile.x, hub.x) .. max(station.tile.x, hub.x):
      for dy in 0'i32 .. 1:
        result.tiles[tileAt(x, corridorY + dy)].wall = false
    for y in min(corridorY, hub.y) .. max(corridorY, hub.y):
      for dx in 0'i32 .. 1:
        result.tiles[tileAt(hub.x + dx, y)].wall = false
  # Restore the original Compound geometry after corridor carving. Its three-tile
  # apron connects the outer paths to the four five-wide gates without holes.
  for dy in -13'i32 .. 13:
    for dx in -13'i32 .. 13:
      result.tiles[tileAt(hub.x + dx, hub.y + dy)].wall =
        (abs(dx) == 10 and abs(dy) <= 10 and abs(dy) > 2) or
        (abs(dy) == 10 and abs(dx) <= 10 and abs(dx) > 2)
  for element in Element:
    result.banks[Red][element] = CogCount * 3
  result.hearts[Red] = 5
  for slot, offset in [(x: 0'i32, y: -2'i32), (x: 2'i32, y: 0'i32),
      (x: 0'i32, y: 2'i32), (x: -2'i32, y: 0'i32), (x: 3'i32, y: 0'i32),
      (x: -3'i32, y: 0'i32), (x: 0'i32, y: 3'i32), (x: 0'i32, y: -3'i32)]:
    result.cogs[slot] = Cog(team: Red, tile: tileAt(hub.x + offset.x, hub.y + offset.y),
      hp: 50, energy: 20, direction: South)
