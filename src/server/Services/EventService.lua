-- Eventos globales: FOOD_RAIN, GOLDEN_FEAST y GIANT_BEAST.
-- El estado se replica con atributos en ReplicatedStorage/FTB_EventState, así los jugadores que
-- entran a mitad de evento lo ven sin lógica adicional. Las recompensas se calculan en servidor
-- y cada jugador se recompensa como mucho una vez por evento.
--
-- API:
--   EventService.incomeMult() -> multiplicador de producción activo
--   EventService.crateMult()  -> multiplicador de recompensa de cajas activo
--   EventService.forceStart(eventId) -> bool      (admin / tests)
--   EventService.stop()
--   EventService.current() -> id | nil, fase
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local EventConfig = require(Shared.Config.EventConfig)
local FoodConfig = require(Shared.Config.FoodConfig)
local CreatureConfig = require(Shared.Config.CreatureConfig)
local Constants = require(Shared.Constants)
local EventLogic = require(Shared.Logic.EventLogic)
local Inventory = require(Shared.Logic.Inventory)
local Rolls = require(Shared.Logic.Rolls)
local PlotLayout = require(Shared.Logic.PlotLayout)
local Utilities = require(Shared.Utilities)
local Clock = require(Shared.Clock)

local EventService = {}

local services
local stateFolder
local rng = Random.new()

local A = Constants.EventAttr
local CA = Constants.CreatureAttr

local state = {
	id = nil,
	phase = "Idle", -- Idle | Announce | Active
	startsAt = 0, -- reloj interno
	endsAt = 0,
	nextAt = 0,
	spawnTimer = 0,
	last = nil,
	giant = nil, -- { model, goal, progress, contributions, lastFeed }
}

local function rnd()
	return rng:NextNumber()
end

local function replicate()
	stateFolder:SetAttribute(A.Id, state.id or "")
	stateFolder:SetAttribute(A.Phase, state.phase)
	-- Convertimos el reloj interno a tiempo de servidor compartido con los clientes.
	local offset = Clock.server() - Clock.now()
	stateFolder:SetAttribute(A.StartsAt, state.startsAt + offset)
	stateFolder:SetAttribute(A.EndsAt, state.endsAt + offset)
	stateFolder:SetAttribute(A.Progress, state.giant and state.giant.progress or 0)
	stateFolder:SetAttribute(A.Goal, state.giant and state.giant.goal or 0)
end

function EventService.current()
	return state.id, state.phase
end

function EventService.incomeMult()
	if state.phase == "Active" and state.id then
		return EventConfig.Events[state.id].incomeMult or 1
	end
	return 1
end

function EventService.crateMult()
	if state.phase == "Active" and state.id then
		return EventConfig.Events[state.id].crateRewardMult or 1
	end
	return 1
end

