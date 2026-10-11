-- Construye el mapa por código (no hay archivo de lugar con geometría): un parque de criaturas
-- con plaza central, altar de eventos, puestos temáticos, 8 parcelas valladas con entrada y
-- corrales, caminos, vegetación e iluminación. La geometría sale de Logic/PlotLayout (pura y
-- testeada) para que nada se solape.
--
-- WorldBuilder.build() -> world = { folder, plots = { [i] = plotInfo }, kiosks, pedestalTop, lobbySpawn, scenery }
local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local Constants = require(Shared.Constants)
local PlotLayout = require(Shared.Logic.PlotLayout)
local FoodModels = require(Shared.Food.FoodModels)

local Build = require(script.Parent.World.Build)
local Scenery = require(script.Parent.World.Scenery)

local WorldBuilder = {}

local W = GameConfig.World
local rgb = Color3.fromRGB
local V = Vector3.new

WorldBuilder.PLOT_TOP = 0.3 -- altura de la superficie de las parcelas
WorldBuilder.SLOT_TOP = 0.5 -- altura de los corrales
WorldBuilder.PLAZA_TOP = 0.2

WorldBuilder.PlotColors = {
	rgb(255, 92, 92),
	rgb(255, 160, 60),
	rgb(250, 220, 70),
	rgb(110, 214, 100),
	rgb(70, 200, 220),
	rgb(90, 130, 255),
	rgb(170, 100, 255),
	rgb(255, 110, 200),
}

WorldBuilder.Kiosks = {
	{ id = "Shop", label = "FOOD SHOP", color = rgb(255, 150, 60) },
	{ id = "Collection", label = "BEAST BOOK", color = rgb(90, 190, 255) },
	{ id = "Upgrades", label = "UPGRADES", color = rgb(120, 220, 110) },
	{ id = "Rebirth", label = "REBIRTH", color = rgb(255, 100, 180) },
}

local WOOD = rgb(150, 104, 66)
local WOOD_DARK = rgb(110, 76, 50)
local STONE = rgb(196, 190, 204)
local STONE_DARK = rgb(140, 134, 156)
local SAND = rgb(232, 210, 164)
local GOLD = rgb(255, 204, 70)

---------------------------------------------------------------------------------------------
-- Suelo
---------------------------------------------------------------------------------------------
local function buildGround(folder)
	local size = W.GroundSize
	Build.block({ name = "Ground", size = V(size, 4, size), cf = CFrame.new(0, -2, 0), color = rgb(112, 186, 96), material = Enum.Material.Grass, collide = true, parent = folder })
	-- Pradera exterior (no jugable): da horizonte más allá del borde.
	Build.block({ name = "Meadow", size = V(size * 4, 2, size * 4), cf = CFrame.new(0, -1.3, 0), color = rgb(100, 174, 92), material = Enum.Material.Grass, shadow = false, parent = folder })
	local half = size / 2
	for i, def in ipairs({
		{ V(size, 80, 2), CFrame.new(0, 40, half) },
		{ V(size, 80, 2), CFrame.new(0, 40, -half) },
		{ V(2, 80, size), CFrame.new(half, 40, 0) },
		{ V(2, 80, size), CFrame.new(-half, 40, 0) },
	}) do
		local wall = Build.block({ name = "Boundary" .. i, size = def[1], cf = def[2], transparency = 1, shadow = false, collide = true, parent = folder })
		wall.CanQuery = false
	end
	-- Seto bajo que marca el límite de forma visible.
	for i, def in ipairs({
		{ V(size, 5, 5), V(0, 2, half - 2.5) },
		{ V(size, 5, 5), V(0, 2, -half + 2.5) },
		{ V(5, 5, size), V(half - 2.5, 2, 0) },
		{ V(5, 5, size), V(-half + 2.5, 2, 0) },
	}) do
		Build.block({ name = "Hedge" .. i, size = def[1], cf = CFrame.new(def[2]), color = rgb(64, 150, 84), material = Enum.Material.Grass, parent = folder })
	end
end

