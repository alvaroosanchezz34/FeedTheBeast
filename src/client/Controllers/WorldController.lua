-- Presentación del mundo en el cliente: comida recogible, cajas, parcelas y kioscos.
-- El servidor replica piezas mínimas con atributos; aquí se añaden iconos, carteles, animación,
-- prompts de kiosco y la línea-guía. Nada de esto afecta a la lógica: recoger, entregar o robar
-- lo decide el servidor por distancia.
--
-- API:
--   WorldController.ownPlot() -> { model, collectPos, deliveryPos, spawnPos } | nil
--   WorldController.guideTo(position | nil, color?)     línea-guía desde el jugador
--   WorldController.carried() -> { id, tier } | nil     caja que lleva el jugador local
--   WorldController.CarryChanged : Signal(carried | nil)
--   WorldController.KioskOpened : Signal(kioskId)
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local FoodConfig = require(Shared.Config.FoodConfig)
local RarityConfig = require(Shared.Config.RarityConfig)
local TheftConfig = require(Shared.Config.TheftConfig)
local VFXConfig = require(Shared.Config.VFXConfig)
local FoodModels = require(Shared.Food.FoodModels)
local Utilities = require(Shared.Utilities)
local Signal = require(Shared.Signal)

local WorldController = {}

WorldController.CarryChanged = Signal.new()
WorldController.KioskOpened = Signal.new()

local controllers
local StateController
local SettingsController

local PA = Constants.PickupAttr
local CA = Constants.CrateAttr
local LA = Constants.PlotAttr

local DISPLAY = Enum.Font.FredokaOne
local BODY = Enum.Font.GothamBold
local WHITE = Color3.fromRGB(255, 255, 255)
local INK = Color3.fromRGB(23, 26, 43)

local clock = 0
local localUserId = 0

local function label(parent, props)
	local text = Instance.new("TextLabel")
	text.Name = props.name or "Label"
	text.BackgroundTransparency = 1
	text.Size = props.size or UDim2.fromScale(1, 1)
	text.Position = props.position or UDim2.new()
	text.Font = props.font or DISPLAY
	text.Text = props.text or ""
	text.TextColor3 = props.color or WHITE
	text.TextScaled = props.scaled ~= false
	text.TextSize = props.textSize or 24
	text.TextStrokeColor3 = INK
	text.TextStrokeTransparency = props.stroke or 0.15
	text.Parent = parent
	return text
end

local function billboard(parent, name, size, offset, maxDistance, alwaysOnTop)
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Size = size
	gui.StudsOffsetWorldSpace = offset
	gui.MaxDistance = maxDistance
	gui.AlwaysOnTop = alwaysOnTop == true
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.Parent = parent
	return gui
end

-- Espera (sin bloquear) a que exista un hijo; con StreamingEnabled o en la primera carga los
-- hijos pueden llegar después que el contenedor.
local function whenChild(parent, name, callback)
	local child = parent:FindFirstChild(name)
	if child then
		callback(child)
		return
	end
	task.spawn(function()
		local found = parent:WaitForChild(name, 20)
		if found and parent.Parent then
			callback(found)
		end
	end)
end

---------------------------------------------------------------------------------------------
-- Comida recogible
---------------------------------------------------------------------------------------------
local pickups = {} -- lista de { id, part, base, phase, drop, dropElapsed, hidden }
local DROP_TIME = 0.9 -- igual que el retardo de recogida del servidor (EventService)
local ANIM_DISTANCE = 110

local function findPickup(id)
	for index, entry in ipairs(pickups) do
		if entry.id == id then
			return entry, index
		end
	end
	return nil, nil
end

local GROUND_OFFSET = 1.55 -- la pieza lógica flota a esta altura sobre el suelo
local APPEAR_TIME = 0.35

local function groundDisc(parent, position, diameter, color, transparency)
	local disc = Instance.new("Part")
	disc.Name = "Ground"
	disc.Shape = Enum.PartType.Cylinder
	disc.Anchored = true
	disc.CanCollide = false
	disc.CanTouch = false
	disc.CanQuery = false
	disc.CastShadow = false
	disc.Material = Enum.Material.SmoothPlastic
	disc.Color = color
	disc.Transparency = transparency
	disc.Size = Vector3.new(0.06, diameter, diameter)
	disc.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	disc.Parent = parent
	return disc
