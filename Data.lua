--[[
  Squizzcap - Data.lua

  Reads Blizzard's death recap (C_DeathRecap) into a plain model the window
  draws from. Field meanings follow Blizzard's own Blizzard_DeathRecap.lua:

    * events come back NEWEST FIRST: events[1] is the hit that killed you
      (Blizzard marks it causedDeath = i == 1).
    * currentHP is your health WHEN THE HIT LANDED, i.e. before it -- their
      tooltip reads "%s sec before death at %s%% health", and the killing
      blow's "Killing blow at %s%% health" is not zero.
    * avoidable / deadly are Blizzard-authored flags on the hit.
    * timeBeforeDeath = newest timestamp - this timestamp.

  12.1 can hand addon code SECRET values. Nothing here compares, measures
  or does arithmetic on a value that might be secret: each is probed first,
  and if any is secret the model is flagged `secret` and carries the raw
  values for the window to pass straight into widget setters (which accept
  secrets), with every calculated section switched off.
]]

local _, addon = ...
local Data = {}
addon.Data = Data

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

-- Environmental deaths carry no spell; these are the icons Blizzard's own
-- recap uses for them.
local ENV_ICONS = {
    DROWNING = "spell_shadow_demonbreath",
    FALLING  = "ability_rogue_quickrecovery",
    FIRE     = "spell_fire_fire",
    LAVA     = "spell_fire_fire",
    SLIME    = "inv_misc_slime_01",
    FATIGUE  = "ability_creature_cursed_05",
}

local SWING_SPELL = 88163 -- what Blizzard shows for a melee swing

local function SpellTexture(spellId)
    if not spellId then return nil end
    local ok, tex = pcall(C_Spell.GetSpellTexture, spellId)
    if ok then return tex end
    return nil
end

local function SpellName(spellId)
    if not spellId or IsSecret(spellId) then return nil end
    local ok, name = pcall(C_Spell.GetSpellName, spellId)
    if ok then return name end
    return nil
end

-- One recap event -> one hit. `secret` is set on the hit if anything in it
-- could not be read as a plain value.
local function BuildHit(ev, maxHealth)
    local hit = { secret = false }
    local numeric = { "amount", "overkill", "absorbed", "resisted", "blocked", "currentHP", "timestamp", "school" }
    for _, k in ipairs(numeric) do
        local v = ev[k]
        if IsSecret(v) then hit.secret = true end
        hit[k] = v
    end
    for _, k in ipairs({ "event", "spellId", "spellName", "sourceName", "hideCaster", "avoidable", "deadly", "environmentalType" }) do
        if IsSecret(ev[k]) then hit.secret = true end
    end

    hit.spellId = ev.spellId
    hit.name = ev.spellName
    hit.source = ev.sourceName

    if hit.secret then
        -- Pass-through only. No event-type branching (a string compare) and
        -- no flag tests; the window shows what it can without reading.
        hit.icon = SpellTexture(ev.spellId)
        return hit
    end

    local event = ev.event
    if event == "SWING_DAMAGE" then
        hit.spellId = SWING_SPELL
        hit.name = ACTION_SWING or MELEE or "Melee"
    elseif event == "ENVIRONMENTAL_DAMAGE" then
        local env = string.upper(ev.environmentalType or "")
        hit.name = _G["ACTION_ENVIRONMENTAL_DAMAGE_" .. env] or ev.environmentalType or UNKNOWN
        hit.icon = "Interface\\Icons\\" .. (ENV_ICONS[env] or "ability_creature_cursed_05")
        hit.environment = true
    end
    hit.name = hit.name or SpellName(hit.spellId) or UNKNOWN
    hit.icon = hit.icon or SpellTexture(hit.spellId) or "Interface\\Icons\\INV_Misc_QuestionMark"

    if ev.hideCaster then
        hit.source = nil
    elseif hit.environment then
        hit.source = ENVIRONMENT_SUBHEADER or "Environment"
    else
        hit.source = ev.sourceName or COMBATLOG_UNKNOWN_UNIT or UNKNOWN
    end

    hit.avoidable = ev.avoidable and true or false
    hit.deadly = ev.deadly and true or false

    hit.amount    = hit.amount or 0
    hit.overkill  = (hit.overkill and hit.overkill > 0) and hit.overkill or 0
    hit.absorbed  = hit.absorbed or 0
    hit.resisted  = hit.resisted or 0
    hit.blocked   = hit.blocked or 0
    hit.school    = hit.school or 1

    -- Health as a percentage of max, before and after the hit. The damage
    -- that actually came off your health is the amount minus any overkill.
    if maxHealth and maxHealth > 0 and hit.currentHP then
        hit.hpBefore = math.min(100, hit.currentHP / maxHealth * 100)
        local taken = math.max(0, hit.amount - hit.overkill)
        hit.hpAfter = math.max(0, hit.hpBefore - taken / maxHealth * 100)
    end
    return hit
