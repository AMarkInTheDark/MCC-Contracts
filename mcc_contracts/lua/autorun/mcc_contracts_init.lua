-- MCC Contracts: kill contracts from payphones. Call a payphone, get a named Combine or Rebel target, kill
-- him, take his dogtag off the body and leave it in a dead drop (a trash can or a dumpster) to get paid.
-- Every Combine and Rebel NPC gets a name from big Half-Life 2 lore pools, and carries a dogtag with it.
-- An expansion of MCC Base (its inventory carries the tags), which has to be installed too. See README.md.

AddCSLuaFile()

local FILES = {
    "mcc_contracts/sh_contracts_names.lua",
    "mcc_contracts/sh_contracts.lua",
    "mcc_contracts/sv_contracts.lua",
    "mcc_contracts/cl_contracts.lua",
}
local NEEDS_API = 1 -- the MCC Base API version this was written against

if SERVER then
    for _, f in ipairs(FILES) do
        if string.sub(string.GetFileFromFilename(f), 1, 3) ~= "sv_" then AddCSLuaFile(f) end
    end
end

local function Load(MCC)
    if (MCC.API_VERSION or 0) < NEEDS_API then
        MCC.Log("MCC Contracts needs a newer MCC Base (API %d, this one has %d); not loaded", NEEDS_API, MCC.API_VERSION or 0)
        return
    end
    for _, f in ipairs(FILES) do MCC.LoadFile(f) end
    MCC.Log("MCC Contracts %s loaded", MCC.Contracts.VERSION or "?")
end

if MCC and MCC.Ready and MCC.LoadFile then
    Load(MCC) -- Lua refresh, or loaded after MCC Base booted
else
    hook.Add("MCC_Loaded", "MCC_Contracts", Load)
end

hook.Add("Initialize", "MCC_Contracts_Check", function()
    if not MCC then print("[MCC Contracts] MCC Base isn't installed; this addon needs it.") end
end)
