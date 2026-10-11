-- GOBBLO — bola verde que es casi toda boca, con ojos saltones sobre antenas.
local Anim = require(script.Parent.Parent.Anim)
local V = Vector3.new
local rgb = Color3.fromRGB
local rot = Anim.rot

local GREEN = rgb(92, 204, 96)
local DARK = rgb(52, 150, 70)
local BELLY = rgb(176, 238, 146)
local WHITE = rgb(252, 252, 246)

local Gobblo = { unit = 0.85 }

function Gobblo.build(kit)
	kit:ball("Body", 4.6, V(0, 2.5, 0), GREEN, { role = "Body", shadow = true })
	kit:ball("Belly", 3.6, V(0, 2.1, -0.75), BELLY, { role = "Belly" })
	kit:ball("MouthCavity", 2.9, V(0, 2.35, -1.38), rgb(96, 22, 34), { role = "Mouth" })
	-- Labio superior y dientes superiores (fijos)
	kit:cyl("UpperLip", 0.7, 3.3, CFrame.new(0, 3.38, -2.05) * rot(0, 0, 90), DARK, { role = "Accent" })
	for i, x in ipairs({ -1.05, -0.35, 0.35, 1.05 }) do
		kit:block("ToothTop" .. i, V(0.48, 0.62, 0.32), V(x, 3.0, -2.42), WHITE, { role = "Teeth" })
	end
	-- Mandíbula articulada
	local jaw = kit:cyl("Jaw", 0.85, 3.1, CFrame.new(0, 1.25, -2.05) * rot(0, 0, 90), DARK, {
		role = "Accent", joint = "Jaw", pivot = V(0, 1.7, -0.6),
	})
	kit:block("Tongue", V(1.4, 0.3, 1.7), V(0, 1.55, -2.15), rgb(255, 120, 150), { role = "Tongue", parent = jaw })
	kit:block("ToothBottomL", V(0.45, 0.5, 0.3), V(-0.75, 1.8, -2.38), WHITE, { role = "Teeth", parent = jaw })
	kit:block("ToothBottomR", V(0.45, 0.5, 0.3), V(0.75, 1.8, -2.38), WHITE, { role = "Teeth", parent = jaw })
	-- Antenas con ojos
	for _, side in ipairs({ { "L", -1 }, { "R", 1 } }) do
		local name, sx = side[1], side[2]
		local stalk = kit:cyl("Stalk" .. name, 0.45, 1.5, V(sx * 1.0, 5.15, -0.4), DARK, {
			role = "Accent", joint = "Eye" .. name, pivot = V(sx * 1.0, 4.4, -0.4),
		})
		kit:eye("Eye" .. name, 1.3, V(sx * 1.0, 6.15, -0.55), { parent = stalk })
		kit:ball("Arm" .. name, 0.95, V(sx * 2.45, 2.3, -0.5), DARK, {
			role = "Accent", joint = "Arm" .. name, pivot = V(sx * 2.0, 2.6, -0.2),
		})
		kit:cyl("Foot" .. name, 1.5, 0.5, V(sx * 1.1, 0.25, -0.4), DARK, { role = "Accent" })
	end
	-- Manchas
	kit:ball("Spot1", 0.75, V(0.9, 4.35, 0.9), DARK, { role = "Detail" })
	kit:ball("Spot2", 0.6, V(-1.25, 3.7, 1.45), DARK, { role = "Detail" })
	kit:ball("Spot3", 0.7, V(0.25, 3.85, 1.8), DARK, { role = "Detail" })

	kit:anchor("Mouth", V(0, 2.3, -2.9))
	kit:anchor("Head", V(0, 4.3, -1))
	kit:anchor("Top", V(0, 7, 0))
	kit:anchor("AuraAnchor", V(0, 2.9, 0))
	kit:anchor("Ground", V(0, 0.05, 0), kit.root)
	return { radius = 2.9, height = 6.9, center = V(0, 2.9, 0) }
end

-- Idle "Bounce": rebota como una pelota contenta.
function Gobblo.idle(v, t)
	local bounce = math.abs(math.sin(t * 3))
	v:pose("Body", CFrame.new(0, bounce * 0.35, 0) * rot(math.sin(t * 3) * 2, 0, math.sin(t * 1.5) * 3))
	v:pose("Jaw", rot(-6 - bounce * 8, 0, 0))
	v:pose("EyeL", rot(math.sin(t * 3 - 0.6) * 9, 0, math.sin(t * 1.5 - 0.5) * 8))
	v:pose("EyeR", rot(math.sin(t * 3 - 0.9) * 9, 0, math.sin(t * 1.5 - 0.8) * 8))
	v:pose("ArmL", rot(0, 0, -bounce * 30))
	v:pose("ArmR", rot(0, 0, bounce * 30))
end

function Gobblo.eat(v, a)
	local open = Anim.chomp(a, 3)
	v:pose("Body", rot(-10 * Anim.bump(a, 0.2), 0, 0), true)
	v:pose("Jaw", rot(-6 - open * 42, 0, 0))
	v:pose("ArmL", rot(0, 0, -50 * open))
	v:pose("ArmR", rot(0, 0, 50 * open))
end

return Gobblo
