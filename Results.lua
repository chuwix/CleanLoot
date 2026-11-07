-- The result popup: when a roll ends, a small card says who won the item and with
-- what roll, and what you rolled yourself. With the per-roll lines kept out of the
-- chat (ChatFilter.lua) this is where the numbers go. Hover a card for every roll
-- of that drop; right-click closes it.
--
-- The data comes from CL.API.GetResult (the loot history, or the simulator).

local _, CL = ...

local Results = {}
CL.Results = Results

local CARD_W = 252
local CARD_H, CARD_H_ME = 46, 57   -- a third line when you did not win
local SPACING = 4
local MAX_CARDS = 8   -- as many as the roll frames: a big drop ends all at once
local SHOW_FOR, FADE_FOR = 10, 0.6  -- seconds on screen, then fading out
local RETRY_DELAYS = { 0.3, 1, 2.5 }  -- the winner reaches the history a moment after "complete"
local FLAT = "Interface\\Buttons\\WHITE8X8"
local BACKDROP = {
    bgFile = FLAT, edgeFile = FLAT, edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}
local GOLD = "|cffffd100"

local free = {}      -- cards not in use
local active = {}    -- cards on screen, oldest first
local anchor

-------------------------------------------------
-- Position: its own anchor, same lock rule as the roll frames
-------------------------------------------------
local function GetAnchor()
    if anchor then return anchor end
    anchor = CreateFrame("Frame", "CleanLootResultsAnchor", UIParent)
    anchor:SetSize(1, 1)
    anchor:SetMovable(true)
    anchor:SetClampedToScreen(true)
    local p = CL.db and CL.db.resultsPoint
    if p then
        anchor:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        -- left of the roll frames, which are centred
        anchor:SetPoint("TOPLEFT", UIParent, "CENTER", -430, 150)
    end
    return anchor
end

local function SavePosition()
    local point, _, relPoint, x, y = anchor:GetPoint()
    if CL.db then CL.db.resultsPoint = { point, relPoint, x, y } end
end

-- Movable when the roll frames are, or while a simulated result is on screen.
function Results.CanMove()
    if CL.RollFrames.CanMove() then return true end
    for _, c in ipairs(active) do
        if c.simulated then return true end
    end
    return false
end

function Results.ResetPosition()
    if CL.db then CL.db.resultsPoint = nil end
    local a = GetAnchor()
    a:ClearAllPoints()
    a:SetPoint("TOPLEFT", UIParent, "CENTER", -430, 150)
    Results.Layout()
end

-------------------------------------------------
-- Text helpers
-------------------------------------------------
local function ShortName(name)
    if type(name) ~= "string" then return "?" end
    return name:match("^([^%-]+)") or name
end