---------------------------------------------------------------------------------------------
-- GIANT_BEAST
---------------------------------------------------------------------------------------------
local function spawnGiant(cfg)
	local candidates = {}
	for _, id in ipairs(CreatureConfig.Order) do
		if CreatureConfig.Species[id].rarity ~= "Secret" then
			table.insert(candidates, id)
		end
	end
	local speciesId = candidates[rng:NextInteger(1, #candidates)]
	local species = CreatureConfig.Species[speciesId]
	local world = services.PlotService.world()

	local model = Instance.new("Model")
	model.Name = "GiantBeast"
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = Vector3.new(1, 0.2, 1)
	base.Anchored = true
	base.CanCollide = false
	base.CanTouch = false
	base.CanQuery = false
	base.Transparency = 1
	-- Mira hacia +Z (hacia el spawn del lobby).
	base.CFrame = CFrame.new(world.pedestalTop) * CFrame.Angles(0, math.pi, 0)
	base.Parent = model
	model.PrimaryPart = base

	model:SetAttribute(CA.Id, "giant")
	model:SetAttribute(CA.Species, speciesId)
	model:SetAttribute(CA.Rarity, species.rarity)
	model:SetAttribute(CA.Mutation, "NORMAL")
	model:SetAttribute(CA.Level, 0)
	model:SetAttribute(CA.Scale, cfg.scale)
	model:SetAttribute(CA.Owner, 0)
	model:SetAttribute(CA.Giant, true)
	model:SetAttribute(CA.EatingUntil, 0)
	model:SetAttribute(CA.Pivot, base.CFrame)
	model.Parent = workspace:FindFirstChild(Constants.Folders.Creatures) or workspace
	CollectionService:AddTag(model, Constants.Tags.Creature)
	return model
end

local function finishGiant(completed)
	local giant = state.giant
	if not giant then
		return
	end
	-- Se desvincula ANTES de repartir: una segunda llamada no puede volver a recompensar.
	state.giant = nil
	local rewards = EventLogic.giantRewards(giant.contributions, completed)
	for userId, reward in pairs(rewards) do
		local session = services.PlayerDataService.getSession(userId)
		if session then
			services.EconomyService.addCoins(userId, reward.coins)
			local text = string.format("Giant Beast %s! +%s coins (%d%% of the feast)", completed and "FED" or "left hungry", Utilities.formatNumber(reward.coins), math.floor(reward.share * 100 + 0.5))
			services.ValidationService.notify(session.player, text, "reward", "👹")
			if rnd() < EventLogic.truffleChance(reward, completed) then
				if services.FoodService.give(session, "VOID_TRUFFLE", 1) > 0 then
					services.ValidationService.notify(session.player, "The beast dropped a VOID TRUFFLE!", "reward", FoodConfig.Foods.VOID_TRUFFLE.icon)
				end
			end
		end
	end
	if giant.model then
		giant.model:Destroy()
	end
end

function EventService.giantFeed(session, foodId)
	local giant = state.giant
	if state.id ~= "GIANT_BEAST" or state.phase ~= "Active" or not giant then
		return false, "no_event"
	end
	local cfg = EventConfig.Events.GIANT_BEAST
	local food = FoodConfig.Foods[foodId]
	if not food then
		return false, "no_food_def"
	end
	local now = Clock.now()
	local userId = session.userId
	if now - (giant.lastFeed[userId] or -math.huge) < cfg.feedCooldown then
		return false, "cooldown"
	end
	local position = services.CharacterService.positionOf(userId)
	local center = services.PlotService.world().pedestalTop
	if not position or Vector3.new(position.X - center.X, 0, position.Z - center.Z).Magnitude > GameConfig.Interaction.GiantFeedDistance then
		return false, "too_far"
	end
	if not Inventory.remove(session.profile, foodId, 1) then
		return false, "no_food"
	end
	giant.lastFeed[userId] = now
	giant.contributions[userId] = (giant.contributions[userId] or 0) + food.growth
	giant.progress = math.min(giant.goal, giant.progress + food.growth)
	session.profile.stats.giantFeeds += 1
	services.StateService.push(userId, "inventory", "stats")
	stateFolder:SetAttribute(A.Progress, giant.progress)
	if giant.model then
		services.ValidationService.fireAll("CreatureEvent", giant.model, "Fed", { food = foodId, duration = 0.5, giant = true })
	end
	if giant.progress >= giant.goal then
		EventService.finish(true)
	end
	return true, nil
end

---------------------------------------------------------------------------------------------
-- Ciclo de vida
---------------------------------------------------------------------------------------------
local function start(eventId)
	local cfg = EventConfig.Events[eventId]
	local now = Clock.now()
	state.id = eventId
	state.phase = "Active"
	state.startsAt = now
	state.endsAt = now + cfg.duration
	state.spawnTimer = 0
	if eventId == "GIANT_BEAST" then
		state.giant = {
			model = spawnGiant(cfg),
			goal = EventLogic.giantGoal(services.PlayerDataService.count()),
			progress = 0,
			contributions = {},
			lastFeed = {},
		}
	end
	replicate()
	services.VFXService.playAll("EventStart", { position = services.PlotService.world().pedestalTop, radius = 6 })
	services.ValidationService.fireAll("Notify", { kind = "event", text = cfg.icon .. " " .. cfg.name .. " — " .. cfg.desc, color = cfg.color })
	-- La producción puede cambiar con el evento.
	services.PlayerDataService.forEach(function(session)
		services.EconomyService.incomeChanged(session.userId)
	end)
end

function EventService.finish(completed)
	if state.phase == "Idle" then
		return
	end
	local eventId = state.id
	if eventId == "GIANT_BEAST" then
		finishGiant(completed == true)
	end
	if state.phase == "Active" then
		services.FoodService.clear("event")
	end
	state.last = eventId
	state.id = nil
	state.phase = "Idle"
	state.nextAt = Clock.now() + EventLogic.nextCooldown(rnd)
	replicate()
	services.PlayerDataService.forEach(function(session)
		services.EconomyService.incomeChanged(session.userId)
	end)
end

function EventService.stop()
	EventService.finish(false)
end

local function announce(eventId)
	local now = Clock.now()
	state.id = eventId
	state.phase = "Announce"
	state.startsAt = now + EventConfig.AnnounceLead
	state.endsAt = state.startsAt + EventConfig.Events[eventId].duration
	replicate()
end

function EventService.forceStart(eventId)
	if not EventConfig.Events[eventId] then
		return false
	end
	if state.phase ~= "Idle" then
		EventService.finish(false)
	end
	start(eventId)
	return true
end

local function updateActive(dt, cfg)
	if state.id == "FOOD_RAIN" or state.id == "GOLDEN_FEAST" then
		state.spawnTimer += dt
		while state.spawnTimer >= cfg.spawnInterval do
			state.spawnTimer -= cfg.spawnInterval
			if services.FoodService.count("event") < cfg.maxActive then
				local foodId = Rolls.eventFood(state.id, rnd)
				if foodId then
					local x, z = PlotLayout.foodPoint(rnd)
					services.FoodService.spawn(foodId, Vector3.new(x, services.FoodService.GROUND_Y + services.FoodService.FLOAT, z), {
						source = "event",
						golden = state.id == "GOLDEN_FEAST",
						dropFrom = cfg.dropHeight or 0,
						delay = cfg.dropHeight and 0.9 or 0,
						lifetime = 40,
					})
				end
			end
		end
	end
end

function EventService.Init(allServices)
	services = allServices
	stateFolder = Instance.new("Folder")
	stateFolder.Name = Constants.Folders.EventState
	state.nextAt = Clock.now() + EventConfig.FirstDelay
	replicate()
	stateFolder.Parent = ReplicatedStorage
end

function EventService.Start()
	services.ValidationService.on("GiantFeed", function(player, foodId)
		local session = services.PlayerDataService.sessionOf(player)
		if not session then
			return
		end
		local ok, reason = EventService.giantFeed(session, foodId)
		if not ok and reason == "too_far" then
			services.ValidationService.notify(player, "Get closer to the Giant Beast!", "error", "📏")
		end
	end)
end

function EventService.Update(dt)
	local now = Clock.now()
	if state.phase == "Idle" then
		-- `Enabled = false` solo apaga la programación automática: un evento forzado (admin)
		-- sigue su ciclo completo.
		if EventConfig.Enabled and now >= state.nextAt and services.PlayerDataService.count() > 0 then
			local eventId = EventLogic.pickEvent(rnd, state.last)
			if eventId then
				announce(eventId)
			end
		end
	elseif state.phase == "Announce" then
		if now >= state.startsAt then
			start(state.id)
		end
	elseif state.phase == "Active" then
		if now >= state.endsAt then
			EventService.finish(false)
		else
			updateActive(dt, EventConfig.Events[state.id])
		end
	end
end

return EventService
