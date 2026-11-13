import
  std/[json, os, monotimes, times],
  coworldhost, spectators,
  sims, replays, bots, containerplayers

proc runHosted*() =
  ## Runs staged BASIC seats and publishes the standard CoWorld artifacts.
  let options = coworldOptions(CogCount, mixedPlayers = true)
  if options.maximumTicks != MaxTicks:
    raise newException(CoworldError, "Cogs vs Clips requires 10,000 ticks")
  var sources: array[CogCount, string]
  var active: array[CogCount, bool]
  for slot, seat in seats.seats:
    if seat.kind != policy:
      continue
    active[slot] = true
    try:
      sources[slot] = readPlayerSource(localPath(seat.fileUri))
    except CoworldError as error:
      rejectPlayer(slot, error.msg)
  var mapSeed = 1'i32
  when defined(cooperative):
    let config = parseJson(readLocal(getEnv("COGAME_CONFIG_URI")))
    if not config.hasKey("map_seed") or config["map_seed"].kind != JInt or
      config["map_seed"].getBiggestInt notin int64(int32.low) .. int64(int32.high):
        raise newException(CoworldError, "Cooperative episodes require a frozen int32 map_seed")
    mapSeed = int32(config["map_seed"].getBiggestInt)
  let
    session = newSession(options.seed, mapSeed)
    policies = newBots(sources, active)
  session.tape.config.players = coworldhost.config.players
  publishSpectatorTape(session.replayBytes())
  var published = getMonoTime()
  var remote = connectPlayers()
  while session.world.tick < MaxTicks:
    var actions = policies.decide(session.world)
    remote.decide(session.world, actions)
    session.advance(actions)
    if (getMonoTime() - published).inMilliseconds >= 1000:
      publishSpectatorTape(session.replayBytes())
      published = getMonoTime()
  publishSpectatorTape(session.replayBytes())
  remote.finish(session.world)
  session.save(options.recordPath)
  var scores: seq[int]
  for cog in session.world.cogs:
    scores.add int(session.world.scores[cog.team])
  finishCoworld(CoworldResults(
    scores: scores,
    ticks: session.world.tick,
    seed: options.seed,
    outcome: "time_limit"
  ), scoreDivisor = MaxTicks)
