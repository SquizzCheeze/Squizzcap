--[[
  Squizzcap - Death Recap
  WoW 12.0.7 Midnight API

  Uses the native C_DeathInfo API (available since 10.0) to fetch
  Blizzard's own death recap data. Displays a detailed window that
  stays open through release, resurrection, and zoning until closed.

  Also uses CLEU (Combat Log Event Unfiltered) to track both damage
  taken and healing received for a complete recent damage/healing timeline.
]]

local addonName, addon = ...

-- ---------------------------------------------------------------------------
-- Constants & colour helpers
-- ---------------------------------------------------------------------------

local SCHOOL_COLORS = {
    [1]  = { 0.9, 0.8, 0.4 },  -- Physical
    [2]  = { 1.0, 0.9, 0.5 },  -- Holy
    [4]  = { 1.0, 0.5, 0.0 },  -- Fire
    [8]  = { 0.3, 0.9, 0.3 },  -- Nature
    [16] = { 0.5, 0.8, 1.0 },  -- Frost
    [32] = { 0.7, 0.4, 1.0 },  -- Shadow
    [64] = { 0.6, 0.9, 1.0 },  -- Arcane
}

local function GetSchoolColor(schoolMask)
    local r, g, b = 1.0, 1.0, 1.0
    for mask, color in pairs(SCHOOL_COLORS) do
        if bit.band(schoolMask, mask) > 0 then
            r, g, b = color[1], color[2], color[3]
        end
    end
    return r, g, b
end

local function Colorize(text, r, g, b)
    if not r then return text end
    return string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, text)
end

local function FormatNumber(n)
    if not n then return "0" end
    if n >= 1e6 then
        return string.format("%.1fm", n / 1e6)
    elseif n >= 1e4 then
        return string.format("%.1fk", n / 1e3)
    end
    return string.format("%d", n)
end

-- ---------------------------------------------------------------------------
-- Settings / DB
-- ---------------------------------------------------------------------------

local defaults = {
    profile = {
        window = {
            width = 540,
            height = 560,
            scale = 1.0,
            point = "CENTER",
            x = 0,
            y = 0,
        },
        appearance = {
            displayMode = "text",  -- "none", "text"
            fontSize = 12,
        },
    }
}

local db = defaults.profile

local function LoadDB()
    if SquizzcapDB then
        db = SquizzcapDB
        for k, v in pairs(defaults.profile) do
            if db[k] == nil then db[k] = v end
            if type(v) == "table" then
                for k2, v2 in pairs(v) do
                    if db[k][k2] == nil then db[k][k2] = v2 end
                end
            end
        end
    else
        db = CopyTable(defaults.profile)
        SquizzcapDB = db
    end
end

local function SaveDB()
    SquizzcapDB = db
end

local function CopyTable(orig)
    if type(orig) ~= "table" then return {} end
    local copy = {}
    for k, v in pairs(orig) do
        if type(v) == "table" then
            copy[k] = CopyTable(v)
        else
            copy[k] = v
        end
    end
    return copy
end

-- ---------------------------------------------------------------------------
-- UI — the recap window
-- ---------------------------------------------------------------------------

local frame = nil
local contentText = nil

-- Media
local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8x8"

-- Color definitions (match SquizzFrames)
local DARK_BG     = {0.1, 0.1, 0.1, 0.9}
local DARK_BORDER = {0, 0, 0, 1}
local TITLE_BG    = {0.115, 0.115, 0.115, 1}
local PANEL_BG    = {0.115, 0.115, 0.115, 1}
local GREY_TEXT   = {0.7, 0.7, 0.7, 1}

-- Class color accent (lazy-initialized)
local accentColor = {r = 0.7, g = 0.7, b = 0.7}
local accentInited = false

local function InitAccentColor()
    if accentInited then return end
    local _, class = UnitClass("player")
    local color = RAID_CLASS_COLORS[class]
    if color then
        accentColor.r, accentColor.g, accentColor.b = color.r, color.g, color.b
    end
    accentInited = true
end

-- Get player class color
local function GetClassColor()
    InitAccentColor()
    return accentColor.r, accentColor.g, accentColor.b
end

-- StylizeFrame: Apply dark semi-transparent backdrop to a frame (SquizzFrames style)
local function StylizeFrame(f, color, borderColor)
    if not f then return end
    color = color or DARK_BG
    borderColor = borderColor or DARK_BORDER
    f:SetBackdrop({
        bgFile = WHITE_TEXTURE,
        edgeFile = WHITE_TEXTURE,
        edgeSize = 1,
        insets = {left = 1, right = 1, top = 1, bottom = 1},
    })
    f:SetBackdropColor(color[1], color[2], color[3], color[4] or 1)
    f:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
end

