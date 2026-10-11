-- Comida recogible en el mundo. La recogida se decide por distancia medida en el servidor
-- (bucle único a ~8 Hz), sin remotos ni eventos Touched: el cliente no puede "decir" que la cogió.
--
-- API:
--   FoodService.spawn(foodId, position, opts) -> entry    opts = { source, lifetime, owner, golden, dropFrom, delay }
--   FoodService.count(source) -> número activo de esa fuente
--   FoodService.clear(source)
--   FoodService.give(session, foodId, amount) -> añadidas   (respeta capacidad)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local FoodConfig = require(Shared.Config.FoodConfig)
local Constants = require(Shared.Constants)
local EconomyMath = require(Shared.Logic.EconomyMath)
local Inventory = require(Shared.Logic.Inventory)
local Rolls = require(Shared.Logic.Rolls)
local PlotLayout = require(Shared.Logic.PlotLayout)
local Clock = require(Shared.Clock)

local FoodService = {}

local services
local cfg = GameConfig.FoodField
local folder
local pickups = {} -- lista de entradas
local nextId = 1
local spawnTimer = 0
local scanTimer = 0
local fullNotice = {} -- userId -> reloj del último aviso de mochila llena
local rng = Random.new()

local function rnd()
	return rng:NextNumber()
end

local GROUND_Y = 0.26
local FLOAT = 1.7

function FoodService.spawn(foodId, position, opts)
	local def = FoodConfig.Foods[foodId]
	if not def then
		return nil
	end
	opts = opts or {}
	local now = Clock.now()
	local part = Instance.new("Part")
	part.Name = "Pickup_" .. foodId
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = opts.golden and Enum.Material.Neon or Enum.Material.SmoothPlastic
	part.Color = def.color
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if def.shape == "Ball" then
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(2.2, 2.2, 2.2)
	elseif def.shape == "Cylinder" then
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(1.2, 2.4, 2.4)
	else
		part.Size = Vector3.new(2, 2, 2)
	end
	part.CFrame = CFrame.new(position)
	part:SetAttribute(Constants.PickupAttr.Id, nextId)
	part:SetAttribute(Constants.PickupAttr.Food, foodId)
	part:SetAttribute(Constants.PickupAttr.Golden, opts.golden == true)
	part:SetAttribute(Constants.PickupAttr.DropFrom, opts.dropFrom or 0)
	part:SetAttribute(Constants.PickupAttr.Owner, opts.owner or 0)
	part.Parent = folder
	CollectionService:AddTag(part, Constants.Tags.Pickup)

	local entry = {
		id = nextId,
		part = part,
		foodId = foodId,
		position = position,
		source = opts.source or "field",
		owner = opts.owner,
		availableAt = now + (opts.delay or 0),
		expiresAt = now + (opts.lifetime or cfg.Lifetime),
	}
	nextId += 1
	table.insert(pickups, entry)
	return entry
end

