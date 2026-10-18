-- MCC Contracts: settings, the dogtag items, and what makes payphones and dead drops usable.
--
-- The loop: use a payphone, take a contract on a named Combine or Rebel, find him (where he was last seen,
-- from the payphone, on your HUD), kill him, take his dogtag from the body's DOGTAG slot, and leave it in any
-- dead drop (trash can or dumpster) for roubles. Every Combine and Rebel NPC has a name and, on its body, a dogtag with it.
-- Admins place the phones and drops from the spawn menu (MCC category) and keep them with mcc_contracts_save.

MCC.Contracts = MCC.Contracts or {}
local C = MCC.Contracts
C.VERSION = "0.2.1"

C.PHONE_CLASS = "mcc_payphone"
C.DROP_CLASSES = {mcc_deaddrop_trash = true, mcc_deaddrop_dumpster = true}
C.LEGACY_DROPS = {mcc_deaddrop_mailbox = "mcc_deaddrop_dumpster"} -- saved maps from 0.1.0
C.TAG_ITEMS = {combine = "dogtag_combine", rebels = "dogtag_rebel"}
C.FACTION_NAMES = {combine = "Combine", rebels = "Rebel"}
C.UNIT_NAMES = {soldier = "Overwatch Soldier", elite = "Overwatch Elite", cp = "Civil Protection", rebel = "Resistance"}
C.KIND_FACTION = {soldier = "combine", elite = "combine", cp = "combine", rebel = "rebels"}
C.UNITS_TO_M = 0.01905

local D = MCC.Config.Define
D("contracts_enabled", true, "Payphones hand out kill contracts (MCC Contracts).")
D("contracts_npc_names", true, "Combine and Rebel NPCs get names from the HL2-lore pools (data/mcc/contracts_names.json), shown on their bodies.")
D("contracts_npc_tags", 1, "Chance (0-1) a named NPC's body has its dogtag. A contract target always has his.", 0, 1)
D("contracts_time", 1200, "Seconds to finish a contract (0 = no time limit).", 0, 86400)
D("contracts_cooldown", 60, "Seconds before a player can take another contract after one ends.", 0, 86400)
D("contracts_min_dist", 2000, "Targets are at least this far from the payphone (units).", 0, 100000)
D("contracts_max_dist", 0, "Targets are at most this far from the payphone (units, 0 = anywhere).", 0, 100000)
D("contracts_target_mode", 1, "0 = only NPCs already on the map, 1 = those first, then spawn one, 2 = always spawn a target.", 0, 2)
D("contracts_escorts", 2, "Bodyguards a spawned target comes with.", 0, 8)
D("contracts_spawn_player_dist", 2500, "Spawned targets appear at least this far from every player (units).", 0, 100000)
D("contracts_reward_min", 6000, "Smallest contract payout (roubles).", 0, 10000000)
D("contracts_reward_max", 15000, "Largest contract payout before the bodyguard bonus (roubles).", 0, 10000000)
D("contracts_reward_escort", 1500, "Extra roubles for each bodyguard or friend standing near the target.", 0, 10000000)
D("contracts_ping_interval", 90, "Seconds between updates of where the target was last seen.", 5, 3600)
D("contracts_drop_marker_range", 1312, "How close a dead drop has to be for its HUD marker to show (1312 = 25 m).", 0, 100000)
D("contracts_any_drop", true, "Any dead drop takes a contract's tag. Off: each contract names one drop.")
D("contracts_tag_bounty", 0, "Roubles for any other Combine or Rebel dogtag left in a dead drop (0 = drops refuse them).", 0, 1000000)

function C.Enabled()
    return MCC.Config.Get("contracts_enabled") and MCC.Inv and MCC.Inv.Enabled and MCC.Inv.Enabled()
end

function C.IsPhone(ent)
    return IsValid(ent) and ent:GetClass() == C.PHONE_CLASS
end

function C.IsDrop(ent)
    return IsValid(ent) and C.DROP_CLASSES[ent:GetClass()] == true
end

-- The dogtags. Each one carries the name it was taken from (d.name), the unit (d.note), the faction and,
-- for a contract target, the contract's number.
hook.Add("MCC_RegisterItems", "MCC_Contracts", function(Items)
    Items.Register("dogtag_combine", {name = "Dogtag (Combine)", kind = "misc", w = 1, h = 1, maxStack = 1, weight = 0.02,
        price = 150, category = "dogtag", model = "models/props_lab/huladoll.mdl", tags = {"dogtag"},
        data = {slot = "dogtag", faction = "combine"}})
    Items.Register("dogtag_rebel", {name = "Dogtag (Rebel)", kind = "misc", w = 1, h = 1, maxStack = 1, weight = 0.02,
        price = 150, category = "dogtag", model = "models/props_lab/huladoll.mdl", tags = {"dogtag"},
        data = {slot = "dogtag", faction = "rebels"}})
end)

function C.IsDogtag(def)
    if not def then return false end
    for _, t in ipairs(def.tags or {}) do
        if t == "dogtag" then return true end
    end
    return false
end

-- Dead drops are containers: E opens them, and items dragged onto them in the vicinity list go in.
-- Payphones are their own kind: E calls (sv_contracts.lua, MCC_PickupCustom).
hook.Add("MCC_IsPickup", "MCC_Contracts", function(ent)
    if C.IsDrop(ent) and MCC.Inv and MCC.Inv.Enabled() then return "container" end
    if C.IsPhone(ent) then return "payphone" end
end)

-- (Dead drops get MCC Base's container prompt: "Search", "Dead drop".)
hook.Add("MCC_PickupPrompt", "MCC_Contracts", function(ent, kind)
    if C.IsPhone(ent) then return "Payphone", "Make a call" end
end)

-- 640 m north-east: a compass bearing and distance from one point to another (Source: +x east, +y north).
local atan2 = math.atan2 or math.atan
local DIRS = {"east", "north-east", "north", "north-west", "west", "south-west", "south", "south-east"}
function C.Bearing(from, to)
    local dx, dy = to.x - from.x, to.y - from.y
    local deg = math.deg(atan2(dy, dx)) % 360
    local dir = DIRS[math.floor((deg + 22.5) / 45) % 8 + 1]
    return dir, math.sqrt(dx * dx + dy * dy) * C.UNITS_TO_M
end

function C.Money(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    if out:sub(1, 1) == "," then out = out:sub(2) end
    return out .. " RUB"
end
