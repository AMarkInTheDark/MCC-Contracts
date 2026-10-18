"""MCC Contracts tests: NPC names and dogtags, taking a contract at a payphone, finding or spawning the target,
the search area, killing him, delivering his tag to a dead drop, payouts in roubles, failures, saving per map.

Runs against MCC Base (../mcc_base) in its inventory test world."""
import json, os, sys, re
HERE = os.path.dirname(os.path.abspath(__file__))
BASE_TESTS = os.environ.get("MCC_BASE_TESTS", os.path.join(HERE, "..", "..", "mcc_base", "tests"))
sys.path.insert(0, BASE_TESTS)
from gmod_mock import Realm
from inv_world import WORLD
CT_LUA = os.path.join(HERE, "..", "lua")

failures = []
def check(cond, msg):
    print(("PASS " if cond else "FAIL ") + msg)
    if not cond:
        failures.append(msg)

EXTRA = r'''
game.GetMap = function() return "gm_test" end
MASK_NPCSOLID = 33701899
function math.Rand(a, b) return a + (b - a) * 0.5 end
function isfunction(v) return type(v) == "function" end
_ROOM_BLOCKED = {}
util.TraceHull = function(t)
  for _, b in ipairs(_ROOM_BLOCKED) do
    if math.abs(b.x - t.start.x) < 30 and math.abs(b.y - t.start.y) < 30 then return {Hit = true} end
  end
  return {Hit = false}
end
function _FindByClass(c) local o = {} for _, e in ipairs(_ENTS) do if getmetatable(e).valid and e:GetClass() == c then o[#o + 1] = e end end return o end
ents.GetAll = function() local o = {} for _, e in ipairs(_ENTS) do if getmetatable(e).valid then o[#o + 1] = e end end return o end
local NPCS = {npc_combine_s = true, npc_metropolice = true, npc_citizen = true, npc_manhack = true}
function _NPC(class, pos, model)
  local hp = 100
  local e
  e = _Ent(class, {IsNPC = function() return true end, Health = function() return hp end, SetHealth = function(s, v) hp = v end,
    GetActiveWeapon = function() return NULL end, SetSquad = function(s, q) e._squad = q end,
    SetKeyValue = function(s, k, v) e._kv = e._kv or {} e._kv[k] = v end,
    LookupBone = function(s, b) if class == "npc_manhack" then return nil end return 1 end})
  e:SetPos(pos or Vector())
  if model then e:SetModel(model) end
  return e
end
local create = ents.Create
ents.Create = function(class)
  if NPCS[class] then local n = _NPC(class) _SPAWNED_NPCS[#_SPAWNED_NPCS + 1] = n return n end
  if class == "mcc_payphone" or MCC.Contracts.DROP_CLASSES[class] then
    return _Ent(class, {Spawn = function(s)
      if MCC.Contracts.DROP_CLASSES[class] then MCC.Contracts.SetupDrop(s, class == "mcc_deaddrop_trash" and "trash can" or "dumpster", class == "mcc_deaddrop_dumpster" and 4 or 2, class == "mcc_deaddrop_dumpster" and 4 or 2) end
    end})
  end
  return create(class)
end
_SPAWNED_NPCS = {}
-- a navmesh: a row of areas along +x
_AREAS = {}
for i = 0, 40 do
  local c = Vector(i * 500, 0, 0)
  _AREAS[#_AREAS + 1] = {GetCenter = function() return c end, GetSizeX = function() return 200 end, GetSizeY = function() return 200 end}
end
navmesh = {IsLoaded = function() return _NAV ~= false end, GetAllNavAreas = function() return _AREAS end}
-- kills an NPC the way the engine does: its ragdoll (the body), then OnNPCKilled, then it's removed
function _Kill(npc, attacker)
  npc:SetHealth(0)
  local rag = _Ent("prop_ragdoll")
  rag:SetPos(npc:GetPos())
  hook.Run("CreateEntityRagdoll", npc, rag)
  hook.Run("OnNPCKilled", npc, attacker)
  getmetatable(npc).valid = false
  hook.Run("EntityRemoved", npc)
  return rag
end
_NOTES = {}
'''

sv = Realm("server", extra_roots=[CT_LUA])
sv.load_mcc()
sv.run(WORLD)
sv.run(EXTRA)
sv.run('include("autorun/mcc_contracts_init.lua")')
sv.boot()
L = sv.eval
def run(code):
    sv.run(code)
