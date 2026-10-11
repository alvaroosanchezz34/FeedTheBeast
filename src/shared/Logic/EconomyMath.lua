-- Fórmulas económicas puras (sin dependencias de Roblox). El servidor es el único que las
-- usa con autoridad; el cliente solo las usa para mostrar previsualizaciones.
local Config = script.Parent.Parent.Config
local EconomyConfig = require(Config.EconomyConfig)
local CreatureConfig = require(Config.CreatureConfig)
local MutationConfig = require(Config.MutationConfig)
local UpgradeConfig = require(Config.UpgradeConfig)
local FoodConfig = require(Config.FoodConfig)

local EconomyMath = {}

EconomyMath.MinScale = 0.6
EconomyMath.ScaleExponent = 0.6

local function isFinite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end
EconomyMath.isFinite = isFinite

function EconomyMath.maxLevel(rebirths)
	rebirths = math.max(0, rebirths or 0)
	return math.min(
		CreatureConfig.AbsoluteMaxLevel,
		CreatureConfig.BaseMaxLevel + rebirths * CreatureConfig.MaxLevelPerRebirth
	)
end

-- Crecimiento acumulado necesario para alcanzar `level`.
function EconomyMath.growthForLevel(speciesId, level)
	local species = CreatureConfig.Species[speciesId]
	if not species or level <= 0 then
		return 0
	end
	return EconomyConfig.GrowthBase * species.growthCost * level ^ EconomyConfig.GrowthExponent
end

-- Devuelve (nivel, progreso 0..1 hacia el siguiente nivel).
function EconomyMath.levelFromGrowth(speciesId, growth, maxLevel)
	local species = CreatureConfig.Species[speciesId]
	if not species or not isFinite(growth) or growth <= 0 then
		return 0, 0
	end
	maxLevel = maxLevel or CreatureConfig.BaseMaxLevel
	local unit = EconomyConfig.GrowthBase * species.growthCost
	local level = math.floor((growth / unit) ^ (1 / EconomyConfig.GrowthExponent) + 1e-9)
	-- Corrige errores de coma flotante.
	while level > 0 and EconomyMath.growthForLevel(speciesId, level) > growth + 1e-6 do
		level -= 1
	end
	while EconomyMath.growthForLevel(speciesId, level + 1) <= growth + 1e-6 do
		level += 1
	end
	if level >= maxLevel then
		return maxLevel, 0
	end
	local floorGrowth = EconomyMath.growthForLevel(speciesId, level)
	local nextGrowth = EconomyMath.growthForLevel(speciesId, level + 1)
	local progress = (growth - floorGrowth) / (nextGrowth - floorGrowth)
	return level, math.clamp(progress, 0, 1)
end

-- Crecimiento máximo almacenable (el del nivel máximo).
function EconomyMath.maxGrowth(speciesId, maxLevel)
	return EconomyMath.growthForLevel(speciesId, maxLevel)
end

-- Escala visual lógica (la que se guarda/replica). Empieza en MinScale y llega a maxScale
-- en BaseMaxLevel; los niveles extra de renacimiento no aumentan más el tamaño.
function EconomyMath.scaleFor(speciesId, level, progress)
	local species = CreatureConfig.Species[speciesId]
	if not species then
		return 1
	end
	local t = math.clamp((level + (progress or 0)) / CreatureConfig.BaseMaxLevel, 0, 1)
	return EconomyMath.MinScale + (species.maxScale - EconomyMath.MinScale) * t ^ EconomyMath.ScaleExponent
end

function EconomyMath.scaleFromGrowth(speciesId, growth, maxLevel)
	local level, progress = EconomyMath.levelFromGrowth(speciesId, growth, maxLevel)
	return EconomyMath.scaleFor(speciesId, level, progress), level, progress
end

-- Las colisiones crecen menos que la escala visual.
function EconomyMath.hitboxScale(scale)
	return math.min(scale, CreatureConfig.HitboxMaxScale)
end

-- Etapa de evolución (1..n) para un nivel.
function EconomyMath.stageFor(level)
	local stage = 1
	for _, threshold in ipairs(CreatureConfig.EvolutionLevels) do
		if (level or 0) >= threshold then
			stage += 1
		end
	end
	return stage
end

function EconomyMath.creatureIncome(creature, maxLevel)
	local species = CreatureConfig.Species[creature.species]
	if not species then
		return 0
	end
	local mutation = MutationConfig.Mutations[creature.mutation] or MutationConfig.Mutations.NORMAL
	local level = EconomyMath.levelFromGrowth(creature.species, creature.growth or 0, maxLevel)
	local stageMult = CreatureConfig.StageIncomeMult[EconomyMath.stageFor(level)] or 1
	return species.baseIncome * (1 + level * EconomyConfig.IncomePerLevel) * mutation.incomeMult * stageMult
end

local function upgradeLevel(profile, id)
	local lvl = profile.upgrades and profile.upgrades[id] or 0
	local def = UpgradeConfig.Upgrades[id]
	if type(lvl) ~= "number" or not def then
		return 0
	end
	return math.clamp(math.floor(lvl), 0, def.maxLevel)
