-- Criaturas en el mundo. El servidor es dueño de: propiedad, especie, mutación, crecimiento,
-- espacio ocupado, hitbox y distancia de interacción. El modelo de servidor es mínimo (base +
-- hitbox + atributos); el aspecto visual lo construye cada cliente a partir de los atributos.
--
-- API:
--   CreatureService.add(session, speciesId, mutationId) -> creature
--   CreatureService.remove(session, creatureId) -> bool
--   CreatureService.refresh(session, creatureId)       -- reaplica atributos/hitbox
--   CreatureService.modelOf(userId, creatureId) -> Model | nil
--   CreatureService.positionOf(session, creatureId) -> Vector3 | nil
--   CreatureService.interactRadius(creature) -> number
--   CreatureService.slotCount(session) -> number
--   CreatureService.view(session) -> lista para el cliente
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local CreatureConfig = require(Shared.Config.CreatureConfig)
local Constants = require(Shared.Constants)
local EconomyMath = require(Shared.Logic.EconomyMath)
local ProfileSchema = require(Shared.Logic.ProfileSchema)
local Clock = require(Shared.Clock)

local CreatureService = {}

local services
local models = {} -- userId -> { [creatureId] = Model }
local folder

local A = Constants.CreatureAttr

function CreatureService.slotCount(session)
	return math.min(
		GameConfig.World.MaxSlotsPerPlot,
		EconomyMath.slotCount(session.profile, session.passes.EXTRA_SLOT == true)
	)
end

local function stats(session, creature)
	local maxLevel = EconomyMath.maxLevel(session.profile.rebirths)
	local scale, level, progress = EconomyMath.scaleFromGrowth(creature.species, creature.growth, maxLevel)
	return scale, level, progress, maxLevel
end

function CreatureService.interactRadius(creature, scale)
	local species = CreatureConfig.Species[creature.species]
	return species.baseRadius * EconomyMath.hitboxScale(scale)
end

local function applyToModel(session, creature, model)
	local species = CreatureConfig.Species[creature.species]
	local scale, level = stats(session, creature)
	model:SetAttribute(A.Mutation, creature.mutation)
	model:SetAttribute(A.Level, level)
	model:SetAttribute(A.Scale, scale)
	local hitScale = EconomyMath.hitboxScale(scale)
	local hitbox = model:FindFirstChild("Hitbox")
	local base = model.PrimaryPart
	if hitbox and base then
		local height = species.baseHeight * hitScale * 0.8
		local diameter = species.baseRadius * 2 * hitScale * 0.75
		hitbox.Size = Vector3.new(height, diameter, diameter)
		hitbox.CFrame = base.CFrame * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90))
	end
end

local function spawnModel(session, creature)
	local userId = session.userId
	local slotCf = services.PlotService.slotCFrame(session.plotIndex, creature.slot)
	if not slotCf then
		return nil
	end
	local species = CreatureConfig.Species[creature.species]

	local model = Instance.new("Model")
	model.Name = species.name

	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = Vector3.new(1, 0.2, 1)
	base.Anchored = true
	base.CanCollide = false
	base.CanTouch = false
	base.CanQuery = false
	base.Transparency = 1
	base.CFrame = slotCf
	base.Parent = model
	model.PrimaryPart = base

	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Shape = Enum.PartType.Cylinder
	hitbox.Anchored = true
	hitbox.CanCollide = true
	hitbox.CanTouch = false
	hitbox.Transparency = 1
	hitbox.CastShadow = false
	hitbox.Size = Vector3.new(4, 4, 4)
	hitbox.CFrame = slotCf
	hitbox.Parent = model

	model:SetAttribute(A.Id, creature.id)
	model:SetAttribute(A.Species, creature.species)
	model:SetAttribute(A.Rarity, species.rarity)
	model:SetAttribute(A.Owner, userId)
	model:SetAttribute(A.Giant, false)
	model:SetAttribute(A.EatingUntil, 0)
	model:SetAttribute(A.Pivot, slotCf)
	applyToModel(session, creature, model)

	model.Parent = folder
	CollectionService:AddTag(model, Constants.Tags.Creature)

	models[userId] = models[userId] or {}
	models[userId][creature.id] = model
	return model
end

local function despawnModel(userId, creatureId)
	local set = models[userId]
	local model = set and set[creatureId]
	if model then
		set[creatureId] = nil
		model:Destroy()
	end
end

function CreatureService.modelOf(userId, creatureId)
	local set = models[userId]
	return set and set[creatureId] or nil
end

function CreatureService.positionOf(session, creatureId)
	local creature = session.profile.creatures[creatureId]
	if not creature or creature.slot <= 0 or not session.plotIndex then
		return nil
	end
	local cf = services.PlotService.slotCFrame(session.plotIndex, creature.slot)
	return cf and cf.Position or nil
end

function CreatureService.refresh(session, creatureId)
	local creature = session.profile.creatures[creatureId]
	local model = CreatureService.modelOf(session.userId, creatureId)
	if creature and model then
		applyToModel(session, creature, model)
	end
end

