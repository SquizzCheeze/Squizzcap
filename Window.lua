--[[
  Squizzcap - Window.lua

  The recap window: a glance layer (killed-by card, three quick stats, the
  health strip and the what-hit-you bar) over a drill-down area with three
  tabs (Hits, Sources, All deaths). Plus the compact toast.

  Everything is drawn from the model Data.lua builds. A model flagged
  `secret` (the game hid recap values from addon code) shows only what can
  be handed straight to a widget -- the card and the hit list -- and hides
  every calculated section instead of guessing.
]]

local _, addon = ...
local Data = addon.Data
local Window = {}
addon.Window = Window

local IsSecret = Data.IsSecret

-- ---------------------------------------------------------------------------
-- Look
-- ---------------------------------------------------------------------------

local FONT_DIR = "Interface\\AddOns\\Squizzcap\\Media\\Fonts\\"
local FONT = {
    body     = FONT_DIR .. "Barlow-Regular.ttf",
    bodyBold = FONT_DIR .. "Barlow-SemiBold.ttf",
    head     = FONT_DIR .. "BarlowSemiCondensed-Bold.ttf",
    headSemi = FONT_DIR .. "BarlowSemiCondensed-SemiBold.ttf",
}
local WHITE = "Interface\\Buttons\\WHITE8x8"
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local GLOW = "Interface\\Buttons\\UI-ActionButton-Border"

local C = {
    bg       = { 0.059, 0.063, 0.071, 0.97 },
    title    = { 0.075, 0.078, 0.090, 1 },
    panel    = { 0.090, 0.094, 0.106, 1 },
    rowSel   = { 0.106, 0.110, 0.125, 1 },
    border   = { 0.165, 0.169, 0.188, 1 },
    grid     = { 0.165, 0.169, 0.188, 1 },
    track    = { 0.150, 0.153, 0.170, 1 },
    text     = { 0.925, 0.914, 0.894 },
    muted    = { 0.640, 0.630, 0.660 },
    dmg      = { 1.000, 0.540, 0.490 },
    avoid    = { 1.000, 0.690, 0.400 },
    avoidBg  = { 0.230, 0.150, 0.070, 1 },
    deadly   = { 1.000, 0.560, 0.650 },
    deadlyBg = { 0.230, 0.080, 0.130, 1 },
    hpGood   = { 0.370, 0.820, 0.410 },
    hpLow    = { 1.000, 0.420, 0.360 },
    burst    = { 1.000, 0.540, 0.490 },
    worn     = { 0.900, 0.800, 0.400 },
}

local accent = { 0.7, 0.7, 0.7 }
local function RefreshAccent()
    local ok, _, class = pcall(UnitClass, "player")
    if ok and class and not IsSecret(class) then
        local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if c then accent[1], accent[2], accent[3] = c.r, c.g, c.b end
    end
end

local function Fmt(n)
    if IsSecret(n) then return n end
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(math.floor(n + 0.5)) end
    return tostring(math.floor(n + 0.5))
end

-- ---------------------------------------------------------------------------
-- Widget helpers
-- ---------------------------------------------------------------------------

local function Fill(parent, layer, color)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    return t
end

-- 1px (or `size`) edges. Square corners throughout, by request.
local function AddBorder(f, color, size)
    size = size or 1
    local e = {}
    for i = 1, 4 do e[i] = f:CreateTexture(nil, "BORDER") end
    e[1]:SetPoint("TOPLEFT"); e[1]:SetPoint("TOPRIGHT"); e[1]:SetHeight(size)
    e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT"); e[2]:SetHeight(size)
    e[3]:SetPoint("TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT"); e[3]:SetWidth(size)
    e[4]:SetPoint("TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT"); e[4]:SetWidth(size)
    function f:SetBorderColor(r, g, b, a)
        for i = 1, 4 do e[i]:SetColorTexture(r, g, b, a or 1) end
    end
    f:SetBorderColor(color[1], color[2], color[3], color[4])
    return e
end

