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
    onDeath = "window", -- "window" | "toast" | "none"
    runs = {},          -- saved deaths, see "Runs" below
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

local RUNS_MAX = 20
local startNewRun = false
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
    while #runs > RUNS_MAX do table.remove(runs, 1) end
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
    local msg = string.format("Squizzcap: died to %s%s for %s", kb.name, kb.source and (" (" .. kb.source .. ")") or "", amount)
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
    optionsFrame:SetSize(380, 400)
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
        { value = "none",   text = "Nothing (use /squizzcap test)" },
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
    note:SetText("Every death is kept for this character, grouped by dungeon or raid visit (the last " .. RUNS_MAX .. "). See the All deaths tab.")
    y = y - 34

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

-- ---------------------------------------------------------------------------
-- Death handling
-- ---------------------------------------------------------------------------

local function OnDeath()
    local model = addon.Data.Read()
    if not model then return end
    local run, runIndex = CurrentRun()
    table.insert(run.deaths, Saveable(model))
    local deathIndex = #run.deaths

    local mode = addon.db.onDeath
    if mode == "toast" then
        addon.Window.ShowToast(model, runIndex, deathIndex)
    elseif mode ~= "none" then
        addon.Window.Show(model, runIndex, deathIndex)
    end
end

-- The newest saved death, as something the window can draw.
local function LastDeath()
    local runs = addon.db.runs
    for r = #runs, 1, -1 do
        local deaths = runs[r].deaths
        for d = #deaths, 1, -1 do
            local m = deaths[d]
            m = (m.stub and liveCopies[m]) or m
            if not m.stub then return m, r, d end
        end
    end
    return addon.Data.Read()
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_DEAD")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("CHALLENGE_MODE_START")
events:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then
            LoadDB()
            self:UnregisterEvent("ADDON_LOADED")
        end
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
    elseif event == "PLAYER_DEAD" then
        -- The recap is assembled as you die; give it a moment to land.
        C_Timer.After(0.3, OnDeath)
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
    elseif arg == "options" or arg == "" then
        ToggleOptions()
    else
        Say("Commands:")
        print("  |cffffffff/squizzcap|r - options")
        print("  |cffffffff/squizzcap show|r - open your last death (All deaths tab for the rest)")
        print("  |cffffffff/squizzcap toast|r - show your last death as the compact summary")
    end
end
