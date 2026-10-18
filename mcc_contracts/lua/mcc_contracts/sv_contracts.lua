-- MCC Contracts, server: NPC names and dogtags, the contracts themselves, payphones, dead drops, payouts.
--
-- A contract: a named target (a Combine or Rebel NPC already on the map, or one spawned with bodyguards), a
-- reward, a time limit. The holder's HUD says where he was last seen, from the payphone, updated as he moves. Whoever
-- kills him, the tag on his body is what counts: put it in a dead drop and the holder is paid in roubles.
--
-- Hooks for other addons:
--   MCC_ContractStarted(contract, ply)        MCC_ContractCompleted(contract, depositor)
--   MCC_ContractFailed(contract, reason)      MCC_ContractCanTarget(npc, faction) -> false to skip an NPC

local C = MCC.Contracts
local Inv = MCC.Inv

C.List = C.List or {}         -- contract id -> contract (only open ones: active or dead)
C.BySid = C.BySid or {}       -- holder's SteamID64 -> their open contract
C.CooldownUntil = C.CooldownUntil or {} -- SteamID64 -> CurTime() when they can take another
C.Pending = C.Pending or {}   -- SteamID64 -> roubles owed (the holder was offline when the tag came in)
C.NextID = C.NextID or 0

-- Data files ------------------------------------------------------------------------------------------------

-- data/mcc/contracts.json: what a spawned target and his bodyguards are (per faction), and what the voice
-- on the phone says.
C.DEFAULT_SETUP = {
    targets = {
        combine = {
            target = {
                {class = "npc_combine_s", weapons = {"weapon_ar2"}, keyvalues = {model = "models/combine_super_soldier.mdl"}, weight = 1},
                {class = "npc_combine_s", weapons = {"weapon_smg1", "weapon_ar2"}, weight = 2},
                {class = "npc_metropolice", weapons = {"weapon_pistol", "weapon_smg1"}, weight = 1},
            },
            escorts = {
                {class = "npc_combine_s", weapons = {"weapon_smg1", "weapon_ar2"}, weight = 2},
                {class = "npc_combine_s", weapons = {"weapon_shotgun"}, keyvalues = {skin = 1}, weight = 1},
                {class = "npc_metropolice", weapons = {"weapon_smg1", "weapon_pistol"}, weight = 1},
            },
        },
        rebels = {
            target = {{class = "npc_citizen", weapons = {"weapon_ar2", "weapon_shotgun", "weapon_smg1"}, keyvalues = {citizentype = 3}}},
            escorts = {{class = "npc_citizen", weapons = {"weapon_smg1", "weapon_shotgun", "weapon_pistol"}, keyvalues = {citizentype = 3}}},
        },
    },
    lines = {
        greet = {"Line's clean. Talk.", "I wondered when you'd call.", "Don't say your name. I already know it.",
            "You've got the look of someone who needs work.", "Make it quick. They listen to these lines."},
        offer = {"One name, one tag. You know how this goes.", "Someone wants this one gone. Bring me the tag, not a story.",
            "Here's your name. Don't miss.", "He doesn't know he's on a list yet. Keep it that way."},
        active = {"You already have a name. Finish it.", "Still breathing, is he? Get on with it.", "I gave you a job. Do it."},
        dead = {"He's down. Now the tag, in a drop. Not here.", "Good. I want that tag in a drop, not in your pocket."},
        busy = {"Not now. Call back in a bit.", "Lines are hot. Give it a minute.", "Patience. I'll have something soon."},
        none = {"Nobody worth paying for out there right now. Try later.", "Quiet out there. Too quiet to pay for."},
        abandon = {"Fine. I'll find someone who finishes.", "Your loss. Don't make a habit of it."},
        owed = {"Money I owed you. Don't spend it all on rations."},
    },
}

