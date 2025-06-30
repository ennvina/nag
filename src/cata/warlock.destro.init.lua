aura_env.nag = {
  enabled = false,

  next = {
    what = "", -- Reason for the next cast e.g., "aura:immo"
    cast = nil, -- Spell ID
    icon = nil, -- Icon ID
    time = nil, -- Cast time
    name = nil, -- Name (usually spell name)
  },

  last_known_gcd = 1.5,
  last_target = nil,

  links = {}, -- Links between auras, procs, casts, and cooldowns; filled last

  auras = {}, -- Buffs/debuffs to track

  procs = {}, -- Procs to track on the player

  casts = {}, -- Spells already cast by the player, waiting to hit its target
  casting = nil, -- Spell currently being cast by the player

  cd = {}, -- Cooldowns to track on the player

  -- Methods written below, separated for clarity
}


-- Decision making

function aura_env.nag:decide(what, spellID, castTime)
  local spellInfo = C_Spell.GetSpellInfo(spellID)

  if not spellInfo then
    self:error("Spell ID " .. spellID .. " not found")
    self.next = {
      what = what,
      cast = spellID,
      icon = "Interface\\Icons\\INV_Misc_QuestionMark",
      name = "???",
      time = castTime or 0
    }
    return 0
  end

  if castTime == nil then
    castTime = 0.001 * (spellInfo.castTime or 0)
  end

  self.next = {
    what = what,
    cast = spellID,
    icon = spellInfo.iconID,
    name = spellInfo.name,
    time = castTime
  }

  return castTime
end

-- Utility Functions

local function debugPrint(level, color, ...)
  print("|cn" .. color .. ":NAG " .. level .. ":|r", ...)
end

function aura_env.nag:trace(...)
  if aura_env.config.trace then
    debugPrint("Trace", "WHITE_FONT_COLOR", ...)
  end
end

function aura_env.nag:log(...)
  if aura_env.config.debug or aura_env.config.trace then
    debugPrint("Log", "NORMAL_FONT_COLOR", ...)
  end
end

function aura_env.nag:info(...)
  debugPrint("Info", "HIGHLIGHT_LIGHT_BLUE", ...)
end

function aura_env.nag:warn(...)
  debugPrint("Warn", "WARNING_FONT_COLOR", ...)
end

function aura_env.nag:error(...)
  debugPrint("Error", "ERROR_COLOR", ...)
end