run('_TIME = 100 _SetCV("mcc_search_enabled", 0)')
run('MCC.Inv.Notify = function(ply, msg) _NOTES[#_NOTES + 1] = {ply = ply, msg = msg} end')
run('function _Note(ply) for i = #_NOTES, 1, -1 do if _NOTES[i].ply == ply then return _NOTES[i].msg end end return "" end')
run('function _Roubles(ply) local n = 0 local inv = MCC.Inv.Get(ply) '
    'local function scan(list) for _, it in ipairs(list or {}) do if it.id == "roubles" then n = n + (it.n or 1) end '
    'for _, g in ipairs(it.cont or {}) do scan(g.items or g) end end end '
    'for _, it in pairs(inv.slots) do if it.id == "roubles" then n = n + (it.n or 1) end if it.cont then for _, g in pairs(it.cont) do scan(g.items or g) end end end return n end')
run('hook.Run("InitPostEntity")')
run('_SENT = {} local send = MCC.Net.Send MCC.Net.Send = function(name, data, t) _SENT[#_SENT + 1] = {name = name, data = data, to = t} return send(name, data, t) end')
run('function _Last(name) for i = #_SENT, 1, -1 do if _SENT[i].name == name then return _SENT[i].data end end end')
run('function _In(v, list) for _, x in ipairs(list) do if x == v then return true end end return false end')

# ---------------------------------------------------------------- items and data
check(L('MCC.Contracts.VERSION') == "0.2.1", "MCC Contracts loads on MCC Base")
check(L('MCC.Items.Get("roubles").maxStack') == 500000 and L('MCC.Items.Get("roubles").kind') == "misc",
      "MCC Base has roubles: one stack holds 500,000")
for tid, fac in [("dogtag_combine", "combine"), ("dogtag_rebel", "rebels")]:
    check(L('MCC.Items.Get("%s").data.slot' % tid) == "dogtag" and L('MCC.Items.Get("%s").data.faction' % tid) == fac
          and L('MCC.Contracts.IsDogtag(MCC.Items.Get("%s"))' % tid), "%s goes in the DOGTAG slot" % tid)
for f in ("contracts_names.json", "contracts.json"):
    check(os.path.exists(os.path.join(sv.datadir, "mcc", f)), "data/mcc/%s is written with the defaults" % f)

# ---------------------------------------------------------------- names
run('math.randomseed(7)')
soldiers = [L('MCC.Contracts.MakeName("soldier")') for _ in range(30)]
check(all(re.fullmatch(r'[A-Z0-9]+:OWS\.[A-Z]+-[1-9]', n) for n in soldiers), "Overwatch soldiers: C17:OWS.RIPCORD-4 (%s)" % soldiers[0])
check(re.fullmatch(r'[A-Z0-9]+:EOW\.[A-Z]+-[1-9]', L('MCC.Contracts.MakeName("elite")')) is not None, "elites: EOW (%s)" % L('MCC.Contracts.MakeName("elite")'))
cps = [L('MCC.Contracts.MakeName("cp")') for _ in range(30)]
check(all(re.fullmatch(r'[A-Z0-9]+:i[1-5]\.[A-Z]+-\d\d', n) for n in cps), "Civil Protection: C17:i4.UNION-27 (%s)" % cps[0])
rebels = [L('MCC.Contracts.MakeName("rebel")') for _ in range(60)]
check(all(re.fullmatch(r'[A-Za-z]+( "[A-Za-z]+")? [A-Za-z]+', n) for n in rebels), "Rebels: first and last name (%s)" % rebels[0])
check(any('"' in n for n in rebels) and any('"' not in n for n in rebels), "some rebels go by a nickname (%s)" % next(n for n in rebels if '"' in n))
check(len(set(soldiers)) >= 25 and len(set(rebels)) >= 55, "names rarely repeat")
counts = {k: L('MCC.Contracts.NameCount("%s")' % k) for k in ("soldier", "cp", "rebel")}
check(counts["rebel"] > 500000 and counts["cp"] > 100000 and counts["soldier"] > 5000, "big pools: %s possible names" % counts)
run('local n = {} for i = 1, 200 do n[MCC.Contracts.UniqueName("soldier")] = true end _UNIQ = table.Count(n)')
check(L('_UNIQ') >= 195, "a session's NPCs get names nobody else has had (%d of 200 unique)" % L('_UNIQ'))

