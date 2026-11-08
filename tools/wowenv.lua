-- Minimal WoW (Forever / retail API) stub harness for running CleanLoot outside
-- the game client. Loads every .lua file listed in CleanLoot.toc, in order, with
-- the (addonName, namespace) varargs WoW passes, and exposes controllable time,
-- timers and events so scenarios can be scripted (see tools/test_forever.lua).
--
-- Not a full API mock: unknown globals fall back to permissive stubs so the
-- addon can run. It checks logic, not looks -- visuals need the real client.

local WOW = { now = 1000, timers = {}, frames = {}, chat = {} }

-------------------------------------------------
-- Generic stub object (callable + indexable)
-------------------------------------------------
local StubMeta = {}
local function NewStub() return setmetatable({}, StubMeta) end
StubMeta.__index = function(t, k)
    local v = function() return NewStub() end
    rawset(t, k, v)
    return v
end
StubMeta.__call = function() return NewStub() end

-------------------------------------------------
-- Frames: real state where the addon depends on it
-------------------------------------------------
-- WoW methods are PascalCase and unknown ones should be harmless no-ops, but
-- plain fields (f.rollID, f.link...) are nil until set -- a frame must never
-- hand back a truthy function for a field the addon has not assigned.
local FrameMeta = {}
FrameMeta.__index = function(t, k)
    if type(k) == "string" and k:match("^%u") then
        local v = function() return NewStub() end
        rawset(t, k, v)
        return v
    end
    return nil
end