end

-- Aggregations for the glance layer. Only ever called on a non-secret model.
local function Summarise(model)
    local hits = model.hits
    local total, mitigated = 0, 0
    local bySpell, bySource = {}, {}
    local highest = 1

    for i, h in ipairs(hits) do
        total = total + h.amount
        mitigated = mitigated + h.absorbed + h.resisted + h.blocked
        if h.amount > hits[highest].amount then highest = i end

        local sk = h.name
        local s = bySpell[sk]
        if not s then
            s = { name = h.name, school = h.school, amount = 0, count = 0 }
            bySpell[sk] = s
        end
        s.amount, s.count = s.amount + h.amount, s.count + 1

        local rk = h.source or UNKNOWN
        local r = bySource[rk]
        if not r then
            r = { name = rk, amount = 0, count = 0, spells = {} }
            bySource[rk] = r
        end
        r.amount, r.count = r.amount + h.amount, r.count + 1
        local rs = r.spells[sk]
        if not rs then
            rs = { name = h.name, school = h.school, amount = 0, count = 0 }
            r.spells[sk] = rs
        end
        rs.amount, rs.count = rs.amount + h.amount, rs.count + 1
    end

    local function Sorted(map)
        local list = {}
        for _, v in pairs(map) do list[#list + 1] = v end
        table.sort(list, function(a, b) return a.amount > b.amount end)
        return list
    end

    model.total = total
    model.mitigated = mitigated
    model.highest = highest
    model.spells = Sorted(bySpell)
    model.sources = Sorted(bySource)
    for _, src in ipairs(model.sources) do
        src.spells = Sorted(src.spells)
    end

    -- How fast: the last moment you were still at 90%+ health, and how long
    -- before death that was. Walk oldest -> newest and keep the latest.
    local healthy
    for i = #hits, 1, -1 do
        local h = hits[i]
        if h.hpBefore and h.hpBefore >= 90 then healthy = h end
    end
    if healthy then
        model.speed = { from = healthy.hpBefore, seconds = healthy.tbd }
    elseif hits[#hits] and hits[#hits].hpBefore then
        -- Never at 90%+ inside the recap. It only holds the last 10 hits
        -- (measured in game 2026-09-27), so the slide began before it and
        -- its length is unknown: measure from the oldest hit, but say so
        -- rather than call it burst or worn down.
        local oldest = hits[#hits]
        model.speed = { from = oldest.hpBefore, seconds = oldest.tbd, partial = true }
    end
    if model.speed and not model.speed.partial then
        model.speed.burst = model.speed.seconds <= 3
    end
end

-- ---------------------------------------------------------------------------
-- Incoming heals
--
-- The recap has damage only. UNIT_COMBAT reports every heal landing on the
-- player with a READABLE amount -- measured 2026-09-28 across the open world
-- and an LFR boss encounter in combat: ~1,900 heals, none secret -- so a
-- short rolling log of them fills the gaps between the recap's hits.
--
-- No healer name or spell: UNIT_COMBAT carries neither (and the combat-text
-- API that does is always secret). Amounts are probed before use anyway, so
-- a heal the game ever hides is skipped, never tripped over.
-- ---------------------------------------------------------------------------

local healLog = {}      -- oldest first: { t = GetTime(), amount, crit }
local HEAL_KEEP = 30    -- seconds; comfortably longer than a 10-hit recap

local healFrame = CreateFrame("Frame")
healFrame:RegisterUnitEvent("UNIT_COMBAT", "player")
healFrame:SetScript("OnEvent", function(_, _, _, kind, flag, amount)
    if IsSecret(kind) or kind ~= "HEAL" then return end
    if IsSecret(amount) or type(amount) ~= "number" or amount <= 0 then return end
    local now = GetTime()
    healLog[#healLog + 1] = { t = now, amount = amount, crit = (not IsSecret(flag)) and flag == "CRITICAL" }
    local cutoff = now - HEAL_KEEP
    while healLog[1] and healLog[1].t < cutoff do table.remove(healLog, 1) end
end)

-- Place the logged heals on the recap's timeline. `deathTime` is GetTime()
-- at PLAYER_DEAD, which lines up with the recap's newest timestamp (the
-- killing blow), so a heal's seconds-before-death is deathTime - its time.
--
-- Each heal goes into the gap it landed in: hit.gapHeals holds the heals
-- between that hit and the one before it (oldest first), hit.gapHeal their
-- sum. Heals from before the recap's first hit are left out -- the recap
-- starts there, so nothing before it can be drawn against.
local function AttachHeals(model, deathTime)
    local hits = model.hits
    local oldestTbd = hits[#hits].tbd
    local total, count = 0, 0
    for i = #healLog, 1, -1 do
        local e = healLog[i]
        local tbd = deathTime - e.t
        if tbd > oldestTbd + 0.001 then break end
        if tbd >= -0.05 then
            tbd = math.max(0, tbd)
            for g = 1, #hits - 1 do
                local newer, older = hits[g], hits[g + 1]
                if tbd >= newer.tbd and tbd <= older.tbd then
                    newer.gapHeals = newer.gapHeals or {}
                    table.insert(newer.gapHeals, 1, { tbd = tbd, amount = e.amount, crit = e.crit })
                    newer.gapHeal = (newer.gapHeal or 0) + e.amount
                    total, count = total + e.amount, count + 1
                    break
                end
            end
        end
    end
    model.healsKnown = true
    model.healTotal = total
    model.healCount = count
end

-- Returns the model for the most recent death (recapID nil), or nil + reason.
-- `deathTime` (GetTime() when you died) lets the incoming heals be placed;
-- without it -- reopening a recap later -- they are simply not attached.
function Data.Read(recapID, deathTime)
    if not (C_DeathRecap and C_DeathRecap.GetRecapEvents) then
        return nil, "death recap API not available"
    end
    local okHas, has = pcall(C_DeathRecap.HasRecapEvents, recapID)
    if not okHas or not has or IsSecret(has) then
        return nil, "no death recap available"
    end
    local okEv, events = pcall(C_DeathRecap.GetRecapEvents, recapID)
    if not okEv or type(events) ~= "table" or #events == 0 then
        return nil, "no death recap events"
    end
    local okMax, maxHealth = pcall(C_DeathRecap.GetRecapMaxHealth, recapID)
    if not okMax then maxHealth = nil end

    local model = {
        hits = {},
        secret = IsSecret(maxHealth),
        maxHealth = maxHealth,
        when = time(),
        zone = GetRealZoneText and GetRealZoneText() or nil,
    }
    local okLink, link = pcall(C_DeathRecap.GetRecapLink, recapID)
    if okLink and not IsSecret(link) then model.link = link end

    local usableMax = (not model.secret) and maxHealth or nil
    for i, ev in ipairs(events) do
        local hit = BuildHit(ev, usableMax)
        hit.causedDeath = (i == 1)
        if hit.secret then model.secret = true end
        model.hits[i] = hit
    end

    if not model.secret then
        local newest = 0
        for _, h in ipairs(model.hits) do
            if h.timestamp and h.timestamp > newest then newest = h.timestamp end
        end
        for _, h in ipairs(model.hits) do
            h.tbd = h.timestamp and (newest - h.timestamp) or 0
        end
        Summarise(model)
        if deathTime and model.hits[1].hpBefore then AttachHeals(model, deathTime) end
    end

    return model
end

-- ---------------------------------------------------------------------------
-- Spell schools
-- ---------------------------------------------------------------------------

local SCHOOL_COLORS = {
    [1]  = { 0.90, 0.80, 0.40 }, -- Physical
    [2]  = { 1.00, 0.90, 0.50 }, -- Holy
    [4]  = { 1.00, 0.50, 0.00 }, -- Fire
    [8]  = { 0.30, 0.90, 0.30 }, -- Nature
    [16] = { 0.50, 0.80, 1.00 }, -- Frost
    [32] = { 0.70, 0.40, 1.00 }, -- Shadow
    [64] = { 1.00, 0.50, 1.00 }, -- Arcane
}
local GREY = { 0.60, 0.60, 0.62 }

-- A multi-school spell takes the colour of its highest school bit, so e.g.
-- Shadowflame (fire + shadow) reads as shadow.
---@return number r, number g, number b
function Data.SchoolColor(school)
    if type(school) ~= "number" or IsSecret(school) then return unpack(GREY) end
    local best
    for mask, c in pairs(SCHOOL_COLORS) do
        if bit.band(school, mask) > 0 and (not best or mask > best) then best = mask end
    end
    return unpack(best and SCHOOL_COLORS[best] or GREY)
end

function Data.SchoolName(school)
    if type(school) ~= "number" or IsSecret(school) then return nil end
    if CombatLogUtil and CombatLogUtil.GetSpellSchoolString then
        local ok, s = pcall(CombatLogUtil.GetSpellSchoolString, school)
        if ok then return s end
    end
    return nil
end

Data.IsSecret = IsSecret