end

local function addPickup(part)
	if not part:IsA("BasePart") then
		return
	end
	local id = part:GetAttribute(PA.Id)
	local foodId = part:GetAttribute(PA.Food)
	local def = foodId and FoodConfig.Foods[foodId]
	if id == nil or not def or findPickup(id) then
		return
	end
	local owner = part:GetAttribute(PA.Owner) or 0
	local hidden = owner ~= 0 and owner ~= localUserId
	local base = part.CFrame
	local entry = {
		id = id,
		part = part,
		base = base,
		phase = (id * 0.73) % 6.28,
		drop = part:GetAttribute(PA.DropFrom) or 0,
		dropElapsed = 0,
		appear = 0,
		hidden = hidden,
		visual = nil,
	}
	-- La comida de bienvenida de otro jugador no se puede recoger, así que no se construye.
	if not hidden then
		local visual = FoodModels.build(foodId)
		if visual then
			entry.visual = visual
			entry.lift = -visual.height * 0.5 -- el modelo se apoya en su base; se centra en la pieza
			local golden = part:GetAttribute(PA.Golden) == true
			if golden then
				-- Variante dorada del evento: acabado metálico sobre el mismo modelo.
				for _, record in ipairs(visual.records) do
					record.part.Color = record.part.Color:Lerp(Color3.fromRGB(255, 206, 70), 0.72)
					record.part.Material = Enum.Material.Metal
					record.part.Reflectance = 0.3
				end
			end
			visual:setScale(0.05)
			visual.root.CFrame = base * CFrame.new(0, entry.lift, 0)
			visual.model.Parent = part
			-- Contacto con el suelo: sombra y, en comida rara, un aro del color de su rareza.
			local ground = base.Position - Vector3.new(0, GROUND_OFFSET, 0)
			groundDisc(part, ground, visual.radius * 1.7, Color3.fromRGB(10, 14, 24), 0.72)
			local rarityIndex = RarityConfig.Index[def.rarity]
			if rarityIndex >= RarityConfig.Index.Rare or golden then
				local color = golden and Color3.fromRGB(255, 214, 90) or RarityConfig.Rarities[def.rarity].color
				local ring = groundDisc(part, ground + Vector3.new(0, 0.03, 0), visual.radius * 2.4, color, 0.55)
				ring.Material = Enum.Material.Neon
				if SettingsController.quality() ~= "Low" then
					local emitter = Instance.new("ParticleEmitter")
					emitter.Name = "RarityGlow"
					emitter.Texture = VFXConfig.Textures.Sparkle
					emitter.Rate = rarityIndex >= RarityConfig.Index.Epic and 5 or 2.5
					emitter.Lifetime = NumberRange.new(0.8, 1.3)
					emitter.Speed = NumberRange.new(1.5, 3)
					emitter.SpreadAngle = Vector2.new(25, 25)
					emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.4), NumberSequenceKeypoint.new(1, 0) })
					emitter.Color = ColorSequence.new(color)
					emitter.LightEmission = 0.9
					emitter.EmissionDirection = Enum.NormalId.Right -- el cilindro está tumbado: +X = arriba
					emitter.Parent = ring
				end
			end
		end
	end
	table.insert(pickups, entry)
end

local function removePickup(part)
	for index = #pickups, 1, -1 do
		if pickups[index].part == part then
			table.remove(pickups, index)
			return
		end
	end
end

local function updatePickups(dt)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local cameraPos = camera.CFrame.Position
	for index = #pickups, 1, -1 do
		local entry = pickups[index]
		local part = entry.part
		if not part.Parent then
			table.remove(pickups, index)
		elseif entry.visual then
			local base = entry.base
			local visual = entry.visual
			local fall = 0
			if entry.drop > 0 then
				entry.dropElapsed += dt
				local a = math.clamp(entry.dropElapsed / DROP_TIME, 0, 1)
				fall = entry.drop * (1 - a * a) -- acelera al caer
				if a >= 1 then
					entry.drop = 0
				end
			end
			-- Aparición: crece con un pequeño rebote.
			if entry.appear < 1 then
				entry.appear = math.min(1, entry.appear + dt / APPEAR_TIME)
				local a = entry.appear
				visual:setScale(math.max(0.05, a + math.sin(a * math.pi) * 0.18))
			end
			if fall > 0 or entry.appear < 1 or (base.Position - cameraPos).Magnitude <= ANIM_DISTANCE then
				local t = clock + entry.phase
				-- Flota y gira despacio (un giro completo cada ~9 s).
				visual.root.CFrame = base * CFrame.new(0, entry.lift + fall + math.sin(t * 1.8) * 0.18, 0) * CFrame.Angles(0, t * 0.7, 0)
			end
		end
	end