---------------------------------------------------------------------------------------------
-- Plaza y altar de eventos
---------------------------------------------------------------------------------------------
local function buildPlaza(folder)
	local plaza = Build.folder("Plaza", folder)
	local top = WorldBuilder.PLAZA_TOP
	-- Anillos concéntricos: borde de piedra oscura, pavimento claro, cenefa y pradera de comida.
	Build.disc({ name = "PlazaRim", diameter = W.PlazaRadius * 2, height = 0.5, x = 0, top = top, z = 0, color = STONE_DARK, material = Enum.Material.Slate, collide = true, parent = plaza })
	Build.disc({ name = "Plaza", diameter = (W.PlazaRadius - 3) * 2, height = 0.5, x = 0, top = top + 0.03, z = 0, color = rgb(232, 222, 204), material = Enum.Material.Cobblestone, collide = true, shadow = false, parent = plaza })
	Build.disc({ name = "Band", diameter = (W.FoodRingOuter + 9) * 2, height = 0.5, x = 0, top = top + 0.06, z = 0, color = rgb(255, 176, 96), material = Enum.Material.SmoothPlastic, collide = true, shadow = false, parent = plaza })
	Build.disc({ name = "BandInner", diameter = (W.FoodRingOuter + 7) * 2, height = 0.5, x = 0, top = top + 0.09, z = 0, color = rgb(232, 222, 204), material = Enum.Material.Cobblestone, collide = true, shadow = false, parent = plaza })
	Build.disc({ name = "FoodField", diameter = (W.FoodRingOuter + 3) * 2, height = 0.5, x = 0, top = top + 0.12, z = 0, color = rgb(150, 212, 120), material = Enum.Material.Grass, collide = true, shadow = false, parent = plaza })
	-- Altar: dos escalones de piedra con aro dorado y cuatro columnas con brasero.
	Build.disc({ name = "AltarStep", diameter = W.PedestalRadius * 2 + 5, height = 0.6, x = 0, top = 0.7, z = 0, color = STONE_DARK, material = Enum.Material.Slate, collide = true, parent = plaza })
	Build.disc({ name = "EventPedestalRim", diameter = W.PedestalRadius * 2 + 1.5, height = 0.5, x = 0, top = 1.0, z = 0, color = GOLD, material = Enum.Material.Metal, collide = true, parent = plaza })
	Build.disc({ name = "EventPedestal", diameter = W.PedestalRadius * 2, height = 0.6, x = 0, top = 1.2, z = 0, color = rgb(126, 114, 150), material = Enum.Material.Slate, collide = true, parent = plaza })
	for i = 1, 4 do
		local angle = (i - 0.5) / 4 * math.pi * 2
		local x, z = math.cos(angle) * 15, math.sin(angle) * 15
		Build.cyl({ name = "PillarBase", diameter = 3, height = 1, position = V(x, 0.9, z), color = STONE_DARK, material = Enum.Material.Slate, collide = true, parent = plaza })
		Build.cyl({ name = "Pillar", diameter = 2, height = 9, position = V(x, 5.6, z), color = STONE, material = Enum.Material.Marble, collide = true, parent = plaza })
		Build.blob({ name = "Bowl", size = V(3.6, 1.6, 3.6), cf = CFrame.new(x, 10.6, z), color = GOLD, material = Enum.Material.Metal, reflectance = 0.2, parent = plaza })
		local flame = Build.blob({ name = "Flame", size = V(1.8, 2.8, 1.8), cf = CFrame.new(x, 12.1, z), color = rgb(255, 150, 60), material = Enum.Material.Neon, shadow = false, parent = plaza })
		local light = Instance.new("PointLight")
		light.Color = rgb(255, 180, 110)
		light.Brightness = 0.7
		light.Range = 22
		light.Shadows = false
		light.Parent = flame
	end
	-- Flores alrededor de la pradera (planas, no estorban).
	for i = 1, 16 do
		local angle = i / 16 * math.pi * 2
		local r = W.FoodRingOuter + 5
		Build.blob({ name = "Petal", size = V(1.6, 0.4, 1.6), cf = CFrame.new(math.cos(angle) * r, top + 0.25, math.sin(angle) * r), color = (i % 2 == 0) and rgb(255, 120, 170) or rgb(255, 220, 90), shadow = false, parent = plaza })
	end
	-- Farolas en el borde de la plaza, entre caminos.
	for i = 1, GameConfig.PlotCount do
		local angle = (i - 0.5) / GameConfig.PlotCount * math.pi * 2
		local r = W.PlazaRadius - 5
		local x, z = math.sin(angle) * r, math.cos(angle) * r
		Build.cyl({ name = "LampPost", diameter = 0.7, height = 11, position = V(x, 5.7, z), color = rgb(60, 62, 84), material = Enum.Material.Metal, collide = true, parent = plaza })
		Build.blob({ name = "LampCap", size = V(2.6, 0.8, 2.6), cf = CFrame.new(x, 11.9, z), color = rgb(60, 62, 84), material = Enum.Material.Metal, parent = plaza })
		local globe = Build.blob({ name = "LampGlobe", size = V(1.8, 1.8, 1.8), cf = CFrame.new(x, 10.9, z), color = rgb(255, 236, 170), material = Enum.Material.Neon, shadow = false, parent = plaza })
		if i % 2 == 0 then
			local light = Instance.new("PointLight")
			light.Color = rgb(255, 230, 170)
			light.Brightness = 0.6
			light.Range = 24
			light.Shadows = false
			light.Parent = globe
		end
	end

	local lobby = Instance.new("SpawnLocation")
	lobby.Name = "LobbySpawn"
	lobby.Anchored = true
	lobby.Neutral = true
	lobby.Duration = 0
	lobby.Size = V(10, 0.4, 10)
	lobby.CFrame = CFrame.new(0, top + 0.25, 64)
	lobby.Color = rgb(240, 240, 250)
	lobby.Material = Enum.Material.Marble
	lobby.TopSurface = Enum.SurfaceType.Smooth
	lobby.Parent = plaza
	return lobby
