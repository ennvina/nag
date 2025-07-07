local nag_mixin = {}
_G["NAG_MIXIN"] = nag_mixin

--[[

    NAG Constructor

]]

function nag_mixin:new()
  local object = {
    enabled = false,

    next = {
        what = "", -- Reason for the next cast e.g., "aura:immo"
        cast = nil, -- Spell ID
        icon = nil, -- Icon ID
        time = nil, -- Cast time
        name = nil, -- Name (usually spell name)
    },

    last_known_gcd = 1.5,
    current_target = nil,

    links = {}, -- Links between auras, procs, casts, and cooldowns; filled last

    auras = {}, -- Buffs/debuffs to track

    procs = {}, -- Procs to track on the player

    casts = {}, -- Spells already cast by the player, waiting to hit its target
    casting = nil, -- Spell currently being cast by the player

    cd = {}, -- Cooldowns to track on the player
  }

  self.__index = nil
  setmetatable(object, self)
  self.__index = self

  return object
end


-- Decision making

function nag_mixin:decide(what, spellID, castTime)
  if not spellID or spellID == 0 then
    self:error("Cannot apply decision " .. what .. " with spellID " .. tostring(spellID))
    self.enabled = false
    return 0
  end

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

  self.enabled = true

  return castTime
end

function nag_mixin:preDecide()
  local timeOfNextSpell = self:getTimeOfNextSpell()

  local gcdCD = select(2, GetSpellCooldown(61304)) -- 61304 = Global Cooldown
  if gcdCD ~= 0 then
    self.last_known_gcd = gcdCD
  end

  local lastDecision = self.next -- Cache for future use in debugging (@see postDecide)

  return timeOfNextSpell, lastDecision
end

function nag_mixin:postDecide(lastDecision)
  -- Debug decision changes
  if aura_env.config.debug or aura_env.config.trace then
    local newDecision = self.next
    if newDecision.what ~= lastDecision.what
    or newDecision.cast ~= lastDecision.cast
    or newDecision.icon ~= lastDecision.icon
    or newDecision.name ~= lastDecision.name
    or newDecision.time ~= lastDecision.time
    then -- Log only if changed
      self:log(
        string.format("Decision: %s, %s, %s, %s, %s",
        tostring(newDecision.what), tostring(newDecision.cast), tostring(newDecision.icon), tostring(newDecision.name), tostring(newDecision.time))
      )
    end
  end
end

-- Utility Functions

local function debugPrint(level, color, ...)
  print("|cn" .. color .. ":NAG " .. level .. ":|r", ...)
end

function nag_mixin:trace(...)
  if aura_env.config.trace then
    debugPrint("Trace", "WHITE_FONT_COLOR", ...)
  end
end

function nag_mixin:log(...)
  if aura_env.config.debug or aura_env.config.trace then
    debugPrint("Log", "NORMAL_FONT_COLOR", ...)
  end
end

function nag_mixin:info(...)
  debugPrint("Info", "HIGHLIGHT_LIGHT_BLUE", ...)
end

function nag_mixin:warn(...)
  debugPrint("Warn", "WARNING_FONT_COLOR", ...)
end

function nag_mixin:error(...)
  debugPrint("Error", "ERROR_COLOR", ...)
end

