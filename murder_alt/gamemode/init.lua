AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

util.AddNetworkString("MA_Role")
util.AddNetworkString("MA_Win")
util.AddNetworkString("MA_Action")
util.AddNetworkString("MA_RoundSound")

-- Клиенты скачают звук начала раунда
resource.AddFile("sound/" .. MA.ROUND_SOUND)

-- Оружие трейторов: {класс, ammo-резерв (0 = не трогать)}
local TRAITOR_WEAPONS = {
	{ "arc9_cod2019_me_knife",    0  },
	{ "arc9_cod2019_pi_357",      24 },
	{ "arc9_cod2019_nade_c4",     1  },
	{ "arc9_cod2019_nade_molotov", 1 },
}

local function GetRole(ply)
	return ply.MA_Role or MA.ROLE_NONE
end

local function GetState()
	return GetGlobalInt("MA_State", MA.STATE_WAIT)
end

local function SetState(state, duration)
	SetGlobalInt("MA_State", state)
	SetGlobalFloat("MA_StateEnd", CurTime() + (duration or 0))
end

-- Одиночная игра: бесконечный раунд, игрок всегда невиновный
local function IsSolo()
	return game.SinglePlayer()
end

local function MinPlayers()
	return IsSolo() and 1 or MA.MIN_PLAYERS
end

local function Shuffle(t)
	for i = #t, 2, -1 do
		local j = math.random(i)
		t[i], t[j] = t[j], t[i]
	end
	return t
end

