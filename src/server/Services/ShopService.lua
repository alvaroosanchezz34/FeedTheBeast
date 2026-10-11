-- Compras con monedas: comida, huevos, mejoras y venta de criaturas. Todo validado en servidor;
-- los precios salen de la configuración, nunca del cliente.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FoodConfig = require(Shared.Config.FoodConfig)
local EggConfig = require(Shared.Config.EggConfig)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local CreatureConfig = require(Shared.Config.CreatureConfig)
local MutationConfig = require(Shared.Config.MutationConfig)
local RarityConfig = require(Shared.Config.RarityConfig)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local EconomyMath = require(Shared.Logic.EconomyMath)
local Inventory = require(Shared.Logic.Inventory)
local ProfileSchema = require(Shared.Logic.ProfileSchema)
local Rolls = require(Shared.Logic.Rolls)
local Utilities = require(Shared.Utilities)

local ShopService = {}

local services
local rng = Random.new()

local function rnd()
	return rng:NextNumber()
end

local function notify(player, text, kind, icon)
	services.ValidationService.notify(player, text, kind, icon)
end

-- Devuelve ok, motivo.
function ShopService.buyFood(session, foodId, quantity)
	local def = FoodConfig.Foods[foodId]
	if not def or def.price <= 0 then
		return false, "not_for_sale"
	end
	if quantity < 1 or quantity > EconomyConfig.MaxBuyQuantity or quantity % 1 ~= 0 then
		return false, "bad_quantity"
	end
	local profile = session.profile
	if EconomyMath.upgradeLevel(profile, "MARKET") < def.marketLevel then
		return false, "locked"
	end
	local free = EconomyMath.inventoryCapacity(profile) - Inventory.count(profile)
	if free <= 0 then
		return false, "full"
	end
	quantity = math.min(quantity, free)
	local cost = def.price * quantity
	if not services.EconomyService.spend(session.userId, cost) then
		return false, "no_coins"
	end
	local added = Inventory.add(profile, foodId, quantity, EconomyMath.inventoryCapacity(profile))
	if added < quantity then
		-- No debería ocurrir (se calculó el hueco antes), pero nunca se cobra de más.
		services.EconomyService.addCoins(session.userId, def.price * (quantity - added))
	end
	services.StateService.push(session.userId, "inventory")
	return true, nil, added
end

function ShopService.buyEgg(session, eggId)
	local egg = EggConfig.Eggs[eggId]
	if not egg then
		return false, "no_egg"
	end
	local profile = session.profile
	if EconomyMath.upgradeLevel(profile, "HATCHERY") < egg.hatcheryLevel then
		return false, "locked"
	end
	if ProfileSchema.creatureCount(profile) >= CreatureConfig.MaxOwned then
		return false, "storage_full"
	end
	local speciesId = Rolls.species(egg, rnd)
	if not speciesId then
		return false, "roll_failed"
	end
	if not services.EconomyService.spend(session.userId, egg.price) then
		return false, "no_coins"
	end
	local mutationId = services.MutationService.rollHatch(egg.mutationLuck)
	local isNew = not profile.collection[ProfileSchema.collectionKey(speciesId, mutationId)]
	local creature = services.CreatureService.add(session, speciesId, mutationId)
	if not creature then
		services.EconomyService.addCoins(session.userId, egg.price)
		return false, "add_failed"
	end
	profile.stats.eggsHatched += 1
	services.QuestService.progress(session, "Hatched", 1)
	services.StateService.push(session.userId, "stats")

	local species = CreatureConfig.Species[speciesId]
	local mutation = MutationConfig.Mutations[mutationId]
	local rarityIndex = RarityConfig.Index[species.rarity]
	local model = services.CreatureService.modelOf(session.userId, creature.id)

	-- Tarjeta de revelación para el comprador.
	services.ValidationService.fireClient(session.player, "Notify", {
		kind = "hatch",
		species = speciesId,
		mutation = mutationId,
		isNew = isNew,
		stored = creature.slot == 0,
	})

	if model then
		services.ValidationService.fireAll("CreatureEvent", model, "Spawned", {})
		if species.rarity == "Secret" then
			services.VFXService.playAll("SecretReveal", { model = model })
		elseif rarityIndex >= RarityConfig.Index.Epic or mutation.tier >= 1 then
			services.VFXService.playAll("RareFind", { model = model })
		else
			services.VFXService.playAll("Spawn", { model = model })
		end
	end
	if species.rarity == "Secret" then
		services.VFXService.announce(string.format("%s hatched a SECRET %s!!!", session.player.DisplayName, species.name), RarityConfig.Rarities.Secret.color)
	elseif rarityIndex >= RarityConfig.Index.Legendary or mutation.tier >= 3 then
		local prefix = mutation.tier >= 1 and (mutation.name .. " ") or ""
		services.VFXService.announce(string.format("%s hatched a %s%s!", session.player.DisplayName, prefix, species.name), RarityConfig.Rarities[species.rarity].color)
	end
	return true, nil, creature
