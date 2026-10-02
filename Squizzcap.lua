--[[
  Squizzcap - Death Recap

  Core: saved settings, the options panel, the death event and slash
  commands. Reading the recap lives in Data.lua and drawing it in
  Window.lua; both load before this file.
]]

local addonName, addon = ...

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------

local defaults = {
    window = {
        scale = 1.0,
        rememberPosition = true,
    },
    toast = {},
    onDeath = "toast",  -- "window" | "toast" | "none"; compact by default (user decision 2026-09-27)
    runs = {},          -- saved deaths, see "Runs" below
    keepRuns = 20,      -- how many runs to keep; the oldest go first
    freshEachKey = false, -- clear earlier runs when a Mythic+ key starts
    groupDeaths = true, -- save group members' deaths too (see "Group deaths")
    historyShow = "all", -- All deaths lists "all" deaths or only "mine"
}

local function Backfill(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            dst[k] = type(v) == "table" and Backfill({}, v) or v
        elseif type(v) == "table" and type(dst[k]) == "table" then
            Backfill(dst[k], v)
        end
    end
    return dst
end

local function LoadDB()
    -- Welcome.lua tells a first install from an update by this.
    addon.hadSavedVariables = SquizzcapDB ~= nil
    SquizzcapDB = SquizzcapDB or {}
    addon.db = Backfill(SquizzcapDB, defaults)
end

local function Say(msg)
    print("|cff88aaff[Squizzcap]|r " .. msg)
end

-- ---------------------------------------------------------------------------
-- Runs: every death is saved (per character), grouped so a dungeon's deaths
-- can be looked back on together.
--
-- A run is one visit to one instance at one difficulty. A new one starts
-- when you walk into an instance from outside, or when a Mythic+ key
-- starts. A corpse run does NOT split it: coming back in while dead or a
-- ghost keeps the same run, and so does a /reload. Deaths outside instances
-- are grouped by zone and day. Runs are created lazily, on the first death.
-- ---------------------------------------------------------------------------

local startNewRun = false

-- Drops the oldest runs past the "Keep history" setting. Also run when the
-- setting is lowered, so it takes effect at once.
function addon.TrimRuns()
    local runs, keep = addon.db.runs, addon.db.keepRuns or 20
    while #runs > keep do table.remove(runs, 1) end
end
local wasInInstance

local function RunIdentity()
    local inInstance = IsInInstance()
    if inInstance then
        local name, _, difficultyID, difficultyName, _, _, _, instanceID = GetInstanceInfo()
        return "i:" .. tostring(instanceID) .. ":" .. tostring(difficultyID), name, difficultyName
    end
    local zone = GetRealZoneText() or UNKNOWN
    return "w:" .. zone .. ":" .. date("%Y-%m-%d"), zone, "Open world"
end

local function KeystoneLevel()
    if not (C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo) then return nil end
    local ok, level = pcall(C_ChallengeMode.GetActiveKeystoneInfo)
    if ok and type(level) == "number" and not addon.Data.IsSecret(level) and level > 0 then return level end
    return nil
end

local function CurrentRun()
    local runs = addon.db.runs
    local key, name, difficulty = RunIdentity()
    local last = runs[#runs]
    if last and last.key == key and not startNewRun then
        return last, #runs
    end
    startNewRun = false
    local run = { key = key, name = name, difficulty = difficulty, keyLevel = KeystoneLevel(), started = time(), deaths = {} }
    table.insert(runs, run)
    addon.TrimRuns()
    return run, #runs
end

-- SavedVariables must never be handed a secret value, so a recap the game
-- hid is saved as a stub (when it happened, nothing else). This session
-- still has the live copy, and the window uses it while it lasts.
local liveCopies = setmetatable({}, { __mode = "k" })
function addon.LiveModel(stub) return liveCopies[stub] end

local function Saveable(model)
    if not model.secret then return model end
    local stub = { stub = true, when = model.when, zone = model.zone, hits = {} }
    liveCopies[stub] = model
    return stub
end

function addon.ClearSavedDeaths()
    wipe(addon.db.runs)
    addon.Window.HistoryChanged()
end

function addon.DeleteRun(index)
    if addon.db.runs[index] then table.remove(addon.db.runs, index) end
    addon.Window.HistoryChanged()
end

-- ---------------------------------------------------------------------------
-- Link / Report (the window's title-bar buttons)
-- ---------------------------------------------------------------------------

function addon.LinkDeath(model)
    local link = model and model.link
    if not link then
        Say("No recap link for this death.")
        return
    end
    local inserters = {
        ChatFrameUtil and ChatFrameUtil.InsertLink,
        ChatEdit_InsertLink,
    }
    for _, fn in ipairs(inserters) do
        if fn then
            local ok, done = pcall(fn, link)
            if ok and done then return end
        end
    end
    local openers = { ChatFrameUtil and ChatFrameUtil.OpenChat, ChatFrame_OpenChat }
    for _, fn in ipairs(openers) do
        if fn and pcall(fn, link) then return end
    end
    Say(link)
end

local function GroupChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end

function addon.ReportDeath(model)
    if not model or model.secret then return end
    local kb = model.hits[1]
    local amount = BreakUpLargeNumbers and BreakUpLargeNumbers(kb.amount) or tostring(kb.amount)
    local who = model.who and model.who.name and (model.who.name .. " ") or ""
    local msg = string.format("Squizzcap: %sdied to %s%s for %s", who, kb.name, kb.source and (" (" .. kb.source .. ")") or "", amount)
    if kb.overkill > 0 then
        msg = msg .. string.format(" (%s overkill)", BreakUpLargeNumbers and BreakUpLargeNumbers(kb.overkill) or kb.overkill)
    end
    if kb.avoidable then msg = msg .. ", avoidable" end
    if model.speed then
        msg = msg .. string.format(" - %d%% to 0 in %.1fs", math.floor(model.speed.from + 0.5), model.speed.seconds)
    end

    local channel = GroupChannel()
    if not channel then
        Say(msg)
        return
    end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not (send and pcall(send, msg, channel)) then
        Say(msg)
    end
end

-- ---------------------------------------------------------------------------
-- Options panel (same flat style as the window)
-- ---------------------------------------------------------------------------

local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8x8"
local DARK_BG     = {0.1, 0.1, 0.1, 0.9}
local DARK_BORDER = {0, 0, 0, 1}
local TITLE_BG    = {0.115, 0.115, 0.115, 1}
local PANEL_BG    = {0.115, 0.115, 0.115, 1}
local GREY_TEXT   = {0.7, 0.7, 0.7, 1}
local FONT_PATH   = "Interface\\AddOns\\Squizzcap\\Media\\Fonts\\Barlow-SemiBold.ttf"

local function GetClassColor()
    local ok, _, class = pcall(UnitClass, "player")
    if not ok or not class or addon.Data.IsSecret(class) then return 0.7, 0.7, 0.7 end
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if color then return color.r, color.g, color.b end
    return 0.7, 0.7, 0.7
end

local function StylizeFrame(f, color, borderColor)
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

local optionsFrame

local function CreateOptionsPanel()
    if optionsFrame then return optionsFrame end
    local db = addon.db

    optionsFrame = CreateFrame("Frame", "SquizzcapOptionsFrame", UIParent, "BackdropTemplate")
    optionsFrame:SetSize(380, 524)
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
    tinsert(UISpecialFrames, "SquizzcapOptionsFrame")

    StylizeFrame(optionsFrame, DARK_BG, DARK_BORDER)

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
    title:SetFont(FONT_PATH, 13, "")
    title:SetPoint("LEFT", 10, 0)
    title:SetTextColor(1, 1, 1, 1)
    title:SetText("Squizzcap Options")

    local cr, cg, cb = GetClassColor()
    local accentLine = titleBar:CreateTexture(nil, "BACKGROUND")
    accentLine:SetPoint("BOTTOMLEFT", 0, 0)
    accentLine:SetPoint("BOTTOMRIGHT", 0, 0)
    accentLine:SetHeight(1)
    accentLine:SetColorTexture(cr, cg, cb, 0.5)

    local close = CreateFrame("Button", nil, optionsFrame, "BackdropTemplate")
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", optionsFrame, "TOPRIGHT", -2, -2)
    close:SetFrameLevel(optionsFrame:GetFrameLevel() + 10)
    StylizeFrame(close, TITLE_BG, DARK_BORDER)
    local closeText = close:CreateFontString(nil, "OVERLAY")
    closeText:SetFont(FONT_PATH, 12, "")
    closeText:SetPoint("CENTER")
    closeText:SetTextColor(1, 1, 1, 1)
    closeText:SetText("x")
    close:SetScript("OnEnter", function(self)
        self:SetBackdropColor(cr, cg, cb, 0.6)
        self:SetBackdropBorderColor(cr, cg, cb, 1)
    end)
    close:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(TITLE_BG))
        self:SetBackdropBorderColor(0, 0, 0, 1)
    end)
    close:SetScript("OnClick", function() optionsFrame:Hide() end)

    local content = CreateFrame("Frame", nil, optionsFrame)
    content:SetPoint("TOPLEFT", 12, -36)
    content:SetPoint("BOTTOMRIGHT", -12, 12)

    local function CreateSectionHeader(parent, text, yOffset)
        local header = parent:CreateFontString(nil, "OVERLAY")
        header:SetFont(FONT_PATH, 12, "")
        header:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
        header:SetTextColor(cr, cg, cb, 1)
        header:SetText(text)
        return header
    end

    local function CreateCheckbox(parent, label, yOffset, getValue, onValueChanged)
        local checkbox = CreateFrame("CheckButton", nil, parent, "BackdropTemplate")
        checkbox:SetSize(18, 18)
        checkbox:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
        StylizeFrame(checkbox, PANEL_BG, DARK_BORDER)

        local checkedTex = checkbox:CreateTexture(nil, "ARTWORK")
        checkedTex:SetPoint("TOPLEFT", 1, -1)
        checkedTex:SetPoint("BOTTOMRIGHT", -1, 1)
        checkedTex:SetColorTexture(cr, cg, cb, 0.7)
        checkbox:SetCheckedTexture(checkedTex)

        local highlight = checkbox:CreateTexture(nil, "OVERLAY")
        highlight:SetAllPoints()
        highlight:SetColorTexture(cr, cg, cb, 0.1)
        checkbox:SetHighlightTexture(highlight, "ADD")

        local labelText = checkbox:CreateFontString(nil, "OVERLAY")
        labelText:SetFont(FONT_PATH, 12, "")
        labelText:SetPoint("LEFT", checkbox, "RIGHT", 6, 0)
        labelText:SetTextColor(1, 1, 1, 1)
        labelText:SetText(label)

        if getValue then checkbox:SetChecked(getValue()) end
        checkbox:SetScript("OnClick", function(self)
            local checked = self:GetChecked()
            PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
            if onValueChanged then onValueChanged(checked) end
        end)
        return checkbox
    end

    local function CreateSlider(parent, label, yOffset, minVal, maxVal, step, getValue, onValueChanged)
        local container = CreateFrame("Frame", nil, parent)
        container:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
        container:SetSize(340, 48)

        local labelFS = container:CreateFontString(nil, "OVERLAY")
        labelFS:SetFont(FONT_PATH, 12, "")
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
        slider:SetBackdrop({ bgFile = WHITE_TEXTURE, edgeFile = WHITE_TEXTURE, edgeSize = 1 })
        slider:SetBackdropColor(unpack(PANEL_BG))
        slider:SetBackdropBorderColor(0, 0, 0, 1)

        local thumb = slider:CreateTexture(nil, "OVERLAY")
        thumb:SetSize(10, 10)
        thumb:SetColorTexture(cr, cg, cb, 0.7)
        slider:SetThumbTexture(thumb)

        local valueText = container:CreateFontString(nil, "OVERLAY")
        valueText:SetFont(FONT_PATH, 11, "")
        valueText:SetPoint("TOP", slider, "BOTTOM", 0, -4)
        valueText:SetTextColor(unpack(GREY_TEXT))

        local val = getValue()
        slider:SetValue(val)
        valueText:SetText(tostring(val))
        slider:SetScript("OnValueChanged", function(_, value)
            value = math.floor(value / step + 0.5) * step
            valueText:SetText(string.format("%.2f", value))
            onValueChanged(value)
        end)
        slider:SetScript("OnEnter", function() thumb:SetColorTexture(cr, cg, cb, 1) end)
        slider:SetScript("OnLeave", function() thumb:SetColorTexture(cr, cg, cb, 0.7) end)
        return container
    end

    local function CreateDropdown(parent, label, yOffset, items, getValue, onValueChanged)
        local container = CreateFrame("Frame", nil, parent)
        container:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
        container:SetSize(340, 48)

        local labelFS = container:CreateFontString(nil, "OVERLAY")
        labelFS:SetFont(FONT_PATH, 12, "")
        labelFS:SetPoint("TOPLEFT", 0, 0)
        labelFS:SetTextColor(1, 1, 1, 1)
        labelFS:SetText(label)

        local dd = CreateFrame("Button", nil, container, "BackdropTemplate")
        dd:SetSize(340, 24)
        dd:SetPoint("TOPLEFT", 0, -18)
        StylizeFrame(dd, PANEL_BG, DARK_BORDER)

        local ddText = dd:CreateFontString(nil, "OVERLAY")
        ddText:SetFont(FONT_PATH, 12, "")
        ddText:SetPoint("LEFT", 8, 0)
        ddText:SetPoint("RIGHT", -18, 0)
        ddText:SetJustifyH("LEFT")
        ddText:SetTextColor(1, 1, 1, 1)

        local ddArrow = dd:CreateFontString(nil, "OVERLAY")
        ddArrow:SetFont(FONT_PATH, 11, "")
        ddArrow:SetPoint("RIGHT", -6, 0)
        ddArrow:SetTextColor(unpack(GREY_TEXT))
        ddArrow:SetText("v")

        local selectedValue = getValue()
        local function UpdateText()
            for _, item in ipairs(items) do
                if item.value == selectedValue then ddText:SetText(item.text) return end
            end
            ddText:SetText(items[1].text)
        end
        UpdateText()

        local popup, closer
        local function ClosePopup()
            if popup then popup:Hide() end
            if closer then closer:Hide() end
        end

        local function OpenPopup()
            if popup and popup:IsShown() then ClosePopup() return end
            if not popup then
                popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
                popup:SetFrameStrata("TOOLTIP")
                popup:SetFrameLevel(100)
                popup:SetSize(340, #items * 22 + 4)
                StylizeFrame(popup, {0.12, 0.12, 0.12, 1}, DARK_BORDER)
                popup.rows = {}
                for i, item in ipairs(items) do
                    local row = CreateFrame("Button", nil, popup)
                    row:SetSize(336, 22)
                    row:SetPoint("TOPLEFT", 2, -(i - 1) * 22 - 2)
                    row.bg = row:CreateTexture(nil, "BACKGROUND")
                    row.bg:SetAllPoints()
                    local rowText = row:CreateFontString(nil, "OVERLAY")
                    rowText:SetFont(FONT_PATH, 12, "")
                    rowText:SetPoint("LEFT", 8, 0)
                    rowText:SetTextColor(1, 1, 1, 1)
                    rowText:SetText(item.text)
                    row.Paint = function()
                        row.bg:SetColorTexture(cr, cg, cb, item.value == selectedValue and 0.25 or 0)
                    end
                    row:SetScript("OnEnter", function() row.bg:SetColorTexture(cr, cg, cb, 0.4) end)
                    row:SetScript("OnLeave", row.Paint)
                    row:SetScript("OnClick", function()
                        selectedValue = item.value
                        UpdateText()
                        onValueChanged(item.value)
                        ClosePopup()
                    end)
                    popup.rows[i] = row
                end
            end
            popup:ClearAllPoints()
            popup:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -2)
            for _, row in ipairs(popup.rows) do row.Paint() end
            popup:Show()

            if not closer then
                closer = CreateFrame("Button", nil, UIParent)
                closer:SetFrameStrata("TOOLTIP")
                closer:SetFrameLevel(99)
                closer:SetAllPoints(UIParent)
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
        return container
    end

    local y = 0
    CreateSectionHeader(content, "When You Die", y)
    y = y - 24
    CreateDropdown(content, "Show", y, {
        { value = "window", text = "The full recap window" },
        { value = "toast",  text = "A compact summary (click for the full window)" },
        { value = "none",   text = "Nothing (use /squizzcap show)" },
    }, function() return db.onDeath end, function(val) db.onDeath = val end)
    y = y - 60

    CreateSectionHeader(content, "Window", y)
    y = y - 24
    CreateSlider(content, "Scale", y, 0.5, 2.0, 0.05,
        function() return db.window.scale end,
        function(val)
            db.window.scale = val
            addon.Window.SetScale(val)
        end)
    y = y - 58

    CreateCheckbox(content, "Remember window position", y,
        function() return db.window.rememberPosition ~= false end,
        function(val) db.window.rememberPosition = val end)
    y = y - 32

    local resetBtn = CreateFrame("Button", nil, content, "BackdropTemplate")
    resetBtn:SetSize(130, 24)
    resetBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    StylizeFrame(resetBtn, TITLE_BG, DARK_BORDER)
    local resetText = resetBtn:CreateFontString(nil, "OVERLAY")
    resetText:SetFont(FONT_PATH, 12, "")
    resetText:SetPoint("CENTER")
    resetText:SetTextColor(1, 0.4, 0.4, 1)
    resetText:SetText("Reset Position")
    resetBtn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(cr, cg, cb, 1) end)
    resetBtn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0, 0, 0, 1) end)
    resetBtn:SetScript("OnClick", function()
        db.window.point, db.window.relPoint, db.window.x, db.window.y = nil, nil, nil, nil
        db.toast.point, db.toast.relPoint, db.toast.x, db.toast.y = nil, nil, nil, nil
        addon.Window.ResetPosition()
        Say("Window position reset.")
    end)
    y = y - 44

    CreateSectionHeader(content, "Saved Deaths", y)
    y = y - 22
    local note = content:CreateFontString(nil, "OVERLAY")
    note:SetFont(FONT_PATH, 11, "")
    note:SetTextColor(unpack(GREY_TEXT))
    note:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    note:SetWidth(340)
    note:SetJustifyH("LEFT")
    note:SetText("Every death is kept for this character, grouped by dungeon or raid visit. See the All deaths tab.")
    y = y - 34

    CreateDropdown(content, "Keep history", y, {
        { value = 5,  text = "The last 5 runs" },
        { value = 10, text = "The last 10 runs" },
        { value = 20, text = "The last 20 runs" },
        { value = 50, text = "The last 50 runs" },
    }, function() return db.keepRuns end, function(val)
        db.keepRuns = val
        addon.TrimRuns()
        addon.Window.HistoryChanged()
    end)
    y = y - 60

    CreateCheckbox(content, "Start fresh each Mythic+ key", y,
        function() return db.freshEachKey end,
        function(val) db.freshEachKey = val end)
    y = y - 28

    CreateCheckbox(content, "Save group members' deaths too", y,
        function() return db.groupDeaths end,
        function(val) db.groupDeaths = val end)
    y = y - 32

    local clearBtn = CreateFrame("Button", nil, content, "BackdropTemplate")
    clearBtn:SetSize(150, 24)
    clearBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    StylizeFrame(clearBtn, TITLE_BG, DARK_BORDER)
    local clearText = clearBtn:CreateFontString(nil, "OVERLAY")
    clearText:SetFont(FONT_PATH, 12, "")
    clearText:SetPoint("CENTER")
    clearText:SetTextColor(1, 0.4, 0.4, 1)
    clearText:SetText("Clear saved deaths")
    clearBtn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(cr, cg, cb, 1) end)
    clearBtn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0, 0, 0, 1) end)
    -- Two clicks, so one stray click can't wipe a night's history.
    clearBtn:SetScript("OnClick", function()
        if clearBtn.armed then
            clearBtn.armed = nil
            clearText:SetText("Clear saved deaths")
            addon.ClearSavedDeaths()
            Say("Saved deaths cleared.")
        else
            clearBtn.armed = true
            clearText:SetText("Click again to clear")
            C_Timer.After(4, function()
                if clearBtn.armed then
                    clearBtn.armed = nil
                    clearText:SetText("Clear saved deaths")
                end
            end)
        end
    end)

    return optionsFrame