local function Hex(r, g, b)
    return ("|cff%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- The class colour of a name: the game's own table first, its colour API second,
-- grey when the class is not known (an unreadable value, a missing entry).
local function ClassColor(class)
    if type(class) == "string" then
        local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if type(c) ~= "table" and C_ClassColor and C_ClassColor.GetClassColor then
            local ok, color = pcall(C_ClassColor.GetClassColor, class)
            if ok then c = color end
        end
        if type(c) == "table" and type(c.r) == "number" and type(c.g) == "number" and type(c.b) == "number" then
            return c.r, c.g, c.b
        end
    end
    return 0.8, 0.8, 0.8
end

-- The roll type as the game's own button picture: dice for Need, coin for Greed.
local ICONS = {
    [CL.ROLL.NEED] = "Interface\\Buttons\\UI-GroupLoot-Dice-Up",
    [CL.ROLL.GREED] = "Interface\\Buttons\\UI-GroupLoot-Coin-Up",
}

-- "<dice> 57", the picture alone when the game gave no number, the plain word for a
-- type without a picture, or nil when it gave neither.
local function RollText(rollType, value)
    local icon = rollType and ICONS[rollType]
    local label = icon and ("|T%s:16:16:0:-2|t"):format(icon) or (rollType and CL.ROLL_NAME[rollType])
    if label and value then return ("%s %s"):format(label, tostring(value)) end
    return label
end

local function WinnerLine(w)
    local roll = RollText(w.type, w.value)
    local who = w.isSelf and (GOLD .. "You|r") or (Hex(ClassColor(w.class)) .. ShortName(w.name) .. "|r")
    if roll then return ("%s won with %s"):format(who, roll) end
    return ("%s won"):format(who)
end

-- Your own roll, when you are not the winner: always shown, passed or not.
local function MeLine(me)
    if not me then return nil end
    if me.type == CL.ROLL.PASS then return "|cffb3b3b3You passed|r" end
    local roll = RollText(me.type, me.value)
    if not roll then return "|cffb3b3b3You did not roll|r" end
    if me.value then return ("You rolled %s"):format(roll) end
    return ("You chose %s"):format(roll)
end

-------------------------------------------------
-- Cards
-------------------------------------------------
local function ShowTooltip(card)
    local res = card.result
    if not res then return end
    GameTooltip:SetOwner(card, "ANCHOR_RIGHT")
    local r, g, b = CL.QualityColor(res.quality)
    GameTooltip:AddLine(res.name or "?", r, g, b)
    for _, e in ipairs(res.rolls) do
        local nr, ng, nb = ClassColor(e.class)
        local who = ShortName(e.name)
        if e.isSelf then nr, ng, nb, who = 1, 0.82, 0, "You" end
        local roll = RollText(e.type, e.value) or "?"
        if e.isWinner then roll = GOLD .. roll .. "|r" end
        GameTooltip:AddDoubleLine(who, roll, nr, ng, nb, 1, 1, 1)
    end
    if res.passes > 0 then
        GameTooltip:AddLine(("%d passed"):format(res.passes), 0.6, 0.6, 0.6)
    end
    if card.sample then
        GameTooltip:AddLine("Drag to move. Right-click when done.", 1, 1, 1)
    end
    GameTooltip:Show()
end

local function CreateCard()
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetSize(CARD_W, CARD_H)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop(BACKDROP)
    f:SetBackdropColor(0.04, 0.04, 0.04, 0.9)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:Hide()

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(32, 32)
    f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -7)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local function Line(font, y)
        local fs = f:CreateFontString(nil, "OVERLAY", font)
        fs:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 6, y)
        fs:SetSize(CARD_W - 58, 13)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        return fs
    end
    f.name = Line("GameFontNormal", -1)
    f.winner = Line("GameFontHighlightSmall", -17)
    f.me = Line("GameFontHighlightSmall", -30)

    f:SetScript("OnEnter", function(self)
        self.hover = true
        if self.age > SHOW_FOR then self.age = SHOW_FOR - 2 end  -- caught while fading
        self:SetAlpha(1)
        ShowTooltip(self)
    end)
    f:SetScript("OnLeave", function(self)
        self.hover = nil
        GameTooltip:Hide()
    end)
    f:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then Results.Remove(self) end
    end)
    f:SetScript("OnDragStart", function(self)
        if not Results.CanMove() then return end
        self.dragging = true
        GetAnchor():StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        if not self.dragging then return end
        self.dragging = nil
        GetAnchor():StopMovingOrSizing()
        SavePosition()
    end)
    f:SetScript("OnUpdate", function(self, elapsed)
        if self.hover or self.dragging or self.sample then return end
        self.age = self.age + (elapsed or 0)
        if self.age <= SHOW_FOR then return end
        local alpha = 1 - (self.age - SHOW_FOR) / FADE_FOR
        if alpha <= 0 then
            Results.Remove(self)
        else
            self:SetAlpha(alpha)
        end
    end)
    return f
end

function Results.Layout()
    local grow = (CL.db and CL.db.growDirection) or "DOWN"
    local scale = (CL.db and CL.db.frameScale) or CL.DEFAULT_SCALE
    local base = GetAnchor()
    local prev
    for _, f in ipairs(active) do
        f:SetScale(scale)
        f:ClearAllPoints()
        if not prev then
            f:SetPoint(grow == "UP" and "BOTTOMLEFT" or "TOPLEFT", base, grow == "UP" and "BOTTOMLEFT" or "TOPLEFT", 0, 0)
        elseif grow == "UP" then
            f:SetPoint("BOTTOMLEFT", prev, "TOPLEFT", 0, SPACING)
        else
            f:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -SPACING)
        end
        prev = f
    end
end

