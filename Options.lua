-- Options panel, under Game Menu > Options > AddOns > CleanLoot. A canvas
-- category (the way addons already running on Forever register theirs), with
-- plain widgets of our own: no dependency on Blizzard's option templates beyond
-- the check button and the button.

local _, CL = ...

local Options = {}
CL.Options = Options

local widgets = {}
Options.widgets = widgets

-------------------------------------------------
-- Widgets
-------------------------------------------------
local function Text(parent, text, x, y, font)
    local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return fs
end

local function Checkbox(parent, label, x, y, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local fs = cb.Text
    if type(fs) ~= "table" then
        fs = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    end
    fs:SetText(label)
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        Options.Refresh()
    end)
    cb.Sync = function() cb:SetChecked(get() and true or false) end
    return cb
end

-- A flat horizontal slider (a track and a thumb), so it does not depend on any
-- slider template the client may or may not still ship.
local function Slider(parent, label, x, y, min, max, step, fmt, get, set)
    Text(parent, label, x, y)
    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(220, 16)
    s:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 24)
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)

    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(0.15, 0.15, 0.15, 1)
    track:SetPoint("LEFT", s, "LEFT", 0, 0)
    track:SetPoint("RIGHT", s, "RIGHT", 0, 0)
    track:SetHeight(4)
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(0.9, 0.75, 0.2, 1)
    thumb:SetSize(8, 16)
    s:SetThumbTexture(thumb)

    local value = Text(parent, "", x + 232, y - 24)
    s:SetScript("OnValueChanged", function(self, v)
        if self.syncing then return end
        v = tonumber(("%.2f"):format(math.floor(v / step + 0.5) * step))
        set(v)
        value:SetText(fmt:format(v))
    end)
    s.Sync = function()
        s.syncing = true
        s:SetValue(get())
        value:SetText(fmt:format(get()))
        s.syncing = false
    end
    return s
end

local function PushButton(parent, label, x, y, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 24)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
end

-------------------------------------------------
-- Panel
-------------------------------------------------
function Options.Refresh()
    for _, w in pairs(widgets) do
        if w.Sync then w.Sync() end
    end
end

local function SetDirection(direction)
    CL.db.growDirection = direction
    CL.RollFrames.Layout()
end

