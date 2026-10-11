-- Alimentación y crecimiento. Toda la validación ocurre aquí:
--   criatura propia y colocada · comida válida y en inventario · personaje vivo y cerca ·
--   criatura no ocupada (evita duplicar con peticiones repetidas) · no supera el nivel máximo.
--
-- API:
--   FeedingService.feed(session, creatureId, foodId, opts) -> ok, motivo     opts = { skipDistance }
--   FeedingService.isBusy(session, creatureId) -> bool
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local FoodConfig = require(Shared.Config.FoodConfig)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local CreatureConfig = require(Shared.Config.CreatureConfig)
local RarityConfig = require(Shared.Config.RarityConfig)
local ProfileSchema = require(Shared.Logic.ProfileSchema)
local Constants = require(Shared.Constants)
local EconomyMath = require(Shared.Logic.EconomyMath)
local Inventory = require(Shared.Logic.Inventory)
local ReceiptLogic = require(Shared.Logic.ReceiptLogic)
local Clock = require(Shared.Clock)

local FeedingService = {}

local services
local autoTimer = 0

function FeedingService.isBusy(session, creatureId)
	local eating = session.eating
	return eating ~= nil and (eating[creatureId] or 0) > Clock.now()
end

function FeedingService.feed(session, creatureId, foodId, opts)
	opts = opts or {}
	local profile = session.profile
	local creature = profile.creatures[creatureId]
	if not creature then
		return false, "no_creature"
	end
	if creature.slot <= 0 or not session.plotIndex then
		return false, "not_placed"
	end
	local food = FoodConfig.Foods[foodId]
	if not food then
		return false, "no_food_def"
	end
	if Inventory.get(profile, foodId) < 1 then
		return false, "no_food"
	end

	local maxLevel = EconomyMath.maxLevel(profile.rebirths)
	local scaleBefore, levelBefore = EconomyMath.scaleFromGrowth(creature.species, creature.growth, maxLevel)

	if not opts.skipDistance then
		local position = services.CharacterService.positionOf(session.userId)
		local target = services.CreatureService.positionOf(session, creatureId)
		if not position or not target then
			return false, "no_character"
		end
		local reach = GameConfig.Interaction.FeedBaseDistance + services.CreatureService.interactRadius(creature, scaleBefore)
		local flat = Vector3.new(position.X - target.X, 0, position.Z - target.Z)
		if flat.Magnitude > reach or math.abs(position.Y - target.Y) > 25 then
			return false, "too_far"
		end
	end

	if FeedingService.isBusy(session, creatureId) then
		return false, "busy"
	end
	if levelBefore >= maxLevel then
		return false, "max_level"
	end

	-- A partir de aquí no hay yields: consumo y recompensa son atómicos.
	if not Inventory.remove(profile, foodId, 1) then
		return false, "no_food"
	end
	local now = Clock.now()
	session.eating = session.eating or {}
	session.eating[creatureId] = now + food.consumeTime

	local boost = ReceiptLogic.boostActive(profile, "Growth", Clock.unix())
	local growth = EconomyMath.feedGrowth(foodId, creature.species, boost)
	creature.growth = math.min(EconomyMath.maxGrowth(creature.species, maxLevel), creature.growth + growth)

	local first = not profile.flags.firstFeed
	local coins = EconomyMath.feedCoins(foodId)
	if first then
		profile.flags.firstFeed = true
		coins += EconomyConfig.FirstFeedBonus
	end
	profile.stats.foodsFed += 1

	local favorite = table.find(food.favoriteOf, creature.species) ~= nil
	services.QuestService.progress(session, "Fed", 1)
	if (RarityConfig.Index[food.rarity] or 0) >= RarityConfig.Index.Rare then
		services.QuestService.progress(session, "FedRare", 1)
	end
	if favorite then
		services.QuestService.progress(session, "FedFavorite", 1)
	end

	local collectionBefore = table.clone(profile.collection)
	local mutated = services.MutationService.tryFeedMutation(session, creature, foodId)
	if mutated then
		-- Descubrimiento: misma tarjeta que al eclosionar, marcando si es nueva en la colección.
		services.ValidationService.fireClient(session.player, "Notify", {
			kind = "hatch",
			species = creature.species,
			mutation = mutated,
			isNew = not collectionBefore[ProfileSchema.collectionKey(creature.species, mutated)],
			stored = false,
			mutatedByFood = true,
		})
	end

	local _, levelAfter = EconomyMath.scaleFromGrowth(creature.species, creature.growth, maxLevel)
	local stageAfter = EconomyMath.stageFor(levelAfter)
	local evolved = stageAfter > EconomyMath.stageFor(levelBefore)
	services.CreatureService.refresh(session, creatureId)
	local model = services.CreatureService.modelOf(session.userId, creatureId)
	if evolved then
		local species = CreatureConfig.Species[creature.species]
		local stageName = CreatureConfig.StageNames[stageAfter] or "Evolved"
		services.ValidationService.notify(session.player, string.format("%s evolved: %s form! Coin bonus up.", species.name, stageName), "reward", "🌟")
	end
	if model then
		model:SetAttribute(Constants.CreatureAttr.EatingUntil, Clock.server() + food.consumeTime)
		services.ValidationService.fireAll("CreatureEvent", model, "Fed", {
			food = foodId,
			duration = food.consumeTime,
			leveledUp = levelAfter > levelBefore,
			evolved = evolved and stageAfter or nil,
			level = levelAfter,
			first = first,
			favorite = favorite,
			mutated = mutated,
		})
	end

	services.EconomyService.addCoins(session.userId, coins)
	services.StateService.push(session.userId, "inventory", "creatures", "stats")
	if first then
		services.StateService.push(session.userId, "flags")
	end
	if levelAfter > levelBefore then
		services.QuestService.progress(session, "LevelUp", levelAfter - levelBefore)
		services.EconomyService.incomeChanged(session.userId)
	end
	return true, nil
