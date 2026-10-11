-- Tareas (contratos diarios). Cada día (UTC) cada jugador recibe `DailyCount` tareas de este
-- catálogo, de categorías distintas para que no sea todo "repite lo mismo". Completar las tres
-- da un premio extra. Las recompensas las calcula y concede el servidor, una sola vez.
--
-- event: contador que hace avanzar la tarea (ver QuestService.progress).
-- coins: monedas fijas; incomeSeconds: + segundos de la producción actual del jugador.
local QuestConfig = {}

QuestConfig.DailyCount = 3
QuestConfig.DaySeconds = 86400
QuestConfig.MaxRewardCoins = 5e8

QuestConfig.Quests = {
	COLLECT = { id = "COLLECT", category = "gather", icon = "🧺", name = "Snack Run", desc = "Collect %d food", event = "FoodCollected", goal = 15, coins = 120, incomeSeconds = 45 },
	COLLECT_BIG = { id = "COLLECT_BIG", category = "gather", icon = "🧺", name = "Stock the Pantry", desc = "Collect %d food", event = "FoodCollected", goal = 40, coins = 300, incomeSeconds = 90 },
	FEED = { id = "FEED", category = "feed", icon = "🍽️", name = "Dinner Time", desc = "Feed your beasts %d times", event = "Fed", goal = 12, coins = 150, incomeSeconds = 45 },
	FEED_RARE = { id = "FEED_RARE", category = "feed", icon = "🥩", name = "Fine Dining", desc = "Feed %d Rare or better foods", event = "FedRare", goal = 3, coins = 400, incomeSeconds = 90, food = "MEGA_MELON" },
	FAVORITE = { id = "FAVORITE", category = "feed", icon = "❤️", name = "Just What I Wanted", desc = "Feed a beast its favourite food %d times", event = "FedFavorite", goal = 4, coins = 220, incomeSeconds = 60 },
	LEVEL = { id = "LEVEL", category = "grow", icon = "📈", name = "Growth Spurt", desc = "Gain %d beast levels", event = "LevelUp", goal = 5, coins = 250, incomeSeconds = 75 },
	COINS = { id = "COINS", category = "coins", icon = "💰", name = "Payday", desc = "Collect coins from your gold pad %d times", event = "PadCollected", goal = 5, coins = 150, incomeSeconds = 60 },
	HATCH = { id = "HATCH", category = "collect", icon = "🥚", name = "New Arrival", desc = "Hatch %d egg", event = "Hatched", goal = 1, coins = 200, incomeSeconds = 60, food = "DONUT" },
	CRATE = { id = "CRATE", category = "crates", icon = "📦", name = "Special Delivery", desc = "Deliver %d crate to your blue pad", event = "CrateDelivered", goal = 1, coins = 250, incomeSeconds = 60 },
	CRATES = { id = "CRATES", category = "crates", icon = "📦", name = "Crate Hauler", desc = "Deliver %d crates to your blue pad", event = "CrateDelivered", goal = 3, coins = 600, incomeSeconds = 120, food = "DINO_STEAK" },
	EVENT = { id = "EVENT", category = "event", icon = "🎉", name = "Party Animal", desc = "Grab or feed %d times during a server event", event = "EventAction", goal = 6, coins = 300, incomeSeconds = 90 },
	SHOP = { id = "SHOP", category = "coins", icon = "🛒", name = "Big Spender", desc = "Buy %d upgrade", event = "UpgradeBought", goal = 1, coins = 180, incomeSeconds = 45 },
}

QuestConfig.Order = { "COLLECT", "COLLECT_BIG", "FEED", "FEED_RARE", "FAVORITE", "LEVEL", "COINS", "HATCH", "CRATE", "CRATES", "EVENT", "SHOP" }

-- Premio por completar y reclamar las tres del día.
QuestConfig.Bonus = { coins = 500, incomeSeconds = 180, food = "LAYER_CAKE", foodAmount = 2 }

function QuestConfig.get(id)
	return QuestConfig.Quests[id]
end

return QuestConfig