end

local function ToggleOptions()
    CreateOptionsPanel()
    optionsFrame:SetShown(not optionsFrame:IsShown())
end
addon.ToggleOptions = ToggleOptions -- the welcome window's Options button

-- ---------------------------------------------------------------------------
-- Death handling
-- ---------------------------------------------------------------------------

-- Is `model` the death already saved as `last`? PLAYER_DEAD can fire twice
-- for one death (seen in an arena skirmish, 2026-09-29: two identical entries),
-- and each firing reads the same recap. Readable recaps are matched on the
-- killing blow's own game timestamp and amount; a hidden (stub) one has
-- neither, so on being saved within a few seconds of each other.
local function SameDeath(last, model)
    if not last then return false end
    local a, b = last.hits and last.hits[1], model.hits and model.hits[1]
    if last.stub or model.secret or not a or not b then
        return math.abs((last.when or 0) - (model.when or 0)) <= 3
    end
    local ta, tb, aa, ab = a.timestamp, b.timestamp, a.amount, b.amount
    local IsSecret = addon.Data.IsSecret
    if IsSecret(ta) or IsSecret(tb) or IsSecret(aa) or IsSecret(ab) then
        return math.abs((last.when or 0) - (model.when or 0)) <= 3
    end
    return ta == tb and aa == ab