local function removeAt(index)
	local entry = pickups[index]
	pickups[index] = pickups[#pickups]
	pickups[#pickups] = nil
	if entry.part then
		entry.part:Destroy()
		entry.part = nil
	end
end

function FoodService.count(source)
	local n = 0
	for _, entry in ipairs(pickups) do
		if source == nil or entry.source == source then
			n += 1
		end
	end
	return n
end

function FoodService.clear(source)
	for index = #pickups, 1, -1 do
		if pickups[index].source == source then
			removeAt(index)
		end
	end
end

-- Añade comida al inventario respetando la capacidad. Devuelve cuántas se añadieron.
function FoodService.give(session, foodId, amount)
	local added = Inventory.add(session.profile, foodId, amount, EconomyMath.inventoryCapacity(session.profile))
	if added > 0 then
		services.StateService.push(session.userId, "inventory")
	end
	return added
end

local function tryCollect(session, entry)
	local profile = session.profile
	local capacity = EconomyMath.inventoryCapacity(profile)
	if Inventory.count(profile) >= capacity then
		local now = Clock.now()
		if now - (fullNotice[session.userId] or -math.huge) >= cfg.FullNoticeCooldown then
			fullNotice[session.userId] = now
			services.ValidationService.notify(session.player, "Backpack full! Feed your creatures.", "error", "🎒")
		end
		return false
	end
	local amount = 1
	if rnd() < EconomyMath.harvestDoubleChance(profile) then
		amount = 2
	end
	local added = Inventory.add(profile, entry.foodId, amount, capacity)
	if added <= 0 then
		return false
	end
	profile.stats.foodsCollected += added
	services.StateService.push(session.userId, "inventory", "stats")
	services.VFXService.playFor(session.player, "PickupFood", { position = entry.position, radius = 1.2, food = entry.foodId, amount = added })
	return true
end

function FoodService.spawnStarter(session)
	local plot = session.plotIndex and services.PlotService.plot(session.plotIndex)
	if not plot then
		return
	end
	for i, foodId in ipairs(GameConfig.StarterPickups) do
		local loc = PlotLayout.Local.StarterFood[i]
		if loc then
			local wx, wz = PlotLayout.toWorld(plot.layout, loc.x, loc.z)
			FoodService.spawn(foodId, Vector3.new(wx, 0.3 + FLOAT, wz), {
				source = "starter",
				owner = session.userId,
				lifetime = cfg.StarterLifetime,
			})
		end
	end
end

local function spawnField()
	local target = math.min(cfg.MaxActive, cfg.BaseActive + cfg.PerPlayer * services.PlayerDataService.count())
	if FoodService.count("field") >= target then
		return
	end
	local foodId = Rolls.fieldFood(rnd)
	if not foodId then
		return
	end
	local x, z = PlotLayout.foodPoint(rnd)
	FoodService.spawn(foodId, Vector3.new(x, GROUND_Y + FLOAT, z), { source = "field" })
end

FoodService.GROUND_Y = GROUND_Y
FoodService.FLOAT = FLOAT

function FoodService.Init(allServices)
	services = allServices
	folder = workspace:FindFirstChild(Constants.Folders.Pickups)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Constants.Folders.Pickups
		folder.Parent = workspace
	end
end

function FoodService.Start()
	services.PlayerDataService.SessionStarted:Connect(function(session)
		-- Comida en la propia parcela para que la primera alimentación llegue en segundos.
		if session.plotIndex and session.profile.stats.foodsFed == 0 then
			FoodService.spawnStarter(session)
		end
	end)
	services.PlayerDataService.SessionEnding:Connect(function(session)
		fullNotice[session.userId] = nil
		for index = #pickups, 1, -1 do
			if pickups[index].owner == session.userId then
				removeAt(index)
			end
		end
	end)
	-- Siembra inicial para que el campo no esté vacío al abrir el servidor.
	for _ = 1, cfg.BaseActive do
		spawnField()
	end
end

function FoodService.Update(dt)
	spawnTimer += dt
	if spawnTimer >= cfg.SpawnInterval then
		spawnTimer = 0
		spawnField()
	end

	scanTimer += dt
	if scanTimer < 0.12 then
		return
	end
	scanTimer = 0
	local now = Clock.now()

	-- Caducidad
	for index = #pickups, 1, -1 do
		if now >= pickups[index].expiresAt then
			removeAt(index)
		end
	end

	-- Recogida por proximidad
	local radius = cfg.PickupRadius
	services.PlayerDataService.forEach(function(session)
		local position = services.CharacterService.positionOf(session.userId)
		if not position then
			return
		end
		for index = #pickups, 1, -1 do
			local entry = pickups[index]
			if now >= entry.availableAt and (entry.owner == nil or entry.owner == session.userId) then
				local delta = entry.position - position
				if math.abs(delta.Y) < 8 and delta.X * delta.X + delta.Z * delta.Z <= radius * radius then
					if tryCollect(session, entry) then
						removeAt(index)
					else
						break -- mochila llena: no seguir comprobando para este jugador
					end
				end
			end
		end
	end)
end

return FoodService