-- Reconstruye todos los modelos del jugador (tras renacer, cambiar espacios, etc.).
function CreatureService.respawnAll(session)
	local set = models[session.userId]
	if set then
		for creatureId in pairs(table.clone(set)) do
			despawnModel(session.userId, creatureId)
		end
	end
	if not session.plotIndex then
		return
	end
	local slots = CreatureService.slotCount(session)
	for _, creature in pairs(session.profile.creatures) do
		if creature.slot > slots then
			creature.slot = 0
		end
		if creature.slot > 0 then
			spawnModel(session, creature)
		end
	end
end

local function freeSlot(session)
	local used = {}
	for _, creature in pairs(session.profile.creatures) do
		if creature.slot > 0 then
			used[creature.slot] = true
		end
	end
	for slot = 1, CreatureService.slotCount(session) do
		if not used[slot] then
			return slot
		end
	end
	return nil
end

-- Añade una criatura al jugador. La coloca en un espacio libre o la guarda en el almacén.
function CreatureService.add(session, speciesId, mutationId)
	if not CreatureConfig.Species[speciesId] then
		return nil
	end
	if ProfileSchema.creatureCount(session.profile) >= CreatureConfig.MaxOwned then
		return nil
	end
	local creature = ProfileSchema.addCreature(session.profile, speciesId, mutationId, freeSlot(session) or 0, Clock.unix())
	if creature.slot > 0 and session.plotIndex then
		spawnModel(session, creature)
	end
	services.StateService.push(session.userId, "creatures", "collection")
	services.EconomyService.incomeChanged(session.userId)
	return creature
end

function CreatureService.remove(session, creatureId)
	if not session.profile.creatures[creatureId] then
		return false
	end
	despawnModel(session.userId, creatureId)
	session.profile.creatures[creatureId] = nil
	services.StateService.push(session.userId, "creatures")
	services.EconomyService.incomeChanged(session.userId)
	return true
end

function CreatureService.view(session)
	local list = {}
	local maxLevel = EconomyMath.maxLevel(session.profile.rebirths)
	for id, creature in pairs(session.profile.creatures) do
		local level, progress = EconomyMath.levelFromGrowth(creature.species, creature.growth, maxLevel)
		table.insert(list, {
			id = id,
			species = creature.species,
			mutation = creature.mutation,
			slot = creature.slot,
			level = level,
			progress = progress,
			maxed = level >= maxLevel,
			income = EconomyMath.creatureIncome(creature, maxLevel),
			sellValue = EconomyMath.sellValue(creature, maxLevel),
		})
	end
	table.sort(list, function(a, b)
		if (a.slot > 0) ~= (b.slot > 0) then
			return a.slot > 0
		end
		if a.slot ~= b.slot then
			return a.slot < b.slot
		end
		return a.id < b.id
	end)
	return list
end

function CreatureService.Init(allServices)
	services = allServices
	folder = workspace:FindFirstChild(Constants.Folders.Creatures)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Constants.Folders.Creatures
		folder.Parent = workspace
	end
end

function CreatureService.Start()
	services.PlayerDataService.SessionStarted:Connect(function(session)
		if not session.plotIndex then
			return
		end
		local profile = session.profile
		-- Criatura inicial (idempotente).
		if ProfileSchema.creatureCount(profile) == 0 and not profile.flags.starterGiven then
			ProfileSchema.addCreature(profile, GameConfig.StarterSpecies, "NORMAL", GameConfig.StarterSlot, Clock.unix())
			profile.flags.starterGiven = true
		end
		CreatureService.respawnAll(session)
		services.PlotService.refresh(session)
		services.EconomyService.incomeChanged(session.userId)
		services.StateService.push(session.userId, "creatures", "collection", "slots")
	end)

	services.PlayerDataService.SessionEnding:Connect(function(session)
		local set = models[session.userId]
		if set then
			for _, model in pairs(set) do
				model:Destroy()
			end
			models[session.userId] = nil
		end
	end)

	services.ValidationService.on("PlaceCreature", function(player, creatureId, slot)
		local session = services.PlayerDataService.sessionOf(player)
		if not session or not session.plotIndex then
			return
		end
		local creature = session.profile.creatures[creatureId]
		if not creature or slot > CreatureService.slotCount(session) then
			return
		end
		if services.FeedingService.isBusy(session, creatureId) then
			return
		end
		if creature.slot == slot then
			return
		end
		-- Si el espacio está ocupado, se intercambian.
		local previousSlot = creature.slot
		for otherId, other in pairs(session.profile.creatures) do
			if otherId ~= creatureId and other.slot == slot then
				if services.FeedingService.isBusy(session, otherId) then
					return
				end
				despawnModel(session.userId, otherId)
				other.slot = previousSlot
				if other.slot > 0 then
					spawnModel(session, other)
				end
			end
		end
		despawnModel(session.userId, creatureId)
		creature.slot = slot
		spawnModel(session, creature)
		services.StateService.push(session.userId, "creatures")
		services.EconomyService.incomeChanged(session.userId)
	end)

	services.ValidationService.on("StoreCreature", function(player, creatureId)
		local session = services.PlayerDataService.sessionOf(player)
		if not session then
			return
		end
		local creature = session.profile.creatures[creatureId]
		if not creature or creature.slot == 0 or services.FeedingService.isBusy(session, creatureId) then
			return
		end
		despawnModel(session.userId, creatureId)
		creature.slot = 0
		services.StateService.push(session.userId, "creatures")
		services.EconomyService.incomeChanged(session.userId)
	end)
end

return CreatureService
