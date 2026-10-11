-- Eventos globales del servidor. Probabilidades, duración, cooldowns y recompensas centralizados.
local EventConfig = {
	Enabled = true,
	FirstDelay = 100,
	CooldownMin = 150,
	CooldownMax = 240,
	AnnounceLead = 6, -- segundos de aviso antes de empezar

	Events = {
		FOOD_RAIN = {
			id = "FOOD_RAIN",
			name = "FOOD RAIN",
			desc = "Food is falling in the plaza. Grab it first!",
			icon = "🌧️",
			weight = 50,
			duration = 45,
			spawnInterval = 0.35,
			maxActive = 70,
			dropHeight = 60,
			color = Color3.fromRGB(110, 190, 255),
		},
		GOLDEN_FEAST = {
			id = "GOLDEN_FEAST",
			name = "GOLDEN FEAST",
			desc = "Golden food appears and coin production is boosted!",
			icon = "✨",
			weight = 30,
			duration = 60,
			spawnInterval = 1.4,
			maxActive = 30,
			incomeMult = 1.5,
			crateRewardMult = 2,
			color = Color3.fromRGB(255, 205, 60),
		},
		GIANT_BEAST = {
			id = "GIANT_BEAST",
			name = "GIANT BEAST",
			desc = "A giant beast is starving! Feed it together for rewards.",
			icon = "👹",
			weight = 20,
			duration = 90,
			goalBase = 120,
			goalPerPlayer = 100,
			scale = 4.5,
			coinsPerPoint = 3,
			completionMult = 2,
			maxCoinsPerPlayer = 250000,
			minSharePercentForBonus = 0.1,
			truffleChance = 0.05,
			truffleChanceTop = 0.2,
			feedCooldown = 0.35,
			color = Color3.fromRGB(255, 90, 90),
		},
	},
}

EventConfig.Order = { "FOOD_RAIN", "GOLDEN_FEAST", "GIANT_BEAST" }

return EventConfig
