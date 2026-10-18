-- Payphone: call it (E) for a kill contract. Admins place it from the spawn menu (MCC) and keep it on the map
-- with mcc_contracts_save. It doesn't move and can't be broken. See lua/mcc_contracts/.

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Payphone (Contracts)"
ENT.Category = "MCC"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.Model = "models/props_trainstation/payphone001a.mdl"

if SERVER then
    function ENT:SpawnFunction(ply, tr, class)
        if not tr.Hit then return end
        local e = ents.Create(class)
        e:SetPos(tr.HitPos)
        e:SetAngles(Angle(0, ply:EyeAngles().y + 180, 0))
        e:Spawn()
        e:Activate()
        return e
    end

    function ENT:Initialize()
        self:SetModel(self.Model)
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
        self:SetNWString("MCCName", "Payphone")
    end

    -- With MCC's E-to-interact on, the pickup system opens the phone (and shows the prompt); this is the fallback.
    function ENT:Use(activator)
        if MCC and MCC.Pickup and MCC.Pickup.Active and MCC.Pickup.Active() then return end
        if IsValid(activator) and activator:IsPlayer() and MCC and MCC.Contracts and MCC.Contracts.PhoneUse then
            MCC.Contracts.PhoneUse(activator, self)
        end
    end

    function ENT:OnTakeDamage() end
end

if CLIENT then
    function ENT:Draw()
        self:DrawModel()
    end
end
