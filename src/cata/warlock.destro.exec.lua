---- Intro is provided to trick the IDEs into accepting the code is a syntactically correct Lua function
---- THIS MUST BE REMOVED BEFORE INSERTION IN THE WEAKAURAS (so does the outro)
local aura_env = aura_env or {}
local function yolo(ev)
----

-- function (ev) -- Remove this comment before insertion in the WeakAuras

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

  local targetGUID = UnitGUID("target")

  local timeOfNextSpell = aura_env.nag:getTimeOfNextSpell()

  local hasHotStreak = aura_env.hot_streak

  local gcdCD = select(2, GetSpellCooldown(61304))
  if gcdCD ~= 0 then
    aura_env.nag.last_known_gcd = gcdCD
  end

--[[
  local needPyro = aura_env.nag:isAuraExpired("pyro", "target", timeOfNextSpell)

  local pyroCastTime = hasHotStreak and 0 or 0.001 * select(4, GetSpellInfo(11366)) -- Pyro = 11366
  local pyroTravelTime = select(1, aura_env.nag:pyroTravelTime("target"))
  local missingPyroDOT = GetTime() > aura_env.pyro_until
  local timeForPyroLand = timeOfNextSpell + pyroCastTime + pyroTravelTime
  local pyroWillExpire = timeForPyroLand > aura_env.pyro_until
  local isPyroBeingCastOnTarget = aura_env.pyros_cast[targetGUID] == 0 or (aura_env.pyros_cast[targetGUID] and GetTime() < (aura_env.pyros_cast[targetGUID]+3)) -- Max 3 sec before giving up
  local needPyro = (missingPyroDOT or pyroWillExpire) and not isPyroBeingCastOnTarget
]]

--[[
  local needLivingBomb = aura_env.nag:isAuraExpired("living_bomb", "target", timeOfNextSpell)

  local missingLivingBombDOT = GetTime() > aura_env.lb_until
  local livingBombWillExpire = timeOfNextSpell > aura_env.lb_until
  local needLivingBomb = missingLivingBombDOT or livingBombWillExpire
]]

--[[
  local mayCastFlameOrb = aura_env.nag:isCooldownReady("flame_orb", timeOfNextSpell)

  local flameOrbStart, flameOrbCD = GetSpellCooldown(82731) -- 82731 = Flame Orb
  local flameOrbIsReady = flameOrbCD == 0
  local flameOrbWillBeReady = flameOrbCD == gcdCD or flameOrbStart+flameOrbCD <= timeOfNextSpell
  local flameOrbTooSoon = GetTime() < aura_env.orb_last_cast+1 -- Security against queue lags, where the spell is not yet on cooldown (as seen by GetSpellCooldown) even though Flame Orb was cast right now
  local mayCastFlameOrb = (flameOrbIsReady or flameOrbWillBeReady) and not flameOrbTooSoon
]]