local function StringList(v)
    local out = {}
    for _, s in ipairs(istable(v) and v or {}) do
        if isstring(s) and s ~= "" then out[#out + 1] = s end
    end
    return out
end

local function SanitizeUnits(list)
    local out = {}
    for _, e in ipairs(istable(list) and list or {}) do
        if istable(e) and isstring(e.class) and e.class ~= "" then
            local weps = StringList(e.weapons)
            if isstring(e.weapon) then weps[#weps + 1] = e.weapon end
            out[#out + 1] = {class = e.class, weapons = weps, keyvalues = istable(e.keyvalues) and e.keyvalues or {},
                weight = math.max(0, tonumber(e.weight) or 1)}
        end
    end
    return out
end

function C.LoadData()
    MCC.Data.EnsureJSON("contracts_names.json", C.DEFAULT_NAMES)
    local raw = MCC.Data.ReadJSON("contracts_names.json")
    local names = {}
    for key, def in pairs(C.DEFAULT_NAMES) do
        if istable(def) then
            local list = StringList(istable(raw) and raw[key])
            names[key] = #list > 0 and list or table.Copy(def)
        else
            names[key] = istable(raw) and tonumber(raw[key]) or def
        end
    end
    C.Names = names

    MCC.Data.EnsureJSON("contracts.json", C.DEFAULT_SETUP)
    raw = MCC.Data.ReadJSON("contracts.json")
    raw = istable(raw) and raw or {}
    local setup = {targets = {}, lines = {}}
    local targets = istable(raw.targets) and raw.targets or C.DEFAULT_SETUP.targets
    for faction, t in pairs(targets) do
        if isstring(faction) and istable(t) then
            setup.targets[faction] = {target = SanitizeUnits(t.target), escorts = SanitizeUnits(t.escorts)}
        end
    end
    for key, def in pairs(C.DEFAULT_SETUP.lines) do
        local list = StringList(istable(raw.lines) and raw.lines[key])
        setup.lines[key] = #list > 0 and list or table.Copy(def)
    end
    C.Setup = setup
end
hook.Add("MCC_Ready", "MCC_Contracts", function() C.LoadData() end)
hook.Add("MCC_ReloadConfig", "MCC_Contracts", function() C.LoadData() end)

function C.Line(key)
    local list = C.Setup and C.Setup.lines[key] or C.DEFAULT_SETUP.lines[key] or {}
    return list[math.random(1, math.max(1, #list))] or ""
end

local function Notify(ply, msg, ...)
    if IsValid(ply) and msg then Inv.Notify(ply, select("#", ...) > 0 and string.format(msg, ...) or msg) end
end

local function PlayerBySid(sid)
    for _, p in ipairs(player.GetAll()) do
        if p:SteamID64() == sid then return p end
    end
end

-- Names and dogtags -----------------------------------------------------------------------------------------

local function HasHead(npc)
    if not npc.LookupBone then return true end
    return npc:LookupBone("ValveBiped.Bip01_Head1") ~= nil
end

-- Which name an NPC gets: "soldier", "elite", "cp", "rebel", or nil for NPCs without one (manhacks, hunters,
-- turrets, zombies...). ZBase NPCs and MCC AI faction units count by their faction if they're humanoid.
function C.KindOf(npc)
    if not IsValid(npc) or not npc:IsNPC() then return nil end
    if npc.MCCNameKind ~= nil then return npc.MCCNameKind or nil end
    local cls, kind = npc:GetClass(), nil
    local function CombineKind()
        local mdl = string.lower(npc:GetModel() or "")
        if string.find(mdl, "super", 1, true) then return "elite" end
        if string.find(mdl, "police", 1, true) then return "cp" end
        return "soldier"
    end
    if cls == "npc_metropolice" then
        kind = "cp"
    elseif cls == "npc_combine_s" then
        kind = CombineKind()
    elseif cls == "npc_citizen" then
        kind = "rebel"
    elseif HasHead(npc) then
        local AF = MCC.AI and MCC.AI.FOB
        local f = (AF and AF.FactionOf and AF.FactionOf(npc)) or npc.ZBaseFaction
        if f == "combine" then kind = CombineKind() elseif f == "rebels" or f == "ally" then kind = "rebel" end
    end
    npc.MCCNameKind = kind or false
    return kind
end

-- "combine" or "rebels" (nil: no faction contracts know of).
function C.FactionOf(npc)
    local kind = C.KindOf(npc)
    return kind and C.KIND_FACTION[kind] or nil
end

-- Gives an NPC its name (once). force: even with mcc_contracts_npc_names off (contract targets).
function C.NameNPC(npc, force)
    if isstring(npc.MCCName) and npc.MCCName ~= "" then return npc.MCCName end
    local kind = C.KindOf(npc)
    if not kind or not (force or MCC.Config.Get("contracts_npc_names")) then return nil end
    npc.MCCName = C.UniqueName(kind)
    npc.MCCUnit = C.UNIT_NAMES[kind]
    return npc.MCCName
end

-- Who last hurt a named NPC, and with what: the dogtag says who killed him.
hook.Add("EntityTakeDamage", "MCC_ContractsLastHit", function(ent, dmg)
    if not IsValid(ent) or not ent:IsNPC() or not C.KindOf(ent) then return end
    local att = dmg:GetAttacker()
    if IsValid(att) and att ~= ent then ent.MCCLastHit = {att = att, inf = dmg:GetInflictor(), t = CurTime()} end
end)

function C.MakeTag(npc, c)
    local kind = C.KindOf(npc)
    local faction = kind and C.KIND_FACTION[kind]
    if not faction or not MCC.Items.Get(C.TAG_ITEMS[faction]) then return nil end
    local note = npc.MCCUnit or C.UNIT_NAMES[kind]
    if c then note = note .. "  |  Contract #" .. c.id end
    local hit = npc.MCCLastHit
    local d = Inv.DeathInfo and Inv.DeathInfo(npc, hit and hit.att, hit and hit.inf) or {t = os.time()}
    if not hit then d.killer = "Unknown" end
    d.name, d.note, d.faction, d.side, d.contract = npc.MCCName, note,
        (C.FACTION_NAMES[faction] or faction) .. " (" .. (npc.MCCUnit or C.UNIT_NAMES[kind]) .. ")", faction, c and c.id or nil
    return Inv.NewItem(C.TAG_ITEMS[faction], 1, d)
end

-- The body: named after the NPC (MCC Base reads npc.MCCName), with his dogtag in the DOGTAG slot.
hook.Add("MCC_NPCBody", "MCC_Contracts", function(npc, inv)
    if not MCC.Config.Get("contracts_enabled") or not C.KindOf(npc) then return end
    local c = npc.MCCContract and C.List[npc.MCCContract]
    if not C.NameNPC(npc, c ~= nil) or inv.slots.dogtag then return end
    if not c and math.random() >= MCC.Config.Get("contracts_npc_tags") then return end
    inv.slots.dogtag = C.MakeTag(npc, c)
end)

-- Finding and spawning targets ------------------------------------------------------------------------------

local HULL_MIN, HULL_MAX = Vector(-18, -18, 0), Vector(18, 18, 72)

local function Room(pos)
    local start = pos + Vector(0, 0, 4)
    local tr = util.TraceHull({start = start, endpos = start, mins = HULL_MIN, maxs = HULL_MAX, mask = MASK_NPCSOLID})
    return not tr.Hit and not tr.StartSolid
end

local function FarFromPlayers(pos, dist)
    for _, p in ipairs(player.GetAll()) do
        if p:Alive() and p:GetPos():Distance(pos) < dist then return false end
    end
    return true
end

local function InRange(origin, pos)
    local d = pos:Distance(origin)
    local maxD = MCC.Config.Get("contracts_max_dist")
    return d >= MCC.Config.Get("contracts_min_dist") and (maxD <= 0 or d <= maxD)
end

local function Wants(want, faction)
    return faction and (want == "any" or want == faction)
end

-- Allies of the target close to him (bodyguards, squadmates): each one adds to the reward.
function C.Guards(target)
    local faction, n = C.FactionOf(target), 0
    for _, e in ipairs(ents.GetAll()) do
        if e ~= target and IsValid(e) and e:IsNPC() and e:Health() > 0 and C.FactionOf(e) == faction
            and e:GetPos():Distance(target:GetPos()) < 600 then n = n + 1 end
    end
    return n
end

-- A Combine or Rebel NPC already on the map, in range of the phone and not anyone's target yet.
function C.PickExisting(origin, want)
    local list = {}
    for _, e in ipairs(ents.GetAll()) do
        if IsValid(e) and e:IsNPC() and e:Health() > 0 and not e.MCCContract and Wants(want, C.FactionOf(e))
            and InRange(origin, e:GetPos()) and hook.Run("MCC_ContractCanTarget", e, C.FactionOf(e)) ~= false then
            list[#list + 1] = e
        end
    end
    return #list > 0 and list[math.random(1, #list)] or nil
end

-- A spot on the navmesh in range of the phone and out of every player's sight distance.
function C.SpawnPos(origin)
    if not navmesh or not navmesh.IsLoaded or not navmesh.IsLoaded() then return nil end
    local areas = navmesh.GetAllNavAreas()
    if not areas or #areas == 0 then return nil end
    local away = MCC.Config.Get("contracts_spawn_player_dist")
    for _ = 1, 80 do
        local a = areas[math.random(1, #areas)]
        if a:GetSizeX() >= 48 and a:GetSizeY() >= 48 and not (a.IsUnderwater and a:IsUnderwater()) then
            local p = a:GetCenter()
            if InRange(origin, p) and FarFromPlayers(p, away) and Room(p) and not hook.Run("MCC_NoNPCZone", p, 300) then return p end
        end
    end
end

local function Weighted(list)
    local sum = 0
    for _, e in ipairs(list) do sum = sum + (e.weight or 1) end
    if sum <= 0 then return list[1] end
    local r = math.random() * sum
    for _, e in ipairs(list) do
        r = r - (e.weight or 1)
        if r <= 0 then return e end
    end
    return list[#list]
end

function C.SpawnNPC(entry, pos, faction)
    local wep = #entry.weapons > 0 and entry.weapons[math.random(1, #entry.weapons)] or nil
    local npc
    if ZBaseNPCs and ZBaseNPCs[entry.class] and ZBaseSpawnZBaseNPC then
        npc = ZBaseSpawnZBaseNPC(entry.class, pos, nil, wep or "default")
    else
        npc = ents.Create(entry.class)
        if not IsValid(npc) then return nil end
        npc:SetPos(pos)
        npc:SetAngles(Angle(0, math.random(0, 359), 0))
        for k, v in pairs(entry.keyvalues) do npc:SetKeyValue(k, tostring(v)) end
        if entry.keyvalues.model then npc:SetModel(entry.keyvalues.model) end
        if wep then npc:SetKeyValue("additionalequipment", wep) end
        npc:Spawn()
        npc:Activate()
    end
    if not IsValid(npc) then return nil end
    npc.MCCContractSpawn = true
    -- with MCC AI Behaviors: one of the faction's units, so it fights whoever the faction fights
    local AF = MCC.AI and MCC.AI.FOB
    if AF and AF.Factions and AF.Factions[faction] then
        npc.MCCFaction = faction
        if AF.Units then AF.Units[npc] = true end
        if AF.ApplyRelations then AF.ApplyRelations(npc) end
        if MCC.AI.Rescan then MCC.AI.Rescan() end
    end
    return npc
end

local ESCORT_OFFSETS = {{70, 0}, {-70, 0}, {0, 70}, {0, -70}, {70, 70}, {-70, -70}, {70, -70}, {-70, 70},
    {140, 0}, {-140, 0}, {0, 140}, {0, -140}}

-- A named target with mcc_contracts_escorts bodyguards, somewhere on the navmesh.
function C.SpawnTarget(origin, want)
    local factions = {}
    for f, t in pairs(C.Setup and C.Setup.targets or {}) do
        if Wants(want, f) and #t.target > 0 then factions[#factions + 1] = f end
    end
    table.sort(factions)
    if #factions == 0 then return nil end
    local faction = factions[math.random(1, #factions)]
    local pos = C.SpawnPos(origin)
    if not pos then return nil end
    local T = C.Setup.targets[faction]
    local target = C.SpawnNPC(Weighted(T.target), pos, faction)
    if not IsValid(target) then return nil end
    local squad = "mcc_contract_" .. (C.NextID + 1)
    if target.SetSquad then target:SetSquad(squad) end
    local escorts = {}
    if #T.escorts > 0 then
        local want_n, i = MCC.Config.Get("contracts_escorts"), 1
        while #escorts < want_n and i <= #ESCORT_OFFSETS do
            local p = pos + Vector(ESCORT_OFFSETS[i][1], ESCORT_OFFSETS[i][2], 0)
            if Room(p) then
                local e = C.SpawnNPC(Weighted(T.escorts), p, faction)
                if IsValid(e) then
                    if e.SetSquad then e:SetSquad(squad) end
                    escorts[#escorts + 1] = e
                end
            end
            i = i + 1
        end
    end
    return target, escorts
end

-- Per mcc_contracts_target_mode: an NPC already out there, or a fresh one with bodyguards.
function C.FindTarget(origin, want)
    local mode = MCC.Config.Get("contracts_target_mode")
    if mode ~= 2 then
        local t = C.PickExisting(origin, want)
        if t then return t, {} end
    end
    if mode ~= 0 then return C.SpawnTarget(origin, want) end
end

-- Contracts -------------------------------------------------------------------------------------------------

function C.Drops()
    local list = {}
    for cls in pairs(C.DROP_CLASSES) do
        for _, e in ipairs(ents.FindByClass(cls)) do
            if IsValid(e) then list[#list + 1] = e end
        end
    end
    table.sort(list, function(a, b) return a:EntIndex() < b:EntIndex() end)
    return list
end

function C.Open(ply)
    local c = IsValid(ply) and C.BySid[ply:SteamID64()]
    if c and C.List[c.id] == c then return c end
end

function C.CooldownLeft(ply)
    return math.max(0, (C.CooldownUntil[ply:SteamID64()] or 0) - CurTime())
end

-- Where the target was last seen, from the payphone (and the outpost he's near), refreshed each ping.
-- No marker: the hint is all the holder gets.
function C.Ping(c)
    local t = c.target
    if not IsValid(t) then return end
    local pos = t:GetPos()
    c.pingAt = CurTime()
    local dir, m = C.Bearing(c.origin, pos)
    c.hint = string.format("Last seen about %d m %s of the payphone", math.max(50, math.floor(m / 50 + 0.5) * 50), dir)
    local AF = MCC.AI and MCC.AI.FOB
    if AF and AF.All then
        local best, bestD
        for _, core in ipairs(AF.All()) do
            local d = IsValid(core) and core:GetPos():Distance(pos)
            if d and d < 2500 and (not bestD or d < bestD) then best, bestD = core, d end
        end
        local f = best and AF.Factions and AF.Factions[best:GetNWString("MCCFaction")]
        if f then c.hint = c.hint .. ", near a " .. f.name .. " outpost" end
    end
end

-- What the holder's HUD and the phone screen get.
function C.Payload(c)
    if not c then return nil end
    local p = {id = c.id, name = c.name, unit = c.unit, faction = c.faction, reward = c.reward, state = c.state,
        hint = c.hint, timeLeft = c.expires and math.max(0, c.expires - CurTime()) or -1, escorts = c.guards}
    if c.state == "dead" then
        p.drops = {}
        for _, d in ipairs(IsValid(c.drop) and {c.drop} or C.Drops()) do
            local q = d:GetPos()
            p.drops[#p.drops + 1] = {q.x, q.y, q.z}
            if #p.drops >= 24 then break end
        end
    end
    if IsValid(c.drop) then
        local dir, m = C.Bearing(c.origin, c.drop:GetPos())
        p.dropHint = string.format("The %s about %d m %s of the payphone", c.drop.MCCDropName or "dead drop",
            math.floor(m / 10 + 0.5) * 10, dir)
    end
    return p
end

function C.SendState(ply)
    if IsValid(ply) then MCC.Net.Send("contracts_state", {c = C.Payload(C.Open(ply))}, ply) end
end

local function SendHolder(c)
    local ply = PlayerBySid(c.sid)
    if ply then C.SendState(ply) end
end

local function Close(c, state)
    c.state = state
    C.List[c.id] = nil
    if C.BySid[c.sid] == c then C.BySid[c.sid] = nil end
    C.CooldownUntil[c.sid] = CurTime() + MCC.Config.Get("contracts_cooldown")
    if IsValid(c.target) and c.target.MCCContract == c.id then c.target.MCCContract = nil end
    SendHolder(c)
end

-- origin: where the contract was taken (the phone, or the player for mcc_contracts_test).
-- want: "combine", "rebels" or "any". Returns the contract, or nil and what the voice says instead.
function C.Request(ply, origin, want, phone)
    if not C.Enabled() then return nil, "The line's dead." end
    if want ~= "combine" and want ~= "rebels" then want = "any" end
    local open = C.Open(ply)
    if open then return nil, C.Line(open.state == "dead" and "dead" or "active") end
    if C.CooldownLeft(ply) > 0 then return nil, C.Line("busy") end
    local drops = C.Drops()
    if #drops == 0 then return nil, "Nowhere to leave a tag on this map. (An admin has to place a dead drop.)" end

    local target, escorts = C.FindTarget(origin, want)
    if not IsValid(target) then return nil, C.Line("none") end

    C.NextID = C.NextID + 1
    local now, limit = CurTime(), MCC.Config.Get("contracts_time")
    local guards = math.max(#(escorts or {}), C.Guards(target))
    local lo, hi = MCC.Config.Get("contracts_reward_min"), MCC.Config.Get("contracts_reward_max")
    local reward = lo + math.random() * math.max(0, hi - lo) + guards * MCC.Config.Get("contracts_reward_escort")
    local c = {
        id = C.NextID, sid = ply:SteamID64(), holder = ply:Nick(), target = target, escorts = escorts or {},
        faction = C.FactionOf(target), name = C.NameNPC(target, true), unit = target.MCCUnit or "", guards = guards,
        reward = math.floor(reward / 100 + 0.5) * 100, started = now, expires = limit > 0 and now + limit or nil,
        state = "active", origin = origin, phone = phone, spawned = target.MCCContractSpawn == true,
    }
    if not MCC.Config.Get("contracts_any_drop") then c.drop = drops[math.random(1, #drops)] end
    target.MCCContract = c.id
    C.List[c.id] = c
    C.BySid[c.sid] = c
    C.Ping(c)
    C.SendState(ply)
    hook.Run("MCC_ContractStarted", c, ply)
    return c
end

function C.Fail(c, msg, reason)
    if not C.List[c.id] then return end
    Close(c, "failed")
    if msg then Notify(PlayerBySid(c.sid), msg) end
    hook.Run("MCC_ContractFailed", c, reason or "failed")
end

function C.Abandon(ply)
    local c = C.Open(ply)
    if not c then return false end
    C.Fail(c, nil, "abandoned")
    return true
end

-- Pays roubles: into the inventory, the rest at their feet. Offline: owed until they next use a payphone.
function C.Pay(sid, n, near)
    n = math.floor(tonumber(n) or 0)
    if n <= 0 then return true end
    local ply = PlayerBySid(sid)
    if not IsValid(ply) then
        C.Pending[sid] = (C.Pending[sid] or 0) + n
        return false
    end
    local left = Inv.GiveID(ply, "roubles", n)
    if left > 0 then
        local where = IsValid(near) and near or ply
        Inv.SpawnWorldItem(Inv.NewItem("roubles", left), where:GetPos() + Vector(0, 0, 24), nil)
        Notify(ply, "No room for all of it: %s on the ground", C.Money(left))
    end
    return true
end

function C.Complete(c, depositor)
    if not C.List[c.id] then return end
    Close(c, "done")
    local holder = PlayerBySid(c.sid)
    local online = C.Pay(c.sid, c.reward, holder == depositor and depositor or holder)
    if holder then Notify(holder, "Contract on %s complete: %s paid", c.name, C.Money(c.reward)) end
    if IsValid(depositor) and depositor ~= holder then
        Notify(depositor, "Tag delivered for %s%s", c.holder, online and "" or " (paid when they're back)")
    end
    hook.Run("MCC_ContractCompleted", c, depositor)
end

-- The target died (whoever killed him): his tag is on the body now.
hook.Add("OnNPCKilled", "MCC_Contracts", function(npc, attacker)
    local c = npc.MCCContract and C.List[npc.MCCContract]
    if not c or c.state ~= "active" then return end
    c.state = "dead"
    c.deathPos = npc:GetPos()
    local holder = PlayerBySid(c.sid)
    if holder then
        Notify(holder, "%s is down%s. Take his dogtag to a dead drop", c.name, attacker == holder and "" or " (not by you)")
    end
    SendHolder(c)
end)

function C.Tick()
    local now = CurTime()
    for _, c in pairs(C.List) do
        if c.expires and now >= c.expires then
            C.Fail(c, "Time's up. The contract on " .. c.name .. " is off", "expired")
        elseif c.state == "active" then
            if not IsValid(c.target) then
                C.Fail(c, "Your target's gone. Nobody to collect on. Call again", "lost")
            else
                local every = MCC.Config.Get("contracts_ping_interval")
                if now - (c.pingAt or 0) >= every then
                    C.Ping(c)
                    SendHolder(c)
                end
            end
        end
    end
end
timer.Create("MCC_Contracts", 1, 0, function() C.Tick() end)

-- The target removed without dying (cleanup, an admin): nothing to collect.
hook.Add("EntityRemoved", "MCC_Contracts", function(ent)
    local c = ent.MCCContract and C.List[ent.MCCContract]
    if c and c.state == "active" and c.target == ent then
        C.Fail(c, "Your target's gone. Nobody to collect on. Call again", "lost")
    end
end)

hook.Add("PlayerInitialSpawn", "MCC_Contracts", function(ply)
    timer.Simple(5, function()
        if not IsValid(ply) then return end
        C.SendState(ply)
        local owed = C.Pending[ply:SteamID64()]
        if owed then Notify(ply, "%s waiting for you at any payphone", C.Money(owed)) end
    end)
end)

-- Dead drops ------------------------------------------------------------------------------------------------

function C.SetupDrop(ent, name, w, h)
    ent.MCCDropName = name or "dead drop"
    if not ent.MCCCont then
        ent.MCCCont = {name = "Dead drop", noSearch = true, deaddrop = true, grids = {{w = w or 2, h = h or 2, items = {}}}}
    end
    ent:SetNWString("MCCName", "Dead drop")
end

-- Only dogtags go in, and only ones someone pays for.
function C.CanDeposit(ply, it, ent)
    local def = MCC.Items.Get(it.id)
    if not C.IsDogtag(def) then return false, "Only dogtags go in a dead drop" end
    local d = it.d or {}
    if d.contract then
        local c = C.List[d.contract]
        if not c or c.state ~= "dead" then return false, "That contract's off. Nobody's paying for this one" end
        if IsValid(c.drop) and c.drop ~= ent then return false, "Wrong drop. This one goes in the " .. (c.drop.MCCDropName or "other drop") end
        return true
    end
    if MCC.Config.Get("contracts_tag_bounty") > 0 and (d.side or d.faction) and not d.sid then return true end
    return false, "Nobody's paying for that tag"
end

hook.Add("MCC_CanStore", "MCC_Contracts", function(ply, it, ent)
    if C.IsDrop(ent) then return C.CanDeposit(ply, it, ent) end
end)

-- Collects what's in a drop: contract tags complete their contract, other tags pay the bounty.
function C.Collect(ent, ply)
    local cont = ent.MCCCont
    if not cont or not cont.grids then return 0 end
    local n, bounty = 0, MCC.Config.Get("contracts_tag_bounty")
    for _, g in ipairs(cont.grids) do
        for i = #g.items, 1, -1 do
            local it = g.items[i]
            local d = it.d or {}
            local c = d.contract and C.List[d.contract]
            if c and c.state == "dead" and (not IsValid(c.drop) or c.drop == ent) then
                table.remove(g.items, i)
                C.Complete(c, ply)
                n = n + 1
            elseif not d.contract and (d.side or d.faction) and not d.sid and bounty > 0 and IsValid(ply) then
                table.remove(g.items, i)
                C.Pay(ply:SteamID64(), bounty, ply)
                Notify(ply, "Tag taken: %s", C.Money(bounty))
                n = n + 1
            end
        end
    end
    if n > 0 then
        ent:EmitSound("physics/metal/metal_box_impact_soft2.wav", 60)
        for _, p in ipairs(player.GetAll()) do
            if p == ply or p.MCCInvOpen == ent then Inv.Update(p) end
        end
    end
    return n
end

hook.Add("MCC_ContainerChanged", "MCC_Contracts", function(ent, ply)
    if C.IsDrop(ent) then C.Collect(ent, ply) end
end)

-- Payphones -------------------------------------------------------------------------------------------------

local PHONE_REACH = 160

function C.SendPhone(ply, phone, line)
    local c = C.Open(ply)
    MCC.Net.Send("contracts_phone", {phone = phone:EntIndex(), line = line, c = C.Payload(c),
        cooldown = math.ceil(C.CooldownLeft(ply))}, ply)
end

function C.PhoneUse(ply, phone)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if not C.Enabled() then
        Notify(ply, "The line's dead")
        return
    end
    ply.MCCContractPhone = phone
    phone:EmitSound("buttons/button14.wav", 60)
    local line = C.Line("greet")
    local owed = C.Pending[ply:SteamID64()]
    if owed then
        C.Pending[ply:SteamID64()] = nil
        C.Pay(ply:SteamID64(), owed, phone)
        Notify(ply, "%s paid out", C.Money(owed))
        line = C.Line("owed")
    end
    local c = C.Open(ply)
    if c then line = C.Line(c.state == "dead" and "dead" or "active") end
    C.SendPhone(ply, phone, line)
end

hook.Add("MCC_PickupCustom", "MCC_Contracts", function(ply, ent, kind)
    if kind == "payphone" and C.IsPhone(ent) then C.PhoneUse(ply, ent) end
end)

MCC.Net.Receive("contracts_req", function(data, ply)
    local phone = ply.MCCContractPhone
    if not istable(data) or not C.IsPhone(phone) or ply:GetPos():Distance(phone:GetPos()) > PHONE_REACH then return end
    local line
    if data.a == "take" then
        local c, why = C.Request(ply, phone:GetPos(), data.f, phone)
        line = c and C.Line("offer") or why
        if c then phone:EmitSound("ambient/levels/prison/radio_random" .. math.random(1, 15) .. ".wav", 55) end
    elseif data.a == "abandon" then
        line = C.Abandon(ply) and C.Line("abandon") or C.Line("greet")
    else
        return
    end
    C.SendPhone(ply, phone, line)
end, {allowClient = true, maxBytes = 512})

-- Placing phones and drops (saved per map) --------------------------------------------------------------------

local function MapFile()
    return "contracts_" .. (game.GetMap and game.GetMap() or "map") .. ".json"
end

local function Placeables()
    local list = {}
    for _, e in ipairs(ents.FindByClass(C.PHONE_CLASS)) do list[#list + 1] = e end
    for _, e in ipairs(C.Drops()) do list[#list + 1] = e end
    return list
end

function C.SaveMap()
    local out = {}
    for _, e in ipairs(Placeables()) do
        local p, a = e:GetPos(), e:GetAngles()
        out[#out + 1] = {class = e:GetClass(), pos = {p.x, p.y, p.z}, yaw = a.y or a[2] or 0}
    end
    MCC.Data.WriteJSON(MapFile(), out)
    return #out
end

function C.LoadMap()
    local list = MCC.Data.ReadJSON(MapFile())
    local n = 0
    for _, e in ipairs(istable(list) and list or {}) do
        if istable(e) and C.LEGACY_DROPS[e.class] then e.class = C.LEGACY_DROPS[e.class] end
        if istable(e) and (e.class == C.PHONE_CLASS or C.DROP_CLASSES[e.class]) and istable(e.pos) then
            local ent = ents.Create(e.class)
            if IsValid(ent) then
                ent:SetPos(Vector(tonumber(e.pos[1]) or 0, tonumber(e.pos[2]) or 0, tonumber(e.pos[3]) or 0))
                ent:SetAngles(Angle(0, tonumber(e.yaw) or 0, 0))
                ent:Spawn()
                ent:Activate()
                n = n + 1
            end
        end
    end
    return n
end
hook.Add("InitPostEntity", "MCC_Contracts", function() C.LoadMap() end)
hook.Add("PostCleanupMap", "MCC_Contracts", function() C.LoadMap() end)

-- Commands --------------------------------------------------------------------------------------------------

MCC.Command("contracts_save", "MCC Admin", "", "Saves the payphones and dead drops on this map; they come back every session.",
function(ply)
    MCC.Util.Reply(ply, "Saved %d payphones and dead drops for this map.", C.SaveMap())
end)

MCC.Command("contracts_reload", "MCC Admin", "", "Re-reads data/mcc/contracts.json and contracts_names.json.", function(ply)
    C.LoadData()
    MCC.Util.Reply(ply, "Contracts data reloaded.")
end)

MCC.Command("contracts_list", "MCC Moderator", "", "Lists the open contracts.", function(ply)
    local n = 0
    for _, c in pairs(C.List) do
        n = n + 1
        MCC.Util.Reply(ply, "#%d %s -> %s (%s), %s, %s%s", c.id, c.holder, c.name, c.unit, c.state, C.Money(c.reward),
            c.expires and string.format(", %ds left", math.max(0, math.floor(c.expires - CurTime()))) or "")
    end
    if n == 0 then MCC.Util.Reply(ply, "No open contracts.") end
end)

MCC.Command("contracts_cancel", "MCC Admin", "<player name|all>", "Calls off a player's contract (or everyone's).", function(ply, args)
    local who = string.lower(table.concat(args or {}, " "))
    if who == "" then return MCC.Util.Reply(ply, "Usage: mcc_contracts_cancel <player name|all>") end
    local n = 0
    for _, c in pairs(table.Copy(C.List)) do
        if who == "all" or string.find(string.lower(c.holder), who, 1, true) then
            C.Fail(C.List[c.id], "An admin called off your contract", "cancelled")
            n = n + 1
        end
    end
    MCC.Util.Reply(ply, "Cancelled %d contract(s).", n)
end)

MCC.Command("contracts_names", "MCC Moderator", "[count] [soldier|elite|cp|rebel]", "Prints some names from the pools.",
function(ply, args)
    local n = math.Clamp(tonumber(args and args[1]) or 10, 1, 100)
    local only = args and args[2]
    local kinds = {"soldier", "elite", "cp", "rebel"}
    for i = 1, n do
        local kind = (only and C.UNIT_NAMES[only]) and only or kinds[(i - 1) % #kinds + 1]
        MCC.Util.Reply(ply, "%-14s %s", C.UNIT_NAMES[kind], C.MakeName(kind))
    end
    MCC.Util.Reply(ply, "Possible names: %d soldier, %d elite, %d Civil Protection, %d rebel.", C.NameCount("soldier"),
        C.NameCount("elite"), C.NameCount("cp"), C.NameCount("rebel"))
end)

MCC.Command("contracts_test", "MCC Admin", "[combine|rebels|any]", "Gives you a contract as if you'd called from where you stand.",
function(ply, args)
    if not IsValid(ply) then return end
    local c, why = C.Request(ply, ply:GetPos(), args and args[1] or "any")
    if c then
        MCC.Util.Reply(ply, "Contract #%d: %s (%s), %s. %s", c.id, c.name, c.unit, C.Money(c.reward), c.hint or "")
    else
        MCC.Util.Reply(ply, "No contract: %s", why or "?")
    end
end)
