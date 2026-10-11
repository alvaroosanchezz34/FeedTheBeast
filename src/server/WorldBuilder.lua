-- Construye el mapa por código (no hay archivo de lugar con geometría): suelo, plaza central,
-- zona de comida, pedestal de eventos, 8 parcelas equidistantes, caminos, kioscos y límites.
-- La geometría sale de Logic/PlotLayout (pura y testeada) para que no haya solapes.
--
-- WorldBuilder.build() -> world = { folder, plots = { [i] = plotInfo }, kiosks, pedestalTop, lobbySpawn }
local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Constants = require(Shared.Constants)
local PlotLayout = require(Shared.Logic.PlotLayout)

local WorldBuilder = {}

local W = GameConfig.World

WorldBuilder.PLOT_TOP = 0.3 -- altura de la superficie de las parcelas
WorldBuilder.SLOT_TOP = 0.5 -- altura de los pedestales de criatura
WorldBuilder.PLAZA_TOP = 0.2

WorldBuilder.PlotColors = {
	Color3.fromRGB(255, 92, 92),
	Color3.fromRGB(255, 160, 60),
	Color3.fromRGB(250, 220, 70),
	Color3.fromRGB(110, 214, 100),
	Color3.fromRGB(70, 200, 220),
	Color3.fromRGB(90, 130, 255),
	Color3.fromRGB(170, 100, 255),
	Color3.fromRGB(255, 110, 200),
}

WorldBuilder.Kiosks = {
	{ id = "Shop", label = "SHOP", color = Color3.fromRGB(255, 170, 60) },
	{ id = "Collection", label = "COLLECTION", color = Color3.fromRGB(90, 200, 255) },
	{ id = "Upgrades", label = "UPGRADES", color = Color3.fromRGB(120, 220, 110) },
	{ id = "Rebirth", label = "REBIRTH", color = Color3.fromRGB(255, 100, 180) },
}

local function part(props)
	local p = Instance.new(props.className or "Part")
	p.Name = props.name or "Part"
	p.Anchored = true
	p.Size = props.size
	p.CFrame = props.cf
	p.Color = props.color or Color3.fromRGB(200, 200, 200)
	p.Material = props.material or Enum.Material.SmoothPlastic
	p.Transparency = props.transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props.shape then
		p.Shape = props.shape
	end
	if props.canCollide == false then
		p.CanCollide = false
	end
	if props.canTouch == false then
		p.CanTouch = false
	end
	if props.canQuery == false then
		p.CanQuery = false
	end
	if props.castShadow == false then
		p.CastShadow = false
	end
	p.Parent = props.parent
	return p
end

-- Disco horizontal (cilindro con el eje en Y) con la cara superior en `top`.
local function disc(name, diameter, height, x, top, z, color, material, parent)
	return part({
		name = name,
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(height, diameter, diameter),
		cf = CFrame.new(x, top - height / 2, z) * CFrame.Angles(0, 0, math.rad(90)),
		color = color,
		material = material,
		parent = parent,
	})
end

local function buildGround(folder)
	local size = W.GroundSize
	part({ name = "Ground", size = Vector3.new(size, 4, size), cf = CFrame.new(0, -2, 0), color = Color3.fromRGB(106, 176, 92), material = Enum.Material.Grass, parent = folder })
	-- Muros invisibles en el borde.
	local half = size / 2
	for i, def in ipairs({
		{ Vector3.new(size, 80, 2), CFrame.new(0, 40, half) },
		{ Vector3.new(size, 80, 2), CFrame.new(0, 40, -half) },
		{ Vector3.new(2, 80, size), CFrame.new(half, 40, 0) },
		{ Vector3.new(2, 80, size), CFrame.new(-half, 40, 0) },
	}) do
		part({ name = "Boundary" .. i, size = def[1], cf = def[2], transparency = 1, castShadow = false, canQuery = false, parent = folder })
	end
end

