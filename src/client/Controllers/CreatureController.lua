-- Presentación de las criaturas en el cliente.
-- El servidor replica un modelo mínimo con atributos (especie, mutación, escala, nivel, dueño);
-- aquí se construye el aspecto visual, se anima, se escala con suavidad y se conectan auras,
-- placas de nombre y la interacción de alimentar. Nada de esto concede recompensas.
--
-- API:
--   CreatureController.visualFor(model) -> Visual | nil, escalaActual
--   CreatureController.pop(model, amount)           -- pulso de escala
--   CreatureController.entries() -> tabla clave -> entrada
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local GameConfig = require(Shared.Config.GameConfig)
local CreatureConfig = require(Shared.Config.CreatureConfig)
local MutationConfig = require(Shared.Config.MutationConfig)
local RarityConfig = require(Shared.Config.RarityConfig)
local FoodConfig = require(Shared.Config.FoodConfig)
local VFXConfig = require(Shared.Config.VFXConfig)
local EconomyMath = require(Shared.Logic.EconomyMath)
local CreatureBuilder = require(Shared.Creatures.CreatureBuilder)
local MutationVisuals = require(Shared.Creatures.MutationVisuals)
local Signal = require(Shared.Signal)

local CreatureController = {}

CreatureController.FeedRequested = Signal.new() -- (entry) al pulsar el prompt
CreatureController.FeedReleased = Signal.new() -- (entry) al soltarlo

local controllers
local StateController
local SettingsController
local AuraController
local EffectsController

local A = Constants.CreatureAttr

local entries = {} -- clave -> entrada
local order = {}
local lodTimer = math.huge
local frameAccumulator = 0

local function keyOf(model)
	local id = model:GetAttribute(A.Id)
	if id == nil then
		return nil
	end
	return tostring(model:GetAttribute(A.Owner) or 0) .. ":" .. tostring(id)
end

local function makeNameplate(entry)
	local species = CreatureConfig.Species[entry.speciesId]
	local rarity = RarityConfig.Rarities[species.rarity]
	local gui = Instance.new("BillboardGui")
	gui.Name = "Nameplate"
	gui.Size = UDim2.fromOffset(190, 54)
	gui.AlwaysOnTop = false
	gui.MaxDistance = entry.isGiant and 400 or 70
	gui.LightInfluence = 0
	gui.Adornee = entry.visual.root

	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, 28)
	name.Font = Enum.Font.FredokaOne
	name.TextSize = 24
	name.TextColor3 = rarity.color
	name.TextStrokeTransparency = 0.2
	name.TextStrokeColor3 = Color3.fromRGB(20, 20, 30)
	name.Text = entry.isGiant and ("GIANT " .. string.upper(species.name)) or species.name
	name.Parent = gui

	local info = Instance.new("TextLabel")
	info.Name = "Info"
	info.BackgroundTransparency = 1
	info.Position = UDim2.fromOffset(0, 28)
	info.Size = UDim2.new(1, 0, 0, 22)
	info.Font = Enum.Font.GothamBold
	info.TextSize = 16
	info.TextColor3 = Color3.fromRGB(255, 255, 255)
	info.TextStrokeTransparency = 0.3
	info.Text = ""
	info.Parent = gui

	gui.Parent = entry.visual.model
	entry.nameplate = gui
	entry.infoLabel = info
end

local function refreshNameplate(entry)
	if not entry.nameplate then
		return
	end
	local mutation = MutationConfig.Mutations[entry.mutationId]
	local parts = {}
	if entry.isGiant then
		table.insert(parts, "Feed me!")
	else
		table.insert(parts, "Lv " .. tostring(entry.level))
	end
	if mutation and mutation.id ~= "NORMAL" then
		table.insert(parts, "· " .. string.upper(mutation.name))
		entry.infoLabel.TextColor3 = mutation.color
	else
		entry.infoLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	end
	entry.infoLabel.Text = table.concat(parts, " ")
	entry.nameplate.StudsOffsetWorldSpace = Vector3.new(0, entry.visual.height * entry.displayScale + 1.6, 0)
