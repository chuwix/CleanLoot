-- The "You won: [item]" banner Blizzard shows when a roll is won or loot is
-- received. Opt-in: nothing is touched until it is hidden, shrunk or moved.
--   * hide / scale: applied to each loot toast as the alert system hands it out
--     (hook on AlertFrame:AddAlertFrame, plus a sweep after the loot events for a
--     toast that does not go through it).
--   * move: AlertFrame is the anchor every alert banner stacks from, so moving it
--     moves all of them (achievements and the like too), not only the loot ones.

local _, CL = ...

local Toasts = {}
CL.Toasts = Toasts

local MIN_SCALE, MAX_SCALE = 0.5, 1.5
local EVENTS = { "SHOW_LOOT_TOAST", "SHOW_LOOT_TOAST_UPGRADE", "LOOT_ITEM_ROLL_WON" }
local SWEEP_DELAYS = { 0, 0.05, 0.2, 0.5 }  -- a toast is set up and animated in over a few tenths of a second
local FALLBACK_ANCHOR = { "BOTTOM", UIParent, "BOTTOM", 0, 128 }
-- Where the first toast of the stack sits against AlertFrame, until a real one has
-- been measured: standing on top of it. Sizes are in the toast's own units.
local DEFAULT_GEOM = { w = 276, h = 64, point = "BOTTOM", relPoint = "TOP", x = 0, y = 0 }
local GEOM_KEYS = { "w", "h", "point", "relPoint", "x", "y", "scale" }

local known = setmetatable({}, { __mode = "k" })   -- toast frames seen, so a changed setting reaches them
local hooked = setmetatable({}, { __mode = "k" })
local original   -- { point, relativeTo, relPoint, x, y }: AlertFrame's anchor before we moved it
local mover
local applying

local function Clamp(v)
    return math.max(MIN_SCALE, math.min(MAX_SCALE, tonumber(v) or 1))
end

local function Round(v)
    return math.floor(v * 2 + 0.5) / 2   -- half a pixel is plenty
end

local function Name(frame)
    local name = frame and frame.GetName and frame:GetName()
    return CL.Plain(name) or "-"
end

-------------------------------------------------
-- Recognising and styling a loot toast
-------------------------------------------------
-- A loot toast carries its item name as a font string next to an icon/background
-- (this is what keeps achievements, currency and other banners out of it).
local function IsLootToast(frame)
    if type(frame) ~= "table" or not frame.GetObjectType then return false end
    if frame.IsForbidden and frame:IsForbidden() then return false end
    if tostring(Name(frame)):match("^CleanLoot") then return false end
    local item = frame.ItemName
    return type(item) == "table" and item.GetText ~= nil and (frame.Icon ~= nil or frame.Background ~= nil)
end

-- Looking is free: until one loot toast has been measured (for the mover), every
-- one is watched, even with nothing to change.
local function Wanted()
    local db = CL.db
    return db and (db.hideToasts or db.toastScale ~= nil or db.toastPos ~= nil or db.debug
        or db.toastGeom == nil) or false
end

local PlaceMover  -- defined with the mover
local warnedRel

-- The first toast of the stack hangs from AlertFrame by one anchor: its numbers
-- are what the mover copies, so the box sits exactly where a toast will show.
-- Only a toast anchored straight to AlertFrame says anything (the next ones hang
-- from the previous toast). Read before we change the toast's scale.
local function Measure(frame)
    if type(AlertFrame) ~= "table" or not frame.GetPoint then return end
    local point, rel, relPoint, x, y = frame:GetPoint(1)
    if rel ~= AlertFrame then
        if not warnedRel then
            warnedRel = true
            CL.Debug("loot toast hangs from %s, not AlertFrame", Name(rel))
        end
        return
    end
    point, relPoint = CL.Plain(point), CL.Plain(relPoint)
    local g = {
        w = CL.Plain(frame:GetWidth()), h = CL.Plain(frame:GetHeight()),
        point = point, relPoint = relPoint, x = CL.Plain(x) or 0, y = CL.Plain(y) or 0,
    }
    if type(g.w) ~= "number" or type(g.h) ~= "number" or g.w < 20 or g.h < 20 then return end
    if type(point) ~= "string" or type(relPoint) ~= "string" then return end
    local db = CL.db
    if db.toastScale == nil then
        local s = CL.Plain(frame:GetScale())
        if type(s) == "number" and s > 0 then g.scale = s end
    elseif db.toastGeom then
        g.scale = db.toastGeom.scale   -- our own scale is on the frame now: keep the native one
    end
    local old = db.toastGeom
    local same = old ~= nil
    if same then
        for _, k in ipairs(GEOM_KEYS) do
            if old[k] ~= g[k] then same = false break end
        end
    end
    if same then return end
    db.toastGeom = g
    CL.Debug("loot toast geometry: %sx%s %s->%s %s,%s", tostring(g.w), tostring(g.h), point, relPoint,
        tostring(g.x), tostring(g.y))
    if mover and mover:IsShown() then PlaceMover() end
