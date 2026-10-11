-- 20 comidas. `growth` son puntos de crecimiento; `price` 0 = no se vende en tienda.
-- `spawnWeight` controla la aparición en la zona central (0 = nunca aparece sola).
-- `events` lista los eventos en los que puede aparecer. `favoriteOf` da bonus de crecimiento.
local FoodConfig = {}

local function food(def)
	def.consumeTime = def.consumeTime or 0.8
	def.spawnWeight = def.spawnWeight or 0
	def.events = def.events or {}
	def.favoriteOf = def.favoriteOf or {}
	def.marketLevel = def.marketLevel or 0
	return def
end

FoodConfig.Foods = {
	-- Common
	BREAD_CRUMB = food({ id = "BREAD_CRUMB", name = "Crusty Crumb", icon = "🍞", rarity = "Common", price = 5, growth = 4, spawnWeight = 30, shape = "Block", color = Color3.fromRGB(222, 170, 98), vfx = "Crumbs", events = { "FOOD_RAIN" }, favoriteOf = { "GOBBLO" } }),
	APPLE = food({ id = "APPLE", name = "Wobbly Apple", icon = "🍎", rarity = "Common", price = 6, growth = 5, spawnWeight = 26, shape = "Ball", color = Color3.fromRGB(226, 58, 58), vfx = "Juice", events = { "FOOD_RAIN" } }),
	CARROT = food({ id = "CARROT", name = "Crunch Carrot", icon = "🥕", rarity = "Common", price = 8, growth = 6, spawnWeight = 22, shape = "Cylinder", color = Color3.fromRGB(255, 140, 40), vfx = "Crumbs", events = { "FOOD_RAIN" }, favoriteOf = { "CHOMPITO" } }),
	JELLY_BERRIES = food({ id = "JELLY_BERRIES", name = "Jelly Berries", icon = "🫐", rarity = "Common", price = 8, growth = 6, spawnWeight = 20, shape = "Ball", color = Color3.fromRGB(104, 92, 230), vfx = "Juice", events = { "FOOD_RAIN" } }),
	STINKY_CHEESE = food({ id = "STINKY_CHEESE", name = "Stinky Cheese", icon = "🧀", rarity = "Common", price = 10, growth = 7, spawnWeight = 16, shape = "Block", color = Color3.fromRGB(255, 214, 74), vfx = "Crumbs", events = { "FOOD_RAIN" }, favoriteOf = { "TOILETINI" } }),
	MEATBALL = food({ id = "MEATBALL", name = "Mystery Meatball", icon = "🧆", rarity = "Common", price = 12, growth = 8, spawnWeight = 14, shape = "Ball", color = Color3.fromRGB(140, 82, 52), vfx = "Crumbs", events = { "FOOD_RAIN" } }),
	-- Uncommon
	PIZZA = food({ id = "PIZZA", name = "Pizza Slab", icon = "🍕", rarity = "Uncommon", price = 30, growth = 14, spawnWeight = 9, shape = "Block", color = Color3.fromRGB(240, 150, 60), vfx = "Crumbs", consumeTime = 0.9, events = { "FOOD_RAIN" }, favoriteOf = { "GOBBLO" } }),
	DONUT = food({ id = "DONUT", name = "Glazed Donut", icon = "🍩", rarity = "Uncommon", price = 35, growth = 16, spawnWeight = 8, shape = "Cylinder", color = Color3.fromRGB(255, 130, 190), vfx = "Sparkle", consumeTime = 0.9, events = { "FOOD_RAIN" } }),
	BURGER = food({ id = "BURGER", name = "Triple Burger", icon = "🍔", rarity = "Uncommon", price = 40, growth = 18, spawnWeight = 7, shape = "Cylinder", color = Color3.fromRGB(170, 100, 50), vfx = "Crumbs", consumeTime = 1, events = { "FOOD_RAIN" }, favoriteOf = { "CHOMPITO" } }),
	TACO = food({ id = "TACO", name = "Turbo Taco", icon = "🌮", rarity = "Uncommon", price = 45, growth = 20, spawnWeight = 6, shape = "Block", color = Color3.fromRGB(250, 200, 90), vfx = "Crumbs", consumeTime = 1, events = { "FOOD_RAIN" } }),
	SUSHI = food({ id = "SUSHI", name = "Sushi Roll", icon = "🍣", rarity = "Uncommon", price = 50, growth = 22, spawnWeight = 5, shape = "Cylinder", color = Color3.fromRGB(245, 245, 240), vfx = "Juice", consumeTime = 1, events = { "FOOD_RAIN" } }),
	-- Rare
	DINO_STEAK = food({ id = "DINO_STEAK", name = "Dino Steak", icon = "🥩", rarity = "Rare", price = 140, growth = 45, spawnWeight = 2, shape = "Block", color = Color3.fromRGB(200, 60, 70), vfx = "Juice", consumeTime = 1.1, marketLevel = 1, events = { "FOOD_RAIN" }, favoriteOf = { "BANANOSAUR" } }),
	MEGA_MELON = food({ id = "MEGA_MELON", name = "Mega Melon", icon = "🍉", rarity = "Rare", price = 150, growth = 50, spawnWeight = 1.6, shape = "Ball", color = Color3.fromRGB(70, 190, 90), vfx = "Juice", consumeTime = 1.1, marketLevel = 1, events = { "FOOD_RAIN" } }),
	LAYER_CAKE = food({ id = "LAYER_CAKE", name = "Layer Cake", icon = "🍰", rarity = "Rare", price = 170, growth = 55, spawnWeight = 1.2, shape = "Cylinder", color = Color3.fromRGB(255, 190, 220), vfx = "Sparkle", consumeTime = 1.2, marketLevel = 1, events = { "FOOD_RAIN" } }),
	LAVA_RAMEN = food({ id = "LAVA_RAMEN", name = "Lava Ramen", icon = "🍜", rarity = "Rare", price = 190, growth = 60, spawnWeight = 1, shape = "Cylinder", color = Color3.fromRGB(255, 96, 40), vfx = "Sparkle", consumeTime = 1.2, marketLevel = 1, favoriteOf = { "TOILETINI" } }),
	-- Epic
	ROYAL_LOBSTER = food({ id = "ROYAL_LOBSTER", name = "Royal Lobster", icon = "🦞", rarity = "Epic", price = 600, growth = 150, spawnWeight = 0.25, shape = "Block", color = Color3.fromRGB(235, 70, 50), vfx = "Sparkle", consumeTime = 1.3, marketLevel = 2, favoriteOf = { "GLORB" } }),
	THUNDER_HONEY = food({ id = "THUNDER_HONEY", name = "Thunder Honey", icon = "🍯", rarity = "Epic", price = 720, growth = 180, spawnWeight = 0.2, shape = "Cylinder", color = Color3.fromRGB(255, 200, 40), vfx = "Sparkle", consumeTime = 1.3, marketLevel = 2 }),
	GOLDEN_APPLE = food({ id = "GOLDEN_APPLE", name = "Golden Apple", icon = "🍏", rarity = "Epic", price = 0, growth = 200, shape = "Ball", color = Color3.fromRGB(255, 208, 60), vfx = "Gold", consumeTime = 1.3, events = { "GOLDEN_FEAST" } }),
	-- Legendary
	STARFRUIT = food({ id = "STARFRUIT", name = "Starfruit Supreme", icon = "⭐", rarity = "Legendary", price = 2800, growth = 550, spawnWeight = 0.04, shape = "Ball", color = Color3.fromRGB(255, 240, 120), vfx = "Gold", consumeTime = 1.5, marketLevel = 3, events = { "GOLDEN_FEAST" } }),
	-- Secret
	VOID_TRUFFLE = food({ id = "VOID_TRUFFLE", name = "Void Truffle", icon = "🌑", rarity = "Secret", price = 0, growth = 2000, shape = "Ball", color = Color3.fromRGB(60, 20, 90), vfx = "Cosmic", consumeTime = 1.5, events = { "GIANT_BEAST" }, favoriteOf = { "NULLABYTE" } }),
}