local function Build()
    local panel = CreateFrame("Frame")
    panel.name = "CleanLoot"
    Options.panel = panel

    Text(panel, "CleanLoot", 16, -16, "GameFontNormalLarge")
    Text(panel, "v" .. CL.Version(), 110, -20, "GameFontDisableSmall")

    Text(panel, "Roll frames", 16, -56, "GameFontNormalLarge")
    Text(panel, "Stacking direction", 16, -84)
    widgets.down = Checkbox(panel, "Downwards", 16, -102,
        function() return CL.db.growDirection ~= "UP" end,
        function() SetDirection("DOWN") end)
    widgets.up = Checkbox(panel, "Upwards (first at the bottom)", 16, -126,
        function() return CL.db.growDirection == "UP" end,
        function() SetDirection("UP") end)
    widgets.scale = Slider(panel, "Frame scale", 16, -166, 0.8, 1.5, 0.05, "%.2f",
        function() return CL.db.frameScale or CL.DEFAULT_SCALE end,
        function(v) CL.db.frameScale = v CL.RollFrames.Layout() end)
    widgets.native = Checkbox(panel, "Hide Blizzard's own roll frames", 16, -216,
        function() return CL.db.hideNative end,
        function(v) CL.Native.SetHidden(v) end)
    widgets.chat = Checkbox(panel, "Hide roll messages from the chat (winners stay)", 16, -242,
        function() return CL.db.hideRollSpam end,
        function(v) CL.db.hideRollSpam = v end)
    widgets.lock = Checkbox(panel, "Lock the frames' and popup's position", 16, -268,
        function() return CL.db.locked end,
        function(v) CL.db.locked = v end)
    widgets.reset = PushButton(panel, "Reset position", 20, -304, 140, function()
        CL.RollFrames.ResetPosition()
        CL.Results.ResetPosition()
    end)

    -- second column, beside the short rows of the first
    Text(panel, "Loot toasts", 330, -56, "GameFontNormalLarge")
    Text(panel, "The \"You won\" banner Blizzard shows.", 330, -84, "GameFontDisableSmall")
    widgets.toastHide = Checkbox(panel, "Hide it", 330, -102,
        function() return CL.db.hideToasts end,
        function(v) CL.Toasts.SetHidden(v) end)
    widgets.toastHideInPopup = Checkbox(panel, "Hide it only for popup items", 330, -126,
        function() return CL.db.hideToastsInPopup end,
        function(v) CL.Toasts.SetHiddenInPopup(v) end)
    widgets.toastScale = Slider(panel, "Size", 330, -164, 0.5, 1.5, 0.05, "%.2f",
        function() return CL.db.toastScale or 1 end,
        function(v) CL.Toasts.SetScale(v) end)
    widgets.toastMove = PushButton(panel, "Move", 334, -214, 80, function() CL.Toasts.ToggleMover() end)
    widgets.toastReset = PushButton(panel, "Reset", 420, -214, 80, function() CL.Toasts.ResetPosition() end)

    Text(panel, "Winner popup", 330, -260, "GameFontNormalLarge")
    Text(panel, "Who won each roll and with what; your own roll too.", 330, -288, "GameFontDisableSmall")
    widgets.results = Checkbox(panel, "Show it", 330, -306,
        function() return CL.db.showResults end,
        function(v)
            CL.db.showResults = v
            if not v then CL.Results.Clear() end
        end)
    widgets.resultsDown = Checkbox(panel, "Stack downwards", 330, -330,
        function() return CL.Results.Direction() ~= "UP" end,
        function() CL.Results.SetDirection("DOWN") end)
    widgets.resultsUp = Checkbox(panel, "Stack upwards", 470, -330,
        function() return CL.Results.Direction() == "UP" end,
        function() CL.Results.SetDirection("UP") end)
    widgets.resultsMove = PushButton(panel, "Move", 334, -366, 80, function() CL.Results.ToggleSample() end)
    widgets.resultsReset = PushButton(panel, "Reset", 420, -366, 80, function() CL.Results.ResetPosition() end)

    Text(panel, "Minimap", 16, -354, "GameFontNormalLarge")
    widgets.minimap = Checkbox(panel, "Hide the minimap button", 16, -378,
        function() return CL.db.minimap and CL.db.minimap.hide end,
        function(v) CL.MinimapButton.SetHidden(v) end)

    Text(panel, "Testing", 16, -428, "GameFontNormalLarge")
    Text(panel, "Fake loot rolls with a simulated group, to try the frames without a real drop.", 16, -454,
        "GameFontDisableSmall")
    widgets.sim = PushButton(panel, "Simulate 3 drops", 20, -476, 150, function() CL.Sim.Start(3) end)
    widgets.simColors = PushButton(panel, "One of each colour", 180, -476, 150, function() CL.Sim.Colors() end)
    widgets.simClear = PushButton(panel, "Clear", 340, -476, 80, function() CL.Sim.Clear() end)

    -- values may have changed through a slash command since the panel was built
    panel:SetScript("OnShow", Options.Refresh)
    Options.Refresh()
    return panel
end

function Options.Setup()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    local panel = Build()
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
    Options.category = category
end

function Options.Open()
    if InCombatLockdown and InCombatLockdown() then
        CL.Print("the options cannot be opened during combat.")
        return
    end
    local category = Options.category
    if not (category and Settings and Settings.OpenToCategory) then
        CL.Print("the options panel is not available.")
        return
    end
    Settings.OpenToCategory(category.GetID and category:GetID() or category.ID)
end
