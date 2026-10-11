-- Operaciones puras sobre el inventario de comida de un perfil.
local FoodConfig = require(script.Parent.Parent.Config.FoodConfig)

local Inventory = {}

function Inventory.count(profile)
	local total = 0
	for _, n in pairs(profile.inventory) do
		total += n
	end
	return total
end

function Inventory.get(profile, foodId)
	return profile.inventory[foodId] or 0
end

-- Añade hasta `amount` respetando la capacidad. Devuelve cuántas se añadieron.
function Inventory.add(profile, foodId, amount, capacity)
	if not FoodConfig.Foods[foodId] or type(amount) ~= "number" or amount <= 0 then
		return 0
	end
	amount = math.floor(amount)
	local free = math.max(0, capacity - Inventory.count(profile))
	local added = math.min(amount, free)
	if added > 0 then
		profile.inventory[foodId] = (profile.inventory[foodId] or 0) + added
	end
	return added
end

-- Quita exactamente `amount` o no quita nada. Devuelve true si se quitó.
function Inventory.remove(profile, foodId, amount)
	amount = amount or 1
	local have = profile.inventory[foodId] or 0
	if amount <= 0 or have < amount then
		return false
	end
	local left = have - amount
	profile.inventory[foodId] = left > 0 and left or nil
	return true
end

return Inventory
