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

  local timeOfNextSpell, lastDecision = nag:preDecide()

  local immo = nag:isAuraExpired("immo", "target", timeOfNextSpell)
  local coe = nag:isAuraExpired("coe", "target", timeOfNextSpell)
  local shadowburn = nag:canCast("shadowburn", timeOfNextSpell)
  local chaosBolt = nag:canCast("chaos_bolt", timeOfNextSpell)
  local conflag = nag:canCast("conflagrate", timeOfNextSpell)
  if immo.expired then
    nag:decide("aura:immo", immo.spellID, immo.castTime)
  elseif coe.expired then
    nag:decide("aura:coe", coe.spellID, coe.castTime)
  elseif conflag.usable then
    nag:decide("cast:conflagrate", conflag.spellID, conflag.castTime)
  elseif shadowburn.usable then
    nag:decide("cast:shadowburn", shadowburn.spellID, shadowburn.castTime)
  elseif chaosBolt.usable then
    nag:decide("cast:chaos_bolt", chaosBolt.spellID, chaosBolt.castTime)
  else
    -- Use Incinerate as filler
    nag:decide("filler:incinerate", 29722) -- Incinerate = 29722
  end

  -- Look into the future, and adjust the present if the future does not look bright enough
  local timeOfNextNextSpell = timeOfNextSpell + math.max(nag.next.time, nag.last_known_gcd)
  -- Priority: refresh Immolate at all costs
  if not immo.expired and nag.next.what ~= "aura:immo" then
    -- Try again with Immolate in the future
    immo = nag:isAuraExpired("immo", "target", timeOfNextNextSpell)
    if immo.expired then
      nag:decide("aura:immo:future", immo.spellID, immo.castTime)
    end
  end

  nag:postDecide(lastDecision)

  return true
end
