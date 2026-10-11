-- Biblioteca de modelos 3D de comida. Cada alimento tiene su propio constructor con una silueta
-- reconocible (no hay esferas genéricas). Se construyen con el mismo Kit que las criaturas, así
-- que comparten escala, soldaduras y previsualización, y sirven igual para el mundo, para los
-- iconos de la interfaz y para la comida que vuela a la boca de la criatura.
--
-- Todos son PROTOTIPOS hechos con piezas nativas. Para sustituir uno por una malla de artista,
-- cambia su constructor por uno que clone el modelo (ver docs/ASSETS_PENDIENTES.md).
--
--   FoodModels.build(foodId) -> Visual | nil       (origen = punto de apoyo, +Y arriba)
--   FoodModels.has(foodId) -> bool
local Kit = require(script.Parent.Parent.Creatures.Kit)

local FoodModels = {}

local V = Vector3.new
local rgb = Color3.fromRGB

local function rot(x, y, z)
	return CFrame.Angles(math.rad(x or 0), math.rad(y or 0), math.rad(z or 0))
end

local function at(x, y, z, rx, ry, rz)
	return CFrame.new(x, y, z) * rot(rx, ry, rz)
end

local METAL = Enum.Material.Metal
local NEON = Enum.Material.Neon
local GLASS = Enum.Material.Glass

local B = {}

-- Triángulo isósceles plano (porción) hecho con dos cuñas espejadas. Punta hacia -Z.
local function slice(kit, name, width, length, thickness, cf, color, opts)
	for _, sx in ipairs({ -1, 1 }) do
		local o = table.clone(opts or {})
		-- WedgePart: sección triangular en YZ. Se tumba para que el triángulo quede horizontal.
		kit:wedge(name .. (sx < 0 and "L" or "R"), V(thickness, width / 2, length), cf * CFrame.new(sx * width / 4, 0, 0) * rot(0, 0, -sx * 90), color, o)
	end
end

function B.BREAD_CRUMB(kit)
	kit:blob("Loaf", V(2.5, 1.5, 1.5), V(0, 0.8, 0), rgb(214, 152, 82), { shadow = true })
	kit:blob("Base", V(2.3, 0.7, 1.35), V(0, 0.45, 0), rgb(240, 204, 140))
	for i = -1, 1 do
		kit:blob("Score" .. i, V(0.22, 0.2, 1.0), at(i * 0.62, 1.5, 0, 0, 22, 0), rgb(250, 226, 172))
	end
	return { radius = 1.3, height = 1.6 }
end

local function apple(kit, skin, leaf, material, reflectance)
	kit:blob("Fruit", V(2.0, 1.85, 2.0), V(0, 1.0, 0), skin, { shadow = true, material = material, reflectance = reflectance })
	kit:blob("Shoulder", V(1.5, 0.9, 1.5), V(0, 1.55, 0), skin, { material = material, reflectance = reflectance })
	kit:cyl("Stem", 0.16, 0.6, at(0.05, 2.05, 0, 0, 0, -14), rgb(110, 72, 40))
	kit:blob("Leaf", V(0.95, 0.14, 0.5), at(0.5, 2.15, 0, 0, 20, 24), leaf, { material = material, reflectance = reflectance })
	return { radius = 1.1, height = 2.3 }
end

function B.APPLE(kit)
	local info = apple(kit, rgb(226, 54, 54), rgb(98, 190, 80))
	kit:blob("Shine", V(0.4, 0.6, 0.2), at(-0.55, 1.3, -0.85, 0, 30, 20), rgb(255, 190, 190))
	return info
end

function B.GOLDEN_APPLE(kit)
	local info = apple(kit, rgb(255, 204, 60), rgb(255, 232, 140), METAL, 0.4)
	kit:blob("Glow", V(0.5, 0.5, 0.5), V(0, 1.0, 0), rgb(255, 244, 190), { material = NEON })
	return info
end

