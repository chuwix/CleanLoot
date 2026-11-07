-- End-to-end scenarios for the Forever core, run against the stub harness.
--   lua tools/test_forever.lua      (from the repo root)
-- Checks logic only (frames/timers/events/rolls); looks need the real client.

math.randomseed(42)
local WOW = dofile("tools/wowenv.lua")
local CL = WOW.CL
local RF = CL.RollFrames

local failures, checks = 0, 0
local function check(cond, label)
    checks = checks + 1
    if not cond then
        failures = failures + 1
        io.write("FAIL: " .. label .. "\n")
    end
end

local function click(rollID, rollType)
    local f = RF.GetFrame(rollID)
    local b = f.buttons[rollType]
    b.__scripts.OnMouseDown(b)
    b.__scripts.OnClick(b, "LeftButton")
end

-- 1. Defaults were applied on ADDON_LOADED
check(CL.db and CL.db.growDirection == "DOWN" and CL.db.frameScale == 1.10, "defaults applied (scale 1.10)")
check(CL.DEFAULT_SCALE == 1.10, "the default scale constant is 1.10")

local setupErrors = {}
for _, line in ipairs(WOW.chat) do setupErrors[#setupErrors + 1] = line end
check(#setupErrors == 0, "no module failed to set up (" .. table.concat(setupErrors, " | ") .. ")")

-- 2. Simulating two drops opens two frames, with real item data
CL.Sim.Start(2)
check(RF.ActiveCount() == 2, "sim start opens 2 frames (got " .. RF.ActiveCount() .. ")")
check(CL.Sim.ActiveCount() == 2, "sim tracks 2 rolls")

local ids = {}
for rollID = 900001, 900002 do ids[#ids + 1] = rollID end
local f1 = RF.GetFrame(ids[1])
check(f1 and f1:IsShown(), "first roll frame is shown")
check(f1.name:GetText():match("^Item%d+$") ~= nil, "frame shows the item name")
check(not f1.buttons[CL.ROLL.PASS].unavailable, "Pass is always available")

-- 3. Clicking Need rolls through the API and closes that frame immediately
click(ids[1], CL.ROLL.NEED)
check(CL.Sim.GetRoll(ids[1]).mine == CL.ROLL.NEED, "click recorded as Need on the sim roll")
check(RF.ActiveCount() == 1, "rolled frame closes (got " .. RF.ActiveCount() .. ")")
check(RF.GetFrame(ids[1]) == nil, "rolled frame is released")

-- 4. The other players resolve and the roll ends
WOW.Advance(4)
check(CL.Sim.GetRoll(ids[1]) == nil, "sim roll resolves after others choose")

-- 5. An unanswered roll still ends when its timer does
check(RF.ActiveCount() == 1, "unanswered roll still has a frame")
WOW.Advance(31)
check(RF.ActiveCount() == 0, "unanswered roll ends at timeout (got " .. RF.ActiveCount() .. ")")
check(CL.Sim.ActiveCount() == 0, "no simulated rolls left")

local N, G, P = CL.ROLL.NEED, CL.ROLL.GREED, CL.ROLL.PASS

-- 7. Real-event path: START_LOOT_ROLL / CANCEL_LOOT_ROLL through the real API
function GetLootRollItemInfo(rollID)
    -- texture, name, count, quality, bop, canNeed, canGreed, canDE, reasonNeed, reasonGreed
    return 135000, "Real Item", 1, 4, false, false, true, false, 3, nil
end
function GetLootRollItemLink(rollID) return "|cffa335ee|Hitem:12345::::::::|h[Real Item]|h|r" end
local rolled = {}
function RollOnLoot(rollID, rollType) rolled[#rolled + 1] = { rollID, rollType } end

WOW.FireEvent("START_LOOT_ROLL", 5001, 20000)
check(RF.ActiveCount() == 1 and RF.GetFrame(5001), "START_LOOT_ROLL opens a frame")
local rf = RF.GetFrame(5001)
check(rf.buttons[N].unavailable, "Need unavailable when the client says canNeed=false")
check(not rf.buttons[G].unavailable, "Greed available")
check(rf.buttons[N]:IsEnabled(), "an unavailable button stays enabled so mouse-over still works")
check(rf.reasonNeed == 3, "ineligibility reason kept for the tooltip")
LOOT_ROLL_INELIGIBLE_REASON3 = "Cannot Need this."
local needBtn = rf.buttons[N]
needBtn.__scripts.OnEnter(needBtn)
check(GameTooltip.lines[#GameTooltip.lines] == "Cannot Need this.", "a greyed-out Need explains why")
needBtn.__scripts.OnLeave(needBtn)

click(5001, G)
check(#rolled == 1 and rolled[1][1] == 5001 and rolled[1][2] == G, "click calls the real RollOnLoot(5001, Greed)")
check(RF.ActiveCount() == 0, "frame closes after a real roll")

WOW.FireEvent("START_LOOT_ROLL", 5002, 20000)
WOW.FireEvent("CANCEL_LOOT_ROLL", 5002)
check(RF.ActiveCount() == 0, "CANCEL_LOOT_ROLL closes the frame")

-- 8. The mouse-down snapshot: a click that straddles a frame reuse must not
--    vote on the new item
WOW.FireEvent("START_LOOT_ROLL", 6001, 20000)
local fa = RF.GetFrame(6001)
local btn = fa.buttons[G]
btn.__scripts.OnMouseDown(btn)            -- player presses on item 6001...
WOW.FireEvent("CANCEL_LOOT_ROLL", 6001)   -- ...its roll ends and the frame frees up...
WOW.FireEvent("START_LOOT_ROLL", 6002, 20000)  -- ...and is reused for a new item
check(RF.GetFrame(6002) == fa, "frame was reused for the new roll")
rolled = {}
btn.__scripts.OnClick(btn, "LeftButton")  -- ...then releases
check(#rolled == 1 and rolled[1][1] == 6001, "click still targets the item pressed, not the new one")
WOW.FireEvent("CANCEL_LOOT_ROLL", 6002)

-- 9. Stack order and direction
WOW.FireEvent("START_LOOT_ROLL", 7001, 20000)
WOW.FireEvent("START_LOOT_ROLL", 7002, 20000)
local a, b = RF.GetFrame(7001), RF.GetFrame(7002)
local pa, _, _, _, _ = a:GetPoint()
local pb = b:GetPoint()
check(pa == "TOPLEFT" and pb == "TOPLEFT", "DOWN: frames anchor from their top-left")
CL.db.growDirection = "UP"
RF.Layout()
check((a:GetPoint()) == "BOTTOMLEFT" and (b:GetPoint()) == "BOTTOMLEFT", "UP: frames anchor from their bottom-left")
RF.StopAll()
check(RF.ActiveCount() == 0, "StopAll empties the stack")

-- 10. Simulator item pool: owned items are used, ids the client cannot describe
--     are skipped without breaking the run (14551 was unknown on the beta)
check(CL.Sim.StartItem(99999) == nil, "an item the client does not know starts no roll")
check(RF.ActiveCount() == 0, "...and opens no frame")

WOW.items[777] = { name = "Owned Sword", quality = 3, icon = 200777 }
WOW.equipped[16] = 777
WOW.bags[0] = { 888, 777 }  -- 888: not cached, must be filtered out
CL.Sim.Start(8)
check(RF.ActiveCount() == 8, "Start(8) opens 8 frames even with an unknown id in the bags (got " .. RF.ActiveCount() .. ")")
CL.Sim.Clear()
check(RF.ActiveCount() == 0 and CL.Sim.ActiveCount() == 0, "Sim.Clear removes every simulated roll and frame")

-- 11. /cll sim colors: one drop per quality, common to legendary
local function qualitiesOf(ids)
    local q = {}
    for _, id in ipairs(ids) do q[#q + 1] = RF.GetFrame(id).quality end
    table.sort(q)
    return table.concat(q, ",")
end

local ids = CL.Sim.Colors()
check(#ids == 5 and RF.ActiveCount() == 5, "Colors opens 5 frames")
check(qualitiesOf(ids) == "1,2,3,4,5", "Colors covers every quality (got " .. qualitiesOf(ids) .. ")")
CL.Sim.Clear()

-- 12. Nothing the client can describe: synthetic items still cover every colour,
--     with no hyperlink (tooltip falls back to name + colour) and clean chat text
local saved = WOW.items
WOW.items, WOW.equipped, WOW.bags = {}, {}, {}
ids = CL.Sim.Colors()
check(#ids == 5 and qualitiesOf(ids) == "1,2,3,4,5", "synthetic items cover every colour")
local legendary
for _, id in ipairs(ids) do
    local fr = RF.GetFrame(id)
    check(fr.link == nil and fr.name:GetText():match("^Sim ") ~= nil, "synthetic item has no hyperlink and a Sim name")
    if fr.quality == 5 then legendary = id end
end
check(legendary and RF.GetFrame(legendary).name:GetText():find("Legendary", 1, true) ~= nil, "legendary synthetic exists")
WOW.chat = {}
click(ids[1], CL.ROLL.GREED)
check(#WOW.chat == 0, "the simulator is silent in chat (the game prints its own lines)")
click(legendary, CL.ROLL.GREED)
CL.Sim.Clear()
check(#CL.Sim.Start(2) == 2 and RF.ActiveCount() == 2, "Start(2) works with no item data at all")
CL.Sim.Clear()
WOW.items = saved

-- 13. Vote counters and the who-chose-what tooltip
local vid = CL.Sim.Start(1)[1]
local vf = RF.GetFrame(vid)
local function countText(rollType) return tostring(vf.buttons[rollType].count:GetText()) end
check(countText(N) == "" and countText(G) == "" and countText(P) == "", "no votes yet: every counter is empty")

CL.Sim.Vote(vid, "Aludra", N)
CL.Sim.Vote(vid, "Baric", N)
CL.Sim.Vote(vid, "Cyndra", G)
CL.Sim.Vote(vid, "Dorun", P)
check(countText(N) == "2" and countText(G) == "1" and countText(P) == "1", "counters show 2 Need, 1 Greed, 1 Pass")
check(CL.Sim.Vote(vid, "Aludra", G) == false, "a player cannot vote twice")
check(countText(N) == "2" and countText(G) == "1", "...and the counters are unchanged")

local nb = vf.buttons[N]
nb.__scripts.OnEnter(nb)
check(GameTooltip.lines[1] == "Need (2)", "tooltip title counts the voters (got " .. tostring(GameTooltip.lines[1]) .. ")")
check(GameTooltip.lines[2] == "Aludra" and GameTooltip.lines[3] == "Baric", "tooltip lists the voters in vote order")
nb.__scripts.OnLeave(nb)
GameTooltip:Hide()

-- the 4 fake players have all voted; a hover on a type nobody chose shows nothing
GameTooltip.lines = {}
local gb = vf.buttons[G]
gb.__scripts.OnEnter(gb)
check(GameTooltip.lines[1] == "Greed (1)" and GameTooltip.lines[2] == "Cyndra", "Greed tooltip lists Cyndra")
GameTooltip:Hide()

-- an open tooltip follows new votes as they arrive
WOW.items[777] = WOW.items[777] or { name = "Owned Sword", quality = 3, icon = 200777 }
CL.Sim.SetGroupSize(6)
local vid2 = CL.Sim.Start(1)[1]
local vf2 = RF.GetFrame(vid2)
local nb2 = vf2.buttons[N]
CL.Sim.Vote(vid2, "Aludra", N)
nb2.__scripts.OnEnter(nb2)
GameTooltip:Show()
CL.Sim.Vote(vid2, "Baric", N)
check(GameTooltip.lines[1] == "Need (2)", "an open tooltip follows new votes (got " .. tostring(GameTooltip.lines[1]) .. ")")
GameTooltip:Hide()

CL.Sim.Clear()

-- 13b. Greyed-out (unavailable) buttons: the voter list still shows on hover,
--      followed by why the roll type is unavailable; clicks do nothing
local realGetVotes = CL.API.GetVotes
CL.API.GetVotes = function()
    return { [N] = { { name = "Aludra" }, { name = "You" } }, [G] = {}, [P] = {} }
end
rolled = {}
WOW.FireEvent("START_LOOT_ROLL", 5003, 20000)   -- stub says canNeed=false, reasonNeed=3
local gf = RF.GetFrame(5003)
local gneed = gf.buttons[N]
check(gneed.unavailable, "Need is greyed out on this roll")
check(gneed.count:GetText() == 2, "greyed-out Need still shows its vote count")
gneed.__scripts.OnEnter(gneed)
check(GameTooltip.lines[1] == "Need (2)" and GameTooltip.lines[2] == "Aludra" and GameTooltip.lines[3] == "You",
    "hovering a greyed-out button lists who voted")
check(GameTooltip.lines[#GameTooltip.lines] == "Cannot Need this.", "...then says why it is unavailable")
gneed.__scripts.OnLeave(gneed)
GameTooltip:Hide()
click(5003, N)
check(#rolled == 0 and RF.GetFrame(5003) ~= nil, "clicking a greyed-out button does nothing")
WOW.FireEvent("CANCEL_LOOT_ROLL", 5003)
CL.API.GetVotes = realGetVotes

-- 14. Group size and votes arriving over time
check(CL.Sim.SetGroupSize(100) == 39, "group size is clamped to 39 other players")
check(CL.Sim.SetGroupSize(0) == 1, "...and to at least 1")
check(CL.Sim.SetGroupSize(25) == 25, "group of 25 accepted")
local rid = CL.Sim.Start(1)[1]
local rframe = RF.GetFrame(rid)
WOW.Advance(21)  -- every scheduled vote falls before the 30s end
local total, seen, dup = 0, {}, false
for _, rt in ipairs({ N, G, P }) do
    local list = rframe.votes and rframe.votes[rt] or {}
    for _, v in ipairs(list) do
        total = total + 1
        if seen[v.name] then dup = true end
        seen[v.name] = true
    end
end
check(total >= 10 and total <= 25, "most of 25 players voted over time (got " .. total .. ")")
check(not dup, "no player is counted twice")
local counted = 0
for _, rt in ipairs({ N, G, P }) do counted = counted + (tonumber(rframe.buttons[rt].count:GetText()) or 0) end
check(counted == total, "the button counters add up to the votes (" .. counted .. " vs " .. total .. ")")
CL.Sim.SetGroupSize(4)
CL.Sim.Clear()

-- 15. Hiding Blizzard's roll frames: container alpha + roll button mouse only,
--     re-applied after Blizzard's own updates, never inside them
WOW.Advance(0.01)  -- let the deferred Native.Refresh run
local nbox = GroupLootFrame1.LootButtonContainer
check(GroupLootContainer:GetAlpha() == 0, "Blizzard's container is hidden by default")
check(nbox.NeedButton.__clickEnabled == false and nbox.NeedButton.__motionEnabled == false,
    "native roll buttons stop catching clicks and hover")
check(GroupLootFrame1.IconFrame.__clickEnabled == false, "...and the native icon too")

GroupLootContainer:SetAlpha(1)  -- Blizzard resets it during an update
GroupLootContainer_Update()
check(GroupLootContainer:GetAlpha() == 1, "nothing is written inside Blizzard's own call")
WOW.Advance(0.01)
check(GroupLootContainer:GetAlpha() == 0, "...it is re-hidden on the next frame")

check(GroupLootFrame1:GetAlpha() == 0 and GroupLootFrame2:GetAlpha() == 0,
    "each roll frame is hidden itself: they are not children of the container, its alpha does not reach them")

-- Blizzard's own animation puts a roll frame's alpha back: no hook fires, the
-- periodic check catches it
GroupLootFrame2:SetAlpha(1)
WOW.Advance(0.3)
check(GroupLootFrame2:GetAlpha() == 0, "a native frame that became visible again is hidden within a fraction of a second")

local pooled = CreateFrame("Frame")
pooled.IconFrame = CreateFrame("Button")
pooled.LootButtonContainer = { NeedButton = CreateFrame("Button") }
GroupLootContainer.rollFrames[5] = pooled
GroupLootContainer_AddFrame(GroupLootContainer, pooled)
check(pooled:GetAlpha() == 0, "a frame Blizzard adds is made invisible right away, no one-frame flash")
WOW.Advance(0.01)
check(pooled.LootButtonContainer.NeedButton.__clickEnabled == false, "frames only in the container's pool are handled too")

CL.Native.SetHidden(false)
WOW.Advance(0.01)
check(GroupLootContainer:GetAlpha() == 1 and nbox.NeedButton.__clickEnabled == true, "showing the natives restores everything")
check(GroupLootFrame1:GetAlpha() == 1 and pooled:GetAlpha() == 1, "...including each roll frame's alpha")
GroupLootContainer:SetAlpha(0.5)  -- another addon's business now
GroupLootContainer_Update()
WOW.Advance(0.01)
check(GroupLootContainer:GetAlpha() == 0.5, "frames are left alone while we are not hiding them")
CL.Native.SetHidden(true)
WOW.Advance(0.01)
check(GroupLootContainer:GetAlpha() == 0, "hiding the natives hides them again")

-- 15b. Every frame in a native roll frame's tree stops catching the mouse (an
--      invisible frame that still takes clicks blocks the world behind it), and
--      each frame gets back exactly the mouse state it had
local nbox1 = GroupLootFrame1.LootButtonContainer
local overlay = CreateFrame("Frame", nil, nbox1)      -- an extra container Blizzard might use
local catcher = CreateFrame("Frame", nil, overlay)    -- a deeper frame that takes the mouse
local quiet = CreateFrame("Frame", nil, overlay)
quiet:SetMouseClickEnabled(false)                     -- already off before we hid anything
GroupLootContainer_Update()
WOW.Advance(0.01)
check(overlay.__clickEnabled == false and catcher.__clickEnabled == false and catcher.__motionEnabled == false,
    "every frame in a native roll frame's tree stops catching the mouse, however deep")
check(GroupLootContainer.__clickEnabled == false, "...and the container itself")

catcher:SetMouseClickEnabled(true)                    -- Blizzard turns a state back on
WOW.Advance(1.1)
check(catcher.__clickEnabled == false, "a mouse state Blizzard re-enables is switched off again within about a second")

CL.Native.SetHidden(false)
WOW.Advance(0.01)
check(catcher.__clickEnabled == true and overlay.__clickEnabled == true and GroupLootContainer.__clickEnabled == true,
    "showing the natives: every frame gets its mouse back")
check(quiet.__clickEnabled == false, "...but a frame that never had the mouse on stays off")
CL.Native.SetHidden(true)
WOW.Advance(0.01)

-- 16. Real votes from C_LootHistory, keyed by START_LOOT_ROLL's loot handle
local KEY = 994704903
WOW.drops = {
    [KEY] = { lootListKey = KEY, rollInfos = {
        { isSelf = false, playerName = "Teki Moo", playerClass = "DRUID", state = 5 },
        { isSelf = true, playerName = "Hazas War", playerClass = "WARRIOR", state = 4 },
        { isSelf = false, playerName = "Hazas Hunt", playerClass = "HUNTER", state = 4 },
    } },
}
C_LootHistory = {
    GetAllEncounterInfos = function() return { { encounterID = 7 }, { encounterID = 0 } } end,
    GetSortedInfoForDrop = function(encounterID, key) if encounterID == 0 then return WOW.drops[key] end end,
}
function GetLootRollItemInfo()
    return 133378, "Band of Sulfuras", 1, 4, true, true, true, false, 0, 0, 3, -1, false
end
function GetLootRollItemLink() return "|cnIQ4:|Hitem:288929::::::::18:1491:::::::::|h[Band of Sulfuras]|h|r" end

WOW.FireEvent("START_LOOT_ROLL", 1, 180000, KEY)
local lf = RF.GetFrame(1)
local function lcount(rt) return tostring(lf.buttons[rt].count:GetText()) end
check(lcount(P) == "1" and lcount(N) == "" and lcount(G) == "", "real roll: one Pass counted from the history (Need '" .. lcount(N) .. "')")

check(lf.pendingFrame:IsShown() and tostring(lf.pendingCount:GetText()) == "1",
    "real roll: the clock counts the one player who has not chosen yet (you are not counted)")
lf.pendingFrame.__scripts.OnEnter(lf.pendingFrame)
check(GameTooltip.lines[1] == "Hasn't rolled yet (1)" and GameTooltip.lines[2] == "Hazas Hunt",
    "...and its tooltip names that player")
lf.pendingFrame.__scripts.OnLeave(lf.pendingFrame)
GameTooltip:Hide()

WOW.drops[KEY].rollInfos[3].state = 1  -- Hazas Hunt picks Need (off spec)
WOW.FireEvent("LOOT_HISTORY_UPDATE_DROP", 0, KEY)
check(lcount(N) == "1" and lcount(P) == "1", "LOOT_HISTORY_UPDATE_DROP refreshes the counters")
check(not lf.pendingFrame:IsShown(), "once nobody is left deciding, the clock disappears")

WOW.drops[KEY].rollInfos[2].state = 3  -- you pick Greed
WOW.drops[KEY].rollInfos[2].roll = 92
WOW.FireEvent("LOOT_HISTORY_UPDATE_DROP", 0, KEY)
local lgb = lf.buttons[G]
lgb.__scripts.OnEnter(lgb)
check(GameTooltip.lines[1] == "Greed (1)" and GameTooltip.lines[2] == "You | 92", "your own entry reads 'You' with its roll value")
lgb.__scripts.OnLeave(lgb)
GameTooltip:Hide()

local lnb = lf.buttons[N]
lnb.__scripts.OnEnter(lnb)
check(GameTooltip.lines[2] == "Hazas Hunt", "other players show under their own name")
lnb.__scripts.OnLeave(lnb)
GameTooltip:Hide()

-- secret values (unreadable in some contexts) must not error nor be miscounted
local realSecret = issecretvalue
issecretvalue = function(v) return v == "SECRET" end
WOW.drops[KEY].rollInfos[#WOW.drops[KEY].rollInfos + 1] = { playerName = "SECRET", playerClass = "DRUID", state = 3 }
WOW.drops[KEY].rollInfos[#WOW.drops[KEY].rollInfos + 1] = { playerName = "Hidden State", state = "SECRET" }
WOW.FireEvent("LOOT_HISTORY_UPDATE_DROP", 0, KEY)
check(lcount(G) == "2", "a secret name still counts as a vote, shown as '?' (Greed '" .. lcount(G) .. "')")
check(lcount(N) == "1" and lcount(P) == "1", "a secret state is skipped, other counts unchanged")
issecretvalue = realSecret

WOW.FireEvent("LOOT_HISTORY_UPDATE_DROP", 0, 123456)  -- not one of our rolls
WOW.FireEvent("CANCEL_LOOT_ROLL", 1)
check(RF.GetFrame(1) == nil, "the real roll's frame is gone")
WOW.FireEvent("LOOT_HISTORY_UPDATE_DROP", 0, KEY)     -- late update for a finished roll: ignored
check(true, "updates for finished or foreign drops are ignored without error")

-- 17. Minimap button (LibDataBroker launcher registered through LibDBIcon)
local reg = WOW.dbicon.registered["CleanLoot"]
check(reg ~= nil, "the minimap button is registered with LibDBIcon")
check(reg and reg.db == CL.db.minimap and CL.db.minimap.hide == false, "...with the saved minimap settings (visible by default)")
local obj = reg.obj
check(obj.type == "launcher", "it is a launcher data object")

local lines = {}
obj.OnTooltipShow({ AddLine = function(_, t) lines[#lines + 1] = t end })
check(lines[1] == "CleanLoot v1.0.0-test", "tooltip shows the addon version (got " .. tostring(lines[1]) .. ")")

WOW.shift = false
obj.OnClick(nil, "LeftButton")
check(GroupLootHistoryFrame:IsShown(), "left-click opens Blizzard's loot history")
obj.OnClick(nil, "LeftButton")
check(not GroupLootHistoryFrame:IsShown(), "left-click again closes it")

obj.OnClick(nil, "RightButton")
check(WOW.openedCategory == 99, "right-click opens the options panel")

WOW.shift = true
obj.OnClick(nil, "LeftButton")
check(CL.Sim.ActiveCount() == 3, "shift-click simulates 3 drops")
WOW.shift = false
CL.Sim.Clear()

CL.MinimapButton.SetHidden(true)
check(CL.db.minimap.hide == true and WOW.dbicon.hidden["CleanLoot"] == true, "hiding the button saves the choice and hides it")
CL.MinimapButton.SetHidden(false)
check(CL.db.minimap.hide == false and WOW.dbicon.hidden["CleanLoot"] == false, "...and showing it again works")

-- 18. Options panel in the game's AddOns settings
check(WOW.category and WOW.category.name == "CleanLoot" and WOW.registeredCategory == WOW.category,
    "an AddOns settings category 'CleanLoot' is registered")
check(WOW.category.panel == CL.Options.panel, "...and it is our panel")

local W = CL.Options.widgets
CL.db.growDirection = "DOWN"  -- an earlier scenario left it on UP
CL.Options.Refresh()
check(W.down:GetChecked() == true and W.up:GetChecked() == false, "direction DOWN: Downwards is the ticked box")
W.up.__scripts.OnClick(W.up)
W.up:SetChecked(true)
check(CL.db.growDirection == "UP", "ticking Upwards saves the direction")
check(W.up:GetChecked() == true and W.down:GetChecked() == false, "...and the two boxes behave like radio buttons")
W.down.__scripts.OnClick(W.down)
check(CL.db.growDirection == "DOWN", "ticking Downwards goes back")

-- a slash command changes a value while the panel is closed: opening it shows the truth
CL.db.growDirection = "UP"
CL.Options.panel.__scripts.OnShow(CL.Options.panel)
check(W.up:GetChecked() == true and W.down:GetChecked() == false, "the panel re-reads the saved values when shown")
CL.db.growDirection = "DOWN"

W.scale.__scripts.OnValueChanged(W.scale, 1.234)
check(CL.db.frameScale == 1.25, "the scale slider snaps to its 0.05 step (got " .. tostring(CL.db.frameScale) .. ")")
W.scale.__scripts.OnValueChanged(W.scale, 0.97)
check(CL.db.frameScale == 0.95, "...(0.97 -> 0.95)")
CL.db.frameScale = CL.DEFAULT_SCALE

W.native:SetChecked(false)
W.native.__scripts.OnClick(W.native)
WOW.Advance(0.01)
check(CL.db.hideNative == false and GroupLootContainer:GetAlpha() == 1, "unticking 'Hide Blizzard's roll frames' shows them again")
W.native:SetChecked(true)
W.native.__scripts.OnClick(W.native)
WOW.Advance(0.01)
check(CL.db.hideNative == true and GroupLootContainer:GetAlpha() == 0, "ticking it hides them again")

W.minimap:SetChecked(true)
W.minimap.__scripts.OnClick(W.minimap)
check(CL.db.minimap.hide == true and WOW.dbicon.hidden["CleanLoot"] == true, "'Hide the minimap button' hides it")
W.minimap:SetChecked(false)
W.minimap.__scripts.OnClick(W.minimap)
check(CL.db.minimap.hide == false, "...and unticking shows it")

CL.db.point = { "TOPLEFT", "TOPLEFT", 10, -10 }
W.reset.__scripts.OnClick(W.reset)
check(CL.db.point == nil, "Reset position forgets the saved position")

W.sim.__scripts.OnClick(W.sim)
check(CL.Sim.ActiveCount() == 3, "the 'Simulate 3 drops' button works")
W.simClear.__scripts.OnClick(W.simClear)
check(CL.Sim.ActiveCount() == 0 and RF.ActiveCount() == 0, "the 'Clear' button removes them")
W.simColors.__scripts.OnClick(W.simColors)
check(CL.Sim.ActiveCount() == 5, "the 'One of each colour' button works")
CL.Sim.Clear()

CL.Options.Open()
check(WOW.openedCategory == 99, "Options.Open() opens the registered category")
WOW.openedCategory = nil
WOW.combat = true
CL.Options.Open()
check(WOW.openedCategory == nil, "the options do not open during combat")
WOW.combat = false

-- 19. Chat spam filter: the roll lines go, your own win and the loot receipt stay
local hide = WOW.chatFilters["CHAT_MSG_LOOT"]
check(hide ~= nil, "a CHAT_MSG_LOOT filter is registered")
local itemLink = "|cnIQ4:|Hitem:288874::::::::18:1491:::::::::|h[Giantstalker's Epaulets]|h|r"
local function filtered(msg) return hide(nil, "CHAT_MSG_LOOT", msg) end
check(filtered("|HlootHistory:123|h[Loot]|h: Plague Dancer has selected Greed for: " .. itemLink) == true, "someone choosing Greed is hidden")
check(filtered("|HlootHistory:124|h[Loot]|h: Shmrgn Daseer has selected Need for: " .. itemLink) == true, "someone choosing Need is hidden")
check(filtered("|HlootHistory:125|h[Loot]|h: Vash Skystrike passed on: " .. itemLink) == true, "someone passing is hidden")
check(filtered("|HlootHistory:126|h[Loot]|h: You have selected Need for: " .. itemLink) == true, "your own Need choice is hidden")
check(filtered("|HlootHistory:126|h[Loot]|h: You have selected Greed for: " .. itemLink) == true, "your own Greed choice is hidden")
check(filtered("|HlootHistory:126|h[Loot]|h: You passed on: " .. itemLink) == true, "your own Pass is hidden")
check(filtered("|HlootHistory:127|h[Loot]|h: Need Roll - 52 for " .. itemLink .. " by Nong Shim") == true, "a Need roll value is hidden")
check(filtered("|HlootHistory:127|h[Loot]|h: Greed Roll - 7 for " .. itemLink .. " by Nong Shim") == true, "a Greed roll value is hidden")
check(filtered("|HlootHistory:128|h[Loot]|h: Token Dat won: " .. itemLink) == false, "who won what stays visible: someone else's win")
check(filtered("|HlootHistory:128|h[Loot]|h: You won: " .. itemLink) == false, "...and your own win")
check(filtered("You receive loot: " .. itemLink) == false, "the loot receipt stays visible")
check(filtered("Bob receives loot: " .. itemLink) == false, "other players' loot receipts are not touched")
check(filtered(nil) == false, "a missing message is left alone")

local realSecretFn = issecretvalue
issecretvalue = function(v) return v == "SECRET LINE" end
check(filtered("SECRET LINE") == false, "a secret (unreadable) message is passed through, never errors")
issecretvalue = realSecretFn

CL.db.hideRollSpam = false
check(filtered("|HlootHistory:123|h[Loot]|h: Plague Dancer has selected Greed for: " .. itemLink) == false, "with the option off nothing is hidden")
CL.db.hideRollSpam = true
check(CL.db.hideRollSpam == true, "the option is on by default")

local cw = CL.Options.widgets
cw.chat:SetChecked(false)
cw.chat.__scripts.OnClick(cw.chat)
check(CL.db.hideRollSpam == false, "the options checkbox turns the filter off")
cw.chat:SetChecked(true)
cw.chat.__scripts.OnClick(cw.chat)
check(CL.db.hideRollSpam == true, "...and back on")

-- 20. The "hasn't rolled yet" clock on simulated rolls
CL.Sim.SetGroupSize(4)
local pid = CL.Sim.Start(1)[1]
local pf = RF.GetFrame(pid)
check(pf.pendingFrame:IsShown() and tostring(pf.pendingCount:GetText()) == "4", "everyone is still deciding: the clock shows 4")
pf.pendingFrame.__scripts.OnEnter(pf.pendingFrame)
check(GameTooltip.lines[1] == "Hasn't rolled yet (4)" and GameTooltip.lines[2] == "Aludra", "its tooltip lists who is still deciding")
GameTooltip:Show()
CL.Sim.Vote(pid, "Aludra", N)
check(tostring(pf.pendingCount:GetText()) == "3", "a player choosing lowers the count")
check(GameTooltip.lines[1] == "Hasn't rolled yet (3)" and GameTooltip.lines[2] == "Baric", "an open tooltip follows it")
CL.Sim.Vote(pid, "Baric", G)
CL.Sim.Vote(pid, "Cyndra", P)
CL.Sim.Vote(pid, "Dorun", N)
check(not pf.pendingFrame:IsShown(), "the clock is gone once everybody has chosen")
GameTooltip:Hide()
CL.Sim.Clear()

-- 21. A big drop: more rolls than frames are queued, never dropped
CL.Sim.SetGroupSize(4)
local firstEight = CL.Sim.Start(8)
local nextFour = CL.Sim.Start(4)   -- 12 rolls for 8 frames
check(RF.ActiveCount() == 8 and RF.QueuedCount() == 4,
    "12 rolls: 8 frames and 4 queued (got " .. RF.ActiveCount() .. " and " .. RF.QueuedCount() .. ")")
check(RF.GetFrame(nextFour[1]) == nil and RF.IsQueued(nextFour[1]), "a queued roll has no frame yet")

click(firstEight[1], CL.ROLL.GREED)
check(RF.ActiveCount() == 8 and RF.QueuedCount() == 3 and RF.GetFrame(nextFour[1]) ~= nil,
    "answering one roll lets the oldest queued one in")

CL.OnRollGone(nextFour[4])   -- the server cancels a roll that was still queued
check(RF.QueuedCount() == 2 and not RF.IsQueued(nextFour[4]), "a queued roll that gets cancelled leaves the queue")
CL.Sim.Clear()
check(RF.ActiveCount() == 0 and RF.QueuedCount() == 0 and CL.Sim.ActiveCount() == 0, "clearing empties the frames and the queue")

-- a queued roll keeps counting down while it waits
local eight = CL.Sim.Start(8)
local ninth = CL.Sim.Start(1)[1]
WOW.Advance(20)
click(eight[1], CL.ROLL.PASS)
local nf9 = RF.GetFrame(ninth)
check(nf9 ~= nil and math.abs((nf9.endTime - GetTime()) - 10) < 0.2,
    "a roll that waited 20s in the queue only has about 10s left (got " .. tostring(nf9 and (nf9.endTime - GetTime())) .. ")")
CL.Sim.Clear()

-- 22. The item is not known to the client yet at START_LOOT_ROLL: ask again, do not give up
local infoCalls = 0
function GetLootRollItemInfo()
    infoCalls = infoCalls + 1
    if infoCalls <= 2 then return nil end
    return 133378, "Late Item", 1, 4, true, true, true, false, 0, 0, 3, -1, false
end
function GetLootRollItemLink() return "|cnIQ4:|Hitem:1::::::::18:1491:::::::::|h[Late Item]|h|r" end
WOW.FireEvent("START_LOOT_ROLL", 7301, 60000, 111)
check(RF.GetFrame(7301) == nil, "no frame while the item is unknown")
WOW.Advance(0.6)
local lateFrame = RF.GetFrame(7301)
check(lateFrame ~= nil and lateFrame.name:GetText() == "Late Item", "the roll appears once the item data arrives")
local lateLeft = lateFrame.endTime - GetTime()
check(lateLeft < 59.7 and lateLeft > 58, "...with the time spent waiting taken off its timer (got " .. lateLeft .. ")")
CL.OnRollGone(7301)

infoCalls = -1000   -- the item never becomes known
WOW.FireEvent("START_LOOT_ROLL", 7302, 60000, 112)
WOW.FireEvent("CANCEL_LOOT_ROLL", 7302)   -- cancelled while we were still waiting
infoCalls = 100
WOW.Advance(1)
check(RF.GetFrame(7302) == nil, "a roll cancelled while waiting for its item never shows up as a ghost")

infoCalls = -1000
CL.db.debug = true
WOW.chat = {}
WOW.FireEvent("START_LOOT_ROLL", 7303, 60000, 113)
WOW.Advance(4)
local neverArrived = false
for _, line in ipairs(WOW.chat) do if line:find("never arrived", 1, true) then neverArrived = true end end
check(RF.GetFrame(7303) == nil and neverArrived, "an item that never arrives is reported in debug mode, not silently lost")
CL.db.debug = false

-- 23. A roll whose timer ran out without a CANCEL_LOOT_ROLL does not hold a slot forever
function GetLootRollItemInfo() return 133378, "Slow Cancel", 1, 4, true, true, true, false, 0, 0, 3, -1, false end
WOW.FireEvent("START_LOOT_ROLL", 7401, 5000, 114)
WOW.Advance(6)
check(RF.GetFrame(7401) ~= nil, "right after its timer ended the frame is still there")
WOW.Advance(2)
check(RF.GetFrame(7401) == nil, "...and it closes by itself two seconds later")

-- 24. /cll debug: every roll is traced in chat and kept in the saved variables
CL.db.debug = true
CL.db.debugLog = nil
WOW.chat = {}
WOW.FireEvent("START_LOOT_ROLL", 7501, 60000, 115)
local traced = table.concat(WOW.chat, "\n")
check(traced:find("START_LOOT_ROLL roll=7501", 1, true) and traced:find("roll 7501 shown", 1, true),
    "debug mode traces the start and that the roll was shown")
WOW.chat = {}
WOW.FireEvent("CANCEL_LOOT_ROLL", 7501)
check(table.concat(WOW.chat, "\n"):find("frame was open", 1, true) ~= nil, "...and the cancel, saying a frame was open")
check(CL.db.debugLog and #CL.db.debugLog >= 3, "...and keeps the lines in the saved variables")
CL.db.debug = false
WOW.chat = {}
WOW.FireEvent("START_LOOT_ROLL", 7502, 60000, 116)
check(#WOW.chat == 0, "with debug off nothing is printed")
CL.OnRollGone(7502)

-- 25. After a /reload START_LOOT_ROLL is not sent again: running rolls are brought back
local LINKS = { [7601] = "L1", [7602] = "L2", [7603] = "L2", [7604] = "L3" }
function GetLootRollItemLink(id) return LINKS[id] end
function GetLootRollItemInfo(id) return 1000 + id, "Item" .. id, 1, 4, false, true, true, false, 0, 0, 3, -1, false end
function GetActiveLootRollIDs() return { 7601, 7602, 7603, 7604 } end
function GetLootRollTimeLeft(id) if id == 7604 then return 0 end return 42000 end
WOW.drops = {
    [901] = { lootListKey = 901, itemHyperlink = "L1", playerRollState = 4, rollInfos = {
        { isSelf = false, playerName = "Teki Moo", playerClass = "DRUID", state = 3 },
        { isSelf = true, playerName = "Hazas War", playerClass = "WARRIOR", state = 4 } } },
    [902] = { lootListKey = 902, itemHyperlink = "L2", playerRollState = 4, rollInfos = {} },
    [903] = { lootListKey = 903, itemHyperlink = "L2", playerRollState = 4, rollInfos = {} },
}
C_LootHistory = {
    GetAllEncounterInfos = function() return { { encounterID = 0 } } end,
    GetSortedDropsForEncounter = function() return { WOW.drops[901], WOW.drops[902], WOW.drops[903] } end,
    GetSortedInfoForDrop = function(_, key) return WOW.drops[key] end,
}
check(CL.RestoreRolls() == 3, "three running rolls are restored; the one with no time left is not")
check(RF.GetFrame(7601) and RF.GetFrame(7602) and RF.GetFrame(7603) and not RF.GetFrame(7604), "...the right ones")
check(math.abs((RF.GetFrame(7601).endTime - GetTime()) - 42) < 0.1, "...with the time the client says is left")
local r1 = RF.GetFrame(7601)
check(r1.votes ~= nil and #r1.votes[CL.ROLL.GREED] == 1 and r1.votes[CL.ROLL.GREED][1].name == "Teki Moo",
    "a unique item is linked back to its history entry, so its votes show")
check(RF.GetFrame(7602).votes == nil and RF.GetFrame(7603).votes == nil,
    "two identical items cannot be told apart: no votes rather than the wrong ones")
check(CL.RestoreRolls() == 0, "running it again brings back nothing new")

for _, id in ipairs({ 7601, 7602, 7603 }) do CL.OnRollGone(id) end
WOW.FireEvent("PLAYER_ENTERING_WORLD")
check(RF.GetFrame(7601) == nil, "not instantly: Blizzard gets a moment to reopen its own frames first")
WOW.Advance(2)
check(RF.GetFrame(7601) ~= nil, "login or /reload restores the running rolls by itself")
for _, id in ipairs({ 7601, 7602, 7603 }) do CL.OnRollGone(id) end

-- without GetActiveLootRollIDs: the (hidden) native frames Blizzard reopened
-- (false, not nil: the harness answers any unset global with a stub function, whereas
-- in the real client a missing global is simply nil)
GetActiveLootRollIDs, GetLootRollTimeLeft = false, false
GroupLootFrame3.rollID = 7605
GroupLootFrame3.rollTime = 90000
GroupLootFrame3:Show()
check(CL.RestoreRolls() == 1 and RF.GetFrame(7605) ~= nil, "a native roll frame is enough to bring its roll back")
check(RF.GetFrame(7605).duration == 90, "...using the native frame's duration when no time-left call exists")
CL.OnRollGone(7605)
GroupLootFrame3.rollID = nil
GroupLootFrame3:Hide()

-- 26. The real /cll sim command shows the "hasn't rolled yet" clock on every frame
--     (through the slash handler, the way a player types it, not the internal API)
CL.Sim.SetGroupSize(4)
SlashCmdList["CLEANLOOT"]("sim 3")
check(RF.ActiveCount() == 3, "/cll sim 3 opens three frames")
for i = 1, 3 do
    local fr = _G["CleanLootRollFrame" .. i]
    check(fr and fr:IsShown(), "sim frame " .. i .. " is shown")
    check(fr.pendingFrame:IsShown() and tostring(fr.pendingCount:GetText()) == "4",
        "/cll sim: frame " .. i .. " shows the clock with the 4 players still deciding")
    check((fr.pendingFrame:GetPoint()) == "TOPRIGHT", "...in the top-right corner")
end
SlashCmdList["CLEANLOOT"]("sim clear")
check(RF.ActiveCount() == 0, "/cll sim clear removes them")

SlashCmdList["CLEANLOOT"]("sim group 10")
SlashCmdList["CLEANLOOT"]("sim colors")
check(RF.ActiveCount() == 5, "/cll sim colors opens five frames")
for i = 1, 5 do
    local fr = _G["CleanLootRollFrame" .. i]
    check(fr.pendingFrame:IsShown() and tostring(fr.pendingCount:GetText()) == "10",
        "/cll sim colors: frame " .. i .. " shows the clock with 10 players deciding")
end
SlashCmdList["CLEANLOOT"]("sim clear")
CL.Sim.SetGroupSize(4)

-- 27. Position lock: locked by default, movable only when unlocked or while simulating
CL.Sim.Clear()
CL.Sim.Start(1)
check(CL.db.locked == true, "frames are locked by default")
check(RF.CanMove() == true, "...but movable while simulated rolls are on screen")
CL.Sim.Clear()
check(RF.CanMove() == false, "locked, no simulation: not movable")
local f1 = CleanLootRollFrame1
f1:GetScript("OnDragStart")(f1)
check(not f1.dragging, "a drag does nothing while locked")
f1:GetScript("OnDragStop")(f1)
local lockBox = CL.Options.widgets.lock
lockBox:SetChecked(false)
lockBox.__scripts.OnClick(lockBox)
check(CL.db.locked == false and RF.CanMove() == true, "unticking the lock option allows moving")
f1:GetScript("OnDragStart")(f1)
check(f1.dragging == true, "a drag starts once unlocked")
f1:GetScript("OnDragStop")(f1)
check(not f1.dragging and CL.db.point ~= nil, "...and the position is saved on drop")
lockBox:SetChecked(true)
lockBox.__scripts.OnClick(lockBox)
check(CL.db.locked == true and RF.CanMove() == false, "ticking it locks again")
check(CL.Options.widgets.lock ~= nil, "the options panel has the lock checkbox")

-- 28. Loot toasts: untouched by default; hide / scale / move on demand
local function NewToast(parent, withItem)
    local t = CreateFrame("Frame", nil, parent or AlertFrame)
    if withItem ~= false then
        rawset(t, "ItemName", CreateFrame("FontString", nil, t))
        rawset(t, "Icon", CreateFrame("Texture", nil, t))
    end
    return t
end
local function Banner(withItem)
    local t = NewToast(AlertFrame, withItem)
    AlertFrame:AddAlertFrame(t)
    return t
end
local T = CL.Toasts
check(CL.db.hideToasts == false or CL.db.hideToasts == nil, "toasts are not hidden by default")
check(CL.db.toastScale == nil and CL.db.toastPos == nil, "...nor resized or moved by default")
local t0 = Banner()
check(t0:IsShown() and t0:GetScale() == 1, "a loot toast is left alone by default")
local p0 = { AlertFrame:GetPoint() }
check(p0[1] == "BOTTOM" and p0[5] == 128, "...and so is the anchor")

T.SetScale(0.7)
local t1, ach = Banner(), Banner(false)
check(t1:GetScale() == 0.7, "scale applies to a loot toast as it is shown")
check(ach:GetScale() == 1 and ach:IsShown(), "...but not to other banners (no item name)")
T.SetScale(9)
check(CL.db.toastScale == 1.5, "scale is clamped to 1.5")
T.SetScale(0.7)

CL.db.toastScale = nil
T.SetHidden(true)
local t2, ach2 = Banner(), Banner(false)
check(not t2:IsShown(), "hidden: a loot toast does not stay on screen")
check(ach2:IsShown(), "...while other banners still do")
t2:Show()
t2.__scripts.OnShow(t2)
check(not t2:IsShown(), "hidden: a toast shown by other means is hidden again (OnShow)")

-- a toast that does not go through AddAlertFrame: found by the sweep after the loot event
local stray = NewToast(UIParent)
stray:SetFrameStrata("FULLSCREEN_DIALOG")
stray:Show()
WOW.FireEvent("SHOW_LOOT_TOAST")
WOW.Advance(1)
check(not stray:IsShown(), "hidden: a toast outside AlertFrame is found and hidden after SHOW_LOOT_TOAST")
local other = NewToast(UIParent)   -- same shape but not a dialog-strata frame: not ours to touch
other:Show()
WOW.FireEvent("LOOT_ITEM_ROLL_WON")
WOW.Advance(1)
check(other:IsShown(), "...a frame at another strata is left alone")
T.SetHidden(false)
local t3 = Banner()
check(t3:IsShown(), "shown again: toasts come back")

-- move: the box stands where the first toast shows
check(CL.db.toastGeom == nil, "no toast measured yet (none was anchored to AlertFrame)")
T.ToggleMover(true)
local mover = CleanLootToastMover
check(mover and mover:IsShown(), "the mover box opens")
local mp = { mover:GetPoint() }
check(mp[1] == "BOTTOM" and mp[2] == AlertFrame and mp[3] == "TOP" and mp[5] == 0,
    "...standing on AlertFrame's anchor while no toast has been measured")
T.ToggleMover(false)

local real = NewToast(AlertFrame)
real:SetSize(250, 80)
real:SetPoint("BOTTOM", AlertFrame, "TOP", 0, 14)
AlertFrame:AddAlertFrame(real)
local g = CL.db.toastGeom
check(g and g.w == 250 and g.h == 80 and g.point == "BOTTOM" and g.relPoint == "TOP" and g.y == 14,
    "the first toast hanging from AlertFrame is measured")
local second = NewToast(AlertFrame)
second:SetSize(250, 80)
second:SetPoint("BOTTOM", real, "TOP", 0, 6)
AlertFrame:AddAlertFrame(second)
check(CL.db.toastGeom.y == 14, "...a toast hanging from another toast says nothing")

T.ToggleMover(true)
mp = { mover:GetPoint() }
check(mover:GetWidth() == 250 and mover:GetHeight() == 80, "the box takes the toast's size")
check(mp[1] == "BOTTOM" and mp[2] == AlertFrame and mp[3] == "TOP" and mp[5] == 14,
    "...and its anchor: the box covers the toast")
T.SetScale(0.5)
check(mover:GetScale() == 0.5, "the Size slider resizes the open box too")

-- drag: 60 right and 30 up on the screen, in the box's own (half-size) units
local boxL, boxB = 500, 300
rawset(mover, "GetLeft", function() return boxL end)
rawset(mover, "GetBottom", function() return boxB end)
mover.__scripts.OnDragStart(mover)
mp = { mover:GetPoint() }
check(mp[1] == "BOTTOMLEFT" and mp[2] == UIParent and mp[4] == 500 and mp[5] == 300,
    "a drag sets the box on a spot of its own")
boxL, boxB = 560, 330
mover.__scripts.OnDragStop(mover)
local ap = { AlertFrame:GetPoint() }
check(ap[1] == "BOTTOM" and ap[2] == UIParent and ap[3] == "BOTTOM" and ap[4] == 30 and ap[5] == 143,
    "dropping the box moves the toast anchor by the same screen distance")
check(CL.db.toastPos and CL.db.toastPos[3] == 30, "...and saves the spot")
mp = { mover:GetPoint() }
check(mp[2] == AlertFrame, "...then the box hangs from the anchor again")
AlertFrame:ClearAllPoints()
AlertFrame:SetPoint("TOP", UIParent, "TOP", 0, 0)
AlertFrame:UpdateAnchors()
ap = { AlertFrame:GetPoint() }
check(ap[1] == "BOTTOM" and ap[4] == 30, "if Blizzard re-anchors it, our spot is put back")
CL.db.toastScale = nil
mover.__scripts.OnMouseUp(mover, "RightButton")
check(not mover:IsShown(), "right-click closes the box")
T.ResetPosition()
ap = { AlertFrame:GetPoint() }
check(CL.db.toastPos == nil and ap[1] == "BOTTOM" and ap[5] == 128, "reset puts Blizzard's anchor back")

-- slash command and options
local tw = CL.Options.widgets
tw.toastHide:SetChecked(true)
tw.toastHide.__scripts.OnClick(tw.toastHide)
check(CL.db.hideToasts == true, "the Hide option hides the toasts")
tw.toastHide:SetChecked(false)
tw.toastHide.__scripts.OnClick(tw.toastHide)
check(CL.db.hideToasts == false, "...and unticking shows them again")
tw.toastScale.__scripts.OnValueChanged(tw.toastScale, 0.8)
check(CL.db.toastScale == 0.8, "the Size slider sets the toast scale")
tw.toastMove.__scripts.OnClick(tw.toastMove)
check(CleanLootToastMover:IsShown(), "the Move button opens the mover")
tw.toastReset.__scripts.OnClick(tw.toastReset)
check(CL.db.toastPos == nil, "the Reset button clears the saved spot")
CleanLootToastMover:Hide()
for _, w in ipairs({ "toastHide", "toastScale", "toastMove", "toastReset" }) do
    check(CL.Options.widgets[w] ~= nil, "the options panel has " .. w)
end
CL.db.toastScale = nil

-- 29. The slash command: /cll opens the options, the rest is testing tools
WOW.openedCategory = nil
SlashCmdList["CLEANLOOT"]("")
check(WOW.openedCategory ~= nil, "/cll opens the options panel")
WOW.openedCategory = nil
SlashCmdList["CLEANLOOT"]("options")
check(WOW.openedCategory ~= nil, "/cll options opens it too")
WOW.chat = {}
SlashCmdList["CLEANLOOT"]("help")
local help = table.concat(WOW.chat, "\n")
check(help:find("sim", 1, true) and help:find("debug", 1, true) and help:find("restore", 1, true),
    "/cll help lists the sim, debug and restore commands")
check(not help:find("grow", 1, true) and not help:find("toasts", 1, true) and not help:find("native", 1, true),
    "...and none of the settings that live in the options")
local before = CL.db.growDirection
SlashCmdList["CLEANLOOT"]("grow up")
check(CL.db.growDirection == before, "the old settings commands no longer change anything")

io.write(("%d checks, %d failed\n"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
