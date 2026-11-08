local _, CL = ...

local K = {}
CL.Keyboard = K

local selectedID, selectedFrame
local inspection, inspectionAnchor, inspectionToggle

local function Eligible(f)
    if not f or not f.rollID then return false end
    if CL.Plain(f.link) or CL.Plain(f.itemName) then return true end
    for _, rollType in ipairs(CL.ROLL_ORDER) do
        if f.buttons[rollType] and not f.buttons[rollType].unavailable then return true end
    end
    return false
end

local function Reason(f, rollType)
    local reason = CL.Plain(rollType == CL.ROLL.NEED and f.reasonNeed or f.reasonGreed)
    return (reason and rawget(_G, "LOOT_ROLL_INELIGIBLE_REASON" .. tostring(reason)))
        or ("You can't roll %s on this item."):format(CL.ROLL_NAME[rollType])
end

local function EnsureInspectionAnchor()
    if not inspectionAnchor then
        inspectionAnchor = CreateFrame("Frame", nil, UIParent)
        inspectionAnchor:SetSize(252, 1)
        inspectionAnchor:Show()
    end
end

local function EnsureInspection()
    if inspection then return end
    EnsureInspectionAnchor()
    inspection = CreateFrame("GameTooltip", "CleanLootInspectionTooltip", UIParent, "GameTooltipTemplate")
    inspection:SetClampedToScreen(true)
    inspection:EnableMouse(false)
end

local function LayoutToggle()
    local frames = CL.RollFrames.VisibleFrames()
    if not CL.db.keyboardEnabled or not frames[1] then
        if inspectionToggle then inspectionToggle:Hide() end
        return
    end
    if not inspectionToggle then
        local flat = "Interface\\Buttons\\WHITE8X8"
        inspectionToggle = CreateFrame("Button", "CleanLootInspectionToggle", UIParent, "BackdropTemplate")
        inspectionToggle:SetSize(92, 20)
        inspectionToggle:SetBackdrop({ bgFile = flat, edgeFile = flat, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 } })
        inspectionToggle:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
        inspectionToggle:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
        inspectionToggle.label = inspectionToggle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        inspectionToggle.label:SetPoint("CENTER")
        inspectionToggle:SetFrameStrata("DIALOG")
        inspectionToggle:SetClampedToScreen(true)
        inspectionToggle:RegisterForClicks("LeftButtonUp")
        inspectionToggle:SetScript("OnClick", function() K.Action("inspect") end)
        inspectionToggle:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(0.6, 0.6, 0.6, 1) end)
        inspectionToggle:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.25, 0.25, 0.25, 1) end)
    end
    local up = CL.db.growDirection == "UP"
    local left = CL.db.keyboardInspectSide == "LEFT"
    inspectionToggle:ClearAllPoints()
    inspectionToggle:SetScale(CL.db.frameScale or CL.DEFAULT_SCALE)
    inspectionToggle:SetPoint(up and (left and "TOPRIGHT" or "TOPLEFT") or (left and "BOTTOMRIGHT" or "BOTTOMLEFT"),
        inspectionAnchor, up and (left and "BOTTOMLEFT" or "BOTTOMRIGHT") or (left and "TOPLEFT" or "TOPRIGHT"),
        left and -12 or 12, up and -5 or 5)
    inspectionToggle.label:SetText(CL.db.keyboardInspect and "Inspect: On" or "Inspect: Off")
    if CL.db.keyboardInspect then
        inspectionToggle.label:SetTextColor(1, 0.82, 0)
    else
        inspectionToggle.label:SetTextColor(0.7, 0.7, 0.7)
    end
    inspectionToggle:Show()
end

function K.Layout()
    if CL.db.keyboardEnabled and #CL.RollFrames.VisibleFrames() > 0 then EnsureInspectionAnchor() end
    if not inspectionAnchor then LayoutToggle() return end
    local up = CL.db.growDirection == "UP"
    inspectionAnchor:ClearAllPoints()
    inspectionAnchor:SetScale(CL.db.frameScale or CL.DEFAULT_SCALE)
    inspectionAnchor:SetPoint(up and "BOTTOMLEFT" or "TOPLEFT", CL.RollFrames.Anchor(),
        up and "BOTTOMLEFT" or "TOPLEFT")
    LayoutToggle()
    if not inspection then return end
    inspection:ClearAllPoints()
    if CL.db.keyboardInspectSide == "LEFT" then
        inspection:SetPoint(up and "BOTTOMRIGHT" or "TOPRIGHT", inspectionAnchor,
            up and "BOTTOMLEFT" or "TOPLEFT", -12, 0)
    else
        inspection:SetPoint(up and "BOTTOMLEFT" or "TOPLEFT", inspectionAnchor,
            up and "BOTTOMRIGHT" or "TOPRIGHT", 12, 0)
    end