local function Panel(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.bg = Fill(f, "BACKGROUND", C.panel)
    f.bg:SetAllPoints()
    AddBorder(f, C.border)
    return f
end

local function Text(parent, font, size, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(font, size, "")
    fs:SetTextColor(color[1], color[2], color[3], 1)
    fs:SetShadowColor(0, 0, 0, 0.85)
    fs:SetShadowOffset(1, -1)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function Label(parent, text)
    local fs = Text(parent, FONT.headSemi, 11, C.muted)
    fs:SetText(text)
    return fs
end

local function SmallButton(parent, w, h, label)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    b.bg = Fill(b, "BACKGROUND", C.title)
    b.bg:SetAllPoints()
    AddBorder(b, C.border)
    b.label = Text(b, FONT.bodyBold, 12, C.text, "CENTER")
    b.label:SetPoint("CENTER")
    b.label:SetText(label)
    b:SetScript("OnEnter", function(self)
        self:SetBorderColor(accent[1], accent[2], accent[3], 1)
        if self.tip then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(self.tip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBorderColor(C.border[1], C.border[2], C.border[3], 1)
        GameTooltip:Hide()
    end)
    function b:SetEnabledLook(on)
        self:SetEnabled(on)
        self.label:SetAlpha(on and 1 or 0.35)
    end
    return b
end

-- A texture cut to a circle. The mask is its own object and must follow the
-- texture's size, so both share an anchor.
local function Circle(parent, layer, sub)
    local t = parent:CreateTexture(nil, layer, nil, sub)
    t:SetTexture(WHITE)
    local m = parent:CreateMaskTexture()
    m:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetAllPoints(t)
    t:AddMaskTexture(m)
    return t
end

-- AVOIDABLE / DEADLY, with Blizzard's own icon for each.
local BADGE = {
    avoidable = { text = "AVOIDABLE", atlas = "damagemeters-avoidabledamage-icon", fg = C.avoid, bg = C.avoidBg },
    deadly    = { text = "DEADLY",    atlas = "icons_16x16_deadly",               fg = C.deadly, bg = C.deadlyBg },
}
local function Badge(parent, kind, small)
    local spec = BADGE[kind]
    local b = CreateFrame("Frame", nil, parent)
    local h = small and 16 or 20
    b.bg = Fill(b, "BACKGROUND", spec.bg)
    b.bg:SetAllPoints()
    AddBorder(b, { spec.fg[1], spec.fg[2], spec.fg[3], 0.9 })
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetAtlas(spec.atlas)
    icon:SetSize(h - 6, h - 6)
    icon:SetPoint("LEFT", 3, 0)
    local fs = Text(b, FONT.head, small and 10 or 11, spec.fg)
    fs:SetPoint("LEFT", icon, "RIGHT", 3, 0)
    fs:SetText(spec.text)
    -- Measured on show as well as now: a font file loaded from the addon may
    -- not report its real width on the very first frame it is used.
    local function Fit(self) self:SetSize((h - 6) + 12 + fs:GetStringWidth(), h) end
    Fit(b)
    b:SetScript("OnShow", Fit)
    return b
end

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------

local WIDTH, HEIGHT = 572, 720
local PAD = 12
local INNER = WIDTH - PAD * 2

local frame                 -- SquizzcapDeathRecap
local ui = {}               -- named parts
local state = { tab = "hits", selected = 1, expanded = 1 }

local function SavePosition(f, key)
    local db = addon.db
    if not db then return end
    local point, _, relPoint, x, y = f:GetPoint()
    db[key].point, db[key].relPoint, db[key].x, db[key].y = point, relPoint, x, y
end

local function RestorePosition(f, key)
    local db = addon.db
    local p = db and db[key]
    f:ClearAllPoints()
    if p and p.point and db.window.rememberPosition ~= false then
        f:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
    else
        f:SetPoint(key == "toast" and "TOP" or "CENTER", UIParent, key == "toast" and "TOP" or "CENTER", 0, key == "toast" and -140 or 0)
    end
end

local Render -- forward

local function SpellTooltip(owner, hit)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local shown = false
    if hit.spellId and not hit.environment and not IsSecret(hit.spellId) then
        shown = pcall(GameTooltip.SetSpellByID, GameTooltip, hit.spellId)
    end
    if not shown then GameTooltip:SetText(hit.name or UNKNOWN, 1, 1, 1) end
    if not hit.secret then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(Fmt(hit.amount) .. " damage" .. (hit.overkill > 0 and (" (" .. Fmt(hit.overkill) .. " overkill)") or ""), C.dmg[1], C.dmg[2], C.dmg[3])
        if hit.source then GameTooltip:AddLine(hit.source, C.muted[1], C.muted[2], C.muted[3]) end
        if hit.hpBefore then
            GameTooltip:AddLine(string.format("%.1fs before death, at %d%% health", hit.tbd or 0, math.floor(hit.hpBefore + 0.5)), 1, 0.82, 0)
        end
        if hit.avoidable and DEATH_RECAP_AVOIDABLE_SPELL then
            GameTooltip:AddLine(CreateAtlasMarkup(BADGE.avoidable.atlas, 16, 16) .. " " .. DEATH_RECAP_AVOIDABLE_SPELL, 1, 1, 1, true)
        end
        if hit.deadly and DEATH_RECAP_DEADLY_SPELL then
            GameTooltip:AddLine(CreateAtlasMarkup(BADGE.deadly.atlas, 16, 16) .. " " .. DEATH_RECAP_DEADLY_SPELL, 1, 1, 1, true)
        end
    end
    GameTooltip:Show()
end

-- ----- title bar -----------------------------------------------------------

local function BuildTitle()
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(36)
    local bg = Fill(bar, "BACKGROUND", C.title)
    bg:SetAllPoints()
    local line = Fill(bar, "BORDER", C.border)
    line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); line:SetHeight(1)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() frame:StartMoving() end)
    bar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        SavePosition(frame, "window")
    end)

    ui.titleText = Text(bar, FONT.head, 18, accent)
    ui.titleText:SetPoint("LEFT", 14, 0)
    ui.titleText:SetText("Squizzcap")
    local sub = Text(bar, FONT.body, 13, C.muted)
    sub:SetPoint("LEFT", ui.titleText, "RIGHT", 10, -1)
    sub:SetText("Death recap")

    local close = SmallButton(bar, 26, 26, "x")
    close:SetPoint("RIGHT", -6, 0)
    close:SetScript("OnClick", function() frame:Hide() end)

    ui.report = SmallButton(bar, 58, 26, "Report")
    ui.report:SetPoint("RIGHT", close, "LEFT", -6, 0)
    ui.report.tip = "Post a one-line summary of this death to your group."
    ui.report:SetScript("OnClick", function() addon.ReportDeath(ui.model) end)

    ui.link = SmallButton(bar, 44, 26, "Link")
    ui.link:SetPoint("RIGHT", ui.report, "LEFT", -6, 0)
    ui.link.tip = "Put Blizzard's death recap link into chat."
    ui.link:SetScript("OnClick", function() addon.LinkDeath(ui.model) end)

    -- One dot per death this session, newest on the right.
    ui.pips = {}
    ui.pipAnchor = CreateFrame("Frame", nil, bar)
    ui.pipAnchor:SetSize(1, 14)
    ui.pipAnchor:SetPoint("RIGHT", ui.link, "LEFT", -12, 0)
end

local function Pip(i)
    local p = ui.pips[i]
    if p then return p end
    p = CreateFrame("Button", nil, ui.pipAnchor)
    p:SetSize(12, 12)
    p.ring = Circle(p, "ARTWORK", 1)
    p.ring:SetAllPoints()
    p.hole = Circle(p, "ARTWORK", 2)
    p.hole:SetPoint("CENTER")
    p.hole:SetSize(8, 8)
    p:SetScript("OnEnter", function(self)
        local deaths = ui.run and ui.run.deaths or {}
        local m = deaths[self.index]
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(string.format("Death %d of %d this run", self.index, #deaths), 1, 1, 1)
        if m and not m.stub and m.hits and m.hits[1] and not m.secret then
            GameTooltip:AddLine(m.hits[1].name, C.muted[1], C.muted[2], C.muted[3])
        end
        GameTooltip:Show()
    end)
    p:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p:SetScript("OnClick", function(self) Window.ShowDeath(ui.runIndex, self.index) end)
    ui.pips[i] = p
    return p
end

-- ----- killed-by card ------------------------------------------------------

local function BuildCard()
    local card = Panel(frame)
    card:SetHeight(106)
    ui.card = card

    local iconHolder = CreateFrame("Frame", nil, card)
    iconHolder:SetSize(64, 64)
    iconHolder:SetPoint("LEFT", 14, 0)
    ui.glow = iconHolder:CreateTexture(nil, "BACKGROUND")
    ui.glow:SetTexture(GLOW)
    ui.glow:SetBlendMode("ADD")
    ui.glow:SetSize(122, 122)
    ui.glow:SetPoint("CENTER")
    ui.kbIcon = iconHolder:CreateTexture(nil, "ARTWORK")
    ui.kbIcon:SetPoint("TOPLEFT", 2, -2)
    ui.kbIcon:SetPoint("BOTTOMRIGHT", -2, 2)
    ui.kbIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    ui.kbIconBorder = AddBorder(iconHolder, C.border, 2)
    iconHolder:EnableMouse(true)
    iconHolder:SetScript("OnEnter", function(self) if ui.model then SpellTooltip(self, ui.model.hits[1]) end end)
    iconHolder:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ui.kbIconHolder = iconHolder

    local label = Label(card, "KILLED BY")
    label:SetPoint("TOPLEFT", card, "TOPLEFT", 92, -12)

    ui.kbName = Text(card, FONT.head, 24, C.text)
    ui.kbName:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -3)
    ui.kbName:SetPoint("RIGHT", card, "RIGHT", -150, 0)

    ui.kbSource = Text(card, FONT.body, 13, C.text)
    ui.kbSource:SetPoint("TOPLEFT", ui.kbName, "BOTTOMLEFT", 0, -3)
    ui.kbSource:SetPoint("RIGHT", card, "RIGHT", -150, 0)

    ui.kbAvoid = Badge(card, "avoidable")
    ui.kbDeadly = Badge(card, "deadly")

    ui.kbAmount = Text(card, FONT.head, 26, C.dmg, "RIGHT")
    ui.kbAmount:SetPoint("TOPRIGHT", -14, -24)
    ui.kbOverkill = Text(card, FONT.body, 12, C.muted, "RIGHT")
    ui.kbOverkill:SetPoint("TOPRIGHT", ui.kbAmount, "BOTTOMRIGHT", 0, -4)

    -- Shown only when the game hid the recap's values.
    ui.secretNote = Text(frame, FONT.body, 12, C.muted)
    ui.secretNote:SetWordWrap(true)
    ui.secretNote:SetWidth(INNER)
    ui.secretNote:SetText("The game is hiding this recap's numbers from addons here, so totals and the health graph are unavailable. Each hit is still shown.")
end

-- ----- quick stats ---------------------------------------------------------

local function Stat(parent, title)
    local p = Panel(parent)
    local l = Label(p, title)
    l:SetPoint("TOPLEFT", 10, -8)
    p.value = Text(p, FONT.head, 19, C.text)
    p.value:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 0, -2)
    p.sub = Text(p, FONT.body, 12, C.muted)
    p.sub:SetPoint("TOPLEFT", p.value, "BOTTOMLEFT", 0, -1)
    p.sub:SetPoint("RIGHT", -8, 0)
    return p