end

---------------------------------------------------------------------------------------------
-- Línea-guía (tutorial y entrega de cajas)
---------------------------------------------------------------------------------------------
local guide = { target = nil, color = nil, part = nil, beam = nil, a0 = nil, a1 = nil, root = nil }

local function localRoot()
	local player = Players.LocalPlayer
	local character = player and player.Character
	return character and character:FindFirstChild("HumanoidRootPart") or nil
end

local function destroyGuide()
	for _, key in ipairs({ "beam", "a0", "part" }) do
		if guide[key] then
			guide[key]:Destroy()
			guide[key] = nil
		end
	end
	guide.a1 = nil
	guide.root = nil
end

function WorldController.guideTo(position, color)
	if position == nil then
		guide.target = nil
		destroyGuide()
		return
	end
	guide.target = position
	guide.color = color or Color3.fromRGB(255, 214, 90)
	if guide.part then
		guide.part.CFrame = CFrame.new(position)
		guide.beam.Color = ColorSequence.new(guide.color)
	end
end

local function updateGuide()
	if not guide.target then
		return
	end
	local root = localRoot()
	if not root then
		destroyGuide()
		return
	end
	if guide.root ~= root or not guide.part then
		destroyGuide()
		local part = Instance.new("Part")
		part.Name = "FTB_GuideTarget"
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Transparency = 1
		part.Size = Vector3.new(0.2, 0.2, 0.2)
		part.CFrame = CFrame.new(guide.target)
		local a1 = Instance.new("Attachment")
		a1.Parent = part
		local a0 = Instance.new("Attachment")
		a0.Name = "FTB_GuideOrigin"
		a0.CFrame = CFrame.new(0, -2.6, 0)
		a0.Parent = root
		local beam = Instance.new("Beam")
		beam.Name = "FTB_Guide"
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.FaceCamera = true
		beam.Width0 = 0.7
		beam.Width1 = 0.7
		beam.Segments = 1
		beam.LightEmission = 0.6
		beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.85), NumberSequenceKeypoint.new(0.25, 0.35), NumberSequenceKeypoint.new(1, 0.2) })
		beam.Color = ColorSequence.new(guide.color)
		beam.Parent = part
		part.Parent = workspace
		guide.part, guide.beam, guide.a0, guide.a1, guide.root = part, beam, a0, a1, root
	end
end

---------------------------------------------------------------------------------------------
-- Cajas
---------------------------------------------------------------------------------------------
local crates = {} -- lista de { id, part, tier, text, beacon, prompt, connections }
local carried = nil

local function findCrate(id)
	for index, entry in ipairs(crates) do
		if entry.id == id then
			return entry, index
		end
	end
	return nil, nil
end

local function refreshCarried()
	local mine = nil
	for _, entry in ipairs(crates) do
		if entry.part.Parent and entry.part:GetAttribute(CA.Carrier) == localUserId then
			mine = { id = entry.id, tier = entry.tier }
		end
	end
	local changed = (mine and mine.id) ~= (carried and carried.id)
	carried = mine
	if changed then
		WorldController.CarryChanged:Fire(carried)
	end
end