local function NewFrame(frameType, name, parent)
    local f = setmetatable({}, FrameMeta)
    local points, shown, scripts, events = {}, false, {}, {}
    local enabled, value, scale = true, 0, 1
    local text = ""

    local function set(k, fn) rawset(f, k, fn) end
    set("SetPoint", function(self, ...) points[#points + 1] = { ... } return self end)
    set("GetPoint", function(self) local p = points[#points] or { "CENTER", nil, "CENTER", 0, 0 } return p[1], p[2], p[3], p[4], p[5] end)
    set("ClearAllPoints", function(self) points = {} end)
    set("Show", function(self) shown = true end)
    set("Hide", function(self) shown = false end)
    set("IsShown", function(self) return shown end)
    set("IsVisible", function(self) return shown end)
    set("SetScript", function(self, ev, fn) scripts[ev] = fn end)
    set("GetScript", function(self, ev) return scripts[ev] end)
    set("HookScript", function(self, ev, fn) local prev = scripts[ev] scripts[ev] = function(...) if prev then prev(...) end return fn(...) end end)
    set("RegisterEvent", function(self, ev) events[ev] = true end)
    set("UnregisterEvent", function(self, ev) events[ev] = nil end)
    set("IsEventRegistered", function(self, ev) return events[ev] == true end)
    set("Enable", function(self) enabled = true end)
    set("Disable", function(self) enabled = false end)
    set("IsEnabled", function(self) return enabled end)
    set("SetValue", function(self, v) value = v end)
    set("GetValue", function(self) return value end)
    set("IsForbidden", function(self) return false end)
    local checked = false
    set("SetChecked", function(self, v) checked = v and true or false end)
    set("GetChecked", function(self) return checked end)
    rawset(f, "__alpha", 1)
    rawset(f, "__clickEnabled", true)
    rawset(f, "__motionEnabled", true)
    set("SetAlpha", function(self, a) rawset(self, "__alpha", a) end)
    set("GetAlpha", function(self) return self.__alpha end)
    set("SetMouseClickEnabled", function(self, v) rawset(self, "__clickEnabled", v) end)
    set("SetMouseMotionEnabled", function(self, v) rawset(self, "__motionEnabled", v) end)
    local strata = "MEDIUM"
    set("SetFrameStrata", function(self, s) strata = s end)
    set("GetFrameStrata", function(self) return strata end)
    set("SetScale", function(self, s) scale = s end)
    set("GetScale", function(self) return scale end)
    set("GetEffectiveScale", function(self) return scale end)  -- parents are not scaled in the harness
    local width, height = 0, 0
    set("SetSize", function(self, w, h) width, height = w, h end)
    set("SetWidth", function(self, w) width = w end)
    set("SetHeight", function(self, h) height = h end)
    set("GetWidth", function(self) return width end)
    set("GetHeight", function(self) return height end)
    -- no layout engine: a scenario that needs screen coordinates rawsets these
    set("GetLeft", function(self) return nil end)
    set("GetBottom", function(self) return nil end)
    set("SetText", function(self, t) text = t end)
    set("GetText", function(self) return text end)
    set("GetName", function(self) return name end)
    set("GetParent", function(self) return parent end)
    set("GetObjectType", function(self) return frameType or "Frame" end)
    set("CreateFontString", function(self) return NewFrame("FontString", nil, self) end)
    set("CreateTexture", function(self) return NewFrame("Texture", nil, self) end)
    if frameType == "FontString" then
        local font, fontSize, fontFlags = "test-font", 10, ""
        set("GetFont", function() return font, fontSize, fontFlags end)
        set("SetFont", function(self, f, size, flags) font, fontSize, fontFlags = f, size, flags end)
        set("GetStringWidth", function() return #tostring(text) * fontSize * 0.6 end)
    end
    if frameType == "GameTooltip" then
        rawset(f, "lines", {})
        set("SetOwner", function(self, owner) self.owner = owner self.lines = {} end)
        set("IsOwned", function(self, owner) return self.owner == owner end)
        set("ClearLines", function(self) self.lines = {} end)
        set("AddLine", function(self, t) self.lines[#self.lines + 1] = tostring(t) end)
        set("AddDoubleLine", function(self, l, r) self.lines[#self.lines + 1] = tostring(l) .. " | " .. tostring(r) end)
        set("SetText", function(self, t) self.lines = { tostring(t) } end)
        set("SetHyperlink", function(self, link) self.link = link self.lines = { tostring(link) } end)
    end
    rawset(f, "__children", {})
    set("GetChildren", function(self) return (table.unpack or unpack)(self.__children) end)
    set("IsMouseClickEnabled", function(self) return self.__clickEnabled end)
    set("IsMouseMotionEnabled", function(self) return self.__motionEnabled end)
    rawset(f, "__events", events)
    rawset(f, "__scripts", scripts)

    WOW.frames[#WOW.frames + 1] = f
    if name then _G[name] = f end
    -- children are real: GetChildren() lets the addon walk a frame's tree
    -- (regions -- textures and font strings -- are not children in WoW's sense)
    if type(parent) == "table" and rawget(parent, "__children")
        and frameType ~= "Texture" and frameType ~= "FontString" then
        local list = rawget(parent, "__children")
        list[#list + 1] = f
    end
    return f
end

function CreateFrame(frameType, name, parent) return NewFrame(frameType, name, parent) end
UIParent = NewFrame("Frame", "UIParent")
UIParent:Show()
GameTooltip = NewFrame("GameTooltip", "GameTooltip")
-- Record what the tooltip would show, so scenarios can check its content.
GameTooltip.lines = {}
rawset(GameTooltip, "SetOwner", function(self, owner) self.owner = owner self.lines = {} end)
rawset(GameTooltip, "IsOwned", function(self, f) return self.owner == f end)
rawset(GameTooltip, "AddLine", function(self, t) self.lines[#self.lines + 1] = tostring(t) end)
rawset(GameTooltip, "AddDoubleLine", function(self, l, r) self.lines[#self.lines + 1] = tostring(l) .. " | " .. tostring(r) end)
rawset(GameTooltip, "SetText", function(self, t) self.lines = { tostring(t) } end)

-------------------------------------------------
-- Time, timers, events
-------------------------------------------------
function GetTime() return WOW.now end
C_Timer = {
    After = function(delay, fn) WOW.timers[#WOW.timers + 1] = { at = WOW.now + delay, fn = fn } end,
}

-- Advance the clock like the game does: in small steps (the real client calls
-- OnUpdate every frame), running due timers in order and OnUpdate scripts.
local STEP = 0.05
function WOW.Advance(dt)
    local remaining = dt
    while remaining > 1e-9 do
        local step = math.min(STEP, remaining)
        remaining = remaining - step
        local target = WOW.now + step
        while true do
            local nextIdx, nextAt
            for i, t in ipairs(WOW.timers) do
                if t.at <= target and (not nextAt or t.at < nextAt) then nextIdx, nextAt = i, t.at end
            end
            if not nextIdx then break end
            local t = table.remove(WOW.timers, nextIdx)
            WOW.now = math.max(WOW.now, t.at)
            t.fn()
        end
        WOW.now = target
        for _, f in ipairs(WOW.frames) do
            local up = f.__scripts.OnUpdate
            if up and f:IsShown() then up(f, step) end
        end
    end
end

function WOW.FireEvent(event, ...)
    for _, f in ipairs(WOW.frames) do
        local h = f.__scripts.OnEvent
        if h and f.__events[event] then h(f, event, ...) end
    end
end

-------------------------------------------------
-- Globals the addon touches
-------------------------------------------------
function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    WOW.chat[#WOW.chat + 1] = table.concat(parts, " ")
end

SlashCmdList = {}
function date(fmt) return os.date(fmt) end
function IsControlKeyDown() return WOW.ctrl or false end
function IsShiftKeyDown() return WOW.shift or false end
function issecretvalue() return false end
function UnitName() return "Tester" end

ITEM_QUALITY_COLORS = {
    [0] = { r = 0.62, g = 0.62, b = 0.62 }, [1] = { r = 1, g = 1, b = 1 },
    [2] = { r = 0.12, g = 1, b = 0 }, [3] = { r = 0, g = 0.44, b = 0.87 },
    [4] = { r = 0.64, g = 0.21, b = 0.93 }, [5] = { r = 1, g = 0.5, b = 0 },
}

-- Item data: id -> name, quality, icon. Every id the simulator may pick is
-- "cached" so a scenario runs without async item loading.
WOW.items = {}
for i, id in ipairs({ 2589, 4306, 118, 2092, 1204, 1980, 12940, 14551, 16799, 11815, 18803, 19019 }) do
    WOW.items[id] = { name = "Item" .. id, quality = (i % 5) + 1, icon = 100000 + id }
end
function GetItemInfo(id)
    local it = WOW.items[id]
    if not it then return nil end
    return it.name, ("|cffffffff|Hitem:%d::::::::|h[%s]|h|r"):format(id, it.name), it.quality, 1, 1, "", "", 1, "", it.icon
end
C_Item = {
    GetItemInfo = GetItemInfo,
    RequestLoadItemDataByID = function() end,
    GetItemQualityColor = function(q) local c = ITEM_QUALITY_COLORS[q] return c.r, c.g, c.b, "ffffffff" end,
}
C_AddOns = { GetAddOnMetadata = function() return "1.0.0-test" end, LoadAddOn = function() return true end }
function InCombatLockdown() return WOW.combat or false end

-- Blizzard's loot history window (load-on-demand in the real client).
GroupLootHistoryFrame = NewFrame("Frame", "GroupLootHistoryFrame")
function GroupLootHistoryFrame:SetShown(v) if v then self:Show() else self:Hide() end end

-- The client's loot roll chat strings, exactly as the diagnostic captured them.
LOOT_ROLL_NEED = "|HlootHistory:%d|h[Loot]|h: %s has selected Need for: %s"
LOOT_ROLL_GREED = "|HlootHistory:%d|h[Loot]|h: %s has selected Greed for: %s"
LOOT_ROLL_PASSED = "|HlootHistory:%d|h[Loot]|h: %s passed on: %s"
LOOT_ROLL_NEED_SELF = "|HlootHistory:%d|h[Loot]|h: You have selected Need for: %s"
LOOT_ROLL_GREED_SELF = "|HlootHistory:%d|h[Loot]|h: You have selected Greed for: %s"
LOOT_ROLL_PASSED_SELF = "|HlootHistory:%d|h[Loot]|h: You passed on: %s"
LOOT_ROLL_WON = "|HlootHistory:%d|h[Loot]|h: %s won: %s"
LOOT_ROLL_YOU_WON = "|HlootHistory:%d|h[Loot]|h: You won: %s"
LOOT_ROLL_ROLLED_NEED = "|HlootHistory:%d|h[Loot]|h: Need Roll - %d for %s by %s"
LOOT_ROLL_ROLLED_GREED = "|HlootHistory:%d|h[Loot]|h: Greed Roll - %d for %s by %s"
WOW.chatFilters = {}
function ChatFrame_AddMessageEventFilter(event, fn) WOW.chatFilters[event] = fn end

-- Settings API: record what gets registered / opened.
Settings = {
    RegisterCanvasLayoutCategory = function(panel, name)
        local c = { ID = 99, name = name, panel = panel, GetID = function() return 99 end }
        WOW.category = c
        return c
    end,
    RegisterAddOnCategory = function(c) WOW.registeredCategory = c end,
    OpenToCategory = function(id) WOW.openedCategory = id end,
}

-- Fake LibStub + LibDataBroker + LibDBIcon (the real ones are exercised in the
-- game; here we only check how the addon drives them).
WOW.libs, WOW.ldbObjects = {}, {}
WOW.dbicon = { registered = {}, hidden = {} }
WOW.libs["LibDataBroker-1.1"] = {
    NewDataObject = function(self, name, obj)
        if WOW.ldbObjects[name] then return nil end
        WOW.ldbObjects[name] = obj
        return obj
    end,
    GetDataObjectByName = function(self, name) return WOW.ldbObjects[name] end,
}
WOW.libs["LibDBIcon-1.0"] = {
    Register = function(self, name, obj, db) WOW.dbicon.registered[name] = { obj = obj, db = db } end,
    IsRegistered = function(self, name) return WOW.dbicon.registered[name] ~= nil end,
    Hide = function(self, name) WOW.dbicon.hidden[name] = true end,
    Show = function(self, name) WOW.dbicon.hidden[name] = false end,
}
LibStub = { GetLibrary = function(self, name) return WOW.libs[name] end }

Enum = { EncounterLootDropRollState = { NeedMainSpec = 0, NeedOffSpec = 1, Transmog = 2, Greed = 3, NoRoll = 4, Pass = 5 } }
RAID_CLASS_COLORS = {
    DRUID = { r = 1, g = 0.49, b = 0.04 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
    HUNTER = { r = 0.67, g = 0.83, b = 0.45 }, SHAMAN = { r = 0, g = 0.44, b = 0.87 },
}

-- hooksecurefunc: run `fn` after the original global function, like WoW does.
function hooksecurefunc(target, name, fn)
    -- hooksecurefunc("Global", fn) or hooksecurefunc(table, "Method", fn)
    local holder = _G
    if type(target) == "table" then holder = target else fn, name = name, target end
    local orig = holder[name]
    holder[name] = function(...)
        local result = orig(...)
        fn(...)
        return result
    end
end

-- Blizzard's native roll frames: a managed container holding named roll frames,
-- each with an icon button and a container of roll buttons (shape taken from the
-- real client, see the ForeverDiag capture).
GroupLootContainer = NewFrame("Frame", "GroupLootContainer")
GroupLootContainer.maxIndex = 3
GroupLootContainer.rollFrames = {}
for i = 1, 4 do
    local nf = NewFrame("Frame", "GroupLootFrame" .. i, GroupLootContainer)
    nf.IconFrame = NewFrame("Button", nil, nf)
    nf.LootButtonContainer = NewFrame("Frame", nil, nf)
    for _, key in ipairs({ "NeedButton", "GreedButton", "PassButton", "TransmogButton" }) do
        nf.LootButtonContainer[key] = NewFrame("Button", nil, nf.LootButtonContainer)
    end
end
function GroupLootContainer_AddFrame() end
function GroupLootContainer_Update() end

-- Blizzard's alert banners: AlertFrame is the anchor they stack from, and every
-- banner goes through AddAlertFrame (which shows it).
AlertFrame = NewFrame("Frame", "AlertFrame", UIParent)
AlertFrame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 128)
AlertFrame.alertFrameSubSystems = {}
function AlertFrame:AddAlertFrame(frame) frame:Show() end

-- What the "player" owns, for the simulator's item pool.
WOW.equipped = {}  -- slot -> itemID
WOW.bags = {}      -- bag -> { itemID, ... }
function GetInventoryItemID(unit, slot) return WOW.equipped[slot] end
C_Container = {
    GetContainerNumSlots = function(bag) local b = WOW.bags[bag] return b and #b or 0 end,
    GetContainerItemID = function(bag, slot) local b = WOW.bags[bag] return b and b[slot] end,
}

-- Anything else: a permissive stub (namespaces become indexable tables).
setmetatable(_G, {
    __index = function(t, k)
        -- SavedVariables are genuinely nil on a first run
        if type(k) == "string" and k:match("DB$") then return nil end
        local v
        if type(k) == "string" and k:match("^C_") then v = NewStub() else v = function() return NewStub() end end
        rawset(t, k, v)
        return v
    end,
})

-------------------------------------------------
-- Load the addon exactly as WoW would: files from the .toc, in order
-------------------------------------------------
local ADDON = "CleanLoot"
local CL = {}
WOW.CL = CL

for line in io.lines("CleanLoot.toc") do
    local file = line:match("^([^#%s][^%s]*%.lua)%s*$")
    -- the embedded libraries are replaced by fakes above
    if file and not file:match("^Libs[\\/]") then
        local chunk, err = loadfile(file)
        if not chunk then
            io.stderr:write("PARSE FAILED " .. file .. ": " .. tostring(err) .. "\n")
            os.exit(1)
        end
        local ok, runErr = pcall(chunk, ADDON, CL)
        if not ok then
            io.stderr:write("RUNTIME ERROR in " .. file .. ": " .. tostring(runErr) .. "\n")
            os.exit(1)
        end
    end
end

WOW.FireEvent("ADDON_LOADED", ADDON)

WOW.loaded = true
io.write("LOADED OK\n")
return WOW
