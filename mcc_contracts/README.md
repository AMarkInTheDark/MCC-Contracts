# MCC Contracts 0.2.1

**0.2.1:** spawned targets never appear in (or within 300 units of) a safe zone (MCC Traders' trader zones).

Kill contracts for MCC. Call a payphone and the voice on the line gives you a name: a Combine unit or a Rebel. Find
him, kill him, take his dogtag off the body, and leave it in a dead drop (a trash can or a dumpster). Then you get paid
in roubles.

Needs **MCC Base 0.13.0** or later, for the roubles item and named NPC bodies. Works with or without MCC AI Behaviors
and ZBase.

## The loop
1. **Call.** Press E on a payphone and ask for a Combine name, a Rebel name, or "whoever pays".
2. **Hunt.** Your HUD shows the target's name, unit, reward and time left, and where he was last seen. There's
   no marker on screen.
   - The "last seen" line updates as he moves, every 90 s.
   - The text hint gives the distance and direction from the phone ("about 650 m north-east of the payphone"), and
     says which outpost he's near if MCC AI Behaviors is installed.
   - Once he's down, dead drops get a marker within 25 m. Further out, the panel says which way the nearest one is.
3. **Kill.** Anyone can kill him; what counts is the tag. His body has it in the DOGTAG slot, marked "Contract #n".
4. **Deliver.** Drag the tag into any dead drop, or open the drop with E and put it in. The holder is paid straight into
   their inventory; whatever doesn't fit lands at their feet.
   - Someone else can deliver it for you; you still get paid.
   - If you're offline, the money waits for you at the next payphone you call from.

The contract fails if time runs out, if the target disappears without dying (cleaned up, removed by an admin), or if
you call it off at the phone. After any contract there's a short cooldown.

## Targets
- `mcc_contracts_target_mode`:
  - 0: only NPCs already on the map
  - 1 (default): those first, otherwise spawn one
  - 2: always spawn one
- **Existing NPCs:** a random Combine or Rebel NPC at least `mcc_contracts_min_dist` from the phone. Any of his friends
  standing nearby add to the reward.
- **Spawned targets:** one man with `mcc_contracts_escorts` bodyguards in his squad, on the navmesh, away from every
  player.
  - What they are (class, weapons, keyvalues, weights) is in `data/mcc/contracts.json`, per faction.
  - Spawning needs a navmesh (`nav_generate`).
  - With MCC AI Behaviors they join their faction, so they fight its enemies.

## Names and dogtags
Every Combine and Rebel NPC gets a name from the Half-Life 2-flavoured pools, shown on its body. Its body also carries
its dogtag (`mcc_contracts_npc_tags` is the chance).

| Unit | Example | Possible names |
|---|---|---|
| Overwatch Soldier | `C17:OWS.RIPCORD-4` | about 7,000 |
| Overwatch Elite | `C17:EOW.REAPER-1` | about 1,300 |
| Civil Protection | `C17:i4.UNION-27` (i5 lowest rank, i1 highest) | about 285,000 |
| Rebel | `Pavel "Static" Horvat` | about 620,000 |

- Names don't repeat within a session.
- Manhacks, hunters, turrets and the like get no name.
- The pools (sectors, Overwatch and Civil Protection callsigns, first names, last names, nicknames, the nickname
  chance) are in `data/mcc/contracts_names.json`. Edit them, then run `mcc_contracts_reload`.
- `mcc_contracts_names 20` prints some names.
- Two items: **Dogtag (Combine)** and **Dogtag (Rebel)**. They fit the DOGTAG slot and are worth 150 each. The tooltip
  shows the name and unit.
- Inspecting a dogtag shows its name, faction and unit, roughly when he died, who killed him and with what. MCC Base
  does the same for players' dogtags.

## Placing phones and drops (admins)
- Spawn menu, Entities, MCC: **Payphone (Contracts)**, **Dead drop (trash can)** (2x2) and **Dead drop (dumpster)** (the big
  green one, 4x4).
  - They spawn frozen and can't be broken; move them with the physgun.
  - `mcc_contracts_save` keeps them on this map, and they come back every session (`data/mcc/contracts_<map>.json`).
- A map needs at least one dead drop before the phones hand out work.
- Maps saved with 0.1.0's mailbox drop get a dumpster in its place.

## Settings (Server Settings page, "Contracts")
| Cvar | Default | |
|---|---|---|
| `mcc_contracts_enabled` | 1 | |
| `mcc_contracts_npc_names` | 1 | name Combine and Rebel NPCs |
| `mcc_contracts_npc_tags` | 1 | chance a named NPC's body has his tag (targets always do) |
| `mcc_contracts_time` | 1200 | seconds to finish (0 = no limit) |
| `mcc_contracts_cooldown` | 60 | seconds between contracts |
| `mcc_contracts_min_dist` / `_max_dist` | 2000 / 0 | target distance from the phone (0 = anywhere) |
| `mcc_contracts_target_mode` | 1 | see Targets |
| `mcc_contracts_escorts` | 2 | bodyguards with a spawned target |
| `mcc_contracts_spawn_player_dist` | 2500 | spawned targets stay this far from players |
| `mcc_contracts_reward_min` / `_max` | 6000 / 15000 | roubles |
| `mcc_contracts_reward_escort` | 1500 | extra per guard or friend near him |
| `mcc_contracts_ping_interval` | 90 | seconds between "last seen" updates |
| `mcc_contracts_drop_marker_range` | 1312 | dead-drop markers show within this many units (25 m) |
| `mcc_contracts_any_drop` | 1 | 0: each contract names one drop |
| `mcc_contracts_tag_bounty` | 0 | roubles for any other NPC tag left in a drop (0 = refused) |

Players can hide the HUD panel with `mcc_contracts_hud 0`.

## Commands
- `mcc_contracts_save` (admin): save the phones and drops on this map.
- `mcc_contracts_reload` (admin): re-read both JSON files.
- `mcc_contracts_list` (moderator): the open contracts.
- `mcc_contracts_cancel <name|all>` (admin): call off contracts.
- `mcc_contracts_test [combine|rebels|any]` (admin): take a contract from where you stand, no phone needed.
- `mcc_contracts_names [count] [soldier|elite|cp|rebel]` (moderator): preview names.

## For other addons
- Hooks:
  - `MCC_ContractStarted(contract, ply)`
  - `MCC_ContractCompleted(contract, depositor)`
  - `MCC_ContractFailed(contract, reason)`, where reason is `expired`, `lost`, `abandoned` or `cancelled`
  - `MCC_ContractCanTarget(npc, faction)`: return false to keep an NPC off the list
- Set `npc.MCCName` before an NPC dies to name its body yourself (MCC Base reads it).

## Tests
`python3 tests/test_contracts.py`, with MCC Base next to this folder.