end

-- Prompt local (solo en criaturas propias y en la bestia gigante).
local function makePrompt(entry)
	local species = CreatureConfig.Species[entry.speciesId]
	local holder = Instance.new("Part")
	holder.Name = "PromptHolder"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanTouch = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.5, 0.5, 0.5)
	holder.Parent = entry.visual.model

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "FeedPrompt"
	prompt.ActionText = entry.isGiant and "Feed the Beast" or "Feed"
	prompt.ObjectText = species.name
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = holder
	prompt.Triggered:Connect(function()
		CreatureController.FeedRequested:Fire(entry)
	end)
	prompt.TriggerEnded:Connect(function()
		CreatureController.FeedReleased:Fire(entry)
	end)
	entry.promptHolder = holder
	entry.prompt = prompt
end

local function refreshPrompt(entry)
	if not entry.prompt then
		return
	end
	local visual = entry.visual
	entry.promptHolder.CFrame = CFrame.new(visual.root.CFrame.Position + Vector3.new(0, visual.center.Y * entry.displayScale, 0))
	if entry.isGiant then
		entry.prompt.MaxActivationDistance = GameConfig.Interaction.GiantFeedDistance - 4
	else
		local species = CreatureConfig.Species[entry.speciesId]
		local reach = GameConfig.Interaction.FeedBaseDistance + species.baseRadius * EconomyMath.hitboxScale(entry.targetScale)
		entry.prompt.MaxActivationDistance = math.max(6, reach - 1.5)
	end
end

local function applyScale(entry, scale)
	if math.abs(scale - entry.displayScale) < 0.002 then
		return
	end
	entry.displayScale = scale
	entry.visual:setScale(scale)
end

local function attachAura(entry)
	AuraController.attach(entry.key, entry.visual, entry.mutationId, entry.rarity, entry.targetScale)
end

local function destroyEntry(key)
	local entry = entries[key]
	if not entry then
		return
	end
	entries[key] = nil
	local index = table.find(order, key)
	if index then
		table.remove(order, index)
	end
	for _, connection in ipairs(entry.connections) do
		connection:Disconnect()
	end
	AuraController.detach(key)
	entry.visual:destroy()
end

local function buildEntry(model)
	local key = keyOf(model)
	local speciesId = model:GetAttribute(A.Species)
	if not key or not speciesId or not CreatureConfig.Species[speciesId] then
		return nil
	end
	if entries[key] then
		destroyEntry(key)
	end
	local visual = CreatureBuilder.build(speciesId)
	if not visual then
		return nil
	end
	local pivot = model:GetAttribute(A.Pivot)
	if typeof(pivot) ~= "CFrame" then
		pivot = model:GetPivot()
	end
	visual.root.CFrame = pivot

	local scale = model:GetAttribute(A.Scale) or 1
	local entry = {
		key = key,
		model = model,
		visual = visual,
		speciesId = speciesId,
		species = visual.species,
		rarity = model:GetAttribute(A.Rarity) or "Common",
		mutationId = model:GetAttribute(A.Mutation) or "NORMAL",
		level = model:GetAttribute(A.Level) or 0,
		ownerId = model:GetAttribute(A.Owner) or 0,
		creatureId = model:GetAttribute(A.Id),
		isGiant = model:GetAttribute(A.Giant) == true,
		targetScale = scale,
		baseScale = scale,
		displayScale = 1,
		pops = {},
		eat = nil,
		growAfter = nil,
		animTime = math.random() * 10,
		near = true,
		connections = {},
	}
	entry.isOwn = entry.ownerId == StateController.localUserId()

	MutationVisuals.apply(visual, entry.mutationId)
	visual.model.Parent = model
	applyScale(entry, scale)
	makeNameplate(entry)
	refreshNameplate(entry)
	if entry.isOwn or entry.isGiant then
		makePrompt(entry)
		refreshPrompt(entry)
	end
	attachAura(entry)

	table.insert(entry.connections, model:GetAttributeChangedSignal(A.Scale):Connect(function()
		local value = model:GetAttribute(A.Scale)
		if type(value) == "number" then
			entry.targetScale = value
			refreshPrompt(entry)
			AuraController.setScale(key, value)
		end
	end))
	table.insert(entry.connections, model:GetAttributeChangedSignal(A.Level):Connect(function()
		entry.level = model:GetAttribute(A.Level) or 0
		refreshNameplate(entry)
	end))
	table.insert(entry.connections, model:GetAttributeChangedSignal(A.Mutation):Connect(function()
		local value = model:GetAttribute(A.Mutation)
		if value and value ~= entry.mutationId and MutationConfig.Mutations[value] then
			entry.mutationId = value
			MutationVisuals.apply(visual, value)
			refreshNameplate(entry)
			attachAura(entry)
		end
	end))

	entries[key] = entry
	table.insert(order, key)
	lodTimer = math.huge
	return entry
