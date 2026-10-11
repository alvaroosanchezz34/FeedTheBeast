-- Todas las fórmulas y multiplicadores económicos están centralizados aquí
-- (las fórmulas en sí viven en Logic/EconomyMath, que lee esta tabla).
local EconomyConfig = {
	-- Crecimiento acumulado necesario para el nivel L: GrowthBase * growthCost * L ^ GrowthExponent
	GrowthBase = 10,
	GrowthExponent = 1.5,

	-- Producción: baseIncome * (1 + level * IncomePerLevel) * mutación * mejoras * renacimientos...
	IncomePerLevel = 0.12,

	-- Monedas inmediatas al alimentar (por punto de crecimiento aplicado).
	FeedCoinsPerGrowth = 1,
	FirstFeedBonus = 25,

	ProductionTick = 1,
	-- Las ganancias sin recoger se acumulan hasta este tope (en segundos de producción).
	PendingCapSeconds = 1800,
	PendingCapMin = 250,

	Offline = {
		MaxSeconds = 8 * 3600,
		Rate = 0.5,
		MinSeconds = 60,
	},

	SellRefund = 0.5,
	SellValuePerLevel = 0.1,
	MaxCoins = 1e15,
	MaxBuyQuantity = 50,

	VIPIncomeMult = 1.2,
	GrowthBoostMult = 2,

	Rebirth = {
		BaseCost = 25000,
		CostGrowth = 4,
		RequiredLevel = 15,
		RequiredLevelPerRebirth = 5,
		RequiredLevelMax = 50,
		IncomeMultPerRebirth = 0.5,
		-- Mejoras que NO se reinician.
		KeepUpgrades = { PLOT_STYLE = true },
		MaxRebirths = 100,
	},
}

return EconomyConfig