end

---------------------------------------------------------------------------------------------
-- Puestos (tiendas físicas). Cada uno lleva en el tejado un objeto que lo identifica de lejos.
---------------------------------------------------------------------------------------------
local function landmark(model, base, def)
	local top = base * CFrame.new(0, 13.2, 0.5)
	if def.id == "Shop" then
		-- Una hamburguesa gigante: el mismo modelo que la comida del juego.
		local visual = FoodModels.build("BURGER")
		if visual then
			visual:setScale(2.6)
			visual.root.CFrame = top * CFrame.new(0, -1.4, 0)
			visual.model.Name = "Landmark"
			visual.model.Parent = model
		end
	elseif def.id == "Collection" then
		for _, sx in ipairs({ -1, 1 }) do
			Build.block({ name = "Cover", size = V(4.6, 0.5, 6), cf = top * CFrame.new(sx * 2.3, 0.6, 0) * CFrame.Angles(0, 0, math.rad(sx * 16)), color = def.color, parent = model })
			Build.block({ name = "Pages", size = V(4.2, 0.6, 5.5), cf = top * CFrame.new(sx * 2.2, 1.1, 0) * CFrame.Angles(0, 0, math.rad(sx * 16)), color = rgb(255, 250, 236), parent = model })
		end
		Build.blob({ name = "Paw", size = V(1.6, 0.4, 1.6), cf = top * CFrame.new(2.2, 1.9, 0) * CFrame.Angles(0, 0, math.rad(16)), color = def.color, shadow = false, parent = model })
	elseif def.id == "Upgrades" then
		Build.block({ name = "ArrowStem", size = V(2.2, 4, 1.4), cf = top * CFrame.new(0, 1.2, 0), color = def.color, parent = model })
		for _, sx in ipairs({ -1, 1 }) do
			Build.wedge({ name = "ArrowHead", size = V(1.4, 3.2, 2.8), cf = top * CFrame.new(sx * 1.4, 4.8, 0) * CFrame.Angles(0, math.rad(sx * 90), 0), color = def.color, parent = model })
		end
	else
		Build.blob({ name = "Egg", size = V(4.4, 5.6, 4.4), cf = top * CFrame.new(0, 2.4, 0), color = rgb(255, 236, 214), parent = model })
		for i = 1, 3 do
			local a = i / 3 * math.pi * 2
			Build.blob({ name = "Flame", size = V(1.6, 3.4, 1.6), cf = top * CFrame.new(math.cos(a) * 1.9, 1.2, math.sin(a) * 1.9), color = (i % 2 == 0) and rgb(255, 150, 60) or def.color, material = Enum.Material.Neon, shadow = false, parent = model })
		end
	end
