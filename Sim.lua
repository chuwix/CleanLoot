-- Loot drop simulator (/cll sim). Real drops are rare and random, so this fakes
-- the whole flow: START_LOOT_ROLL, the roll data, other players choosing,
-- a winner, and the roll ending (CANCEL_LOOT_ROLL).
--
-- It answers CL.API for the rollIDs it creates (ids >= 900001, far from real
-- ones), so everything built on CL.API behaves exactly as with a real roll. What
-- it cannot cover: Blizzard's own native frames and the real RollOnLoot.
--
-- Drops follow a small loot table: a quality is drawn first, then an item of that
-- quality -- a real one when the client can describe one (owned or cached), else
-- a synthetic one, so every colour can always be tested.

local _, CL = ...

local Sim = {}
CL.Sim = Sim

local ROLL_TIME_MS = 30000
local nextID = 900001
local rolls = {}  -- rollID -> simulated roll

-- The other players in the simulated group (you are not counted); resized with
-- /cll sim group <n> to test a 5-man, a 10-man raid, a 25-man...
local NAME_POOL = { "Aludra", "Baric", "Cyndra", "Dorun", "Eluned", "Farrow", "Galen", "Hestia",
    "Isolde", "Jarek", "Kestrel", "Lyra", "Marrow", "Nerys", "Orin", "Pyria", "Quill", "Rowan",
    "Sable", "Tamsin" }
local PLAYERS = {}