end

-- The damage meter can still be hidden at the moment of death -- you can be
-- flagged in combat for a moment after dying, and in an arena it was (This
-- fight missing, while a second, later PLAYER_DEAD read had it). So a failed
-- read is retried over the next few seconds and the tab added to the death
-- already saved. `saved` is the table in the run (a live model; a stub for a
-- hidden recap has no tabs to add to).
local FIGHT_RETRIES = { 1, 3, 6 }
local function RetryFight(saved)
    if not saved or saved.stub or saved.fight then return end
    for _, delay in ipairs(FIGHT_RETRIES) do
        C_Timer.After(delay, function()
            if saved.fight then return end
            local fight, why = addon.Data.ReadFight()
            if fight then
                saved.fight, saved.fightWhy = fight, nil
                addon.Window.HistoryChanged() -- redraws an open window, tab included
            else
                saved.fightWhy = (why or "?") .. (InCombatLockdown() and " [in combat]" or "")
            end
        end)
    end
end

local function OnDeath(deathTime)
    local model = addon.Data.Read(nil, deathTime)
    if not model then return end
    local run, runIndex = CurrentRun()
    -- The same death reported twice: it is saved and on screen already. The
    -- second read can have what the first could not (This fight, above).
    -- Compared with your own last death: a group member's may be newer.
    local last
    for i = #run.deaths, 1, -1 do
        if not run.deaths[i].who then last = run.deaths[i] break end
    end
    if SameDeath(last, model) then
        if not last.stub and not last.fight and model.fight then
            last.fight, last.fightWhy = model.fight, nil
            addon.Window.HistoryChanged()
        end
        return
    end
    if not model.fight then RetryFight(model) end
    table.insert(run.deaths, Saveable(model))
    local deathIndex = #run.deaths

    local mode = addon.db.onDeath
    if mode == "toast" then
        addon.Window.ShowToast(model, runIndex, deathIndex)
    elseif mode ~= "none" then
        addon.Window.Show(model, runIndex, deathIndex)
    end
