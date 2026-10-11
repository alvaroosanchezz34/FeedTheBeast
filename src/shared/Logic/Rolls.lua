-- Tiradas aleatorias puras. `rnd` es una función que devuelve un número en [0, 1).
local Config = script.Parent.Parent.Config
local CreatureConfig = require(Config.CreatureConfig)
local MutationConfig = require(Config.MutationConfig)
local FoodConfig = require(Config.FoodConfig)
local RarityConfig = require(Config.RarityConfig)

local Rolls = {}

-- weights: { clave = peso }. `order` opcional para que el resultado sea determinista.
function Rolls.weighted(weights, rnd, order)
	local keys = order
	if not keys then
		keys = {}
		for key in pairs(weights) do
			table.insert(keys, key)
		end
		table.sort(keys)
	end
	local total = 0
	for _, key in ipairs(keys) do
		local w = weights[key]
		if type(w) == "number" and w > 0 then
			total += w
		end
	end
	if total <= 0 then
		return nil
	end
	local roll = rnd() * total
	local acc = 0
	local last = nil
	for _, key in ipairs(keys) do
		local w = weights[key]
		if type(w) == "number" and w > 0 then
			acc += w
			last = key
			if roll < acc then
				return key
			end
		end
	end
	return last
end

function Rolls.species(egg, rnd)
	local rarity = Rolls.weighted(egg.weights, rnd, RarityConfig.Order)
	if not rarity then
		return nil
	end
	-- Si no hay especie de esa rareza, baja hasta encontrar una.
	local index = RarityConfig.Index[rarity]
	while index >= 1 do
		local candidates = CreatureConfig.byRarity(RarityConfig.Order[index])
		if #candidates > 0 then
			return candidates[math.min(#candidates, math.floor(rnd() * #candidates) + 1)]
		end
		index -= 1
	end
	return nil
end

-- Mutación al nacer. `luck` multiplica las probabilidades de mutación.
function Rolls.hatchMutation(luck, rnd)
	luck = luck or 1
	local roll = rnd()
	local acc = 0
	-- De la más rara a la más común para que la suerte no "tape" las raras.
	for i = #MutationConfig.Order, 1, -1 do
		local def = MutationConfig.Mutations[MutationConfig.Order[i]]
		if def.hatchWeight > 0 then
			acc += math.min(1, def.hatchWeight * luck)
			if roll < acc then
				return def.id
			end
		end
	end
	return "NORMAL"
end

-- Mutación al alimentar: solo criaturas NORMAL. Devuelve id de mutación o nil.
function Rolls.feedMutation(currentMutation, foodId, rnd)
	if currentMutation ~= "NORMAL" then
		return nil
	end
	local food = FoodConfig.Foods[foodId]
	if not food then
		return nil
	end
	local chance = FoodConfig.MutationChanceByRarity[food.rarity] or 0
	if rnd() >= chance then
		return nil
	end
	local weights = {}
	for _, id in ipairs(MutationConfig.Order) do
		weights[id] = MutationConfig.Mutations[id].feedWeight
	end
	return Rolls.weighted(weights, rnd, MutationConfig.Order)
end

-- Comida aleatoria según `spawnWeight` (zona central).
function Rolls.fieldFood(rnd)
	local weights = {}
	for _, id in ipairs(FoodConfig.Order) do
		weights[id] = FoodConfig.Foods[id].spawnWeight
	end
	return Rolls.weighted(weights, rnd, FoodConfig.Order)
end

-- Comida aleatoria de un evento (ponderada inversamente a la rareza).
function Rolls.eventFood(eventId, rnd)
	local list = FoodConfig.forEvent(eventId)
	if #list == 0 then
		return nil
	end
	local weights = {}
	for _, id in ipairs(list) do
		local def = FoodConfig.Foods[id]
		local w = def.spawnWeight
		if w <= 0 then
			w = 1 / RarityConfig.Rarities[def.rarity].valueMult
		end
		weights[id] = w
	end
	return Rolls.weighted(weights, rnd, list)
end

-- Comida aleatoria de una rareza dada (para cajas).
function Rolls.foodOfRarity(rarity, rnd)
	local list = {}
	for _, id in ipairs(FoodConfig.Order) do
		local def = FoodConfig.Foods[id]
		if def.rarity == rarity and #def.events <= 1 and def.price > 0 then
			table.insert(list, id)
		end
	end
	if #list == 0 then
		return nil
	end
	return list[math.min(#list, math.floor(rnd() * #list) + 1)]
end

return Rolls
