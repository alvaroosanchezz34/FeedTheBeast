-- CHOMPITO — todo mandíbula: dos mitades redondeadas con una fila de dientes, cejas de mal genio
-- y unas patitas con zapatillas que apenas lo sostienen.
local Anim = require(script.Parent.Parent.Anim)
local V = Vector3.new
local rgb = Color3.fromRGB
local rot = Anim.rot

local ORANGE = rgb(244, 108, 56)
local SHADE = rgb(206, 74, 44)
local DARK = rgb(112, 42, 40)
local MOUTH = rgb(110, 22, 40)
local WHITE = rgb(252, 252, 246)
local BLUE = rgb(62, 124, 232)
local GOLD = rgb(255, 204, 70)

local Chompito = { unit = 0.9 }

function Chompito.build(kit)
	for _, side in ipairs({ { "L", -1 }, { "R", 1 } }) do
		local name, sx = side[1], side[2]
		local leg = kit:cyl("Leg" .. name, 0.5, 1.4, V(sx * 1.05, 1.0, 0.1), DARK, { role = "Accent", joint = "Leg" .. name, pivot = V(sx * 1.05, 1.7, 0.1) })
		kit:blob("Shoe" .. name, V(1.4, 0.8, 2.1), V(sx * 1.05, 0.4, -0.35), BLUE, { role = "Detail", parent = leg })
	end
	local lower = kit:blob("LowerJaw", V(4.8, 2.3, 4.2), V(0, 2.45, 0), SHADE, { role = "Belly", shadow = true, joint = "Torso", pivot = V(0, 1.4, 0) })
	kit:blob("Mouth", V(4.2, 1.2, 3.7), V(0, 3.15, -0.25), MOUTH, { role = "Mouth", parent = lower })
	kit:blob("Tongue", V(1.9, 0.5, 2.4), V(0, 3.3, -0.8), rgb(255, 120, 150), { role = "Tongue", parent = lower })
	local upper = kit:blob("UpperJaw", V(5.0, 2.9, 4.4), V(0, 4.25, 0), ORANGE, { role = "Body", parent = lower, joint = "Jaw", pivot = V(0, 3.3, 1.7), shadow = true })
	-- Dientes sobre el arco frontal: los de arriba cuelgan de la mandíbula superior.
	for i, angle in ipairs({ -56, -34, -11, 11, 34, 56 }) do
		local a = math.rad(angle)
		local x, z = math.sin(a) * 2.02, -math.cos(a) * 1.82 - 0.2
		kit:blob("ToothUp" .. i, V(0.62, 0.95, 0.5), CFrame.new(x, 3.2, z) * CFrame.Angles(0, -a, 0), WHITE, { role = "Teeth", parent = upper })
	end
	for i, angle in ipairs({ -45, -22, 0, 22, 45 }) do
		local a = math.rad(angle)
		local x, z = math.sin(a) * 1.95, -math.cos(a) * 1.75 - 0.2
		kit:blob("ToothLow" .. i, V(0.56, 0.8, 0.46), CFrame.new(x, 3.05, z) * CFrame.Angles(0, -a, 0), WHITE, { role = "Teeth", parent = lower })
	end
	for _, side in ipairs({ { "L", -1 }, { "R", 1 } }) do
		local name, sx = side[1], side[2]
		kit:eyeball("Eye" .. name, 1.3, V(sx * 0.95, 4.95, -1.42), { parent = upper, dir = V(sx * 0.1, 0.38, -1), lid = ORANGE })
		kit:blob("Brow" .. name, V(1.4, 0.4, 0.6), CFrame.new(sx * 0.98, 5.6, -1.35) * rot(22, 0, sx * 24), DARK, { role = "Accent", parent = upper })
	end
	kit:blob("Fin", V(0.5, 1.3, 1.6), CFrame.new(0, 3.6, 2.2) * rot(-25, 0, 0), DARK, { role = "Accent", parent = lower, joint = "Tail", pivot = V(0, 3.2, 1.7) })
	-- Evolución: cresta punk (etapa 2) y diente de oro (etapa 3).
	for i = 0, 2 do
		kit:blob("Mohawk" .. i, V(0.5, 1.2 - i * 0.15, 0.9), CFrame.new(0, 5.75 - i * 0.2, -0.5 + i * 0.85) * rot(-15 - i * 14, 0, 0), DARK, { role = "Accent", parent = upper, stage = 2 })
	end
	kit:blob("GoldTooth", V(0.7, 1.05, 0.56), V(0, 3.12, -2.0), GOLD, { role = "Detail", parent = upper, material = Enum.Material.Metal, reflectance = 0.3, stage = 3 })

	kit:anchor("Mouth", V(0, 3.2, -2.5))
	kit:anchor("Head", V(0, 4.6, -0.8))
	kit:anchor("Top", V(0, 6.2, 0))
	kit:anchor("AuraAnchor", V(0, 3.4, 0))
	kit:anchor("Ground", V(0, 0.05, 0), kit.root)
	return { radius = 2.7, height = 5.9, center = V(0, 3.4, 0) }
end

-- Idle: anadea de una pata a otra y castañetea los dientes cuando se impacienta.
function Chompito.idle(v, t)
	local step = math.sin(t * 3.6)
	v:pose("Torso", CFrame.new(0, math.abs(step) * 0.1, 0) * rot(0, 0, step * 5))
	v:pose("LegL", rot(math.max(0, step) * 20, 0, -step * 5))
	v:pose("LegR", rot(math.max(0, -step) * 20, 0, -step * 5))
	v:pose("Tail", rot(0, math.sin(t * 5) * 16, 0))
	local chatter = Anim.window(t, 3.4, 0.6)
	if chatter then
		v:pose("Jaw", rot(math.abs(math.sin(chatter * math.pi * 4)) * 13, 0, 0))
	else
		v:pose("Jaw", rot(2 + math.sin(t * 1.8) * 1.5, 0, 0))
	end
end

function Chompito.eat(v, a)
	local open = Anim.chomp(a, 4)
	v:pose("Jaw", rot(open * 44, 0, 0))
	v:pose("Torso", CFrame.new(0, 0, -0.35 * Anim.bump(a, 0.15)) * rot(-5 * open, 0, 0), true)
end

-- Satisfacción: gira sobre sí mismo castañeteando.
function Chompito.happy(v, a)
	v:pose("Torso", CFrame.new(0, math.sin(a * math.pi) * 0.5, 0) * rot(0, a * 360, 0), true)
	v:pose("Jaw", rot(math.abs(math.sin(a * math.pi * 5)) * 16 * (1 - a), 0, 0))
end

return Chompito