local function refreshCrate(entry)
	local part = entry.part
	local state = part:GetAttribute(CA.State)
	local carrier = part:GetAttribute(CA.Carrier) or 0
	local tier = TheftConfig.Tiers[entry.tier]
	local text
	if state == "AVAILABLE" then
		text = "GRAB ME!"
	elseif carrier == localUserId then
		text = state == "PROTECTED" and "🛡️ SAFE" or (state == "BEING_STOLEN" and "⚠️ RUN!" or "TAKE IT HOME")
	elseif state == "PROTECTED" then
		text = "🛡️ SHIELDED"
	else
		text = "STEAL IT!"
	end
	entry.title.Text = tier and string.upper(tier.name) or "CRATE"
	entry.title.TextColor3 = tier and tier.color or WHITE
	entry.text.Text = text
	entry.beacon.Transparency = state == "AVAILABLE" and 0.55 or 1
	-- El prompt de robo lo crea el servidor para todos; en la propia caja no tiene sentido.
	if entry.prompt and carrier == localUserId and entry.prompt.Enabled then
		entry.prompt.Enabled = false
	end
	refreshCarried()
end

local function addCrate(part)
	if not part:IsA("BasePart") then
		return
	end
	local id = part:GetAttribute(CA.Id)
	if id == nil or findCrate(id) then
		return
	end
	local gui = billboard(part, "CrateLabel", UDim2.fromScale(7, 2.2), Vector3.new(0, 3.2, 0), 140, false)
	local entry = {
		id = id,
		part = part,
		tier = part:GetAttribute(CA.Tier),
		title = label(gui, { name = "Title", size = UDim2.fromScale(1, 0.5) }),
		text = label(gui, { name = "State", size = UDim2.fromScale(1, 0.5), position = UDim2.fromScale(0, 0.5), font = BODY }),
		connections = {},
	}
	-- Columna de luz para localizar desde lejos las cajas que están en el suelo.
	local beacon = Instance.new("Part")
	beacon.Name = "CrateBeacon"
	beacon.Shape = Enum.PartType.Cylinder
	beacon.Anchored = true
	beacon.CanCollide = false
	beacon.CanTouch = false
	beacon.CanQuery = false
	beacon.CastShadow = false
	beacon.Material = Enum.Material.Neon
	beacon.Color = part.Color
	beacon.Size = Vector3.new(44, 1.1, 1.1)
	beacon.Transparency = 1
	beacon.Parent = part
	entry.beacon = beacon

	whenChild(part, "StealPrompt", function(prompt)
		entry.prompt = prompt
		table.insert(entry.connections, prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
			if prompt.Enabled and part:GetAttribute(CA.Carrier) == localUserId then
				prompt.Enabled = false
			end
		end))
		refreshCrate(entry)
	end)
	table.insert(entry.connections, part:GetAttributeChangedSignal(CA.State):Connect(function()
		refreshCrate(entry)
	end))
	table.insert(entry.connections, part:GetAttributeChangedSignal(CA.Carrier):Connect(function()
		refreshCrate(entry)
	end))
	table.insert(crates, entry)
	refreshCrate(entry)
end

local function removeCrate(part)
	for index = #crates, 1, -1 do
		local entry = crates[index]
		if entry.part == part then
			for _, connection in ipairs(entry.connections) do
				connection:Disconnect()
			end
			table.remove(crates, index)
		end
	end
	refreshCarried()
end

local function updateCrates()
	for _, entry in ipairs(crates) do
		if entry.part.Parent and entry.beacon.Transparency < 1 then
			local position = entry.part.CFrame.Position
			entry.beacon.CFrame = CFrame.new(position + Vector3.new(0, 22, 0)) * CFrame.Angles(0, 0, math.rad(90))
		end
	end
end

function WorldController.carried()
	return carried
end

---------------------------------------------------------------------------------------------
-- Parcelas
---------------------------------------------------------------------------------------------
local plots = {} -- lista de { index, model, ... }

local function findPlot(index)
	for _, entry in ipairs(plots) do
		if entry.index == index then
			return entry
		end
	end
	return nil
end

local function signGui(part, face)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui" .. face.Name
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.Parent = part
	local text = label(gui, { text = "" })
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.06, 0)
	padding.PaddingRight = UDim.new(0.06, 0)
	padding.PaddingTop = UDim.new(0.1, 0)
	padding.PaddingBottom = UDim.new(0.1, 0)
	padding.Parent = text
	return text
end