end

local function buildKiosk(folder, index, def)
	local k = PlotLayout.kiosk(index)
	local base = CFrame.new(k.x, WorldBuilder.PLAZA_TOP, k.z) * CFrame.Angles(0, k.yaw, 0)
	local model = Instance.new("Model")
	model.Name = "Kiosk_" .. def.id
	Build.block({ name = "Floor", size = V(13, 0.3, 8), cf = base * CFrame.new(0, 0.15, 0.5), color = WOOD_DARK, material = Enum.Material.WoodPlanks, collide = true, parent = model })
	local counter = Build.block({ name = "Counter", size = V(10, 3, 2.6), cf = base * CFrame.new(0, 1.8, -1.2), color = WOOD, material = Enum.Material.WoodPlanks, collide = true, parent = model })
	Build.block({ name = "CounterTop", size = V(10.8, 0.4, 3.2), cf = base * CFrame.new(0, 3.5, -1.2), color = rgb(250, 240, 220), material = Enum.Material.Marble, collide = true, parent = model })
	Build.block({ name = "BackWall", size = V(11, 9, 0.6), cf = base * CFrame.new(0, 4.8, 3.6), color = rgb(250, 240, 220), material = Enum.Material.SmoothPlastic, collide = true, parent = model })
	for _, sx in ipairs({ -1, 1 }) do
		Build.cyl({ name = "Post", diameter = 0.8, height = 10, position = (base * CFrame.new(sx * 5.4, 5, -2.2)).Position, color = WOOD_DARK, material = Enum.Material.Wood, collide = true, parent = model })
		Build.blob({ name = "Lantern", size = V(1.1, 1.4, 1.1), cf = base * CFrame.new(sx * 5.4, 7.4, -3.0), color = rgb(255, 236, 170), material = Enum.Material.Neon, shadow = false, parent = model })
	end
	-- Toldo a rayas.
	for i = 0, 6 do
		Build.block({ name = "Awning" .. i, size = V(1.72, 0.5, 7.4), cf = base * CFrame.new(-5.16 + i * 1.72, 10.3, 0.2) * CFrame.Angles(math.rad(-12), 0, 0), color = (i % 2 == 0) and def.color or rgb(255, 255, 255), material = Enum.Material.Fabric, parent = model })
	end
	Build.block({ name = "SignFrame", size = V(8.6, 2.8, 0.4), cf = base * CFrame.new(0, 8.3, -2.95), color = WOOD_DARK, material = Enum.Material.Wood, parent = model })
	Build.block({ name = "Sign", size = V(8, 2.2, 0.5), cf = base * CFrame.new(0, 8.3, -3.0), color = def.color, material = Enum.Material.SmoothPlastic, parent = model })
	landmark(model, base, def)
	model.PrimaryPart = counter
	model:SetAttribute("Kiosk", def.id)
	model:SetAttribute("Label", def.label)
	model.Parent = folder
	CollectionService:AddTag(model, Constants.Tags.Kiosk)
	return model
end

---------------------------------------------------------------------------------------------
-- Parcelas
---------------------------------------------------------------------------------------------
local DECOR_LEVELS = 4

