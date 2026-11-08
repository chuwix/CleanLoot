-- CleanLoot (WoW Forever)
-- Loot roll frames for the Forever client (Interface 16001, retail UI
-- architecture). Forever only has Need / Greed / Pass: no Disenchant and no
-- Transmog rolls.
--
-- All loot data goes through CL.API, which answers from the real client or, for
-- rollIDs created by /cll sim, from the simulator (Sim.lua). Everything above
-- that layer cannot tell the difference, so simulated drops exercise the same
-- code paths as real ones.

local ADDON_NAME, CL = ...

CL.MSG = "|cff33ff99CleanLoot|r: "

CL.ROLL = { PASS = 0, NEED = 1, GREED = 2 }
CL.ROLL_NAME = { [0] = "Pass", [1] = "Need", [2] = "Greed" }
CL.ROLL_ORDER = { 1, 2, 0 }  -- button order on a roll frame

-- Default frame scale, picked by eye on the real client.
CL.DEFAULT_SCALE = 1.10

local DEFAULTS = {
    growDirection = "DOWN",
    frameScale = CL.DEFAULT_SCALE,
    locked = true,  -- the stack cannot be dragged by accident (always movable during /cll sim)
    hideNative = true,  -- hide Blizzard's own roll frames, ours replace them
    hideRollSpam = true,  -- keep the per-roll lines out of the chat
    showResults = true,  -- a small popup with who won each roll, and with what
    keyboardEnabled = false,
    keyboardInspect = false,
    keyboardInspectSide = "RIGHT",
}

function CL.Print(msg)
    print(CL.MSG .. tostring(msg))
end