function B.CARROT(kit)
	local axis = at(0, 1.0, 0, 0, 0, 52)
	local orange = rgb(255, 140, 44)
	kit:blob("Top", V(0.95, 1.2, 0.95), axis * CFrame.new(0, 0.75, 0), orange, { shadow = true })
	kit:blob("Mid", V(0.78, 1.2, 0.78), axis * CFrame.new(0, 0.05, 0), orange)
	kit:blob("Tip", V(0.5, 1.1, 0.5), axis * CFrame.new(0, -0.7, 0), orange)
	for i, a in ipairs({ -30, 0, 30 }) do
		kit:blob("Leaf" .. i, V(0.3, 1.0, 0.3), axis * CFrame.new(0, 1.5, 0) * rot(a, 0, a * 0.6), rgb(96, 190, 84))
	end
	for i = 0, 2 do
		kit:blob("Ring" .. i, V(0.5, 0.08, 0.3), axis * CFrame.new(0, 0.55 - i * 0.5, -0.36 + i * 0.05), rgb(224, 108, 30))
	end
	return { radius = 1.2, height = 2.0 }
end

function B.JELLY_BERRIES(kit)
	local berry = rgb(104, 92, 232)
	local spots = { V(-0.5, 1.35, 0), V(0.5, 1.35, 0), V(0, 1.4, 0.45), V(-0.25, 0.75, 0.1), V(0.3, 0.75, -0.1), V(0, 0.3, 0) }
	for i, p in ipairs(spots) do
		kit:blob("Berry" .. i, V(0.95, 0.95, 0.95), p, i % 2 == 0 and berry or rgb(134, 110, 245), { material = GLASS, reflectance = 0.15, shadow = i == 1 })
	end
	kit:cyl("Stem", 0.14, 0.6, at(0, 2.0, 0.1, 0, 0, 10), rgb(110, 72, 40))
	kit:blob("Leaf", V(1.0, 0.14, 0.6), at(0.45, 2.05, 0.1, 0, 0, 18), rgb(98, 190, 80))
	return { radius = 1.0, height = 2.3 }
end

function B.STINKY_CHEESE(kit)
	local yellow = rgb(255, 212, 76)
	kit:wedge("Wedge", V(1.5, 1.3, 2.3), at(0, 0.65, 0, 0, 180, 0), yellow, { shadow = true })
	kit:block("Rind", V(1.56, 1.34, 0.14), V(0, 0.67, -1.1), rgb(236, 170, 50))
	for i, p in ipairs({ V(0.76, 0.5, -0.5), V(0.76, 0.85, -0.85), V(-0.76, 0.45, -0.3), V(-0.76, 0.8, -0.75), V(0.76, 0.3, 0.1) }) do
		kit:blob("Hole" .. i, V(0.12, 0.38 - (i % 2) * 0.1, 0.38 - (i % 2) * 0.1), p, rgb(214, 150, 40))
	end
	kit:blob("Stink1", V(0.14, 0.7, 0.14), at(0.2, 1.7, -0.6, 0, 0, 18), rgb(150, 210, 110), { material = NEON, transparency = 0.35 })
	kit:blob("Stink2", V(0.14, 0.55, 0.14), at(-0.35, 1.55, -0.2, 0, 0, -16), rgb(150, 210, 110), { material = NEON, transparency = 0.35 })
	return { radius = 1.3, height = 2.0 }
end

function B.MEATBALL(kit)
	kit:blob("Plate", V(2.5, 0.3, 2.5), V(0, 0.15, 0), rgb(244, 244, 248), { shadow = true })
	kit:blob("Ball", V(1.8, 1.7, 1.8), V(0, 1.0, 0), rgb(142, 84, 54))
	kit:blob("Lump1", V(0.8, 0.7, 0.8), V(0.55, 1.35, -0.45), rgb(128, 72, 46))
	kit:blob("Lump2", V(0.7, 0.6, 0.7), V(-0.6, 0.85, 0.4), rgb(128, 72, 46))
	kit:blob("Sauce", V(1.5, 0.5, 1.5), V(0, 1.65, 0), rgb(214, 52, 40))
	kit:blob("Drip", V(0.4, 0.8, 0.4), V(0.55, 1.3, 0.5), rgb(214, 52, 40))
	kit:cyl("Pick", 0.1, 1.5, at(0, 2.2, 0, 0, 0, 8), rgb(226, 190, 130))
	kit:blob("Olive", V(0.42, 0.42, 0.42), V(-0.1, 2.9, 0), rgb(120, 170, 60))
	return { radius = 1.3, height = 3.1 }
end

