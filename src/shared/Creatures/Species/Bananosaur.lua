-- BANANOSAUR — un tiranosaurio con piel de plátano: cabezón, brazos ridículos, cola larga con
-- la punta marrón y un collar de cáscara a medio pelar.
local Anim = require(script.Parent.Parent.Anim)
local V = Vector3.new
local rgb = Color3.fromRGB
local rot = Anim.rot

local YELLOW = rgb(255, 220, 66)
local DEEP = rgb(236, 184, 44)
local PALE = rgb(255, 244, 186)
local BROWN = rgb(116, 76, 38)
local LEAF = rgb(104, 184, 80)
local MOUTH = rgb(120, 30, 44)
local WHITE = rgb(252, 252, 246)

local Bananosaur = { unit = 0.8 }

function Bananosaur.build(kit)
	for _, side in ipairs({ { "L", -1 }, { "R", 1 } }) do
		local name, sx = side[1], side[2]
		local thigh = kit:blob("Thigh" .. name, V(1.7, 2.6, 2.1), V(sx * 1.2, 1.6, 0.45), DEEP, { role = "Accent", joint = "Leg" .. name, pivot = V(sx * 1.2, 2.6, 0.45) })
		kit:blob("Foot" .. name, V(1.6, 0.8, 2.5), V(sx * 1.2, 0.4, -0.3), BROWN, { role = "Detail", parent = thigh })
	end
	local torso = kit:blob("Torso", V(3.4, 4.2, 3.9), CFrame.new(0, 3.6, 0.35) * rot(-12, 0, 0), YELLOW, { role = "Body", shadow = true, joint = "Torso", pivot = V(0, 2.2, 0.4) })
	kit:blob("Belly", V(2.4, 3.2, 1.5), CFrame.new(0, 3.35, -1.05) * rot(-12, 0, 0), PALE, { role = "Belly", parent = torso })
	-- Cola: tres tramos que se estrechan, con la punta marrón del plátano.
	local tail = kit:blob("Tail1", V(2.1, 1.9, 3.0), CFrame.new(0, 2.7, 2.35) * rot(10, 0, 0), YELLOW, { role = "Body", parent = torso, joint = "Tail", pivot = V(0, 2.7, 1.3) })
	local tail2 = kit:blob("Tail2", V(1.4, 1.3, 2.4), CFrame.new(0, 3.15, 4.15) * rot(18, 0, 0), YELLOW, { role = "Body", parent = tail, joint = "Tail2", pivot = V(0, 2.95, 3.3) })
	kit:blob("TailTip", V(0.85, 0.8, 1.2), CFrame.new(0, 3.65, 5.25) * rot(24, 0, 0), BROWN, { role = "Detail", parent = tail2 })
	local neck = kit:blob("Neck", V(2.3, 2.6, 2.3), V(0, 5.45, -0.55), YELLOW, { role = "Body", parent = torso })
	-- Cabeza grande con hocico y mandíbula articulada.
	local head = kit:blob("Head", V(2.9, 2.6, 4.0), V(0, 6.75, -1.75), YELLOW, { role = "Body", parent = neck, joint = "Head", pivot = V(0, 6.1, -0.6), shadow = true })
	kit:blob("SnoutTip", V(1.7, 1.3, 1.1), V(0, 6.8, -3.4), BROWN, { role = "Detail", parent = head })
	kit:blob("Mouth", V(2.2, 0.8, 3.2), V(0, 6.0, -1.9), MOUTH, { role = "Mouth", parent = head })
	for i, def in ipairs({ { -0.75, -3.05 }, { 0.75, -3.05 }, { -0.98, -2.3 }, { 0.98, -2.3 }, { -1.02, -1.5 }, { 1.02, -1.5 } }) do
		kit:blob("Tooth" .. i, V(0.36, 0.6, 0.36), V(def[1], 5.85, def[2]), WHITE, { role = "Teeth", parent = head })
	end
	local jaw = kit:blob("Jaw", V(2.3, 0.9, 3.4), V(0, 5.55, -1.85), DEEP, { role = "Accent", parent = head, joint = "Jaw", pivot = V(0, 5.9, -0.5) })
	kit:blob("Tongue", V(1.1, 0.35, 2.0), V(0, 5.95, -2.0), rgb(255, 124, 150), { role = "Tongue", parent = jaw })
	for _, side in ipairs({ { "L", -1 }, { "R", 1 } }) do
		local name, sx = side[1], side[2]
		kit:eyeball("Eye" .. name, 1.15, V(sx * 1.08, 7.35, -1.55), { parent = head, dir = V(sx * 0.8, 0.25, -0.7), lid = YELLOW })
		kit:blob("Arm" .. name, V(0.55, 0.55, 1.3), CFrame.new(sx * 1.25, 4.2, -1.55) * rot(25, 0, 0), DEEP, { role = "Accent", parent = torso, joint = "Arm" .. name, pivot = V(sx * 1.25, 4.4, -1.0) })
		-- Cáscara pelada cayendo sobre los hombros.
		kit:blob("Peel" .. name, V(1.9, 0.4, 2.3), CFrame.new(sx * 1.75, 4.95, -0.2) * rot(0, 0, -sx * 48), PALE, { role = "Accent", parent = torso, joint = "Peel" .. name, pivot = V(sx * 1.1, 5.5, -0.2) })
	end
	kit:blob("PeelBack", V(2.0, 0.4, 2.2), CFrame.new(0, 5.05, 1.55) * rot(-50, 0, 0), PALE, { role = "Accent", parent = torso })
	kit:cyl("Stem", 0.5, 0.9, CFrame.new(0, 8.15, -1.2) * rot(18, 0, 0), BROWN, { role = "Detail", parent = head })
	for i = 0, 2 do
		kit:blob("Spike" .. i, V(0.45, 1.0, 1.1), CFrame.new(0, 5.05 - i * 0.95, 2.05 + i * 0.25) * rot(-35, 0, 0), LEAF, { role = "Detail", parent = torso })
	end
	-- Evolución: cresta en la cabeza (etapa 2) y cuerno en el hocico (etapa 3).
	for i = 0, 2 do
		kit:blob("Crest" .. i, V(0.45, 1.1 - i * 0.2, 1.0), CFrame.new(0, 8.1 - i * 0.25, -0.5 + i * 0.75) * rot(-30, 0, 0), LEAF, { role = "Detail", parent = head, stage = 2 })
	end
	kit:blob("Horn", V(0.6, 1.4, 0.6), CFrame.new(0, 7.75, -3.05) * rot(-20, 0, 0), PALE, { role = "Detail", parent = head, stage = 3 })

	kit:anchor("Mouth", V(0, 6.0, -3.9))
	kit:anchor("Head", V(0, 6.9, -2.0))
	kit:anchor("Top", V(0, 8.9, -1))
	kit:anchor("AuraAnchor", V(0, 3.9, 0.3))
	kit:anchor("Ground", V(0, 0.05, 0), kit.root)
	return { radius = 3.4, height = 8.6, center = V(0, 3.9, 0.3) }