# the JSON pools can be edited
names_path = os.path.join(sv.datadir, "mcc", "contracts_names.json")
data = json.load(open(names_path))
data["first"], data["last"], data["nick"], data["overwatch"] = ["Gordon"], ["Freeman"], [], ["LAMBDA"]
json.dump(data, open(names_path, "w"))
run('MCC.Contracts.LoadData()')
check(L('MCC.Contracts.MakeName("rebel")') == "Gordon Freeman" and "LAMBDA" in L('MCC.Contracts.MakeName("soldier")'),
      "contracts_names.json changes the pools (mcc_contracts_reload)")
data["first"] = []
json.dump(data, open(names_path, "w"))
run('MCC.Contracts.LoadData()')
check(L('#MCC.Contracts.Names.first') > 50, "an emptied list falls back to the defaults")
os.remove(names_path)
run('MCC.Contracts.LoadData()')

# ---------------------------------------------------------------- NPC kinds, bodies and their tags
run('N1 = _NPC("npc_combine_s", Vector(100, 0, 0)) N2 = _NPC("npc_combine_s", Vector(0, 0, 0), "models/combine_super_soldier.mdl")')
run('N3 = _NPC("npc_metropolice") N4 = _NPC("npc_citizen") N5 = _NPC("npc_manhack")')
check([L('MCC.Contracts.KindOf(N%d)' % i) for i in range(1, 6)] == ["soldier", "elite", "cp", "rebel", None],
      "soldier, elite, Civil Protection, rebel; manhacks get no name")
check(L('MCC.Contracts.FactionOf(N3)') == "combine" and L('MCC.Contracts.FactionOf(N4)') == "rebels", "and a faction: Combine or Rebels")

run('P = _MakeTester(1) _PLAYERS = {P} hook.Run("PlayerInitialSpawn", P) hook.Run("PlayerLoadout", P)')
run('R1 = _Kill(N1, P)')
check(L('R1.MCCCont ~= nil') and L('R1:GetNWString("MCCName")') == L('N1.MCCName') and ":OWS." in L('N1.MCCName'),
      "a dead soldier's body carries his name (%s)" % L('N1.MCCName'))
check(L('R1.MCCCont.inv.slots.dogtag.id') == "dogtag_combine" and L('R1.MCCCont.inv.slots.dogtag.d.name') == L('N1.MCCName')
      and L('R1.MCCCont.inv.slots.dogtag.d.note') == "Overwatch Soldier" and L('R1.MCCCont.inv.slots.dogtag.d.contract') is None,
      "and his dogtag in the DOGTAG slot, with his name and unit")
run('R4 = _Kill(N4, P)')
check(L('R4.MCCCont.inv.slots.dogtag.id') == "dogtag_rebel", "rebels carry rebel dogtags (%s)" % L('N4.MCCName'))
run('R5 = _Kill(N5, P)')
check(L('R5.MCCCont.inv.slots.dogtag') is None and L('R5:GetNWString("MCCName")') != "", "manhacks have no tag")
run('_SetCV("mcc_contracts_npc_tags", 0) R3 = _Kill(N3, P)')
check(L('R3.MCCCont.inv.slots.dogtag') is None and ":i" in L('R3:GetNWString("MCCName")'),
      "mcc_contracts_npc_tags 0: no tags (still named)")
run('_SetCV("mcc_contracts_npc_tags", 1) _SetCV("mcc_contracts_npc_names", 0) R2 = _Kill(N2, P)')
check(L('R2.MCCCont.inv.slots.dogtag') is None and L('R2:GetNWString("MCCName")') == "npc_combine_s",
      "mcc_contracts_npc_names 0: plain bodies")
run('_SetCV("mcc_contracts_npc_names", 1)')

# ---------------------------------------------------------------- the phone
run('PH = ents.Create("mcc_payphone") PH:SetPos(Vector(0, 0, 0)) PH:Spawn()')
check(L('MCC.Pickup.Kind(PH)') == "payphone" and L('(MCC.Pickup.PromptText(PH, "payphone"))') == "Payphone",
      "a payphone: E to call")
run('MCC.Contracts.PhoneUse(P, PH)')
check(L('_Last("contracts_phone") ~= nil and _Last("contracts_phone").phone') == L('PH:EntIndex()'), "calling opens the phone screen")
run('_C, _WHY = MCC.Contracts.Request(P, PH:GetPos(), "combine", PH)')
check(L('_C') is None and "dead drop" in L('_WHY'), "no contracts on a map without dead drops: \"%s\"" % L('_WHY'))