end

local function BuildStats()
    local row = CreateFrame("Frame", nil, frame)
    row:SetHeight(62)
    ui.stats = row
    local w = (INNER - 16) / 3
    ui.statSpeed = Stat(row, "HOW FAST")
    ui.statDamage = Stat(row, "DAMAGE TAKEN")
    ui.statMitig = Stat(row, "MITIGATED")
    for i, p in ipairs({ ui.statSpeed, ui.statDamage, ui.statMitig }) do
        p:SetSize(w, 62)
        p:SetPoint("TOPLEFT", (i - 1) * (w + 8), 0)
    end
    ui.statMitig.sub:SetText("absorbed, resisted, blocked")
end

-- ----- health strip --------------------------------------------------------

local PLOT_W, PLOT_H = INNER - 56, 100

local function BuildStrip()
    local p = Panel(frame)
    p:SetHeight(156)
    ui.strip = p
    local l = Label(p, "YOUR HEALTH")
    l:SetPoint("TOPLEFT", 12, -9)
    local hint = Text(p, FONT.body, 12, C.muted, "RIGHT")
    hint:SetPoint("TOPRIGHT", -12, -9)
    hint:SetText("Exact at each hit  ·  dim between hits: healing, timing estimated")

    local plot = CreateFrame("Frame", nil, p)
    plot:SetSize(PLOT_W, PLOT_H)
    plot:SetPoint("TOPLEFT", 44, -30)
    ui.plot = plot

    for _, pct in ipairs({ 100, 50, 0 }) do
        local g = Fill(plot, "BACKGROUND", C.grid)
        g:SetHeight(1)
        g:SetPoint("BOTTOMLEFT", 0, PLOT_H * pct / 100)
        g:SetPoint("BOTTOMRIGHT", 0, PLOT_H * pct / 100)
        if pct == 50 then g:SetAlpha(0.6) end
        local t = Text(p, FONT.body, 11, C.muted, "RIGHT")
        t:SetPoint("RIGHT", plot, "BOTTOMLEFT", -6, PLOT_H * pct / 100)
        t:SetText(pct == 0 and "0" or (pct .. "%"))
    end

    ui.lines, ui.cols, ui.dots, ui.ticks = {}, {}, {}, {}
    ui.tomb = plot:CreateTexture(nil, "OVERLAY", nil, 3)
    ui.tomb:SetAtlas("deathrecap-icon-tombstone", true)
end

local function PoolLine(i)
    local l = ui.lines[i]
    if not l then
        l = ui.plot:CreateLine(nil, "ARTWORK")
        l:SetThickness(2)
        ui.lines[i] = l
    end
    return l
end

local function PoolCol(i)
    local c = ui.cols[i]
    if not c then
        c = ui.plot:CreateTexture(nil, "BACKGROUND", nil, 1)
        c:SetWidth(2)
        ui.cols[i] = c
    end
    return c
end

local function PoolTick(i)
    local t = ui.ticks[i]
    if not t then
        t = Text(ui.strip, FONT.body, 11, C.muted, "CENTER")
        ui.ticks[i] = t
    end
    return t
end

local SelectHit -- forward

local function PoolDot(i)
    local d = ui.dots[i]
    if d then return d end
    d = CreateFrame("Button", nil, ui.plot)
    d:SetFrameLevel(ui.plot:GetFrameLevel() + 5)
    d.halo = Circle(d, "ARTWORK", 1)
    d.halo:SetPoint("CENTER")
    d.ring = Circle(d, "ARTWORK", 2)
    d.ring:SetPoint("CENTER")
    d.fill = Circle(d, "ARTWORK", 3)
    d.fill:SetPoint("CENTER")
    d:SetScript("OnEnter", function(self) SpellTooltip(self, ui.model.hits[self.hitIndex]) end)
    d:SetScript("OnLeave", function() GameTooltip:Hide() end)
    d:SetScript("OnClick", function(self) SelectHit(self.hitIndex, true) end)
    ui.dots[i] = d
    return d
end