--[[

    Class Properties

    These methods define how to handle properties in general
    Class-specific property initialization will come later, at the end of this script

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

-- Example: nag:addLink("pyro_instant", { cast = "pyro", proc = "hot_streak" })
function nag_mixin:addLink(key, objKeys)
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
function nag_mixin:addAura(key, helpful, selfOnly, spellID)
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

local function debuffExpiration(self, auraDef)
  -- Debuffs should always be on target
  if auraDef.helpful ~= false then
    self:error("debuffExpiration called for a helpful aura: " .. auraDef.spellID)
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

local function buffExpiration(self, auraDef)
  if auraDef.helpful ~= true then
    self:error("buffExpiration called for a harmful aura: " .. auraDef.spellID)
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

function nag_mixin:auraExpiration(key)
  local auraDef = self.auras[key]
  if not auraDef then
    self:warn("Aura " .. key .. " not found")
    return 0
  end
  if auraDef.helpful then
    return buffExpiration(self, auraDef)
  else
    return debuffExpiration(self, auraDef)
  end
end

function nag_mixin:getAuraCastInfo(aura, cast, unit, when)
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

function nag_mixin:isAuraExpired(key, unit, when)
  local aura = self.auras[key]
  if not aura then
    self:warn("Aura " .. key .. " not found")
    return { expired = false, spellID = 0, castTime = 0 }
  end

  local missingAura = GetTime() > aura.expiration -- This one is probably useless @TODO clean it up
  local auraWillBeThere = when <= aura.expiration
  local isBeingCastOnUnit = false
  local refreshSpellID = nil
  local refreshCastTime = nil

  local castLinks = aura.links.cast
  if castLinks then
    -- We know which spell(s) can refresh the aura, we will use this information to have a better idea
    auraWillBeThere = false -- reset the auraWillBeThere, because we will check if it will be there by the time the cast lands
    for _, cast in ipairs(castLinks) do
      if IsSpellKnownOrOverridesKnown(cast.spellID) then
        local auraWillBeThereByCast, isBeingCastOnUnitByCast, castTime = self:getAuraCastInfo(aura, cast, unit, when)
        if (missingAura or not auraWillBeThereByCast) and not isBeingCastOnUnitByCast then
          if not refreshSpellID then
            refreshSpellID = cast.spellID
            refreshCastTime = castTime
          end
        end
        auraWillBeThere = auraWillBeThere or auraWillBeThereByCast
        isBeingCastOnUnit = isBeingCastOnUnit or isBeingCastOnUnitByCast
      end
    end
  end

  local auraExpired = (missingAura or not auraWillBeThere) and not isBeingCastOnUnit
  return { expired = auraExpired, spellID = refreshSpellID or 0, castTime = refreshCastTime or 0 }
end

local function fetchTargetDebuffs(self)
  for _, auraDef in pairs(self.auras) do
    if not auraDef.helpful then -- Non-helpful auras are supposed to be target debuffs
      auraDef.expiration = debuffExpiration(self, auraDef)
    end
  end
end

local function resetTargetDebuffs(self)
  for _, auraDef in pairs(self.auras) do
    if not auraDef.helpful then -- Non-helpful auras are supposed to be target debuffs
      auraDef.expiration = 0
    end
  end
end


-- [[ Procs ]]

function nag_mixin:addProc(key, spellID)
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

function nag_mixin:hasProc(key)
  local proc = self.procs[key]
  if not proc then
    self:warn("Proc " .. key .. " not found")
    return false
  end
  return proc.active
end


-- [[ Casts ]]

function nag_mixin:addCast(key, spellID, travels)
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
function nag_mixin:setCasting(spellID, guid, startTime, endTime)
  if not spellID then
    local gcdStart, gcdDuration = GetSpellCooldown(61304) -- GCD = 61304

    if not gcdStart or gcdStart == 0 or gcdDuration == 0 then
      self.casting = nil
      return
    end

    spellID, startTime, endTime = 61304, gcdStart, gcdStart + gcdDuration
  end

  if spellID ~= 61304 and (aura_env.config.debug or aura_env.config.trace) then
    self:log("Casting:", spellID, C_Spell.GetSpellInfo(spellID).name)
  end

  self.casting = { spellID = spellID, guid = guid, startTime = startTime, endTime = endTime }
end

function nag_mixin:getCastingCost(powerType)
  local powerTypeCost = 0

  if self.casting then
    local powerCosts = C_Spell.GetSpellPowerCost(self.casting.spellID)
    for _, cost in ipairs(powerCosts or {}) do
      if cost.type == Enum.PowerType.BurningEmbers then
        powerTypeCost = powerTypeCost + cost.cost
      end
    end
  end

  return powerTypeCost
end

function nag_mixin:getTimeOfNextSpell()
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
function nag_mixin:getTravelTime(cast, unit)
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

function nag_mixin:getCastTime(cast, when)
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

function nag_mixin:canCast(key, when)
  local cast = self.casts[key]
  if not cast then
    self:warn("Cast " .. key .. " not found")
    return { usable = false }
  end

  -- Check if the spell is known
  local usable = IsSpellKnownOrOverridesKnown(cast.spellID)
  if not usable then
    return { usable = false }
  end

  -- Check if the spell is being cast right now
  local isUsable, noMana = C_Spell.IsSpellUsable(cast.spellID)
  if not isUsable then
    return { usable = false }
  end

  -- Check if the spell depends on a cooldown
  for _, link in ipairs(cast.links.cd or {}) do
    if link and not self:isCooldownReady(link.key, when) then
      return { usable = false }
    end
  end

  --[[ Anticipate that if we are casting right now, the current spell might make the next spell unusable
    For example:
    - The Warlock currently has 1.2 Burning Embers
    - The Warlock is casting Chaos Bolt, that will cost 1 Burning Ember
    - We are looking at the possibility of casting Shadowburn, that requires 1 Burning Ember

    Currently, the game sees that the Warlock still has 1.2 Burning Embers, and believes Shadowburn can be cast
    However, by the time Chaos Bolt is cast, there will be 0.2 Burning Embers left, and Shadowburn will not be usable
    That's what we are trying to detect with the code below
  ]]
  if self.casting then
    local powerCosts = C_Spell.GetSpellPowerCost(cast.spellID)
    local castingPowerCosts = C_Spell.GetSpellPowerCost(self.casting.spellID)
    for _, cost in ipairs(powerCosts or {}) do
      local currentPower = UnitPower("player", cost.type)
      for _, castingCost in ipairs(castingPowerCosts or {}) do
        if cost.type == castingCost.type then
          -- If cost types match, there is a risk that the currently casting spell will make the next spell unusable
          local futurePower = currentPower - castingCost.cost
          if futurePower < cost.cost then
            return { usable = false }
          end
        end
      end
    end
  end

  return { usable = true, spellID = cast.spellID, castTime = self:getCastTime(cast, when) }
end

-- [[ Cooldowns ]]

function nag_mixin:addCooldown(key, spellID, spammable)
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
    spammable = spammable or false, -- If true, the spell may be cast several times in a row, granted there are enough charges

    -- Cooldown state
    cast = 0, -- last time the spell was cast
  }

  self.cd[spellID] = self.cd[key] -- Also map the spellID to the cooldown, for easier access
end

-- Check if the cooldown is ready, which must respect the following conditions:
-- 1. The spell is known
-- 2. The spell's cooldown duration matches the GCD's duration, or the spell will be off cooldown at 'when'
-- 3. GetTime() is greater than the spell last known cast time + 1 second, for extra safety against lags
function nag_mixin:isCooldownReady(key, when)
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
  local notTooSoon = cd.spammable or GetTime() >= cd.cast + 1

  return (isReady or willBeReady) and notTooSoon
end

--[[

    Event Handlers

]]

function nag_mixin:updateTarget()
  self.enabled = UnitExists("target") and UnitCanAttack("player", "target")
  local current_target = UnitGUID("target")
  if current_target ~= self.current_target then
    if current_target then
      fetchTargetDebuffs(self)
    else
      resetTargetDebuffs(self)
    end
    self.current_target = current_target
  end
end

function nag_mixin:analyzeCLEU()
  local _, event, _, sourceGUID, _, _, _, destGUID = CombatLogGetCurrentEventInfo()
  local spellID, spellName, spellSchool = select(12, CombatLogGetCurrentEventInfo()) -- For SPELL_*

  if not event then -- Ignore non-events
    return false
  end

  self:trace(event, 'from:'..(sourceGUID or 'no_src'), 'to:'..(destGUID or 'no_dst'), spellID, spellName)

  local cleuUsed = false

  local current_target = self.current_target

  local fromPlayer = sourceGUID == UnitGUID("player") -- Events originated by player only

  -- SPELL_CAST_START, SPELL_CAST_SUCCESS, SPELL_CAST_FAILED, SPELL_INTERRUPT are used to track which spell is being cast
  if fromPlayer and event == "SPELL_CAST_START" then
    local startTime, endTime = GetTime(), GetTime()+0.001*select(4, GetSpellInfo(spellID))
    self:setCasting(spellID, current_target, startTime, endTime) -- Assume _CAST_START is always done on target
    cleuUsed = true
    if aura_env.config.trace then
      DevTools_Dump({ casting = self.casting })
    end
  elseif fromPlayer and
  (  event == "SPELL_CAST_SUCCESS"
  or(event == "SPELL_CAST_FAILED" and self.casting and spellID == self.casting.spellID)
  or event == "SPELL_INTERRUPT"
  ) then
    self:setCasting() -- Casting ended, either clear it ot set it to GCD
    cleuUsed = true
  end

  -- SPELL_CAST_SUCCESS is used to track last time a cooldown was used
  local cd = self.cd[spellID]
  if cd and fromPlayer then
    if event == "SPELL_CAST_SUCCESS" then
      cd.cast = GetTime() -- Update last cast time
      if aura_env.config.trace then
        DevTools_Dump({ cooldown = { key = cd.key, last_cast = cd.cast }})
      end
    end
  end

   -- SPELL_AURA_APPLIED, SPELL_AURA_REFRESH, SPELL_AURA_REMOVED are used to track buffs and debuffs
   local aura = self.auras[spellID]
   if aura and (not aura.selfOnly or fromPlayer) then
     if aura.helpful or current_target == destGUID then
       if event == "SPELL_AURA_APPLIED" or event == "SPELL_AURA_REFRESH" then
         aura.expiration = self:auraExpiration(aura.key)
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
  local cast = self.casts[spellID]
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
  local proc = self.procs[spellID]
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

  return cleuUsed
end

function nag_mixin:analyzeEvent(event)
  -- Step 1.1 Align with the new target, if it has changed
  -- Always look into it, even if the event that triggered this function is not "PLAYER_TARGET_CHANGED"
  -- Target changes are too important to ignore, and should be caught as soon as possible
  self:updateTarget()

  -- Step 1.2 Analyze CLEU we just received, if it was a CLEU
  if event == "COMBAT_LOG_EVENT_UNFILTERED" then
    local cleuUsed = self:analyzeCLEU()
    if not cleuUsed then -- Stop now if there is nothing new, to save resources
      return false
    end
  end

  return self.enabled
end

--[[

    Warlock-specific init

]]

local nag = _G["NAG_MIXIN"]:new()

nag:info("Initializing |T626007:16:16:0:0:512:512:32:480:32:480|t Warlock...")

-- Buffs and debuffs
nag:log("Initializing auras...")
nag:addAura("coe", false, false, 1490) -- Curse of the Elements = 1490
nag:addAura("master_poisoner", false, false, 58410) -- Master Poisoner = 58410
nag:addAura("fire_breath", false, false, 34889) -- Fire Breath = 34889
nag:addAura("lightning_breath", false, false, 24844) -- Lightning Breath = 24844

nag:addAura("immo", false, true, 348) -- Immolate

nag:addAura("ds:instability", true, true, 113858) -- Dark Soul: Instability = 113858

for key, auraDef in pairs(nag.auras) do
  if type(key) == "string" then
    nag:log("Aura:", key, "Spell ID:", auraDef.spellID, "Helpful:", auraDef.helpful, "Self Only:", auraDef.self)
  end
end

-- Procs
nag:log("Initializing procs...")
nag:addProc("backdraft", 117828) -- Backdraft = 117828
for key, procDef in pairs(nag.procs) do
  if type(key) == "string" then
    nag:log("Proc:", key, "Spell ID:", procDef.spellID)
  end
end

-- Spells being cast
nag:log("Initializing casts...")
nag:addCast("incinerate", 29722, true) -- Incinerate
nag:addCast("immolate", 348, false) -- Immolate
nag:addCast("conflagrate", 17962, false) -- Conflagrate
nag:addCast("chaos_bolt", 116858, true) -- Chaos Bolt
nag:addCast("shadowburn", 17877, false) -- Shadowburn
nag:addCast("coe", 1490, false) -- Curse of Elements
for key, castDef in pairs(nag.casts) do
  if type(key) == "string" then
    nag:log("Cast:", key, "Spell ID:", castDef.spellID, "Travels:", castDef.travels)
  end
end

-- Cooldowns
nag:log("Initializing cooldowns...")
nag:addCooldown("conflag", 17962, true) -- Conflagrate
nag:addCooldown("ds:instability", 113858) -- Dark Soul: Instability = 113858
for key, cdDef in pairs(nag.cd) do
  if type(key) == "string" then
    nag:log("Cooldown:", key, "Spell ID:", cdDef.spellID)
  end
end

-- Links, always added last
nag:log("Initializing links...")
nag:addLink("immo", { aura = "immo", cast = "immolate" })
nag:addLink("conflag", { cast = "conflagrate", cd = "conflag" })
nag:addLink("coe", { aura = "coe", cast = "coe" })
for key, linkDef in pairs(nag.links) do
  if type(key) == "string" then
    nag:log("Link:", key, "Aura:", linkDef.aura and linkDef.aura.key or nil, "Cast:", linkDef.cast and linkDef.cast.key or nil, "Proc:", linkDef.proc and linkDef.proc.key or nil, "Cooldown:", linkDef.cd and linkDef.cd.key or nil)
  end
end

nag:info("Initialization complete.")

aura_env.nag = nag