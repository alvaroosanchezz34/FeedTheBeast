-- Lógica pura de las tareas diarias: elección determinista, progreso y reclamación idempotente.
local QuestConfig = require(script.Parent.Parent.Config.QuestConfig)
local EconomyConfig = require(script.Parent.Parent.Config.EconomyConfig)

local QuestLogic = {}

function QuestLogic.dayOf(unix)
	return math.floor((unix or 0) / QuestConfig.DaySeconds)
end

function QuestLogic.secondsLeft(unix)
	return QuestConfig.DaySeconds - (unix % QuestConfig.DaySeconds)
end

-- Generador determinista sencillo (mismo día + mismo jugador = mismas tareas).
local function lcg(seed)
	local state = seed % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return function()
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
end

-- Elige las tareas del día: una por categoría como máximo.
function QuestLogic.pick(day, userId)
	local rnd = lcg(day * 7919 + (userId % 100000) * 31 + 17)
	local pool = table.clone(QuestConfig.Order)
	local picked, usedCategories = {}, {}
	while #picked < QuestConfig.DailyCount and #pool > 0 do
		local index = math.min(#pool, math.floor(rnd() * #pool) + 1)
		local id = table.remove(pool, index)
		local def = QuestConfig.Quests[id]
		if not usedCategories[def.category] then
			usedCategories[def.category] = true
			table.insert(picked, { id = id, progress = 0, claimed = false })
		end
	end
	return picked
end

-- Renueva el tablero si ha cambiado el día. Devuelve true si lo renovó.
function QuestLogic.refresh(profile, unix, userId)
	local day = QuestLogic.dayOf(unix)
	local quests = profile.quests
	if type(quests) ~= "table" or quests.day ~= day or type(quests.list) ~= "table" or #quests.list == 0 then
		profile.quests = { day = day, list = QuestLogic.pick(day, userId), bonusClaimed = false }
		return true
	end
	return false
end

-- Suma progreso a las tareas del evento. Devuelve la lista de índices recién completados.
function QuestLogic.progress(profile, event, amount)
	local completed = {}
	local quests = profile.quests
	if type(quests) ~= "table" or type(amount) ~= "number" or amount <= 0 or amount ~= amount then
		return completed, false
	end
	local changed = false
	for index, entry in ipairs(quests.list) do
		local def = QuestConfig.Quests[entry.id]
		if def and def.event == event and not entry.claimed and entry.progress < def.goal then
			entry.progress = math.min(def.goal, entry.progress + math.floor(amount))
			changed = true
			if entry.progress >= def.goal then
				table.insert(completed, index)
			end
		end
	end
	return completed, changed
end

function QuestLogic.rewardCoins(def, incomePerSecond)
	local coins = (def.coins or 0) + math.max(0, incomePerSecond or 0) * (def.incomeSeconds or 0)
	return math.floor(math.clamp(coins, 0, math.min(QuestConfig.MaxRewardCoins, EconomyConfig.MaxCoins)))
end

-- Reclama una tarea. Devuelve (def, nil) o (nil, motivo). Marca `claimed` ANTES de que el
-- llamador conceda la recompensa: una petición repetida no puede cobrar dos veces.
function QuestLogic.claim(profile, index)
	local quests = profile.quests
	local entry = type(quests) == "table" and quests.list[index] or nil
	if not entry then
		return nil, "no_quest"
	end
	local def = QuestConfig.Quests[entry.id]
	if not def then
		return nil, "no_quest"
	end
	if entry.claimed then
		return nil, "already_claimed"
	end
	if entry.progress < def.goal then
		return nil, "not_done"
	end
	entry.claimed = true
	return def, nil
end

function QuestLogic.allClaimed(profile)
	local quests = profile.quests
	if type(quests) ~= "table" or #quests.list == 0 then
		return false
	end
	for _, entry in ipairs(quests.list) do
		if not entry.claimed then
			return false
		end
	end
	return true
end

function QuestLogic.claimBonus(profile)
	if not QuestLogic.allClaimed(profile) then
		return false, "not_done"
	end
	if profile.quests.bonusClaimed then
		return false, "already_claimed"
	end
	profile.quests.bonusClaimed = true
	return true, nil
end

return QuestLogic
