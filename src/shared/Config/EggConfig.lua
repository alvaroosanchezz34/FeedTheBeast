-- Huevos comprados con monedas. `weights` es por rareza; la especie se elige dentro de la rareza.
local EggConfig = {}

EggConfig.Eggs = {
	BASIC = {
		id = "BASIC", name = "Basic Egg", icon = "🥚", price = 150, hatcheryLevel = 0,
		weights = { Common = 70, Uncommon = 24, Rare = 5.5, Epic = 0.5 },
		mutationLuck = 1,
	},
	FANCY = {
		id = "FANCY", name = "Fancy Egg", icon = "🪺", price = 1500, hatcheryLevel = 1,
		weights = { Uncommon = 50, Rare = 35, Epic = 13, Legendary = 2 },
		mutationLuck = 1.5,
	},
	ROYAL = {
		id = "ROYAL", name = "Royal Egg", icon = "👑", price = 15000, hatcheryLevel = 2,
		weights = { Rare = 40, Epic = 40, Legendary = 19.5, Secret = 0.5 },
		mutationLuck = 2,
	},
}

EggConfig.Order = { "BASIC", "FANCY", "ROYAL" }

function EggConfig.get(id)
	return EggConfig.Eggs[id]
end

return EggConfig
