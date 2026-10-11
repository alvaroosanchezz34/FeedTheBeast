-- Tareas diarias. Los demás servicios informan de lo que ocurre con QuestService.progress y aquí
-- se lleva la cuenta, se renueva el tablero al cambiar el día y se conceden las recompensas
-- (una sola vez por tarea, validado en servidor).
--
-- API:
--   QuestService.progress(session, event, amount?)
--   QuestService.view(session) -> datos para la interfaz
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local QuestConfig = require(Shared.Config.QuestConfig)
local FoodConfig = require(Shared.Config.FoodConfig)
local QuestLogic = require(Shared.Logic.QuestLogic)
local Utilities = require(Shared.Utilities)
local Clock = require(Shared.Clock)

local QuestService = {}

local services
local timer = 0

local function rewardText(def, income)
	local text = Utilities.formatNumber(QuestLogic.rewardCoins(def, income)) .. " coins"
	if def.food and FoodConfig.Foods[def.food] then
		text ..= " + " .. (def.foodAmount or 1) .. "x " .. FoodConfig.Foods[def.food].name
	end
	return text
end

function QuestService.view(session)
	local profile = session.profile
	local quests = profile.quests
	local income = services.EconomyService.income(session)
	local list = {}
	if type(quests) == "table" then
		for index, entry in ipairs(quests.list) do
			local def = QuestConfig.Quests[entry.id]
			if def then
				table.insert(list, {
					index = index,
					id = def.id,
					icon = def.icon,
					name = def.name,
					desc = string.format(def.desc, def.goal),
					progress = entry.progress,
					goal = def.goal,
					done = entry.progress >= def.goal,
					claimed = entry.claimed,
					reward = rewardText(def, income),
				})
			end
		end
	end
	return {
		list = list,
		resetAt = Clock.unix() + QuestLogic.secondsLeft(Clock.unix()),
		bonus = {
			reward = rewardText(QuestConfig.Bonus, income),
			ready = QuestLogic.allClaimed(profile) and not (quests and quests.bonusClaimed),
			claimed = quests ~= nil and quests.bonusClaimed == true,
		},
	}
end

function QuestService.progress(session, event, amount)
	if not session or not session.profile then
		return
	end
	local completed, changed = QuestLogic.progress(session.profile, event, amount or 1)
	if not changed then
		return
	end
	services.StateService.push(session.userId, "quests")
	for _, index in ipairs(completed) do
		local def = QuestConfig.Quests[session.profile.quests.list[index].id]
		services.ValidationService.notify(session.player, "Task complete: " .. def.name .. "! Claim it in TASKS.", "reward", "📋")
	end
end

local function grant(session, def)
	local coins = QuestLogic.rewardCoins(def, services.EconomyService.income(session))
	services.EconomyService.addCoins(session.userId, coins)
	local foodText = ""
	if def.food and FoodConfig.Foods[def.food] then
		local wanted = def.foodAmount or 1
		local added = services.FoodService.give(session, def.food, wanted)
		if added < wanted then
			-- Mochila llena: lo que no cabe se paga en monedas, nunca se pierde.
			services.EconomyService.addCoins(session.userId, FoodConfig.Foods[def.food].price * (wanted - added))
		end
		foodText = " + " .. FoodConfig.Foods[def.food].icon
	end
	return coins, foodText
end

function QuestService.claim(session, index)
	local def, reason = QuestLogic.claim(session.profile, index)
	if not def then
		return false, reason
	end
	local coins, foodText = grant(session, def)
	session.profile.stats.questsClaimed = (session.profile.stats.questsClaimed or 0) + 1
	services.StateService.push(session.userId, "quests", "stats")
	services.ValidationService.notify(session.player, string.format("%s: +%s coins%s", def.name, Utilities.formatNumber(coins), foodText), "reward", def.icon)
	return true, nil
end

function QuestService.claimBonus(session)
	local ok, reason = QuestLogic.claimBonus(session.profile)
	if not ok then
		return false, reason
	end
	local coins, foodText = grant(session, QuestConfig.Bonus)
	services.StateService.push(session.userId, "quests")
	services.ValidationService.notify(session.player, string.format("Daily bonus: +%s coins%s", Utilities.formatNumber(coins), foodText), "reward", "🎁")
	local position = services.CharacterService.positionOf(session.userId)
	if position then
		services.VFXService.playFor(session.player, "Purchase", { position = position, radius = 2 })
	end
	return true, nil
end

function QuestService.Init(allServices)
	services = allServices
end

function QuestService.Start()
	services.PlayerDataService.SessionStarted:Connect(function(session)
		QuestLogic.refresh(session.profile, Clock.unix(), session.userId)
		services.StateService.push(session.userId, "quests")
	end)
	services.ValidationService.on("ClaimQuest", function(player, index)
		local session = services.PlayerDataService.sessionOf(player)
		if session then
			QuestService.claim(session, index)
		end
	end)
	services.ValidationService.on("ClaimQuestBonus", function(player)
		local session = services.PlayerDataService.sessionOf(player)
		if session then
			QuestService.claimBonus(session)
		end
	end)
end

-- Cambio de día con el jugador conectado.
function QuestService.Update(dt)
	timer += dt
	if timer < 20 then
		return
	end
	timer = 0
	local now = Clock.unix()
	services.PlayerDataService.forEach(function(session)
		if QuestLogic.refresh(session.profile, now, session.userId) then
			services.StateService.push(session.userId, "quests")
			services.ValidationService.notify(session.player, "New daily tasks are ready!", "info", "📋")
		end
	end)
end

return QuestService
