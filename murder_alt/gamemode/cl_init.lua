include("shared.lua")

MA.Role       = MA.Role   or MA.ROLE_NONE
MA.Allies     = MA.Allies or {}
MA.WinTeam    = MA.WinTeam or 0
MA.WheelOpen  = false
MA.WheelHover = 0

local COL_INNOCENT = Color(80, 170, 255)
local COL_TRAITOR  = Color(225, 50, 50)
local COL_WHITE    = Color(255, 255, 255)

surface.CreateFont("MA_Huge",  { font = "Arial", size = 72, weight = 800, extended = true })
surface.CreateFont("MA_Big",   { font = "Arial", size = 34, weight = 700, extended = true })
surface.CreateFont("MA_Med",   { font = "Arial", size = 24, weight = 600, extended = true })
surface.CreateFont("MA_Small", { font = "Arial", size = 19, weight = 500, extended = true })

---------------------------------------------------------------------
-- Сеть
---------------------------------------------------------------------
net.Receive("MA_Role", function()
	MA.Role = net.ReadUInt(2)
	local n = net.ReadUInt(8)
	MA.Allies = {}
	for i = 1, n do
		MA.Allies[i] = net.ReadEntity()
	end
end)

net.Receive("MA_Win", function()
	MA.WinTeam = net.ReadUInt(2)
end)

---------------------------------------------------------------------
-- Звук начала раунда
---------------------------------------------------------------------
local cvRoundSound  = CreateClientConVar("ma_round_sound", "1", true, false, "Играть звук в начале раунда")
local cvRoundVolume = CreateClientConVar("ma_round_sound_volume", "1", true, false, "Громкость звука начала раунда (0-1)")

net.Receive("MA_RoundSound", function()
	if not cvRoundSound:GetBool() then return end

	sound.PlayFile("sound/" .. MA.ROUND_SOUND, "noplay", function(channel, errCode, errName)
		if IsValid(channel) then
			channel:SetVolume(math.Clamp(cvRoundVolume:GetFloat(), 0, 1))
			channel:Play()
		else
			surface.PlaySound(MA.ROUND_SOUND) -- запасной вариант
		end
	end)
end)

---------------------------------------------------------------------
-- Колесо действий. Список действий можно расширять.
---------------------------------------------------------------------
MA.Actions = {
	{
		id   = "drop",
		name = "Drop Weapon",
		check = function(lp)
			local w = lp:GetActiveWeapon()
			return IsValid(w) and not MA.UNDROPPABLE[w:GetClass()]
		end,
	},
}

local function OpenWheel()
	if MA.WheelOpen then return end
	MA.WheelOpen  = true
	MA.WheelHover = 0
	gui.EnableScreenClicker(true)
	gui.SetMousePos(ScrW() / 2, ScrH() / 2)
end

local function CloseWheel(doSelect)
	if not MA.WheelOpen then return end
	MA.WheelOpen = false
	gui.EnableScreenClicker(false)

	if doSelect and MA.WheelHover > 0 then
		local act = MA.Actions[MA.WheelHover]
		local lp = LocalPlayer()
		if act and IsValid(lp) and lp:Alive() and lp:GetObserverMode() == OBS_MODE_NONE and not lp:GetNWBool("MA_Fake", false) and act.check(lp) then
			net.Start("MA_Action")
				net.WriteString(act.id)
			net.SendToServer()
		end
	end
	MA.WheelHover = 0
end

-- Q (удерживать) = колесо действий, отпустить = выбрать
function GM:OnSpawnMenuOpen()
	OpenWheel()
end

function GM:OnSpawnMenuClose()
	CloseWheel(true)
end

-- F1 = spawn menu
local function ToggleSpawnMenu()
	local gm = GAMEMODE
	if not gm or not gm.BaseClass then return end

	local visible = IsValid(g_SpawnMenu) and g_SpawnMenu:IsVisible()
	if visible then
		gm.BaseClass.OnSpawnMenuClose(gm)
	else
		gm.BaseClass.OnSpawnMenuOpen(gm)
	end
end

hook.Add("PlayerBindPress", "MA_F1SpawnMenu", function(ply, bind, pressed)
	if bind == "gm_showhelp" then
		if pressed then ToggleSpawnMenu() end
		return true
	end
end)

---------------------------------------------------------------------
-- HUD (только роль в Q-меню, экран роли и экран победы)
---------------------------------------------------------------------
function GM:HUDShouldDraw(name)
	if MA.WheelOpen and name == "CHudCrosshair" then return false end
	local r = MA.CallBase(self, "HUDShouldDraw", name)
	if r == nil then return true end
	return r
end

-- Никаких имён над головами
function GM:HUDDrawTargetID() end

local function DrawShadowText(text, font, x, y, col, ax, ay)
	draw.SimpleText(text, font, x + 2, y + 2, Color(0, 0, 0, 220), ax, ay)
	draw.SimpleText(text, font, x, y, col, ax, ay)
end