local function buildPlot(plotsFolder, index)
	local layout = PlotLayout.plot(index)
	local size = W.PlotSize
	local half = size / 2
	local color = WorldBuilder.PlotColors[(index - 1) % #WorldBuilder.PlotColors + 1]
	local cf = CFrame.new(layout.x, WorldBuilder.PLOT_TOP, layout.z) * CFrame.Angles(0, layout.yaw, 0)

	local model = Instance.new("Model")
	model.Name = "Plot" .. index

	local floor = Build.block({ name = "Floor", size = V(size, 0.6, size), cf = cf * CFrame.new(0, -0.3, 0), color = rgb(128, 190, 110), material = Enum.Material.Grass, collide = true, parent = model })
	model.PrimaryPart = floor
	-- Patio interior y sendero de entrada.
	Build.block({ name = "Yard", size = V(size - 10, 0.1, 36), cf = cf * CFrame.new(0, 0.05, 10), color = rgb(214, 190, 150), material = Enum.Material.Ground, shadow = false, parent = model })
	Build.block({ name = "Walk", size = V(14, 0.1, 22), cf = cf * CFrame.new(0, 0.05, -17), color = SAND, material = Enum.Material.Sand, shadow = false, parent = model })

	-- Valla: postes y dos travesaños en laterales y fondo; la entrada queda abierta.
	local trims = {}
	local function rail(name, sizeV, offset)
		local t = Build.block({ name = name, size = sizeV, cf = cf * offset, color = color, material = Enum.Material.WoodPlanks, collide = true, parent = model })
		table.insert(trims, t)
		return t
	end
	rail("FenceL", V(0.5, 0.7, size), CFrame.new(-half + 0.5, 2.6, 0))
	rail("FenceR", V(0.5, 0.7, size), CFrame.new(half - 0.5, 2.6, 0))
	rail("FenceB", V(size, 0.7, 0.5), CFrame.new(0, 2.6, half - 0.5))
	rail("FenceL2", V(0.5, 0.7, size), CFrame.new(-half + 0.5, 1.2, 0))
	rail("FenceR2", V(0.5, 0.7, size), CFrame.new(half - 0.5, 1.2, 0))
	rail("FenceB2", V(size, 0.7, 0.5), CFrame.new(0, 1.2, half - 0.5))
	rail("FrontL", V(half - 9, 0.7, 0.5), CFrame.new(-(half + 9) / 2, 1.2, -half + 0.5))
	rail("FrontR", V(half - 9, 0.7, 0.5), CFrame.new((half + 9) / 2, 1.2, -half + 0.5))
	-- Pared invisible baja para que la valla (dos travesaños) se comporte como una barrera.
	for _, def in ipairs({
		{ V(0.6, 3.4, size), CFrame.new(-half + 0.5, 1.7, 0) },
		{ V(0.6, 3.4, size), CFrame.new(half - 0.5, 1.7, 0) },
		{ V(size, 3.4, 0.6), CFrame.new(0, 1.7, half - 0.5) },
	}) do
		Build.block({ name = "FenceBlock", size = def[1], cf = cf * def[2], transparency = 1, shadow = false, collide = true, parent = model })
	end
	for i = 0, 7 do
		local z = -half + 0.5 + i * (size - 1) / 7
		for _, sx in ipairs({ -1, 1 }) do
			Build.cyl({ name = "FencePost", diameter = 0.9, height = 3.8, position = (cf * CFrame.new(sx * (half - 0.5), 1.9, z)).Position, color = WOOD_DARK, material = Enum.Material.Wood, parent = model })
		end
		if i > 0 and i < 7 then
			Build.cyl({ name = "FencePost", diameter = 0.9, height = 3.8, position = (cf * CFrame.new(-half + 0.5 + i * (size - 1) / 7, 1.9, half - 0.5)).Position, color = WOOD_DARK, material = Enum.Material.Wood, parent = model })
		end
	end

	-- Entrada: arco con el cartel del propietario y dos balizas del color de la parcela.
	local beacons = {}
	for _, sx in ipairs({ -1, 1 }) do
		Build.cyl({ name = "GatePost", diameter = 1.8, height = 12, position = (cf * CFrame.new(sx * 9, 6, -half + 0.6)).Position, color = WOOD_DARK, material = Enum.Material.Wood, collide = true, parent = model })
		local beacon = Build.blob({ name = "Beacon", size = V(3, 3, 3), cf = cf * CFrame.new(sx * 9, 13.4, -half + 0.6), color = color, material = Enum.Material.Neon, shadow = false, parent = model })
		table.insert(beacons, beacon)
	end
	Build.block({ name = "GateBeam", size = V(20, 1.4, 1.4), cf = cf * CFrame.new(0, 11.4, -half + 0.6), color = WOOD, material = Enum.Material.Wood, parent = model })
	local sign = Build.block({ name = "Sign", size = V(13, 3.4, 0.6), cf = cf * CFrame.new(PlotLayout.Local.Sign.x, 9.0, PlotLayout.Local.Sign.z), color = color, material = Enum.Material.SmoothPlastic, parent = model })

	local spawnPad = Build.block({ name = "SpawnPad", size = V(8, 0.2, 8), cf = cf * CFrame.new(PlotLayout.Local.Spawn.x, 0.14, PlotLayout.Local.Spawn.z), color = rgb(240, 240, 250), material = Enum.Material.Marble, shadow = false, parent = model })

	-- Corrales: un lecho de paja con borde y cuatro estacas (decorativas, no bloquean).
	local slotPads, slotCFrames = {}, {}
	for slot = 1, W.MaxSlotsPerPlot do
		local s = PlotLayout.slotLocal(slot)
		local wx, wz = PlotLayout.toWorld(layout, s.x, s.z)
		Build.disc({ name = "PenRim" .. slot, diameter = 13.6, height = 0.2, x = wx, top = WorldBuilder.SLOT_TOP - 0.04, z = wz, color = WOOD_DARK, material = Enum.Material.Wood, shadow = false, parent = model })
		local pad = Build.disc({ name = "Slot" .. slot, diameter = 12, height = 0.2, x = wx, top = WorldBuilder.SLOT_TOP, z = wz, color = rgb(236, 214, 150), material = Enum.Material.Sand, collide = true, shadow = false, parent = model })
		pad:SetAttribute("Slot", slot)
		slotPads[slot] = pad
		slotCFrames[slot] = cf * CFrame.new(s.x, WorldBuilder.SLOT_TOP - WorldBuilder.PLOT_TOP, s.z)
		for i = 1, 4 do
			local a = (i - 0.5) / 4 * math.pi * 2
			Build.cyl({ name = "PenStake", diameter = 0.6, height = 1.4, position = V(wx + math.cos(a) * 6.5, WorldBuilder.PLOT_TOP + 0.7, wz + math.sin(a) * 6.5), color = WOOD, material = Enum.Material.Wood, shadow = false, parent = model })
		end
	end

	-- Zonas de recogida de ganancias (oro, con cofre) y de entrega de cajas (azul).
	local function pad(name, loc, padColor)
		local wx, wz = PlotLayout.toWorld(layout, loc.x, loc.z)
		Build.disc({ name = name .. "Rim", diameter = 10, height = 0.25, x = wx, top = WorldBuilder.PLOT_TOP + 0.2, z = wz, color = rgb(60, 62, 84), material = Enum.Material.Metal, shadow = false, parent = model })
		local p = Build.disc({ name = name, diameter = 9, height = 0.25, x = wx, top = WorldBuilder.PLOT_TOP + 0.25, z = wz, color = padColor, material = Enum.Material.Neon, shadow = false, parent = model })
		return p, V(wx, WorldBuilder.PLOT_TOP + 0.25, wz)
	end
	local collectPad, collectPos = pad("CollectPad", PlotLayout.Local.CollectPad, rgb(255, 208, 70))
	local deliveryPad, deliveryPos = pad("DeliveryPad", PlotLayout.Local.DeliveryPad, rgb(90, 170, 255))
	local chestAt = cf * CFrame.new(PlotLayout.Local.CollectPad.x + 6.5, 0, PlotLayout.Local.CollectPad.z)
	Build.block({ name = "Chest", size = V(2.6, 1.8, 3.4), cf = chestAt * CFrame.new(0, 0.9, 0), color = WOOD, material = Enum.Material.WoodPlanks, parent = model })
	Build.cyl({ name = "ChestLid", diameter = 2.6, height = 3.4, cf = chestAt * CFrame.new(0, 1.8, 0) * CFrame.Angles(math.rad(90), 0, 0), color = WOOD_DARK, material = Enum.Material.WoodPlanks, parent = model })
	Build.block({ name = "ChestBand", size = V(2.8, 2.9, 0.5), cf = chestAt * CFrame.new(0, 1.4, 0), color = GOLD, material = Enum.Material.Metal, parent = model })
	for i = 1, 3 do
		Build.cyl({ name = "Coin", diameter = 1.1, height = 0.2, position = (chestAt * CFrame.new(-2.2 + i * 0.3, 0.1 + i * 0.2, 1.4 - i * 0.5)).Position, color = GOLD, material = Enum.Material.Metal, shadow = false, parent = model })
	end

	-- Decoración por nivel de "Plot Makeover" (se muestra según la mejora; ver PlotService).
	local decor = {}
	for level = 1, DECOR_LEVELS do
		decor[level] = {}
	end
	local function deco(level, part)
		part.Transparency = 1
		part:SetAttribute("ShownTransparency", 0)
		table.insert(decor[level], part)
		return part
	end
	-- Nivel 1: macizos de flores junto a la entrada.
	for _, sx in ipairs({ -1, 1 }) do
		deco(1, Build.block({ name = "Planter", size = V(8, 1, 2.4), cf = cf * CFrame.new(sx * 17, 0.5, -half + 3.4), color = WOOD, material = Enum.Material.WoodPlanks, parent = model }))
		for i = 0, 3 do
			deco(1, Build.blob({ name = "Flower", size = V(1.5, 1.2, 1.5), cf = cf * CFrame.new(sx * 17 - 2.7 + i * 1.8, 1.5, -half + 3.4), color = (i % 2 == 0) and color or rgb(255, 255, 255), shadow = false, parent = model }))
		end
	end
	-- Nivel 2: farolillos en las esquinas del fondo.
	for _, sx in ipairs({ -1, 1 }) do
		deco(2, Build.cyl({ name = "LanternPost", diameter = 0.6, height = 7, position = (cf * CFrame.new(sx * (half - 3), 3.5, half - 3)).Position, color = rgb(60, 62, 84), material = Enum.Material.Metal, parent = model }))
		deco(2, Build.blob({ name = "LanternGlow", size = V(1.8, 2.2, 1.8), cf = cf * CFrame.new(sx * (half - 3), 7.6, half - 3), color = rgb(255, 236, 170), material = Enum.Material.Neon, shadow = false, parent = model }))
	end
	-- Nivel 3: estatua-trofeo al fondo.
	deco(3, Build.cyl({ name = "TrophyBase", diameter = 4, height = 1.4, position = (cf * CFrame.new(0, 0.7, half - 4)).Position, color = STONE, material = Enum.Material.Marble, parent = model }))
	deco(3, Build.blob({ name = "TrophyCup", size = V(3, 3.4, 3), cf = cf * CFrame.new(0, 3.4, half - 4), color = GOLD, material = Enum.Material.Metal, reflectance = 0.3, parent = model }))
	deco(3, Build.blob({ name = "TrophyStar", size = V(1.4, 1.4, 1.4), cf = cf * CFrame.new(0, 5.6, half - 4), color = color, material = Enum.Material.Neon, shadow = false, parent = model }))
	-- Nivel 4: banderines luminosos en el arco.
	for i = -3, 3 do
		deco(4, Build.wedge({ name = "Pennant", size = V(0.3, 1.8, 1.6), cf = cf * CFrame.new(i * 2.4, 12.6, -half + 0.6) * CFrame.Angles(math.rad(180), math.rad(90), 0), color = (i % 2 == 0) and color or rgb(255, 255, 255), material = Enum.Material.Neon, shadow = false, parent = model }))
	end

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
		decor = decor,
		layout = layout,
	}
