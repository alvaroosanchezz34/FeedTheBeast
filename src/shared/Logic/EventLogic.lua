-- Lógica pura de eventos globales.
local Config = script.Parent.Parent.Config
local EventConfig = require(Config.EventConfig)
local Rolls = require(script.Parent.Rolls)

local EventLogic = {}

function EventLogic.pickEvent(rnd, exclude)
	local weights = {}
	for _, id in ipairs(EventConfig.Order) do
		if id ~= exclude then
			weights[id] = EventConfig.Events[id].weight
		end
	end
	return Rolls.weighted(weights, rnd, EventConfig.Order)
end

function EventLogic.nextCooldown(rnd)
	return EventConfig.CooldownMin + (EventConfig.CooldownMax - EventConfig.CooldownMin) * rnd()
end

function EventLogic.giantGoal(playerCount)
	local cfg = EventConfig.Events.GIANT_BEAST
	return cfg.goalBase + cfg.goalPerPlayer * math.max(1, playerCount)
end

-- contributions: { [userId] = puntos }. Devuelve { [userId] = { coins, share, top } } y el total.
-- Cada jugador aparece una sola vez: no hay forma de duplicar recompensa.
function EventLogic.giantRewards(contributions, completed)
	local cfg = EventConfig.Events.GIANT_BEAST
	local total = 0
	local topId, topPoints = nil, 0
	for userId, points in pairs(contributions) do
		if type(points) == "number" and points > 0 and points == points then
			total += points
			if points > topPoints or (points == topPoints and topId ~= nil and tostring(userId) < tostring(topId)) then
				topId, topPoints = userId, points
			end
		end
	end
	local rewards = {}
	if total <= 0 then
		return rewards, 0
	end
	for userId, points in pairs(contributions) do
		if type(points) == "number" and points > 0 and points == points then
			local coins = points * cfg.coinsPerPoint
			if completed then
				coins *= cfg.completionMult
			end
			rewards[userId] = {
				coins = math.min(cfg.maxCoinsPerPlayer, math.floor(coins)),
				share = points / total,
				top = userId == topId,
			}
		end
	end
	return rewards, total
end

-- Probabilidad de la comida secreta para un jugador recompensado.
function EventLogic.truffleChance(reward, completed)
	local cfg = EventConfig.Events.GIANT_BEAST
	if not completed or reward.share < cfg.minSharePercentForBonus then
		return 0
	end
	return reward.top and cfg.truffleChanceTop or cfg.truffleChance
end

return EventLogic