function B.PIZZA(kit)
	local base = at(0, 0.5, 0.1, -14, 0, 0)
	slice(kit, "Dough", 2.3, 2.6, 0.22, base, rgb(236, 190, 110), { shadow = true })
	slice(kit, "Cheese", 2.0, 2.2, 0.1, base * CFrame.new(0, 0.16, 0.12), rgb(255, 206, 72))
	kit:cyl("Crust", 0.5, 2.4, base * CFrame.new(0, 0.08, 1.3) * rot(0, 0, 90), rgb(214, 150, 80))
	for i, p in ipairs({ V(0, 0.24, 0.75), V(-0.45, 0.24, 0.2), V(0.4, 0.24, 0.1), V(0, 0.24, -0.45) }) do
		kit:cyl("Pepperoni" .. i, 0.46, 0.08, base * CFrame.new(p), rgb(196, 50, 44))
	end
	kit:blob("Basil", V(0.4, 0.06, 0.26), base * CFrame.new(0.3, 0.26, 0.7) * rot(0, 30, 0), rgb(90, 170, 70))
	return { radius = 1.4, height = 1.3 }
end

function B.DONUT(kit)
	local tilt = at(0, 1.15, 0, 62, 0, 0)
	for i = 1, 12 do
		local a = (i - 1) / 12 * math.pi * 2
		local ring = tilt * CFrame.new(math.cos(a) * 0.75, 0, math.sin(a) * 0.75)
		kit:blob("Dough" .. i, V(0.85, 0.8, 0.85), ring, rgb(222, 160, 92), { shadow = i == 1 })
		kit:blob("Glaze" .. i, V(0.8, 0.5, 0.8), ring * CFrame.new(0, 0.22, 0), rgb(255, 128, 190))
	end
	local colors = { rgb(255, 255, 255), rgb(120, 220, 255), rgb(255, 230, 90), rgb(150, 240, 150) }
	for i = 1, 8 do
		local a = (i - 0.5) / 8 * math.pi * 2
		kit:block("Sprinkle" .. i, V(0.24, 0.08, 0.08), tilt * CFrame.new(math.cos(a) * 0.75, 0.48, math.sin(a) * 0.75) * rot(0, i * 47, 0), colors[i % 4 + 1])
	end
	return { radius = 1.25, height = 2.3 }
end

function B.BURGER(kit)
	local bun = rgb(226, 160, 84)
	kit:blob("BunBottom", V(2.3, 0.9, 2.3), V(0, 0.45, 0), bun, { shadow = true })
	kit:cyl("Patty", 2.4, 0.45, V(0, 0.95, 0), rgb(112, 64, 40))
	kit:block("Cheese", V(2.1, 0.12, 2.1), at(0, 1.22, 0, 0, 45, 0), rgb(255, 204, 60))
	kit:blob("Lettuce", V(2.7, 0.4, 2.7), V(0, 1.4, 0), rgb(120, 204, 90))
	kit:cyl("Tomato", 2.0, 0.22, V(0, 1.62, 0), rgb(226, 62, 56))
	kit:blob("BunTop", V(2.3, 1.4, 2.3), V(0, 2.05, 0), bun)
	for i = 1, 6 do
		local a = (i - 1) / 6 * math.pi * 2
		kit:blob("Sesame" .. i, V(0.2, 0.1, 0.12), at(math.cos(a) * 0.6, 2.62, math.sin(a) * 0.6, 0, i * 50, 0), rgb(252, 240, 200))
	end
	return { radius = 1.35, height = 2.8 }
end

function B.TACO(kit)
	local shell = rgb(246, 198, 88)
	kit:blob("ShellL", V(0.3, 1.9, 2.6), at(-0.5, 0.95, 0, 0, 0, 20), shell, { shadow = true })
	kit:blob("ShellR", V(0.3, 1.9, 2.6), at(0.5, 0.95, 0, 0, 0, -20), shell)
	kit:blob("ShellBase", V(1.0, 0.5, 2.3), V(0, 0.3, 0), shell)
	kit:blob("Meat", V(0.8, 0.8, 2.1), V(0, 1.1, 0), rgb(128, 76, 46))
	kit:blob("Lettuce", V(0.9, 0.6, 2.3), V(0, 1.6, 0), rgb(120, 204, 90))
	for i, z in ipairs({ -0.7, 0, 0.7 }) do
		kit:blob("Tomato" .. i, V(0.45, 0.4, 0.45), V((i % 2 == 0) and 0.12 or -0.12, 1.95, z), rgb(226, 62, 56))
	end
	kit:blob("Cheese", V(0.5, 0.2, 1.6), V(0.05, 1.85, 0.35), rgb(255, 214, 80))
	return { radius = 1.35, height = 2.2 }
