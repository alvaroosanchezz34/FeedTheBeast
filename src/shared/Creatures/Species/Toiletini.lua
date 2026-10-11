-- TOILETINI — un inodoro presumido. La tapa levantada es su cara (los ojos van en su interior),
-- la taza es la boca, y saluda con un desatascador.
local Anim = require(script.Parent.Parent.Anim)
local V = Vector3.new
local rgb = Color3.fromRGB
local rot = Anim.rot

local PORCELAIN = rgb(248, 248, 252)
local SHADE = rgb(214, 220, 236)
local WATER = rgb(86, 198, 255)
local RED = rgb(230, 62, 62)
local WOOD = rgb(176, 124, 72)
local STEEL = rgb(190, 198, 212)
local GOLD = rgb(255, 204, 70)

local Toiletini = { unit = 0.74 }

function Toiletini.build(kit)
	for _, side in ipairs({ { "L", -1 }, { "R", 1 } }) do
		local name, sx = side[1], side[2]
		local leg = kit:cyl("Leg" .. name, 0.38, 1.0, V(sx * 0.95, 1.1, 0), STEEL, { role = "Accent", joint = "Leg" .. name, pivot = V(sx * 0.95, 1.6, 0) })
		kit:blob("Sneaker" .. name, V(1.3, 0.8, 2.1), V(sx * 0.95, 0.4, -0.45), RED, { role = "Detail", parent = leg })
	end
	local base = kit:blob("Pedestal", V(2.6, 2.4, 2.9), V(0, 2.3, 0.1), PORCELAIN, { role = "Body", reflectance = 0.1, shadow = true, joint = "Torso", pivot = V(0, 1.4, 0) })
	local bowl = kit:blob("Bowl", V(4.2, 2.7, 4.9), V(0, 3.75, -0.35), PORCELAIN, { role = "Body", reflectance = 0.1, parent = base, shadow = true })
	kit:blob("Seat", V(4.45, 0.7, 5.15), V(0, 4.75, -0.35), SHADE, { role = "Belly", parent = bowl })
	kit:blob("Water", V(3.5, 0.6, 4.2), V(0, 4.95, -0.35), WATER, { role = "Mouth", material = Enum.Material.Neon, parent = bowl })
	kit:blob("Tongue", V(1.3, 0.4, 2.2), CFrame.new(0, 4.95, -2.45) * rot(-22, 0, 0), rgb(255, 122, 150), { role = "Tongue", parent = bowl })
	for i, angle in ipairs({ -34, -12, 12, 34 }) do
		local a = math.rad(angle)
		kit:blob("Tooth" .. i, V(0.42, 0.6, 0.4), V(math.sin(a) * 1.75, 5.2, -0.35 - math.cos(a) * 2.1), PORCELAIN, { role = "Teeth", parent = bowl })
	end
	-- Cisterna detrás.
	local tank = kit:blob("Tank", V(3.9, 3.3, 1.9), V(0, 6.3, 2.75), PORCELAIN, { role = "Body", reflectance = 0.1, parent = base, shadow = true })
	kit:blob("TankTop", V(4.1, 0.6, 2.1), V(0, 7.85, 2.75), SHADE, { role = "Belly", parent = tank })
	kit:cyl("Handle", 0.26, 0.9, CFrame.new(-2.1, 7.1, 2.4) * rot(0, 0, 90), STEEL, { role = "Detail", material = Enum.Material.Metal, parent = tank })
	kit:blob("HandleKnob", V(0.5, 0.5, 0.5), V(-2.6, 7.1, 2.4), STEEL, { role = "Detail", material = Enum.Material.Metal, parent = tank })
	-- Tapa levantada = cara. Bisagra detrás de la taza; al comer baja de golpe.
	local lid = kit:blob("Lid", V(4.1, 4.9, 0.7), CFrame.new(0, 7.2, 1.55) * rot(-9, 0, 0), PORCELAIN, { role = "Body", reflectance = 0.1, parent = base, joint = "Jaw", pivot = V(0, 4.95, 1.95), shadow = true })
	for _, side in ipairs({ { "L", -1 }, { "R", 1 } }) do
		local name, sx = side[1], side[2]
		kit:eyeball("Eye" .. name, 1.35, CFrame.new(sx * 0.95, 7.75, 1.12).Position, { parent = lid, dir = V(0, 0.16, -1), lid = SHADE, lidRole = "Belly" })
		kit:blob("Brow" .. name, V(1.3, 0.34, 0.4), CFrame.new(sx * 0.95, 8.62, 1.2) * rot(-9, 0, -sx * 10), SHADE, { role = "Belly", parent = lid })
		kit:blob("Cheek" .. name, V(0.8, 0.5, 0.25), CFrame.new(sx * 1.4, 6.75, 1.25) * rot(-9, 0, 0), rgb(255, 170, 190), { role = "Detail", parent = lid })
	end
	-- Brazos de tubería que salen de la cisterna: el derecho sostiene el desatascador.
	local handL, handR = V(-3.3, 5.2, 1.7), V(3.3, 7.3, 1.7)
	local armL = kit:limb("ArmL", V(-1.8, 6.3, 2.5), handL, 0.32, STEEL, { role = "Accent", parent = tank, joint = "ArmL" })
	kit:blob("HandL", V(0.85, 0.85, 0.85), handL, PORCELAIN, { role = "Body", parent = armL })
	local armR = kit:limb("ArmR", V(1.8, 6.5, 2.5), handR, 0.32, STEEL, { role = "Accent", parent = tank, joint = "ArmR" })
	kit:blob("HandR", V(0.85, 0.85, 0.85), handR, PORCELAIN, { role = "Body", parent = armR })
	kit:limb("PlungerStick", handR - V(0.05, 0.5, 0), handR + V(0.25, 2.3, 0), 0.26, WOOD, { role = "Accent", parent = armR, pivot = handR })
	kit:blob("PlungerCup", V(1.4, 0.9, 1.4), handR + V(0.3, 2.6, 0), RED, { role = "Detail", parent = armR })
	-- Evolución: corona (etapa 2) y capa real (etapa 3).
	for i = -1, 1 do
		kit:blob("Crown" .. i, V(0.6, i == 0 and 1.3 or 1.0, 0.6), CFrame.new(i * 0.85, 9.85 - math.abs(i) * 0.12, 1.2) * rot(-9, 0, -i * 12), GOLD, { role = "Detail", material = Enum.Material.Metal, reflectance = 0.3, parent = lid, stage = 2 })
	end
	kit:blob("Cape", V(4.6, 5.2, 0.6), CFrame.new(0, 5.1, 3.95) * rot(12, 0, 0), RED, { role = "Accent", parent = tank, stage = 3 })

	kit:anchor("Mouth", V(0, 5.1, -2.7))
	kit:anchor("Head", V(0, 7.6, 0.6))
	kit:anchor("Top", V(0, 10.4, 1.4))
	kit:anchor("AuraAnchor", V(0, 5.0, 0.6))
	kit:anchor("Ground", V(0, 0.05, 0), kit.root)
	return { radius = 3.3, height = 10.0, center = V(0, 5.0, 0.6) }
