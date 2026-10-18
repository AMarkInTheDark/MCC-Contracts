-- Dead drop: the big green dumpster. See mcc_deaddrop_base.lua. (Replaces 0.1.0's mailbox; saved maps convert.)

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "mcc_deaddrop_base"
ENT.PrintName = "Dead drop (dumpster)"
ENT.Category = "MCC"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.Model = "models/props_junk/TrashDumpster01a.mdl"
ENT.DropName = "dumpster"
ENT.DropW, ENT.DropH = 4, 4