end

-- ---------------------------------------------------------------------------
-- Group deaths
--
-- Blizzard's damage meter lists every death in the fight with a
-- deathRecapID, and C_DeathRecap reads a group member's recap by it as fully
-- as your own (probed 2026-10-02, out of combat). The meter's values are
-- secret while YOU are in combat, so the list is checked every couple of
-- seconds while you are out of it: between pulls, and while you lie dead
-- mid-fight. Each recapID is read once per session; a death is saved once
-- ever (DeathKey), so a /reload re-reading the same list adds nothing.
--
-- A group member's death is saved like yours, with `who` = { name, guid,
-- class, key }. It has no heals or older hits (those logs are yours alone)
-- and This fight is THEIR damage taken. Only a fully readable recap is kept.
-- ---------------------------------------------------------------------------

local function ShortName(name)
    return name and (name:match("^([^%-]+)") or name) or nil
end
addon.ShortName = ShortName

local function Plain(v)
    if v == nil or addon.Data.IsSecret(v) then return nil end
    return v
end

local function DeathKey(m)
    local kb = m.who and m.hits and m.hits[1]
    if not (kb and kb.timestamp) then return nil end
    return m.who.key .. ":" .. tostring(kb.timestamp) .. ":" .. tostring(kb.amount)
end

local function AlreadySaved(key)
    for _, run in ipairs(addon.db.runs) do
        for _, m in ipairs(run.deaths) do
            if m.who and DeathKey(m) == key then return true end
        end
    end
    return false
