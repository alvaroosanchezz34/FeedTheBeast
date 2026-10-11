-- Vegetación y decoración ambiental: árboles, setas gigantes, rocas, arbustos, flores, cristales
-- y colinas en el horizonte. La colocación es determinista (misma semilla = mismo mapa) y respeta
-- parcelas, caminos y plaza: nada bloquea rutas ni zonas de interacción.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local PlotLayout = require(Shared.Logic.PlotLayout)

local Build = require(script.Parent.Build)

local Scenery = {}

local W = GameConfig.World
local rgb = Color3.fromRGB
local V = Vector3.new

Scenery.Counts = { trees = 44, mushrooms = 14, rocks = 22, bushes = 30, flowers = 46, crystals = 8, hills = 14 }

local LEAF = { rgb(96, 190, 96), rgb(70, 170, 110), rgb(140, 206, 90), rgb(255, 150, 190) }
local CAP = { rgb(232, 70, 70), rgb(170, 100, 240), rgb(255, 160, 60) }
local PETAL = { rgb(255, 120, 170), rgb(255, 220, 90), rgb(140, 190, 255), rgb(255, 255, 255), rgb(190, 130, 255) }

-- ¿Está (x, z) libre de parcelas, caminos, plaza y borde? `margin` = holgura del objeto.
function Scenery.isFree(x, z, margin)
	local r = math.sqrt(x * x + z * z)
	local limit = W.GroundSize / 2 - 10
	if math.abs(x) > limit - margin or math.abs(z) > limit - margin then
		return false
	end
	if r < W.PlazaRadius + 5 + margin then
		return false
	end
	local half = W.PlotSize / 2 + 3 + margin
	for index = 1, GameConfig.PlotCount do
		local plot = PlotLayout.plot(index)
		-- A coordenadas locales de la parcela.
		local dx, dz = x - plot.x, z - plot.z
		local cos, sin = math.cos(plot.yaw), math.sin(plot.yaw)
		local lx = dx * cos - dz * sin
		local lz = dx * sin + dz * cos
		if math.abs(lx) < half and math.abs(lz) < half then
			return false
		end
		-- Camino entre la plaza y la entrada (franja radial).
		local along = x * math.sin(plot.angle) + z * math.cos(plot.angle)
		local across = math.abs(x * math.cos(plot.angle) - z * math.sin(plot.angle))
		if along > 0 and along < W.PlotRingRadius and across < 11 + margin then
			return false
		end
	end
	return true
end

