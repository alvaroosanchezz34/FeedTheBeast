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
local Players = game:GetService("Players")
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
local FoodModels = require(Shared.Food.FoodModels)
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

local LOOK_DISTANCE = 34
local EXCITED_DISTANCE = 16
local BLINK_TIME = 0.16
local HAPPY_TIME = 0.9

local function localRootPosition()
	local player = Players.LocalPlayer
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and root.CFrame.Position or nil
end

local function hasFood()
	local inventory = StateController.get("inventory")
	return inventory ~= nil and next(inventory) ~= nil
end

local startBite -- definida más abajo

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
		local stage = EconomyMath.stageFor(entry.level)
		table.insert(parts, (stage > 1 and string.rep("★", stage - 1) .. " " or "") .. "Lv " .. tostring(entry.level))
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
	if entry.bite then
		entry.bite.visual:destroy()
		entry.bite = nil
	end
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
		seed = math.random() * 6.28,
		tempo = 0.88 + math.random() * 0.24,
		lookX = 0,
		lookY = 0,
		blinkIn = 1 + math.random() * 3,
		happy = nil,
		near = true,
		connections = {},
	}
	entry.isOwn = entry.ownerId == StateController.localUserId()

	MutationVisuals.apply(visual, entry.mutationId)
	visual:setStage(entry.isGiant and 1 or EconomyMath.stageFor(entry.level))
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
		local stage = EconomyMath.stageFor(entry.level)
		if stage ~= visual.stage then
			visual:setStage(stage)
		end
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
		startBite(entry, data.food, duration)
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
		if data.evolved then
			entry.growAfter = { delay = duration, effect = "Evolve" }
		elseif data.first then
			entry.growAfter = { delay = duration, effect = "FirstFeed" }
		elseif data.leveledUp then
			entry.growAfter = { delay = duration, effect = VFXConfig.MutationGrowEffects[entry.mutationId] or "Grow" }
		end
	elseif kind == "Spawned" then
		-- Aparece creciendo desde pequeño.
		applyScale(entry, entry.targetScale * 0.25)
	end
end

-- La comida entra volando en la boca durante la primera parte del mordisco.
local BITE_PORTION = 0.42

local function clearBite(entry)
	if entry.bite then
		entry.bite.visual:destroy()
		entry.bite = nil
	end
end

function startBite(entry, foodId, duration)
	clearBite(entry)
	if not entry.near or not foodId then
		return
	end
	local visual = FoodModels.build(foodId)
	if not visual then
		return
	end
	visual.model.Parent = entry.visual.model
	entry.bite = { visual = visual, elapsed = 0, duration = math.max(0.15, duration * BITE_PORTION) }
end

local function updateBite(entry, dt)
	local bite = entry.bite
	if not bite then
		return
	end
	bite.elapsed += dt
	local a = bite.elapsed / bite.duration
	if a >= 1 then
		clearBite(entry)
		return
	end
	local mouth = entry.visual:anchorWorld("Mouth")
	local root = entry.visual.root.CFrame
	local reach = entry.visual.radius * entry.displayScale
	-- Sale de delante y un poco por encima de la criatura y describe un arco hasta la boca.
	local start = mouth + root.LookVector * (reach * 1.2 + 2) + Vector3.new(0, reach * 0.5 + 1, 0)
	local position = start:Lerp(mouth, a) + Vector3.new(0, math.sin(a * math.pi) * 1.2, 0)
	local size = math.clamp(reach / 3, 0.6, 2.2) * (1 - a * 0.75)
	bite.visual:setScale(size)
	bite.visual.root.CFrame = CFrame.new(position - Vector3.new(0, bite.visual.height * size * 0.5, 0)) * CFrame.Angles(0, a * 5, 0)
end

local function updateEntry(entry, dt, animate)
	updateBite(entry, dt)
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
			-- Reacción de satisfacción al terminar de comer.
			entry.happy = { elapsed = 0, duration = HAPPY_TIME }
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
		local visual = entry.visual
		local species = entry.species
		local mutation = MutationConfig.Mutations[entry.mutationId]

		-- Atención al jugador: lo sigue con la mirada y se anima si llega con comida.
		local lookX, lookY, excited = 0, 0, false
		local target = localRootPosition()
		if target then
			local rel = visual.root.CFrame:PointToObjectSpace(target)
			local distance = rel.Magnitude
			if distance < LOOK_DISTANCE then
				lookX = math.clamp(rel.X / 9, -1, 1)
				lookY = math.clamp((rel.Y - visual.height * entry.displayScale * 0.6) / 9, -1, 1)
				excited = entry.isOwn and distance < EXCITED_DISTANCE and hasFood()
			end
		end
		if lookX == 0 and lookY == 0 then
			-- Sin nadie cerca, la mirada vaga despacio.
			lookX = math.sin(entry.animTime * 0.6 + entry.seed) * 0.6
			lookY = math.sin(entry.animTime * 0.43 + entry.seed * 2) * 0.3
		end
		local blend = math.min(1, dt * 6)
		entry.lookX += (lookX - entry.lookX) * blend
		entry.lookY += (lookY - entry.lookY) * blend

		-- Cada criatura lleva su propio ritmo (no se mueven sincronizadas).
		local speed = (mutation and mutation.animSpeed or 1) * entry.tempo * (excited and 1.6 or 1)
		entry.animTime += dt * speed
		if species.idle then
			species.idle(visual, entry.animTime)
		end
		if eating and species.eat then
			species.eat(visual, eating.elapsed / eating.duration)
		end
		local happy = entry.happy
		if happy then
			happy.elapsed += dt
			local a = happy.elapsed / happy.duration
			if a >= 1 then
				entry.happy = nil
				happy = nil
			elseif species.happy then
				species.happy(visual, a)
			end
		end

		-- Parpadeo: breve, a intervalos irregulares; ojos entrecerrados de gusto tras comer.
		entry.blinkIn -= dt
		local blink = 0
		if entry.blinkIn <= 0 then
			local a = -entry.blinkIn / BLINK_TIME
			if a >= 1 then
				entry.blinkIn = 1.8 + math.random() * 3.6
			else
				blink = math.sin(a * math.pi)
			end
		end
		if happy then
			blink = math.max(blink, 0.55 * math.sin(math.min(1, happy.elapsed / happy.duration) * math.pi))
		end
		visual:setLook(entry.lookX, entry.lookY)
		visual:setBlink(blink)
		visual:applyPoses()
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
			entry.happy = nil
			if entry.bite then
				entry.bite.visual:destroy()
				entry.bite = nil
			end
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