end

-- Idle: contonea las caderas con aire de superioridad y agita el desatascador.
function Toiletini.idle(v, t)
	local wig = math.sin(t * 2.4)
	v:pose("Torso", CFrame.new(0, math.sin(t * 2.4 * 2) * 0.04, 0) * rot(0, wig * 6, wig * 2))
	v:pose("LegL", rot(wig * 10, 0, 0))
	v:pose("LegR", rot(-wig * 10, 0, 0))
	v:pose("ArmL", rot(0, 0, math.sin(t * 2.4) * 12))
	v:pose("ArmR", rot(math.sin(t * 5) * 8, 0, math.sin(t * 2.4) * 10))
	local nod = Anim.window(t, 5, 0.6)
	if nod then
		v:pose("Jaw", rot(-math.sin(nod * math.pi) * 22, 0, 0))
	else
		v:pose("Jaw", rot(math.sin(t * 1.2) * 3, 0, 0))
	end
end

function Toiletini.eat(v, a)
	local open = Anim.chomp(a, 2)
	-- La tapa cae sobre la taza (mordisco) y vuelve a subir.
	v:pose("Jaw", rot(-(1 - open) * 62 * Anim.bump(a, 0.12), 0, 0))
	v:pose("ArmL", rot(0, 0, -40 * open))
	v:pose("ArmR", rot(0, 0, 30 * open))
	v:pose("Torso", CFrame.new(0, 0.2 * open, 0), true)
end

-- Satisfacción: tira de la cadena, orgulloso.
function Toiletini.happy(v, a)
	local up = Anim.bump(a, 0.25)
	v:pose("ArmR", rot(0, 0, 55 * up), true)
	v:pose("Jaw", rot(8 * up, 0, 0), true)
	v:pose("Torso", CFrame.new(0, math.abs(math.sin(a * math.pi * 3)) * 0.3 * (1 - a), 0), true)
end

return Toiletini