function Results.Remove(card)
    for i, c in ipairs(active) do
        if c == card then table.remove(active, i) break end
    end
    card.result, card.hover, card.dragging, card.sample = nil, nil, nil, nil
    if GameTooltip:IsShown() and GameTooltip:IsOwned(card) then GameTooltip:Hide() end
    card:Hide()
    free[#free + 1] = card
    Results.Layout()
end

function Results.Clear()
    for i = #active, 1, -1 do Results.Remove(active[i]) end
end

function Results.ActiveCount()
    return #active
end

function Results.GetCard(index)
    return active[index]
end

-- Put a result on screen (also what the simulator calls). Returns the card, or
-- nil when the popup is off or there is nothing to say.
function Results.Show(res, simulated, sample)
    if not (sample or (CL.db and CL.db.showResults)) then return nil end
    if type(res) ~= "table" or not res.winner then return nil end

    while #active >= MAX_CARDS do Results.Remove(active[1]) end
    local card = table.remove(free) or CreateCard()
    active[#active + 1] = card

    card.result, card.age, card.simulated = res, 0, simulated and true or nil
    card.sample = sample and true or nil
    card.hover, card.dragging = nil, nil
    card:SetAlpha(1)

    local r, g, b = CL.QualityColor(res.quality)
    card.icon:SetTexture(res.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    card.name:SetText(res.name or "?")
    card.name:SetTextColor(r, g, b)
    card.winner:SetText(WinnerLine(res.winner))
    if not res.winner.class and not sample then
        CL.Debug("result %s: no class for %s (unreadable?), its name stays grey", tostring(res.key), tostring(res.winner.name))
    end

    local me = (not res.winner.isSelf) and MeLine(res.me) or nil
    card.me:SetText(me or "")
    card:SetHeight(me and CARD_H_ME or CARD_H)

    if res.winner.isSelf then
        card:SetBackdropBorderColor(1, 0.82, 0, 1)  -- you won it
    else
        card:SetBackdropBorderColor(r, g, b, 1)
    end

    card:Show()
    Results.Layout()
    return card
end

-- Items the popup speaks about: from the start of their roll until a while after
-- the result. Blizzard's "You won" toast for such an item is redundant (Toasts.lua
-- can hide exactly those). Keyed by the item's plain lower-case name.
local covered = {}   -- name -> time until which it counts as covered

local function PlainName(name)
    name = CL.Plain(name)
    if type(name) ~= "string" then return nil end
    name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:]*:", ""):gsub("|H.-|h", ""):gsub("|h", ""):gsub("|r", "")
    name = name:gsub("[%[%]]", ""):match("^%s*(.-)%s*$")
    return name ~= "" and name:lower() or nil
end

function Results.Cover(name, seconds)
    local n = PlainName(name)
    if not n then return end
    local untilTime = GetTime() + (seconds or 30)
    if (covered[n] or 0) < untilTime then covered[n] = untilTime end
end

function Results.Covers(name)
    if not (CL.db and CL.db.showResults) then return false end
    local n = PlainName(name)
    local untilTime = n and covered[n]
    return untilTime ~= nil and GetTime() < untilTime
end

-- A card to place the popup with: it stays until right-clicked and moves whatever
-- the lock says. Its text is made up.
function Results.ToggleSample()
    for _, c in ipairs(active) do
        if c.sample then
            Results.Remove(c)
            return false
        end
    end
    Results.Show({
        name = "Drag to place the popup", quality = 4, rolls = {}, passes = 0,
        texture = "Interface\\Icons\\INV_Misc_QuestionMark",
        winner = { name = "Example", class = "MAGE", type = CL.ROLL.GREED, value = 57 },
        me = { type = CL.ROLL.GREED, value = 6 },
    }, true, true)
    return true
end

-------------------------------------------------
-- From the game's events
-------------------------------------------------
-- A roll is followed from the moment we know of it until the game names a winner.
-- Several signals feed that, none of them trusted alone: START_LOOT_ROLL (the roll
-- is ours), a history update that still shows no winner, and LOOT_ROLLS_COMPLETE.
-- The complete event's key can be unreadable (a secret value), so a sweep over all
-- the rolls being followed does the looking, not that one key.
local open = {}    -- lootListKey -> time first known: rolls waiting for their winner
local shown = {}   -- lootListKey -> true: already announced
local OPEN_FOR = 900  -- seconds; a roll lasts three minutes at most

local function Announce(key, res)
    open[key] = nil
    shown[key] = true
    Results.Cover(res.name, 30)   -- the winner's toast comes with the result
    local card = Results.Show(res)
    CL.Debug("result %s: %s won %s -> %s", tostring(key), tostring(res.winner.name), tostring(res.name),
        card and "card shown" or "popup is off")
end

-- Look at one roll. `mayOpen`: a roll seen undecided is now one to follow.
local function Consider(key, mayOpen)
    if shown[key] then return end
    local res = CL.API.GetResult(key)
    if not res then
        CL.Debug("result %s: the loot history does not know this drop", tostring(key))
        return
    end
    if res.winner then
        if open[key] then Announce(key, res) end
    elseif res.allPassed then
        open[key] = nil   -- the chat already says everyone passed
    elseif mayOpen and not open[key] then
        open[key] = GetTime()
    end
end

local function Sweep()
    local now = GetTime()
    for key, since in pairs(open) do
        if now - since > OPEN_FOR then
            open[key] = nil
        else
            Consider(key, false)
        end
    end
end

-- START_LOOT_ROLL gave us the roll's key.
function Results.Watch(key)
    key = CL.Plain(key)
    if key ~= nil and not shown[key] then open[key] = open[key] or GetTime() end
end

-- LOOT_ROLLS_COMPLETE: the roll is over. The winner reaches the history a moment
-- later, so look again shortly (the history's own update also looks).
function Results.OnComplete(key)
    key = CL.Plain(key)
    CL.Debug("result: rolls complete, key %s%s", key ~= nil and tostring(key) or "unreadable",
        (InCombatLockdown and InCombatLockdown()) and " (in combat)" or "")
    if key ~= nil and not shown[key] then open[key] = open[key] or GetTime() end
    Sweep()
    for _, delay in ipairs(RETRY_DELAYS) do C_Timer.After(delay, Sweep) end
end

-- LOOT_HISTORY_UPDATE_DROP: somebody's choice or the result changed.
function Results.OnDropUpdate(key)
    key = CL.Plain(key)
    if key == nil then
        Sweep()
    else
        Consider(key, true)
    end
end