-- /cll debug: say what happens to every roll in chat, and keep the last lines in
-- the saved variables (CleanLootDB.debugLog) so they can be read after the fact.
function CL.Debug(fmt, ...)
    if not (CL.db and CL.db.debug) then return end
    local ok, line = pcall(string.format, fmt, ...)
    if not ok then line = tostring(fmt) end
    print(CL.MSG .. "[debug] " .. line)
    local log = CL.db.debugLog
    if not log then log = {} CL.db.debugLog = log end
    log[#log + 1] = date("%H:%M:%S") .. " " .. line
    if #log > 300 then table.remove(log, 1) end
end

function CL.Version()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return (get and get(ADDON_NAME, "Version")) or "?"
end

function CL.QualityColor(quality)
    if C_Item and C_Item.GetItemQualityColor then
        local r, g, b = C_Item.GetItemQualityColor(quality or 1)
        if r then return r, g, b end
    end
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- Values from the client can be "secret" (unreadable by addons in some
-- contexts); treat those as absent rather than erroring on them.
local function Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end
CL.Plain = Plain

-------------------------------------------------
-- Data access (real client or simulator)
-------------------------------------------------
local API = {}
CL.API = API

local function Bool(v)
    return v == true or v == 1
end

-- Returns { texture, name, count, quality, bop, canNeed, canGreed,
-- reasonNeed, reasonGreed } or nil when the roll is unknown.
function API.GetRollInfo(rollID)
    local sim = CL.Sim and CL.Sim.GetRoll(rollID)
    if sim then return sim.info end
    local ok, texture, name, count, quality, bop, canNeed, canGreed, _, reasonNeed, reasonGreed =
        pcall(GetLootRollItemInfo, rollID)
    if not ok or not name then return nil end
    return {
        texture = texture, name = name, count = count or 1, quality = quality or 1,
        bop = Bool(bop), canNeed = Bool(canNeed), canGreed = Bool(canGreed),
        reasonNeed = reasonNeed, reasonGreed = reasonGreed,
    }
end

function API.GetRollLink(rollID)
    local sim = CL.Sim and CL.Sim.GetRoll(rollID)
    if sim then return sim.link end
    local ok, link = pcall(GetLootRollItemLink, rollID)
    return ok and link or nil
end

-- A live roll is tied to its entry in the loot history by the third argument of
-- START_LOOT_ROLL (the "loot handle" = the drop's lootListKey).
local keyByRoll, rollByKey, encounterByKey = {}, {}, {}

function API.TrackRoll(rollID, lootKey)
    lootKey = Plain(lootKey)
    if lootKey == nil then return end
    keyByRoll[rollID] = lootKey
    rollByKey[lootKey] = rollID
    if CL.Results then CL.Results.Watch(lootKey) end  -- its winner is announced when known
end

function API.ForgetRoll(rollID)
    local key = keyByRoll[rollID]
    if key ~= nil then
        rollByKey[key] = nil
        encounterByKey[key] = nil
    end
    keyByRoll[rollID] = nil
end

-- The roll a LOOT_HISTORY_UPDATE_DROP lootListKey belongs to, if we show it.
function API.RollForKey(lootKey)
    return rollByKey[Plain(lootKey)]
end

-- The drop's entry in C_LootHistory. The history is organised by encounter and
-- START_LOOT_ROLL does not say which, so look it up once and remember it.
local function FindDrop(lootKey)
    local H = C_LootHistory
    if not (H and H.GetSortedInfoForDrop and H.GetAllEncounterInfos) then return nil end
    local known = encounterByKey[lootKey]
    if known ~= nil then
        local ok, drop = pcall(H.GetSortedInfoForDrop, known, lootKey)
        if ok and drop then return drop end
    end
    local ok, encounters = pcall(H.GetAllEncounterInfos)
    if not ok or type(encounters) ~= "table" then return nil end
    for _, enc in ipairs(encounters) do
        local okDrop, drop = pcall(H.GetSortedInfoForDrop, enc.encounterID, lootKey)
        if okDrop and drop then
            encounterByKey[lootKey] = enc.encounterID
            return drop
        end
    end
    return nil
end

-- C_LootHistory roll state -> our roll type (Enum.EncounterLootDropRollState:
-- NeedMainSpec 0, NeedOffSpec 1, Transmog 2, Greed 3, NoRoll 4, Pass 5).
local STATE = Enum and Enum.EncounterLootDropRollState
local NO_ROLL = (STATE and STATE.NoRoll) or 4
local STATE_TO_TYPE = {
    [(STATE and STATE.NeedMainSpec) or 0] = CL.ROLL.NEED,
    [(STATE and STATE.NeedOffSpec) or 1] = CL.ROLL.NEED,
    [(STATE and STATE.Greed) or 3] = CL.ROLL.GREED,
    [(STATE and STATE.Pass) or 5] = CL.ROLL.PASS,
}

-- After a /reload START_LOOT_ROLL is not sent again, so the loot handle of a
-- running roll is lost. Find its drop in the history by item link: only when
-- exactly one still-open drop of that item exists (two identical items cannot be
-- told apart, and a wrong link would show another roll's votes).
function API.GuessLootKey(rollID)
    local H = C_LootHistory
    local link = API.GetRollLink(rollID)
    if not (link and H and H.GetAllEncounterInfos and H.GetSortedDropsForEncounter) then return nil end
    local okEnc, encounters = pcall(H.GetAllEncounterInfos)
    if not okEnc or type(encounters) ~= "table" then return nil end
    local found, count = nil, 0
    for _, enc in ipairs(encounters) do
        local okDrops, drops = pcall(H.GetSortedDropsForEncounter, enc.encounterID)
        if okDrops and type(drops) == "table" then
            for _, drop in ipairs(drops) do
                local key = Plain(drop.lootListKey)
                if key ~= nil and not rollByKey[key] and Plain(drop.itemHyperlink) == link
                    and Plain(drop.playerRollState) == NO_ROLL and not drop.winner then
                    found, count = key, count + 1
                end
            end
        end
    end
    return count == 1 and found or nil
end

-- Who chose what so far:
--   { [NEED] = { { name = "X", class = "DRUID", value = nil|number }, ... },
--     [GREED] = {...}, [PASS] = {...},
--     pending = { { name = "Y", class = "HUNTER" }, ... } }   -- not chosen yet
-- or nil when unknown.
function API.GetVotes(rollID)
    local sim = CL.Sim and CL.Sim.GetRoll(rollID)
    if sim then return CL.Sim.GetVotes(rollID) end

    local lootKey = keyByRoll[rollID]
    if lootKey == nil then return nil end
    local drop = FindDrop(lootKey)
    if not drop or type(drop.rollInfos) ~= "table" then return nil end

    local votes = { [CL.ROLL.NEED] = {}, [CL.ROLL.GREED] = {}, [CL.ROLL.PASS] = {}, pending = {} }
    for _, info in ipairs(drop.rollInfos) do
        local state = Plain(info.state)
        local isSelf = Plain(info.isSelf)
        local rollType = STATE_TO_TYPE[state]
        if rollType then
            local list = votes[rollType]
            list[#list + 1] = {
                name = isSelf and "You" or Plain(info.playerName) or "?",
                class = Plain(info.playerClass),
                value = Plain(info.roll),
            }
        elseif state == NO_ROLL and not isSelf then
            -- has not chosen yet (you are not listed: you are the one deciding)
            votes.pending[#votes.pending + 1] = {
                name = Plain(info.playerName) or "?",
                class = Plain(info.playerClass),
            }
        end
    end
    return votes
end

-- Name, quality and icon of an item link. The link text carries the name and (in
-- "|cnIQ<n>:" colour tags) the quality, so most of it needs no cached item data.
local function ItemFacts(link)
    if type(link) ~= "string" then return nil end
    local name = link:match("|h%[(.-)%]|h")
    local quality = tonumber(link:match("|cnIQ(%d)"))
    local texture
    local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if instant then
        -- itemID, type, subtype, equipLoc, icon
        local ok, _, _, _, _, icon = pcall(instant, link)
        if ok and icon ~= nil then texture = icon end
    end
    if not (name and quality) then
        local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        if get then
            local ok, n, _, q = pcall(get, link)
            if ok then name, quality = name or n, quality or q end
        end
    end
    return name, quality, texture
end

local function SortRolls(a, b)
    if a.type ~= b.type then return (a.type or 9) < (b.type or 9) end  -- Need before Greed
    return (a.value or -1) > (b.value or -1)
end

-- How a finished roll ended, from the loot history:
--   { key, link, name, quality, texture, allPassed,
--     winner = { name, class, type, value, isSelf } | nil,
--     me = { type = nil|NEED|GREED|PASS, value = nil|number } | nil,
--     rolls = { { name, class, type, value, isSelf, isWinner }, ... },  -- Need then Greed, best first
--     passes = n }
-- or nil when the drop is unknown. `winner` is nil until the game has decided.
function API.GetResult(lootKey)
    lootKey = Plain(lootKey)
    if lootKey == nil then return nil end
    local drop = FindDrop(lootKey)
    if not drop then return nil end

    local res = { key = lootKey, rolls = {}, passes = 0 }
    res.link = Plain(drop.itemHyperlink)
    res.name, res.quality, res.texture = ItemFacts(res.link)
    res.allPassed = Plain(drop.allPassed) == true

    local function Entry(info)
        return {
            name = Plain(info.playerName) or "?", class = Plain(info.playerClass),
            type = STATE_TO_TYPE[Plain(info.state)], value = Plain(info.roll),
            isSelf = Plain(info.isSelf) == true, isWinner = Plain(info.isWinner) == true,
        }
    end
    if type(drop.rollInfos) == "table" then
        for _, info in ipairs(drop.rollInfos) do
            local e = Entry(info)
            if e.isSelf then res.me = { type = e.type, value = e.value } end
            if e.type == CL.ROLL.NEED or e.type == CL.ROLL.GREED then
                res.rolls[#res.rolls + 1] = e
            elseif e.type == CL.ROLL.PASS then
                res.passes = res.passes + 1
            end
        end
        table.sort(res.rolls, SortRolls)
    end
    if type(drop.winner) == "table" then
        res.winner = Entry(drop.winner)
        if not res.winner.type then
            for _, e in ipairs(res.rolls) do
                if e.isWinner then res.winner.type = e.type break end
            end
        end
    end
    return res
end

function API.Roll(rollID, rollType)
    local sim = CL.Sim and CL.Sim.GetRoll(rollID)
    if sim then return CL.Sim.Roll(rollID, rollType) end
    local ok, err = pcall(RollOnLoot, rollID, rollType)
    if not ok then CL.Print("RollOnLoot failed: " .. tostring(err)) end
    return ok
end

-------------------------------------------------
-- Roll lifecycle (called by the real events and by the simulator)
-------------------------------------------------
-- Rolls still waiting for the client to know their item. Keyed by rollID so a
-- CANCEL_LOOT_ROLL in the meantime stops the retries instead of leaving a ghost.
local waitingForItem = {}
local INFO_RETRY_DELAY, INFO_MAX_RETRIES = 0.25, 12  -- about 3 seconds

function CL.OnStartLootRoll(rollID, rollTime, lootKey, startedAt, attempt)
    startedAt = startedAt or GetTime()
    attempt = attempt or 0

    local info = API.GetRollInfo(rollID)
    if not info then
        -- The item can be unknown to the client for a moment (it is for some
        -- drops). Do not give the roll up: ask again shortly.
        if attempt == 0 then waitingForItem[rollID] = true end
        if attempt >= INFO_MAX_RETRIES then
            waitingForItem[rollID] = nil
            CL.Debug("roll %s: the item data never arrived, the roll is NOT shown", tostring(rollID))
            return
        end
        CL.Debug("roll %s: no item data yet (try %d), asking again", tostring(rollID), attempt + 1)
        C_Timer.After(INFO_RETRY_DELAY, function()
            if waitingForItem[rollID] then
                CL.OnStartLootRoll(rollID, rollTime, lootKey, startedAt, attempt + 1)
            end
        end)
        return
    end
    waitingForItem[rollID] = nil

    -- time already spent waiting for the item counts against the roll
    local remaining = rollTime
    if rollTime and rollTime > 0 then
        remaining = rollTime - (GetTime() - startedAt) * 1000
        if remaining <= 0 then
            CL.Debug("roll %s: already over by the time the item data arrived", tostring(rollID))
            return
        end
    end

    API.TrackRoll(rollID, lootKey)
    -- this item will be in the winner popup: its "You won" toast is redundant
    if CL.Results then CL.Results.Cover(info.name, 300) end
    CL.RollFrames.Start(rollID, info, API.GetRollLink(rollID), remaining)
end

function CL.OnRollGone(rollID)
    waitingForItem[rollID] = nil
    CL.RollFrames.Stop(rollID)
    API.ForgetRoll(rollID)
end

-- After a login or /reload the client does not send START_LOOT_ROLL again for rolls
-- that were already running, so they would never get a frame even though the
-- server still waits for your choice. Look for them: the active roll ids, and the
-- native roll frames Blizzard reopened (they are hidden, not gone).
function CL.RestoreRolls()
    local RF = CL.RollFrames
    local candidates, seen = {}, {}
    local function add(rollID, nativeFrame)
        if type(rollID) == "number" and not seen[rollID] then
            seen[rollID] = true
            candidates[#candidates + 1] = { rollID = rollID, nativeTime = nativeFrame and nativeFrame.rollTime }
        end
    end

    if GetActiveLootRollIDs then
        local ok, list = pcall(GetActiveLootRollIDs)
        if ok and type(list) == "table" then
            for _, rollID in ipairs(list) do add(rollID) end
        end
    end
    for i = 1, 12 do
        local nf = _G["GroupLootFrame" .. i]
        if type(nf) == "table" and nf.rollID and nf.IsShown and nf:IsShown() then add(nf.rollID, nf) end
    end

    local restored = 0
    for _, c in ipairs(candidates) do
        local rollID = c.rollID
        if not (RF.GetFrame(rollID) or RF.IsQueued(rollID) or waitingForItem[rollID]) then
            -- time left: the client's own answer, else the native frame's full duration
            local left = c.nativeTime
            if GetLootRollTimeLeft then
                local ok, t = pcall(GetLootRollTimeLeft, rollID)
                if ok and type(t) == "number" then left = t end
            end
            if (left or 60000) > 0 and API.GetRollInfo(rollID) then
                CL.Debug("restoring roll %s (%s ms left)", tostring(rollID), tostring(left))
                CL.OnStartLootRoll(rollID, left or 60000, API.GuessLootKey(rollID))
                restored = restored + 1
            end
        end
    end
    CL.Debug("restore: %d candidate(s), %d restored", #candidates, restored)
    return restored
end

-- Someone chose Need/Greed/Pass on this roll: refresh the counters.
function CL.OnVotesChanged(rollID)
    CL.RollFrames.RefreshVotes(rollID)
end

-------------------------------------------------
-- Events
-------------------------------------------------
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("ADDON_LOADED")
watcher:RegisterEvent("START_LOOT_ROLL")
watcher:RegisterEvent("CANCEL_LOOT_ROLL")
watcher:RegisterEvent("LOOT_HISTORY_UPDATE_DROP")
watcher:RegisterEvent("LOOT_ROLLS_COMPLETE")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")

watcher:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        CleanLootDB = CleanLootDB or {}
        for k, v in pairs(DEFAULTS) do
            if CleanLootDB[k] == nil then CleanLootDB[k] = v end
        end
        CL.db = CleanLootDB
        -- each part on its own: one failing must not take the others down
        for _, part in ipairs({ "Native", "Toasts", "Options", "MinimapButton", "ChatFilter" }) do
            local module = CL[part]
            local setup = module and (module.Install or module.Setup)
            if setup then
                local ok, err = pcall(setup)
                if not ok then CL.Print(part .. ": " .. tostring(err)) end
            end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- login, /reload or a loading screen: give Blizzard a moment to reopen its
        -- own roll frames, then pick up whatever is still running
        C_Timer.After(1.5, function()
            local ok, err = pcall(CL.RestoreRolls)
            if not ok then CL.Print("restoring the running rolls failed: " .. tostring(err)) end
        end)
    elseif event == "START_LOOT_ROLL" then
        CL.Debug("START_LOOT_ROLL roll=%s time=%s key=%s", tostring(arg1), tostring(arg2), tostring(Plain(arg3)))
        local ok, err = pcall(CL.OnStartLootRoll, arg1, arg2, arg3)
        if not ok then CL.Print("START_LOOT_ROLL: " .. tostring(err)) end
        if CL.Native then CL.Native.Refresh() end
    elseif event == "CANCEL_LOOT_ROLL" then
        local RF = CL.RollFrames
        CL.Debug("CANCEL_LOOT_ROLL roll=%s (%s)", tostring(arg1),
            RF.GetFrame(arg1) and "frame was open" or (RF.IsQueued(arg1) and "was queued" or "no frame"))
        local ok, err = pcall(CL.OnRollGone, arg1)
        if not ok then CL.Print("CANCEL_LOOT_ROLL: " .. tostring(err)) end
    elseif event == "LOOT_HISTORY_UPDATE_DROP" then
        -- (encounterID, lootListKey): somebody's choice or the result changed
        local rollID = API.RollForKey(arg2)
        if rollID then
            local ok, err = pcall(CL.OnVotesChanged, rollID)
            if not ok then CL.Print("LOOT_HISTORY_UPDATE_DROP: " .. tostring(err)) end
        end
        -- the result of a finished roll lands in the history just after the "complete" event
        local ok, err = pcall(CL.Results.OnDropUpdate, arg2)
        if not ok then CL.Print("LOOT_HISTORY_UPDATE_DROP (result): " .. tostring(err)) end
    elseif event == "LOOT_ROLLS_COMPLETE" then
        -- (lootListKey): everybody has answered or the time is up, the winner is known
        CL.Debug("LOOT_ROLLS_COMPLETE key=%s", tostring(Plain(arg1)))
        local ok, err = pcall(CL.Results.OnComplete, arg1)
        if not ok then CL.Print("LOOT_ROLLS_COMPLETE: " .. tostring(err)) end
    end
end)