local function RenderStrip(model)
    local hits = model.hits
    local n = #hits
    local span = 0
    for _, h in ipairs(hits) do if h.tbd > span then span = h.tbd end end
    span = math.max(3, math.ceil(span + 0.5))
    local usableW = PLOT_W - 10
    local function X(tbd) return usableW * (1 - tbd / span) end
    local function Y(pct) return PLOT_H * (pct or 0) / 100 end

    -- Polyline, oldest -> newest: flat from the left edge to the first hit,
    -- then for each hit a vertical drop (the damage) and a slope to the next
    -- hit's starting health (a rise there is healing received).
    local pts = {}
    local oldest = hits[n]
    pts[1] = { 0, Y(oldest.hpBefore) }
    for i = n, 1, -1 do
        local h = hits[i]
        pts[#pts + 1] = { X(h.tbd), Y(h.hpBefore) }
        pts[#pts + 1] = { X(h.tbd), Y(i == 1 and 0 or h.hpAfter) }
    end

    -- Only the hit drops are measured: currentHP is your real health when
    -- each hit landed, healing included. What happened BETWEEN two hits is
    -- not in the recap (no heal events), so those stretches are drawn dim --
    -- the line is right at every hit and an estimate in between.
    local li = 0
    for i = 1, #pts - 1 do
        local a, b = pts[i], pts[i + 1]
        if math.abs(a[1] - b[1]) > 0.01 or math.abs(a[2] - b[2]) > 0.01 then
            li = li + 1
            local l = PoolLine(li)
            local measured = math.abs(a[1] - b[1]) <= 0.01
            l:SetThickness(measured and 2 or 1.5)
            l:SetColorTexture(accent[1], accent[2], accent[3], measured and 1 or 0.45)
            l:SetStartPoint("BOTTOMLEFT", ui.plot, a[1], a[2])
            l:SetEndPoint("BOTTOMLEFT", ui.plot, b[1], b[2])
            l:Show()
        end
    end
    for i = li + 1, #ui.lines do ui.lines[i]:Hide() end

    -- Shaded area: 2px columns under the line. WoW cannot fill an arbitrary
    -- polygon, and a few hundred plain textures cost nothing.
    local function HeightAt(x)
        local h = pts[1][2]
        for i = 1, #pts - 1 do
            local a, b = pts[i], pts[i + 1]
            if x >= a[1] and x <= b[1] then
                if b[1] - a[1] < 0.01 then
                    h = b[2]
                else
                    h = a[2] + (b[2] - a[2]) * (x - a[1]) / (b[1] - a[1])
                end
            end
        end
        return h
    end
    local ci = 0
    for x = 0, usableW - 2, 2 do
        local h = HeightAt(x + 1)
        if h > 0.5 then
            ci = ci + 1
            local c = PoolCol(ci)
            c:SetColorTexture(accent[1], accent[2], accent[3], 0.14)
            c:ClearAllPoints()
            c:SetPoint("BOTTOMLEFT", ui.plot, "BOTTOMLEFT", x, 0)
            c:SetHeight(h)
            c:Show()
        end
    end
    for i = ci + 1, #ui.cols do ui.cols[i]:Hide() end

    -- Hit dots, sized by damage.
    local maxAmt = hits[model.highest].amount
    for i = 1, n do
        local h = hits[i]
        local d = PoolDot(i)
        d.hitIndex = i
        local size = math.floor(10 + math.sqrt(maxAmt > 0 and h.amount / maxAmt or 0) * 12 + 0.5)
        d:SetSize(size + 8, size + 8)
        d:ClearAllPoints()
        d:SetPoint("CENTER", ui.plot, "BOTTOMLEFT", X(h.tbd), Y(i == 1 and 0 or h.hpAfter))
        d.fill:SetSize(size, size)
        d.fill:SetVertexColor(Data.SchoolColor(h.school))
        d.ring:SetSize(size + 4, size + 4)
        d.halo:SetSize(size + 8, size + 8)
        local sel = (state.selected == i)
        if sel then
            d.ring:SetVertexColor(1, 1, 1)
            d.halo:SetVertexColor(accent[1], accent[2], accent[3])
            d.halo:Show()
        else
            d.ring:SetVertexColor(C.bg[1], C.bg[2], C.bg[3])
            d.halo:Hide()
        end
        d:Show()
    end
    for i = n + 1, #ui.dots do ui.dots[i]:Hide() end

    ui.tomb:ClearAllPoints()
    ui.tomb:SetPoint("BOTTOM", ui.plot, "BOTTOMLEFT", X(0), 16)

    -- Seconds-before-death ticks.
    local step = span <= 6 and 1 or (span <= 12 and 2 or 5)
    local ti = 0
    for s = 0, span, step do
        ti = ti + 1
        local t = PoolTick(ti)
        t:ClearAllPoints()
        t:SetPoint("TOP", ui.plot, "BOTTOMLEFT", X(s), -5)
        t:SetText(s == 0 and "0s" or ("-" .. s .. "s"))
        t:Show()
    end
    for i = ti + 1, #ui.ticks do ui.ticks[i]:Hide() end
end

-- ----- what hit you --------------------------------------------------------

local function BuildShare()
    local p = Panel(frame)
    p:SetHeight(68)
    ui.share = p
    local l = Label(p, "WHAT HIT YOU")
    l:SetPoint("TOPLEFT", 12, -9)
    ui.shareBar = CreateFrame("Frame", nil, p)
    ui.shareBar:SetPoint("TOPLEFT", 12, -26)
    ui.shareBar:SetSize(INNER - 24, 10)
    ui.segs = {}
    ui.legend = {}
    local w = (INNER - 24 - 16) / 3
    for i = 1, 3 do
        local e = CreateFrame("Frame", nil, p)
        e:SetSize(w, 16)
        e:SetPoint("TOPLEFT", 12 + (i - 1) * (w + 8), -42)
        e.dot = e:CreateTexture(nil, "ARTWORK")
        e.dot:SetSize(10, 10)
        e.dot:SetPoint("LEFT", 0, 0)
        e.text = Text(e, FONT.body, 12, C.text)
        e.text:SetPoint("LEFT", e.dot, "RIGHT", 6, 0)
        e.text:SetPoint("RIGHT", 0, 0)
        ui.legend[i] = e
    end
end

local function RenderShare(model)
    local total = model.total
    local barW = INNER - 24
    local x = 0
    local gaps = math.max(0, #model.spells - 1) * 2
    for i, s in ipairs(model.spells) do
        local seg = ui.segs[i]
        if not seg then
            seg = ui.shareBar:CreateTexture(nil, "ARTWORK")
            ui.segs[i] = seg
        end
        local w = total > 0 and (barW - gaps) * s.amount / total or 0
        seg:ClearAllPoints()
        seg:SetPoint("TOPLEFT", ui.shareBar, "TOPLEFT", x, 0)
        seg:SetSize(math.max(1, w), 10)
        seg:SetColorTexture(Data.SchoolColor(s.school))
        seg:Show()
        x = x + w + 2
    end
    for i = #model.spells + 1, #ui.segs do ui.segs[i]:Hide() end

    for i = 1, 3 do
        local e = ui.legend[i]
        local s = model.spells[i]
        if s then
            e.dot:SetColorTexture(Data.SchoolColor(s.school))
            local pct = total > 0 and math.floor(s.amount / total * 100 + 0.5) or 0
            e.text:SetText(string.format("%s  |cffa3a1a8%d%%|r", s.name, pct))
            e:Show()
        else
            e:Hide()
        end
    end
end

-- ----- tabs + drill-down area ---------------------------------------------

local TABS = { { id = "hits", label = "Hits" }, { id = "sources", label = "Sources" }, { id = "history", label = "All deaths" } }

local function BuildTabs()
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetHeight(32)
    ui.tabBar = bar
    local line = Fill(bar, "BORDER", C.border)
    line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); line:SetHeight(1)
    ui.tabs = {}
    local prev
    for i, def in ipairs(TABS) do
        local b = CreateFrame("Button", nil, bar)
        b:SetHeight(32)
        b.label = Text(b, FONT.bodyBold, 13, C.muted, "CENTER")
        b.label:SetPoint("CENTER", 0, 1)
        b.under = Fill(b, "ARTWORK", C.border)
        b.under:SetPoint("BOTTOMLEFT"); b.under:SetPoint("BOTTOMRIGHT"); b.under:SetHeight(2)
        b.id = def.id
        b.base = def.label
        b:SetScript("OnClick", function(self)
            state.tab = self.id
            Render()
        end)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("LEFT", 0, 0) end
        prev = b
        ui.tabs[i] = b
    end

    local scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local v = self:GetVerticalScroll() - delta * 40
        self:SetVerticalScroll(math.max(0, math.min(v, self:GetVerticalScrollRange())))
    end)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(INNER, 1)
    scroll:SetScrollChild(child)
    ui.scroll, ui.list = scroll, child
    ui.rows, ui.srcPanels, ui.deathRows = {}, {}, {}
end

local function RenderTabs(model)
    for _, b in ipairs(ui.tabs) do
        local count
        if b.id == "hits" then count = #model.hits
        elseif b.id == "sources" then count = model.sources and #model.sources
        else count = nil end
        b.label:SetText(count and string.format("%s (%d)", b.base, count) or b.base)
        b:SetWidth(b.label:GetStringWidth() + 28)
        local on = (state.tab == b.id)
        b.label:SetTextColor(unpack(on and C.text or C.muted))
        if on then b.under:SetColorTexture(accent[1], accent[2], accent[3], 1) end
        b.under:SetShown(on)
        -- Sources needs the aggregation a secret recap cannot have.
        local usable = not (b.id == "sources" and model.secret)
        b:SetShown(usable)
    end
end

-- Hits tab rows.
local ROW_H, ROW_EXPANDED_H = 38, 76

local function DetailPair(parent, x, title)
    local l = Text(parent, FONT.body, 11, C.muted)
    l:SetPoint("TOPLEFT", x, 0)
    l:SetText(title)
    local v = Text(parent, FONT.bodyBold, 13, C.text)
    v:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 0, -2)
    return v
