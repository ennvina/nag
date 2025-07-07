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
  local dsi = nag:isAuraExpired("ds:instability", "player", timeOfNextSpell)
  local shadowburn = nag:canCast("shadowburn", timeOfNextSpell)
  local chaosBolt = nag:canCast("chaos_bolt", timeOfNextSpell)
  local conflag = nag:canCast("conflagrate", timeOfNextSpell)
 
  local currentBurningEmbers = UnitPower("player", Enum.PowerType.BurningEmbers, true) * 0.1
  local futureBurningEmbers = currentBurningEmbers - nag:getCastingCost(Enum.PowerType.BurningEmbers)
  -- @TODO define what is a good burst window for Chaos Bolt and Shadowburn using the prefer_cb_on_burst option
  local isBurstWindow = not dsi.expired -- For now make it simple: burst window = Dark Soul: Instability

  -- Cast / refresh Immolate first
  if immo.expired then
    nag:decide("aura:immo", immo.spellID, immo.castTime)

  -- Cast Curse of the Elements if missing and no one else applies an equivalent debuff
  elseif coe.expired
  and nag:isAuraExpired("master_poisoner", "target", timeOfNextSpell).expired
  and nag:isAuraExpired("fire_breath", "target", timeOfNextSpell).expired
  and nag:isAuraExpired("lightning_breath", "target", timeOfNextSpell).expired
  then
    nag:decide("aura:coe", coe.spellID, coe.castTime)

  -- Cast Shadowburn before being overcapped
  elseif shadowburn.usable and futureBurningEmbers >= 3.5 then
    nag:decide("cast:shadowburn:capped", shadowburn.spellID, shadowburn.castTime)

  -- Cast Chaos Bolt before being overcapped
  elseif chaosBolt.usable and futureBurningEmbers >= 3.5 then
    nag:decide("cast:chaos_bolt:capped", chaosBolt.spellID, chaosBolt.castTime)

  -- Cast Shadowburn during burst windows
  elseif shadowburn.usable and isBurstWindow then
    nag:decide("cast:shadowburn:burst", shadowburn.spellID, shadowburn.castTime)

  -- Cast Chaos Bolt during burst windows
  elseif chaosBolt.usable and isBurstWindow then
    nag:decide("cast:chaos_bolt:burst", chaosBolt.spellID, chaosBolt.castTime)

  -- Cast Conflagrate if there are charges available
  elseif conflag.usable then
    nag:decide("cast:conflagrate", conflag.spellID, conflag.castTime)

  -- Cast Shadowburn as pseudo-filler, if not setup to be cast only in burst windows
  elseif shadowburn.usable and not aura_env.config.prefer_cb_on_burst then
    nag:decide("cast:shadowburn", shadowburn.spellID, shadowburn.castTime)

  -- Cast Chaos Bolt as pseudo-filler, if not setup to be cast only in burst windows
  elseif chaosBolt.usable and not aura_env.config.prefer_cb_on_burst then
    nag:decide("cast:chaos_bolt", chaosBolt.spellID, chaosBolt.castTime)

  -- Cast Incinerate as filler
  else
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
