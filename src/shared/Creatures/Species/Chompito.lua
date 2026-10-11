-- CHOMPITO — unos dientes de cuerda con patas: mandíbula-trampa naranja y mal genio.
local Anim = require(script.Parent.Parent.Anim)
local V = Vector3.new
local rgb = Color3.fromRGB
local rot = Anim.rot

local ORANGE = rgb(238, 96, 52)
local DARK = rgb(120, 44, 40)
local GUM = rgb(250, 146, 156)
local WHITE = rgb(252, 252, 246)

local Chompito = { unit = 0.9 }

function Chompito.build(kit)
	-- Mandíbula inferior (fija al cuerpo)
	local lower = kit:block("LowerJaw", V(4.2, 1.1, 3.4), V(0, 2.35, -0.2), ORANGE, { role = "Body", shadow = true })
	kit:block("LowerGum", V(3.8, 0.25, 3.0), V(0, 2.98, -0.25), GUM, { role = "Mouth", parent = lower })
	kit:block("Tongue", V(1.7, 0.25, 2.3), V(0, 3.18, -0.7), rgb(255, 110, 140), { role = "Tongue", parent = lower })
	for i, x in ipairs({ -1.5, -0.75, 0, 0.75, 1.5 }) do
		kit:block("ToothLow" .. i, V(0.5, 0.6, 0.35), V(x, 3.35, -1.72), WHITE, { role = "Teeth", parent = lower })
	end
	for i, z in ipairs({ -0.9, 0 }) do
		kit:block("ToothLowL" .. i, V(0.35, 0.55, 0.5), V(-1.78, 3.3, z), WHITE, { role = "Teeth", parent = lower })
		kit:block("ToothLowR" .. i, V(0.35, 0.55, 0.5), V(1.78, 3.3, z), WHITE, { role = "Teeth", parent = lower })
	end
	-- Mandíbula superior articulada por detrás
	local upper = kit:block("UpperJaw", V(4.2, 1.1, 3.4), V(0, 4.4, -0.2), ORANGE, {
		role = "Body", joint = "Jaw", pivot = V(0, 3.5, 1.5), shadow = true,
	})
	kit:block("UpperGum", V(3.8, 0.25, 3.0), V(0, 3.78, -0.25), GUM, { role = "Mouth", parent = upper })
	for i, x in ipairs({ -1.125, -0.375, 0.375, 1.125 }) do
		kit:block("ToothUp" .. i, V(0.5, 0.6, 0.35), V(x, 3.6, -1.72), WHITE, { role = "Teeth", parent = upper })
	end
	-- Ojos enfadados encima
	for _, side in ipairs({ { "L", -1 }, { "R", 1 } }) do
		local name, sx = side[1], side[2]
		kit:eye("Eye" .. name, 1.1, V(sx * 0.9, 5.25, -0.9), { parent = upper })
		kit:block("Brow" .. name, V(1.25, 0.28, 0.35), CFrame.new(sx * 0.9, 5.88, -1.15) * rot(0, 0, sx * 22), DARK, {
			role = "Accent", parent = upper,
		})
		local leg = kit:cyl("Leg" .. name, 0.45, 1.6, V(sx * 1.1, 1.1, 0), DARK, {
			role = "Accent", joint = "Leg" .. name, pivot = V(sx * 1.1, 1.9, 0),
		})
		kit:block("Shoe" .. name, V(1.0, 0.5, 1.7), V(sx * 1.1, 0.25, -0.3), rgb(62, 124, 232), { role = "Detail", parent = leg })
	end
	-- Aleta trasera
	kit:wedge("Tail", V(0.4, 1.3, 1.3), CFrame.new(0, 3.2, 2.1) * rot(0, 180, 0), DARK, {
		role = "Accent", joint = "Tail", pivot = V(0, 3, 1.5),
	})
	-- Remaches decorativos
	kit:ball("RivetL", 0.5, V(-2.1, 3.5, 1.2), rgb(250, 210, 80), { role = "Detail", material = Enum.Material.Metal })
	kit:ball("RivetR", 0.5, V(2.1, 3.5, 1.2), rgb(250, 210, 80), { role = "Detail", material = Enum.Material.Metal })

	kit:anchor("Mouth", V(0, 3.5, -2.1))
	kit:anchor("Head", V(0, 4.7, -0.5))
	kit:anchor("Top", V(0, 6.3, 0))
	kit:anchor("AuraAnchor", V(0, 3.4, 0))
	kit:anchor("Ground", V(0, 0.05, 0), kit.root)
	return { radius = 2.8, height = 6.1, center = V(0, 3.4, 0) }
end

-- Idle "Waddle": se balancea de pata a pata y castañetea de vez en cuando.
function Chompito.idle(v, t)
	local step = math.sin(t * 4)
	v:pose("Body", CFrame.new(0, math.abs(step) * 0.12, 0) * rot(0, 0, step * 6))
	v:pose("LegL", rot(math.max(0, step) * 22, 0, -step * 6))
	v:pose("LegR", rot(math.max(0, -step) * 22, 0, -step * 6))
	v:pose("Tail", rot(0, math.sin(t * 6) * 18, 0))
	local chatter = Anim.window(t, 3.2, 0.55)
	if chatter then
		v:pose("Jaw", rot(math.abs(math.sin(chatter * math.pi * 4)) * 14, 0, 0))
	else
		v:pose("Jaw", rot(3 + math.sin(t * 2) * 2, 0, 0))
	end
end

function Chompito.eat(v, a)
	local open = Anim.chomp(a, 4)
	v:pose("Jaw", rot(open * 48, 0, 0))
	v:pose("Body", CFrame.new(0, 0, -0.4 * Anim.bump(a, 0.15)) * rot(-6 * open, 0, 0), true)
end

return Chompito
