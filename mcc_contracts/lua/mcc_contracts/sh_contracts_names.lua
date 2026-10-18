-- Names for Combine and Rebel NPCs, after Half-Life 2's lore.
--
--   Overwatch soldiers  C17:OWS.RIPCORD-4     sector, unit type, squad callsign, number (the soldiers' radio
--   Overwatch elites    C17:EOW.REAPER-1      callsigns: "Ripcord", "Sundown", "Sweeper"...)
--   Civil Protection    C17:i4.UNION-27       sector, rank (i5 is the lowest, i1 the highest), callsign, number
--   Rebels              Pavel "Static" Horvat  first name, sometimes a nickname, last name
--
-- The pools are in data/mcc/contracts_names.json (written with these defaults the first time): add, remove or
-- rename freely, and mcc_contracts_reload picks the changes up. mcc_contracts_names 20 previews a few.

MCC.Contracts = MCC.Contracts or {}
local C = MCC.Contracts

C.DEFAULT_NAMES = {
    -- City sectors; a repeat makes one more likely (most units serve in City 17).
    sectors = {"C17", "C17", "C17", "C17", "C17", "C24", "C24", "C08", "C11", "C13", "C45", "NP"},

    -- Overwatch squad callsigns
    overwatch = {
        "APEX", "BLADE", "DAGGER", "ECHO", "FIST", "FLASH", "GHOST", "GRID", "HAMMER", "HELIX", "HUNTER", "HURRICANE",
        "ICE", "JET", "JUDGE", "KING", "LEADER", "MACE", "NOMAD", "NOVA", "PAYBACK", "PHANTOM", "QUICKSAND", "RANGER",
        "RAZOR", "REAPER", "RIPCORD", "SAVAGE", "SCAR", "SLAM", "SLASH", "SPEAR", "STAB", "STAR", "STINGER", "STORM",
        "STRIKER", "SUNDOWN", "SWEEPER", "SWIFT", "SWORD", "TRACKER", "UNIFORM", "VAMP", "VICE", "VIPER", "WINDER",
        "ZERO", "ANVIL", "BULWARK", "CINDER", "COBALT", "DIRGE", "EMBER", "FLINT", "GALLOWS", "HALBERD", "IRON",
        "LANCE", "MAUL", "ONYX", "PIKE", "QUARRY", "RAMPART", "SENTRY", "TALON", "TEMPEST", "WARDEN",
    },
    -- Overwatch elites draw from these instead
    elite = {"REAPER", "PHANTOM", "KING", "LEADER", "STAR", "JUDGE", "APEX", "ZERO", "HALBERD", "GALLOWS", "WARDEN", "ONYX"},

    -- Civil Protection callsigns (the metrocops' radio: "Union", "Defender", "Hero"...)
    civilprotection = {
        "UNION", "DEFENDER", "HERO", "JURY", "KING", "LINE", "PATROL", "QUICK", "ROLLER", "STICK", "TAP", "VICTOR",
        "XRAY", "YELLOW", "VICE", "GRID", "HELIX", "ION", "NOMAD", "SPEAR", "SWORD", "HAMMER", "APEX", "ECHO",
        "BLADE", "DAGGER", "FIST", "MACE", "RAZOR", "SAVAGE", "SCAR", "SLASH", "STAB", "SUNDOWN", "UNIFORM", "ZONE",
        "BADGE", "BATON", "CORDON", "CURFEW", "LOCKDOWN", "MANDATE", "MARSHAL", "QUOTA", "RATION", "SEIZE", "VERDICT",
        "WARRANT",
    },

    -- Rebels: Eastern European for the most part (City 17 is somewhere in Eastern Europe), with the odd name
    -- from further away; people were shipped in from everywhere.
    first = {
        "Aleksei", "Anya", "Anton", "Andrei", "Bogdan", "Boris", "Branko", "Dasha", "Dmitri", "Dusan", "Elena", "Emil",
        "Filip", "Goran", "Gregor", "Hana", "Igor", "Ilya", "Irina", "Ivan", "Jakub", "Jana", "Josef", "Karel", "Kasia",
        "Katya", "Klara", "Lazlo", "Lena", "Leon", "Lev", "Lidia", "Luka", "Maja", "Marek", "Milan", "Mila", "Mira",
        "Miro", "Nadia", "Natasha", "Nikolai", "Nina", "Oleg", "Olga", "Ondrej", "Pavel", "Pavla", "Petra", "Radek",
        "Rada", "Roman", "Sasha", "Sergei", "Sonja", "Stanislav", "Stefan", "Taras", "Tomas", "Vasil", "Vera", "Vesna",
        "Viktor", "Vlad", "Yelena", "Yuri", "Zdenek", "Zofia", "Zora", "Winston", "Adam", "Alan", "Ben", "Carla",
        "Dan", "Dina", "Frank", "Gina", "Hank", "Jack", "Joel", "Kate", "Leah", "Marcus", "Mia", "Nick", "Owen",
        "Paul", "Rosa", "Ruth", "Sam", "Sean", "Tess", "Tom", "Wes", "Will", "Ada", "Arturo", "Chiara", "Kenji",
        "Amara", "Kofi", "Lucia", "Mateo", "Noor", "Rafael", "Soren", "Tariq", "Yusuf", "Ines", "Elio", "Greta",
    },
    last = {
        "Novak", "Kowalski", "Dvorak", "Horvat", "Petrov", "Volkov", "Sokolov", "Kuznetsov", "Popescu", "Blazek",
        "Kral", "Varga", "Nagy", "Toth", "Kovac", "Babic", "Jovanovic", "Zelenko", "Moroz", "Hrabal", "Svoboda",
        "Cerny", "Prochazka", "Kolar", "Fiala", "Benes", "Sedlak", "Zeman", "Holub", "Wojcik", "Mazur", "Lewandowski",
        "Zielinski", "Bauer", "Weber", "Fischer", "Richter", "Wagner", "Keller", "Brandt", "Lindqvist", "Nyberg",
        "Halvorsen", "Moreau", "Laurent", "Rossi", "Bruno", "Conti", "Greco", "Murphy", "Kelly", "Walsh", "Doyle",
        "Reyes", "Ortega", "Castillo", "Mendez", "Silva", "Costa", "Okafor", "Mensah", "Tanaka", "Mori", "Park",
        "Chen", "Ward", "Hayes", "Fletcher", "Grady", "Brennan", "Calloway", "Garrett", "Shaw", "Ramsey", "Dalton",
        "Hughes", "Greer", "Harlow", "Sheckley", "Griggs", "Kessler", "Voss", "Lang", "Stein", "Roth", "Hartmann",
        "Krause", "Becker", "Abel", "Ostrowski", "Pavlik", "Hajek", "Malek", "Rusnak", "Hlavac", "Kucera", "Vesely",
        "Pokorny", "Ruzicka", "Simek", "Urban", "Lukin", "Orlov", "Belov", "Gromov", "Zaitsev", "Karpov", "Rybak",
        "Shevchenko", "Bondarenko", "Tkachenko", "Kravets", "Melnyk", "Lysenko", "Marchenko", "Savchenko",
    },
    -- Nicknames some rebels go by (a nod to the canals, Ravenholm, Black Mesa East and the rest)
    nick = {
        "Static", "Sparks", "Doc", "Tinman", "Bricks", "Ghost", "Gopher", "Mole", "Rook", "Hooch", "Lucky", "Radio",
        "Patch", "Scrap", "Rusty", "Pipes", "Canal", "Wrench", "Bolt", "Red", "Bones", "Fixer", "Smokes", "Cricket",
        "Magpie", "Hex", "Junk", "Mutt", "Shovel", "Hatch", "Ant", "Lion", "Crab", "Rat", "Crow", "Lighthouse",
        "Tunnels", "Rails", "Coil", "Ration", "Sewer", "Buggy", "Airboat", "Lambda", "Gravity", "Flare", "Cinder",
    },
    nick_chance = 0.25, -- share of rebels with a nickname
}

-- The pools in use: the defaults until the server has read contracts_names.json (sv_contracts.lua).
C.Names = C.Names or table.Copy(C.DEFAULT_NAMES)

local function Pick(list, fallback)
    if istable(list) and #list > 0 then return list[math.random(1, #list)] end
    return fallback
end

-- One name of a kind: "soldier", "elite", "cp" or "rebel".
function C.MakeName(kind)
    local N = C.Names
    local sector = Pick(N.sectors, "C17")
    if kind == "elite" then
        return string.format("%s:EOW.%s-%d", sector, Pick(N.elite, Pick(N.overwatch, "REAPER")), math.random(1, 9))
    elseif kind == "soldier" then
        return string.format("%s:OWS.%s-%d", sector, Pick(N.overwatch, "RIPCORD"), math.random(1, 9))
    elseif kind == "cp" then
        return string.format("%s:i%d.%s-%02d", sector, math.random(1, 5) == 1 and math.random(1, 3) or math.random(4, 5),
            Pick(N.civilprotection, "UNION"), math.random(1, 99))
    end
    local first, last = Pick(N.first, "Ivan"), Pick(N.last, "Novak")
    if math.random() < (tonumber(N.nick_chance) or 0.25) and istable(N.nick) and #N.nick > 0 then
        return string.format('%s "%s" %s', first, Pick(N.nick), last)
    end
    return first .. " " .. last
end

-- A name nobody alive this session has had yet (tries a few times, then accepts a repeat).
C.UsedNames = C.UsedNames or {}
function C.UniqueName(kind)
    local name
    for _ = 1, 12 do
        name = C.MakeName(kind)
        if not C.UsedNames[name] then break end
    end
    C.UsedNames[name] = true
    return name
end

-- How many different names a kind can make (for the README's "massive" claim, and the preview command).
function C.NameCount(kind)
    local N = C.Names
    local sectors = math.max(1, #(N.sectors or {}))
    if kind == "elite" then return sectors * math.max(1, #(N.elite or {})) * 9 end
    if kind == "soldier" then return sectors * math.max(1, #(N.overwatch or {})) * 9 end
    if kind == "cp" then return sectors * 5 * math.max(1, #(N.civilprotection or {})) * 99 end
    local base = math.max(1, #(N.first or {})) * math.max(1, #(N.last or {}))
    return base * (1 + math.max(0, #(N.nick or {})))
end