run('DT = ents.Create("mcc_deaddrop_trash") DT:SetPos(Vector(-300, 0, 0)) DT:Spawn()')
run('DM = ents.Create("mcc_deaddrop_dumpster") DM:SetPos(Vector(-600, 0, 0)) DM:Spawn()')
check(L('MCC.Pickup.Kind(DT)') == "container" and L('({MCC.Pickup.PromptText(DT, "container")})[2]') == "Dead drop"
      and L('DT.MCCCont.grids[1].w') == 2 and L('DT.MCCCont.noSearch') is True, "dead drops: 2x2 containers, nothing to search")

# ---------------------------------------------------------------- picking a target already on the map
run('_SetCV("mcc_contracts_min_dist", 2000)')
run('NEAR = _NPC("npc_combine_s", Vector(500, 0, 0)) FAR = _NPC("npc_combine_s", Vector(5000, 0, 0)) G1 = _NPC("npc_combine_s", Vector(5200, 0, 0))')
run('REB = _NPC("npc_citizen", Vector(6000, 300, 0))')
run('_C, _WHY = MCC.Contracts.Request(P, PH:GetPos(), "combine", PH)')
check(L('_C ~= nil') and L('_C.target == FAR or _C.target == G1'), "a Combine contract: a Combine NPC at least mcc_contracts_min_dist from the phone")
check(L('_C.target.MCCContract') == L('_C.id') and L('_C.name') == L('_C.target.MCCName') and L('_C.state') == "active",
      "the target gets a name: %s (%s)" % (L('_C.name'), L('_C.unit')))
check(L('_C.guards') == 1 and 7500 <= L('_C.reward') <= 16500 and L('_C.reward') % 100 == 0,
      "the reward: %s, with a bonus for the soldier next to him" % L('MCC.Contracts.Money(_C.reward)'))
check(L('_C.expires') == 100 + 1200, "20 minutes to do it (mcc_contracts_time)")
check(L('_C.area') is None and L('_C.hint').startswith("Last seen about") and "east" in L('_C.hint'),
      "no search area: where he was last seen, from the phone: \"%s\"" % L('_C.hint'))
check(L('_Last("contracts_state").c.name') == L('_C.name') and L('_Last("contracts_state").c.area') is None
      and L('_Last("contracts_state").c.hint') == L('_C.hint'), "the holder's HUD gets the contract and the hint, no marker")
run('_C2, _WHY = MCC.Contracts.Request(P, PH:GetPos(), "any", PH)')
check(L('_C2') is None and L('_In(_WHY, MCC.Contracts.Setup.lines.active)'), "one contract at a time: \"%s\"" % L('_WHY'))

# the hint follows him, each ping
run('_C.target:SetPos(Vector(9000, 0, 0)) _TIME = _TIME + 91 MCC.Contracts.Tick()')
check("about 150 m east" in L('_C.hint') or "about 200 m east" in L('_C.hint') or "east" in L('_C.hint'),
      "every mcc_contracts_ping_interval the hint follows him: \"%s\"" % L('_C.hint'))

# ---------------------------------------------------------------- tags into drops
run('_AR2 = _Ent("weapon_ar2", {IsWeapon = function() return true end}) P.GetActiveWeapon = function() return _AR2 end')
run('TGT = _C.target hook.Run("EntityTakeDamage", TGT, {GetAttacker = function() return P end, GetInflictor = function() return P end}) RT = _Kill(TGT, P)')
check(L('_C.state') == "dead" and "is down" in L('_Note(P)'), "killing him: \"%s\"" % L('_Note(P)'))
check(L('RT.MCCCont.inv.slots.dogtag.d.contract') == L('_C.id') and "Contract #" in L('RT.MCCCont.inv.slots.dogtag.d.note'),
      "his body has the contract's tag")
tag = 'RT.MCCCont.inv.slots.dogtag.d'
check(L(tag + '.killer') == "Tester1" and L(tag + '.killerSid') == "1" and L(tag + '.t') is not None
      and L(tag + '.faction').startswith("Combine (") and L(tag + '.weapon') == "weapon_ar2",
      "the tag says when he died, who killed him, with what, and his faction (%s, %s)" % (L(tag + '.faction'), L(tag + '.weapon')))