--[[
  local mustCastScorch = aura_env.nag:isAuraExpired("cm", "target", timeOfNextSpell) and aura_env.nag:isAuraExpired("saf", "target", timeOfNextSpell)

  local scorchCastTime = 0.001 * select(4, GetSpellInfo(2948)) -- Scorch = 2948
  local criticalMassIsMissing = GetTime() > aura_env.cm_until and GetTime() > aura_env.sf_until
  local criticalMassWillBeMissing = timeOfNextSpell+scorchCastTime > aura_env.cm_until and timeOfNextSpell+scorchCastTime > aura_env.sf_until
  local isScorchBeingCastOnTarget = aura_env.casting and aura_env.casting.spellID == 2948 and aura_env.casting.guid == targetGUID -- Scorch = 2948
  local isCriticalMassIncoming = isPyroBeingCastOnTarget or isScorchBeingCastOnTarget
  local mustCastScorch = (criticalMassIsMissing or criticalMassWillBeMissing) and not isCriticalMassIncoming
]]

  local castTimeOfNextSpell = 0

  local lastDecision = aura_env.nag.next -- Cache for future use in debugging

  local isfExpired, isffRefreshSpellID, isfRefreshCastTime = aura_env.nag:isAuraExpired("isf", "target", timeOfNextSpell)
  local immoExpired, immoRefreshSpellID, immoRefreshCastTime = aura_env.nag:isAuraExpired("immo", "target", timeOfNextSpell)
  local corrupExpired, corrupRefreshSpellID, corrupRefreshCastTime = aura_env.nag:isAuraExpired("corrup", "target", timeOfNextSpell)
  local safExpired, safRefreshSpellID, safRefreshCastTime = aura_env.nag:isAuraExpired("saf", "target", timeOfNextSpell)
  if isfExpired then
    aura_env.nag:decide("aura:isf", isffRefreshSpellID, isfRefreshCastTime)
  elseif immoExpired then
    aura_env.nag:decide("aura:immo", immoRefreshSpellID, immoRefreshCastTime)
  elseif corrupExpired then
    aura_env.nag:decide("aura:corrup", corrupRefreshSpellID, corrupRefreshCastTime)
  elseif safExpired then
    aura_env.nag:decide("aura:saf", safRefreshSpellID, safRefreshCastTime)
  else
    -- Use Shadow Bolt as filler
    aura_env.nag:decide("filler:shadowbolt", 686) -- Shadow Bolt = 686
  end

  -- Look into the future, and ajust the present if the future does not look bright enough
  local timeOfNextNextSpell = timeOfNextSpell + math.max(aura_env.nag.next.time, aura_env.nag.last_known_gcd)
  -- Priority: refresh ISF at all costs
  if not isfExpired and aura_env.nag.next.what ~= "aura:isf" then
    -- Try again with ISF in the future
    isfExpired, isffRefreshSpellID, isfRefreshCastTime = aura_env.nag:isAuraExpired("isf", "target", timeOfNextNextSpell)
    if isfExpired then
      aura_env.nag:decide("aura:isf:future", isffRefreshSpellID, isfRefreshCastTime)
    end
  end

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

  --[[
  if not InCombatLockdown() and needPyro then
    aura_env.icon = 135808 -- Pyroblast
    aura_env.icon_name = "Pyro"
    castTimeOfNextSpell = pyroCastTime
  elseif not InCombatLockdown() and mayCastFlameOrb then
    aura_env.icon = 451164 -- Flame Orb
    aura_env.icon_name = "Orb"
  elseif mustCastScorch then
    aura_env.icon = 135827 -- Scorch
    aura_env.icon_name = "Scorch"
    castTimeOfNextSpell = scorchCastTime
  elseif hasHotStreak and aura_env.config.pyro_over_lb then
    aura_env.icon = 135808 -- Pyroblast
    aura_env.icon_name = "Pyro"
  elseif needLivingBomb then
    aura_env.icon = 236220 -- Living Bomb
    aura_env.icon_name = "LB"
  elseif hasHotStreak then
    aura_env.icon = 135808 -- Pyroblast
    aura_env.icon_name = "Pyro"
  elseif mayCastFlameOrb then
    aura_env.icon = 451164 -- Flame Orb
    aura_env.icon_name = "Orb"
  elseif aura_env.config.ffb_over_fb then
    aura_env.icon = 236217 -- Frostfire Bolt
    aura_env.icon_name = "FFB"
    castTimeOfNextSpell = 0.001 * select(4, GetSpellInfo(44614)) -- Frostfire Bolt = 44614
  elseif aura_env.config.check_hardcast_pyro and aura_env.may_hardcast_pyro() then
    aura_env.icon = 135808 -- Pyroblast
    aura_env.icon_name = "Pyro"
    castTimeOfNextSpell = pyroCastTime
  else
    aura_env.icon = 135812 -- Fireball
    aura_env.icon_name = "FB"
    castTimeOfNextSpell = 0.001 * select(4, GetSpellInfo(133)) -- Fireball = 133
  end

  -- Override with Scorch if needed, to guarantee 100% uptime on Critical Mass
  if InCombatLockdown() and aura_env.icon_name ~= "Scorch" and aura_env.icon_name ~= "Pyro" and not isCriticalMassIncoming then
    local timeOfNextNextSpell = timeOfNextSpell + math.max(castTimeOfNextSpell, aura_env.nag.last_known_gcd)
    if timeOfNextNextSpell+scorchCastTime > aura_env.cm_until and timeOfNextNextSpell+scorchCastTime > aura_env.sf_until then
      aura_env.icon = 135827 -- Scorch
      aura_env.icon_name = "Scorch"
    end
  end

  -- Replace Fireball with Scorch if it allows to refresh Living Bomb slightly sooner
  if aura_env.config.scorch_more_often and (aura_env.icon_name == "FB" or aura_env.icon_name == "FFB") then
    if aura_env.lb_until < timeOfNextSpell+scorchCastTime+0.25 then -- Add 0.25 to account for delay and player reactivity, and threshold before we lose too much damage
      aura_env.icon = 135827 -- Scorch
      aura_env.icon_name = "Scorch"
    end
  end

  if aura_env.config.trace then
    DevTools_Dump(
      {
        decision = {
          general = {
            targetGUID=targetGUID,
            timeOfNextSpell=timeOfNextSpell,
            hasHotStreak=hasHotStreak,
            GetTime = GetTime(),
          },

          pyro = {
            pyroCastTime=pyroCastTime,
            pyroTravelTime=pyroTravelTime,
            missingPyroDOT=missingPyroDOT,
            timeForPyroLand=timeForPyroLand,
            pyroWillExpire=pyroWillExpire,
            isPyroBeingCastOnTarget=isPyroBeingCastOnTarget,
            needPyro=needPyro,
            pyroExpiresAt = aura_env.pyro_until,
          },

          lb = {
            missingLivingBombDOT=missingLivingBombDOT,
            livingBombWillExpire=livingBombWillExpire,
            needLivingBomb=needLivingBomb,
            lbExpiresAt = aura_env.lb_until,
          },

          icon = {
            id = aura_env.icon,
            spell = aura_env.icon_name
          }
        }
      }
    )
  end
]]

  return true
end

---- Outro is provided only to trick the IDEs into accepting the code is actually used
---- THIS MUST BE REMOVED BEFORE INSERTION IN THE WEAKAURAS (so does the intro)
yolo({});