local function RenderRecap(data)
    if not frame then
        LoadDB()
        InitAccentColor()

        frame = CreateFrame("Frame", "SquizzcapDeathRecap", UIParent, "BackdropTemplate")
        frame:SetSize(db.window.width, db.window.height)
        frame:SetScale(db.window.scale)
        frame:SetFrameStrata("DIALOG")
        frame:SetClampedToScreen(true)
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local point, _, relPoint, x, y = self:GetPoint()
            db.window.point = point
            db.window.relPoint = relPoint
            db.window.x = x
            db.window.y = y
        end)

        -- Restore saved position
        if db.window.point then
            frame:ClearAllPoints()
            frame:SetPoint(db.window.point, UIParent, db.window.relPoint or "CENTER", db.window.x or 0, db.window.y or 0)
        else
            frame:SetPoint("CENTER")
        end

        -- Dark semi-transparent backdrop with black border
        frame:SetBackdrop({
            bgFile = WHITE_TEXTURE,
            edgeFile = WHITE_TEXTURE,
            edgeSize = 1,
            insets = {left = 1, right = 1, top = 1, bottom = 1},
        })
        frame:SetBackdropColor(unpack(DARK_BG))
        frame:SetBackdropBorderColor(unpack(DARK_BORDER))

        -- Title bar (draggable)
        local titleBar = CreateFrame("Frame", nil, frame)
        titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
        titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
        titleBar:SetHeight(24)
        titleBar:EnableMouse(true)
        titleBar:RegisterForDrag("LeftButton")
        titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
        titleBar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)

        -- Title bar background
        local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
        titleBg:SetAllPoints()
        titleBg:SetColorTexture(unpack(TITLE_BG))

        -- Title text
        local title = titleBar:CreateFontString(nil, "OVERLAY")
        title:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
        title:SetPoint("LEFT", 10, 0)
        title:SetTextColor(1, 1, 1, 1)
        title:SetText("Squizzcap Death Recap")

        -- Class-color accent line under title
        local cr, cg, cb = GetClassColor()
        local accentLine = titleBar:CreateTexture(nil, "BACKGROUND")
        accentLine:SetPoint("BOTTOMLEFT", 0, 0)
        accentLine:SetPoint("BOTTOMRIGHT", 0, 0)
        accentLine:SetHeight(1)
        accentLine:SetColorTexture(cr, cg, cb, 0.5)

        -- Close button (styled)
        local close = CreateFrame("Button", nil, frame, "BackdropTemplate")
        close:SetSize(20, 20)
        close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
        close:SetFrameLevel(frame:GetFrameLevel() + 10)
        close:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        close:SetBackdrop({
            bgFile = WHITE_TEXTURE,
            edgeFile = WHITE_TEXTURE,
            edgeSize = 1,
            insets = {left = 1, right = 1, top = 1, bottom = 1},
        })
        close:SetBackdropColor(0.115, 0.115, 0.115, 1)
        close:SetBackdropBorderColor(0, 0, 0, 1)
        local closeText = close:CreateFontString(nil, "OVERLAY")
        closeText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        closeText:SetPoint("CENTER")
        closeText:SetTextColor(1, 1, 1, 1)
        closeText:SetText("x")
        close:SetHitRectInsets(0, 0, 0, 0)
        close:SetScript("OnEnter", function(self)
            self:SetBackdropColor(cr, cg, cb, 0.6)
            self:SetBackdropBorderColor(cr, cg, cb, 1)
        end)
        close:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.115, 0.115, 0.115, 1)
            self:SetBackdropBorderColor(0, 0, 0, 1)
        end)
        close:SetScript("OnClick", function() frame:Hide() end)

        -- Tip text at bottom
        local tip = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tip:SetPoint("BOTTOM", 0, 10)
        tip:SetTextColor(0.5, 0.5, 0.55)
        tip:SetText("This window stays open until closed.  |cffffffffDrag title bar to move.|r")

        -- Custom scroll frame (no visible scrollbar)
        local scrollFrame = CreateFrame("ScrollFrame", nil, frame)
        scrollFrame:SetPoint("TOPLEFT",  12, -36)
        scrollFrame:SetPoint("BOTTOMRIGHT", -12, 12)
        scrollFrame:EnableMouseWheel(true)
        scrollFrame:SetScript("OnMouseWheel", function(self, delta)
            local newVal = self:GetVerticalScroll() - delta * 50
            self:SetVerticalScroll(math.max(0, math.min(newVal, self:GetVerticalScrollRange())))
        end)

        local scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollFrame:SetScrollChild(scrollChild)

        -- Text frame (created once, stored on frame) - for permanent sections (killing blow, combat stats, damage/healing by source)
        frame.textFrame = CreateFrame("Frame", nil, scrollChild)
        frame.textFrame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
        frame.textFrame:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, 0)
        frame.textFrame:SetHeight(1)
        frame.textFrame:Show()  -- Always show permanent sections

        contentText = frame.textFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        contentText:SetPoint("TOPLEFT", 0, 0)
        contentText:SetWidth(516)
        contentText:SetJustifyH("LEFT")
        contentText:SetSpacing(4)

        -- Recent damage text frame (for Text display mode - column aligned like graph)
        frame.recentDamageTextFrame = CreateFrame("Frame", nil, scrollChild)
        frame.recentDamageTextFrame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
        frame.recentDamageTextFrame:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, 0)
        frame.recentDamageTextFrame:SetHeight(1)
        frame.recentDamageTextFrame:Hide()
        frame.recentDamageTextFrame.bars = {}

        -- Health bar graph frame (created once, stored on frame) - for graph
        -- REMOVED: Graph mode no longer supported
        frame.healthGraph = nil

        -- Make main frame resizable
        frame:SetResizable(true)
        frame:SetResizeBounds(400, 300, 800, 1200)

        -- Resize handle (bottom-right corner)
        local resizeHandle = CreateFrame("Button", nil, frame)
        resizeHandle:SetSize(16, 16)
        resizeHandle:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
        resizeHandle:SetFrameLevel(frame:GetFrameLevel() + 20)
        local resizeTex = resizeHandle:CreateTexture(nil, "OVERLAY")
        resizeTex:SetAllPoints()
        resizeTex:SetColorTexture(1, 1, 1, 0.3)
        -- Diagonal lines for resize indicator
        local line1 = resizeHandle:CreateTexture(nil, "OVERLAY")
        line1:SetColorTexture(1, 1, 1, 0.5)
        line1:SetPoint("BOTTOMRIGHT", -2, 2)
        line1:SetSize(8, 1)
        local line2 = resizeHandle:CreateTexture(nil, "OVERLAY")
        line2:SetColorTexture(1, 1, 1, 0.5)
        line2:SetPoint("BOTTOMRIGHT", -2, 2)
        line2:SetSize(1, 8)
        resizeHandle:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" then
                frame:StartSizing("BOTTOMRIGHT")
            end
        end)
        resizeHandle:SetScript("OnMouseUp", function(self, button)
            frame:StopMovingOrSizing()
            db.window.width = frame:GetWidth()
            db.window.height = frame:GetHeight()
            SaveDB()
        end)
        resizeHandle:SetScript("OnEnter", function(self) resizeTex:SetColorTexture(1, 1, 1, 0.6) end)
        resizeHandle:SetScript("OnLeave", function(self) resizeTex:SetColorTexture(1, 1, 1, 0.3) end)
    end

    local fontSize = db.appearance.fontSize or 12
    contentText:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")

    -- Build the recap text from C_DeathInfo data
    local lines = {}
    local t = function(...) tinsert(lines, string.format(...)) end

    local displayMode = db.appearance.displayMode or "text"
    local showRecentDamageText = (displayMode == "text")

    -- ===== PERMANENT SECTIONS (always rendered) =====
    -- Header
    t(" ")
    t("|cffffaa00=====  KILLING BLOW  =====|r")
    if data.killingBlow then
        local kb = data.killingBlow
        local r, g, b = GetSchoolColor(kb.schoolMask or 1)
        t("  %s hit you for |cffff4444%s|r (%s)  |cff888888(overkill: %s)|r",
          kb.source,
          FormatNumber(kb.amount),
          Colorize(kb.spellName or "Melee", r, g, b),
          FormatNumber(kb.overkill or 0))
    else
        t("  |cff888888(no killing blow data available)|r")
    end

    t(" ")

    -- Combat stats
    t("|cff88aaff=====  COMBAT STATS  =====|r")
    t("  Damage taken:   |cffff4444%s|r",   FormatNumber(data.totalDamage or 0))
    --t("  Healing recv'd: |cff44ff44%s|r",   FormatNumber(data.totalHealing or 0))

    t(" ")

    -- Damage breakdown by source
    t("|cffff4444=====  DAMAGE BY SOURCE  =====|r")
    if data.damageBySource and next(data.damageBySource) then
        local sortedSources = {}
        for name, sd in pairs(data.damageBySource) do
            tinsert(sortedSources, { name = name, total = sd.total, data = sd })
        end
        sort(sortedSources, function(a, b) return a.total > b.total end)

        for _, s in ipairs(sortedSources) do
            local sd = s.data
            t("  |cffff8844%s|r  |cffff4444%s|r  (%d hits)", s.name, FormatNumber(sd.total), sd.count)

            local sortedSpells = {}
            for spellName, spellData in pairs(sd.spells) do
                tinsert(sortedSpells, { name = spellName, total = spellData.total, data = spellData })
            end
            sort(sortedSpells, function(a, b) return a.total > b.total end)

            for _, sp in ipairs(sortedSpells) do
                local r, g, b = GetSchoolColor(sp.data.schoolMask or 1)
                t("    %s x%d  |cffff4444%s|r",
                  Colorize(sp.name, r, g, b),
                  sp.data.count,
                  FormatNumber(sp.data.total))
            end
        end
    else
        t("  |cff888888(no damage data available)|r")
    end

    t(" ")

    -- Healing breakdown
    if data.healBySource and next(data.healBySource) then
        t("|cff44ff44=====  HEALING BY SOURCE  =====|r")
        local sortedHeals = {}
        for name, hd in pairs(data.healBySource) do
            tinsert(sortedHeals, { name = name, total = hd.total, data = hd })
        end
        sort(sortedHeals, function(a, b) return a.total > b.total end)

        for _, s in ipairs(sortedHeals) do
            local hd = s.data
            t("  |cff88ff88%s|r  |cff44ff44%s|r  (%d heals)", s.name, FormatNumber(hd.total), hd.count)
            local sortedSpells = {}
            for spellName, spellData in pairs(hd.spells) do
                tinsert(sortedSpells, { name = spellName, total = spellData.total, data = spellData })
            end
            sort(sortedSpells, function(a, b) return a.total > b.total end)
            for _, sp in ipairs(sortedSpells) do
                t("    %s x%d  |cff44ff44%s|r", sp.name, sp.data.count, FormatNumber(sp.data.total))
            end
        end
        t(" ")
    end
    -- ===== END PERMANENT SECTIONS =====

    -- First, set the text so we can measure its height
    contentText:SetText(table.concat(lines, "\n"))
    local textHeight = contentText:GetStringHeight()

    -- Text frame (permanent sections) - always show
    frame.textFrame:SetHeight(textHeight)
    frame.textFrame:Show()

    -- ===== RECENT DAMAGE SECTION (controlled by displayMode) =====
    -- Build recent damage/healing text frame for Text mode (column-aligned like graph)
    local recentDamageTextFrame = frame.recentDamageTextFrame
    recentDamageTextFrame.bars = recentDamageTextFrame.bars or {}

    -- Build combined timeline: damage taken + healing received
    local timeline = {}

    -- Add damage events
    for _, ev in ipairs(data.damageTimeline or {}) do
        tinsert(timeline, {
            time = ev.time,
            amount = ev.amount,
            spellName = ev.spellName,
            source = ev.source,
            schoolMask = ev.schoolMask,
            isKillingBlow = ev.isKillingBlow,
            overkill = ev.overkill,
            isHeal = false,
            overhealing = 0,
        })
    end

    -- Add healing events (from CLEU data merged in FetchFullDeathRecap)
    for _, ev in ipairs(data.healTimeline or {}) do
        tinsert(timeline, {
            time = ev.time,
            amount = ev.amount,
            spellName = ev.spellName,
            source = ev.source,
            schoolMask = 1,
            isKillingBlow = false,
            overkill = 0,
            isHeal = true,
            overhealing = ev.overhealing or 0,
            critical = ev.critical,
        })
    end

    -- Sort by time (oldest first at top)
    sort(timeline, function(a, b) return a.time < b.time end)

    -- Calculate health at each step by working BACKWARDS from death (0 health)
    local healthPoints = {}
    local healthAfterLast = 0  -- dead after killing blow
    tinsert(healthPoints, healthAfterLast)

    -- Walk backwards through timeline to reconstruct health before each event
    for i = #timeline, 1, -1 do
        local ev = timeline[i]
        local healthBefore
        if ev.isHeal then
            -- Healing going forward = health increases, so going backwards = health decreases
            healthBefore = healthPoints[1] - (ev.amount or 0)
        else
            -- Damage going forward = health decreases, so going backwards = health increases
            healthBefore = healthPoints[1] + (ev.amount or 0)
        end
        tinsert(healthPoints, 1, healthBefore)
    end

    local recapStartHealth = healthPoints[1]
    local barCount = #healthPoints - 1

    -- Column positions for aligned text (matching graph)
    local COL_SPELL = 6
    local COL_SOURCE = 90
    local COL_HEALTH = 220
    local COL_AMOUNT = 290
    local COL_OVERKILL = 390
    local COL_KB = 390
    local maxBarWidth = 500
    local barHeight = 18
    local barSpacing = 4

    -- Create/update bars for recent damage text frame
    for idx = 1, barCount do
        local i = idx
        local newHealth = healthPoints[i + 1]
        local pctHealth = newHealth / recapStartHealth
        local ev = timeline[i]

        local barData = recentDamageTextFrame.bars[idx]
        if not barData then
            local bg = CreateFrame("Frame", nil, recentDamageTextFrame)
            bg:SetSize(maxBarWidth, barHeight)
            bg:SetPoint("TOPLEFT", recentDamageTextFrame, "TOPLEFT", 0, -(idx - 1) * (barHeight + barSpacing))

            -- Background (full width dark)
            local bgTex = bg:CreateTexture(nil, "BACKGROUND")
            bgTex:SetAllPoints()
            bgTex:SetColorTexture(0.15, 0.15, 0.15, 0.8)

            -- Separate font strings for each column
            local txtSpell = bg:CreateFontString(nil, "OVERLAY")
            txtSpell:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
            txtSpell:SetPoint("LEFT", bg, "LEFT", COL_SPELL, 0)
            txtSpell:SetWidth(COL_SOURCE - COL_SPELL - 4)
            txtSpell:SetJustifyH("LEFT")

            local txtSource = bg:CreateFontString(nil, "OVERLAY")
            txtSource:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
            txtSource:SetPoint("LEFT", bg, "LEFT", COL_SOURCE, 0)
            txtSource:SetWidth(COL_HEALTH - COL_SOURCE - 4)
            txtSource:SetJustifyH("LEFT")
            txtSource:SetTextColor(0.67, 0.67, 0.67, 1)

            local txtHealth = bg:CreateFontString(nil, "OVERLAY")
            txtHealth:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
            txtHealth:SetPoint("LEFT", bg, "LEFT", COL_HEALTH, 0)
            txtHealth:SetWidth(COL_AMOUNT - COL_HEALTH - 4)
            txtHealth:SetJustifyH("RIGHT")
            txtHealth:SetTextColor(1, 1, 1, 1)

            local txtAmount = bg:CreateFontString(nil, "OVERLAY")
            txtAmount:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
            txtAmount:SetPoint("LEFT", bg, "LEFT", COL_AMOUNT, 0)
            txtAmount:SetWidth(COL_OVERKILL - COL_AMOUNT - 4)
            txtAmount:SetJustifyH("RIGHT")
            txtAmount:SetTextColor(1, 1, 1, 1)

            local txtOverkill = bg:CreateFontString(nil, "OVERLAY")
            txtOverkill:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
            txtOverkill:SetPoint("LEFT", bg, "LEFT", COL_OVERKILL, 0)
            txtOverkill:SetWidth(COL_KB - COL_OVERKILL - 4)
            txtOverkill:SetJustifyH("LEFT")
            txtOverkill:SetTextColor(1, 1, 0, 1)

            local txtKB = bg:CreateFontString(nil, "OVERLAY")
            txtKB:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
            txtKB:SetPoint("LEFT", bg, "LEFT", COL_KB, 0)
            txtKB:SetWidth(maxBarWidth - COL_KB - 6)
            txtKB:SetJustifyH("LEFT")
            txtKB:SetTextColor(1, 0, 0, 1)

            barData = { bg = bg, txtSpell = txtSpell, txtSource = txtSource, txtHealth = txtHealth, txtAmount = txtAmount, txtOverkill = txtOverkill, txtKB = txtKB }
            recentDamageTextFrame.bars[idx] = barData
        end

        local yPos = -(idx - 1) * (barHeight + barSpacing)
        barData.bg:SetPoint("TOPLEFT", recentDamageTextFrame, "TOPLEFT", 0, yPos)
        barData.bg:Show()

        -- Set column text
        local amount = healthPoints[i] - newHealth
        barData.txtSpell:SetText(ev.spellName or "Melee")
        barData.txtSource:SetText(ev.source or UNKNOWN)
        barData.txtHealth:SetText(math.floor(pctHealth * 100) .. "%")

        if ev.isHeal then
            -- Healing: positive amount, green color
            barData.txtAmount:SetText("+" .. FormatNumber(amount))
            barData.txtAmount:SetTextColor(0.3, 1, 0.3, 1)  -- green for healing
        else
            -- Damage: negative amount, red color
            barData.txtAmount:SetText("-" .. FormatNumber(amount))
            barData.txtAmount:SetTextColor(1, 0.3, 0.3, 1)  -- red for damage
        end

        if ev.overkill and ev.overkill > 0 then
            barData.txtOverkill:SetText("(overkill: " .. FormatNumber(ev.overkill) .. ")")
        elseif ev.overhealing and ev.overhealing > 0 then
            barData.txtOverkill:SetText("(overheal: " .. FormatNumber(ev.overhealing) .. ")")
        else
            barData.txtOverkill:SetText("")
        end
        barData.txtKB:SetText(ev.isKillingBlow and "<--- KILLING BLOW" or "")

        barData.txtSpell:Show()
        barData.txtSource:Show()
        barData.txtHealth:Show()
        barData.txtAmount:Show()
        barData.txtOverkill:Show()
        barData.txtKB:Show()
    end

    -- Hide any unused bars
    for idx = barCount + 1, #recentDamageTextFrame.bars do
        recentDamageTextFrame.bars[idx].bg:Hide()
    end

    local recentDamageTextHeight = barCount > 0 and (barCount * (barHeight + barSpacing)) or 0

    -- Show/hide recent damage frames based on display mode
    if showRecentDamageText and barCount > 0 then
        recentDamageTextFrame:SetHeight(recentDamageTextHeight)
        recentDamageTextFrame:Show()
        -- Position below textFrame
        recentDamageTextFrame:SetPoint("TOPLEFT", frame.textFrame, "BOTTOMLEFT", 0, -10)
    else
        recentDamageTextFrame:Hide()
        recentDamageTextFrame:SetHeight(1)
    end

    -- Hide graph frame (graph mode removed)
    if frame.healthGraph then
        frame.healthGraph:Hide()
    end

    -- Update scroll child height to include text + recent damage
    local totalHeight = textHeight + recentDamageTextHeight
    frame.textFrame:GetParent():SetHeight(totalHeight)
    frame.textFrame:GetParent():SetWidth(460)

    frame:Show()