--[[
function aura_env.nag:dotDuration(spellID)
  local duration = (GetSpellDescription(spellID) or ""):match("over (%d*.?%d*) sec")
  if duration ~= "" then
    return tonumber(duration)
  else
    return nil
  end
end

function aura_env.nag:findDebuff(self, spellID, unit)
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


-- [[ Links ]]

--[[ Link combinations
  - Aura <-> Cast     - The 'aura' can be refreshed by casting the 'cast' spell
  - Aura <-> Proc     - unused yet
  - Aura <-> Cooldown - unused yet
  - Cast <-> Proc     - The 'cast' spell can be cast instantly, under the influence of 'proc'
  - Proc <-> Cooldown - unused yet
  - Cast <-> Cooldown - The 'cast' spell can be cast only when the 'cooldown' is ready
]]

-- Example: aura_env.nag:addLink("pyro_instant", { cast = "pyro", proc = "hot_streak" })
function aura_env.nag:addLink(key, objKeys)
  if self.links[key] then
    self:warn("Link " .. key .. " already exists, overwriting it")
  end

  local aura = self.auras[objKeys.aura]
  if objKeys.aura and not aura then
    self:warn("Aura " .. objKeys.aura .. " not found, link will not work")
    objKeys.aura = nil
  end
  local proc = self.procs[objKeys.proc]
  if objKeys.proc and not proc then
    self:warn("Proc " .. objKeys.proc .. " not found, link will not work")
    objKeys.proc = nil
  end
  local cast = self.casts[objKeys.cast]
  if objKeys.cast and not cast then
    self:warn("Cast " .. objKeys.cast .. " not found, link will not work")
    objKeys.cast = nil
  end
  local cd = self.cd[objKeys.cd]
  if objKeys.cd and not cd then
    self:warn("Cooldown " .. objKeys.cd .. " not found, link will not work")
    objKeys.cd = nil
  end

  self.links[key] = {
    key = key,
    aura = aura,
    proc = proc,
    cast = cast,
    cd = cd,
  }

  -- Link back to the aura, proc, cast, and cooldown
  local linkBack = function(def)
    if def then
      local newLink = self.links[key]
      local defLinks = def.links
      for _, k in ipairs({ 'aura', 'proc', 'cast', 'cd' }) do
        if k ~= def.type then -- Do not link back e.g. proc to proc
          if not defLinks[k] then
            defLinks[k] = {}
          end
          tinsert(defLinks[k], newLink[k])
        end
      end
    end
  end
  linkBack(aura)
  linkBack(proc)
  linkBack(cast)
  linkBack(cd)
end


--[[ Auras ]]

-- key = internal identifier
-- helpful = true for player buff, false for target debuff; do not support (yet) target buffs or player debuffs, which would be a bit weird for a NAG
-- selfOnly = true if the buff/debuff must originate from the player, false if it can cast by anyone, including the player
-- spellID = spell to track
function aura_env.nag:addAura(key, helpful, selfOnly, spellID)
  if self.auras[key] then
    self:warn("Aura " .. key .. " already exists, overwriting it")
  end

  self.auras[key] = {
    -- Base properties
    type = 'aura',
    key = key,
    links = {},

    -- Aura properties
    spellID = spellID,
    helpful = helpful,
    self = selfOnly,

    -- Aura state
    expiration = 0,
  }

  self.auras[spellID] = self.auras[key] -- Also map the spellID to the aura, for easier access
end

local function debuffExpiration(auraDef)
  -- Debuffs should always be on target
  if auraDef.helpful ~= false then
    aura_env.nag:error("debuffExpiration called for a helpful aura: " .. auraDef.spellID)
    return 0
  end
  -- local unit = buff.helpful and "player" or "target"
  -- local filter = buff.helpful and "HELPFUL" or "HARMFUL"
  -- if buff.selfOnly then
  --   filter = filter.."|PLAYER"
  -- end
  local unit = "target"
  local filter = auraDef.selfOnly and "HARMFUL|PLAYER" or "HARMFUL"

  local i = 1
  local aura = C_UnitAuras.GetAuraDataByIndex(unit, i ,filter)
  while aura do
    if aura.spellId == auraDef.spellID then
      return aura.expirationTime
    end
    i = i+1
    aura = C_UnitAuras.GetAuraDataByIndex(unit, i ,filter)
  end

  return 0
end

local function buffExpiration(auraDef)
  if auraDef.helpful ~= true then
    aura_env.nag:error("buffExpiration called for a harmful aura: " .. auraDef.spellID)
    return 0
  end
  local aura = C_UnitAuras.GetPlayerAuraBySpellID(auraDef.spellID);
  if aura then
    if not auraDef.selfOnly or UnitIsUnit("player", aura.sourceUnit) then
      return aura.expirationTime
    end
  end
  return 0
end

function aura_env.nag:auraExpiration(key)
  local auraDef = self.auras[key]
  if not auraDef then
    self:warn("Aura " .. key .. " not found")
    return 0
  end
  if auraDef.helpful then
    return buffExpiration(auraDef)
  else
    return debuffExpiration(auraDef)
  end
end

function aura_env.nag:getAuraCastInfo(aura, cast, unit, when)
    -- Take into account for cast time and travel time
    local minTravelTime, maxTravelTime, giveUpTravelTime = self:getTravelTime(cast, unit)
    -- We use minTravelTime to avoid refreshing the aura too soon
    -- Remember we're trying to know if the aura is (or will be) expired for sure, not when it will potentially expire
    local castTime = self:getCastTime(cast, when)
    local timeForSpellLand = when + castTime + minTravelTime
    local auraWillBeThere = timeForSpellLand <= aura.expiration

    -- But maybe the spell is being cast right now, in which case we will not consider the aura expired
    local unitGUID = UnitGUID(unit)
    local isBeingCastOnUnit = cast.sent[unitGUID] == 0 or (cast.sent[unitGUID] ~= nil and GetTime() < (cast.sent[unitGUID]+giveUpTravelTime))

    return auraWillBeThere, isBeingCastOnUnit, castTime
end

function aura_env.nag:isAuraExpired(key, unit, when)
  local aura = self.auras[key]
  if not aura then
    self:warn("Aura " .. key .. " not found")
    return false, nil, nil
  end

  local missingAura = GetTime() > aura.expiration -- This one is probably useless @TODO clean it up
  local auraWillBeThere = when <= aura.expiration
  local isBeingCastOnUnit = false
  local suggestionRefreshSpellID = nil
  local suggestionCastTime = nil

  local castLinks = aura.links.cast
  if castLinks then
    -- We know which spell(s) can refresh the aura, we will use this information to have a better idea
    auraWillBeThere = false -- reset the auraWillBeThere, because we will check if it will be there by the time the cast lands
    for _, cast in ipairs(castLinks) do
      if IsSpellKnownOrOverridesKnown(cast.spellID) then
        local auraWillBeThereByCast, isBeingCastOnUnitByCast, castTime = self:getAuraCastInfo(aura, cast, unit, when)
        if (missingAura or not auraWillBeThereByCast) and not isBeingCastOnUnitByCast then
          if not suggestionRefreshSpellID then
            suggestionRefreshSpellID = cast.spellID
            suggestionCastTime = castTime
          end
        end
        auraWillBeThere = auraWillBeThere or auraWillBeThereByCast
        isBeingCastOnUnit = isBeingCastOnUnit or isBeingCastOnUnitByCast
      end
    end
  end

  -- if aura_env.config.debug or aura_env.config.trace then
  --   if ((missingAura or not auraWillBeThere) and not isBeingCastOnUnit) == true then
  --     self:log("Aura:", key, "Unit:", unit, "When:", when, "Missing:", missingAura, "BeThere:", auraWillBeThere, "Casting:", isBeingCastOnUnit, "SuggSpellID:", suggestionRefreshSpellID, "SuggCastTime:", suggestionCastTime)
  --   end
  -- end

  return (missingAura or not auraWillBeThere) and not isBeingCastOnUnit, suggestionRefreshSpellID, suggestionCastTime
end

function aura_env.nag:fetchTargetDebuffs()
  for _, auraDef in pairs(self.auras) do
    if not auraDef.helpful then -- Non-helpful auras are supposed to be target debuffs
      auraDef.expiration = debuffExpiration(auraDef)
    end
  end
end

function aura_env.nag:resetTargetDebuffs()
  for _, auraDef in pairs(self.auras) do
    if not auraDef.helpful then -- Non-helpful auras are supposed to be target debuffs
      auraDef.expiration = 0
    end
  end
end


-- [[ Procs ]]

function aura_env.nag:addProc(key, spellID)
  if self.procs[key] then
    self:warn("Proc " .. key .. " already exists, overwriting it")
  end

  self.procs[key] = {
    -- Base properties
    type = 'proc',
    key = key,
    links = {},

    -- Proc properties
    spellID = spellID,

    -- Proc state
    active = false,
  }

  self.procs[spellID] = self.procs[key] -- Also map the spellID to the proc, for easier access
end

function aura_env.nag:hasProc(key)
  local proc = self.procs[key]
  if not proc then
    self:warn("Proc " .. key .. " not found")
    return false
  end
  return proc.active
end


-- [[ Casts ]]

function aura_env.nag:addCast(key, spellID, travels)
  if self.casts[key] then
    self:warn("Cast " .. key .. " already exists, overwriting it")
  end

  self.casts[key] = {
    -- Base properties
    type = 'cast',
    key = key,
    links = {},

    -- Cast properties
    spellID = spellID,
    travels = travels, -- If true, the spell has a travel time, otherwise it hits instantly when cast
    -- The property is currently limited to telling whether or not a travel time occurs
    -- We can morph this property later on, from boolean to something else, to pin-point the right travel time for each spell

    -- Cast state
    sent = {}, -- map of ongoing casts, key is target's GUID, value is the time when the cast was sent
    casting_on = nil, -- unit name to which the cast is being cast
  }

  self.casts[spellID] = self.casts[key] -- Also map the spellID to the cast, for easier access
end

-- Fill the .casting table, which knows which spell is being cast by the player right now, and on which unit
-- It takes a spellID, a GUID of the target, a start time, and an end time.
-- There are 3 use cases:
-- 1. If the spellID is not nil, then the cast has started and not finished yet -> use startTime and endTime provided
-- 2. If the spellID is nil, then the cast has finished, in which case, either:
-- 2a. The Global Cooldown is triggered -> use the Global Cooldown (GCD) start and end times to simulate a lingering cast
-- 2b. The GCD is not triggered -> set the casting to nil, because the player is completely free to cast something else right now
function aura_env.nag:setCasting(spellID, guid, startTime, endTime)
  if not spellID then
    local gcdStart, gcdDuration = GetSpellCooldown(61304) -- GCD = 61304

    if not gcdStart or gcdStart == 0 or gcdDuration == 0 then
      self.casting = nil
      return
    end

    spellID, startTime, endTime = 61304, gcdStart, gcdStart + gcdDuration
  end

  self.casting = { spellID = spellID, guid = guid, startTime = startTime, endTime = endTime }
end

function aura_env.nag:getTimeOfNextSpell()
  return self.casting and self.casting.endTime or GetTime()
end

--[[ Estimate min and max cast time, based on unit range
Due to how range works, we can only get a min and max value

It returns three values:
- minTravelTime is the minimum travel time for the current range
- maxTravelTime is the maximum travel time for the current range
- giveUpTravelTime is the time after which we should give up on the cast

All values are estimations, and may be more or less accurate depending on factors, such as:
- unit moving closer or farther away after the cast has started
- server latency or otherwise issues in the client-server timing capabilities
- wrong estimation of the unit's range e.g., altered by hitboxes
- wrong estimation of the spell's travel time (remember it is based on empirical data)
]]
function aura_env.nag:getTravelTime(cast, unit)
  if not cast.travels then
    return 0, 0, 0 -- Instant hit = zero travel time
  end

  -- Otherwise estimate the travel time based on the unit's range
  -- We have performed advanced tests against Pyroblast and Fireball, and we'll generalize it, for now
  -- It may be wise to run additional tests against other spells, in case they have different travel times

  local minRange, maxRange = WeakAuras.GetRange(unit, true)

  local minCast, maxCast

--[[ Original values, based on empirical data ]]
--[[
  if not minRange or minRange < 3 then
    minCast = 0 -- min of 0-3
  elseif minRange < 5 then
    minCast = 0.2 -- min of 3-5
  elseif minRange < 7 then
    minCast = 0.27 -- min of 5-7
  elseif minRange < 8 then
    minCast = 0.35 -- min of 7-8
  elseif minRange < 10 then
    minCast = 0.36 -- min of 8-10
  elseif minRange < 15 then
    minCast = 0.42 -- min of 10-15
  elseif minRange < 20 then
    minCast = 0.67 -- min of 15-20
  elseif minRange < 25 then
    minCast = 0.95 -- min of 20-25
  elseif minRange < 30 then
    minCast = 1.1 -- min of 25-30
  elseif minRange < 35 then
    minCast = 1.3 -- min of 30-35
  elseif minRange < 40 then
    minCast = 1.55 -- min of 35-40
  else
    minCast = 1.72 -- min of 40+
  end
]]
  if not minRange or minRange < 3 then
    minCast = 0 -- min of 0-3
  else
    minCast = 0.043 * minRange - 0.07 -- Linear approximation based on the above data
  end

--[[ Original values, based on empirical data ]]
--[[
  if not maxRange or maxRange > 40 then
    maxCast = 2 -- max of 40+ (presumed, cannot test reliably 40+ yd)
  elseif maxRange > 35 then
    maxCast = 1.87 -- max of 35-40
  elseif maxRange > 30 then
    maxCast = 1.67 -- max of 30-35
  elseif maxRange > 25 then
    maxCast = 1.45 -- max of 25-30
  elseif maxRange > 20 then
    maxCast = 1.25 -- max of 20-25
  elseif maxRange > 15 then
    maxCast = 1 -- max of 15-20
  elseif maxRange > 10 then
    maxCast = 0.82 -- max of 10-15
  elseif maxRange > 8 then
    maxCast = 0.62 -- max of 8-10
  elseif maxRange > 7 then
    maxCast = 0.52 -- max of 7-8
  elseif maxRange > 5 then
    maxCast = 0.42 -- max of 5-7
  elseif maxRange > 3 then
    maxCast = 0.35 -- max of 3-5
  else
    maxCast = 0.25 -- max of 0-3
  end
]]
  if not maxRange or maxRange > 40 then
    maxCast = 2 -- max of 40+ (presumed, cannot test reliably 40+ yd)
  else
    maxCast = 0.045 * maxRange + 0.19 -- Linear approximation based on the above data
  end

  local giveUpTime = 3 -- Give up after 3 seconds, to avoid waiting too long for the cast to land

  return minCast, maxCast, giveUpTime
end

function aura_env.nag:getCastTime(cast, when)
  local procLinks = cast.links.proc
  if procLinks then
    for _, proc in ipairs(procLinks) do
      if proc.active then
        -- If the proc is active, the cast time is 0
        -- @TODO use 'when' to determine if the proc will still be active
        return 0
      end
    end
  end

  return 0.001 * select(4, GetSpellInfo(cast.spellID))
end

-- [[ Cooldowns ]]

function aura_env.nag:addCooldown(key, spellID)
  if self.cd[key] then
    self:warn("Cooldown " .. key .. " already exists, overwriting it")
  end

  self.cd[key] = {
    -- Base properties
    type = 'cd',
    key = key,
    links = {},

    -- Cooldown properties
    spellID = spellID,

    -- Cooldown state
    cast = 0, -- last time the spell was cast
  }

  self.cd[spellID] = self.cd[key] -- Also map the spellID to the cooldown, for easier access
end

-- Check if the cooldown is ready, which must respect the following conditions:
-- 1. The spell is known
-- 2. The spell's cooldown duration matches the GCD's duration, or the spell will be off cooldown at 'when'
-- 3. GetTime() is greater than the spell last known cast time + 1 second, for extra safety against lags
function aura_env.nag:isCooldownReady(key, when)
  local cd = self.cd[key]
  if not cd then
    warn("Cooldown " .. key .. " not found")
    return false
  end

  local usable = IsSpellKnownOrOverridesKnown(cd.spellID)
  if not usable then
    return false
  end

  local _, gcdDuration = GetSpellCooldown(61304) -- GCD = 61304
  local cdStart, cdDuration = GetSpellCooldown(cd.spellID)

  local isReady = cdDuration == 0
  local willBeReady = cdDuration == gcdDuration or cdStart + cdDuration <= when
  local notTooSoon = GetTime() >= cd.cast + 1

  return (isReady or willBeReady) and notTooSoon
end

-- [[ Warlock-specific init ]]

aura_env.nag:info("Initializing |T626007:16:16:0:0:512:512:32:480:32:480|t Warlock...")

-- Buffs and debuffs
aura_env.nag:log("Initializing auras...")
aura_env.nag:addAura("coe", false, false, 1490) -- Curse of the Elements = 1490
-- TODO: add:
-- Master Poisoner (Rogue)
-- Ebon Plaguebinder (DK)
-- Earth and Moon (Druid)
-- Fire Breath (pet)
-- Lightning Breath (pet)

aura_env.nag:addAura("immo", false, true, 348) -- Immolate
-- aura_env.nag:addAura("immo", false, true, WOW_PROJECT_ID == WOW_PROJECT_MISTS_CLASSIC and 118297 or 348) -- Immolate (until Cata) = 348, Immolate (MoP) = 118297
aura_env.nag:addAura("corrup", false, true, WOW_PROJECT_ID == WOW_PROJECT_MISTS_CLASSIC and 146739 or 172); -- Corruption (until Cata) = 172, Curruption DoT (MoP) = 146739
aura_env.nag:addAura("agony", false, true, 980); -- Curse of Agony (until Wrath), Bane of Agony (Cata), Agony (MoP), any of them = 980

aura_env.nag:addAura("cm", false, false, 22959) -- Critical Mass = 22959
aura_env.nag:addAura("saf", false, false, 17800) -- Shadow and Flame = 17800

aura_env.nag:addAura("isf", true, true, 85383) -- Improved Soul Fire = 85383

for key, auraDef in pairs(aura_env.nag.auras) do
  if type(key) == "string" then
    aura_env.nag:log("Aura:", key, "Spell ID:", auraDef.spellID, "Helpful:", auraDef.helpful, "Self Only:", auraDef.self)
  end
end

-- Procs
aura_env.nag:log("Initializing procs...")
aura_env.nag:addProc("emp_imp", 47283) -- Empowered Imp = 47283, instant Soul Fire
for key, procDef in pairs(aura_env.nag.procs) do
  if type(key) == "string" then
    aura_env.nag:log("Proc:", key, "Spell ID:", procDef.spellID)
  end
end

-- Spells being cast
aura_env.nag:log("Initializing casts...")
aura_env.nag:addCast("soulfire", 6353, true) -- Soul Fire
aura_env.nag:addCast("shadowbolt", 686, true) -- Shadow Bolt
aura_env.nag:addCast("incinerate", 29722, true) -- Incinerate
aura_env.nag:addCast("immolate", 348, false) -- Immolate
aura_env.nag:addCast("corruption", 172, false) -- Corruption
for key, castDef in pairs(aura_env.nag.casts) do
  if type(key) == "string" then
    aura_env.nag:log("Cast:", key, "Spell ID:", castDef.spellID, "Travels:", castDef.travels)
  end
end

-- Cooldowns
aura_env.nag:log("Initializing cooldowns...")
aura_env.nag:addCooldown("soulburn", 74434) -- Soulburn
aura_env.nag:addCooldown("conflag", 17962) -- Conflagrate
aura_env.nag:addCooldown("cb", WOW_PROJECT_ID == WOW_PROJECT_MISTS_CLASSIC and 116858 or 50796) -- Chaos Bolt (MoP) = 116858, Chaos Bolt (Cata) = 50796
for key, cdDef in pairs(aura_env.nag.cd) do
  if type(key) == "string" then
    aura_env.nag:log("Cooldown:", key, "Spell ID:", cdDef.spellID)
  end
end

-- Links, always added last
aura_env.nag:log("Initializing links...")
aura_env.nag:addLink("saf_in", { aura = "saf", cast = "incinerate" }) -- Prioritize refresh Shadow and Flame by Incinerate
aura_env.nag:addLink("saf_sb", { aura = "saf", cast = "shadowbolt" }) -- Otherwise refresh Shadow and Flame by Shadow Bolt
aura_env.nag:addLink("isf", { aura = "isf", cast = "soulfire" })
aura_env.nag:addLink("immo", { aura = "immo", cast = "immolate" })
aura_env.nag:addLink("corrup", { aura = "corrup", cast = "corruption" })
for key, linkDef in pairs(aura_env.nag.links) do
  if type(key) == "string" then
    aura_env.nag:log("Link:", key, "Aura:", linkDef.aura and linkDef.aura.key or nil, "Cast:", linkDef.cast and linkDef.cast.key or nil, "Proc:", linkDef.proc and linkDef.proc.key or nil, "Cooldown:", linkDef.cd and linkDef.cd.key or nil)
  end
end

aura_env.nag:info("Initialization successful.")