local function DrawWheel()
	local lp = LocalPlayer()
	local sw, sh = ScrW(), ScrH()
	local cx, cy = sw / 2, sh / 2
	local rIn, rOut = 95, 195
	local n = #MA.Actions
	if n < 1 then return end

	local full = math.pi * 2
	local span = full / n
	local start = -math.pi / 2 - span / 2
	local gap = (n > 1) and math.rad(2) or 0

	-- затемнение
	surface.SetDrawColor(0, 0, 0, 110)
	surface.DrawRect(0, 0, sw, sh)

	-- выбранный сектор
	local mx, my = gui.MousePos()
	local dx, dy = mx - cx, my - cy
	local hover = 0
	if math.sqrt(dx * dx + dy * dy) > 40 then
		local rel = (math.atan2(dy, dx) - start) % full
		hover = math.min(n, math.floor(rel / span) + 1)
	end
	MA.WheelHover = hover

	local canUse = lp:Alive() and lp:GetObserverMode() == OBS_MODE_NONE and not lp:GetNWBool("MA_Fake", false)

	draw.NoTexture()
	for i = 1, n do
		local act = MA.Actions[i]
		local enabled = canUse and act.check(lp)

		local col
		if not enabled then
			col = Color(40, 40, 40, 190)
		elseif hover == i then
			col = Color(190, 35, 35, 235)
		else
			col = Color(25, 25, 25, 215)
		end
		surface.SetDrawColor(col)

		local a0 = start + (i - 1) * span + gap
		local a1 = start + i * span - gap
		local steps = math.max(8, math.floor(32 / n) + 8)
		local step = (a1 - a0) / steps

		for s = 0, steps - 1 do
			local b0 = a0 + s * step
			local b1 = b0 + step
			surface.DrawPoly({
				{ x = cx + math.cos(b0) * rOut, y = cy + math.sin(b0) * rOut },
				{ x = cx + math.cos(b1) * rOut, y = cy + math.sin(b1) * rOut },
				{ x = cx + math.cos(b1) * rIn,  y = cy + math.sin(b1) * rIn  },
				{ x = cx + math.cos(b0) * rIn,  y = cy + math.sin(b0) * rIn  },
			})
		end

		local mid = start + (i - 0.5) * span
		local rMid = (rIn + rOut) / 2
		local tcol = enabled and COL_WHITE or Color(120, 120, 120)
		draw.SimpleText(act.name, "MA_Med", cx + math.cos(mid) * rMid, cy + math.sin(mid) * rMid, tcol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
end

local function DrawRoleCorner()
	local state = GetGlobalInt("MA_State", MA.STATE_WAIT)
	if state == MA.STATE_WAIT or MA.Role == MA.ROLE_NONE then return end

	local x, y = 30, 30
	if MA.Role == MA.ROLE_TRAITOR then
		DrawShadowText("Трейтор", "MA_Big", x, y, COL_TRAITOR, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

		local yy = y + 44
		local first = true
		for _, a in ipairs(MA.Allies) do
			if IsValid(a) then
				if first then
					DrawShadowText("Союзники:", "MA_Small", x, yy, COL_TRAITOR, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
					first = false
					yy = yy + 22
				end
				DrawShadowText(a:Nick(), "MA_Small", x, yy, COL_WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
				yy = yy + 22
			end
		end
	else
		DrawShadowText("Невиновный", "MA_Big", x, y, COL_INNOCENT, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
	end
end

function GM:HUDPaint()
	MA.CallBase(self, "HUDPaint")

	local lp = LocalPlayer()
	if not IsValid(lp) then return end

	local sw, sh = ScrW(), ScrH()
	local state = GetGlobalInt("MA_State", MA.STATE_WAIT)
	local role  = MA.Role

	-- Экран роли в начале раунда
	if state == MA.STATE_PREP and role ~= MA.ROLE_NONE then
		surface.SetDrawColor(0, 0, 0, 170)
		surface.DrawRect(0, 0, sw, sh)

		local left = math.max(0, math.ceil(GetGlobalFloat("MA_StateEnd", 0) - CurTime()))

		if role == MA.ROLE_TRAITOR then
			DrawShadowText("Вы трейтор", "MA_Huge", sw / 2, sh / 2 - 30, COL_TRAITOR, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			DrawShadowText("Убейте всех невиновных", "MA_Med", sw / 2, sh / 2 + 35, COL_WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		else
			DrawShadowText("Вы невиновный", "MA_Huge", sw / 2, sh / 2 - 30, COL_INNOCENT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			DrawShadowText("Найдите и убейте трейтора", "MA_Med", sw / 2, sh / 2 + 35, COL_WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end

		DrawShadowText("Раунд начнётся через " .. left, "MA_Small", sw / 2, sh / 2 + 80, COL_WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	-- Экран победы
	if state == MA.STATE_END and MA.WinTeam ~= 0 then
		surface.SetDrawColor(0, 0, 0, 140)
		surface.DrawRect(0, 0, sw, sh)

		if MA.WinTeam == MA.WIN_TRAITOR then
			DrawShadowText("Победа Трейторов", "MA_Huge", sw / 2, sh / 2 - 20, COL_TRAITOR, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		else
			DrawShadowText("Победа Невиновных", "MA_Huge", sw / 2, sh / 2 - 20, COL_INNOCENT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end

		DrawShadowText("Скоро начнётся новый раунд", "MA_Med", sw / 2, sh / 2 + 45, COL_WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	-- Строка статуса сверху
	local statusText
	if GetGlobalBool("MA_Solo", false) then
		statusText = "Одиночная игра - Сандбокс"
	elseif state == MA.STATE_WAIT then
		statusText = "Хомисайд - Ожидание игроков"
	else
		local t = 0
		local startT = GetGlobalFloat("MA_RoundStart", 0)
		if state == MA.STATE_ACTIVE then
			t = CurTime() - startT
		elseif state == MA.STATE_END then
			t = GetGlobalFloat("MA_RoundEnd", startT) - startT
		end
		t = math.max(0, t)
		statusText = string.format("Хомисайд - %02d:%02d", math.floor(t / 60), math.floor(t % 60))
	end
	DrawShadowText(statusText, "MA_Med", sw / 2, 24, COL_WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

	-- Колесо действий + роль в углу (только пока зажат Q)
	if MA.WheelOpen then
		DrawWheel()
		DrawRoleCorner()
	end
end
