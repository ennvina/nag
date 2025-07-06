---- Intro is provided to trick the IDEs into accepting the code is a syntactically correct Lua function
---- THIS MUST BE REMOVED BEFORE INSERTION IN THE WEAKAURAS
aura_env.mop.warlock.destro.exec =
----

function (ev)

  -- The Next Action Guide (NAG) is a module that handles the logic of what spell to cast next.
  -- This is done in two steps:
  -- 1. Gather information about the current state of the game, such as cooldowns, buffs, debuffs, etc.
  -- 2. Analyze the gathered information and decide what spell to cast next.

  -- Step 1. Gather information about the current state of the game

  -- Step 1.1 Align with the new target, if it has changed
  aura_env.nag.enabled = UnitExists("target") and UnitCanAttack("player", "target")
  local current_target = UnitGUID("target")
  if current_target ~= aura_env.nag.last_target then
    if current_target then
      aura_env.nag:fetchTargetDebuffs()
    else
      aura_env.nag:resetTargetDebuffs()
    end
    aura_env.nag.last_target = current_target
  end

  -- Step 1.2 Analyze CLEU we just received, if it was a CLEU
  if ev == "COMBAT_LOG_EVENT_UNFILTERED" then
    local _, event, _, sourceGUID, _, _, _, destGUID = CombatLogGetCurrentEventInfo()
    local spellID, spellName, spellSchool = select(12, CombatLogGetCurrentEventInfo()) -- For SPELL_*

    if not event then -- Ignore non-events
      return aura_env.nag.enabled
    end

    aura_env.nag:trace(event, 'from:'..(sourceGUID or 'no_src'), 'to:'..(destGUID or 'no_dst'), spellID, spellName)

    local cleuUsed = false

    local fromPlayer = sourceGUID == UnitGUID("player") -- Events originated by player only

    -- SPELL_CAST_START, SPELL_CAST_SUCCESS, SPELL_CAST_FAILED, SPELL_INTERRUPT are used to track which spell is being cast
    if fromPlayer and event == "SPELL_CAST_START" then
      local startTime, endTime = GetTime(), GetTime()+0.001*select(4, GetSpellInfo(spellID))
      aura_env.nag:setCasting(spellID, current_target, startTime, endTime) -- Assume _CAST_START is always done on target
      cleuUsed = true
      if aura_env.config.trace then
        DevTools_Dump({ casting = aura_env.nag.casting })
      end
    elseif fromPlayer and (event == "SPELL_CAST_SUCCESS" or event == "SPELL_CAST_FAILED" or event == "SPELL_INTERRUPT") then
      aura_env.nag:setCasting() -- Casting ended, either clear it ot set it to GCD
      cleuUsed = true
    end

    -- SPELL_CAST_SUCCESS is used to track last time a cooldown was used
    local cd = aura_env.nag.cd[spellID]
    if cd and fromPlayer then
      if event == "SPELL_CAST_SUCCESS" then
        cd.cast = GetTime() -- Update last cast time
        if aura_env.config.trace then
          DevTools_Dump({ cooldown = { key = cd.key, last_cast = cd.cast }})
        end
      end
    end

    -- SPELL_AURA_APPLIED, SPELL_AURA_REFRESH, SPELL_AURA_REMOVED are used to track buffs and debuffs
    local aura = aura_env.nag.auras[spellID]
    if aura and (not aura.selfOnly or fromPlayer) then
      if aura.helpful or current_target == destGUID then
        if event == "SPELL_AURA_APPLIED" or event == "SPELL_AURA_REFRESH" then
            aura.expiration = aura_env.nag:auraExpiration(aura.key)
            cleuUsed = true
        elseif event == "SPELL_AURA_REMOVED" then
            aura.expiration = 0
            cleuUsed = true
        end
        if aura_env.config.trace then
          DevTools_Dump({ aura = { key = aura.key, expiration = aura.expiration, remaining = aura.expiration >= GetTime() and (aura.expiration-GetTime()) or -1 } })
        end
      end
    end

    -- SPELL_CAST_START, SPELL_CAST_SUCCESS, SPELL_CAST_FAILED, SPELL_INTERRUPT, SPELL_DAMAGE, SPELL_MISSED are used to track casts
    local cast = aura_env.nag.casts[spellID]
    if cast and fromPlayer then
      if event == "SPELL_CAST_START" then
        if current_target then
          cast.casting_on = current_target -- Assume casting on target
          cast.sent[current_target] = 0
          cleuUsed = true
        end
      elseif event == "SPELL_CAST_SUCCESS" then
        cast.sent[destGUID] = GetTime()
        cast.casting_on = nil -- Please test if overwrite in case of e.g. double pyro
        cleuUsed = true
      elseif event == "SPELL_CAST_FAILED" or event == "SPELL_INTERRUPT" then
        if cast.casting_on then
          cast.sent[cast.casting_on] = nil
          cast.casting_on = nil -- Please test if overwrite in case of e.g. double pyro
          cleuUsed = true
        end
      elseif event == "SPELL_DAMAGE" or event == "SPELL_MISSED" then
        cast.sent[destGUID] = nil
        cleuUsed = true
      end
      if aura_env.config.trace then
        DevTools_Dump({ cast = { key = cast.key, casting_on = cast.casting_on, sent = cast.sent } })
      end
    end

    -- SPELL_AURA_APPLIED, SPELL_AURA_REFRESH, SPELL_AURA_REMOVED are used to track procs
    -- This is just a simpler version of buffs/debuffs
    local proc = aura_env.nag.procs[spellID]
    if proc and fromPlayer then
      if event == "SPELL_AURA_APPLIED" or event == "SPELL_AURA_REFRESH" then
        proc.active = true
        cleuUsed = true
      elseif event == "SPELL_AURA_REMOVED" then
        proc.active = false
        cleuUsed = true
      end
      if aura_env.config.trace then
        DevTools_Dump({ proc = { key = proc.key, active = proc.active } })
      end
    end

    if not cleuUsed then
      -- Stop now if there is nothing new
      return aura_env.nag.enabled
    end
  end

  if not aura_env.nag.enabled then
    return false
  end

  -- Step 2. Analyze the gathered information and decide what spell to cast next

  local timeOfNextSpell = aura_env.nag:getTimeOfNextSpell()

  local gcdCD = select(2, GetSpellCooldown(61304))
  if gcdCD ~= 0 then
    aura_env.nag.last_known_gcd = gcdCD
  end

  local lastDecision = aura_env.nag.next -- Cache for future use in debugging

  local immoExpired, immoRefreshSpellID, immoRefreshCastTime = aura_env.nag:isAuraExpired("immo", "target", timeOfNextSpell)
  local coeExpired, coeRefreshSpellID, coeRefreshCastTime = aura_env.nag:isAuraExpired("coe", "target", timeOfNextSpell)
  local shadowburnUsable, shadowburnSpellID, shadowburnCastTime = aura_env.nag:canCast("shadowburn", timeOfNextSpell)
  local chaosBoltUsable, chaosBoltSpellID, chaosBoltCastTime = aura_env.nag:canCast("chaos_bolt", timeOfNextSpell)
  local conflagUsable, conflagSpellID, conflagCastTime = aura_env.nag:canCast("conflagrate", timeOfNextSpell)
  if immoExpired then
    aura_env.nag:decide("aura:immo", immoRefreshSpellID, immoRefreshCastTime)
  elseif coeExpired then
    aura_env.nag:decide("aura:coe", coeRefreshSpellID, coeRefreshCastTime)
  elseif conflagUsable then
    aura_env.nag:decide("cast:conflagrate", conflagSpellID, conflagCastTime)
  elseif shadowburnUsable then
    aura_env.nag:decide("cast:shadowburn", shadowburnSpellID, shadowburnCastTime)
  elseif chaosBoltUsable then
    aura_env.nag:decide("cast:chaos_bolt", chaosBoltSpellID, chaosBoltCastTime)
  else
    -- Use Incinerate as filler
    aura_env.nag:decide("filler:incinerate", 29722) -- Incinerate = 29722
  end

  -- Look into the future, and ajust the present if the future does not look bright enough
  local timeOfNextNextSpell = timeOfNextSpell + math.max(aura_env.nag.next.time, aura_env.nag.last_known_gcd)
  -- Priority: refresh Immolate at all costs
  if not immoExpired and aura_env.nag.next.what ~= "aura:immo" then
    -- Try again with Immolate in the future
    immoExpired, immoRefreshSpellID, immoRefreshCastTime = aura_env.nag:isAuraExpired("immo", "target", timeOfNextNextSpell)
    if immoExpired then
      aura_env.nag:decide("aura:immo:future", immoRefreshSpellID, immoRefreshCastTime)
    end
  end

  -- Debug decision changes
  if aura_env.config.debug or aura_env.config.trace then
    local newDecision = aura_env.nag.next
    if newDecision.what ~= lastDecision.what
    or newDecision.cast ~= lastDecision.cast
    or newDecision.icon ~= lastDecision.icon
    or newDecision.name ~= lastDecision.name
    or newDecision.time ~= lastDecision.time
    then -- Log only if changed
      aura_env.nag:log(
        string.format("Decision: %s, %s, %s, %s, %s",
        tostring(newDecision.what), tostring(newDecision.cast), tostring(newDecision.icon), tostring(newDecision.name), tostring(newDecision.time))
      )
    end
  end

  return true
end