end

local function ShowInspection()
    if not (CL.db.keyboardEnabled and CL.db.keyboardInspect and Eligible(selectedFrame)) then
        if inspection then inspection:Hide() end
        return
    end
    EnsureInspection()
    inspection:SetOwner(inspectionAnchor, "ANCHOR_NONE")
    K.Layout()
    inspection:ClearLines()
    local link = CL.Plain(selectedFrame.link)
    local name = CL.Plain(selectedFrame.itemName)
    local shown = false
    if link then shown = pcall(inspection.SetHyperlink, inspection, link) end
    if not shown then
        local r, g, b = CL.QualityColor(selectedFrame.quality)
        inspection:SetText(name or "Item details unavailable", r, g, b)
    else
        local pawnUpdate = rawget(_G, "PawnUpdateTooltip")
        if type(pawnUpdate) == "function" then
            local ok, err = pcall(pawnUpdate, inspection:GetName(), "SetHyperlink", link)
            if not ok then CL.Debug("Pawn inspection update failed: %s", tostring(err)) end
        end
    end
    inspection:Show()
end

local bindingNames = {
    [CL.ROLL.NEED] = "CLEANLOOT_NEED",
    [CL.ROLL.GREED] = "CLEANLOOT_GREED",
    [CL.ROLL.PASS] = "CLEANLOOT_PASS",
}

local function BindingText(rollType)
    local getKey = rawget(_G, "GetBindingKey")
    if type(getKey) ~= "function" then return nil end
    local ok, key = pcall(getKey, bindingNames[rollType])
    key = ok and CL.Plain(key) or nil
    if type(key) ~= "string" or key == "" then return nil end
    local getText = rawget(_G, "GetBindingText")
    if type(getText) == "function" then
        local textOK, text = pcall(getText, key, "KEY_", true)
        text = textOK and CL.Plain(text) or nil
        if type(text) == "string" and text ~= "" then return text end
    end
    return key
end

local function SetBindingText(hint, text)
    hint:SetText(text)
    hint:SetWidth(0)
    local font, _, flags = hint:GetFont()
    if font then
        local size = 9
        hint:SetFont(font, size, flags)
        while size > 6 and hint:GetStringWidth() > 48 do
            size = size - 1
            hint:SetFont(font, size, flags)
        end
    end
    hint:SetWidth(48)
    hint:Show()
end

function K.RefreshBindings()
    if not CL.db then return end
    for _, f in ipairs(CL.RollFrames.VisibleFrames()) do
        for _, rollType in ipairs(CL.ROLL_ORDER) do
            local b = f.buttons[rollType]
            local text = CL.db.keyboardEnabled and f == selectedFrame and not b.unavailable and BindingText(rollType)
            b.label:ClearAllPoints()
            if text then
                b.label:SetPoint("TOP", b, "TOP", -6, -1)
                SetBindingText(b.binding, text)
            else
                b.label:SetPoint("CENTER")
                b.binding:Hide()
            end
        end
    end
end

local function Select(f)
    if selectedFrame then selectedFrame.selection:Hide() end
    selectedFrame = Eligible(f) and f or nil
    selectedID = selectedFrame and selectedFrame.rollID or nil
    if selectedFrame then selectedFrame.selection:Show() end
    K.RefreshBindings()
    ShowInspection()
end

local function First()
    for _, f in ipairs(CL.RollFrames.VisibleFrames()) do
        if Eligible(f) then return f end
    end
end

function K.OnChanged()
    if not CL.db.keyboardEnabled then return end
    if selectedID and CL.RollFrames.GetFrame(selectedID) == selectedFrame then
        K.RefreshBindings()
        ShowInspection()
    elseif CL.db.keyboardInspect then
        Select(First())
    else
        Select(nil)
    end