end

local function Row(i)
    local r = ui.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, ui.list)
    r:SetWidth(INNER)
    r.sel = Fill(r, "BACKGROUND", C.rowSel)
    r.sel:SetAllPoints()
    r.edge = AddBorder(r, { 0.23, 0.23, 0.26, 1 })

    r.time = Text(r, FONT.body, 12, C.muted, "RIGHT")
    r.time:SetPoint("TOPLEFT", 4, -12)
    r.time:SetWidth(40)

    r.iconHolder = CreateFrame("Frame", nil, r)
    r.iconHolder:SetSize(26, 26)
    r.iconHolder:SetPoint("TOPLEFT", 54, -6)
    r.icon = r.iconHolder:CreateTexture(nil, "ARTWORK")
    r.icon:SetPoint("TOPLEFT", 1, -1)
    r.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    AddBorder(r.iconHolder, C.border)
    r.iconHolder:EnableMouse(true)
    r.iconHolder:SetScript("OnEnter", function(self) SpellTooltip(self, ui.model.hits[r.hitIndex]) end)
    r.iconHolder:SetScript("OnLeave", function() GameTooltip:Hide() end)

    r.name = Text(r, FONT.bodyBold, 14, C.text)
    r.name:SetPoint("TOPLEFT", 90, -5)
    r.source = Text(r, FONT.body, 12, C.muted)
    r.source:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -1)
    r.source:SetWidth(250)

    r.avoid = Badge(r, "avoidable", true)
    r.deadly = Badge(r, "deadly", true)

    r.amount = Text(r, FONT.headSemi, 16, C.dmg, "RIGHT")
    r.amount:SetPoint("TOPRIGHT", -10, -11)

    r.hpTrack = Fill(r, "ARTWORK", C.track)
    r.hpTrack:SetSize(64, 6)
    r.hpTrack:SetPoint("TOPRIGHT", -112, -11)
    r.hpFill = r:CreateTexture(nil, "ARTWORK", nil, 1)
    r.hpFill:SetPoint("TOPLEFT", r.hpTrack, "TOPLEFT")
    r.hpFill:SetHeight(6)
    r.hpText = Text(r, FONT.body, 11, C.muted)
    r.hpText:SetPoint("TOPLEFT", r.hpTrack, "BOTTOMLEFT", 0, -3)

    r.detail = CreateFrame("Frame", nil, r)
    r.detail:SetPoint("TOPLEFT", 90, -40)
    r.detail:SetSize(INNER - 100, 30)
    r.dHealth = DetailPair(r.detail, 0, "Health")
    r.dAbsorb = DetailPair(r.detail, 110, "Absorbed")
    r.dResBlk = DetailPair(r.detail, 220, "Resisted / Blocked")
    r.dOverkill = DetailPair(r.detail, 350, "Overkill")

    r:SetScript("OnClick", function(self)
        state.expanded = (state.expanded == self.hitIndex) and nil or self.hitIndex
        state.selected = self.hitIndex
        Render()
    end)
    ui.rows[i] = r
    return r
end