FoodConfig.Order = {
	"BREAD_CRUMB", "APPLE", "CARROT", "JELLY_BERRIES", "STINKY_CHEESE", "MEATBALL",
	"PIZZA", "DONUT", "BURGER", "TACO", "SUSHI",
	"DINO_STEAK", "MEGA_MELON", "LAYER_CAKE", "LAVA_RAMEN",
	"ROYAL_LOBSTER", "THUNDER_HONEY", "GOLDEN_APPLE",
	"STARFRUIT",
	"VOID_TRUFFLE",
}

FoodConfig.FavoriteGrowthMult = 1.5
-- Probabilidad por alimentación de que una criatura NORMAL mute, según rareza de la comida.
FoodConfig.MutationChanceByRarity = {
	Common = 0.002,
	Uncommon = 0.005,
	Rare = 0.012,
	Epic = 0.03,
	Legendary = 0.08,
	Secret = 0.25,
}

function FoodConfig.get(id)
	return FoodConfig.Foods[id]
end

function FoodConfig.forEvent(eventId)
	local list = {}
	for _, id in ipairs(FoodConfig.Order) do
		local def = FoodConfig.Foods[id]
		if table.find(def.events, eventId) then
			table.insert(list, id)
		end
	end
	return list
end

return FoodConfig