end

function K.OnRemoved(rollID, index, removedFrame)
    if removedFrame then removedFrame.selection:Hide() end
    if selectedID ~= rollID then
        K.OnChanged()
        return
    end
    local frames = CL.RollFrames.VisibleFrames()
    local nextFrame
    if CL.db.keyboardEnabled and #frames > 0 then
        for offset = 0, #frames - 1 do
            local f = frames[((index - 1 + offset) % #frames) + 1]
            if Eligible(f) then nextFrame = f break end
        end
    end
    Select(nextFrame)
end

function K.SetEnabled(enabled)
    CL.db.keyboardEnabled = enabled and true or false
    if CL.db.keyboardEnabled then K.OnChanged() else Select(nil) end
    K.Layout()
end

function K.SetSide(side)
    CL.db.keyboardInspectSide = side == "LEFT" and "LEFT" or "RIGHT"
    K.Layout()
end

function K.SelectedID()
    return selectedID
end

local function LootConfirmationOpen()
    local findPopup = rawget(_G, "StaticPopup_FindVisible")
    if type(findPopup) == "function" then
        local ok, popup = pcall(findPopup, "CONFIRM_LOOT_ROLL")
        if ok and popup then return true end
    end
    for i = 1, 4 do
        local popup = rawget(_G, "StaticPopup" .. i)
        if popup and popup.which == "CONFIRM_LOOT_ROLL" and popup:IsShown() then return true end
    end
    return false
end

function K.Action(action)
    if not CL.db.keyboardEnabled then
        CL.Print("Enable keyboard rolls in CleanLoot options first.")
        return
    end
    if action == "inspect" then
        CL.db.keyboardInspect = not CL.db.keyboardInspect
        if CL.db.keyboardInspect and not selectedID then Select(First()) else ShowInspection() end
        K.Layout()
        return
    end
    local frames = CL.RollFrames.VisibleFrames()
    if not selectedID or CL.RollFrames.GetFrame(selectedID) ~= selectedFrame then
        local first = First()
        Select(first)
        if not first then CL.Print("No visible loot roll to select.") end
        return
    end
    if action == "next" or action == "previous" then
        local index
        for i, f in ipairs(frames) do if f.rollID == selectedID then index = i break end end
        if not index then Select(nil) return end
        local step = action == "next" and 1 or -1
        for offset = 1, #frames do
            local f = frames[((index - 1 + step * offset) % #frames) + 1]
            if Eligible(f) then Select(f) return end
        end
        return
    end
    local rollType = ({ need = CL.ROLL.NEED, greed = CL.ROLL.GREED, pass = CL.ROLL.PASS })[action]
    if rollType == nil then return end
    if LootConfirmationOpen() then
        CL.Print("Answer the loot confirmation first.")
        return
    end
    local button = selectedFrame.buttons[rollType]
    if not button or button.unavailable then
        CL.Print(Reason(selectedFrame, rollType))
        return
    end
    local id = selectedID
    local simulated = CL.Sim and CL.Sim.GetRoll(id)
    local waitsForConfirmation = not simulated and selectedFrame.bop and rollType ~= CL.ROLL.PASS
    if CL.API.Roll(id, rollType) then
        if not waitsForConfirmation then CL.RollFrames.Stop(id) end
    else
        CL.Print("Roll not submitted; the item remains selected.")
    end
end

BINDING_HEADER_CLEANLOOT = "CleanLoot"
BINDING_NAME_CLEANLOOT_NEXT = "Select next loot roll"
BINDING_NAME_CLEANLOOT_PREVIOUS = "Select previous loot roll"
BINDING_NAME_CLEANLOOT_INSPECT = "Toggle loot inspection"
BINDING_NAME_CLEANLOOT_NEED = "Roll Need"
BINDING_NAME_CLEANLOOT_GREED = "Roll Greed"
BINDING_NAME_CLEANLOOT_PASS = "Pass on loot"
function CleanLootKeyboardAction(action) K.Action(action) end

local bindingWatcher = CreateFrame("Frame")
bindingWatcher:RegisterEvent("UPDATE_BINDINGS")
bindingWatcher:SetScript("OnEvent", function() K.RefreshBindings() end)
