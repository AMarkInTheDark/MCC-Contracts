-- Dead drop (base): a 2x2 container that only takes dogtags. Leave a contract target's tag in one and the
-- contract pays out (lua/mcc_contracts/sv_contracts.lua). The trash can and dumpster are the placeable kinds.
-- Frozen in place; admins move them with the physgun and keep them with mcc_contracts_save.

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Dead drop"
ENT.Category = "MCC"
ENT.Spawnable = false
ENT.AdminOnly = true
ENT.Model = "models/props_trainstation/trashcan_indoor001a.mdl"
ENT.DropName = "dead drop"
ENT.DropW, ENT.DropH = 2, 2

function ENT:GetDropModel()
    return self.Model
end

if SERVER then
    function ENT:SpawnFunction(ply, tr, class)
        if not tr.Hit then return end
        local e = ents.Create(class)
        e:SetPos(tr.HitPos)
        e:SetAngles(Angle(0, ply:EyeAngles().y + 180, 0))
        e:Spawn()
        e:Activate()
        -- stand it on the floor
        local mins = e:OBBMins()
        e:SetPos(tr.HitPos - Vector(0, 0, mins.z))
        return e
    end

    function ENT:Initialize()
        self:SetModel(self:GetDropModel())
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
        if MCC and MCC.Contracts and MCC.Contracts.SetupDrop then MCC.Contracts.SetupDrop(self, self.DropName, self.DropW, self.DropH) end
    end

    function ENT:OnTakeDamage() end
end

if CLIENT then
    function ENT:Draw()
        self:DrawModel()
    end
end