local function tree(parent, x, z, rng)
	local height = rng:NextNumber(9, 14)
	local leaf = LEAF[rng:NextInteger(1, #LEAF)]
	local model = Instance.new("Model")
	model.Name = "Tree"
	Build.cyl({ name = "Trunk", diameter = rng:NextNumber(1.8, 2.4), height = height, position = V(x, height / 2, z), color = rgb(122, 84, 58), material = Enum.Material.Wood, collide = true, parent = model })
	local crown = rng:NextNumber(8, 11)
	Build.blob({ name = "Crown", size = V(crown, crown * 0.85, crown), cf = CFrame.new(x, height + crown * 0.25, z), color = leaf, material = Enum.Material.Grass, parent = model })
	for i = 1, 2 do
		local a = rng:NextNumber(0, math.pi * 2)
		local s = crown * rng:NextNumber(0.55, 0.7)
		Build.blob({ name = "Puff" .. i, size = V(s, s * 0.85, s), cf = CFrame.new(x + math.cos(a) * crown * 0.36, height + crown * rng:NextNumber(0, 0.3), z + math.sin(a) * crown * 0.36), color = leaf:Lerp(rgb(255, 255, 255), 0.12), material = Enum.Material.Grass, shadow = false, parent = model })
	end
	model.Parent = parent
end

local function mushroom(parent, x, z, rng)
	local height = rng:NextNumber(4, 8)
	local cap = CAP[rng:NextInteger(1, #CAP)]
	local width = height * rng:NextNumber(1.1, 1.5)
	local model = Instance.new("Model")
	model.Name = "Mushroom"
	Build.blob({ name = "Stem", size = V(height * 0.36, height * 1.1, height * 0.36), cf = CFrame.new(x, height * 0.5, z), color = rgb(250, 240, 220), collide = true, parent = model })
	Build.blob({ name = "Cap", size = V(width, height * 0.55, width), cf = CFrame.new(x, height, z), color = cap, parent = model })
	for i = 1, 5 do
		local a = (i - 1) / 5 * math.pi * 2 + rng:NextNumber(0, 1)
		local r = width * 0.3
		Build.blob({ name = "Dot" .. i, size = V(width * 0.16, 0.3, width * 0.16), cf = CFrame.new(x + math.cos(a) * r, height + height * 0.2, z + math.sin(a) * r), color = rgb(255, 255, 255), shadow = false, parent = model })
	end
	model.Parent = parent
end

local function rock(parent, x, z, rng)
	local s = rng:NextNumber(2.5, 6)
	Build.blob({ name = "Rock", size = V(s * rng:NextNumber(1, 1.5), s * rng:NextNumber(0.6, 0.9), s * rng:NextNumber(0.9, 1.3)), cf = CFrame.new(x, s * 0.22, z) * CFrame.Angles(0, rng:NextNumber(0, 6.28), rng:NextNumber(-0.2, 0.2)), color = rgb(150, 156, 170), material = Enum.Material.Slate, collide = true, parent = parent })
end

local function bush(parent, x, z, rng)
	local s = rng:NextNumber(3, 5)
	local leaf = LEAF[rng:NextInteger(1, 3)]
	Build.blob({ name = "Bush", size = V(s * 1.3, s * 0.8, s * 1.2), cf = CFrame.new(x, s * 0.28, z), color = leaf, material = Enum.Material.Grass, parent = parent })
	Build.blob({ name = "BushTop", size = V(s * 0.8, s * 0.7, s * 0.8), cf = CFrame.new(x + s * 0.3, s * 0.5, z - s * 0.2), color = leaf:Lerp(rgb(255, 255, 255), 0.1), material = Enum.Material.Grass, shadow = false, parent = parent })
end

local function flowers(parent, x, z, rng)
	local petal = PETAL[rng:NextInteger(1, #PETAL)]
	for i = 1, 3 do
		local fx, fz = x + rng:NextNumber(-1.6, 1.6), z + rng:NextNumber(-1.6, 1.6)
		local h = rng:NextNumber(0.8, 1.4)
		Build.cyl({ name = "Stalk", diameter = 0.14, height = h, position = V(fx, h / 2, fz), color = rgb(80, 160, 80), shadow = false, parent = parent })
		Build.blob({ name = "Bloom", size = V(0.9, 0.45, 0.9), cf = CFrame.new(fx, h, fz), color = petal, shadow = false, parent = parent })
		Build.blob({ name = "Heart", size = V(0.36, 0.36, 0.36), cf = CFrame.new(fx, h + 0.12, fz), color = rgb(255, 214, 80), shadow = false, parent = parent })
	end
end

local function crystal(parent, x, z, rng)
	local color = rng:NextInteger(1, 2) == 1 and rgb(120, 230, 255) or rgb(220, 140, 255)
	for i = 1, 3 do
		local h = rng:NextNumber(2.5, 5.5)
		local w = h * 0.3
		Build.block({ name = "Crystal" .. i, size = V(w, h, w), cf = CFrame.new(x + (i - 2) * 0.9, h * 0.4, z + rng:NextNumber(-0.5, 0.5)) * CFrame.Angles(rng:NextNumber(-0.25, 0.25), rng:NextNumber(0, 3), rng:NextNumber(-0.3, 0.3)), color = color, material = Enum.Material.Glass, transparency = 0.2, reflectance = 0.2, shadow = false, parent = parent })
	end
	Build.blob({ name = "CrystalGlow", size = V(1.2, 0.5, 1.2), cf = CFrame.new(x, 0.25, z), color = color, material = Enum.Material.Neon, shadow = false, parent = parent })
end

-- Coloca `count` objetos en posiciones libres dentro de un anillo [rMin, rMax].
local function scatter(rng, count, margin, rMin, rMax, place)
	local placed, attempts = 0, 0
	local taken = {}
	while placed < count and attempts < count * 40 do
		attempts += 1
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(rMin, rMax)
		local x, z = math.cos(a) * r, math.sin(a) * r
		if Scenery.isFree(x, z, margin) then
			local ok = true
			for _, other in ipairs(taken) do
				if (other.x - x) ^ 2 + (other.z - z) ^ 2 < (margin * 2) ^ 2 then
					ok = false
					break
				end
			end
			if ok then
				table.insert(taken, { x = x, z = z })
				place(x, z)
				placed += 1
			end
		end
	end
	return placed
end

function Scenery.build(parent)
	local rng = Random.new(20261011)
	local folder = Build.folder("Scenery", parent)
	local half = W.GroundSize / 2
	local placed = {}

	placed.trees = scatter(rng, Scenery.Counts.trees, 5, W.PlazaRadius + 12, half - 14, function(x, z)
		tree(folder, x, z, rng)
	end)
	placed.mushrooms = scatter(rng, Scenery.Counts.mushrooms, 4, W.PlazaRadius + 8, half - 20, function(x, z)
		mushroom(folder, x, z, rng)
	end)
	placed.rocks = scatter(rng, Scenery.Counts.rocks, 3, W.PlazaRadius + 6, half - 12, function(x, z)
		rock(folder, x, z, rng)
	end)
	placed.bushes = scatter(rng, Scenery.Counts.bushes, 2.5, W.PlazaRadius + 6, half - 12, function(x, z)
		bush(folder, x, z, rng)
	end)
	placed.flowers = scatter(rng, Scenery.Counts.flowers, 1.5, W.PlazaRadius + 6, half - 12, function(x, z)
		flowers(folder, x, z, rng)
	end)
	placed.crystals = scatter(rng, Scenery.Counts.crystals, 3, W.PlazaRadius + 10, half - 30, function(x, z)
		crystal(folder, x, z, rng)
	end)

	-- Colinas fuera del área jugable: rompen el horizonte plano.
	for i = 1, Scenery.Counts.hills do
		local a = (i - 1) / Scenery.Counts.hills * math.pi * 2 + rng:NextNumber(-0.15, 0.15)
		local r = half * 1.42 + rng:NextNumber(0, 40)
		local s = rng:NextNumber(90, 150)
		Build.blob({ name = "Hill" .. i, size = V(s * 1.4, s * 0.55, s * 1.2), cf = CFrame.new(math.cos(a) * r, -6, math.sin(a) * r) * CFrame.Angles(0, a, 0), color = (i % 2 == 0) and rgb(96, 178, 100) or rgb(118, 196, 110), material = Enum.Material.Grass, shadow = false, parent = folder })
	end
	placed.hills = Scenery.Counts.hills
	return folder, placed
end

return Scenery
