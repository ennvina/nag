---- Intro is provided to trick the IDEs into accepting the code is a syntactically correct Lua function
---- THIS MUST BE REMOVED BEFORE INSERTION IN THE WEAKAURAS (so does the outro)
local aura_env = aura_env or {}
local function yolo(ev)
----

-- function (ev) -- Remove this comment before insertion in the WeakAuras

  aura_env.enabled = UnitExists("target") and UnitCanAttack("player", "target")
  local current_target = UnitGUID("target")
  if current_target ~= aura_env.last_target then
    aura_env.last_target = current_target
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
        -- @TODO SPELL_CHANNEL_CAST_START / END
      end
      
      if event == "SPELL_CAST_SUCCESS" and spellID == 82731 then -- 82731 = Flame Orb
        aura_env.orb_last_cast = GetTime()
        if aura_env.debug then
          DevTools_Dump({ orb = { last_cast = aura_env.orb_last_cast }})
        end
        
      elseif event == "SPELL_CAST_SUCCESS" and spellID == 44425 then -- 44425 = Arcane Barrage
        aura_env.barrage_last_cast = GetTime()
        if aura_env.debug then
          DevTools_Dump({ barrage = { last_cast = aura_env.barrage_last_cast }})
        end
        
      elseif spellID == 12042 then -- Arcane Power = 12042
        if event == "SPELL_AURA_APPLIED" or event == "SPELL_AURA_REFRESH" then
          aura_env.ap_until = aura_env.buffExpiration("player", 12042)
          cleuUsed = true
        elseif event == "SPELL_AURA_REMOVED" then
          if current_target == destGUID then
            aura_env.ap_until = 0
            cleuUsed = true
          end
        end
        if aura_env.debug then
          DevTools_Dump({ ap = { ap_until = aura_env.ap_until, ap_remaining = aura_env.ap_until >= GetTime() and (aura_env.ap_until-GetTime()) or -1 }})
        end
        
      elseif spellID == 12051 then -- Evocation = 12051
        if event == "SPELL_AURA_APPLIED" or event == "SPELL_AURA_REFRESH" then
          aura_env.evoc_until = aura_env.buffExpiration("player", 12051)
          cleuUsed = true
        elseif event == "SPELL_AURA_REMOVED" then
          aura_env.evoc_until = 0
          cleuUsed = true
        end
        if aura_env.debug then
          DevTools_Dump({ evoc = { evoc_until = aura_env.evoc_until, evoc_remaining = aura_env.evoc_until >= GetTime() and (aura_env.evoc_until-GetTime()) or -1 }})
        end
        
      elseif spellID == 79683 then -- Arcane Missiles! = 79683
        if event == "SPELL_AURA_APPLIED" or event == "SPELL_AURA_REFRESH" then
          aura_env.am_until = aura_env.buffExpiration("player", 79683)
          cleuUsed = true
        elseif event == "SPELL_AURA_REMOVED" then
          aura_env.am_until = 0
          cleuUsed = true
        end
        if aura_env.debug then
          DevTools_Dump({ am = { am_until = aura_env.am_until, am_remaining = aura_env.am_until >= GetTime() and (aura_env.am_until-GetTime()) or -1 }})
        end
        
      elseif spellID == 12536 then -- Clearcasting (mage) = 12536
        if event == "SPELL_AURA_APPLIED" or event == "SPELL_AURA_REFRESH" then
          aura_env.cc_until = aura_env.buffExpiration("player", 12536)
          cleuUsed = true
        elseif event == "SPELL_AURA_REMOVED" then
          aura_env.cc_until = 0
          cleuUsed = true
        end
        if aura_env.debug then
          DevTools_Dump({ cc = { cc_until = aura_env.cc_until, cc_remaining = aura_env.cc_until >= GetTime() and (aura_env.cc_until-GetTime()) or -1 }})
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
  
  local gcdCD = select(2, GetSpellCooldown(61304))
  if gcdCD ~= 0 then
    aura_env.last_known_gcd = gcdCD
  end
  
  local mana = UnitPower("player", Enum.PowerType.Mana)
  local manaMax = UnitPowerMax("player", Enum.PowerType.Mana)
  local manaPercent = (type(manaMax) == 'number' and manaMax > 0) and (100 * mana / manaMax) or 0
  
  local manaGemStartTime, manaGemCD = C_Container.GetItemCooldown(36799) -- Mana Gem (item) = 36799
  local manaGemWillBeReady = manaGemCD == gcdCD or manaGemStartTime+manaGemCD <= timeOfNextSpell
  
  local arcanePowerStartTime, arcanePowerCD = GetSpellCooldown(12042) -- Arcane Power = 12042
  local arcanePowerWillBeReady = arcanePowerCD == gcdCD or arcanePowerStartTime+arcanePowerCD <= timeOfNextSpell
  
  local barrageStartTime, barrageCD = GetSpellCooldown(44425) -- Arcane Barrage = 44425
  local barrageIsReady = barrageCD == 0
  local barrageWillBeReady = barrageCD == gcdCD or barrageStartTime+barrageCD <= timeOfNextSpell
  local barrageTooSoon = GetTime() < aura_env.barrage_last_cast+1 -- Security against queue lags, where the spell is not yet on cooldown (as seen by GetSpellCooldown) even though Arcane Barrage was cast right now
  local mayCastBarrage = (barrageIsReady or barrageWillBeReady) and not barrageTooSoon
  
  local evocStartTime, evocCD = GetSpellCooldown(12051) -- Evocation = 12051
  local evocWillBeReady = evocCD == gcdCD or evocStartTime+evocCD <= timeOfNextSpell
  local evocWillBeAvailableIn = evocWillBeReady and 0 or (evocStartTime + evocCD - GetTime())
  
  local arcaneBlastDebuff = C_UnitAuras.GetPlayerAuraBySpellID(36032) -- Arcane Blast (debuff) = 36032
  local nbArcaneBlastStacks = arcaneBlastDebuff and arcaneBlastDebuff.applications or 0
  if aura_env.casting and aura_env.casting.spellID == 30451 and nbArcaneBlastStacks < 4 then -- Arcane Blast (spell) = 30451
    -- Anticipate the next stack of Arcane Blast if currently casting the spell
    nbArcaneBlastStacks = nbArcaneBlastStacks + 1
  end
  
  local missilesBuff = C_UnitAuras.GetPlayerAuraBySpellID(79683) -- Arcane Missiles! (buff) = 79683
  -- Special case for Arcane Missiles: must track buff explicitly, because there is a bug by the game client which does not send SPELL_AURA_REFRESH
  local missilesWillBeReady = timeOfNextSpell < aura_env.am_until or (missilesBuff and timeOfNextSpell < missilesBuff.expirationTime)
  
  local clearcastingWillBeReady = timeOfNextSpell < aura_env.cc_until
  
  local flameOrbStart, flameOrbCD = GetSpellCooldown(82731) -- 82731 = Flame Orb
  local flameOrbIsReady = flameOrbCD == 0
  local flameOrbWillBeReady = flameOrbCD == gcdCD or flameOrbStart+flameOrbCD <= timeOfNextSpell
  local flameOrbTooSoon = GetTime() < aura_env.orb_last_cast+1 -- Security against queue lags, where the spell is not yet on cooldown (as seen by GetSpellCooldown) even though Flame Orb was cast right now
  local mayCastFlameOrb = (flameOrbIsReady or flameOrbWillBeReady) and not flameOrbTooSoon
  
  local blastCastTime = 0.001 * select(4, GetSpellInfo(30451)) -- Blast = 30451
  local missilesCastTime = 0.001 * select(4, GetSpellInfo(5143)) -- Missiles = 5143 / @TODO channel time
  local evocCastTime = 0.001 * select(4, GetSpellInfo(12051)) -- Evocation = 12051 / @TODO channel time
  
  --[[ Icons:
  135735 = Arcane Blast
  136096 = Arcane Missiles
  136048 = Arcane Power
  236205 = Arcane Barrage
  237358 = Conjured Mana Cake
  136075 = Evocation
  451164 = Flame Orb
  134132 = Mana Gem
  ]]
  local isEvocPhase = evocWillBeReady and manaPercent < aura_env.config.mana_pc_before_evoc
  local isBurnPhase = not isEvocPhase and (evocWillBeReady or evocWillBeAvailableIn < aura_env.config.evoc_cd_before_burn)
  if isBurnPhase then
    aura_env.phase = WrapTextInColorCode("BURN", "ffff4000")
  elseif isEvocPhase then
    aura_env.phase = "Evoc"
  else
    aura_env.phase = "Regen"
  end
  local castTimeOfNextSpell = 0
  if not InCombatLockdown() and manaPercent < 99 then
    aura_env.icon = 237358
    aura_env.icon_name = "Drink"
  elseif isBurnPhase and (manaPercent < aura_env.config.mana_pc_managem) and manaGemWillBeReady then
    aura_env.icon = 134132
    aura_env.icon_name = "ManaGem"
  elseif isBurnPhase and InCombatLockdown() and mayCastFlameOrb then
    aura_env.icon = 451164 -- Flame Orb
    aura_env.icon_name = "Orb"
  elseif isBurnPhase then
    aura_env.icon = 135735
    aura_env.icon_name = "Blast"
    castTimeOfNextSpell = blastCastTime
  elseif isEvocPhase then
    aura_env.icon = 136075
    aura_env.icon_name = "Evoc"
    castTimeOfNextSpell = evocCastTime
  elseif clearcastingWillBeReady or nbArcaneBlastStacks < aura_env.config.min_blasts_regen then
    aura_env.icon = 135735
    aura_env.icon_name = "Blast"
    castTimeOfNextSpell = blastCastTime
  elseif manaPercent < aura_env.config.mana_pc_regen and missilesWillBeReady then
    aura_env.icon = 136096
    aura_env.icon_name = "Missiles"
    castTimeOfNextSpell = missilesCastTime
  elseif manaPercent < aura_env.config.mana_pc_regen and mayCastBarrage and nbArcaneBlastStacks >= 2 then -- From 2 stacks and onward, Barrage costs less than Blast
    aura_env.icon = 236205
    aura_env.icon_name = "Barrage"
  elseif nbArcaneBlastStacks < 4 then
    aura_env.icon = 135735
    aura_env.icon_name = "Blast"
    castTimeOfNextSpell = blastCastTime
  elseif missilesWillBeReady then
    aura_env.icon = 136096
    aura_env.icon_name = "Missiles"
    castTimeOfNextSpell = missilesCastTime
  elseif manaPercent < 90 and mayCastBarrage then
    aura_env.icon = 236205
    aura_env.icon_name = "Barrage"
  else -- Default spell if no other spell is available, which is unlikely
    aura_env.icon = 135735
    aura_env.icon_name = "Blast"
    castTimeOfNextSpell = blastCastTime
  end
  
  if aura_env.debug then
    DevTools_Dump(
      {
        decision = {
          general = {
            targetGUID=targetGUID,
            timeOfNextSpell=timeOfNextSpell,
            GetTime = GetTime(),
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