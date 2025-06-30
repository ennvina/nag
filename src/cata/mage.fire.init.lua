aura_env.enabled = false
aura_env.icon = nil
aura_env.icon_name = nil
aura_env.last_known_gcd = 1.5

aura_env.last_target = nil
aura_env.cm_until = 0 -- Critical Mass
aura_env.sf_until = 0 -- Shadow & Flame (Critical Mass from warlocks)
aura_env.lb_until = 0 -- Living Bomb
aura_env.alysrazor = false -- Alysra's Razor
aura_env.hot_streak = false
aura_env.pyro_until = 0
aura_env.pyros_cast = {}
aura_env.pyro_casting_on = nil
aura_env.casting = nil
aura_env.orb_last_cast = 0

aura_env.debug = false

aura_env.check_t12_2p = function()
  local itemIDs = {71290,71286,71287,71288,71289,71511,71507,71508,71510,71509}
  local equippedCount = 0
  
  for _, itemID in ipairs(itemIDs) do
    if equippedCount == 2 then
      return true
    end
    if IsEquippedItem(itemID) then
      equippedCount = equippedCount + 1
    end
  end
  
  return false
end
aura_env.has_t12_2p = aura_env.check_t12_2p()

aura_env.may_hardcast_pyro = function()
  -- Function inspired by https://wago.io/rjljulogr
  
  -- Get current Haste
  local haste = UnitSpellHaste("player")
  
  -- Get current Crit%, for Fire
  local crit = GetSpellCritChance(3) -- 3 = Fire school magic
  if aura_env.alysrazor then  -- Do we have Alysra's Razor buff?
    -- Note: test doesn't anticipate if buff will be present at end of current cast
    -- It would be harder to check and the difference would be marginal
    crit = crit + 75
  end
  if crit > 100 then -- Clamp if too much crit (happens typically with Alysra's Razor)
    crit = 100
  end
  
  local hasT122P = aura_env.has_t12_2p
  
  -- Compute haste breakpoint; latest formula available here
  -- https://discord.com/channels/253212375790911489/1174788019534971031/1307400365888765982
  local baseHaste = hasT122P and 178 or 176
  local hasteIncrementRatio = hasT122P and 0.481 or 0.417
  local hasteNegativeExponent = hasT122P and -0.000275 or -0.000201
  
  local expectedHaste = hasteIncrementRatio * crit + (hasteNegativeExponent * crit^2) + baseHaste
  
  if haste - expectedHaste > 0 then
    return true
  else
    return false 
  end
end

--[[
aura_env.dot_duration = function(spellID)
  local duration = (GetSpellDescription(spellID) or ""):match("over (%d*.?%d*) sec")
  if duration ~= "" then
    return tonumber(duration)
  else
    return nil
  end
end

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

aura_env.pyroCastTime = function(unit)
  -- Estimate min and max Pyro cast time, based on unit range
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

aura_env.pyroExpiration = function(unit)
  local i = 1
  local name, _, _, _, _, expirationTime, _, _, _, spellId = UnitDebuff(unit, i, "PLAYER")
  while name do
    if spellId == 11366 or spellId == 92315 then -- Pyro = 11366, Pyro! = 92315
      return expirationTime
    end
    i = i+1
    name, _, _, _, _, expirationTime, _, _, _, spellId = UnitDebuff(unit, i, "PLAYER")
  end
  
  return 0
end

aura_env.lbExpiration = function(unit)
  local i = 1
  local name, _, _, _, _, expirationTime, _, _, _, spellId = UnitDebuff(unit, i, "PLAYER")
  while name do
    if spellId == 44457 then -- Living Bomb = 44457
      return expirationTime
    end
    i = i+1
    name, _, _, _, _, expirationTime, _, _, _, spellId = UnitDebuff(unit, i, "PLAYER")
  end
  
  return 0
end

aura_env.cmExpiration = function(unit)
  local i = 1
  local name, _, _, _, _, expirationTime, _, _, _, spellId = UnitDebuff(unit, i)
  while name do
    if spellId == 22959 then -- Critical Mass = 22959
      return expirationTime
    end
    i = i+1
    name, _, _, _, _, expirationTime, _, _, _, spellId = UnitDebuff(unit, i)
  end
  
  return 0
end

aura_env.sfExpiration = function(unit)
  local i = 1
  local name, _, _, _, _, expirationTime, _, _, _, spellId = UnitDebuff(unit, i)
  while name do
    if spellId == 17800 then -- Shadow and Flame = 17800
      return expirationTime
    end
    i = i+1
    name, _, _, _, _, expirationTime, _, _, _, spellId = UnitDebuff(unit, i)
  end
  
  return 0
end

--[[
aura_env.getUnitTokenByGUID = function(guid)
  print("MUST FIX getUnitTokenByGUID")
  return "target" -- @TODO
end
]]