local function buildPlaza(folder)
	disc("Plaza", W.PlazaRadius * 2, 0.4, 0, WorldBuilder.PLAZA_TOP, 0, Color3.fromRGB(226, 208, 170), Enum.Material.Cobblestone, folder)
	disc("FoodField", (W.FoodRingOuter + 3) * 2, 0.4, 0, WorldBuilder.PLAZA_TOP + 0.06, 0, Color3.fromRGB(150, 208, 120), Enum.Material.Grass, folder)
	disc("EventPedestal", W.PedestalRadius * 2, 1.2, 0, 1.2, 0, Color3.fromRGB(120, 110, 140), Enum.Material.Slate, folder)
	disc("EventPedestalRim", W.PedestalRadius * 2 + 2, 0.5, 0, 0.75, 0, Color3.fromRGB(255, 196, 70), Enum.Material.Metal, folder)

	local lobby = Instance.new("SpawnLocation")
	lobby.Name = "LobbySpawn"
	lobby.Anchored = true
	lobby.Neutral = true
	lobby.Duration = 0
	lobby.Size = Vector3.new(10, 0.6, 10)
	lobby.CFrame = CFrame.new(0, WorldBuilder.PLAZA_TOP + 0.2, 64)
	lobby.Color = Color3.fromRGB(240, 240, 250)
	lobby.Material = Enum.Material.Marble
	lobby.TopSurface = Enum.SurfaceType.Smooth
	lobby.Parent = folder
	return lobby
end

local function buildKiosk(folder, index, def)
	local k = PlotLayout.kiosk(index)
	local base = CFrame.new(k.x, WorldBuilder.PLAZA_TOP, k.z) * CFrame.Angles(0, k.yaw, 0)
	local model = Instance.new("Model")
	model.Name = "Kiosk_" .. def.id
	local counter = part({ name = "Counter", size = Vector3.new(9, 3, 3), cf = base * CFrame.new(0, 1.5, 0), color = Color3.fromRGB(150, 104, 66), material = Enum.Material.WoodPlanks, parent = model })
	part({ name = "PostL", size = Vector3.new(0.8, 9, 0.8), cf = base * CFrame.new(-4.4, 4.5, 0), color = Color3.fromRGB(110, 76, 50), material = Enum.Material.Wood, parent = model })
	part({ name = "PostR", size = Vector3.new(0.8, 9, 0.8), cf = base * CFrame.new(4.4, 4.5, 0), color = Color3.fromRGB(110, 76, 50), material = Enum.Material.Wood, parent = model })
	part({ name = "Roof", size = Vector3.new(11, 1, 6), cf = base * CFrame.new(0, 9.4, -0.6) * CFrame.Angles(math.rad(-8), 0, 0), color = def.color, material = Enum.Material.Fabric, parent = model })
	part({ name = "Sign", size = Vector3.new(7, 2, 0.4), cf = base * CFrame.new(0, 7, -1.8), color = def.color, material = Enum.Material.Neon, parent = model })
	model.PrimaryPart = counter
	model:SetAttribute("Kiosk", def.id)
	model:SetAttribute("Label", def.label)
	model.Parent = folder
	CollectionService:AddTag(model, Constants.Tags.Kiosk)
	return model
end