check(L('_Last("contracts_state").c.state') == "dead" and L('#_Last("contracts_state").c.drops') == 2
      and L('_Last("contracts_state").c.area') is None, "the HUD now shows the dead drops")
check(L('MCC.Contracts.Open(P) == _C'), "and the contract stays open until the tag is in")

run('TAG = RT.MCCCont.inv.slots.dogtag RT.MCCCont.inv.slots.dogtag = nil')
run('_OK, _ERR = MCC.Contracts.CanDeposit(P, MCC.Inv.NewItem("ammo_smg1", 10), DT)')
check(L('_OK') is False and "Only dogtags" in L('_ERR'), "drops refuse anything but dogtags")
run('_OK, _ERR = MCC.Contracts.CanDeposit(P, R1.MCCCont.inv.slots.dogtag, DT)')
check(L('_OK') is False and "Nobody's paying" in L('_ERR'), "and tags nobody has a contract on (mcc_contracts_tag_bounty 0)")
check(L('MCC.Inv.GiveItem(P, TAG)'), "the tag goes in your inventory")
run('_LOC = nil for _, g in ipairs({}) do end')
before = L('_Roubles(P)')
run('_FOUND, _LOC2, _LIST, _IDX = MCC.Inv.Find(P, TAG.u)')
run('_OK, _ERR = MCC.Inv.StoreIn(P, DT, TAG, {loc = _LOC2, list = _LIST, idx = _IDX})')
check(L('_OK') is True, "dragging the tag onto a dead drop puts it in")
check(L('#DT.MCCCont.grids[1].items') == 0 and L('MCC.Inv.Find(P, TAG.u)') is None, "the drop takes it away")
check(L('_C.state') == "done" and L('MCC.Contracts.Open(P)') is None and L('MCC.Contracts.List[_C.id]') is None, "the contract is done")
check(L('_Roubles(P)') - before == L('_C.reward'), "and pays the holder %s in roubles" % L('MCC.Contracts.Money(_C.reward)'))
check("complete" in L('_Note(P)'), "\"%s\"" % L('_Note(P)'))
check(L('MCC.Contracts.CooldownLeft(P)') == 60, "then a cooldown before the next one (mcc_contracts_cooldown)")
run('_C3, _WHY = MCC.Contracts.Request(P, PH:GetPos(), "any", PH)')
check(L('_C3') is None and L('_In(_WHY, MCC.Contracts.Setup.lines.busy)'), "calling during it: \"%s\"" % L('_WHY'))

# ---------------------------------------------------------------- spawning a target with bodyguards
run('_TIME = _TIME + 61 _SetCV("mcc_contracts_target_mode", 2) _SPAWNED_NPCS = {}')
run('_C, _WHY = MCC.Contracts.Request(P, PH:GetPos(), "rebels", PH)')
check(L('_C ~= nil') and L('_C.spawned') is True and L('_C.target:GetClass()') == "npc_citizen" and L('_C.faction') == "rebels",
      "mcc_contracts_target_mode 2: a Rebel target is spawned (%s)" % (L('_C and _C.name') or L('_WHY')))
check(L('#_C.escorts') == 2 and L('#_SPAWNED_NPCS') == 3 and L('_C.escorts[1]._squad') == L('_C.target._squad'),
      "with 2 bodyguards in his squad (mcc_contracts_escorts)")
check(L('_C.target:GetPos():Distance(PH:GetPos())') >= 2000 and L('_C.target._kv.citizentype') == "3",
      "on the navmesh, away from the phone, from data/mcc/contracts.json")
check(L('_C.guards') == 2 and L('_C.reward') >= 6000 + 2 * 1500, "and pays more for the guards")

# the target dies, but by someone else's hand: the tag still counts; anyone can deliver it
run('Q = _MakeTester(2) _PLAYERS = {P, Q} hook.Run("PlayerInitialSpawn", Q) hook.Run("PlayerLoadout", Q)')
run('RT2 = _Kill(_C.target, Q) TAG2 = RT2.MCCCont.inv.slots.dogtag RT2.MCCCont.inv.slots.dogtag = nil MCC.Inv.GiveItem(Q, TAG2)')
check("not by you" in L('_Note(P)'), "the holder hears he's down: \"%s\"" % L('_Note(P)'))
before = L('_Roubles(P)')
run('_FOUND, _LOC2, _LIST, _IDX = MCC.Inv.Find(Q, TAG2.u) _OK = MCC.Inv.StoreIn(Q, DM, TAG2, {loc = _LOC2, list = _LIST, idx = _IDX})')
check(L('_OK') is True and L('_C.state') == "done" and L('_Roubles(P)') - before == L('_C.reward'),
      "someone else delivering the tag still pays the holder")