end

function B.SUSHI(kit)
	local function roll(x, z, fill)
		kit:cyl("Nori" .. x, 1.3, 1.0, V(x, 0.5, z), rgb(30, 54, 44), { shadow = true })
		kit:cyl("Rice" .. x, 1.14, 1.04, V(x, 0.52, z), rgb(250, 250, 244))
		kit:blob("Fill" .. x, V(0.6, 0.3, 0.6), V(x, 1.02, z), fill)
	end
	roll(-0.72, 0.1, rgb(255, 140, 90))
	roll(0.72, -0.1, rgb(140, 210, 110))
	kit:cyl("Chopstick1", 0.1, 3.0, at(0, 1.25, 0.1, 0, 0, 82) * rot(0, 0, 0), rgb(196, 140, 86))
	kit:cyl("Chopstick2", 0.1, 3.0, at(0, 1.25, -0.2, 8, 0, 80), rgb(196, 140, 86))
	return { radius = 1.5, height = 1.5 }
end

function B.DINO_STEAK(kit)
	kit:blob("Meat", V(2.5, 1.7, 1.4), at(0, 1.1, 0, 0, 0, 12), rgb(196, 62, 66), { shadow = true })
	kit:blob("Fat", V(2.6, 1.8, 0.9), at(0, 1.1, 0, 0, 0, 12), rgb(250, 228, 214))
	kit:blob("Marble", V(1.5, 0.9, 1.46), at(0.1, 1.15, 0, 0, 0, 12), rgb(156, 40, 50))
	kit:limb("Bone", V(-0.9, 0.9, 0), V(-2.1, 0.55, 0), 0.34, rgb(250, 246, 236))
	kit:blob("Knob1", V(0.55, 0.55, 0.55), V(-2.2, 0.75, 0), rgb(250, 246, 236))
	kit:blob("Knob2", V(0.55, 0.55, 0.55), V(-2.2, 0.36, 0), rgb(250, 246, 236))
	return { radius = 1.7, height = 2.1 }
end

function B.MEGA_MELON(kit)
	local base = at(0, 1.25, 0, 90, 0, 0) -- la porción de pie, con la corteza abajo
	slice(kit, "Flesh", 2.6, 2.0, 0.7, base * CFrame.new(0, 0, -0.1), rgb(240, 70, 84), { shadow = true })
	kit:blob("Rind", V(2.8, 0.75, 0.6), V(0, 0.3, 0), rgb(70, 170, 84))
	kit:blob("RindInner", V(2.5, 0.5, 0.66), V(0, 0.5, 0), rgb(214, 240, 190))
	for i, p in ipairs({ V(-0.5, 1.0, 0.36), V(0.45, 1.05, 0.36), V(0, 1.6, 0.36), V(-0.5, 1.0, -0.36), V(0.45, 1.05, -0.36), V(0, 1.6, -0.36) }) do
		kit:blob("Seed" .. i, V(0.16, 0.26, 0.08), p, rgb(30, 24, 24))
	end
	return { radius = 1.4, height = 2.4 }
end

function B.LAYER_CAKE(kit)
	kit:cyl("Plate", 2.6, 0.12, V(0, 0.06, 0), rgb(244, 244, 248), { shadow = true })
	kit:cyl("Sponge1", 2.1, 0.6, V(0, 0.42, 0), rgb(246, 214, 150))
	kit:cyl("Cream1", 2.16, 0.2, V(0, 0.82, 0), rgb(255, 150, 196))
	kit:cyl("Sponge2", 2.1, 0.6, V(0, 1.22, 0), rgb(246, 214, 150))
	kit:blob("Icing", V(2.3, 0.7, 2.3), V(0, 1.62, 0), rgb(255, 244, 248))
	for i = 1, 6 do
		local a = (i - 1) / 6 * math.pi * 2
		kit:blob("Dollop" .. i, V(0.42, 0.42, 0.42), V(math.cos(a) * 0.78, 2.0, math.sin(a) * 0.78), rgb(255, 150, 196))
	end
	kit:blob("Cherry", V(0.5, 0.5, 0.5), V(0, 2.2, 0), rgb(214, 30, 50), { material = GLASS, reflectance = 0.2 })
	kit:cyl("CherryStem", 0.06, 0.5, at(0.1, 2.6, 0, 0, 0, -20), rgb(110, 72, 40))
	return { radius = 1.4, height = 2.8 }