local function refreshPlot(entry)
	local model = entry.model
	local owner = model:GetAttribute(LA.Owner) or 0
	local ownerName = model:GetAttribute(LA.OwnerName) or ""
	local isOwn = owner ~= 0 and owner == localUserId
	entry.isOwn = isOwn
	entry.owner = owner

	local signText = owner == 0 and "EMPTY PLOT" or (isOwn and "YOUR PLOT" or ownerName)
	for _, text in ipairs(entry.signLabels) do
		text.Text = signText
	end

	local income = model:GetAttribute(LA.Income) or 0
	local pending = model:GetAttribute(LA.Pending) or 0
	local cap = model:GetAttribute(LA.PendingCap) or 0
	if entry.collectGui then
		entry.collectGui.Enabled = owner ~= 0
		if isOwn then
			local full = cap > 0 and pending >= cap
			entry.collectTitle.Text = full and "💰 FULL! COLLECT" or ("💰 " .. Utilities.formatNumber(pending))
			entry.collectTitle.TextColor3 = full and Color3.fromRGB(255, 120, 90) or Color3.fromRGB(255, 214, 90)
			entry.collectInfo.Text = string.format("+%s/s  ·  step here to collect", Utilities.formatNumber(income))
		else
			entry.collectTitle.Text = "💰 " .. Utilities.formatNumber(pending)
			entry.collectTitle.TextColor3 = Color3.fromRGB(255, 214, 90)
			entry.collectInfo.Text = string.format("+%s/s", Utilities.formatNumber(income))
		end
	end
	if entry.deliveryGui then
		entry.deliveryGui.Enabled = isOwn
	end
	if entry.homeGui then
		entry.homeGui.Enabled = isOwn
	end

	-- Cosmético: borde brillante (solo partículas en las balizas; no cambia nada jugable).
	local aura = model:GetAttribute(LA.Aura) == true and owner ~= 0
	if aura ~= entry.aura then
		entry.aura = aura
		for _, emitter in ipairs(entry.auraEmitters) do
			emitter:Destroy()
		end
		entry.auraEmitters = {}
		if aura then
			for _, child in ipairs(model:GetChildren()) do
				if child.Name == "Beacon" and child:IsA("BasePart") then
					local emitter = Instance.new("ParticleEmitter")
					emitter.Name = "PlotAura"
					emitter.Texture = VFXConfig.Textures.Sparkle
					emitter.Rate = 6
					emitter.Lifetime = NumberRange.new(1.2, 1.8)
					emitter.Speed = NumberRange.new(1, 2.5)
					emitter.SpreadAngle = Vector2.new(180, 180)
					emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.7), NumberSequenceKeypoint.new(1, 0) })
					emitter.Color = ColorSequence.new(child.Color, WHITE)
					emitter.LightEmission = 1
					emitter.Parent = child
					table.insert(entry.auraEmitters, emitter)
				end
			end
		end
	end
end

local function addPlot(model)
	if not model:IsA("Model") then
		return
	end
	local index = model:GetAttribute(LA.Index)
	if index == nil or findPlot(index) then
		return
	end
	local entry = { index = index, model = model, signLabels = {}, auraEmitters = {}, aura = false, connections = {} }
	table.insert(plots, entry)

	whenChild(model, "Sign", function(sign)
		table.insert(entry.signLabels, signGui(sign, Enum.NormalId.Front))
		table.insert(entry.signLabels, signGui(sign, Enum.NormalId.Back))
		refreshPlot(entry)
	end)
	whenChild(model, "CollectPad", function(pad)
		entry.collectPad = pad
		local gui = billboard(pad, "CollectInfo", UDim2.fromScale(11, 3.4), Vector3.new(0, 5, 0), 90, false)
		entry.collectGui = gui
		entry.collectTitle = label(gui, { name = "Title", size = UDim2.fromScale(1, 0.58), color = Color3.fromRGB(255, 214, 90) })
		entry.collectInfo = label(gui, { name = "Info", size = UDim2.fromScale(1, 0.38), position = UDim2.fromScale(0, 0.6), font = BODY })
		refreshPlot(entry)
	end)
	whenChild(model, "DeliveryPad", function(pad)
		entry.deliveryPad = pad
		local gui = billboard(pad, "DeliveryInfo", UDim2.fromScale(11, 2.2), Vector3.new(0, 4.2, 0), 90, false)
		entry.deliveryGui = gui
		label(gui, { text = "📦 DELIVER CRATES HERE", color = Color3.fromRGB(130, 200, 255) })
		refreshPlot(entry)
	end)
	whenChild(model, "Floor", function(floor)
		entry.floor = floor
		-- Marcador visible desde la plaza para encontrar el camino a casa.
		local gui = billboard(floor, "HomeMarker", UDim2.fromOffset(170, 44), Vector3.new(0, 26, 0), 600, true)
		entry.homeGui = gui
		label(gui, { text = "▼ YOUR PLOT", scaled = false, textSize = 26, color = Color3.fromRGB(140, 255, 170) })
		refreshPlot(entry)
	end)
	for _, attr in ipairs({ LA.Owner, LA.OwnerName, LA.Income, LA.Pending, LA.PendingCap, LA.Aura }) do
		table.insert(entry.connections, model:GetAttributeChangedSignal(attr):Connect(function()
			refreshPlot(entry)
		end))
	end
	refreshPlot(entry)
