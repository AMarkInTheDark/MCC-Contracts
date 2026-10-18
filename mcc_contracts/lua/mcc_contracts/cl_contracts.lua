-- MCC Contracts, client: the payphone call, the contract panel on the HUD, and dead drop markers (close ones only).

local C = MCC.Contracts

if MCC.Settings and MCC.Settings.AddGroup then
    MCC.Settings.AddGroup("Contracts", {"contracts_"})
end
local cvHUD = CreateClientConVar("mcc_contracts_hud", "1", true, false, "Show your contract on the HUD.")
if MCC.Settings and MCC.Settings.AddClientOption then
    MCC.Settings.AddClientOption("mcc_contracts_hud", "Show my contract on the HUD")
end

local COL = {
    bg = Color(16, 18, 18, 248), head = Color(34, 36, 34), line = Color(70, 72, 68), text = Color(214, 214, 204),
    dim = Color(128, 130, 122), amber = Color(222, 182, 70), red = Color(200, 80, 70), green = Color(130, 200, 120),
    btn = Color(30, 32, 30), btnHover = Color(54, 56, 52), panel = Color(12, 14, 14, 200),
}

local fonts
local function Fonts()
    if fonts then return end
    fonts = true
    for name, f in pairs({MCC_CtTitle = {20, 700}, MCC_CtLabel = {15, 700}, MCC_CtSmall = {13, 600},
        MCC_CtVoice = {17, 500, true}}) do
        surface.CreateFont(name, {font = "Bahnschrift", size = f[1], weight = f[2], italic = f[3], extended = true})
    end
end

local function Clock(s)
    s = math.max(0, math.floor(s))
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

-- The contract this player holds (nil: none). expiresAt is local CurTime().
C.Mine = C.Mine or nil

local function Store(c)
    if c then c.expiresAt = (c.timeLeft or -1) >= 0 and CurTime() + c.timeLeft or nil end
    C.Mine = c
end

MCC.Net.Receive("contracts_state", function(data) Store(data.c) end)

-- The phone call ----------------------------------------------------------------------------------------

