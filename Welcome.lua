--[[
  Squizzcap - Welcome.lua

  The first-run greeting and the "what changed" note after an update. Ported
  from SquizzTalents' Welcome.lua (itself from SquizzFrames and Squizzumables):
  a scrolling body, the first-run/update/nothing decision, and the shared
  one-note-at-a-time queue. Drawn in Squizzcap's own look (Window.Look).

  The notes are duplicated here rather than read from CHANGELOG.txt because an
  addon cannot read its own text files at runtime. So this is a HIGHLIGHT list,
  not a changelog: a few lines per release, what a player would notice.

  The seen version is kept ACCOUNT-wide (SquizzcapAccountDB): the settings
  are per character, which would show the same note again on every one.
]]

local addonName, addon = ...

local Welcome = {}
addon.Welcome = Welcome

-- Highlights per version, newest first, keyed by the .toc Version string.
-- ADD A NEW ENTRY AS PART OF RELEASING. A version with no entry still shows
-- the update window, just without bullets.
local RELEASE_NOTES = {
    ["1.1.0"] = {
        "Healing you received is now part of the recap: the health graph rises in green exactly when each "
            .. "heal landed, with a Healing Received total and a \"+48,300 healed\" line between hits.",
        "The recap now reaches back 5 seconds before your death, not just Blizzard's last 10 hits. Hits older "
            .. "than the recap are added from the game's own hit feed, marked with ~ because they're approximate.",
        "Blizzard's 10 hits, including the killing blow, are still shown exactly as the game recorded them.",
        "This window, and /squizzcap notes to open it again.",
    },
    ["1.0.0"] = {
        "First release: a death summary the moment you die, a health graph of the hits that killed you, and "
            .. "every death saved and grouped by dungeon or raid visit.",
    },
}

local function CurrentVersion()
    return C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"
end

-- ONE UPDATE NOTE AT A TIME, across all of the Squizz addons.
--
-- SquizzFrames, Squizzumables and Avatar Continued each carry a copy of this
-- window, and the copies were identical: same size, same spot, same DIALOG
-- strata, same frame level. Frames that tie on strata and level have no defined
-- draw order, so when two of them updated at the same login their notes drew
-- through each other and flickered as the order flipped.
--
-- The queue lives in _G and is created by whichever addon loads first. Notes
-- that come due at login wait behind one already on screen and appear when it
-- closes; notes opened by hand (/sf notes) show straight away, on top.
--
-- KEEP THIS BLOCK IDENTICAL IN ALL THREE ADDONS. They share the table, so its
-- shape is an interface between them.
local NotesQueue = _G.SquizzNotesQueue or { pending = {} }
_G.SquizzNotesQueue = NotesQueue

local function PresentNotes(f, queued)
    local active = NotesQueue.active
    if queued and active and active ~= f and active:IsShown() then
        for _, waiting in ipairs(NotesQueue.pending) do
            if waiting == f then return end
        end
        table.insert(NotesQueue.pending, f)
        return
    end
    NotesQueue.active = f
    f:Show()
    f:Raise()
end

local function OnNotesHidden(f)
    if NotesQueue.active ~= f then return end
    NotesQueue.active = nil
    local nextFrame = table.remove(NotesQueue.pending, 1)
    if nextFrame then
        PresentNotes(nextFrame, false)
    end
end

-- Narrower than the frame by the scroll bar's gutter.
local BODY_WIDTH = 404

local frame

local function BuildFrame()
    if frame then return frame end
    local L = addon.Window.Look
    local C, FONT = L.C, L.FONT
    L.RefreshAccent()

    frame = CreateFrame("Frame", "SquizzcapWelcome", UIParent)
    frame:SetSize(460, 320)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    frame:SetToplevel(true)
    frame:HookScript("OnHide", OnNotesHidden)
    local bg = L.Fill(frame, "BACKGROUND", C.bg)
    bg:SetAllPoints()
    L.AddBorder(frame, C.border)

    local title = L.Text(frame, FONT.head, 18, L.accent)
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -16)
    frame.title = title

    -- Scrolls, bounded between the title and the buttons, so a long release
    -- can never push text under the buttons (Squizzumables shipped that bug).
    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -26, 52)
    frame.scroll = scroll

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(BODY_WIDTH, 1)
    scroll:SetScrollChild(content)
    frame.content = content

    local body = L.Text(content, FONT.body, 13, C.text)
    body:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    body:SetWidth(BODY_WIDTH)
    body:SetJustifyV("TOP")
    body:SetWordWrap(true)
    body:SetSpacing(4)
    frame.body = body

    local openBtn = L.SmallButton(frame, 130, 26, "Options")
    openBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 16)
    openBtn:SetScript("OnClick", function()
        frame:Hide()
        addon.ToggleOptions()
    end)

    local closeBtn = L.SmallButton(frame, 90, 26, CLOSE)
    closeBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 16)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    return frame
end

-- queued: true for the automatic login note, which waits its turn behind
-- another addon's note; false/nil when opened by hand.
local function Show(titleText, bodyText, queued)
    local f = BuildFrame()
    f.title:SetText(titleText)
    f.body:SetText(bodyText)
    -- Size the scroll child AFTER SetText, to the wrapped height.
    f.content:SetHeight(math.max(1, f.body:GetStringHeight() + 4))
    f.scroll:SetVerticalScroll(0)
    PresentNotes(f, queued)
end

local function ShowFirstRun(queued)
    Show("Welcome to Squizzcap",
        "Squizzcap shows you what killed you, the moment you die.\n\n"
        .. "A compact summary pops up with the killing blow and how fast you went down; click Details for the "
        .. "full recap: a health graph, every hit and heal, and who hit you.\n\n"
        .. "Every death is saved and grouped by dungeon or raid visit, so you can look back over a whole key "
        .. "afterwards: /squizzcap show opens your last one.\n\n"
        .. "Options: /squizzcap.", queued)
end

local function ShowUpdated(version, queued)
    local notes = RELEASE_NOTES[version]
    local body = string.format("Squizzcap has been updated to %s.", version) .. "\n\n"
    if notes then
        for _, line in ipairs(notes) do
            body = body .. "- " .. line .. "\n"
        end
        body = body .. "\n" .. "The full changelog is in CHANGELOG.txt in the addon folder."
    else
        body = body .. "See CHANGELOG.txt in the addon folder for what changed."
    end
    Show("Squizzcap updated", body, queued)
end

-- Reads lastSeenVersion straight off the account-wide SavedVariable.
local function CheckVersion()
    SquizzcapAccountDB = SquizzcapAccountDB or {}
    local version = CurrentVersion()
    local seen = SquizzcapAccountDB.lastSeenVersion
    if seen == nil then
        -- New install, or an upgrade from before this file existed.
        if addon.hadSavedVariables then
            ShowUpdated(version, true)
        else
            ShowFirstRun(true)
        end
    elseif seen ~= version then
        ShowUpdated(version, true)
    end
    SquizzcapAccountDB.lastSeenVersion = version
end

-- After login so the SavedVariables exist, delayed past the loading screen.
local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function()
    C_Timer.After(4, CheckVersion)
end)

Welcome.ShowReleaseNotes = function() ShowUpdated(CurrentVersion()) end
Welcome.ShowFirstRun = ShowFirstRun