end

-- Elige automáticamente qué dar de comer (pase Auto-Feed): la criatura colocada de menor nivel
-- que no esté ocupada ni al máximo, con la comida de menor crecimiento disponible.
local function autoFeed(session)
	local profile = session.profile
	local maxLevel = EconomyMath.maxLevel(profile.rebirths)
	local bestFood, bestGrowth = nil, math.huge
	for foodId, count in pairs(profile.inventory) do
		local def = FoodConfig.Foods[foodId]
		if def and count > 0 and def.growth < bestGrowth then
			bestFood, bestGrowth = foodId, def.growth
		end
	end
	if not bestFood then
		return
	end
	local bestCreature, bestLevel = nil, math.huge
	for id, creature in pairs(profile.creatures) do
		if creature.slot > 0 and not FeedingService.isBusy(session, id) then
			local level = EconomyMath.levelFromGrowth(creature.species, creature.growth, maxLevel)
			if level < maxLevel and (level < bestLevel or (level == bestLevel and id < bestCreature)) then
				bestCreature, bestLevel = id, level
			end
		end
	end
	if bestCreature then
		FeedingService.feed(session, bestCreature, bestFood, { skipDistance = true })
	end
end

function FeedingService.Init(allServices)
	services = allServices
end

function FeedingService.Start()
	services.ValidationService.on("Feed", function(player, creatureId, foodId)
		local session = services.PlayerDataService.sessionOf(player)
		if not session then
			return
		end
		local ok, reason = FeedingService.feed(session, creatureId, foodId)
		if not ok then
			if reason == "max_level" then
				local creature = session.profile.creatures[creatureId]
				local species = creature and CreatureConfig.Species[creature.species]
				services.ValidationService.notify(player, (species and species.name or "Creature") .. " is at max level. Rebirth to raise the cap!", "info", "⭐")
			elseif reason == "too_far" then
				services.ValidationService.notify(player, "Get closer to feed.", "error", "📏")
			elseif reason == "no_food" then
				services.ValidationService.notify(player, "You don't have that food.", "error", "🍽️")
			end
		end
	end)
end

function FeedingService.Update(dt)
	autoTimer += dt
	if autoTimer < MonetizationConfig.AutoFeed.Interval then
		return
	end
	autoTimer = 0
	services.PlayerDataService.forEach(function(session)
		if session.passes.AUTO_FEED and session.plotIndex then
			autoFeed(session)
		end
	end)
end

return FeedingService
