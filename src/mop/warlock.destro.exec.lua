---- Intro is provided to trick the IDEs into accepting the code is a syntactically correct Lua function
---- THIS MUST BE REMOVED BEFORE INSERTION IN THE WEAKAURAS
aura_env.mop.warlock.destro.exec =
----

function (ev)

  -- The Next Action Guide (NAG) is a module that handles the logic of what spell to cast next
  -- This is done in two steps:
  -- 1. Gather information about the current state of the game, such as cooldowns, buffs, etc.
  -- 2. Analyze gathered information and decide what spell to cast next
  local nag = aura_env.nag

  -- Step 1. Gather information about the current state of the game

  local keepGoing = nag:analyzeEvent(ev)
  if not keepGoing then
    return nag.enabled -- If the event is not relevant, stop here
  end

  -- Step 2. Analyze gathered information and decide what spell to cast next

  local timeOfNextSpell = nag:getTimeOfNextSpell()

  local gcdCD = select(2, GetSpellCooldown(61304))
  if gcdCD ~= 0 then
    nag.last_known_gcd = gcdCD
  end

  local lastDecision = nag.next -- Cache for future use in debugging

  local immoExpired, immoRefreshSpellID, immoRefreshCastTime = nag:isAuraExpired("immo", "target", timeOfNextSpell)
  local coeExpired, coeRefreshSpellID, coeRefreshCastTime = nag:isAuraExpired("coe", "target", timeOfNextSpell)
  local shadowburnUsable, shadowburnSpellID, shadowburnCastTime = nag:canCast("shadowburn", timeOfNextSpell)
  local chaosBoltUsable, chaosBoltSpellID, chaosBoltCastTime = nag:canCast("chaos_bolt", timeOfNextSpell)
  local conflagUsable, conflagSpellID, conflagCastTime = nag:canCast("conflagrate", timeOfNextSpell)
  if immoExpired then
    nag:decide("aura:immo", immoRefreshSpellID, immoRefreshCastTime)
  elseif coeExpired then
    nag:decide("aura:coe", coeRefreshSpellID, coeRefreshCastTime)
  elseif conflagUsable then
    nag:decide("cast:conflagrate", conflagSpellID, conflagCastTime)
  elseif shadowburnUsable then
    nag:decide("cast:shadowburn", shadowburnSpellID, shadowburnCastTime)
  elseif chaosBoltUsable then
    nag:decide("cast:chaos_bolt", chaosBoltSpellID, chaosBoltCastTime)
  else
    -- Use Incinerate as filler
    nag:decide("filler:incinerate", 29722) -- Incinerate = 29722
  end

  -- Look into the future, and ajust the present if the future does not look bright enough
  local timeOfNextNextSpell = timeOfNextSpell + math.max(nag.next.time, nag.last_known_gcd)
  -- Priority: refresh Immolate at all costs
  if not immoExpired and nag.next.what ~= "aura:immo" then
    -- Try again with Immolate in the future
    immoExpired, immoRefreshSpellID, immoRefreshCastTime = nag:isAuraExpired("immo", "target", timeOfNextNextSpell)
    if immoExpired then
      nag:decide("aura:immo:future", immoRefreshSpellID, immoRefreshCastTime)
    end
  end

  -- Debug decision changes
  if aura_env.config.debug or aura_env.config.trace then
    local newDecision = nag.next
    if newDecision.what ~= lastDecision.what
    or newDecision.cast ~= lastDecision.cast
    or newDecision.icon ~= lastDecision.icon
    or newDecision.name ~= lastDecision.name
    or newDecision.time ~= lastDecision.time
    then -- Log only if changed
      nag:log(
        string.format("Decision: %s, %s, %s, %s, %s",
        tostring(newDecision.what), tostring(newDecision.cast), tostring(newDecision.icon), tostring(newDecision.name), tostring(newDecision.time))
      )
    end
  end

  return true
end