end

-- ---------------------------------------------------------------------------
-- C_DeathRecap API wrapper (modern WoW 12.0+ death recap API)
-- ---------------------------------------------------------------------------

local function FetchDeathRecap()
    -- Check if C_DeathRecap API is available
    if not C_DeathRecap or not C_DeathRecap.GetRecapEvents then
        return nil, "C_DeathRecap API not available"
    end

    -- Check if there are recap events available
    if not C_DeathRecap.HasRecapEvents() then
        return nil, "No death recap events available"
    end

    -- Get the death recap events (most recent death = recapID 1)
    local events = C_DeathRecap.GetRecapEvents()
    if not events or #events == 0 then
        return nil, "No death recap events returned"
    end

    local maxHealth = C_DeathRecap.GetRecapMaxHealth() or 1
    local totalDamage = 0
    local totalHealing = 0
    local damageBySource = {}
    local healBySource = {}
    local damageTimeline = {}
    local killingBlow = nil

    for _, ev in ipairs(events) do
        -- C_DeathRecap event structure:
        -- ev.spellId, ev.amount, ev.school, ev.timestamp, ev.sourceName, ev.overkill, etc.
        local spellId = ev.spellId or 0
        local spellName = ev.spellName or (spellId > 0 and GetSpellInfo(spellId)) or "Melee"
        local amount = ev.amount or 0
        local schoolMask = ev.school or 1
        local sourceName = ev.sourceName or UNKNOWN
        local timestamp = ev.timestamp or 0
        local overkill = ev.overkill or 0
        local absorbed = ev.absorbed or 0
        local resisted = ev.resisted or 0
        local blocked = ev.blocked or 0

        -- Amount > 0 = damage taken (C_DeathRecap only returns damage events)
        if amount > 0 then
            totalDamage = totalDamage + amount

            if not damageBySource[sourceName] then
                damageBySource[sourceName] = { total = 0, count = 0, spells = {} }
            end
            local sd = damageBySource[sourceName]
            sd.total = sd.total + amount
            sd.count = sd.count + 1

            if not sd.spells[spellName] then
                sd.spells[spellName] = { total = 0, count = 0, schoolMask = schoolMask }
            end
            sd.spells[spellName].total = sd.spells[spellName].total + amount
            sd.spells[spellName].count = sd.spells[spellName].count + 1

            tinsert(damageTimeline, {
                time        = timestamp,
                source      = sourceName,
                spellName   = spellName,
                amount      = amount,
                absorbed    = absorbed,
                resisted    = resisted,
                blocked     = blocked,
                schoolMask  = schoolMask,
                isKillingBlow = (overkill > 0),
                overkill    = overkill,  -- store overkill amount
            })

            if overkill > 0 then
                killingBlow = {
                    source     = sourceName,
                    spellName  = spellName,
                    amount     = amount,
                    overkill   = overkill,
                    schoolMask = schoolMask,
                    time       = timestamp,
                }
            end
        end
    end

    -- If no overkill event, last damage is killing blow
    if not killingBlow and #damageTimeline > 0 then
        killingBlow = damageTimeline[#damageTimeline]
    end

    return {
        totalDamage     = totalDamage,
        totalHealing    = totalHealing,
        maxHealth       = maxHealth,
        damageBySource  = damageBySource,
        healBySource    = healBySource,
        damageTimeline  = damageTimeline,
        killingBlow     = killingBlow,
    }
end

-- ---------------------------------------------------------------------------
-- Enhanced FetchDeathRecap: merges C_DeathRecap damage data with healing data
-- ---------------------------------------------------------------------------
-- C_DeathRecap provides accurate damage timeline and killing blow but NO healing.
-- This adds healing data based on C_DeathRecap timestamps.

local function FetchFullDeathRecap()
    -- First get the base death recap data from C_DeathRecap (damage only)
    local data, err = FetchDeathRecap()
    if not data then
        return nil, err
    end

    -- Since we don't have CLEU, we can only report what C_DeathRecap gives us
    -- (which is damage only - no healing events)
    -- totalHealing will remain 0 from C_DeathRecap
    data.totalHealing = 0
    data.healBySource = {}
    data.healTimeline = {}

    return data
end

-- ---------------------------------------------------------------------------
-- Options Panel (SquizzFrames style)
-- ---------------------------------------------------------------------------

local optionsFrame = nil

local function CreateOptionsPanel()
    if optionsFrame then return optionsFrame end

    optionsFrame = CreateFrame("Frame", "SquizzcapOptionsFrame", UIParent, "BackdropTemplate")
    optionsFrame:SetSize(380, 500)
    optionsFrame:SetPoint("CENTER", 0, 0)
    optionsFrame:SetFrameStrata("DIALOG")
    optionsFrame:SetFrameLevel(520)
    optionsFrame:SetClampedToScreen(true)
    optionsFrame:SetMovable(true)
    optionsFrame:EnableMouse(true)
    optionsFrame:RegisterForDrag("LeftButton")
    optionsFrame:SetScript("OnDragStart", optionsFrame.StartMoving)
    optionsFrame:SetScript("OnDragStop", optionsFrame.StopMovingOrSizing)
    optionsFrame:Hide()

    StylizeFrame(optionsFrame, DARK_BG, DARK_BORDER)

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, optionsFrame)
    titleBar:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", optionsFrame, "TOPRIGHT", -1, -1)
    titleBar:SetHeight(24)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() optionsFrame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() optionsFrame:StopMovingOrSizing() end)

    local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
    titleBg:SetAllPoints()
    titleBg:SetColorTexture(unpack(TITLE_BG))

    local title = titleBar:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    title:SetPoint("LEFT", 10, 0)
    title:SetTextColor(1, 1, 1, 1)
    title:SetText("Squizzcap Options")

    local cr, cg, cb = GetClassColor()
    local accentLine = titleBar:CreateTexture(nil, "BACKGROUND")
    accentLine:SetPoint("BOTTOMLEFT", 0, 0)
    accentLine:SetPoint("BOTTOMRIGHT", 0, 0)
    accentLine:SetHeight(1)
    accentLine:SetColorTexture(cr, cg, cb, 0.5)

    -- Close button
    local close = CreateFrame("Button", nil, optionsFrame, "BackdropTemplate")
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", optionsFrame, "TOPRIGHT", -2, -2)
    close:SetFrameLevel(optionsFrame:GetFrameLevel() + 10)
    close:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    close:SetBackdrop({
        bgFile = WHITE_TEXTURE,
        edgeFile = WHITE_TEXTURE,
        edgeSize = 1,
        insets = {left = 1, right = 1, top = 1, bottom = 1},
    })
    close:SetBackdropColor(0.115, 0.115, 0.115, 1)
    close:SetBackdropBorderColor(0, 0, 0, 1)
    local closeText = close:CreateFontString(nil, "OVERLAY")
    closeText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    closeText:SetPoint("CENTER")
    closeText:SetTextColor(1, 1, 1, 1)
    closeText:SetText("x")
    close:SetHitRectInsets(0, 0, 0, 0)
    close:SetScript("OnEnter", function(self)
        self:SetBackdropColor(cr, cg, cb, 0.6)
        self:SetBackdropBorderColor(cr, cg, cb, 1)
    end)
    close:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.115, 0.115, 0.115, 1)
        self:SetBackdropBorderColor(0, 0, 0, 1)
    end)
    close:SetScript("OnClick", function() optionsFrame:Hide() end)

    -- Content area
    local content = CreateFrame("Frame", nil, optionsFrame)
    content:SetPoint("TOPLEFT", 12, -36)
    content:SetPoint("BOTTOMRIGHT", -12, 12)

    -- Helper: Create a section header
    local function CreateSectionHeader(parent, text, yOffset)
        local header = parent:CreateFontString(nil, "OVERLAY")
        header:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        header:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
        header:SetTextColor(cr, cg, cb, 1)
        header:SetText(text)
        return header
    end

    -- Helper: Create a checkbox
    local function CreateCheckbox(parent, label, yOffset, getValue, onValueChanged)
        local checkbox = CreateFrame("CheckButton", nil, parent, "BackdropTemplate")
        checkbox:SetSize(18, 18)
        checkbox:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
        checkbox:SetBackdrop({
            bgFile = WHITE_TEXTURE,
            edgeFile = WHITE_TEXTURE,
            edgeSize = 1,
            insets = {left = 1, right = 1, top = 1, bottom = 1},
        })
        checkbox:SetBackdropColor(unpack(PANEL_BG))
        checkbox:SetBackdropBorderColor(0, 0, 0, 1)

        local checkedTex = checkbox:CreateTexture(nil, "ARTWORK")
        checkedTex:SetPoint("TOPLEFT", 1, -1)
        checkedTex:SetPoint("BOTTOMRIGHT", -1, 1)
        checkedTex:SetColorTexture(cr, cg, cb, 0.7)
        checkbox:SetCheckedTexture(checkedTex)

        local highlight = checkbox:CreateTexture(nil, "OVERLAY")
        highlight:SetAllPoints()
        highlight:SetColorTexture(cr, cg, cb, 0.1)
        highlight:SetBlendMode("ADD")
        checkbox:SetHighlightTexture(highlight, "ADD")

        local labelText = checkbox:CreateFontString(nil, "OVERLAY")
        labelText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
        labelText:SetPoint("LEFT", checkbox, "RIGHT", 6, 0)
        labelText:SetTextColor(1, 1, 1, 1)
        labelText:SetText(label)

        if getValue then checkbox:SetChecked(getValue()) end

        checkbox:SetScript("OnClick", function(self)
            local checked = self:GetChecked()
            if checked then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            else PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF) end
            if onValueChanged then onValueChanged(checked, self) end
        end)

        return checkbox
    end

    -- Helper: Create a slider
    local function CreateSlider(parent, label, yOffset, minVal, maxVal, step, getValue, onValueChanged)
        local container = CreateFrame("Frame", nil, parent)
        container:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
        container:SetSize(340, 48)

        local labelFS = container:CreateFontString(nil, "OVERLAY")
        labelFS:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
        labelFS:SetPoint("TOPLEFT", 0, 0)
        labelFS:SetTextColor(1, 1, 1, 1)
        labelFS:SetText(label)

        local slider = CreateFrame("Slider", nil, container, "BackdropTemplate")
        slider:SetPoint("TOPLEFT", 0, -18)
        slider:SetSize(340, 10)
        slider:SetOrientation("HORIZONTAL")
        slider:SetMinMaxValues(minVal, maxVal)
        slider:SetValueStep(step)
        slider:SetObeyStepOnDrag(true)

        slider:SetBackdrop({
            bgFile = WHITE_TEXTURE,
            edgeFile = WHITE_TEXTURE,
            edgeSize = 1,
            insets = {left = 0, right = 0, top = 0, bottom = 0},
        })
        slider:SetBackdropColor(unpack(PANEL_BG))
        slider:SetBackdropBorderColor(0, 0, 0, 1)

        local thumb = slider:CreateTexture(nil, "OVERLAY")
        thumb:SetSize(10, 10)
        thumb:SetColorTexture(cr, cg, cb, 0.7)
        slider:SetThumbTexture(thumb)

        local valueText = container:CreateFontString(nil, "OVERLAY")
        valueText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        valueText:SetPoint("TOP", slider, "BOTTOM", 0, -4)
        valueText:SetTextColor(unpack(GREY_TEXT))

        if getValue then
            local val = getValue()
            slider:SetValue(val)
            valueText:SetText(tostring(val))
        end

        slider:SetScript("OnValueChanged", function(_, value)
            value = math.floor(value / step + 0.5) * step
            valueText:SetText(tostring(value))
            if onValueChanged then onValueChanged(value) end
        end)

        slider:SetScript("OnEnter", function() thumb:SetColorTexture(cr, cg, cb, 1) end)
        slider:SetScript("OnLeave", function() thumb:SetColorTexture(cr, cg, cb, 0.7) end)

        return container
    end

    -- Helper: Create a dropdown
    local function CreateDropdown(parent, label, yOffset, items, getValue, onValueChanged)
        local container = CreateFrame("Frame", nil, parent)
        container:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
        container:SetSize(340, 48)

        local labelFS = container:CreateFontString(nil, "OVERLAY")
        labelFS:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
        labelFS:SetPoint("TOPLEFT", 0, 0)
        labelFS:SetTextColor(1, 1, 1, 1)
        labelFS:SetText(label)

        local dd = CreateFrame("Button", nil, container, "BackdropTemplate")
        dd:SetSize(340, 22)
        dd:SetPoint("TOPLEFT", 0, -18)
        StylizeFrame(dd, PANEL_BG, {0, 0, 0, 1})

        local ddText = dd:CreateFontString(nil, "OVERLAY")
        ddText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
        ddText:SetPoint("LEFT", 8, 0)
        ddText:SetPoint("RIGHT", -18, 0)
        ddText:SetJustifyH("LEFT")
        ddText:SetTextColor(1, 1, 1, 1)

        local ddArrow = dd:CreateFontString(nil, "OVERLAY")
        ddArrow:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        ddArrow:SetPoint("RIGHT", -4, 0)
        ddArrow:SetTextColor(unpack(GREY_TEXT))
        ddArrow:SetText("▼")

        local selectedValue = getValue and getValue() or (items[1] and items[1].value)

        local function UpdateText()
            for _, item in ipairs(items) do
                if item.value == selectedValue then
                    ddText:SetText(item.text)
                    return
                end
            end
            ddText:SetText(items[1] and items[1].text or "")
        end
        UpdateText()

        local popup, closer, isOpen

        local function ClosePopup()
            if popup then popup:Hide(); popup = nil end
            if closer then closer:Hide() end
            isOpen = false
        end

        local function OpenPopup()
            if isOpen then ClosePopup(); return end
            ClosePopup()

            popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
            popup:SetFrameStrata("TOOLTIP")
            popup:SetFrameLevel(100)
            popup:SetSize(340, #items * 20 + 4)
            local left, bottom = dd:GetLeft(), dd:GetBottom()
            if left and bottom and left > 0 and bottom > 0 then
                popup:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, bottom - 2)
            else
                popup:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -2)
            end
            StylizeFrame(popup, {0.12, 0.12, 0.12, 1}, {0, 0, 0, 1})

            for i, item in ipairs(items) do
                local row = CreateFrame("Button", nil, popup, "BackdropTemplate")
                row:SetSize(336, 20)
                row:SetPoint("TOPLEFT", 2, -(i - 1) * 20 - 2)
                row.bg = row:CreateTexture(nil, "BACKGROUND")
                row.bg:SetAllPoints()
                row.bg:SetColorTexture(0, 0, 0, 0)
                if item.value == selectedValue then
                    row.bg:SetColorTexture(cr, cg, cb, 0.25)
                end
                local rowText = row:CreateFontString(nil, "OVERLAY")
                rowText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
                rowText:SetPoint("LEFT", 8, 0)
                rowText:SetTextColor(1, 1, 1, 1)
                rowText:SetText(item.text)
                row:SetScript("OnEnter", function() row.bg:SetColorTexture(cr, cg, cb, 0.4) end)
                row:SetScript("OnLeave", function()
                    if item.value == selectedValue then
                        row.bg:SetColorTexture(cr, cg, cb, 0.25)
                    else
                        row.bg:SetColorTexture(0, 0, 0, 0)
                    end
                end)
                row:SetScript("OnClick", function()
                    selectedValue = item.value
                    UpdateText()
                    if onValueChanged then onValueChanged(item.value) end
                    ClosePopup()
                end)
            end

            popup:Show()
            isOpen = true

            if not closer then
                closer = CreateFrame("Button", nil, UIParent)
                closer:SetFrameStrata("TOOLTIP")
                closer:SetFrameLevel(99)
                closer:SetAllPoints(UIParent)
                closer:EnableMouse(true)
                closer:SetScript("OnClick", ClosePopup)
            end
            closer:Show()
        end

        dd:SetScript("OnClick", function()
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            OpenPopup()
        end)
        dd:SetScript("OnEnter", function() dd:SetBackdropBorderColor(cr, cg, cb, 0.6) end)
        dd:SetScript("OnLeave", function() dd:SetBackdropBorderColor(0, 0, 0, 1) end)

        container.dropdown = dd
        return container
    end

    -- ===== Options Content =====
    local y = 0

    -- Recent Damage section
    CreateSectionHeader(content, "Recent Damage", y)
    y = y - 26

    local displayItems = {
        {value = "none", text = "None"},
        {value = "text", text = "Text"},
    }
    CreateDropdown(content, "Display Mode", y, displayItems,
        function() return db.appearance.displayMode or "text" end,
        function(val)
            db.appearance.displayMode = val
            SaveDB()
            if frame and frame:IsShown() then
                local data = FetchFullDeathRecap()
                if data then RenderRecap(data) end
            end
        end)
    y = y - 58

    CreateSlider(content, "Font Size", y, 8, 18, 1,
        function() return db.appearance.fontSize or 12 end,
        function(val)
            db.appearance.fontSize = val
            SaveDB()
            if frame and frame:IsShown() then
                local data = FetchFullDeathRecap()
                if data then RenderRecap(data) end
            end
        end)
    y = y - 58

    -- Window section
    CreateSectionHeader(content, "Window Settings", y)
    y = y - 26

    CreateSlider(content, "Window Scale", y, 0.5, 2.0, 0.05,
        function() return db.window.scale or 1.0 end,
        function(val)
            db.window.scale = val
            SaveDB()
            if frame then frame:SetScale(val) end
        end)
    y = y - 58

    CreateCheckbox(content, "Remember Window Position", y,
        function() return db.window.rememberPosition ~= false end,
        function(val)
            db.window.rememberPosition = val
            SaveDB()
        end)
    y = y - 28

    -- Reset button
    local resetBtn = CreateFrame("Button", nil, content, "BackdropTemplate")
    resetBtn:SetSize(120, 24)
    resetBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    StylizeFrame(resetBtn, {0.115, 0.115, 0.115, 1}, {0, 0, 0, 1})
    local resetText = resetBtn:CreateFontString(nil, "OVERLAY")
    resetText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    resetText:SetPoint("CENTER")
    resetText:SetTextColor(1, 0.3, 0.3, 1)
    resetText:SetText("Reset Position")
    resetBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(cr, cg, cb, 1)
    end)
    resetBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0, 0, 0, 1)
    end)
    resetBtn:SetScript("OnClick", function()
        db.window.point = "CENTER"
        db.window.relPoint = "CENTER"
        db.window.x = 0
        db.window.y = 0
        SaveDB()
        if frame then
            frame:ClearAllPoints()
            frame:SetPoint("CENTER")
        end
        print("|cff88aaff[Squizzcap]|r Window position reset.")
    end)

    return optionsFrame
