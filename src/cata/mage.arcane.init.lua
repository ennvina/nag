aura_env.enabled = false
aura_env.icon = nil
aura_env.icon_name = nil
aura_env.phase = ""
aura_env.last_known_gcd = 1.5

aura_env.last_target = nil
aura_env.am_until = 0 -- Arcane Missiles!
aura_env.ap_until = 0 -- Arcane Power
aura_env.cc_until = 0 -- Clearcasting
aura_env.evoc_until = 0 -- Evocation
aura_env.casting = nil
aura_env.orb_last_cast = 0
aura_env.barrage_last_cast = 0

aura_env.debug = false

--[[
aura_env.findDebuff = function(spellID, unit)
  if not unit then return nil end
  
  local i = 1
  local name, icon, count, dispelType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId, canApplyAura, isBossDebuff, castByPlayer, nameplateShowAll, timeMod = UnitDebuff(unit, i, "PLAYER")
  while name do
    if spellId == spellID then
      return name, icon, count, dispelType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId, canApplyAura, isBossDebuff, castByPlayer, nameplateShowAll, timeMod
    end
    i = i+1
    name, icon, count, dispelType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId, canApplyAura, isBossDebuff, castByPlayer, nameplateShowAll, timeMod = UnitDebuff(unit, i, "PLAYER")
  end
  
  return nil
end
]]

aura_env.travelTime = function(unit)
  -- Estimate min and max travel time, based on unit range
  -- Due to how range works, we can only get a min and max value
  local minRange, maxRange = WeakAuras.GetRange(unit, true)
  
  local minCast, maxCast
  
  if not minRange or minRange < 8 then
    minCast = 0
  elseif minRange < 28 then
    minCast = 0.3
  elseif minRange < 35 then
    minCast = 1.1
  elseif minRange < 40 then
    minCast = 1.3
  else
    minCast = 1.7
  end
  
  if not maxRange or maxRange > 30 then
    maxCast = 2
  elseif maxRange > 28 then
    maxCast = 1.6
  elseif maxRange > 8 then
    maxCast = 1.4
  else
    maxCast = 0.5
  end
  
  return minCast, maxCast
end

aura_env.buffExpiration = function(unit, buffId)
  local i = 1
  local name, _, _, _, _, expirationTime, _, _, _, spellId = UnitBuff(unit, i)
  while name do
    if spellId == buffId then
      return expirationTime
    end
    i = i+1
    name, _, _, _, _, expirationTime, _, _, _, spellId = UnitBuff(unit, i)
  end
  
  return 0
end

aura_env.debuffExpiration = function(unit, debuffId)
  local i = 1
  local name, _, _, _, _, expirationTime, _, _, _, spellId = UnitDebuff(unit, i)
  while name do
    if spellId == debuffId then
      return expirationTime
    end
    i = i+1
    name, _, _, _, _, expirationTime, _, _, _, spellId = UnitDebuff(unit, i)
  end
  
  return 0
end