end

local function onAdded(model)
	if not model:IsA("Model") then
		return
	end
	if model:GetAttribute(A.Species) ~= nil and model:GetAttribute(A.Id) ~= nil then
		buildEntry(model)
		return
	end
	-- Los atributos pueden llegar un instante después que la instancia.
	local connection
	connection = model.AttributeChanged:Connect(function()
		if model:GetAttribute(A.Species) ~= nil and model:GetAttribute(A.Id) ~= nil then
			connection:Disconnect()
			buildEntry(model)
		end
	end)
end

local function onRemoved(model)
	for key, entry in pairs(entries) do
		if entry.model == model then
			destroyEntry(key)
			return
		end
	end
end

local function entryFor(model)
	if typeof(model) ~= "Instance" then
		return nil
	end
	local key = keyOf(model)
	return key and entries[key] or nil
end

function CreatureController.visualFor(model)
	local entry = entryFor(model)
	if entry then
		return entry.visual, entry.displayScale
	end
	return nil, 1
end

function CreatureController.entries()
	return entries
end

function CreatureController.pop(model, amount)
	local entry = entryFor(model)
	if entry then
		table.insert(entry.pops, { amount = amount, elapsed = 0, duration = 0.32 })
	end
end

-- Eventos de criatura enviados por el servidor (cosméticos).
local function onCreatureEvent(model, kind, data)
	local entry = entryFor(model)
	if not entry or type(data) ~= "table" then
		return
	end
	if kind == "Fed" then
		local food = FoodConfig.Foods[data.food]
		local duration = type(data.duration) == "number" and math.clamp(data.duration, 0.2, 3) or 0.8
		entry.eat = { elapsed = 0, duration = duration }
		if entry.isGiant then
			EffectsController.play("GiantBite", { model = model })
			return
		end
		local feedEffect = food and VFXConfig.FoodFeedEffects[food.vfx] or "FeedCrumbs"
		EffectsController.play(feedEffect, { model = model })
		local extra = VFXConfig.MutationFeedEffects[entry.mutationId]
		if extra then
			EffectsController.play(extra, { model = model })
		end
		if data.first then
			entry.growAfter = { delay = duration, effect = "FirstFeed" }
		elseif data.leveledUp then
			entry.growAfter = { delay = duration, effect = VFXConfig.MutationGrowEffects[entry.mutationId] or "Grow" }
		end
	elseif kind == "Spawned" then
		-- Aparece creciendo desde pequeño.
		applyScale(entry, entry.targetScale * 0.25)
	end
end

