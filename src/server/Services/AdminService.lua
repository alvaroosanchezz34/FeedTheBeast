-- Herramientas de administración y depuración. Los permisos se comprueban SIEMPRE en servidor:
-- lista explícita en GameConfig.Admins, creador del lugar o Studio. Un jugador normal que dispare
-- el remoto no obtiene nada (y queda registrado).
--
-- Comandos (remoto "Admin": comando, arg1, arg2):
--   coins <cantidad>            food <foodId> <n>           egg <especie> <mutación>
--   mutate <creatureId|all> <mutación>                      grow <creatureId|all> <puntos>
--   event <eventId>             stopevent                   crate <tier>
--   pass <clave>                (alterna un pase SOLO en la sesión, para probar)
--   clearfx                     inspect                     save
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local FoodConfig = require(Shared.Config.FoodConfig)
local CreatureConfig = require(Shared.Config.CreatureConfig)
local MutationConfig = require(Shared.Config.MutationConfig)
local EventConfig = require(Shared.Config.EventConfig)
local TheftConfig = require(Shared.Config.TheftConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local EconomyMath = require(Shared.Logic.EconomyMath)
local Utilities = require(Shared.Utilities)

local AdminService = {}

local services

function AdminService.isAdmin(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end
	local cfg = GameConfig.Admins
	if table.find(cfg.UserIds, player.UserId) then
		return true
	end
	if cfg.AllowInStudio and RunService:IsStudio() then
		return true
	end
	if cfg.AllowPlaceCreator and game.CreatorType == Enum.CreatorType.User and game.CreatorId == player.UserId and game.CreatorId ~= 0 then
		return true
	end
	return false
end

local commands = {}

function commands.coins(session, amount)
	local n = tonumber(amount)
	if not n or n <= 0 or n ~= n then
		return "usage: coins <amount>"
	end
	return "added " .. Utilities.formatNumber(services.EconomyService.addCoins(session.userId, n))
end

function commands.food(session, foodId, count)
	if not FoodConfig.Foods[foodId or ""] then
		return "unknown food"
	end
	local added = services.FoodService.give(session, foodId, math.clamp(tonumber(count) or 1, 1, 100))
	return "added " .. added .. " " .. foodId
end

function commands.egg(session, speciesId, mutationId)
	mutationId = mutationId or "NORMAL"
	if not CreatureConfig.Species[speciesId or ""] or not MutationConfig.Mutations[mutationId] then
		return "usage: egg <SPECIES> <MUTATION>"
	end
	local creature = services.CreatureService.add(session, speciesId, mutationId)
	if not creature then
		return "storage full"
	end
	local model = services.CreatureService.modelOf(session.userId, creature.id)
	if model then
		services.VFXService.playAll(CreatureConfig.Species[speciesId].rarity == "Secret" and "SecretReveal" or "Spawn", { model = model })
	end
	return "spawned " .. creature.id
end

local function eachTarget(session, target, fn)
	local count = 0
	for id, creature in pairs(session.profile.creatures) do
		if target == "all" or target == id then
			fn(id, creature)
			count += 1
		end
	end
	return count
end

function commands.mutate(session, target, mutationId)
	if not MutationConfig.Mutations[mutationId or ""] then
		return "usage: mutate <creatureId|all> <MUTATION>"
	end
	local count = eachTarget(session, target or "all", function(_, creature)
		services.MutationService.apply(session, creature, mutationId, true)
	end)
	return "mutated " .. count
end

function commands.grow(session, target, points)
	local n = tonumber(points)
	if not n or n ~= n then
		return "usage: grow <creatureId|all> <points>"
	end
	local maxLevel = EconomyMath.maxLevel(session.profile.rebirths)
	local count = eachTarget(session, target or "all", function(id, creature)
		creature.growth = math.clamp(creature.growth + n, 0, EconomyMath.maxGrowth(creature.species, maxLevel))
		services.CreatureService.refresh(session, id)
	end)
	services.StateService.push(session.userId, "creatures")
	services.EconomyService.incomeChanged(session.userId)
	return "grew " .. count
end

function commands.event(_, eventId)
	if not EventConfig.Events[eventId or ""] then
		return "unknown event"
	end
	services.EventService.forceStart(eventId)
	return "started " .. eventId
end

function commands.stopevent()
	services.EventService.stop()
	return "event stopped"
end

function commands.crate(session, tierId)
	tierId = tierId or "WOOD"
	if not TheftConfig.Tiers[tierId] then
		return "unknown tier"
	end
	local position = services.CharacterService.positionOf(session.userId)
	if not position then
		return "no character"
	end
	services.TheftService.spawnCrate(tierId, Vector3.new(position.X + 8, 1.9, position.Z))
	return "crate spawned"
end

function commands.pass(session, key)
	if not MonetizationConfig.GamePasses[key or ""] then
		return "unknown pass"
	end
	services.MonetizationService.setPass(session, key, not session.passes[key])
	return key .. " = " .. tostring(session.passes[key]) .. " (session only)"
end

function commands.clearfx()
	services.ValidationService.fireAll("Effect", "__clear", {})
	return "clear sent"
end

function commands.inspect(session)
	local profile = session.profile
	local creatures = 0
	for _ in pairs(profile.creatures) do
		creatures += 1
	end
	return string.format(
		"coins=%s income=%.1f/s pending=%d creatures=%d rebirths=%d plot=%s ephemeral=%s event=%s",
		Utilities.formatNumber(profile.coins),
		services.EconomyService.income(session),
		math.floor(profile.pendingCoins),
		creatures,
		profile.rebirths,
		tostring(session.plotIndex),
		tostring(session.ephemeral),
		tostring((services.EventService.current()))
	)
end

function commands.save(session)
	return "save " .. (services.PlayerDataService.save(session.userId, false, true) and "ok" or "FAILED")
end

function AdminService.run(player, command, a, b)
	if not AdminService.isAdmin(player) then
		warn(string.format("[Admin] DENIED %s from %d", tostring(command), player.UserId))
		return nil
	end
	local session = services.PlayerDataService.sessionOf(player)
	local handler = commands[command]
	if not session or not handler then
		return "unknown command"
	end
	local result = handler(session, a, b)
	print(string.format("[Admin] %d ran %s %s %s -> %s", player.UserId, command, tostring(a), tostring(b), tostring(result)))
	return result
end

function AdminService.Init(allServices)
	services = allServices
end

function AdminService.Start()
	services.ValidationService.on("Admin", function(player, command, a, b)
		local result = AdminService.run(player, command, a, b)
		if result then
			services.ValidationService.notify(player, "[admin] " .. result, "info", "🛠️")
		end
	end)
end

return AdminService