end

function B.LAVA_RAMEN(kit)
	kit:blob("Bowl", V(2.6, 1.6, 2.6), V(0, 0.8, 0), rgb(40, 34, 44), { shadow = true })
	kit:cyl("Rim", 2.5, 0.18, V(0, 1.4, 0), rgb(226, 62, 56))
	kit:cyl("Broth", 2.3, 0.1, V(0, 1.5, 0), rgb(255, 120, 40), { material = NEON })
	for i, a in ipairs({ 20, 80, 150 }) do
		kit:blob("Noodle" .. i, V(1.5, 0.16, 0.2), at(0, 1.58, 0, 0, a, 0) * CFrame.new(0, 0, 0.25), rgb(255, 234, 150))
	end
	kit:blob("Egg", V(0.7, 0.3, 0.9), V(-0.55, 1.6, -0.45), rgb(255, 255, 250))
	kit:blob("Yolk", V(0.36, 0.2, 0.36), V(-0.55, 1.7, -0.45), rgb(255, 190, 40))
	kit:blob("Chili", V(0.2, 0.2, 0.8), at(0.6, 1.62, 0.4, 0, 40, 0), rgb(214, 30, 40))
	kit:limb("Stick1", V(0.5, 1.5, -0.4), V(1.9, 2.7, -1.2), 0.1, rgb(196, 140, 86))
	kit:limb("Stick2", V(0.7, 1.5, -0.2), V(2.0, 2.7, -0.9), 0.1, rgb(196, 140, 86))
	return { radius = 1.5, height = 2.4 }
end

function B.ROYAL_LOBSTER(kit)
	local red = rgb(236, 72, 52)
	local dark = rgb(196, 44, 40)
	kit:blob("Body", V(1.2, 1.0, 1.9), V(0, 0.8, -0.2), red, { shadow = true })
	kit:blob("Tail1", V(1.0, 0.8, 0.9), V(0, 0.75, 0.9), dark)
	kit:blob("Tail2", V(0.85, 0.65, 0.8), V(0, 0.6, 1.5), red)
	kit:blob("Fan", V(1.5, 0.2, 0.8), V(0, 0.4, 2.05), dark)
	for _, sx in ipairs({ -1, 1 }) do
		kit:limb("Arm" .. sx, V(sx * 0.4, 0.8, -0.9), V(sx * 1.2, 1.0, -1.6), 0.24, dark)
		kit:blob("Claw" .. sx, V(0.8, 0.5, 1.2), at(sx * 1.3, 1.05, -2.1, 0, sx * -18, 0), red)
		kit:blob("Pincer" .. sx, V(0.3, 0.3, 0.8), at(sx * 0.95, 1.05, -2.35, 0, sx * 14, 0), red)
		kit:limb("Feeler" .. sx, V(sx * 0.2, 1.15, -1.0), V(sx * 0.7, 2.1, -1.9), 0.07, dark)
		kit:blob("Eye" .. sx, V(0.22, 0.22, 0.22), V(sx * 0.25, 1.35, -0.95), rgb(20, 20, 26))
		for i = 0, 1 do
			kit:limb("Leg" .. sx .. i, V(sx * 0.5, 0.6, 0.1 + i * 0.5), V(sx * 1.1, 0.1, 0.2 + i * 0.6), 0.12, dark)
		end
	end
	kit:blob("Crown", V(0.5, 0.3, 0.5), V(0, 1.42, -0.3), rgb(255, 204, 60), { material = METAL, reflectance = 0.3 })
	return { radius = 1.6, height = 2.2 }
end

