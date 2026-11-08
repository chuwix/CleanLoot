-- Keyboard roll scenarios against the stub client. Run with lua tools/test_keyboard.lua.
local WOW = dofile("tools/wowenv.lua")
local CL, RF = WOW.CL, WOW.CL.RollFrames
local K = CL.Keyboard
local failures, checks = 0, 0
local function check(ok, label)
    checks = checks + 1
    if not ok then failures = failures + 1 io.write("FAIL: " .. label .. "\n") end
end

local function info(bop, canNeed, canGreed)
    return { name = "Test Item", texture = 123, quality = 3, count = 1, bop = bop,
        canNeed = canNeed ~= false, canGreed = canGreed ~= false, reasonNeed = 3 }
end
local function start(id, item)
    return RF.Start(id, item or info(), "|Hitem:123|h[Test Item]|h", 60000)
end
local rolls = {}
function RollOnLoot(id, kind) rolls[#rolls + 1] = { id, kind } end
function StaticPopup_FindVisible(which) return which == "CONFIRM_LOOT_ROLL" and WOW.lootPopup or nil end
WOW.bindings = { CLEANLOOT_NEED = "1", CLEANLOOT_GREED = "SHIFT-2", CLEANLOOT_PASS = "ALT-3" }
function GetBindingKey(action) return WOW.bindings[action] end
function GetBindingText(key) return "key:" .. key end
LOOT_ROLL_INELIGIBLE_REASON3 = "Cannot Need this."

check(CL.db.keyboardEnabled == false and CL.db.keyboardInspect == false, "keyboard and inspection default off")
local a, b = start(1001), start(1002)
check(rawget(_G, "CleanLootInspectionToggle") == nil, "disabled keyboard rolls do not show an inspection button")
SlashCmdList.CLEANLOOT("need")
check(K.SelectedID() == nil and #rolls == 0 and not a.selection:IsShown(), "disabled commands do not select or roll")
check(not a.buttons[CL.ROLL.NEED].binding:IsShown(), "bindings are hidden when keyboard rolls are disabled")
check(CL.Options.widgets.keyboard and CL.Options.widgets.inspectLeft and CL.Options.widgets.inspectRight, "keyboard settings exist")
CL.Options.widgets.keyboard:SetChecked(true)
CL.Options.widgets.keyboard.__scripts.OnClick(CL.Options.widgets.keyboard)
check(CL.db.keyboardEnabled and K.SelectedID() == nil, "enabling with inspection off leaves the stack unchanged")
local toggle = CleanLootInspectionToggle
check(toggle and toggle:IsShown() and toggle.label:GetText() == "Inspect: Off", "enabling with visible rolls shows the inspection button")
check(toggle:GetHeight() == 20 and toggle:GetScript("OnEnter") and toggle:GetScript("OnLeave"),
    "inspection button uses a compact hoverable control")
check((toggle:GetPoint()) == "BOTTOMLEFT", "inspection button sits above the right-hand inspection area")
CL.db.growDirection = "UP"
RF.Layout()
check((toggle:GetPoint()) == "TOPLEFT", "inspection button sits below the right-hand inspection area when the stack grows up")
CL.Options.widgets.inspectLeft.__scripts.OnClick(CL.Options.widgets.inspectLeft)
check((toggle:GetPoint()) == "TOPRIGHT", "inspection button follows the left-hand inspection side when the stack grows up")
CL.Options.widgets.inspectRight.__scripts.OnClick(CL.Options.widgets.inspectRight)
CL.db.growDirection = "DOWN"
RF.Layout()
toggle.__scripts.OnClick(toggle)
check(CL.db.keyboardInspect and K.SelectedID() == 1001 and CleanLootInspectionTooltip:IsShown()
    and toggle.label:GetText() == "Inspect: On", "mouse click enables inspection and selects the oldest item")
toggle.__scripts.OnClick(toggle)
check(not CL.db.keyboardInspect and not CleanLootInspectionTooltip:IsShown()
    and K.SelectedID() == 1001 and toggle.label:GetText() == "Inspect: Off", "mouse click disables inspection without clearing selection")
CL.Options.widgets.inspectLeft.__scripts.OnClick(CL.Options.widgets.inspectLeft)
check(toggle:IsShown() and (toggle:GetPoint()) == "BOTTOMRIGHT", "button remains accessible on the inspection side while the tooltip is hidden")
CL.Options.widgets.inspectRight.__scripts.OnClick(CL.Options.widgets.inspectRight)
K.SetEnabled(false)
check(not toggle:IsShown(), "disabling keyboard rolls hides the inspection button")
K.SetEnabled(true)

SlashCmdList.CLEANLOOT("need")
check(K.SelectedID() == 1001 and #rolls == 0 and a.selection:IsShown(), "first roll action selects oldest without rolling")
check(a.buttons[CL.ROLL.NEED].binding:IsShown() and a.buttons[CL.ROLL.NEED].binding:GetText() == "key:1"
    and a.buttons[CL.ROLL.GREED].binding:GetText() == "key:SHIFT-2"
    and a.buttons[CL.ROLL.PASS].binding:GetText() == "key:ALT-3", "selected roll shows the formatted roll bindings")
check((a.buttons[CL.ROLL.NEED].label:GetPoint()) == "TOP", "binding hints leave room for the button label")
check(not b.buttons[CL.ROLL.NEED].binding:IsShown(), "unselected rolls do not show bindings")
SlashCmdList.CLEANLOOT("next")
check(K.SelectedID() == 1002 and not a.selection:IsShown() and b.selection:IsShown(), "next selects the next item")
check(not a.buttons[CL.ROLL.NEED].binding:IsShown() and b.buttons[CL.ROLL.NEED].binding:IsShown(),
    "binding hints follow selection")
WOW.bindings.CLEANLOOT_NEED = "CTRL-4"
WOW.FireEvent("UPDATE_BINDINGS")
check(b.buttons[CL.ROLL.NEED].binding:GetText() == "key:CTRL-4", "changed bindings update immediately")
WOW.bindings.CLEANLOOT_NEED = nil
WOW.FireEvent("UPDATE_BINDINGS")
check(not b.buttons[CL.ROLL.NEED].binding:IsShown(), "unbound actions do not show a hint")
WOW.bindings.CLEANLOOT_NEED = "1"
WOW.FireEvent("UPDATE_BINDINGS")
local formatBinding = GetBindingText
GetBindingText = nil
WOW.FireEvent("UPDATE_BINDINGS")
check(b.buttons[CL.ROLL.NEED].binding:GetText() == "1", "raw key is shown when binding text formatting is unavailable")
GetBindingText = formatBinding
WOW.bindings.CLEANLOOT_GREED = "CTRL-SHIFT-LONGKEY"
WOW.FireEvent("UPDATE_BINDINGS")
local _, bindingSize = b.buttons[CL.ROLL.GREED].binding:GetFont()
check(bindingSize < 9 and bindingSize >= 6 and b.buttons[CL.ROLL.GREED].binding:GetWidth() == 48,
    "long bindings are reduced to fit beside vote counters")
WOW.bindings.CLEANLOOT_GREED = "SHIFT-2"
WOW.FireEvent("UPDATE_BINDINGS")
SlashCmdList.CLEANLOOT("next")
check(K.SelectedID() == 1001, "next wraps")
CleanLootKeyboardAction("previous")
check(K.SelectedID() == 1002, "previous binding wraps")
local c = start(1003)
check(K.SelectedID() == 1002 and b.selection:IsShown(), "new item does not steal selection")
RF.Stop(1001)
check(K.SelectedID() == 1002, "removing an earlier item preserves selection")
RF.Stop(1002)
check(K.SelectedID() == 1003 and c.selection:IsShown(), "selected removal advances to the following item")

SlashCmdList.CLEANLOOT("inspect")
local tip = CleanLootInspectionTooltip
check(CL.db.keyboardInspect and tip and tip:IsShown() and tip.link == c.link, "inspect shows a separate tooltip for the selection")
check(toggle.label:GetText() == "Inspect: On", "slash inspection updates the button state")
check(tip ~= GameTooltip, "inspection uses a separate tooltip")
check(not table.concat(tip.lines, " "):find("Need", 1, true)
    and not table.concat(tip.lines, " "):find("Greed", 1, true)
    and not table.concat(tip.lines, " "):find("Pass", 1, true), "inspection omits roll choices")
GameTooltip:SetOwner(c.icon, "ANCHOR_RIGHT")
GameTooltip:SetText("Mouseover")
GameTooltip:Show()
GameTooltip:Hide()
check(tip:IsShown() and tip.link == c.link, "mouseover does not replace or hide inspection")
local pawnCalls = {}
function PawnUpdateTooltip(name, method, link)
    pawnCalls[#pawnCalls + 1] = { name, method, link }
    _G[name]:AddLine("Pawn upgrade")
end
SlashCmdList.CLEANLOOT("next")
check(#pawnCalls == 1 and pawnCalls[1][1] == "CleanLootInspectionTooltip"
    and pawnCalls[1][2] == "SetHyperlink" and pawnCalls[1][3] == c.link,
    "Pawn receives the inspection tooltip and selected item link")
check(table.concat(tip.lines, " "):find("Pawn upgrade", 1, true), "Pawn can add upgrade information to inspection")
SlashCmdList.CLEANLOOT("next")
local pawnLines = 0
for _, line in ipairs(tip.lines) do if line == "Pawn upgrade" then pawnLines = pawnLines + 1 end end
check(#pawnCalls == 2 and pawnLines == 1, "refreshing inspection does not duplicate Pawn lines")
PawnUpdateTooltip = function() error("Pawn unavailable") end
SlashCmdList.CLEANLOOT("next")
check(K.SelectedID() == 1003 and tip:IsShown() and tip.link == c.link,
    "Pawn errors leave inspection usable")
PawnUpdateTooltip = nil
CL.Options.widgets.inspectLeft.__scripts.OnClick(CL.Options.widgets.inspectLeft)
check(CL.db.keyboardInspectSide == "LEFT" and (tip:GetPoint()) == "TOPRIGHT", "inspection side can be set to left")
local buttonPoint, buttonAnchor, buttonRelative, buttonX = toggle:GetPoint()
local _, tipAnchor, tipRelative, tipX = tip:GetPoint()
check(buttonPoint == "BOTTOMRIGHT" and buttonAnchor == tipAnchor and buttonRelative == tipRelative and buttonX == tipX,
    "inspection button follows the left-hand tooltip anchor")
CL.Options.widgets.inspectRight.__scripts.OnClick(CL.Options.widgets.inspectRight)
check(CL.db.keyboardInspectSide == "RIGHT" and (tip:GetPoint()) == "TOPLEFT", "inspection side can be set to right")
buttonPoint, buttonAnchor, buttonRelative, buttonX = toggle:GetPoint()
_, tipAnchor, tipRelative, tipX = tip:GetPoint()
check(buttonPoint == "BOTTOMLEFT" and buttonAnchor == tipAnchor and buttonRelative == tipRelative and buttonX == tipX,
    "inspection button follows the right-hand tooltip anchor")
RF.Stop(1003)
check(K.SelectedID() == nil and not tip:IsShown() and not toggle:IsShown() and CL.db.keyboardInspect,
    "empty stack hides inspection and its button without changing the toggle")
local d = start(1004, info(false, false))
check(K.SelectedID() == 1004 and tip:IsShown() and d.selection:IsShown()
    and toggle:IsShown() and toggle.label:GetText() == "Inspect: On", "enabled inspection and its button return with the next item")
check(not d.buttons[CL.ROLL.NEED].binding:IsShown() and d.buttons[CL.ROLL.GREED].binding:IsShown(),
    "unavailable roll choices have no key hint")
WOW.chat = {}
SlashCmdList.CLEANLOOT("need")
check(#rolls == 0 and RF.GetFrame(1004) == d and K.SelectedID() == 1004
    and table.concat(WOW.chat, " "):find("Cannot Need this.", 1, true),
    "unavailable choice explains the reason and leaves selection intact")

local realRoll = CL.API.Roll
CL.API.Roll = function() return false end
WOW.chat = {}
SlashCmdList.CLEANLOOT("greed")
check(RF.GetFrame(1004) == d and K.SelectedID() == 1004 and #WOW.chat > 0, "an explicit roll failure reports and keeps the item selected")
CL.API.Roll = realRoll
SlashCmdList.CLEANLOOT("greed")
check(#rolls == 1 and rolls[1][1] == 1004 and rolls[1][2] == CL.ROLL.GREED and not RF.GetFrame(1004), "successful Greed rolls and closes the selected item")
check(CL.db.keyboardInspect and not tip:IsShown(), "inspection remains enabled after the last roll")

local bop = start(1005, info(true))
start(1006)
WOW.lootPopup = true
SlashCmdList.CLEANLOOT("need")
check(#rolls == 1 and RF.GetFrame(1005) == bop, "an open loot confirmation blocks roll commands")
WOW.lootPopup = false
local popupFinder = StaticPopup_FindVisible
StaticPopup_FindVisible = false
StaticPopup1 = CreateFrame("Frame", "StaticPopup1", UIParent)
StaticPopup1.which = "CONFIRM_LOOT_ROLL"
StaticPopup1:Show()
SlashCmdList.CLEANLOOT("need")
check(#rolls == 1 and RF.GetFrame(1005) == bop, "visible loot confirmation is detected without the finder API")
StaticPopup1:Hide()
StaticPopup_FindVisible = popupFinder
SlashCmdList.CLEANLOOT("need")
check(#rolls == 2 and RF.GetFrame(1005) == bop and K.SelectedID() == 1005, "bind-on-pickup Need stays selected pending confirmation")
WOW.lootPopup = true
SlashCmdList.CLEANLOOT("next")
SlashCmdList.CLEANLOOT("pass")
check(#rolls == 2 and K.SelectedID() == 1006, "confirmation blocks rolling even after navigating")
WOW.lootPopup = false
SlashCmdList.CLEANLOOT("previous")
check(K.SelectedID() == 1005 and RF.GetFrame(1005), "declining confirmation leaves the original roll available")
SlashCmdList.CLEANLOOT("need")
WOW.FireEvent("CANCEL_LOOT_ROLL", 1005)
check(K.SelectedID() == 1006 and RF.GetFrame(1005) == nil, "resolved confirmation advances on the client cancellation event")
RF.StopAll()

start(1007, info(true))
SlashCmdList.CLEANLOOT("pass")
check(RF.GetFrame(1007) == nil, "passing on a bind-on-pickup item needs no confirmation")
local fake = CL.Sim.Start(1)[1]
CL.Sim.GetRoll(fake).info.bop = true
RF.GetFrame(fake).bop = true
SlashCmdList.CLEANLOOT("greed")
check(RF.GetFrame(fake) == nil, "simulated bind-on-pickup rolls do not wait for a real confirmation")
CL.Sim.Clear()

for id = 1101, 1109 do start(id) end
check(RF.ActiveCount() == 8 and RF.QueuedCount() == 1 and K.SelectedID() == 1101, "inspection selects from visible rolls only")
for i = 1, 8 do SlashCmdList.CLEANLOOT("next") end
check(K.SelectedID() == 1101, "cycling does not select the hidden queue")
local reused = RF.GetFrame(1101)
RF.Stop(1101)
check(RF.GetFrame(1109) == reused and K.SelectedID() == 1102, "frame reuse promotes the queue without selecting the wrong item")
RF.Stop(1102)
check(K.SelectedID() == 1103, "selection continues in queue order")
K.SetEnabled(false)
check(K.SelectedID() == nil and not tip:IsShown() and not toggle:IsShown() and CL.db.keyboardInspect,
    "disabling clears selection and the button but remembers inspection")
check(not RF.GetFrame(1103).buttons[CL.ROLL.NEED].binding:IsShown()
    and (RF.GetFrame(1103).buttons[CL.ROLL.NEED].label:GetPoint()) == "CENTER", "disabling restores the plain button layout")
K.SetEnabled(true)
check(K.SelectedID() == 1103 and tip:IsShown() and toggle:IsShown(), "re-enabling restores inspection, its button and selection")
SlashCmdList.CLEANLOOT("inspect")
check(not tip:IsShown() and not CL.db.keyboardInspect and K.SelectedID() == 1103, "inspect toggle hides the area but preserves selection")
RF.StopAll()

local noLink = RF.Start(1201, info(), nil, 60000)
local missingLinkCalls = 0
PawnUpdateTooltip = function() missingLinkCalls = missingLinkCalls + 1 end
SlashCmdList.CLEANLOOT("inspect")
check(K.SelectedID() == 1201 and tip:IsShown() and tip.lines[1] == "Test Item", "inspection falls back to the item name without a link")
check(missingLinkCalls == 0, "Pawn is not called without an item link")
PawnUpdateTooltip = nil
RollOnLoot = function() error("client rejected call") end
WOW.chat = {}
SlashCmdList.CLEANLOOT("need")
check(RF.GetFrame(1201) == noLink and K.SelectedID() == 1201 and #WOW.chat > 0, "client API errors are reported without removing the roll")
RollOnLoot = function(id) WOW.FireEvent("CANCEL_LOOT_ROLL", id) end
start(1202)
SlashCmdList.CLEANLOOT("pass")
check(RF.GetFrame(1201) == nil and K.SelectedID() == 1202, "synchronous cancellation cannot close the next selected roll")
WOW.Advance(63)
check(RF.GetFrame(1202) == nil and K.SelectedID() == nil and not tip:IsShown() and CL.db.keyboardInspect,
    "timer expiry clears selection while preserving the inspection toggle")

io.write(("%d checks, %d failed\n"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