end

-- The meter counts Feign Death as a death (see DPSReport's DeathTracker). A
-- hunter whose "killing blow" left them standing feigned. UNTESTED in game:
-- whether a feign gets a recap at all is not known.
local function Feigned(who, kb)
    return who.class == "HUNTER" and kb.currentHP and kb.amount < kb.currentHP
end

local readTries = {}   -- recapID -> reads tried this session (true = done)
local MAX_TRIES = 5

local function CaptureGroupDeaths()
    local db = addon.db
    if not (db and db.groupDeaths) or not IsInGroup() or InCombatLockdown() then return end
    local DM = C_DamageMeter
    if not (DM and DM.GetCombatSessionFromType and Enum.DamageMeterType and Enum.DamageMeterType.Deaths) then return end
    local okA, avail = pcall(DM.IsDamageMeterAvailable)
    if not okA or not Plain(avail) then return end
    local ok, session = pcall(DM.GetCombatSessionFromType, Enum.DamageMeterSessionType.Current, Enum.DamageMeterType.Deaths)
    if not ok or type(session) ~= "table" or type(session.combatSources) ~= "table" then return end

    local myGUID = UnitGUID("player")
    local added = false
    for _, src in ipairs(session.combatSources) do
        local id, isMe = Plain(src.deathRecapID), src.isLocalPlayer
        local name, guid = Plain(src.name), Plain(src.sourceGUID)
        if id and id ~= 0 and readTries[id] ~= true and not addon.Data.IsSecret(isMe) and not isMe
            and (guid or name) and not (guid and guid == myGUID) then
            local model = addon.Data.Read(id)
            if model and not model.secret then
                readTries[id] = true
                local who = { name = name, guid = guid, class = Plain(src.classFilename) }
                who.key = guid or ShortName(name)
                model.who = who
                local key = DeathKey(model)
                if not Feigned(who, model.hits[1]) and not (key and AlreadySaved(key)) then
                    model.fight = addon.Data.ReadFight(who)
                    local run = CurrentRun()
                    table.insert(run.deaths, model)
                    added = true
                end
            else
                -- Not there yet, or hidden: try again, but not forever.
                local n = (readTries[id] or 0) + 1
                readTries[id] = (n >= MAX_TRIES) or n
            end
        end
    end
    if added then addon.Window.HistoryChanged() end
end
addon.CaptureGroupDeaths = CaptureGroupDeaths

-- The newest saved death of yours, as something the window can draw.
local function LastDeath()
    local runs = addon.db.runs
    for r = #runs, 1, -1 do
        local deaths = runs[r].deaths
        for d = #deaths, 1, -1 do
            local m = deaths[d]
            m = (m.stub and liveCopies[m]) or m
            if not m.stub and not m.who then return m, r, d end
        end
    end
    return addon.Data.Read()
end

-- For other addons -- DPSReport opens a death from its Deaths list with
-- this. Opens the newest saved death of that player: you when `isPlayer`,
-- else matched on `guid`, or on `name` (realm ignored) when either side has
-- no GUID. Secret arguments are ignored. Returns true if a death was opened.
function Squizzcap_OpenDeathOf(guid, name, isPlayer)
    if not addon.db then return false end
    CaptureGroupDeaths() -- a death from the fight that just ended may be unread
    local IsSecret = addon.Data.IsSecret
    if IsSecret(guid) or guid == "" then guid = nil end
    if IsSecret(name) or name == "" then name = nil end
    if IsSecret(isPlayer) then isPlayer = nil end
    local me = isPlayer or (guid ~= nil and guid == UnitGUID("player"))
    local short = ShortName(name)
    if not me and not guid and not short then return false end
    local runs = addon.db.runs
    for r = #runs, 1, -1 do
        local deaths = runs[r].deaths
        for d = #deaths, 1, -1 do
            local m = deaths[d]
            local who, match = m.who, false
            if me then
                match = not who
            elseif who then
                if guid and who.guid then match = (who.guid == guid)
                else match = short ~= nil and ShortName(who.name) == short end
            end
            if match and not (m.stub and not liveCopies[m]) then
                addon.Window.ShowDeath(r, d)
                return true
            end
        end
    end
    return false
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_DEAD")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("CHALLENGE_MODE_START")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then
            LoadDB()
            self:UnregisterEvent("ADDON_LOADED")
            -- Cheap when nothing is new: one meter call, every recap read once.
            C_Timer.NewTicker(2, CaptureGroupDeaths)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- The pull just ended: pick up its deaths before the next one replaces
        -- the meter's current session.
        C_Timer.After(0.5, CaptureGroupDeaths)
    elseif event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = arg1, arg2
        local inInstance = IsInInstance() and true or false
        -- Walking in from outside starts a new run -- unless you are dead
        -- (a corpse run back to your group) or this is a login/reload.
        if inInstance and wasInInstance == false and not isInitialLogin and not isReloadingUi
            and not UnitIsDeadOrGhost("player") then
            startNewRun = true
        end
        wasInInstance = inInstance
    elseif event == "CHALLENGE_MODE_START" then
        startNewRun = true
        -- The new key's run is created on its first death, so clearing now
        -- leaves All deaths holding only this key.
        if addon.db.freshEachKey and #addon.db.runs > 0 then
            addon.ClearSavedDeaths()
            Say("New key: earlier saved deaths cleared (Start fresh each Mythic+ key is on).")
        end
    elseif event == "PLAYER_DEAD" then
        -- The recap is assembled as you die; give it a moment to land. The
        -- moment of death is taken NOW, not then: it is what lines the logged
        -- incoming heals up against the recap's hits.
        local deathTime = GetTime()
        C_Timer.After(0.3, function() OnDeath(deathTime) end)
    end
end)

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------