end

function WorldController.ownPlot()
	for _, entry in ipairs(plots) do
		if entry.isOwn and entry.model.Parent then
			return {
				index = entry.index,
				model = entry.model,
				collectPos = entry.collectPad and entry.collectPad.CFrame.Position or nil,
				deliveryPos = entry.deliveryPad and entry.deliveryPad.CFrame.Position or nil,
				center = entry.floor and entry.floor.CFrame.Position or nil,
			}
		end
	end
	return nil
end

local homeTimer = 0
local function updateHomeMarker(dt)
	homeTimer += dt
	if homeTimer < 0.4 then
		return
	end
	homeTimer = 0
	local root = localRoot()
	for _, entry in ipairs(plots) do
		if entry.isOwn and entry.homeGui and entry.floor then
			-- Dentro de la propia parcela el marcador sobra.
			local inside = root ~= nil and (root.CFrame.Position - entry.floor.CFrame.Position).Magnitude < 45
			entry.homeGui.Enabled = not inside
		end
	end
end

---------------------------------------------------------------------------------------------
-- Kioscos
---------------------------------------------------------------------------------------------
local kiosks = {} -- lista de ids ya preparados

local function addKiosk(model)
	if not model:IsA("Model") then
		return
	end
	local id = model:GetAttribute("Kiosk")
	if id == nil or table.find(kiosks, id) then
		return
	end
	table.insert(kiosks, id)
	local text = model:GetAttribute("Label") or string.upper(id)
	whenChild(model, "Sign", function(sign)
		for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
			signGui(sign, face).Text = text
		end
	end)
	whenChild(model, "Counter", function(counter)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "KioskPrompt"
		prompt.ActionText = "Open"
		prompt.ObjectText = text
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.Parent = counter
		prompt.Triggered:Connect(function()
			WorldController.KioskOpened:Fire(id)
		end)
	end)
end

---------------------------------------------------------------------------------------------
-- Ciclo de vida
---------------------------------------------------------------------------------------------
local function watch(tag, onAdded, onRemoved)
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance)
		-- Los atributos pueden llegar un instante después que la instancia.
		task.defer(onAdded, instance)
	end)
	if onRemoved then
		CollectionService:GetInstanceRemovedSignal(tag):Connect(onRemoved)
	end
	for _, instance in ipairs(CollectionService:GetTagged(tag)) do
		onAdded(instance)
	end
end

function WorldController.Init(allControllers)
	controllers = allControllers
	StateController = controllers.StateController
	SettingsController = controllers.SettingsController
	localUserId = StateController.localUserId()
end

function WorldController.Start()
	watch(Constants.Tags.Pickup, addPickup, removePickup)
	watch(Constants.Tags.Crate, addCrate, removeCrate)
	watch(Constants.Tags.Plot, addPlot, nil)
	watch(Constants.Tags.Kiosk, addKiosk, nil)
end

function WorldController.Update(dt)
	clock += dt
	updatePickups(dt)
	updateCrates()
	updateGuide()
	updateHomeMarker(dt)
end

-- Diagnóstico (lo usan los tests).
function WorldController.stats()
	return { pickups = #pickups, crates = #crates, plots = #plots, kiosks = #kiosks, guide = guide.part ~= nil }
end

return WorldController
