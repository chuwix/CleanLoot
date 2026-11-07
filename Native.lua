-- Hide Blizzard's own loot roll frames (GroupLootFrame1..N inside
-- GroupLootContainer): ours replace them.
--
-- GroupLootContainer is a managed frame -- its position and layout belong to the
-- UI's secure managed-layout pass, and addon code writing to it taints that pass
-- (EllesmereUI documents the same). So nothing here moves, resizes, reparents or
-- hides anything: only alpha and mouse state, both plain widget calls.
--
-- Alpha: the roll frames are NOT children of the container (they are only
-- positioned against it), so each gets its own. Mouse: an invisible frame still
-- catches clicks, so every frame in each roll frame's tree stops accepting the
-- mouse. The original mouse state of each frame is remembered and put back on
-- the option is turned off. Re-applied after Blizzard's own updates, on the next frame
-- and never from inside them.

local _, CL = ...

local Native = {}
CL.Native = Native

local ROLL_BUTTONS = { "NeedButton", "GreedButton", "PassButton", "TransmogButton" }
local MAX_DEPTH = 5

local hiddenByUs = false
local pending = false
local installed = false

-- frame -> { click, motion }: how it was before we switched its mouse off
local savedMouse = setmetatable({}, { __mode = "k" })

local function GetMouse(frame)
    local click, motion = true, true
    if frame.IsMouseClickEnabled then click = frame:IsMouseClickEnabled() end
    if frame.IsMouseMotionEnabled then motion = frame:IsMouseMotionEnabled() end
    return click, motion
end

local function SetMouse(frame, click, motion)
    if frame.SetMouseClickEnabled then frame:SetMouseClickEnabled(click) end
    if frame.SetMouseMotionEnabled then frame:SetMouseMotionEnabled(motion) end
end

-- Mouse off (remembering what it was) or back to what it was.
local function Mouse(frame, enabled)
    if type(frame) ~= "table" then return end
    if enabled then
        local saved = savedMouse[frame]
        if saved then
            SetMouse(frame, saved.click, saved.motion)
            savedMouse[frame] = nil
        end
    else
        if not savedMouse[frame] then
            local click, motion = GetMouse(frame)
            savedMouse[frame] = { click = click, motion = motion }
        end
        SetMouse(frame, false, false)
    end
end

-- The frame and everything below it.
local function MouseTree(frame, enabled, depth)
    if type(frame) ~= "table" then return end
    if frame.IsForbidden and frame:IsForbidden() then return end
    Mouse(frame, enabled)
    if depth <= 0 or not frame.GetChildren then return end
    for _, child in ipairs({ frame:GetChildren() }) do
        MouseTree(child, enabled, depth - 1)
    end
end

-- Every native roll frame we can find: the named ones and the container's pool.
local function EachRollFrame(container, fn)
    local seen = {}
    local function visit(f)
        if type(f) == "table" and not seen[f] then
            seen[f] = true
            if not (f.IsForbidden and f:IsForbidden()) then fn(f) end
        end
    end
    local maxIndex = tonumber(container.maxIndex) or 4
    for i = 1, math.max(maxIndex, 4) + 2 do visit(_G["GroupLootFrame" .. i]) end
    if type(container.rollFrames) == "table" then
        for _, f in pairs(container.rollFrames) do visit(f) end
    end
end

local function Apply()
    local hide = CL.db and CL.db.hideNative
    -- never touch Blizzard's frames when we have not hidden them (another addon
    -- may own their alpha)
    if not hide and not hiddenByUs then return end

    local container = _G.GroupLootContainer
    if type(container) ~= "table" then return end
    if container.IsForbidden and container:IsForbidden() then return end

    container:SetAlpha(hide and 0 or 1)
    Mouse(container, not hide)
    EachRollFrame(container, function(f)
        f:SetAlpha(hide and 0 or 1)
        MouseTree(f, not hide, MAX_DEPTH)
        -- the buttons by name too, in case a pooled frame's tree is not walkable
        local box = f.LootButtonContainer
        if box then
            Mouse(f.IconFrame, not hide)
            for _, key in ipairs(ROLL_BUTTONS) do Mouse(box[key], not hide) end
        end
    end)
    hiddenByUs = hide and true or false
end

-- Apply on the next frame, once per burst of Blizzard updates.
function Native.Refresh()
    if pending then return end
    pending = true
    C_Timer.After(0, function()
        pending = false
        local ok, err = pcall(Apply)
        if not ok then CL.Print("hiding the native roll frames failed: " .. tostring(err)) end
    end)
end

-- Blizzard is putting a roll frame on screen: make that one invisible right away
-- (a bare SetAlpha, no layout involved) so it never flashes for a frame, then do
-- the full pass on the next frame.
local function OnAddFrame(_, frame)
    if CL.db and CL.db.hideNative and type(frame) == "table" and frame.SetAlpha then
        pcall(frame.SetAlpha, frame, 0)
    end
    Native.Refresh()
end

-- Blizzard's own animations can put a frame's alpha back, and its code can turn a
-- mouse state back on, without any function we hook being called. So a cheap check
-- (a few frames, four times a second) keeps them hidden; the full mouse pass runs
-- about once a second. It only writes when something actually changed back.
local function Enforce(withMouse)
    local container = _G.GroupLootContainer
    if type(container) ~= "table" then return end
    EachRollFrame(container, function(f)
        if f:GetAlpha() > 0 then pcall(f.SetAlpha, f, 0) end
        if withMouse then MouseTree(f, false, MAX_DEPTH) end
    end)
end
Native.Enforce = Enforce

function Native.Install()
    if installed then return end
    installed = true

    local ticker = CreateFrame("Frame")
    local acc, passes = 0, 0
    ticker:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < 0.25 then return end
        acc = 0
        passes = passes + 1
        if CL.db and CL.db.hideNative then Enforce(passes % 4 == 0) end
    end)
    ticker:Show()

    if _G.GroupLootContainer_AddFrame then hooksecurefunc("GroupLootContainer_AddFrame", OnAddFrame) end
    if _G.GroupLootContainer_Update then hooksecurefunc("GroupLootContainer_Update", Native.Refresh) end
    Native.Refresh()
end

function Native.SetHidden(hide)
    CL.db.hideNative = hide and true or false
    Native.Refresh()
end
