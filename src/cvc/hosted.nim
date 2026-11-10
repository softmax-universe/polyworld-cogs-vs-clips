import
  polyworld/coworld,
  sims, replays, bots, socketplayers

proc runHosted*() =
  ## Runs file and socket seats against one deterministic simulation.
  initSocketPlayers()
  let options = coworldOptions(CogCount, playerRequest, playerEvent)
  if options.maximumTicks != MaxTicks:
    raise newException(CoworldError, "FourScore requires 10,000 ticks")
  var sources: array[CogCount, string]
  var enabled: array[CogCount, bool]
  var hasSockets = false
  for slot, group in options.botGroups:
    enabled[slot] = seats.seats[slot].kind == "policy"
    if not enabled[slot]:
      if seats.seats[slot].kind != "container":
        raise newException(CoworldError, "PW supports file and container players")
      hasSockets = true
      continue
    try:
      sources[slot] = readPlayerSource(group.path)
    except CoworldError as error:
      rejectPlayer(slot, error.msg)
  let
    session = newSession(options.seed)
    policies = newBots(sources, enabled)
  awaitSocketPlayers()
  while session.world.tick < MaxTicks:
    var actions = policies.decide(session.world)
    if hasSockets:
      socketActions(session.world, actions)
    session.advance(actions)
  finishSocketPlayers(session.world)
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