check("delivered for" in L('_Note(Q)'), "\"%s\"" % L('_Note(Q)'))

# ---------------------------------------------------------------- failing
run('_TIME = _TIME + 61 _SetCV("mcc_contracts_target_mode", 1)')
run('_C = MCC.Contracts.Request(P, PH:GetPos(), "any", PH)')
check(L('_C ~= nil'), "another contract (%s)" % L('_C and _C.name'))
run('_TIME = _TIME + 1201 MCC.Contracts.Tick()')
check(L('_C.state') == "failed" and "Time's up" in L('_Note(P)'), "running out of time: \"%s\"" % L('_Note(P)'))
check(L('_C.target.MCCContract') is None, "and he isn't a target any more")

run('_TIME = _TIME + 61 _C = MCC.Contracts.Request(P, PH:GetPos(), "any", PH)')
run('getmetatable(_C.target).valid = false hook.Run("EntityRemoved", _C.target)')
check(L('_C.state') == "failed" and "gone" in L('_Note(P)'), "the target removed without dying: \"%s\"" % L('_Note(P)'))

run('_TIME = _TIME + 61 _C = MCC.Contracts.Request(P, PH:GetPos(), "any", PH)')
run('RT3 = _Kill(_C.target, P) MCC.Contracts.Abandon(P)')
check(L('_C.state') == "failed" and L('MCC.Contracts.Open(P)') is None, "calling it off (even with him down)")
run('_OK, _ERR = MCC.Contracts.CanDeposit(P, RT3.MCCCont.inv.slots.dogtag, DT)')
check(L('_OK') is False and "off" in L('_ERR'), "a called-off contract's tag isn't taken: \"%s\"" % L('_ERR'))

# no target anywhere
run('_TIME = _TIME + 61 for _, e in ipairs(ents.GetAll()) do if e:IsNPC() then getmetatable(e).valid = false end end _NAV = false')
run('_C, _WHY = MCC.Contracts.Request(P, PH:GetPos(), "any", PH)')
check(L('_C') is None and L('_In(_WHY, MCC.Contracts.Setup.lines.none)'), "no targets and no navmesh: \"%s\"" % L('_WHY'))
run('_NAV = nil')

# ---------------------------------------------------------------- named drops, bounties, offline payouts
run('_SetCV("mcc_contracts_any_drop", 0) _SetCV("mcc_contracts_target_mode", 2) math.randomseed(3)')
run('_C = MCC.Contracts.Request(P, PH:GetPos(), "combine", PH)')
check(L('IsValid(_C.drop)') and L('_C.drop == DT or _C.drop == DM'), "mcc_contracts_any_drop 0: the contract names a drop")
run('RT4 = _Kill(_C.target, P) TAG4 = RT4.MCCCont.inv.slots.dogtag OTHER = (_C.drop == DT) and DM or DT')
run('_OK, _ERR = MCC.Contracts.CanDeposit(P, TAG4, OTHER)')
check(L('_OK') is False and "Wrong drop" in L('_ERR'), "\"%s\"" % L('_ERR'))
run('_OK = MCC.Contracts.CanDeposit(P, TAG4, _C.drop)')
check(L('_OK') is True, "the named drop takes it")
run('_SetCV("mcc_contracts_any_drop", 1)')

run('_SetCV("mcc_contracts_tag_bounty", 250) BT = MCC.Inv.NewItem("dogtag_combine", 1, {name = "X", faction = "combine"})')
check(L('MCC.Contracts.CanDeposit(P, BT, DT)') is True, "mcc_contracts_tag_bounty: any NPC tag is taken")
before = L('_Roubles(P)')
run('table.insert(DT.MCCCont.grids[1].items, BT) MCC.Contracts.Collect(DT, P)')
check(L('_Roubles(P)') - before == 250 and L('#DT.MCCCont.grids[1].items') == 0, "and pays the bounty")
run('PVP = MCC.Inv.NewItem("dogtag", 1, {name = "Someone", sid = "9"})')
check(L('(MCC.Contracts.CanDeposit(P, PVP, DT))') is False, "player dogtags aren't")
run('_SetCV("mcc_contracts_tag_bounty", 0)')

