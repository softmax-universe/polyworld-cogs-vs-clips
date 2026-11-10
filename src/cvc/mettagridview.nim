## MettaGrid's named 74-feature token interface projected from PW state.
## This changes representation only; PW owns simulation rules and scores.
import sims

const
  ContainerTokens* = 500
  LegacyToAction* = [Rest, North, South, West, East]
  ActionToLegacy = [0, 1, 4, 2, 3]
  ResourceFeatures = [14, 12, 16, 18]
  ResourceTags = [11, 16, 12, 19]
  RoleFeatures = [30, 26, 28, 32]
  RoleTags = [15, 10, 18, 17]
  NetworkTags = [0, 3, 1, 2, 4]

type
  ContainerObservation* = array[ContainerTokens, array[3, uint8]]
  ContainerView* = object
    initialized: bool
    tick: int32
    owners: array[TileCount, Owner]
    known: array[TileCount, bool]
    spawn, previous: array[CogCount, int32]
    last*: Actions

proc relative(owner, team: Owner): int =
  ## Encodes neutral, friendly and enemy territory.
  if owner == Neutral: 0
  elif owner == team: 1
  else: 2

proc owner(view: var ContainerView, world: World, tile: int32): Owner =
  ## Shares visible territory queries across Docker seats within one tick.
  if tile < 0:
    return Neutral
  if not view.known[tile]:
    view.owners[tile] = world.territory(tile)
    view.known[tile] = true
  view.owners[tile]

proc observe*(view: var ContainerView, world: World, slot: int): ContainerObservation =
  ## Keeps globals and nearby objects before truncating to the published budget.
  if not view.initialized:
    for i, cog in world.cogs:
      view.spawn[i] = cog.tile
      view.previous[i] = cog.tile
    view.initialized = true
  if view.tick != world.tick:
    reset(view.known)
    view.tick = world.tick
  for token in result.mitems:
    token = [255'u8, 255'u8, 255'u8]
  var count = 0
  template emit(location, feature, value: untyped) =
    if count < ContainerTokens:
      result[count] = [uint8(location), uint8(feature), uint8(clamp(int(value), 0, 255))]
      inc count
  template inventory(location, feature, value: untyped) =
    block:
      let amount = int(value)
      if amount > 0:
        emit(location, feature, amount and 255)
        if amount >= 256:
          emit(location, feature + 1, (amount shr 8) and 255)
  let cog = world.cogs[slot]
  emit(254, 1, world.tick * 255 div MaxTicks)
  emit(254, 2, ActionToLegacy[ord(view.last[slot])])
  emit(254, 3, 0)
  emit(254, 68, int(cog.tile != view.previous[slot]))
  view.previous[slot] = cog.tile
  let dx = cog.tile.x - view.spawn[slot].x
  let dy = cog.tile.y - view.spawn[slot].y
  if dx > 0: emit(254, 7, dx)
  if dx < 0: emit(254, 8, -dx)
  if dy < 0: emit(254, 9, -dy)
  if dy > 0: emit(254, 10, dy)
  for element in Element:
    inventory(254, 60 + [2, 0, 4, 6][ord(element)], world.banks[cog.team][element])
  emit(254, 69, relative(view.owner(world, cog.tile), cog.team))
  for distance in 0 .. 12:
    for y in -6'i32 .. 6:
      for x in -6'i32 .. 6:
        if abs(x) + abs(y) != distance:
          continue
        let tile = tileAt(cog.tile.x + x, cog.tile.y + y)
        if tile < 0:
          continue
        let location = ((y + 6) shl 4) or (x + 6)
        var occupant = -1
        for i, other in world.cogs:
          if other.tile == tile:
            occupant = i
        if occupant >= 0:
          let other = world.cogs[occupant]
          emit(location, 6, 9)
          emit(location, 6, 4 + NetworkTags[ord(other.team)])
          emit(location, 0, ord(other.team) - 1)
          emit(location, 11, occupant)
          inventory(location, 20, other.hp)
          inventory(location, 22, other.hearts)
          inventory(location, 24, other.energy)
          inventory(location, 34, (if world.tick mod DayLength < 100: 3 else: 1))
          for element in Element:
            inventory(location, ResourceFeatures[ord(element)], other.cargo[element])
          if other.role != Ungeared:
            inventory(location, RoleFeatures[ord(other.role) - 1], 1)
        elif world.tiles[tile].wall:
          emit(location, 6, 20)
        elif world.tiles[tile].station >= 0:
          let station = world.stations[world.tiles[tile].station]
          if station.owner != Neutral:
            emit(location, 6, 4 + NetworkTags[ord(station.owner)])
            if station.kind in {Hub, Junction}:
              emit(location, 6, NetworkTags[ord(station.owner)])
          if station.kind in {Hub, Junction} and station.owner != Neutral:
            for element in Element:
              inventory(location, ResourceFeatures[ord(element)], world.banks[station.owner][element])
          case station.kind
          of Hub:
            emit(location, 6, 13)
            for element in Element:
              emit(location, 36 + [1, 0, 2, 3][ord(element)], HeartCost)
            emit(location, 53, 1)
          of Junction:
            emit(location, 6, 14)
          of Extractor:
            emit(location, 6, ResourceTags[ord(station.element)])
            inventory(location, ResourceFeatures[ord(station.element)], station.stock)
            emit(location, 48 + [1, 0, 2, 3][ord(station.element)],
              (if cog.role == Miner: 10 else: 1))
          of Gear:
            emit(location, 6, RoleTags[ord(station.role) - 1])
            for element in Element:
              emit(location, 36 + [1, 0, 2, 3][ord(element)], GearCosts[station.role][element])
            emit(location, 48 + (RoleFeatures[ord(station.role) - 1] - 12) div 2, 1)
          of Ship:
            # FourScore has no ships; a different ruleset needs its own metadata.
            raise newException(ValueError, "Ship is not part of FourScore")
        let territory = view.owner(world, tile)
        for direction in North .. West:
          let neighbor = view.owner(world, tile.neighbor(direction))
          if territory != neighbor:
            emit(location, [0, 70, 72, 71, 73][ord(direction)],
              relative(territory, cog.team) * 3 + relative(neighbor, cog.team))