end

local function ShowOptionsPanel()
    CreateOptionsPanel()
    if optionsFrame:IsShown() then
        optionsFrame:Hide()
    else
        optionsFrame:Show()
    end
end

-- ---------------------------------------------------------------------------
-- Auto-init on load + Event handling — PLAYER_DEAD fires when you die
-- ---------------------------------------------------------------------------

local logFrame = CreateFrame("Frame")

local function InitAddon()
    local function DoRegister()
        logFrame:RegisterEvent("PLAYER_DEAD")
        logFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        logFrame:RegisterEvent("PLAYER_ALIVE")

        logFrame:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_DEAD" then
                C_Timer.After(0.3, function()
                    local data = FetchFullDeathRecap()
                    if data then
                        RenderRecap(data)
                    else
                        RenderRecap({
                            totalDamage = 0,
                            totalHealing = 0,
                            damageBySource = {},
                            healBySource = {},
                            damageTimeline = {},
                            healTimeline = {},
                            killingBlow = nil,
                        })
                    end
                end)
            elseif event == "PLAYER_ENTERING_WORLD" then
                -- Clear any stale data on zone/load
            elseif event == "PLAYER_ALIVE" then
                -- Resurrected — do NOT hide the window (stays until closed)
            end
        end)
    end

    if securecallfunction then
        securecallfunction(DoRegister)
    else
        xpcall(DoRegister, geterrorhandler())
    end
end

-- Expose globally for macro use: /run Squizzcap_Init()
_G.Squizzcap_Init = InitAddon

-- Auto-initialize on load (no slash command needed)
InitAddon()

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------

SLASH_SQUIZZCAP1 = "/squizzcap"
SLASH_SQUIZZCAP2 = "/scr"
SlashCmdList["SQUIZZCAP"] = function(arg)
    arg = string.lower(string.trim(arg or ""))

    if arg == "test" then
        local data = FetchFullDeathRecap()
        if data then
            RenderRecap(data)
        else
            print("|cff88aaff[Squizzcap]|r No death data available yet. Die first, then test.")
        end
    elseif arg == "options" or arg == "" then
        ShowOptionsPanel()
    else
        print("|cff88aaff[Squizzcap] Commands:|r")
        print("  |cffffffff/squizzcap|r — open options")
        print("  |cffffffff/squizzcap test|r — show last death recap")
        print("  |cffffffff/squizzcap options|r — open options panel")
    end
end

-- Startup message
print("|cff88aaff[Squizzcap]|r Death recap loaded. Uses native C_DeathRecap API. Auto-initialized.")