end

local function buildPath(folder, index)
	local layout = PlotLayout.plot(index)
	local inner = W.PlazaRadius - 2
	local outer = W.PlotRingRadius - W.PlotSize / 2 + 2
	local mid = (inner + outer) / 2
	local base = CFrame.new(math.sin(layout.angle) * mid, 0, math.cos(layout.angle) * mid) * CFrame.Angles(0, layout.yaw, 0)
	Build.block({ name = "Path" .. index, size = V(14, 0.3, outer - inner), cf = base, color = SAND, material = Enum.Material.Sand, collide = true, shadow = false, parent = folder })
	for _, sx in ipairs({ -1, 1 }) do
		Build.block({ name = "PathEdge", size = V(1.2, 0.5, outer - inner), cf = base * CFrame.new(sx * 7.6, 0.05, 0), color = STONE_DARK, material = Enum.Material.Slate, shadow = false, parent = folder })
	end
	-- Banderín del color de la parcela al empezar el camino: se sabe adónde lleva.
	local color = WorldBuilder.PlotColors[(index - 1) % #WorldBuilder.PlotColors + 1]
	local flagAt = base * CFrame.new(9.5, 0, (outer - inner) / 2 - 3)
	Build.cyl({ name = "FlagPole", diameter = 0.5, height = 9, position = (flagAt * CFrame.new(0, 4.5, 0)).Position, color = rgb(60, 62, 84), material = Enum.Material.Metal, parent = folder })
	Build.wedge({ name = "Flag", size = V(0.3, 2.6, 3.6), cf = flagAt * CFrame.new(0, 7.6, -1.9) * CFrame.Angles(0, 0, 0), color = color, material = Enum.Material.Fabric, parent = folder })
end

---------------------------------------------------------------------------------------------
-- Iluminación. La tecnología (ShadowMap) se fija en default.project.json porque no es
-- modificable por script; aquí se añaden atmósfera y un posprocesado suave.
---------------------------------------------------------------------------------------------
local function setupLighting()
	local function ensure(className, props)
		local instance = Lighting:FindFirstChildOfClass(className)
		if not instance then
			instance = Instance.new(className)
			instance.Parent = Lighting
		end
		for key, value in pairs(props) do
			instance[key] = value
		end
		return instance
	end
	ensure("Atmosphere", { Density = 0.26, Offset = 0.15, Color = rgb(214, 228, 255), Decay = rgb(126, 150, 190), Glare = 0.05, Haze = 0.9 })
	ensure("ColorCorrectionEffect", { Saturation = 0.14, Contrast = 0.06, Brightness = 0.01, TintColor = rgb(255, 250, 244) })
	ensure("BloomEffect", { Intensity = 0.35, Size = 22, Threshold = 1.4 })
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

	local plotsFolder = Build.folder(Constants.Folders.Plots, folder)
	local plots = {}
	for index = 1, GameConfig.PlotCount do
		plots[index] = buildPlot(plotsFolder, index)
		buildPath(folder, index)
	end

	local kiosks = {}
	for index, def in ipairs(WorldBuilder.Kiosks) do
		kiosks[def.id] = buildKiosk(folder, index, def)
	end

	local _, placed = Scenery.build(folder)

	for _, name in ipairs({ Constants.Folders.Creatures, Constants.Folders.Pickups, Constants.Folders.Crates }) do
		if not workspace:FindFirstChild(name) then
			Build.folder(name, workspace)
		end
	end

	folder.Parent = workspace
	setupLighting()

	return {
		folder = folder,
		plots = plots,
		kiosks = kiosks,
		lobbySpawn = lobby,
		pedestalTop = V(0, 1.2, 0),
		scenery = placed,
	}
end

-- Referenciado por PlotService para saber cuántos niveles de decoración existen.
WorldBuilder.DecorLevels = DECOR_LEVELS
WorldBuilder.PlotStyles = UpgradeConfig.PlotStyles

return WorldBuilder
