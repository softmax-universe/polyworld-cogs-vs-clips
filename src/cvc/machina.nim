import polyworld/rngs, common

proc generate*(seed, mapSeed: int32): World =
  ## Generates the cooperative arena without consuming simulation randomness.
  result.seed = seed
  result.mapSeed = mapSeed
  result.rng = initRng(seed)
  var terrain = initRng(mapSeed)
  for tile in 0 ..< TileCount:
    result.tiles[tile].station = -1
    let x = tile mod Width
    let y = tile div Width
    result.tiles[tile].wall = x == 0 or y == 0 or x == Width - 1 or y == Height - 1
    result.tiles[tile].biome = uint8((x div 22 + y div 22) mod 4)
  # Small outer buildings vary daily; the compound and four Clips roots stay fixed.
  for building in 0 ..< 100:
    let x = terrain.between(4, Width - 7)
    let y = terrain.between(4, Height - 7)
    if tileAt(x, y).distance2(Red.home) < 225:
      continue
    for dx in 0'i32 .. 2:
      for dy in 0'i32 .. 2:
        result.tiles[tileAt(x + dx, y + dy)].wall = true
  result.addStation(Station(kind: Hub, tile: Red.home, owner: Red))
  for role in [Miner, Aligner, Scrambler, Scout]:
    result.addStation(Station(kind: Gear, tile: Red.gearTile(role), owner: Red, role: role))
  for i, tile in [tileAt(2, 2), tileAt(85, 2), tileAt(2, 85), tileAt(85, 85)]:
    result.addStation(Station(kind: Ship, tile: tile, owner: Blue, lane: int8(i + 1)))
  for row in 0 ..< 9:
    for column in 0 ..< 9:
      let tile = tileAt(int32(7 + column * 9) + terrain.between(-1, 1),
        int32(7 + row * 9) + terrain.between(-1, 1))
      if tile.distance2(Red.home) >= 100:
        result.addStation(Station(kind: Junction, tile: tile))
  for element in Element:
    for resource in 0 ..< 60:
      var placed = false
      for attempt in 0 ..< 1000:
        let tile = tileAt(terrain.between(3, Width - 4), terrain.between(3, Height - 4))
        if result.tiles[tile].station >= 0 or tile.distance2(Red.home) < 100:
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
    for x in min(station.tile.x, 44'i32) .. max(station.tile.x, 44'i32):
      for dy in 0'i32 .. 1:
        result.tiles[tileAt(x, station.tile.y + dy)].wall = false
    for y in min(station.tile.y, 44'i32) .. max(station.tile.y, 44'i32):
      for dx in 0'i32 .. 1:
        result.tiles[tileAt(44 + dx, y)].wall = false
  for element in Element:
    result.banks[Red][element] = CogCount * 3
  result.hearts[Red] = 5
  for slot in 0 ..< CogCount:
    let tile = tileAt(40 + int32(slot), 46)
    result.tiles[tile].wall = false
    result.cogs[slot] = Cog(team: Red, tile: tile, hp: 50, energy: 20, direction: South)