---------------------------------------------------------------------
-- Сеть
---------------------------------------------------------------------
local function SendRole(ply)
	if not IsValid(ply) then return end

	local role = GetRole(ply)
	local allies = {}

	if role == MA.ROLE_TRAITOR then
		for _, p in ipairs(player.GetAll()) do
			if p ~= ply and GetRole(p) == MA.ROLE_TRAITOR then
				allies[#allies + 1] = p
			end
		end
	end

	net.Start("MA_Role")
		net.WriteUInt(role, 2)
		net.WriteUInt(#allies, 8)
		for _, a in ipairs(allies) do
			net.WriteEntity(a)
		end
	net.Send(ply)
end

---------------------------------------------------------------------
-- Выдача оружия
---------------------------------------------------------------------
local function TopUpAmmo(ply, class, amount)
	timer.Simple(0.3, function()
		if not IsValid(ply) or not ply:Alive() then return end
		local wep = ply:GetWeapon(class)
		if not IsValid(wep) then return end
		local at = wep:GetPrimaryAmmoType()
		if at and at >= 0 and ply:GetAmmoCount(at) < amount then
			ply:SetAmmo(amount, at)
		end
	end)
end

-- Руки: сначала наш ma_hands, затем weapon_hands, затем стандартный weapon_fists
local HANDS_CLASSES = { "ma_hands", "weapon_hands", "weapon_fists" }

local function GiveHands(ply)
	ply.MA_HandsClass = nil
	for _, class in ipairs(HANDS_CLASSES) do
		local wep = ply:Give(class)
		if IsValid(wep) then
			ply.MA_HandsClass = class
			return
		end
	end
end

local function SelectHands(ply)
	if ply.MA_HandsClass and ply:HasWeapon(ply.MA_HandsClass) then
		ply:SelectWeapon(ply.MA_HandsClass)
		return
	end
	for _, class in ipairs(HANDS_CLASSES) do
		if ply:HasWeapon(class) then
			ply:SelectWeapon(class)
			return
		end
	end
end

local function GiveTraitorWeapons(ply)
	for _, v in ipairs(TRAITOR_WEAPONS) do
		ply:Give(v[1])
		if v[2] > 0 then
			TopUpAmmo(ply, v[1], v[2])
		end
	end
end

function GM:PlayerLoadout(ply)
	ply:StripWeapons()
	ply:StripAmmo()

	GiveHands(ply)
	if GetRole(ply) == MA.ROLE_TRAITOR then
		GiveTraitorWeapons(ply)
	end

	SelectHands(ply)
	return true
end

---------------------------------------------------------------------
-- Логика раунда
---------------------------------------------------------------------
local function UpdateAliveCount()
	local n = 0
	for _, p in ipairs(player.GetAll()) do
		if p:Alive() and GetRole(p) ~= MA.ROLE_NONE then n = n + 1 end
	end
	SetGlobalInt("MA_Alive", n)
end

local function EndRound(winner)
	if IsSolo() then return end
	if GetState() ~= MA.STATE_ACTIVE then return end

	SetState(MA.STATE_END, MA.END_TIME)
	SetGlobalFloat("MA_RoundEnd", CurTime())

	for _, p in ipairs(player.GetAll()) do
		if IsValid(p) then p:Freeze(false) end
	end

	net.Start("MA_Win")
		net.WriteUInt(winner, 2)
	net.Broadcast()

	if winner == MA.WIN_TRAITOR then
		PrintMessage(HUD_PRINTTALK, "Победа Трейторов")
	else
		PrintMessage(HUD_PRINTTALK, "Победа Невиновных")
	end
end

local function CheckWin()
	if IsSolo() then
		UpdateAliveCount()
		return
	end
	if GetState() ~= MA.STATE_ACTIVE then return end

	local innocents, traitors = 0, 0
	for _, p in ipairs(player.GetAll()) do
		if IsValid(p) and p:Alive() then
			local r = GetRole(p)
			if r == MA.ROLE_INNOCENT then
				innocents = innocents + 1
			elseif r == MA.ROLE_TRAITOR then
				traitors = traitors + 1
			end
		end
	end

	SetGlobalInt("MA_Alive", innocents + traitors)

	if traitors == 0 then
		EndRound(MA.WIN_INNOCENT)
	elseif innocents == 0 then
		EndRound(MA.WIN_TRAITOR)
	end
end

local function BeginActive()
	SetState(MA.STATE_ACTIVE)
	SetGlobalFloat("MA_RoundStart", CurTime())
	SetGlobalFloat("MA_RoundEnd", 0)

	for _, p in ipairs(player.GetAll()) do
		if IsValid(p) then
			p:Freeze(false)
			if GetRole(p) ~= MA.ROLE_NONE then SendRole(p) end
		end
	end

	CheckWin()
end

local function StartRound()
	local plys = {}
	for _, p in ipairs(player.GetAll()) do
		if IsValid(p) and p:Team() ~= TEAM_SPECTATOR then
			plys[#plys + 1] = p
		end
	end

	if #plys < MinPlayers() then
		SetState(MA.STATE_WAIT)
		return
	end

	game.CleanUpMap()
	Shuffle(plys)

	local traitorCount = IsSolo() and 0 or math.max(1, math.floor(#plys / MA.PLAYERS_PER_TRAITOR))

	for i, p in ipairs(plys) do
		p.MA_Role = (i <= traitorCount) and MA.ROLE_TRAITOR or MA.ROLE_INNOCENT
	end

	SetState(MA.STATE_PREP, MA.PREP_TIME)

	-- Звук начала каждого раунда
	net.Start("MA_RoundSound")
	net.Broadcast()

	for _, p in ipairs(plys) do
		p:UnSpectate()
		p:Spawn() -- PlayerLoadout сам заберёт всё и выдаст оружие по роли
		p:Freeze(true)
		SendRole(p)
	end

	UpdateAliveCount()
end

timer.Create("MA_Think", 1, 0, function()
	local state = GetState()
	local count = #player.GetAll()

	if state == MA.STATE_WAIT then
		if count >= MinPlayers() then StartRound() end

	elseif state == MA.STATE_PREP then
		if CurTime() >= GetGlobalFloat("MA_StateEnd", 0) then BeginActive() end

	elseif state == MA.STATE_ACTIVE then
		CheckWin()

	elseif state == MA.STATE_END then
		if CurTime() >= GetGlobalFloat("MA_StateEnd", 0) then
			if count >= MinPlayers() then
				StartRound()
			else
				SetState(MA.STATE_WAIT)
			end
		end
	end
end)

---------------------------------------------------------------------
-- Колесо действий (Q)
---------------------------------------------------------------------
local Actions = {}

Actions.drop = function(ply)
	if ply:GetNWBool("MA_Fake", false) then return end
	local wep = ply:GetActiveWeapon()
	if not IsValid(wep) then return end
	if MA.UNDROPPABLE[wep:GetClass()] then return end

	ply:DropWeapon(wep)

	timer.Simple(0, function()
		if IsValid(ply) and ply:Alive() then
			SelectHands(ply)
		end
	end)
end

net.Receive("MA_Action", function(_, ply)
	if not IsValid(ply) or not ply:Alive() then return end
	if ply:GetObserverMode() ~= OBS_MODE_NONE then return end
	if (ply.MA_NextAction or 0) > CurTime() then return end
	ply.MA_NextAction = CurTime() + 0.4

	local id = net.ReadString()
	local f = Actions[id]
	if f then f(ply) end
end)

---------------------------------------------------------------------
-- Хуки геймода
---------------------------------------------------------------------
function GM:Initialize()
	MA.CallBase(self, "Initialize")
	SetState(MA.STATE_WAIT)
	SetGlobalInt("MA_Alive", 0)
	SetGlobalBool("MA_Solo", game.SinglePlayer())
end

function GM:PlayerInitialSpawn(ply, transition)
	ply.MA_Role = MA.ROLE_NONE
	MA.CallBase(self, "PlayerInitialSpawn", ply, transition)
end

function GM:MakeSpectator(ply)
	ply.MA_Role = MA.ROLE_NONE
	ply:StripWeapons()
	ply:StripAmmo()
	ply:Spectate(OBS_MODE_ROAMING)
	SendRole(ply)
end

function GM:PlayerSpawn(ply, transition)
	-- Зашёл посреди раунда - наблюдает до следующего раунда
	if GetState() ~= MA.STATE_WAIT and GetRole(ply) == MA.ROLE_NONE then
		self:MakeSpectator(ply)
		return
	end

	MA.CallBase(self, "PlayerSpawn", ply, transition)

	-- Мувмент
	ply:SetWalkSpeed(MA.WALK_SPEED)
	ply:SetRunSpeed(MA.RUN_SPEED)
	ply:SetCrouchedWalkSpeed(MA.CROUCH_SPEED)
	ply:SetJumpPower(MA.JUMP_POWER)
end

function GM:PlayerDeathThink(ply)
	-- Возрождение только через новый раунд (кроме режима ожидания)
	if GetState() == MA.STATE_WAIT or IsSolo() then
		return MA.CallBase(self, "PlayerDeathThink", ply)
	end
end

function GM:PostPlayerDeath(ply)
	if IsSolo() then return end -- в одиночке игрок просто возрождается
	timer.Simple(2.5, function()
		if IsValid(ply) and not ply:Alive() then
			ply:Spectate(OBS_MODE_ROAMING)
		end
	end)
	CheckWin()
end

function GM:PlayerSilentDeath(ply)
	timer.Simple(0.1, CheckWin)
end

function GM:PlayerDisconnected(ply)
	MA.CallBase(self, "PlayerDisconnected", ply)
	timer.Simple(0.3, CheckWin)
end

function GM:PlayerShouldTakeDamage(ply, attacker)
	if GetState() == MA.STATE_PREP then return false end
	return true
end

function GM:PlayerNoClip(ply, desired)
	if desired == false then return true end
	if GetState() == MA.STATE_WAIT then return true end
	return ply:IsAdmin()
end
