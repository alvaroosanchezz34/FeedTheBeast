-- BANANOSAUR — un dinosaurio con cuerpo de plátano curvado, cola y brazos de piel de plátano.
local Anim = require(script.Parent.Parent.Anim)
local V = Vector3.new
local rgb = Color3.fromRGB
local rot = Anim.rot

local YELLOW = rgb(255, 222, 64)
local DEEP = rgb(232, 184, 40)
local PALE = rgb(255, 242, 176)
local BROWN = rgb(112, 72, 34)
local LEAF = rgb(96, 176, 74)
local WHITE = rgb(252, 252, 246)

local Bananosaur = { unit = 0.8 }

function Bananosaur.build(kit)
	-- Patas
	for _, side in ipairs({ { "L", -1 }, { "R", 1 } }) do
		local name, sx = side[1], side[2]
		local leg = kit:cyl("Leg" .. name, 1.1, 1.9, V(sx * 0.9, 0.95, 0.2), DEEP, {
			role = "Accent", joint = "Leg" .. name, pivot = V(sx * 0.9, 1.9, 0.2),
		})
		kit:block("Foot" .. name, V(1.3, 0.4, 1.9), V(sx * 0.9, 0.2, -0.3), BROWN, { role = "Detail", parent = leg })
	end
	-- Cuerpo curvado (segmentos)
	local s1 = kit:ball("Seg1", 3.0, V(0, 2.6, 0.2), YELLOW, { role = "Body", shadow = true })
	local s2 = kit:ball("Seg2", 2.8, V(0, 3.9, -0.25), YELLOW, { role = "Body", joint = "Torso", pivot = V(0, 3.0, 0), shadow = true })
	kit:ball("Seg3", 2.5, V(0, 5.0, -0.55), YELLOW, { role = "Body", parent = s2 })
	local neck = kit:ball("Neck", 2.1, V(0, 5.9, -1.0), YELLOW, { role = "Body", parent = s2 })
	kit:ball("BellyStripe", 2.4, V(0, 3.45, -0.72), PALE, { role = "Belly", parent = s2 })
	kit:ball("BellyLow", 2.3, V(0, 2.4, -0.45), PALE, { role = "Belly", parent = s1 })
	-- Cabeza articulada
	local head = kit:block("Snout", V(1.7, 1.25, 2.5), V(0, 6.75, -2.0), YELLOW, {
		role = "Body", parent = neck, joint = "Head", pivot = V(0, 6.1, -0.9),
	})
	kit:block("LowerJaw", V(1.45, 0.4, 2.1), V(0, 5.92, -2.05), DEEP, {
		role = "Accent", parent = head, joint = "Jaw", pivot = V(0, 6.1, -1.0),
	})
	kit:ball("NoseTip", 0.95, V(0, 6.85, -3.25), BROWN, { role = "Detail", parent = head })
	for i, x in ipairs({ -0.5, 0, 0.5 }) do
		kit:block("Tooth" .. i, V(0.3, 0.35, 0.3), V(x, 6.02, -3.0), WHITE, { role = "Teeth", parent = head })
	end
	kit:eye("EyeL", 1.1, V(-0.82, 7.45, -1.5), { parent = head, dir = V(-0.35, 0, -1) })
	kit:eye("EyeR", 1.1, V(0.82, 7.45, -1.5), { parent = head, dir = V(0.35, 0, -1) })
	kit:cyl("Stem", 0.5, 1.0, CFrame.new(0, 7.65, -0.95) * rot(20, 0, 0), BROWN, { role = "Detail", parent = head })
	-- Brazos de piel de plátano
	for _, side in ipairs({ { "L", -1 }, { "R", 1 } }) do
		local name, sx = side[1], side[2]
		kit:wedge("Peel" .. name, V(0.3, 1.7, 1.0), CFrame.new(sx * 1.65, 4.2, -0.45) * rot(0, 0, sx * 28), PALE, {
			role = "Accent", parent = s2, joint = "Arm" .. name, pivot = V(sx * 1.3, 4.95, -0.4),
		})
	end
	-- Cola
	local tail = kit:ball("Tail1", 1.7, V(0, 2.0, 1.6), YELLOW, { role = "Body", parent = s1, joint = "Tail", pivot = V(0, 2.2, 0.9) })
	kit:ball("Tail2", 1.2, V(0, 1.75, 2.5), YELLOW, { role = "Body", parent = tail })
	kit:ball("Tail3", 0.8, V(0, 1.65, 3.1), DEEP, { role = "Accent", parent = tail })
	kit:ball("TailTip", 0.5, V(0, 1.65, 3.5), BROWN, { role = "Detail", parent = tail })
	-- Púas dorsales
	for i = 0, 3 do
		kit:wedge("Spike" .. i, V(0.3, 0.85, 0.85), CFrame.new(0, 3.2 + i * 0.95, 1.25 - i * 0.3) * rot(-20, 180, 0), LEAF, {
			role = "Detail", parent = i == 0 and s1 or s2,
		})
	end

	kit:anchor("Mouth", V(0, 6.2, -3.3))
	kit:anchor("Head", V(0, 6.9, -1.8))
	kit:anchor("Top", V(0, 8.4, -0.8))
	kit:anchor("AuraAnchor", V(0, 3.9, 0))
	kit:anchor("Ground", V(0, 0.05, 0), kit.root)
	return { radius = 3.6, height = 8.2, center = V(0, 3.9, 0) }
end

-- Idle "Sway": se mece despacio, asiente con la cabeza y menea la cola.
function Bananosaur.idle(v, t)
	local sway = math.sin(t * 1.6)
	v:pose("Body", rot(0, 0, sway * 2.5))
	v:pose("Torso", rot(math.sin(t * 1.6 + 1) * 3, 0, sway * 4))
	v:pose("Head", rot(math.sin(t * 3.2) * 6, sway * 10, 0))
	v:pose("Jaw", rot(-3 - math.max(0, math.sin(t * 0.8)) * 6, 0, 0))
	v:pose("Tail", rot(0, math.sin(t * 2.4) * 22, 0))
	v:pose("ArmL", rot(0, 0, math.sin(t * 3.2) * 10))
	v:pose("ArmR", rot(0, 0, -math.sin(t * 3.2 + 0.7) * 10))
end

function Bananosaur.eat(v, a)
	local open = Anim.chomp(a, 3)
	local dip = Anim.bump(a, 0.25)
	v:pose("Torso", rot(-14 * dip, 0, 0))
	v:pose("Head", rot(-18 * dip + open * 6, 0, 0))
	v:pose("Jaw", rot(-open * 34, 0, 0))
	v:pose("ArmL", rot(0, 0, -30 * open))
	v:pose("ArmR", rot(0, 0, 30 * open))
end

return Bananosaur
