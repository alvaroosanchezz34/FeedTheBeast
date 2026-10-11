-- GOBBLO — una rana-bola glotona: un solo cuerpo redondo, ojos saltones integrados en la cabeza
-- y una boca enorme con labio inferior articulado.
local Anim = require(script.Parent.Parent.Anim)
local V = Vector3.new
local rgb = Color3.fromRGB
local rot = Anim.rot

local GREEN = rgb(104, 208, 96)
local DARK = rgb(58, 156, 78)
local BELLY = rgb(196, 240, 150)
local MOUTH = rgb(92, 20, 36)
local WHITE = rgb(252, 252, 246)
local HORN = rgb(250, 236, 190)

local Gobblo = { unit = 0.9 }

function Gobblo.build(kit)
	for _, side in ipairs({ { "L", -1 }, { "R", 1 } }) do
		local name, sx = side[1], side[2]
		kit:blob("Foot" .. name, V(1.7, 0.8, 2.3), V(sx * 1.25, 0.4, -0.75), DARK, { role = "Accent" })
	end
	local body = kit:blob("Body", V(5.0, 4.4, 4.6), V(0, 2.55, 0), GREEN, { role = "Body", shadow = true, joint = "Torso", pivot = V(0, 0.5, 0) })
	kit:blob("Belly", V(3.4, 2.2, 1.2), V(0, 1.45, -1.25), BELLY, { role = "Belly", parent = body })
	-- Boca: cavidad oscura hundida en el cuerpo; el labio inferior la tapa por abajo.
	kit:blob("Mouth", V(3.5, 1.9, 1.6), V(0, 2.55, -1.62), MOUTH, { role = "Mouth", parent = body })
	kit:block("ToothL", V(0.55, 0.62, 0.3), V(-0.34, 3.0, -2.26), WHITE, { role = "Teeth", parent = body })
	kit:block("ToothR", V(0.55, 0.62, 0.3), V(0.34, 3.0, -2.26), WHITE, { role = "Teeth", parent = body })
	local jaw = kit:blob("Jaw", V(3.9, 1.5, 2.3), V(0, 1.82, -1.42), GREEN, { role = "Body", parent = body, joint = "Jaw", pivot = V(0, 2.1, -0.2) })
	kit:blob("Tongue", V(1.9, 0.6, 1.5), V(0, 2.5, -1.95), rgb(255, 122, 150), { role = "Tongue", parent = jaw })
	-- Ojos: dos bultos del propio cuerpo con el globo ocular hundido delante.
	for _, side in ipairs({ { "L", -1 }, { "R", 1 } }) do
		local name, sx = side[1], side[2]
		local bump = kit:blob("EyeBump" .. name, V(2.0, 2.0, 2.0), V(sx * 1.15, 4.3, -0.7), GREEN, { role = "Body", parent = body })
		kit:eyeball("Eye" .. name, 1.55, V(sx * 1.18, 4.42, -1.32), { parent = bump, dir = V(sx * 0.12, 0.08, -1), lid = GREEN })
		kit:blob("Arm" .. name, V(1.2, 0.85, 1.0), V(sx * 2.55, 2.15, -0.55), DARK, { role = "Accent", parent = body, joint = "Arm" .. name, pivot = V(sx * 2.1, 2.3, -0.3) })
	end
	-- Manchas en el lomo (hundidas en la superficie).
	kit:blob("Spot1", V(1.1, 0.5, 1.1), V(0.95, 4.28, 0.75), DARK, { role = "Detail", parent = body })
	kit:blob("Spot2", V(0.8, 0.5, 0.8), V(-1.1, 3.9, 1.35), DARK, { role = "Detail", parent = body })
	kit:blob("Spot3", V(0.9, 0.5, 0.9), V(0.1, 3.75, 1.85), DARK, { role = "Detail", parent = body })
	-- Evolución: cuernos (etapa 2) y cresta dorsal (etapa 3).
	for _, sx in ipairs({ -1, 1 }) do
		kit:blob("Horn" .. sx, V(0.5, 1.3, 0.5), CFrame.new(sx * 0.35, 5.0, 0.2) * rot(-12, 0, -sx * 14), HORN, { role = "Detail", parent = body, stage = 2 })
	end
	for i = 0, 2 do
		kit:blob("Crest" .. i, V(0.5, 1.1 - i * 0.2, 0.9), CFrame.new(0, 4.55 - i * 0.55, 0.95 + i * 0.6) * rot(-25 - i * 18, 0, 0), HORN, { role = "Detail", parent = body, stage = 3 })
	end

	kit:anchor("Mouth", V(0, 2.5, -2.7))
	kit:anchor("Head", V(0, 3.7, -1.5))
	kit:anchor("Top", V(0, 5.6, 0))
	kit:anchor("AuraAnchor", V(0, 2.6, 0))
	kit:anchor("Ground", V(0, 0.05, 0), kit.root)
	return { radius = 2.8, height = 5.4, center = V(0, 2.6, 0) }
end

-- Idle: respira, se balancea y de vez en cuando da un saltito de impaciencia.
function Gobblo.idle(v, t)
	local breath = math.sin(t * 2.2)
	local hop = Anim.window(t, 4.6, 0.5)
	local lift = hop and math.sin(hop * math.pi) * 0.5 or 0
	v:pose("Torso", CFrame.new(0, breath * 0.06 + lift, 0) * rot(breath * 1.2, 0, math.sin(t * 1.1) * 2))
	v:pose("Jaw", rot(-3 - math.max(0, breath) * 3, 0, 0))
	v:pose("ArmL", rot(0, 0, -8 - breath * 6 - lift * 40))
	v:pose("ArmR", rot(0, 0, 8 + breath * 6 + lift * 40))
end

function Gobblo.eat(v, a)
	local open = Anim.chomp(a, 3)
	v:pose("Torso", CFrame.new(0, 0, -0.25 * Anim.bump(a, 0.15)) * rot(-8 * Anim.bump(a, 0.2), 0, 0), true)
	v:pose("Jaw", rot(-4 - open * 24, 0, 0))
	v:pose("ArmL", rot(0, 0, -45 * open))
	v:pose("ArmR", rot(0, 0, 45 * open))
end

-- Satisfacción tras comer: bote doble con los brazos arriba.
function Gobblo.happy(v, a)
	local bounce = math.abs(math.sin(a * math.pi * 2)) * (1 - a)
	v:pose("Torso", CFrame.new(0, bounce * 0.7, 0) * rot(0, 0, math.sin(a * math.pi * 4) * 5 * (1 - a)), true)
	v:pose("ArmL", rot(0, 0, -70 * bounce), true)
	v:pose("ArmR", rot(0, 0, 70 * bounce), true)
end

return Gobblo