end

local function Style(frame)
    local db = CL.db
    if db.hideToasts then
        if frame:IsShown() then frame:Hide() end
        return
    end
    if db.toastScale ~= nil then
        local scale = Clamp(db.toastScale)
        if frame:GetScale() ~= scale then frame:SetScale(scale) end
    end
end

local function Handle(frame)
    if not IsLootToast(frame) then return end
    if not known[frame] then
        known[frame] = true
        CL.Debug("loot toast seen: %s (%s) parent=%s strata=%s", Name(frame), tostring(frame:GetObjectType()),
            Name(frame:GetParent()), tostring(CL.Plain(frame:GetFrameStrata())))
    end
    if not hooked[frame] and frame.HookScript then
        hooked[frame] = true
        frame:HookScript("OnShow", function(self)
            local ok, err = pcall(Style, self)
            if not ok then CL.Debug("loot toast OnShow: %s", tostring(err)) end
        end)
    end
    local ok, err = pcall(Measure, frame)
    if not ok then CL.Debug("loot toast measure: %s", tostring(err)) end
    Style(frame)
end

local function Safe(frame)
    local ok, err = pcall(Handle, frame)
    if not ok then CL.Debug("loot toast: %s", tostring(err)) end
end

-- Every toast frame we can reach without a hook: the alert pools, AlertFrame's
-- children, and shown FULLSCREEN_DIALOG children of UIParent (where the loot
-- toast has been seen to live). Values read from foreign frames can be secret:
-- they are resolved into locals before any comparison.
local function Sweep()
    if not Wanted() then return end
    for frame in pairs(known) do Safe(frame) end

    local alerts = type(AlertFrame) == "table" and AlertFrame or nil
    local systems = alerts and alerts.alertFrameSubSystems
    if type(systems) == "table" then
        for _, system in ipairs(systems) do
            local pool = type(system) == "table" and system.alertFramePool
            if pool and pool.EnumerateActive then
                local ok, iter = pcall(pool.EnumerateActive, pool)
                if ok and iter then
                    for frame in iter do Safe(frame) end
                end
            end
        end
    end
    if alerts and alerts.GetChildren then
        for _, child in ipairs({ alerts:GetChildren() }) do Safe(child) end
    end
    if UIParent.GetChildren then
        for _, child in ipairs({ UIParent:GetChildren() }) do
            local ok, candidate = pcall(function()
                if type(child) ~= "table" or not child.IsShown then return false end
                if child.IsForbidden and child:IsForbidden() then return false end
                local shown, strata = CL.Plain(child:IsShown()), CL.Plain(child:GetFrameStrata())
                return shown == true and strata == "FULLSCREEN_DIALOG"
            end)
            if ok and candidate then Safe(child) end
        end
    end
end

-------------------------------------------------
-- Position (AlertFrame, the anchor of the whole stack)
-------------------------------------------------
local function CanPlace()
    if type(AlertFrame) ~= "table" or not AlertFrame.SetPoint then return false end
    if AlertFrame.IsForbidden and AlertFrame:IsForbidden() == true then return false end
    if AlertFrame.IsAnchoringRestricted and AlertFrame:IsAnchoringRestricted() == true then return false end
    return true
end

function Toasts.ApplyPosition()
    local pos = CL.db and CL.db.toastPos
    if not pos or applying or not CanPlace() then return end
    applying = true
    local ok, err = pcall(function()
        AlertFrame:ClearAllPoints()
        AlertFrame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    end)
    applying = false
    if not ok then CL.Debug("toast position: %s", tostring(err)) end
end

-- Where the stack sits now: our saved spot, else Blizzard's own.
local function CurrentAnchor()
    local pos = CL.db.toastPos
    if pos then return pos[1], UIParent, pos[2], pos[3], pos[4] end
    local o = original
    -- anchored to something other than the screen: the box would have no usable reference
    if not o or (o[2] ~= nil and o[2] ~= UIParent) then o = FALLBACK_ANCHOR end
    return o[1], o[2] or UIParent, o[3], o[4], o[5]
end

function Toasts.ResetPosition()
    CL.db.toastPos = nil
    if CanPlace() then
        local o = original or FALLBACK_ANCHOR
        pcall(function()
            AlertFrame:ClearAllPoints()
            AlertFrame:SetPoint(o[1], o[2] or UIParent, o[3], o[4], o[5])
        end)
    end
    if mover and mover:IsShown() then PlaceMover() end
end

-------------------------------------------------
-- Mover: a box the size of a toast, standing where the first one shows. While it
-- sits it hangs from AlertFrame like a real toast (so it follows it); a drag
-- measures how far the box went and moves AlertFrame by the same distance.
-------------------------------------------------
local function Geometry()
    return CL.db.toastGeom or DEFAULT_GEOM