local function buildPlot(plotsFolder, index)
	local layout = PlotLayout.plot(index)
	local size = W.PlotSize
	local half = size / 2
	local color = WorldBuilder.PlotColors[(index - 1) % #WorldBuilder.PlotColors + 1]
	local cf = CFrame.new(layout.x, WorldBuilder.PLOT_TOP, layout.z) * CFrame.Angles(0, layout.yaw, 0)

	local model = Instance.new("Model")
	model.Name = "Plot" .. index

	local floor = part({ name = "Floor", size = Vector3.new(size, 0.6, size), cf = cf * CFrame.new(0, -0.3, 0), color = Color3.fromRGB(128, 190, 110), material = Enum.Material.Grass, parent = model })
	model.PrimaryPart = floor

	-- Borde de color (identifica la parcela desde lejos) y vallas bajas en laterales y fondo.
	local trims = {}
	local function trim(name, sizeV, offset)
		local t = part({ name = name, size = sizeV, cf = cf * offset, color = color, material = Enum.Material.WoodPlanks, parent = model })
		table.insert(trims, t)
		return t
	end
	trim("FenceL", Vector3.new(1, 3, size), CFrame.new(-half + 0.5, 1.5, 0))
	trim("FenceR", Vector3.new(1, 3, size), CFrame.new(half - 0.5, 1.5, 0))
	trim("FenceB", Vector3.new(size, 3, 1), CFrame.new(0, 1.5, half - 0.5))
	trim("FrontL", Vector3.new(half - 9, 0.5, 1), CFrame.new(-(half + 9) / 2, 0.25, -half + 0.5))
	trim("FrontR", Vector3.new(half - 9, 0.5, 1), CFrame.new((half + 9) / 2, 0.25, -half + 0.5))

	-- Postes-baliza en las esquinas delanteras.
	local beacons = {}
	for _, sx in ipairs({ -1, 1 }) do
		part({ name = "Post", size = Vector3.new(1.4, 14, 1.4), cf = cf * CFrame.new(sx * (half - 0.7), 7, -half + 0.7), color = Color3.fromRGB(90, 70, 60), material = Enum.Material.Wood, parent = model })
		local beacon = part({ name = "Beacon", shape = Enum.PartType.Ball, size = Vector3.new(3, 3, 3), cf = cf * CFrame.new(sx * (half - 0.7), 15, -half + 0.7), color = color, material = Enum.Material.Neon, canCollide = false, parent = model })
		table.insert(beacons, beacon)
	end

	-- Cartel del propietario.
	part({ name = "SignPost", size = Vector3.new(0.6, 5, 0.6), cf = cf * CFrame.new(PlotLayout.Local.Sign.x, 2.5, PlotLayout.Local.Sign.z), color = Color3.fromRGB(90, 70, 60), material = Enum.Material.Wood, parent = model })
	local sign = part({ name = "Sign", size = Vector3.new(7, 3.2, 0.5), cf = cf * CFrame.new(PlotLayout.Local.Sign.x, 5.4, PlotLayout.Local.Sign.z), color = color, material = Enum.Material.SmoothPlastic, parent = model })

	-- Punto de aparición (decorativo; el teletransporte lo hace CharacterService).
	local spawnPad = part({ name = "SpawnPad", size = Vector3.new(8, 0.2, 8), cf = cf * CFrame.new(PlotLayout.Local.Spawn.x, 0.1, PlotLayout.Local.Spawn.z), color = Color3.fromRGB(240, 240, 250), material = Enum.Material.Marble, canCollide = false, parent = model })

	-- Pedestales de criatura.
	local slotPads, slotCFrames = {}, {}
	for slot = 1, W.MaxSlotsPerPlot do
		local s = PlotLayout.slotLocal(slot)
		local wx, wz = PlotLayout.toWorld(layout, s.x, s.z)
		local pad = disc("Slot" .. slot, 12, 0.2, wx, WorldBuilder.SLOT_TOP, wz, Color3.fromRGB(235, 235, 240), Enum.Material.Marble, model)
		pad:SetAttribute("Slot", slot)
		slotPads[slot] = pad
		slotCFrames[slot] = cf * CFrame.new(s.x, WorldBuilder.SLOT_TOP - WorldBuilder.PLOT_TOP, s.z)
	end

	-- Zonas de recogida de ganancias y de entrega de cajas.
	local function pad(name, loc, padColor)
		local wx, wz = PlotLayout.toWorld(layout, loc.x, loc.z)
		local p = disc(name, 9, 0.25, wx, WorldBuilder.PLOT_TOP + 0.25, wz, padColor, Enum.Material.Neon, model)
		p.CanCollide = false
		return p, Vector3.new(wx, WorldBuilder.PLOT_TOP + 0.25, wz)
	end
	local collectPad, collectPos = pad("CollectPad", PlotLayout.Local.CollectPad, Color3.fromRGB(255, 208, 70))
	local deliveryPad, deliveryPos = pad("DeliveryPad", PlotLayout.Local.DeliveryPad, Color3.fromRGB(90, 170, 255))

	model:SetAttribute(Constants.PlotAttr.Index, index)
	model:SetAttribute(Constants.PlotAttr.Owner, 0)
	model:SetAttribute(Constants.PlotAttr.OwnerName, "")
	model:SetAttribute(Constants.PlotAttr.Style, 0)
	model:SetAttribute(Constants.PlotAttr.Income, 0)
	model:SetAttribute(Constants.PlotAttr.Pending, 0)
	model:SetAttribute(Constants.PlotAttr.PendingCap, 0)
	model:SetAttribute(Constants.PlotAttr.Aura, false)
	model:SetAttribute("Slots", 0)
	model.Parent = plotsFolder
	CollectionService:AddTag(model, Constants.Tags.Plot)

	return {
		index = index,
		model = model,
		cframe = cf,
		color = color,
		floor = floor,
		trims = trims,
		beacons = beacons,
		sign = sign,
		spawnPad = spawnPad,
		-- Gira 180°: el frente del personaje (-Z) apunta al fondo de la parcela, donde están las criaturas.
		spawnCFrame = cf * CFrame.new(PlotLayout.Local.Spawn.x, 3.5, PlotLayout.Local.Spawn.z) * CFrame.Angles(0, math.pi, 0),
		slotPads = slotPads,
		slotCFrames = slotCFrames,
		collectPad = collectPad,
		collectPos = collectPos,
		deliveryPad = deliveryPad,
		deliveryPos = deliveryPos,
		layout = layout,
	}
end

local function buildPath(folder, index)
	local layout = PlotLayout.plot(index)
	local inner = W.PlazaRadius - 2
	local outer = W.PlotRingRadius - W.PlotSize / 2 + 2
	local mid = (inner + outer) / 2
	part({
		name = "Path" .. index,
		size = Vector3.new(16, 0.3, outer - inner),
		cf = CFrame.new(math.sin(layout.angle) * mid, 0.0, math.cos(layout.angle) * mid) * CFrame.Angles(0, layout.yaw, 0),
		color = Color3.fromRGB(222, 200, 150),
		material = Enum.Material.Sand,
		parent = folder,
	})
end

local function setupLighting()
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.28
		atmosphere.Offset = 0.2
		atmosphere.Color = Color3.fromRGB(210, 225, 255)
		atmosphere.Decay = Color3.fromRGB(120, 140, 170)
		atmosphere.Glare = 0.1
		atmosphere.Haze = 1
		atmosphere.Parent = Lighting
	end
end

function WorldBuilder.build()
	local existing = workspace:FindFirstChild(Constants.Folders.World)
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = Constants.Folders.World

	buildGround(folder)
	local lobby = buildPlaza(folder)

	local plotsFolder = Instance.new("Folder")
	plotsFolder.Name = Constants.Folders.Plots
	plotsFolder.Parent = folder

	local plots = {}
	for index = 1, GameConfig.PlotCount do
		plots[index] = buildPlot(plotsFolder, index)
		buildPath(folder, index)
	end

	local kiosks = {}
	for index, def in ipairs(WorldBuilder.Kiosks) do
		kiosks[def.id] = buildKiosk(folder, index, def)
	end

	for _, name in ipairs({ Constants.Folders.Creatures, Constants.Folders.Pickups, Constants.Folders.Crates }) do
		if not workspace:FindFirstChild(name) then
			local f = Instance.new("Folder")
			f.Name = name
			f.Parent = workspace
		end
	end

	folder.Parent = workspace
	setupLighting()

	return {
		folder = folder,
		plots = plots,
		kiosks = kiosks,
		lobbySpawn = lobby,
		pedestalTop = Vector3.new(0, 1.2, 0),
	}
end

return WorldBuilder