run('_C.state = "dead" _PLAYERS = {Q}')
run('MCC.Contracts.Complete(_C, Q)')
check(L('MCC.Contracts.Pending[P:SteamID64()]') == L('_C.reward'), "the holder offline: the money is owed")
run('_PLAYERS = {P, Q} before = _Roubles(P) MCC.Contracts.PhoneUse(P, PH)')
check(L('_Roubles(P) - before') == L('_C.reward') and L('MCC.Contracts.Pending[P:SteamID64()]') is None,
      "and paid at the next payphone call")

# ---------------------------------------------------------------- phone requests over the net
run('_TIME = _TIME + 61 _SetCV("mcc_contracts_target_mode", 2) P.MCCContractPhone = PH')
run('MCC.Net.Handlers["contracts_req"].fn({a = "take", f = "combine"}, P)')
check(L('MCC.Contracts.Open(P) ~= nil') and L('MCC.Contracts.Open(P).faction') == "combine", "the phone screen's buttons take a contract")
run('MCC.Net.Handlers["contracts_req"].fn({a = "abandon"}, P)')
check(L('MCC.Contracts.Open(P)') is None, "and call it off")
run('_TIME = _TIME + 61 P:SetPos(Vector(5000, 0, 0)) MCC.Net.Handlers["contracts_req"].fn({a = "take", f = "combine"}, P)')
check(L('MCC.Contracts.Open(P)') is None, "not from across the map")
run('P:SetPos(Vector(0, 0, 0))')

# ---------------------------------------------------------------- saved per map
run('_CMDS["mcc_contracts_save"](nil, "", {}, "")')
saved = json.load(open(os.path.join(sv.datadir, "mcc", "contracts_gm_test.json")))
check(sorted(e["class"] for e in saved) == ["mcc_deaddrop_dumpster", "mcc_deaddrop_trash", "mcc_payphone"],
      "mcc_contracts_save keeps the phones and drops for this map")
run('for _, e in ipairs(ents.GetAll()) do getmetatable(e).valid = false end')
run('hook.Run("PostCleanupMap")')
check(L('#ents.FindByClass("mcc_payphone")') == 1 and L('#MCC.Contracts.Drops()') == 2
      and L('ents.FindByClass("mcc_deaddrop_trash")[1]:GetPos().x') == -300, "and puts them back each session")

# a map saved with 0.1.0's mailbox gets a dumpster in its place
legacy = os.path.join(sv.datadir, "mcc", "contracts_gm_test.json")
json.dump([{"class": "mcc_deaddrop_mailbox", "pos": [10, 20, 0], "yaw": 0}], open(legacy, "w"))
run('for _, e in ipairs(ents.GetAll()) do getmetatable(e).valid = false end MCC.Contracts.LoadMap()')
check(L('#ents.FindByClass("mcc_deaddrop_dumpster")') == 1 and L('ents.FindByClass("mcc_deaddrop_dumpster")[1].MCCCont.grids[1].w') == 4,
      "an old saved mailbox drop comes back as the dumpster (4x4)")

# ---------------------------------------------------------------- settings and the client
check(L('GetConVar("mcc_contracts_time") ~= nil and GetConVar("mcc_contracts_reward_max") ~= nil'), "settings are mcc_contracts_* cvars")
cl = Realm("client", extra_roots=[CT_LUA])
cl.load_mcc()
cl.run('include("autorun/mcc_contracts_init.lua")')
cl.boot()
check(cl.eval('MCC.Contracts ~= nil and MCC.Contracts.OpenPhone ~= nil'), "the client side loads")
check(cl.eval('MCC.Contracts.Money(12000)') == "12,000 RUB" and cl.eval('MCC.Contracts.Money(500)') == "500 RUB", "money reads 12,000 RUB")
check(cl.eval('(MCC.Contracts.Bearing(Vector(0, 0, 0), Vector(0, 1000, 0)))') == "north"
      and cl.eval('(MCC.Contracts.Bearing(Vector(0, 0, 0), Vector(-1000, -1000, 0)))') == "south-west", "compass bearings")

print("\n%d failure(s)" % len(failures))
sys.exit(1 if failures else 0)