local function Button(parent, text, col, fn)
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b:Dock(TOP)
    b:DockMargin(12, 6, 12, 0)
    b:SetTall(34)
    b.Paint = function(self, w, h)
        surface.SetDrawColor(self:IsHovered() and COL.btnHover or COL.btn)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(COL.line)
        surface.DrawOutlinedRect(0, 0, w, h)
        draw.SimpleText(text, "MCC_CtLabel", 12, h / 2, col or COL.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    b.DoClick = function()
        surface.PlaySound("buttons/button14.wav")
        fn()
    end
    return b
end

local function Row(parent, label, value, col)
    local p = vgui.Create("DPanel", parent)
    p:Dock(TOP)
    p:DockMargin(12, 2, 12, 0)
    p:SetTall(20)
    p.Paint = function(_, w, h)
        draw.SimpleText(label, "MCC_CtSmall", 0, h / 2, COL.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local v = isfunction(value) and value() or value
        draw.SimpleText(v or "-", "MCC_CtLabel", w, h / 2, col or COL.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end
end

local function Send(a, f)
    MCC.Net.Send("contracts_req", {a = a, f = f})
end

function C.OpenPhone(data)
    Fonts()
    if IsValid(C.Frame) then C.Frame:Remove() end
    local phone = Entity(data.phone or 0)
    local c = data.c
    Store(c)

    local f = vgui.Create("DFrame")
    C.Frame = f
    f:SetTitle("")
    f:ShowCloseButton(false)
    f:SetDraggable(true)
    f:DockPadding(0, 34, 0, 12)
    f:MakePopup()
    MCC.UI.Escapable(f)
    f.Paint = function(_, w, h)
        surface.SetDrawColor(COL.bg)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(COL.head)
        surface.DrawRect(0, 0, w, 30)
        surface.SetDrawColor(COL.line)
        surface.DrawOutlinedRect(0, 0, w, h)
        draw.SimpleText("PAYPHONE", "MCC_CtTitle", 12, 15, COL.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("UNKNOWN CALLER", "MCC_CtSmall", w - 12, 15, COL.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end
    function f:Think()
        if not IsValid(phone) or LocalPlayer():GetPos():Distance(phone:GetPos()) > 180 then self:Remove() end
    end
    function f:OnKeyCodePressed(key)
        if key == KEY_ESCAPE or key == KEY_E or key == KEY_TAB then self:Remove() end
    end

    -- what the voice says
    local voice = vgui.Create("DLabel", f)
    voice:Dock(TOP)
    voice:DockMargin(14, 8, 14, 6)
    voice:SetFont("MCC_CtVoice")
    voice:SetTextColor(COL.amber)
    voice:SetWrap(true)
    voice:SetAutoStretchVertical(true)
    voice:SetText('"' .. (data.line or "...") .. '"')

    if c then
        local dead = c.state == "dead"
        Row(f, "TARGET", c.name, COL.text)
        Row(f, "UNIT", (c.unit ~= "" and c.unit or (C.FACTION_NAMES[c.faction] or "")), COL.text)
        Row(f, "REWARD", C.Money(c.reward), COL.amber)
        if (c.escorts or 0) > 0 then Row(f, "COMPANY", c.escorts .. (c.escorts == 1 and " guard" or " guards"), COL.red) end
        Row(f, "TIME LEFT", function()
            local m = C.Mine
            return m and m.expiresAt and Clock(m.expiresAt - CurTime()) or "No limit"
        end)
        Row(f, "STATUS", dead and "Down: deliver his tag" or "Alive", dead and COL.green or COL.red)
        local hint = vgui.Create("DLabel", f)
        hint:Dock(TOP)
        hint:DockMargin(12, 6, 12, 0)
        hint:SetFont("MCC_CtSmall")
        hint:SetTextColor(COL.dim)
        hint:SetWrap(true)
        hint:SetAutoStretchVertical(true)
        hint:SetText((dead and (c.dropHint or "Any dead drop will do: a trash can or a dumpster.") or (c.hint or ""))
            .. (not dead and c.dropHint and ("\nDeliver to: " .. c.dropHint) or ""))
        Button(f, "Call it off", COL.red, function() Send("abandon") end)
    elseif (data.cooldown or 0) > 0 then
        Row(f, "CALL BACK IN", Clock(data.cooldown), COL.dim)
    else
        Button(f, "I want a Combine name", nil, function() Send("take", "combine") end)
        Button(f, "I want a Rebel name", nil, function() Send("take", "rebels") end)
        Button(f, "Whoever. Just pay me", nil, function() Send("take", "any") end)
    end
    Button(f, "Hang up", COL.dim, function() f:Remove() end)

    f:SetWide(440)
    f:InvalidateLayout(true)
    timer.Simple(0, function()
        if not IsValid(f) then return end
        f:SizeToChildren(false, true)
        f:SetTall(f:GetTall() + 12)
        f:Center()
    end)
end

MCC.Net.Receive("contracts_phone", function(data) C.OpenPhone(data) end)

-- HUD ---------------------------------------------------------------------------------------------------

local function Marker(pos, text, col, sub)
    local s = pos:ToScreen()
    if not s.visible then return end
    local x, y = math.Clamp(s.x, 40, ScrW() - 40), math.Clamp(s.y, 40, ScrH() - 40)
    surface.SetDrawColor(col.r, col.g, col.b, 220)
    surface.DrawOutlinedRect(x - 6, y - 6, 12, 12, 2)
    draw.SimpleTextOutlined(text, "MCC_CtSmall", x, y - 10, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, Color(0, 0, 0, 200))
    if sub then
        draw.SimpleTextOutlined(sub, "MCC_CtSmall", x, y + 10, COL.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 200))
    end
end

local function Meters(a, b)
    return math.floor(a:Distance(b) * C.UNITS_TO_M) .. " m"
end

hook.Add("HUDPaint", "MCC_Contracts", function()
    local c = C.Mine
    if not c or not cvHUD:GetBool() then return end
    Fonts()
    local me = LocalPlayer()
    if not IsValid(me) then return end
    local eye = me:EyePos()

    -- the panel, top right
    local w, x, y = 300, ScrW() - 316, math.floor(ScrH() * 0.22)
    local dead = c.state == "dead"
    local lines = 4
    draw.RoundedBox(0, x, y, w, 18 + lines * 18 + 8, COL.panel)
    surface.SetDrawColor(dead and COL.green or COL.amber)
    surface.DrawRect(x, y, 3, 18 + lines * 18 + 8)
    draw.SimpleText("CONTRACT #" .. c.id, "MCC_CtSmall", x + 10, y + 4, COL.dim)
    if c.expiresAt then
        local left = c.expiresAt - CurTime()
        draw.SimpleText(Clock(left), "MCC_CtLabel", x + w - 8, y + 3, left < 120 and COL.red or COL.text, TEXT_ALIGN_RIGHT)
    end
    draw.SimpleText(c.name or "?", "MCC_CtLabel", x + 10, y + 22, COL.text)
    draw.SimpleText(c.unit or "", "MCC_CtSmall", x + 10, y + 40, COL.dim)
    draw.SimpleText(C.Money(c.reward), "MCC_CtLabel", x + w - 8, y + 40, COL.amber, TEXT_ALIGN_RIGHT)
    draw.SimpleText(dead and "Down: leave his tag in a dead drop" or "Find him, kill him, take his tag", "MCC_CtSmall",
        x + 10, y + 60, dead and COL.green or COL.text)
    if not dead and c.hint then
        draw.SimpleText(c.hint, "MCC_CtSmall", x + 10, y + 76, COL.dim)
    end

    -- dead drops: a marker only within mcc_contracts_drop_marker_range (25 m); further out, the panel says
    -- which way the nearest one is
    if dead and c.drops and #c.drops > 0 then
        local list = {}
        for _, d in ipairs(c.drops) do list[#list + 1] = Vector(d[1], d[2], d[3]) end
        table.sort(list, function(a, b) return a:DistToSqr(eye) < b:DistToSqr(eye) end)
        local range = MCC.Config.Get("contracts_drop_marker_range")
        for i = 1, math.min(3, #list) do
            if range <= 0 or eye:Distance(list[i]) <= range then
                Marker(list[i] + Vector(0, 0, 50), "DEAD DROP", COL.green, Meters(eye, list[i]))
            end
        end
        local dir, m = C.Bearing(me:GetPos(), list[1])
        draw.SimpleText(string.format("Nearest dead drop: %d m %s", math.floor(m), dir), "MCC_CtSmall", x + 10, y + 76, COL.dim)
    end
end)
