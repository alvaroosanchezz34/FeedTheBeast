-- Mejoras compradas con monedas. cost(level) = baseCost * costGrowth ^ level  (level = nivel actual)
local UpgradeConfig = {}

UpgradeConfig.Upgrades = {
	INVENTORY = { id = "INVENTORY", name = "Bigger Backpack", icon = "🎒", desc = "+5 food slots", baseCost = 40, costGrowth = 1.7, maxLevel = 10 },
	HARVEST = { id = "HARVEST", name = "Greedy Hands", icon = "🧤", desc = "+10% chance to grab double food", baseCost = 60, costGrowth = 2, maxLevel = 5 },
	PRODUCTION = { id = "PRODUCTION", name = "Coin Glands", icon = "💰", desc = "+10% coin production", baseCost = 100, costGrowth = 1.55, maxLevel = 20 },
	CARRY_SPEED = { id = "CARRY_SPEED", name = "Strong Legs", icon = "🦵", desc = "Run faster while carrying crates", baseCost = 120, costGrowth = 2, maxLevel = 5 },
	SLOTS = { id = "SLOTS", name = "Extra Pen", icon = "🏠", desc = "+1 creature slot on your plot", baseCost = 500, costGrowth = 8, maxLevel = 3 },
	SHIELD = { id = "SHIELD", name = "Crate Shield", icon = "🛡️", desc = "+2s steal protection after grabbing a crate", baseCost = 400, costGrowth = 3, maxLevel = 3 },
	MARKET = { id = "MARKET", name = "Market License", icon = "🛒", desc = "Unlocks rarer food in the shop", baseCost = 800, costGrowth = 6, maxLevel = 3 },
	HATCHERY = { id = "HATCHERY", name = "Hatchery", icon = "🥚", desc = "Unlocks better eggs", baseCost = 1200, costGrowth = 10, maxLevel = 2 },
	PLOT_STYLE = { id = "PLOT_STYLE", name = "Plot Makeover", icon = "🎨", desc = "Fancier plot (kept on rebirth)", baseCost = 300, costGrowth = 5, maxLevel = 4, cosmetic = true },
}

UpgradeConfig.Order = { "INVENTORY", "PRODUCTION", "HARVEST", "SLOTS", "CARRY_SPEED", "SHIELD", "MARKET", "HATCHERY", "PLOT_STYLE" }

UpgradeConfig.Effects = {
	BaseInventory = 10,
	InventoryPerLevel = 5,
	HarvestDoubleChancePerLevel = 0.1,
	ProductionPerLevel = 0.1,
	BaseSlots = 3,
	CarrySpeedBase = 0.78,
	CarrySpeedPerLevel = 0.044,
	ShieldSecondsPerLevel = 2,
}

-- Estilos visuales de parcela por nivel de PLOT_STYLE (0..4).
UpgradeConfig.PlotStyles = {
	[0] = { floor = Enum.Material.Grass, trim = Enum.Material.WoodPlanks, glow = false },
	[1] = { floor = Enum.Material.Cobblestone, trim = Enum.Material.Wood, glow = false },
	[2] = { floor = Enum.Material.Marble, trim = Enum.Material.Metal, glow = false },
	[3] = { floor = Enum.Material.Marble, trim = Enum.Material.Neon, glow = true },
	[4] = { floor = Enum.Material.Glass, trim = Enum.Material.Neon, glow = true },
}

function UpgradeConfig.get(id)
	return UpgradeConfig.Upgrades[id]
end

return UpgradeConfig