function Sim.SetGroupSize(n)
    n = math.floor(tonumber(n) or 4)
    if n < 1 then n = 1 end
    if n > 39 then n = 39 end
    PLAYERS = {}
    for i = 1, n do
        local base = NAME_POOL[(i - 1) % #NAME_POOL + 1]
        local round = math.ceil(i / #NAME_POOL)
        PLAYERS[i] = round > 1 and (base .. round) or base
    end
    return n
end
Sim.SetGroupSize(4)

-- Quality draw for /cll sim: { quality, weight }.
local QUALITY_TABLE = { { 1, 10 }, { 2, 35 }, { 3, 30 }, { 4, 20 }, { 5, 5 } }

-- Real vanilla items worth trying beyond what the player owns. The client does
-- not know every id (14551 was unknown on the Forever beta), so these are only
-- used once cached; they are requested so a later call may pick them up.
local EXTRA_ITEMS = { 2589, 4306, 118, 2092, 1204, 1980, 12940, 16799, 11815, 18803, 19019 }

-- One made-up item per quality, used when the client has no real one.
local SYNTHETIC = {
    [0] = { name = "Sim Junk Fragment", icon = "Interface\\Icons\\INV_Misc_Rune_01" },
    [1] = { name = "Sim Common Trinket", icon = "Interface\\Icons\\INV_Misc_Gem_01" },
    [2] = { name = "Sim Uncommon Gauntlets", icon = "Interface\\Icons\\INV_Gauntlets_04" },
    [3] = { name = "Sim Rare Blade", icon = "Interface\\Icons\\INV_Sword_04" },
    [4] = { name = "Sim Epic Crown", icon = "Interface\\Icons\\INV_Helmet_01" },
    [5] = { name = "Sim Legendary Hammer", icon = "Interface\\Icons\\INV_Hammer_Unique_Sulfuras" },
}

local function After(delay, fn)
    if C_Timer and C_Timer.After then C_Timer.After(delay, fn) else fn() end
end

local function ItemInfo(itemID)
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    return get(itemID)
end

local function ColoredName(name, quality)
    local r, g, b = CL.QualityColor(quality)
    return ("|cff%02x%02x%02x[%s]|r"):format(
        math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), name)
end

-- Real items the client can describe right now, grouped by quality: equipped
-- gear and bag contents (always cached), plus any cached extra id.
local function RealItemsByQuality()
    local byQuality, seen = {}, {}
    local function add(id)
        if type(id) ~= "number" then return false end
        if seen[id] then return true end
        seen[id] = true
        local name, _, quality = ItemInfo(id)
        if not name or type(quality) ~= "number" then return false end  -- not fully loaded yet
        byQuality[quality] = byQuality[quality] or {}
        local list = byQuality[quality]
        list[#list + 1] = id
        return true
    end
    if GetInventoryItemID then
        for slot = 1, 19 do add(GetInventoryItemID("player", slot)) end
    end
    local C = C_Container
    if C and C.GetContainerNumSlots and C.GetContainerItemID then
        for bag = 0, 5 do
            for slot = 1, C.GetContainerNumSlots(bag) or 0 do add(C.GetContainerItemID(bag, slot)) end
        end
    end
    for _, id in ipairs(EXTRA_ITEMS) do
        if not add(id) and C_Item and C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(id)
        end
    end
    return byQuality
end

-- What a drop of this quality looks like: a real item when one exists.
local function DescribeQuality(quality, byQuality)
    local list = byQuality[quality]
    if list and #list > 0 then
        local name, link, q, _, _, _, _, _, _, icon = ItemInfo(list[math.random(#list)])
        return { name = name, link = link, display = link, quality = q, icon = icon }
    end
    local s = SYNTHETIC[quality] or SYNTHETIC[1]
    return { name = s.name, link = nil, display = ColoredName(s.name, quality), quality = quality, icon = s.icon }
end

local function PickQuality()
    local total = 0
    for _, e in ipairs(QUALITY_TABLE) do total = total + e[2] end
    local r = math.random() * total
    for _, e in ipairs(QUALITY_TABLE) do
        r = r - e[2]
        if r <= 0 then return e[1] end
    end
    return QUALITY_TABLE[1][1]
end

local function RandomChoice()
    local r = math.random()
    if r < 0.35 then return CL.ROLL.NEED end
    if r < 0.70 then return CL.ROLL.GREED end
    return CL.ROLL.PASS
end

function Sim.GetRoll(rollID)
    return rolls[rollID]
end

function Sim.ActiveCount()
    local n = 0
    for _ in pairs(rolls) do n = n + 1 end
    return n
end

-- Classes for the simulated players, so their names show in colour.
local CLASS_POOL = { "WARRIOR", "DRUID", "HUNTER", "SHAMAN", "MAGE", "PRIEST", "ROGUE", "PALADIN", "WARLOCK" }

local function PlayerClass(name)
    for i, n in ipairs(PLAYERS) do
        if n == name then return CLASS_POOL[(i - 1) % #CLASS_POOL + 1] end
    end
    return CLASS_POOL[1]
end

-- How the roll turned out, in the shape CL.API.GetResult documents: everyone who
-- chose Need or Greed rolls 1-100, Need beats Greed, the best roll wins. Players
-- who never answered count as passes; you, if you never answered, are not rolling.
local function BuildResult(s)
    local entries = {}
    local function add(name, class, choice, isSelf)
        if choice == CL.ROLL.NEED or choice == CL.ROLL.GREED then
            entries[#entries + 1] = { name = name, class = class, type = choice, value = math.random(100), isSelf = isSelf }
        end
    end
    for _, name in ipairs(s.order) do add(name, PlayerClass(name), s.choices[name], false) end
    add("You", nil, s.mine, true)

    table.sort(entries, function(a, b)
        if a.type ~= b.type then return a.type < b.type end  -- Need (1) before Greed (2)
        return a.value > b.value
    end)

    local res = {
        key = s.id, link = s.link, name = s.info.name, quality = s.info.quality, texture = s.info.texture,
        rolls = entries, passes = 0, allPassed = #entries == 0,
        me = { type = s.mine, value = nil },
    }
    for _, name in ipairs(s.order) do
        if s.choices[name] == CL.ROLL.PASS then res.passes = res.passes + 1 end
    end
    if s.mine == CL.ROLL.PASS then res.passes = res.passes + 1 end
    for _, e in ipairs(entries) do
        if e.isSelf then res.me.value = e.value end
    end
    if entries[1] then
        entries[1].isWinner = true
        res.winner = entries[1]
    end
    return res
end

-- The roll ends: the client tells the UI to drop the frame, like a real
-- CANCEL_LOOT_ROLL, and the result popup shows how it went.
function Sim.Finish(rollID)
    local s = rolls[rollID]
    if not s then return end
    rolls[rollID] = nil
    CL.OnRollGone(rollID)
    if CL.Results then CL.Results.Show(BuildResult(s), true) end
end

-- Another player chooses (rollType forced for tests, random otherwise), and the
-- counters on the roll frame update.
function Sim.Vote(rollID, name, rollType)
    local s = rolls[rollID]
    if not s or s.choices[name] then return false end
    s.choices[name] = rollType or RandomChoice()
    s.order[#s.order + 1] = name
    CL.OnVotesChanged(rollID)
    return true
end

-- Who chose what so far, in the shape CL.API.GetVotes documents.
function Sim.GetVotes(rollID)
    local s = rolls[rollID]
    if not s then return nil end
    local votes = { [CL.ROLL.NEED] = {}, [CL.ROLL.GREED] = {}, [CL.ROLL.PASS] = {}, pending = {} }
    for _, name in ipairs(s.order) do
        local list = votes[s.choices[name]]
        list[#list + 1] = { name = name }
    end
    for _, name in ipairs(PLAYERS) do
        if not s.choices[name] then votes.pending[#votes.pending + 1] = { name = name } end
    end
    return votes
end

-- Players make up their minds at random moments while the timer runs; a few
-- never answer, like in a real group.
local function ScheduleVotes(rollID)
    local window = ROLL_TIME_MS / 1000 - 10
    for _, name in ipairs(PLAYERS) do
        if math.random() < 0.85 then
            After(1 + math.random() * window, function() Sim.Vote(rollID, name) end)
        end
    end
end

-- Called through CL.API.Roll when the player clicks a button on a simulated roll.
function Sim.Roll(rollID, rollType)
    local s = rolls[rollID]
    if not s or s.mine ~= nil then return false end
    s.mine = rollType
    After(1 + math.random() * 2, function() Sim.Finish(rollID) end)
    return true
end

-- Registers a simulated roll for described item data and opens it like a real
-- START_LOOT_ROLL would. Returns the rollID.
local function StartRoll(data)
    local rollID = nextID
    nextID = nextID + 1
    local canNeed = math.random() > 0.25
    rolls[rollID] = {
        id = rollID, link = data.link, display = data.display,
        choices = {}, order = {},  -- other players' votes: name -> type, in vote order
        info = {
            texture = data.icon, name = data.name, count = 1, quality = data.quality or 1,
            bop = math.random() > 0.5, canNeed = canNeed, canGreed = true,
            reasonNeed = (not canNeed) and 1 or nil,
        },
    }
    CL.OnStartLootRoll(rollID, ROLL_TIME_MS)
    ScheduleVotes(rollID)
    -- If the player never chooses, the roll still ends when its timer does.
    After(ROLL_TIME_MS / 1000, function() Sim.Finish(rollID) end)
    return rollID
end

-- One roll for a specific real item id; nil when the client has no data for it.
function Sim.StartItem(itemID)
    local name, link, quality, _, _, _, _, _, _, icon = ItemInfo(itemID)
    if not name then return nil end
    return StartRoll({ name = name, link = link, display = link, quality = quality, icon = icon })
end

-- n drops (1-8) from the loot table. Returns the rollIDs.
function Sim.Start(n)
    n = math.floor(tonumber(n) or 1)
    if n < 1 then n = 1 end
    if n > 8 then n = 8 end
    local byQuality = RealItemsByQuality()
    local ids = {}
    for _ = 1, n do
        ids[#ids + 1] = StartRoll(DescribeQuality(PickQuality(), byQuality))
    end
    return ids
end

-- One drop of every colour (common to legendary), to eyeball each quality.
function Sim.Colors()
    local byQuality = RealItemsByQuality()
    local ids = {}
    for quality = 1, 5 do
        ids[#ids + 1] = StartRoll(DescribeQuality(quality, byQuality))
    end
    return ids
end

function Sim.Clear()
    local ids = {}
    for rollID in pairs(rolls) do ids[#ids + 1] = rollID end
    for _, rollID in ipairs(ids) do
        rolls[rollID] = nil
        CL.OnRollGone(rollID)
    end
end