local function updateEntry(entry, dt, animate)
	-- Pulsos de escala
	local popFactor = 1
	local index = 1
	while index <= #entry.pops do
		local pop = entry.pops[index]
		pop.elapsed += dt
		local a = pop.elapsed / pop.duration
		if a >= 1 then
			table.remove(entry.pops, index)
		else
			popFactor *= 1 + (pop.amount - 1) * math.sin(a * math.pi)
			index += 1
		end
	end

	-- Mientras come, el crecimiento espera a que termine el mordisco.
	local eating = entry.eat
	if eating then
		eating.elapsed += dt
		if eating.elapsed >= eating.duration then
			entry.eat = nil
			eating = nil
		end
	end
	if entry.growAfter then
		entry.growAfter.delay -= dt
		if entry.growAfter.delay <= 0 then
			EffectsController.play(entry.growAfter.effect, { model = entry.model })
			entry.growAfter = nil
		end
	end

	if not eating then
		local diff = entry.targetScale - entry.baseScale
		if math.abs(diff) > 0.001 then
			entry.baseScale += diff * math.min(1, dt * 5)
		else
			entry.baseScale = entry.targetScale
		end
	end
	local wanted = entry.baseScale * popFactor
	if math.abs(wanted - entry.displayScale) >= 0.002 then
		applyScale(entry, wanted)
		refreshNameplate(entry)
	end

	if animate then
		local mutation = MutationConfig.Mutations[entry.mutationId]
		entry.animTime += dt * (mutation and mutation.animSpeed or 1)
		local species = entry.species
		if species.idle then
			species.idle(entry.visual, entry.animTime)
		end
		if eating and species.eat then
			species.eat(entry.visual, eating.elapsed / eating.duration)
		end
		entry.visual:applyPoses()
	end
end

local function updateLod()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local limit = SettingsController.qualityConfig().animDistance
	local cameraPos = camera.CFrame.Position
	for _, key in ipairs(order) do
		local entry = entries[key]
		local distance = (entry.visual.root.CFrame.Position - cameraPos).Magnitude
		local near = distance <= limit or entry.isGiant
		if entry.near and not near then
			-- Al dejar de animar vuelve a la pose de reposo y al tamaño final.
			entry.visual:resetPoses()
			entry.baseScale = entry.targetScale
		end
		entry.near = near
	end
end

function CreatureController.Init(allControllers)
	controllers = allControllers
	StateController = controllers.StateController
	SettingsController = controllers.SettingsController
	AuraController = controllers.AuraController
	EffectsController = controllers.EffectsController
end

function CreatureController.Start()
	CollectionService:GetInstanceAddedSignal(Constants.Tags.Creature):Connect(onAdded)
	CollectionService:GetInstanceRemovedSignal(Constants.Tags.Creature):Connect(onRemoved)
	for _, model in ipairs(CollectionService:GetTagged(Constants.Tags.Creature)) do
		task.spawn(onAdded, model)
	end
	StateController.remote("CreatureEvent").OnClientEvent:Connect(onCreatureEvent)
end

function CreatureController.Update(dt)
	lodTimer += dt
	if lodTimer >= 0.5 then
		lodTimer = 0
		updateLod()
	end
	-- La animación se ejecuta a la frecuencia de la calidad elegida; la escala, cada frame.
	local hz = SettingsController.qualityConfig().animHz
	frameAccumulator += dt
	local animate = frameAccumulator >= 1 / hz
	local animDt = frameAccumulator
	if animate then
		frameAccumulator = 0
	end
	for _, key in ipairs(order) do
		local entry = entries[key]
		if entry.near then
			if animate then
				updateEntry(entry, animDt, true)
			elseif #entry.pops > 0 or entry.baseScale ~= entry.targetScale then
				updateEntry(entry, 0, false)
			end
		else
			-- Lejos de la cámara no se anima: se descartan las animaciones pendientes para que no
			-- se reproduzcan con retraso al acercarse, y el tamaño salta al valor final.
			entry.eat = nil
			entry.growAfter = nil
			if #entry.pops > 0 then
				table.clear(entry.pops)
			end
			if entry.displayScale ~= entry.targetScale then
				entry.baseScale = entry.targetScale
				applyScale(entry, entry.targetScale)
				refreshNameplate(entry)
			end
		end
	end
end

return CreatureController