local function RenderHits(model)
    local y = 0
    for i, h in ipairs(model.hits) do
        local r = Row(i)
        r.hitIndex = i
        local open = (state.expanded == i)
        local sel = (state.selected == i)
        r:SetHeight(open and ROW_EXPANDED_H or ROW_H)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", ui.list, "TOPLEFT", 0, -y)
        r.sel:SetShown(sel)
        for _, e in ipairs(r.edge) do e:SetShown(open) end

        r.icon:SetTexture(h.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        r.name:SetText(h.name or UNKNOWN)
        r.source:SetText(h.source or "")
        r.amount:SetText(h.secret and h.amount or ("-" .. Fmt(h.amount)))

        r.avoid:Hide(); r.deadly:Hide()
        if h.secret then
            r.time:SetText("")
            r.hpTrack:Hide(); r.hpFill:Hide(); r.hpText:Hide()
            r.name:SetWidth(300)
        else
            r.time:SetText(h.causedDeath and "death" or string.format("-%.1fs", h.tbd))
            local nameW = math.min(r.name:GetStringWidth(), 200)
            r.name:SetWidth(nameW)
            local anchor = r.name
            for _, b in ipairs({ h.avoidable and r.avoid or false, h.deadly and r.deadly or false }) do
                if b then
                    b:ClearAllPoints()
                    b:SetPoint("LEFT", anchor, "RIGHT", 6, 0)
                    b:Show()
                    anchor = b
                end
            end
            if h.hpBefore then
                local pct = h.hpBefore
                r.hpFill:SetWidth(math.max(1, 64 * pct / 100))
                local c = pct < 35 and C.hpLow or C.hpGood
                r.hpFill:SetColorTexture(c[1], c[2], c[3], 1)
                r.hpText:SetText(string.format("%d%% HP", math.floor(pct + 0.5)))
                r.hpTrack:Show(); r.hpFill:Show(); r.hpText:Show()
            else
                r.hpTrack:Hide(); r.hpFill:Hide(); r.hpText:Hide()
            end
        end

        if open then
            if h.secret then
                r.dHealth:SetText(h.currentHP or "")
                r.dAbsorb:SetText(h.absorbed or "")
                r.dResBlk:SetText(h.resisted or "")
                r.dOverkill:SetText(h.overkill or "")
            else
                r.dHealth:SetText(h.hpBefore and string.format("%d%%  >  %d%%", math.floor(h.hpBefore + 0.5), math.floor((h.causedDeath and 0 or h.hpAfter) + 0.5)) or "-")
                r.dAbsorb:SetText(h.absorbed > 0 and Fmt(h.absorbed) or "-")
                r.dResBlk:SetText((h.resisted > 0 and Fmt(h.resisted) or "-") .. " / " .. (h.blocked > 0 and Fmt(h.blocked) or "-"))
                r.dOverkill:SetText(h.overkill > 0 and Fmt(h.overkill) or "-")
            end
            r.detail:Show()
        else
            r.detail:Hide()
        end
        r:Show()
        y = y + (open and ROW_EXPANDED_H or ROW_H) + 2
    end
    for i = #model.hits + 1, #ui.rows do ui.rows[i]:Hide() end
    return y
end

-- Sources tab.
local function SourcePanel(i)
    local p = ui.srcPanels[i]
    if p then return p end
    p = Panel(ui.list)
    p:SetWidth(INNER)
    p.name = Text(p, FONT.bodyBold, 15, C.text)
    p.name:SetPoint("TOPLEFT", 12, -9)
    p.summary = Text(p, FONT.body, 12, C.muted, "RIGHT")
    p.summary:SetPoint("TOPRIGHT", -12, -11)
    p.lines = {}
    ui.srcPanels[i] = p
    return p
end

local function SourceLine(p, j)
    local l = p.lines[j]
    if l then return l end
    l = CreateFrame("Frame", nil, p)
    l:SetSize(INNER - 24, 16)
    l.name = Text(l, FONT.body, 13, C.text)
    l.name:SetPoint("LEFT", 0, 0)
    l.name:SetWidth(170)
    l.track = Fill(l, "ARTWORK", C.track)
    l.track:SetPoint("LEFT", 180, 0)
    l.track:SetSize(INNER - 24 - 180 - 110, 8)
    l.bar = l:CreateTexture(nil, "ARTWORK", nil, 1)
    l.bar:SetPoint("LEFT", l.track, "LEFT")
    l.bar:SetHeight(8)
    l.amount = Text(l, FONT.body, 13, C.text, "RIGHT")
    l.amount:SetPoint("RIGHT", 0, 0)
    p.lines[j] = l
    return l
end

local function RenderSources(model)
    local y = 0
    for i, src in ipairs(model.sources or {}) do
        local p = SourcePanel(i)
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", ui.list, "TOPLEFT", 0, -y)
        p.name:SetText(src.name)
        p.summary:SetText(string.format("%s  ·  %d%%  ·  %d %s", Fmt(src.amount), math.floor(src.amount / model.total * 100 + 0.5), src.count, src.count == 1 and "hit" or "hits"))
        local top = src.spells[1] and src.spells[1].amount or 1
        local trackW = INNER - 24 - 180 - 110
        for j, sp in ipairs(src.spells) do
            local l = SourceLine(p, j)
            l:ClearAllPoints()
            l:SetPoint("TOPLEFT", 12, -32 - (j - 1) * 20)
            l.name:SetText(string.format("%s |cffa3a1a8x%d|r", sp.name, sp.count))
            l.bar:SetWidth(math.max(1, trackW * sp.amount / top))
            l.bar:SetColorTexture(Data.SchoolColor(sp.school))
            l.amount:SetText(Fmt(sp.amount))
            l:Show()
        end
        for j = #src.spells + 1, #p.lines do p.lines[j]:Hide() end
        local h = 40 + #src.spells * 20
        p:SetHeight(h)
        p:Show()
        y = y + h + 8
    end
    for i = #(model.sources or {}) + 1, #ui.srcPanels do ui.srcPanels[i]:Hide() end
    return y
end

-- Deaths tab: every saved death, grouped into runs (Squizzcap.lua decides
-- where a run starts). A header pages between runs; rows are that run's
-- deaths, newest first.
local function Runs() return addon.db and addon.db.runs or {} end

local function RunTitle(run)
    local t = run.name or UNKNOWN
    if run.keyLevel and run.keyLevel > 0 then t = t .. " +" .. run.keyLevel
    elseif run.difficulty and run.difficulty ~= "" then t = t .. "  ·  " .. run.difficulty end
    return t
end

local function RunHeader()
    if ui.runHeader then return ui.runHeader end
    local h = CreateFrame("Frame", nil, ui.list)
    h:SetSize(INNER, 40)
    h.prev = SmallButton(h, 30, 30, "<")
    h.prev:SetPoint("LEFT", 0, 0)
    h.prev.tip = "Older run"
    h.prev:SetScript("OnClick", function() state.viewRun = state.viewRun - 1; Render() end)
    h.next = SmallButton(h, 30, 30, ">")
    h.next:SetPoint("RIGHT", 0, 0)
    h.next.tip = "Newer run"
    h.next:SetScript("OnClick", function() state.viewRun = state.viewRun + 1; Render() end)
    h.title = Text(h, FONT.head, 16, C.text, "CENTER")
    h.title:SetPoint("TOPLEFT", h.prev, "TOPRIGHT", 8, -1)
    h.title:SetPoint("TOPRIGHT", h.next, "TOPLEFT", -8, -1)
    h.sub = Text(h, FONT.body, 12, C.muted, "CENTER")
    h.sub:SetPoint("TOPLEFT", h.title, "BOTTOMLEFT", 0, -2)
    h.sub:SetPoint("TOPRIGHT", h.title, "BOTTOMRIGHT", 0, -2)
    ui.runHeader = h
    return h
end

local function DeathRow(i)
    local r = ui.deathRows[i]
    if r then return r end
    r = CreateFrame("Button", nil, ui.list)
    r:SetSize(INNER, 48)
    r.bg = Fill(r, "BACKGROUND", C.panel)
    r.bg:SetAllPoints()
    AddBorder(r, C.border)
    r.num = Text(r, FONT.head, 18, C.muted)
    r.num:SetPoint("LEFT", 12, 0)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(28, 28)
    r.icon:SetPoint("LEFT", 40, 0)
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.what = Text(r, FONT.bodyBold, 14, C.text)
    r.what:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 10, 1)
    r.sub = Text(r, FONT.body, 12, C.muted)
    r.sub:SetPoint("TOPLEFT", r.what, "BOTTOMLEFT", 0, -2)
    r.avoid = Badge(r, "avoidable", true)
    r.avoid:SetPoint("RIGHT", -70, 0)
    r.fast = Text(r, FONT.body, 12, C.muted, "RIGHT")
    r.fast:SetPoint("RIGHT", -12, 0)
    r:SetScript("OnClick", function(self) Window.ShowDeath(self.runIndex, self.index) end)
    ui.deathRows[i] = r
    return r
end

local function Ago(t)
    local s = time() - (t or time())
    if s < 60 then return "just now" end
    if s < 3600 then return math.floor(s / 60) .. " min ago" end
    if s < 86400 then return math.floor(s / 3600) .. " h ago" end
    return date("%d %b %H:%M", t)
end

