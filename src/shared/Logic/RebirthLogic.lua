-- Renacimiento (puro): requisitos, consecuencias y aplicación.
local Config = script.Parent.Parent.Config
local EconomyConfig = require(Config.EconomyConfig)
local EconomyMath = require(script.Parent.EconomyMath)

local RebirthLogic = {}

function RebirthLogic.highestLevel(profile)
	local maxLevel = EconomyMath.maxLevel(profile.rebirths)
	local best = 0
	for _, creature in pairs(profile.creatures) do
		local level = EconomyMath.levelFromGrowth(creature.species, creature.growth or 0, maxLevel)
		if level > best then
			best = level
		end
	end
	return best
end

-- Información para la interfaz de confirmación (qué se pide, qué se pierde, qué se gana).
function RebirthLogic.info(profile)
	local cfg = EconomyConfig.Rebirth
	local rebirths = profile.rebirths or 0
	local cost = EconomyMath.rebirthCost(rebirths)
	local requiredLevel = EconomyMath.rebirthRequiredLevel(rebirths)
	local highest = RebirthLogic.highestLevel(profile)
	local info = {
		rebirths = rebirths,
		cost = cost,
		requiredLevel = requiredLevel,
		highestLevel = highest,
		coins = profile.coins,
		maxed = rebirths >= cfg.MaxRebirths,
		currentMult = 1 + rebirths * cfg.IncomeMultPerRebirth,
		nextMult = 1 + (rebirths + 1) * cfg.IncomeMultPerRebirth,
		currentMaxLevel = EconomyMath.maxLevel(rebirths),
		nextMaxLevel = EconomyMath.maxLevel(rebirths + 1),
		resets = { "Coins and uncollected earnings", "Food backpack", "Coin upgrades (except Plot Makeover)", "Creature growth (levels back to 0)" },
		keeps = { "All your creatures and their mutations", "Your collection", "Plot Makeover and purchases", "Stats" },
	}
	info.canRebirth = not info.maxed and profile.coins >= cost and highest >= requiredLevel
	if info.maxed then
		info.reason = "max_rebirths"
	elseif profile.coins < cost then
		info.reason = "not_enough_coins"
	elseif highest < requiredLevel then
		info.reason = "level_too_low"
	end
	return info
end

-- Aplica el renacimiento. Devuelve (ok, motivo). Solo modifica el perfil si ok.
function RebirthLogic.apply(profile)
	local info = RebirthLogic.info(profile)
	if not info.canRebirth then
		return false, info.reason
	end
	local cfg = EconomyConfig.Rebirth
	profile.coins = 0
	profile.pendingCoins = 0
	profile.inventory = {}
	local kept = {}
	for id, level in pairs(profile.upgrades) do
		if cfg.KeepUpgrades[id] then
			kept[id] = level
		end
	end
	profile.upgrades = kept
	local baseSlots = EconomyMath.slotCount(profile, false)
	for _, creature in pairs(profile.creatures) do
		creature.growth = 0
		-- Las mejoras de espacios se reinician: lo que no quepa vuelve al almacén.
		if creature.slot > baseSlots then
			creature.slot = 0
		end
	end
	profile.rebirths = info.rebirths + 1
	return true, nil
end

return RebirthLogic
