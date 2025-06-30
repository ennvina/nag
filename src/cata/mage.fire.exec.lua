---- Intro is provided to trick the IDEs into accepting the code is a syntactically correct Lua function
---- THIS MUST BE REMOVED BEFORE INSERTION IN THE WEAKAURAS (so does the outro)
local aura_env = aura_env or {}
local function yolo(ev)
----

-- function (ev) -- Remove this comment before insertion in the WeakAuras

  aura_env.enabled = UnitExists("target") and UnitCanAttack("player", "target")
  local current_target = UnitGUID("target")
  if current_target ~= aura_env.last_target then
    if current_target then
      aura_env.cm_until = aura_env.cmExpiration("target")
      aura_env.sf_until = aura_env.sfExpiration("target")
      aura_env.lb_until = aura_env.lbExpiration("target")
      aura_env.pyro_until = aura_env.pyroExpiration("target")
    else
      aura_env.cm_until = 0
      aura_env.sf_until = 0
      aura_env.lb_until = 0
      aura_env.pyro_until = 0
    end
    aura_env.last_target = current_target
  end
  
  if ev == "PLAYER_EQUIPMENT_CHANGED" then
    local had_t12_2p = aura_env.has_t12_2p
    aura_env.has_t12_2p = aura_env.check_t12_2p()
    if not had_t12_2p and aura_env.has_t12_2p then
      print("Equipped 2-piece set bonus of T12.")
    elseif had_t12_2p and not aura_env.has_t12_2p then
      print("Un-equipped 2-piece set bonus of T12.")
    end
  end
  
  -- Analyze CLEU we just received, if it was a CLEU
  if ev == "COMBAT_LOG_EVENT_UNFILTERED" then
    local _, event, _, sourceGUID, _, _, _, destGUID = CombatLogGetCurrentEventInfo()
    local spellID, spellName, spellSchool = select(12, CombatLogGetCurrentEventInfo()) -- For SPELL_*
    
    if not event then -- Ignore non-events
      return aura_env.enabled
    end
    
    if aura_env.debug then
      print(event, 'from:'..(sourceGUID or 'no_src'), 'to:'..(destGUID or 'no_dst'), spellID, spellName)
    end
    
    local cleuUsed = false
    
    if sourceGUID == UnitGUID("player") -- Events originated by player only
    and spellID ~= 22959 -- Except for Critical Mass (all sources are of interest)
    and spellID ~= 17800 -- And except for Shadow and Flame (not castable by mages)
    and spellID ~= 100029 -- And except for Alysra's Razor (not sure if mage is the 'source')
    then
      if event == "SPELL_CAST_START" then
        local startTime, endTime = GetTime(), GetTime()+0.001*select(4, GetSpellInfo(spellID))
        aura_env.casting = { spellID = spellID, guid = current_target, startTime = startTime, endTime = endTime } -- Assume _CAST_START is always done on target
        cleuUsed = true
        if aura_env.debug then
          DevTools_Dump({ casting = aura_env.casting })
        end
      elseif event == "SPELL_CAST_SUCCESS" or event == "SPELL_CAST_FAILED" or event == "SPELL_INTERRUPT" then
        local gcdStart, gcdDuration = GetSpellCooldown(61304) -- GCD = 61304
        if gcdStart and gcdDuration then
          aura_env.casting = { spellID = 61304, guid = nil, startTime = gcdStart, endTime = gcdStart+gcdDuration }
        else
          aura_env.casting = nil
        end
        cleuUsed = true
      end
      
      if event == "SPELL_CAST_SUCCESS" and spellID == 82731 then -- 82731 = Flame Orb
        aura_env.orb_last_cast = GetTime()
        if aura_env.debug then
          DevTools_Dump({ orb = { last_cast = aura_env.orb_last_cast }})
        end
      end
      
      if spellID == 11366 or spellID == 92315 then -- Pyro = 11366, Pyro! = 92315
        if event == "SPELL_AURA_APPLIED" or event == "SPELL_AURA_REFRESH" then
          if current_target == destGUID then
            aura_env.pyro_until = aura_env.pyroExpiration("target")
            cleuUsed = true
          end
        elseif event == "SPELL_AURA_REMOVED" then
          if current_target == destGUID then
            aura_env.pyro_until = 0
            cleuUsed = true
          end
        elseif event == "SPELL_CAST_START" then
          if current_target then
            aura_env.pyro_casting_on = current_target -- Assume casting on target
            aura_env.pyros_cast[current_target] = 0
            cleuUsed = true
          end
        elseif event == "SPELL_CAST_SUCCESS" then
          aura_env.pyros_cast[destGUID] = GetTime()
          aura_env.pyro_casting_on = nil -- Please test if overwrite in case of double pyro
          cleuUsed = true
        elseif event == "SPELL_CAST_FAILED" or event == "SPELL_INTERRUPT" then
          if aura_env.pyro_casting_on then
            aura_env.pyros_cast[aura_env.pyro_casting_on] = nil
            aura_env.pyro_casting_on = nil -- Please test if overwrite in case of double pyro
            cleuUsed = true
          end
        elseif event == "SPELL_DAMAGE" or event == "SPELL_MISSED" then
          aura_env.pyros_cast[destGUID] = nil
          cleuUsed = true
        end
        if aura_env.debug then
          DevTools_Dump({ pyro = { pyro_until = aura_env.pyro_until, pyro_remaining = aura_env.pyro_until >= GetTime() and (aura_env.pyro_until-GetTime()) or -1, pyros_cast = aura_env.pyros_cast, pyro_casting_on = aura_env.pyro_casting_on }})
        end
        
      elseif spellID == 44457 then -- Living Bomb = 44457
        if event == "SPELL_AURA_APPLIED" or event == "SPELL_AURA_REFRESH" then
          if current_target == destGUID then
            aura_env.lb_until = aura_env.lbExpiration("target")
            cleuUsed = true
          end
        elseif event == "SPELL_AURA_REMOVED" then
          if current_target == destGUID then
            aura_env.lb_until = 0
            cleuUsed = true
          end
        end
        if aura_env.debug then
          DevTools_Dump({ lb = { lb_until = aura_env.lb_until, lb_remaining = aura_env.lb_until >= GetTime() and (aura_env.lb_until-GetTime()) or -1 }})
        end
        
      elseif spellID == 48108 then -- Hot Streak = 48108
        if event == "SPELL_AURA_APPLIED" or event == "SPELL_AURA_REFRESH" then
          aura_env.hot_streak = true
          cleuUsed = true
        elseif event == "SPELL_AURA_REMOVED" then
          aura_env.hot_streak = false
          cleuUsed = true
        end
        if aura_env.debug then
          DevTools_Dump({ hot_streak = aura_env.hot_streak })
        end
        
      end
      
    else
      -- Check for Critical Mass / Shadow and Flame debuffs
      
      if spellID == 22959 then -- Critical Mass = 22959
        if event == "SPELL_AURA_APPLIED" or event == "SPELL_AURA_REFRESH" or event == "SPELL_AURA_REMOVED" then -- Get timer also on aura remove, because a _REMOVED may follow a _APPLIED when switching source
          if current_target == destGUID then
            aura_env.cm_until = aura_env.cmExpiration("target")
            cleuUsed = true
          end
          if aura_env.debug then
            DevTools_Dump({ cm = { cm_until = aura_env.cm_until, cm_remaining = aura_env.cm_until >= GetTime() and (aura_env.cm_until-GetTime()) or -1 }})
          end
        end
        
      elseif spellID == 17800 then -- Shadow and Flame = 17800
        if event == "SPELL_AURA_APPLIED" or event == "SPELL_AURA_REFRESH" or event == "SPELL_AURA_REMOVED" then -- Get timer also on aura remove, because a _REMOVED may follow a _APPLIED when switching source
          if current_target == destGUID then
            aura_env.sf_until = aura_env.sfExpiration("target")
            cleuUsed = true
          end
          if aura_env.debug then
            DevTools_Dump({ sf = { sf_until = aura_env.sf_until, sf_remaining = aura_env.sf_until >= GetTime() and (aura_env.sf_until-GetTime()) or -1 }})
          end
        end
        
      elseif spellID == 100029 and destGUID == UnitGUID("player") then -- Alysra's Razor = 100029
        if event == "SPELL_AURA_APPLIED" or event == "SPELL_AURA_REFRESH" then
          aura_env.alysrazor = true
          cleuUsed = true
        elseif event == "SPELL_AURA_REMOVED" then
          aura_env.alysrazor = false
          cleuUsed = true
        end
        if cleuUsed and aura_env.debug then
          DevTools_Dump({ ar = { has_alysras_razor = aura_env.alysrazor }})
        end
      end
    end
    
    if not cleuUsed then
      -- Stop now if there is nothing new
      return aura_env.enabled
    end
  end
  
  if not aura_env.enabled then
    return false
  end
  
  -- Compute icon
  local targetGUID = UnitGUID("target")
  
  local timeOfNextSpell = aura_env.casting and aura_env.casting.endTime or GetTime()
  
  local hasHotStreak = aura_env.hot_streak
  
  local gcdCD = select(2, GetSpellCooldown(61304))
  if gcdCD ~= 0 then
    aura_env.last_known_gcd = gcdCD
  end
  
  local pyroCastTime = hasHotStreak and 0 or 0.001 * select(4, GetSpellInfo(11366)) -- Pyro = 11366
  local pyroTravelTime = select(1, aura_env.pyroCastTime("target"))
  local missingPyroDOT = GetTime() > aura_env.pyro_until
  local timeForPyroLand = timeOfNextSpell + pyroCastTime + pyroTravelTime
  local pyroWillExpire = timeForPyroLand > aura_env.pyro_until
  local isPyroBeingCastOnTarget = aura_env.pyros_cast[targetGUID] == 0 or (aura_env.pyros_cast[targetGUID] and GetTime() < (aura_env.pyros_cast[targetGUID]+3)) -- Max 3 sec before giving up
  local needPyro = (missingPyroDOT or pyroWillExpire) and not isPyroBeingCastOnTarget
  
  local missingLivingBombDOT = GetTime() > aura_env.lb_until
  local livingBombWillExpire = timeOfNextSpell > aura_env.lb_until
  local needLivingBomb = missingLivingBombDOT or livingBombWillExpire
  
  local flameOrbStart, flameOrbCD = GetSpellCooldown(82731) -- 82731 = Flame Orb
  local flameOrbIsReady = flameOrbCD == 0
  local flameOrbWillBeReady = flameOrbCD == gcdCD or flameOrbStart+flameOrbCD <= timeOfNextSpell
  local flameOrbTooSoon = GetTime() < aura_env.orb_last_cast+1 -- Security against queue lags, where the spell is not yet on cooldown (as seen by GetSpellCooldown) even though Flame Orb was cast right now
  local mayCastFlameOrb = (flameOrbIsReady or flameOrbWillBeReady) and not flameOrbTooSoon
  
  local scorchCastTime = 0.001 * select(4, GetSpellInfo(2948)) -- Scorch = 2948
  local criticalMassIsMissing = GetTime() > aura_env.cm_until and GetTime() > aura_env.sf_until
  local criticalMassWillBeMissing = timeOfNextSpell+scorchCastTime > aura_env.cm_until and timeOfNextSpell+scorchCastTime > aura_env.sf_until
  local isScorchBeingCastOnTarget = aura_env.casting and aura_env.casting.spellID == 2948 and aura_env.casting.guid == targetGUID -- Scorch = 2948
  local isCriticalMassIncoming = isPyroBeingCastOnTarget or isScorchBeingCastOnTarget
  local mustCastScorch = (criticalMassIsMissing or criticalMassWillBeMissing) and not isCriticalMassIncoming
  
  local castTimeOfNextSpell = 0
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
    --[[
  elseif needPyro then
    aura_env.icon = 135808 -- Pyroblast
    aura_env.icon_name = "Pyro"
    castTimeOfNextSpell = pyroCastTime
]]
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
    local timeOfNextNextSpell = timeOfNextSpell + math.max(castTimeOfNextSpell, aura_env.last_known_gcd)
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
  
  if aura_env.debug then
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
  
  return true
end

---- Outro is provided only to trick the IDEs into accepting the code is actually used
---- THIS MUST BE REMOVED BEFORE INSERTION IN THE WEAKAURAS (so does the intro)
yolo({});