local function RenderHistory()
    local runs = Runs()
    local header = RunHeader()
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", ui.list, "TOPLEFT", 0, 0)
    header:Show()
    if #runs == 0 then
        header.title:SetText("No deaths saved yet")
        header.sub:SetText("")
        header.prev:SetEnabledLook(false)
        header.next:SetEnabledLook(false)
        for _, r in ipairs(ui.deathRows) do r:Hide() end
        return 44
    end

    state.viewRun = math.max(1, math.min(state.viewRun or #runs, #runs))
    local runIndex = state.viewRun
    local run = runs[runIndex]
    header.title:SetText(RunTitle(run))
    header.sub:SetText(string.format("Run %d of %d  ·  %d %s  ·  %s", runIndex, #runs, #run.deaths, #run.deaths == 1 and "death" or "deaths", Ago(run.started)))
    header.prev:SetEnabledLook(runIndex > 1)
    header.next:SetEnabledLook(runIndex < #runs)

    local y = 46
    local list = run.deaths
    local shown = 0
    for i = #list, 1, -1 do
        local m = list[i]
        shown = shown + 1
        local r = DeathRow(shown)
        r.index, r.runIndex = i, runIndex
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", ui.list, "TOPLEFT", 0, -y)
        local kb = m.hits and m.hits[1]
        r.num:SetText(i)
        if m.stub or not kb then
            -- The game hid this recap's values, so nothing could be saved.
            r.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            r.what:SetText("Details hidden by the game")
            r.sub:SetText(Ago(m.when))
            r.avoid:Hide()
            r.fast:SetText("")
        else
            r.icon:SetTexture(kb.icon)
            r.what:SetText(kb.name or UNKNOWN)
            r.sub:SetText((m.secret and "" or ((kb.source or "") .. "  ·  ")) .. Ago(m.when))
            r.avoid:SetShown(not m.secret and kb.avoidable)
            r.fast:SetText((not m.secret and m.speed) and string.format("%.1fs", m.speed.seconds) or "")
        end
        local cur = (run == ui.run and i == ui.deathIndex)
        r:SetBorderColor(cur and accent[1] or C.border[1], cur and accent[2] or C.border[2], cur and accent[3] or C.border[3], 1)
        r.bg:SetColorTexture(unpack(cur and C.rowSel or C.panel))
        r:Show()
        y = y + 48 + 6
    end
    for i = shown + 1, #ui.deathRows do ui.deathRows[i]:Hide() end
    return y
end

-- ----- layout + render -----------------------------------------------------

local function Stack(list)
    local y = -44
    for _, item in ipairs(list) do
        local f, gap = item[1], item[2] or 8
        if f:IsShown() then
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, y)
            f:SetWidth(INNER)
            y = y - f:GetHeight() - gap
        end
    end
    return y
end

Render = function()
    local model = ui.model
    if not model then return end
    RefreshAccent()
    ui.titleText:SetTextColor(accent[1], accent[2], accent[3])

    local kb = model.hits[1]

    -- Card.
    ui.kbIcon:SetTexture(kb.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    local sr, sg, sb = Data.SchoolColor(kb.school)
    for _, e in ipairs(ui.kbIconBorder) do e:SetColorTexture(sr, sg, sb, 1) end
    ui.glow:SetVertexColor(sr, sg, sb, 0.85)
    ui.kbName:SetText(kb.name or UNKNOWN)
    ui.kbAvoid:Hide(); ui.kbDeadly:Hide()
    if model.secret then
        ui.kbSource:SetText(kb.source or "")
        ui.kbAmount:SetText(kb.amount or "")
        ui.kbOverkill:SetText("")
    else
        local school = Data.SchoolName(kb.school)
        local src = kb.source or ""
        if school then
            src = src .. (src ~= "" and "  ·  " or "") .. string.format("|cff%02x%02x%02x%s|r", sr * 255, sg * 255, sb * 255, school)
        end
        ui.kbSource:SetText(src)
        ui.kbAmount:SetText("-" .. Fmt(kb.amount))
        ui.kbOverkill:SetText(kb.overkill > 0 and (Fmt(kb.overkill) .. " overkill") or "")
        local anchor
        for _, b in ipairs({ kb.avoidable and ui.kbAvoid or false, kb.deadly and ui.kbDeadly or false }) do
            if b then
                b:ClearAllPoints()
                if anchor then b:SetPoint("LEFT", anchor, "RIGHT", 6, 0)
                else b:SetPoint("TOPLEFT", ui.kbSource, "BOTTOMLEFT", 0, -6) end
                b:Show()
                anchor = b
            end
        end
    end

    -- Glance layer.
    local calc = not model.secret
    ui.secretNote:SetShown(model.secret)
    ui.stats:SetShown(calc)
    ui.strip:SetShown(calc and model.hits[1].hpBefore ~= nil)
    ui.share:SetShown(calc)
    if calc then
        local sp = model.speed
        if sp then
            ui.statSpeed.value:SetText(string.format("%d%%  >  0 in %.1fs", math.floor(sp.from + 0.5), sp.seconds))
            ui.statSpeed.sub:SetText(sp.burst and "BURST" or "WORN DOWN")
            local c = sp.burst and C.burst or C.worn
            ui.statSpeed.sub:SetTextColor(c[1], c[2], c[3])
        else
            ui.statSpeed.value:SetText("-")
            ui.statSpeed.sub:SetText("")
        end
        ui.statDamage.value:SetText(Fmt(model.total))
        local inWindow = 0
        for _, h in ipairs(model.hits) do if sp and h.tbd <= sp.seconds then inWindow = inWindow + 1 end end
        ui.statDamage.sub:SetText(sp and string.format("%d hits  ·  %d in the last %.1fs", #model.hits, inWindow, sp.seconds) or (#model.hits .. " hits"))
        ui.statMitig.value:SetText(Fmt(model.mitigated))
        if ui.strip:IsShown() then RenderStrip(model) end
        RenderShare(model)
    end

    if model.secret and state.tab == "sources" then state.tab = "hits" end
    RenderTabs(model)

    local bottom = Stack({
        { ui.card, 8 }, { ui.secretNote, 10 }, { ui.stats, 8 }, { ui.strip, 8 }, { ui.share, 10 }, { ui.tabBar, 8 },
    })
    ui.scroll:ClearAllPoints()
    ui.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, bottom)
    ui.scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD)

    -- Only one tab's widgets are visible at a time.
    for _, r in ipairs(ui.rows) do r:Hide() end
    for _, p in ipairs(ui.srcPanels) do p:Hide() end
    for _, r in ipairs(ui.deathRows) do r:Hide() end
    if ui.runHeader then ui.runHeader:Hide() end
    local h
    if state.tab == "sources" then h = RenderSources(model)
    elseif state.tab == "history" then h = RenderHistory()
    else h = RenderHits(model) end
    ui.list:SetHeight(math.max(1, h))

    -- Title bar: link and report need a readable recap.
    ui.link:SetEnabledLook(model.link ~= nil)
    ui.report:SetEnabledLook(not model.secret)

    -- One dot per death in this run (the last six), newest on the right.
    local n = ui.run and #ui.run.deaths or 0
    local first = math.max(1, n - 5)
    local shown = 0
    for i = n, first, -1 do
        shown = shown + 1
        local p = Pip(shown)
        p.index = i
        p:ClearAllPoints()
        p:SetPoint("RIGHT", ui.pipAnchor, "RIGHT", -(shown - 1) * 18, 0)
        local cur = (i == ui.deathIndex)
        p.ring:SetVertexColor(unpack(cur and accent or { 0.29, 0.29, 0.32 }))
        p.hole:SetVertexColor(unpack(cur and accent or C.title))
        p:Show()
    end
    for i = shown + 1, #ui.pips do ui.pips[i]:Hide() end
    ui.pipAnchor:SetShown(n > 1)
end

-- Select a hit from the strip (jump to it in the list) or from a row.
SelectHit = function(index, fromStrip)
    state.selected = index
    if fromStrip then
        state.tab = "hits"
        state.expanded = index
    end
    Render()
    if fromStrip then
        local y = 0
        for i = 1, index - 1 do y = y + ((state.expanded == i) and ROW_EXPANDED_H or ROW_H) + 2 end
        ui.scroll:SetVerticalScroll(math.min(y, ui.scroll:GetVerticalScrollRange()))
    end
end

local function Build()
    RefreshAccent()
    frame = CreateFrame("Frame", "SquizzcapDeathRecap", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    local bg = Fill(frame, "BACKGROUND", C.bg)
    bg:SetAllPoints()
    AddBorder(frame, { 0, 0, 0, 1 })
    tinsert(UISpecialFrames, "SquizzcapDeathRecap") -- Escape closes it

    BuildTitle()
    BuildCard()
    BuildStats()
    BuildStrip()
    BuildShare()
    BuildTabs()
    frame:Hide()
end

-- ---------------------------------------------------------------------------
-- Compact toast
-- ---------------------------------------------------------------------------

local toast

local function BuildToast()
    toast = CreateFrame("Button", "SquizzcapDeathToast", UIParent)
    toast:SetSize(390, 84)
    toast:SetFrameStrata("DIALOG")
    toast:SetClampedToScreen(true)
    toast:SetMovable(true)
    toast:EnableMouse(true)
    toast:RegisterForDrag("LeftButton")
    toast:SetScript("OnDragStart", toast.StartMoving)
    toast:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self, "toast")
    end)
    local bg = Fill(toast, "BACKGROUND", C.bg)
    bg:SetAllPoints()
    AddBorder(toast, C.border)

    local holder = CreateFrame("Frame", nil, toast)
    holder:SetSize(52, 52)
    holder:SetPoint("LEFT", 14, 0)
    toast.glow = holder:CreateTexture(nil, "BACKGROUND")
    toast.glow:SetTexture(GLOW)
    toast.glow:SetBlendMode("ADD")
    toast.glow:SetSize(98, 98)
    toast.glow:SetPoint("CENTER")
    toast.icon = holder:CreateTexture(nil, "ARTWORK")
    toast.icon:SetPoint("TOPLEFT", 2, -2)
    toast.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    toast.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    toast.iconBorder = AddBorder(holder, C.border, 2)

    toast.name = Text(toast, FONT.head, 19, C.text)
    toast.name:SetPoint("TOPLEFT", holder, "TOPRIGHT", 12, 0)
    toast.avoid = Badge(toast, "avoidable", true)
    toast.avoid:SetPoint("LEFT", toast.name, "RIGHT", 6, 0)
    toast.line2 = Text(toast, FONT.body, 13, C.text)
    toast.line2:SetPoint("TOPLEFT", toast.name, "BOTTOMLEFT", 0, -3)
    toast.line2:SetWidth(210)
    toast.line3 = Text(toast, FONT.body, 12, C.muted)
    toast.line3:SetPoint("TOPLEFT", toast.line2, "BOTTOMLEFT", 0, -2)
    toast.line3:SetWidth(210)

    local close = SmallButton(toast, 20, 20, "x")
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() toast:Hide() end)
    local details = SmallButton(toast, 70, 30, "Details")
    details:SetPoint("BOTTOMRIGHT", -10, 10)
    details:SetScript("OnClick", function()
        toast:Hide()
        Window.Show(toast.model, toast.runIndex, toast.deathIndex)
    end)
    toast:Hide()
end

function Window.ShowToast(model, runIndex, deathIndex)
    if not toast then BuildToast() end
    RefreshAccent()
    toast.model, toast.runIndex, toast.deathIndex = model, runIndex, deathIndex
    local kb = model.hits[1]
    toast.icon:SetTexture(kb.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    local r, g, b = Data.SchoolColor(kb.school)
    for _, e in ipairs(toast.iconBorder) do e:SetColorTexture(r, g, b, 1) end
    toast.glow:SetVertexColor(r, g, b, 0.85)
    toast.name:SetText(kb.name or UNKNOWN)
    if model.secret then
        toast.name:SetWidth(210)
        toast.avoid:Hide()
        toast.line2:SetText(kb.source or "")
        toast.line3:SetText("Click Details for every hit.")
    else
        toast.name:SetWidth(math.min(toast.name:GetStringWidth(), kb.avoidable and 130 or 210))
        toast.avoid:SetShown(kb.avoidable)
        toast.line2:SetText(string.format("%s  |cffff8a7d-%s|r", kb.source or "", Fmt(kb.amount)))
        local sp = model.speed
        toast.line3:SetText(sp and string.format("%d%% > 0 in %.1fs  ·  %s", math.floor(sp.from + 0.5), sp.seconds, sp.burst and "|cffff8a7dBURST|r" or "|cffe6cc66WORN DOWN|r") or "")
    end
    RestorePosition(toast, "toast")
    toast:SetScale(addon.db and addon.db.window.scale or 1)
    toast:Show()
end

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------

-- model: what to draw. runIndex/deathIndex: where it sits in the saved runs,
-- for the title-bar dots and the All deaths tab (nil for neither).
function Window.Show(model, runIndex, deathIndex)
    if not model then return end
    if not frame then Build() end
    ui.model = model
    ui.runIndex = runIndex
    ui.run = runIndex and Runs()[runIndex] or nil
    ui.deathIndex = deathIndex
    state.viewRun = runIndex or #Runs()
    state.tab = "hits"
    state.selected = 1
    state.expanded = 1
    RestorePosition(frame, "window")
    frame:SetScale(addon.db and addon.db.window.scale or 1)
    ui.scroll:SetVerticalScroll(0)
    Render()
    frame:Show()
    if toast then toast:Hide() end
end

-- Open a saved death. A death whose values the game hid was saved as a stub
-- and has nothing to show beyond its row, so it stays where it is.
function Window.ShowDeath(runIndex, deathIndex)
    local run = runIndex and Runs()[runIndex]
    local m = run and run.deaths[deathIndex]
    if not m then return end
    -- This session's live copy, when there is one, carries what a stub lost.
    m = (m.stub and addon.LiveModel and addon.LiveModel(m)) or m
    if m.stub then return end
    local tab = state.tab
    Window.Show(m, runIndex, deathIndex)
    if tab == "history" then
        state.tab = "history"
        Render()
    end
end

function Window.SetScale(scale)
    if frame then frame:SetScale(scale) end
    if toast then toast:SetScale(scale) end
end

function Window.ResetPosition()
    if frame then frame:ClearAllPoints(); frame:SetPoint("CENTER") end
    if toast then toast:ClearAllPoints(); toast:SetPoint("TOP", UIParent, "TOP", 0, -140) end
end