end
EconomyMath.upgradeLevel = upgradeLevel

-- ctx = { vip = bool, eventMult = number }
function EconomyMath.multipliers(profile, ctx)
	ctx = ctx or {}
	local m = {
		upgrades = 1 + upgradeLevel(profile, "PRODUCTION") * UpgradeConfig.Effects.ProductionPerLevel,
		rebirth = 1 + math.max(0, profile.rebirths or 0) * EconomyConfig.Rebirth.IncomeMultPerRebirth,
		vip = ctx.vip and EconomyConfig.VIPIncomeMult or 1,
		event = ctx.eventMult or 1,
	}
	m.total = m.upgrades * m.rebirth * m.vip * m.event
	return m
end

-- Producción total por segundo de las criaturas COLOCADAS en la parcela.
function EconomyMath.totalIncome(profile, ctx)
	local maxLevel = EconomyMath.maxLevel(profile.rebirths)
	local sum = 0
	for _, creature in pairs(profile.creatures or {}) do
		if type(creature.slot) == "number" and creature.slot > 0 then
			sum += EconomyMath.creatureIncome(creature, maxLevel)
		end
	end
	return sum * EconomyMath.multipliers(profile, ctx).total
end

function EconomyMath.pendingCap(incomePerSecond)
	return math.max(EconomyConfig.PendingCapMin, math.floor(incomePerSecond * EconomyConfig.PendingCapSeconds))
end

function EconomyMath.upgradeCost(upgradeId, currentLevel)
	local def = UpgradeConfig.Upgrades[upgradeId]
	if not def then
		return nil
	end
	if currentLevel >= def.maxLevel then
		return nil
	end
	return math.floor(def.baseCost * def.costGrowth ^ currentLevel + 0.5)
end

function EconomyMath.inventoryCapacity(profile)
	return UpgradeConfig.Effects.BaseInventory
		+ upgradeLevel(profile, "INVENTORY") * UpgradeConfig.Effects.InventoryPerLevel
end

function EconomyMath.slotCount(profile, hasExtraSlotPass)
	local n = UpgradeConfig.Effects.BaseSlots + upgradeLevel(profile, "SLOTS")
	if hasExtraSlotPass then
		n += 1
	end
	return n
end

function EconomyMath.harvestDoubleChance(profile)
	return upgradeLevel(profile, "HARVEST") * UpgradeConfig.Effects.HarvestDoubleChancePerLevel
end

function EconomyMath.carrySpeedMult(profile)
	return math.min(
		1,
		UpgradeConfig.Effects.CarrySpeedBase + upgradeLevel(profile, "CARRY_SPEED") * UpgradeConfig.Effects.CarrySpeedPerLevel
	)
end

function EconomyMath.shieldSeconds(profile)
	return upgradeLevel(profile, "SHIELD") * UpgradeConfig.Effects.ShieldSecondsPerLevel
end

-- Puntos de crecimiento que aporta una comida a una especie.
function EconomyMath.feedGrowth(foodId, speciesId, growthBoostActive)
	local food = FoodConfig.Foods[foodId]
	if not food then
		return 0
	end
	local growth = food.growth
	if table.find(food.favoriteOf, speciesId) then
		growth *= FoodConfig.FavoriteGrowthMult
	end
	if growthBoostActive then
		growth *= EconomyConfig.GrowthBoostMult
	end
	return growth
end

function EconomyMath.feedCoins(foodId)
	local food = FoodConfig.Foods[foodId]
	if not food then
		return 0
	end
	return math.floor(food.growth * EconomyConfig.FeedCoinsPerGrowth)
end

function EconomyMath.sellValue(creature, maxLevel)
	local species = CreatureConfig.Species[creature.species]
	if not species then
		return 0
	end
	local mutation = MutationConfig.Mutations[creature.mutation] or MutationConfig.Mutations.NORMAL
	local level = EconomyMath.levelFromGrowth(creature.species, creature.growth or 0, maxLevel)
	local value = species.value * mutation.valueMult * (1 + level * EconomyConfig.SellValuePerLevel)
	return math.floor(value * EconomyConfig.SellRefund)
end

function EconomyMath.rebirthCost(rebirths)
	local cfg = EconomyConfig.Rebirth
	return math.floor(cfg.BaseCost * cfg.CostGrowth ^ math.max(0, rebirths or 0))
end

function EconomyMath.rebirthRequiredLevel(rebirths)
	local cfg = EconomyConfig.Rebirth
	return math.min(cfg.RequiredLevelMax, cfg.RequiredLevel + math.max(0, rebirths or 0) * cfg.RequiredLevelPerRebirth)
end

function EconomyMath.clampCoins(amount)
	if not isFinite(amount) then
		return 0
	end
	return math.clamp(math.floor(amount), 0, EconomyConfig.MaxCoins)
end

return EconomyMath
