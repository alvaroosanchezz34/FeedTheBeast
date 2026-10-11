-- Cajas de comida transportables y robables. Nunca se roban criaturas.
local TheftConfig = {
	SpawnInterval = 40,
	MaxActive = 3,
	GroundLifetime = 120,

	HoldDuration = 0.7, -- segundos manteniendo el prompt para robar
	StealDistance = 11,
	PickupDistance = 12,
	DeliverDistance = 16,
	StealCooldown = 4, -- por ladrón
	TransferImmunity = 3, -- la caja queda PROTECTED tras cambiar de manos
	RecoveryWindow = 25, -- si la víctima la recupera en este tiempo cuenta como RECOVERED
	BaseCarrySlow = 0.78, -- ver UpgradeConfig.Effects (se usa el de mejoras)
	-- Anti-teleport: si el portador se mueve más rápido que speed * factor, suelta la caja.
	SpeedCheckInterval = 0.5,
	SpeedTolerance = 2.6,

	HeistBonusMult = 1.5, -- entregar una caja robada
	RecoveryBonusCoins = 25,
	RecoveryBonusIncomeSeconds = 10,

	Tiers = {
		WOOD = {
			id = "WOOD", name = "Snack Crate", weight = 70, color = Color3.fromRGB(176, 120, 66),
			material = Enum.Material.WoodPlanks, rolls = 3, rarities = { Common = 70, Uncommon = 30 },
			coins = 40, incomeSeconds = 30,
		},
		SILVER = {
			id = "SILVER", name = "Feast Crate", weight = 25, color = Color3.fromRGB(190, 200, 215),
			material = Enum.Material.Metal, rolls = 3, rarities = { Uncommon = 60, Rare = 40 },
			coins = 150, incomeSeconds = 60,
		},
		GOLD = {
			id = "GOLD", name = "Royal Crate", weight = 5, color = Color3.fromRGB(255, 200, 50),
			material = Enum.Material.Foil, rolls = 3, rarities = { Rare = 65, Epic = 33, Legendary = 2 },
			coins = 600, incomeSeconds = 120,
		},
	},
	TierOrder = { "WOOD", "SILVER", "GOLD" },
}

return TheftConfig