function B.THUNDER_HONEY(kit)
	kit:cyl("Jar", 1.7, 1.7, V(0, 0.85, 0), rgb(255, 176, 30), { material = GLASS, reflectance = 0.15, transparency = 0.1, shadow = true })
	kit:blob("Honey", V(1.4, 1.2, 1.4), V(0, 0.8, 0), rgb(255, 204, 60), { material = NEON })
	kit:cyl("Neck", 1.4, 0.3, V(0, 1.8, 0), rgb(255, 176, 30), { material = GLASS })
	kit:cyl("Lid", 1.6, 0.3, V(0, 2.05, 0), rgb(70, 60, 90))
	kit:block("Label", V(1.2, 0.8, 0.1), V(0, 0.9, -0.84), rgb(255, 250, 230))
	-- Rayo en la etiqueta (tres trazos).
	local bolt = rgb(90, 220, 255)
	kit:block("Bolt1", V(0.18, 0.4, 0.06), at(0.1, 1.08, -0.9, 0, 0, -28), bolt, { material = NEON })
	kit:block("Bolt2", V(0.4, 0.14, 0.06), V(0, 0.9, -0.9), bolt, { material = NEON })
	kit:block("Bolt3", V(0.18, 0.4, 0.06), at(-0.1, 0.7, -0.9, 0, 0, -28), bolt, { material = NEON })
	kit:limb("Dipper", V(0.2, 2.1, 0.2), V(0.8, 3.1, 0.5), 0.12, rgb(196, 140, 86))
	kit:blob("DipperHead", V(0.5, 0.6, 0.5), V(0.85, 3.2, 0.52), rgb(214, 160, 90))
	return { radius = 1.1, height = 3.4 }
end

function B.STARFRUIT(kit)
	local gold = rgb(255, 236, 110)
	kit:blob("Core", V(1.1, 1.1, 0.9), V(0, 1.5, 0), gold, { material = NEON, shadow = true })
	for i = 1, 5 do
		local a = math.rad((i - 1) * 72)
		kit:blob("Point" .. i, V(0.75, 1.5, 0.7), CFrame.new(math.sin(a) * 0.85, 1.5 + math.cos(a) * 0.85, 0) * CFrame.Angles(0, 0, -a), rgb(255, 214, 60), { material = METAL, reflectance = 0.25 })
	end
	kit:blob("Leaf", V(0.7, 0.12, 0.4), at(0.2, 2.95, 0, 0, 0, 25), rgb(120, 220, 110))
	for i, p in ipairs({ V(-1.5, 2.6, 0.2), V(1.6, 2.2, -0.2), V(-1.2, 0.5, -0.1) }) do
		kit:blob("Twinkle" .. i, V(0.2, 0.2, 0.2), p, rgb(255, 255, 255), { material = NEON })
	end
	return { radius = 1.6, height = 3.1 }
end

function B.VOID_TRUFFLE(kit)
	local void = rgb(46, 18, 74)
	kit:blob("Truffle", V(2.0, 1.7, 1.9), V(0, 1.1, 0), void, { shadow = true })
	kit:blob("Lump1", V(1.0, 0.9, 1.0), V(0.6, 1.6, -0.3), rgb(60, 24, 96))
	kit:blob("Lump2", V(0.9, 0.8, 0.9), V(-0.65, 0.9, 0.45), rgb(60, 24, 96))
	kit:blob("Lump3", V(0.8, 0.7, 0.8), V(-0.4, 1.65, 0.4), void)
	local crack = rgb(255, 70, 200)
	kit:block("Crack1", V(0.9, 0.08, 0.08), at(0.1, 1.2, -0.95, 0, 0, 24), crack, { material = NEON })
	kit:block("Crack2", V(0.6, 0.08, 0.08), at(-0.35, 0.9, -0.92, 0, 0, -30), crack, { material = NEON })
	kit:block("Crack3", V(0.5, 0.08, 0.08), at(0.55, 0.85, -0.85, 0, 20, -50), crack, { material = NEON })
	kit:blob("Heart", V(0.6, 0.6, 0.6), V(0, 1.1, 0), rgb(120, 255, 240), { material = NEON })
	kit:block("Shard1", V(0.3, 0.3, 0.3), at(1.5, 2.2, 0.2, 30, 20, 40), crack, { material = NEON })
	kit:block("Shard2", V(0.24, 0.24, 0.24), at(-1.4, 2.5, -0.3, 10, 50, 20), rgb(120, 255, 240), { material = NEON })
	kit:block("Shard3", V(0.2, 0.2, 0.2), at(-1.6, 0.6, 0.5, 40, 10, 60), void)
	return { radius = 1.5, height = 2.8 }
end

function FoodModels.has(foodId)
	return B[foodId] ~= nil
end

function FoodModels.build(foodId)
	local builder = B[foodId]
	if not builder then
		return nil
	end
	local kit = Kit.new("Food_" .. foodId, 1)
	local info = builder(kit)
	info.center = info.center or Vector3.new(0, info.height / 2, 0)
	return kit:finish(info, true)
end

FoodModels.Ids = {}
for id in pairs(B) do
	table.insert(FoodModels.Ids, id)
end
table.sort(FoodModels.Ids)

return FoodModels