SLASH_SQUIZZCAP1 = "/squizzcap"
SLASH_SQUIZZCAP2 = "/scr"
SlashCmdList["SQUIZZCAP"] = function(arg)
    arg = strtrim(arg or ""):lower()

    if arg == "test" or arg == "show" or arg == "deaths" then
        local model, r, d = LastDeath()
        if model then
            addon.Window.Show(model, r, d)
        else
            Say("No deaths saved yet.")
        end
    elseif arg == "toast" then
        local model, r, d = LastDeath()
        if model then addon.Window.ShowToast(model, r, d) else Say("No deaths saved yet.") end
    elseif arg == "fight" then
        -- Why the last death has no This fight tab (Data.ReadFight's reason).
        local model = LastDeath()
        if not model then Say("No deaths saved yet.") return end
        if model.fight then
            Say(string.format("This fight: %d spells recorded for your last death.", #model.fight.spells))
        else
            Say("No This fight tab for your last death: " .. tostring(model.fightWhy or "not recorded (a death from before this was added)"))
        end
    elseif arg == "notes" or arg == "changelog" then
        addon.Welcome.ShowReleaseNotes()
    elseif arg == "options" or arg == "" then
        ToggleOptions()
    else
        Say("Commands:")
        print("  |cffffffff/squizzcap|r - options")
        print("  |cffffffff/squizzcap show|r - open your last death (All deaths tab for the rest)")
        print("  |cffffffff/squizzcap toast|r - show your last death as the compact summary")
        print("  |cffffffff/squizzcap notes|r - what's new in this version")
    end
end
