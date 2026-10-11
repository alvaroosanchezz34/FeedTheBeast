-- Especies. Los nombres internos (clave) son identificadores estables guardados en datos.
-- `builder` es el nombre del módulo en Shared/Creatures/Species.
local CreatureConfig = {}

CreatureConfig.Species = {
	GOBBLO = {
		id = "GOBBLO",
		name = "Gobblo",
		tagline = "All mouth. No brakes.",
		rarity = "Common",
		builder = "Gobblo",
		baseIncome = 1, -- monedas/segundo a nivel 0
		growthCost = 1, -- multiplicador del crecimiento necesario por nivel
		value = 60,
		maxScale = 2.2,
		baseRadius = 2.5, -- radio aproximado del modelo a escala 1 (studs)
		baseHeight = 4.9,
		idle = "Bounce",
	},
	CHOMPITO = {
		id = "CHOMPITO",
		name = "Chompito",
		tagline = "Tiny legs, giant teeth.",
		rarity = "Uncommon",
		builder = "Chompito",
		baseIncome = 3,
		growthCost = 1.5,
		value = 220,
		maxScale = 2.3,
		baseRadius = 2.4,
		baseHeight = 5.3,
		idle = "Waddle",
	},
	BANANOSAUR = {
		id = "BANANOSAUR",
		name = "Bananosaur",
		tagline = "Prehistoric. Peelable.",
		rarity = "Rare",
		builder = "Bananosaur",
		baseIncome = 8,
		growthCost = 2.5,
		value = 800,
		maxScale = 2.2,
		baseRadius = 2.7,
		baseHeight = 6.9,
		idle = "Sway",
	},
	TOILETINI = {
		id = "TOILETINI",
		name = "Toiletini",
		tagline = "Flushed with success.",
		rarity = "Epic",
		builder = "Toiletini",
		baseIncome = 25,
		growthCost = 4,
		value = 3200,
		maxScale = 2.1,
		baseRadius = 2.5,
		baseHeight = 7.4,
		idle = "Wiggle",
	},
	GLORB = {
		id = "GLORB",
		name = "Glorb",
		tagline = "It sees you. All of you.",
		rarity = "Legendary",
		builder = "Glorb",
		baseIncome = 80,
		growthCost = 7,
		value = 14000,
		maxScale = 2.3,
		baseRadius = 2.5,
		baseHeight = 7.0,
		idle = "Float",
	},
	NULLABYTE = {
		id = "NULLABYTE",
		name = "Nullabyte",
		tagline = "It was never supposed to hatch.",
		rarity = "Secret",
		builder = "Nullabyte",
		baseIncome = 300,
		growthCost = 12,
		value = 90000,
		maxScale = 2.4,
		baseRadius = 2.8,
		baseHeight = 7,
		idle = "Glitch",
	},
}

-- Orden de presentación en la colección.
CreatureConfig.Order = { "GOBBLO", "CHOMPITO", "BANANOSAUR", "TOILETINI", "GLORB", "NULLABYTE" }

-- Evolución: al alcanzar estos niveles la criatura pasa a la etapa siguiente (2, 3...). Cada
-- especie define qué piezas aparecen en cada etapa; aquí solo viven los umbrales y el bonus.
CreatureConfig.EvolutionLevels = { 15, 35 }
CreatureConfig.StageIncomeMult = { 1, 1.25, 1.6 }
CreatureConfig.StageNames = { "Baby", "Evolved", "Apex" }

CreatureConfig.BaseMaxLevel = 50
CreatureConfig.MaxLevelPerRebirth = 5
CreatureConfig.AbsoluteMaxLevel = 100

-- Las colisiones nunca crecen más que esto aunque la escala visual sí lo haga.
CreatureConfig.HitboxMaxScale = 1.6
CreatureConfig.MaxOwned = 30

function CreatureConfig.get(id)
	return CreatureConfig.Species[id]
end

function CreatureConfig.byRarity(rarity)
	local list = {}
	for _, id in ipairs(CreatureConfig.Order) do
		if CreatureConfig.Species[id].rarity == rarity then
			table.insert(list, id)
		end
	end
	return list
end

return CreatureConfig
