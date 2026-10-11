DeriveGamemode("sandbox")

GM.Name    = "Murder Alt"
GM.Author  = "ertyquake"
GM.Email   = ""
GM.Website = ""

MA = MA or {}

-- Состояния раунда
MA.STATE_WAIT   = 0
MA.STATE_PREP   = 1
MA.STATE_ACTIVE = 2
MA.STATE_END    = 3

-- Роли
MA.ROLE_NONE     = 0
MA.ROLE_INNOCENT = 1
MA.ROLE_TRAITOR  = 2

-- Победители
MA.WIN_INNOCENT = 1
MA.WIN_TRAITOR  = 2

-- Настройки
MA.MIN_PLAYERS         = 2   -- минимум игроков для начала раунда
MA.PREP_TIME           = 5   -- сколько секунд показывается роль перед стартом
MA.END_TIME            = 7   -- пауза после победы перед новым раундом
MA.PLAYERS_PER_TRAITOR = 8   -- 1 трейтор на каждые 8 игроков (минимум 1)

-- Оружие, которое нельзя выбросить через колесо действий
MA.UNDROPPABLE = {
	ma_hands = true,
	weapon_hands = true,
	weapon_fists = true,
}

-- Звук начала раунда (файл лежит в content/sound/murder_alt/)
MA.ROUND_SOUND = "murder_alt/round_start.mp3"

-- Движение
MA.WALK_SPEED    = 190
MA.RUN_SPEED     = 300
MA.CROUCH_SPEED  = 0.4
MA.JUMP_POWER    = 200

-- Безопасный вызов функции базового геймода
function MA.CallBase(gm, name, ...)
	local base = gm.BaseClass
	if base then
		local f = base[name]
		if f then return f(gm, ...) end
	end
end