end

-- Idle: se mece, olfatea con la cabeza y la cola le sirve de contrapeso.
function Bananosaur.idle(v, t)
	local sway = math.sin(t * 1.5)
	v:pose("Torso", CFrame.new(0, math.sin(t * 2.1) * 0.06, 0) * rot(math.sin(t * 1.5 + 1) * 2, 0, sway * 2.5))
	v:pose("Head", rot(math.sin(t * 2.6) * 5, sway * 12, 0))
	v:pose("Jaw", rot(-2 - math.max(0, math.sin(t * 0.9)) * 5, 0, 0))
	v:pose("Tail", rot(0, math.sin(t * 2.2) * 18, 0))
	v:pose("Tail2", rot(0, math.sin(t * 2.2 - 0.9) * 22, 0))
	v:pose("ArmL", rot(math.sin(t * 4) * 14, 0, 0))
	v:pose("ArmR", rot(math.sin(t * 4 + 1.3) * 14, 0, 0))
	v:pose("PeelL", rot(0, 0, math.sin(t * 2.1) * 5))
	v:pose("PeelR", rot(0, 0, -math.sin(t * 2.1) * 5))
end

function Bananosaur.eat(v, a)
	local open = Anim.chomp(a, 3)
	local dip = Anim.bump(a, 0.25)
	v:pose("Torso", rot(-10 * dip, 0, 0), true)
	v:pose("Head", rot(-14 * dip + open * 8, 0, 0))
	v:pose("Jaw", rot(-open * 32, 0, 0))
	v:pose("ArmL", rot(-40 * open, 0, 0))
	v:pose("ArmR", rot(-40 * open, 0, 0))
end

-- Satisfacción: rugido de felicidad hacia el cielo.
function Bananosaur.happy(v, a)
	local up = Anim.bump(a, 0.3)
	v:pose("Head", rot(26 * up, 0, 0), true)
	v:pose("Jaw", rot(-28 * up, 0, 0))
	v:pose("Tail", rot(10 * up, math.sin(a * math.pi * 6) * 25, 0))
	v:pose("PeelL", rot(0, 0, 25 * up), true)
	v:pose("PeelR", rot(0, 0, -25 * up), true)
end

return Bananosaur
