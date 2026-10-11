-- Mutaciones: el servidor las decide, las guarda y calcula sus bonificaciones.
-- El cliente solo reproduce los efectos visuales a partir del atributo replicado.
--
-- API:
--   MutationService.rollHatch(luck) -> mutationId
--   MutationService.tryFeedMutation(session, creature, foodId) -> mutationId | nil
--   MutationService.apply(session, creature, mutationId, force) -> bool
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MutationConfig = require(Shared.Config.MutationConfig)
local CreatureConfig = require(Shared.Config.CreatureConfig)
local VFXConfig = require(Shared.Config.VFXConfig)
local ProfileSchema = require(Shared.Logic.ProfileSchema)
local Rolls = require(Shared.Logic.Rolls)

local MutationService = {}

local services
local rng = Random.new()

local function rnd()
	return rng:NextNumber()
end

function MutationService.rollHatch(luck)
	return Rolls.hatchMutation(luck, rnd)
end

-- Cambia la mutación de una criatura. Sin `force` solo permite subir de nivel de mutación.
function MutationService.apply(session, creature, mutationId, force)
	local def = MutationConfig.Mutations[mutationId]
	local current = MutationConfig.Mutations[creature.mutation] or MutationConfig.Mutations.NORMAL
	if not def or creature.mutation == mutationId then
		return false
	end
	if not force and def.tier <= current.tier then
		return false
	end
	creature.mutation = mutationId
	session.profile.collection[ProfileSchema.collectionKey(creature.species, mutationId)] = true
	services.CreatureService.refresh(session, creature.id)
	services.StateService.push(session.userId, "creatures", "collection")
	services.EconomyService.incomeChanged(session.userId)

	if mutationId ~= "NORMAL" then
		local model = services.CreatureService.modelOf(session.userId, creature.id)
		local species = CreatureConfig.Species[creature.species]
		if model then
			services.ValidationService.fireAll("CreatureEvent", model, "Mutated", { mutation = mutationId })
		end
		local effect = VFXConfig.MutationTransformEffects[mutationId]
		if effect and model then
			services.VFXService.playAll(effect, { model = model })
		end
		services.ValidationService.notify(session.player, string.format("%s mutated: %s!", species.name, def.name), "reward", "🧬")
		if def.tier >= 2 then
			services.VFXService.announce(string.format("%s's %s became %s!", session.player.DisplayName, species.name, def.name), def.color)
		end
	end
	return true
end

function MutationService.tryFeedMutation(session, creature, foodId)
	local mutationId = Rolls.feedMutation(creature.mutation, foodId, rnd)
	if mutationId and mutationId ~= "NORMAL" then
		if MutationService.apply(session, creature, mutationId, false) then
			return mutationId
		end
	end
	return nil
end

function MutationService.Init(allServices)
	services = allServices
end

return MutationService