end

function ShopService.buyUpgrade(session, upgradeId)
	local def = UpgradeConfig.Upgrades[upgradeId]
	if not def then
		return false, "no_upgrade"
	end
	local profile = session.profile
	local level = EconomyMath.upgradeLevel(profile, upgradeId)
	local cost = EconomyMath.upgradeCost(upgradeId, level)
	if not cost then
		return false, "max_level"
	end
	if not services.EconomyService.spend(session.userId, cost) then
		return false, "no_coins"
	end
	profile.upgrades[upgradeId] = level + 1
	services.QuestService.progress(session, "UpgradeBought", 1)
	services.StateService.push(session.userId, "upgrades", "capacity", "slots")
	if upgradeId == "PRODUCTION" then
		services.EconomyService.incomeChanged(session.userId)
	elseif upgradeId == "SLOTS" or upgradeId == "PLOT_STYLE" then
		services.PlotService.refresh(session)
	elseif upgradeId == "CARRY_SPEED" then
		services.TheftService.refreshSpeed(session.userId)
	end
	return true, nil, level + 1
end

function ShopService.sellCreature(session, creatureId)
	local profile = session.profile
	local creature = profile.creatures[creatureId]
	if not creature then
		return false, "no_creature"
	end
	if ProfileSchema.creatureCount(profile) <= 1 then
		return false, "last_creature"
	end
	if services.FeedingService.isBusy(session, creatureId) then
		return false, "busy"
	end
	local value = EconomyMath.sellValue(creature, EconomyMath.maxLevel(profile.rebirths))
	if not services.CreatureService.remove(session, creatureId) then
		return false, "remove_failed"
	end
	services.EconomyService.addCoins(session.userId, value)
	return true, nil, value
end

function ShopService.Init(allServices)
	services = allServices
end

function ShopService.Start()
	local V = services.ValidationService

	V.on("BuyFood", function(player, foodId, quantity)
		local session = services.PlayerDataService.sessionOf(player)
		if not session then
			return
		end
		local ok, reason, added = ShopService.buyFood(session, foodId, quantity)
		if ok then
			local def = FoodConfig.Foods[foodId]
			notify(player, string.format("Bought %dx %s", added, def.name), "success", def.icon)
		elseif reason == "no_coins" then
			notify(player, "Not enough coins.", "error", "💰")
		elseif reason == "full" then
			notify(player, "Backpack full!", "error", "🎒")
		elseif reason == "locked" then
			notify(player, "Upgrade your Market License to buy this.", "error", "🔒")
		end
	end)

	V.on("BuyEgg", function(player, eggId)
		local session = services.PlayerDataService.sessionOf(player)
		if not session then
			return
		end
		local ok, reason = ShopService.buyEgg(session, eggId)
		if not ok then
			if reason == "no_coins" then
				notify(player, "Not enough coins.", "error", "💰")
			elseif reason == "storage_full" then
				notify(player, "Creature storage is full. Sell one first.", "error", "📦")
			elseif reason == "locked" then
				notify(player, "Upgrade your Hatchery to buy this egg.", "error", "🔒")
			end
		end
	end)

	V.on("BuyUpgrade", function(player, upgradeId)
		local session = services.PlayerDataService.sessionOf(player)
		if not session then
			return
		end
		local ok, reason, level = ShopService.buyUpgrade(session, upgradeId)
		if ok then
			local def = UpgradeConfig.Upgrades[upgradeId]
			notify(player, string.format("%s → level %d", def.name, level), "success", def.icon)
			local pos = services.CharacterService.positionOf(session.userId)
			if pos then
				services.VFXService.playFor(player, "Purchase", { position = pos, radius = 2 })
			end
		elseif reason == "no_coins" then
			notify(player, "Not enough coins.", "error", "💰")
		end
	end)

	V.on("SellCreature", function(player, creatureId)
		local session = services.PlayerDataService.sessionOf(player)
		if not session then
			return
		end
		local ok, reason, value = ShopService.sellCreature(session, creatureId)
		if ok then
			notify(player, "Sold for " .. Utilities.formatNumber(value) .. " coins", "reward", "💰")
		elseif reason == "last_creature" then
			notify(player, "You can't sell your last creature.", "error", "🚫")
		end
	end)
end

return ShopService