end

local function MoverScale()
    return CL.db.toastScale ~= nil and Clamp(CL.db.toastScale) or Geometry().scale or 1
end

function PlaceMover()
    if not mover then return end
    local g = Geometry()
    mover:SetSize(g.w, g.h)
    mover:SetScale(MoverScale())
    mover:ClearAllPoints()
    mover:SetPoint(g.point, AlertFrame, g.relPoint, g.x, g.y)
    if mover.estimate then mover.estimate:SetShown(CL.db.toastGeom == nil) end
end

local function BuildMover()
    local m = CreateFrame("Frame", "CleanLootToastMover", UIParent, "BackdropTemplate")
    m:SetSize(DEFAULT_GEOM.w, DEFAULT_GEOM.h)
    m:SetFrameStrata("FULLSCREEN_DIALOG")
    m:SetMovable(true)
    m:SetClampedToScreen(true)
    m:EnableMouse(true)
    m:RegisterForDrag("LeftButton")
    m:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    m:SetBackdropColor(0.1, 0.35, 0.1, 0.6)
    m:SetBackdropBorderColor(0.3, 0.9, 0.3, 1)

    local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", m, "TOP", 0, -14)
    title:SetText("Loot toasts")
    local hint = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOP", title, "BOTTOM", 0, -6)
    hint:SetText("Drag to move. Right-click when done.")
    local estimate = m:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    estimate:SetPoint("BOTTOM", m, "BOTTOM", 0, 4)
    estimate:SetText("Size estimated until a loot toast shows")
    m.estimate = estimate

    m:SetScript("OnDragStart", function(self)
        local l, b = self:GetLeft(), self:GetBottom()
        if type(l) ~= "number" or type(b) ~= "number" then return end
        -- off AlertFrame for the drag: the box needs a spot of its own on the screen
        self.dragL, self.dragB = l, b
        self:ClearAllPoints()
        self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
        self:StartMoving()
    end)
    m:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local l, b = self:GetLeft(), self:GetBottom()
        if self.dragL and type(l) == "number" and type(b) == "number" then
            -- the box moved by (l - dragL) of its own units; AlertFrame has its own
            local s = self:GetScale()
            local ra = AlertFrame.GetEffectiveScale and UIParent.GetEffectiveScale
                and AlertFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
            if type(ra) ~= "number" or ra <= 0 then ra = 1 end
            local dx, dy = (l - self.dragL) * s / ra, (b - self.dragB) * s / ra
            local point, _, relPoint, x, y = CurrentAnchor()
            CL.db.toastPos = { point, relPoint, Round(x + dx), Round(y + dy) }
            Toasts.ApplyPosition()
        end
        self.dragL, self.dragB = nil, nil
        PlaceMover()
    end)
    m:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then self:Hide() end
    end)
    m:Hide()
    return m
end

function Toasts.ToggleMover(show)
    if not CanPlace() then
        CL.Print("the toast anchor cannot be moved right now.")
        return
    end
    if not mover then mover = BuildMover() end
    if show == nil then show = not mover:IsShown() end
    if show then
        PlaceMover()
        mover:Show()
    else
        mover:Hide()
    end
end

-------------------------------------------------
-- Settings
-------------------------------------------------
function Toasts.SetHidden(hide)
    CL.db.hideToasts = hide and true or false
    Sweep()
end

function Toasts.SetScale(scale)
    CL.db.toastScale = Clamp(scale)
    if mover and mover:IsShown() then PlaceMover() end
    Sweep()
end

-------------------------------------------------
-- Install
-------------------------------------------------
function Toasts.Setup()
    if CanPlace() and AlertFrame.GetPoint then
        local point, relativeTo, relPoint, x, y = AlertFrame:GetPoint(1)
        if point then original = { point, relativeTo, relPoint, x, y } end
    end
    Toasts.ApplyPosition()

    if type(AlertFrame) == "table" and AlertFrame.AddAlertFrame then
        pcall(hooksecurefunc, AlertFrame, "AddAlertFrame", function(_, frame)
            if Wanted() then Safe(frame) end
        end)
    end
    -- a toast anchored by AlertFrame's own pass would undo our spot: put it back
    if type(AlertFrame) == "table" and AlertFrame.UpdateAnchors then
        pcall(hooksecurefunc, AlertFrame, "UpdateAnchors", function()
            if CL.db.toastPos then Toasts.ApplyPosition() end
        end)
    end

    local watcher = CreateFrame("Frame")
    for _, event in ipairs(EVENTS) do pcall(watcher.RegisterEvent, watcher, event) end
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    watcher:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then
            -- other addons may place AlertFrame during login: ours wins after they are done
            C_Timer.After(2, Toasts.ApplyPosition)
            return
        end
        if not Wanted() then return end
        for _, delay in ipairs(SWEEP_DELAYS) do C_Timer.After(delay, Sweep) end
    end)
end
