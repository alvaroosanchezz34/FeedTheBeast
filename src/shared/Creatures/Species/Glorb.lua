-- GLORB — una medusa-orbe flotante y translúcida con un ojo enorme, ojos extra y tentáculos.
local Anim = require(script.Parent.Parent.Anim)
local V = Vector3.new
local rgb = Color3.fromRGB
local rot = Anim.rot

local SHELL = rgb(152, 92, 232)
local CORE = rgb(80, 232, 212)
local TENT = rgb(120, 70, 204)
local IRIS = rgb(255, 152, 40)

local Glorb = { unit = 0.8 }

function Glorb.build(kit)
	local shell = kit:ball("Shell", 4.4, V(0, 4.6, 0), SHELL, { role = "Body", material = Enum.Material.Glass, transparency = 0.3, shadow = true })
	kit:ball("Core", 2.5, V(0, 4.5, 0.2), CORE, { role = "Belly", material = Enum.Material.Neon, parent = shell })
	-- Ojo principal
	local eye = kit:ball("EyeMain", 2.2, V(0, 4.85, -1.45), rgb(250, 250, 250), {
		role = "Eye", parent = shell, joint = "EyeMain",
	})
	kit:ball("Iris", 1.35, V(0, 4.85, -2.12), IRIS, { role = "Pupil", parent = eye })
	kit:ball("Pupil", 0.72, V(0, 4.85, -2.58), rgb(15, 15, 20), { role = "Pupil", parent = eye })
	kit:ball("Glint", 0.3, V(0.3, 5.15, -2.72), rgb(255, 255, 255), { role = "Pupil", parent = eye, material = Enum.Material.Neon })
	-- Boquita con colmillos
	kit:block("Mouth", V(1.5, 0.28, 0.3), V(0, 3.42, -1.9), rgb(60, 20, 70), { role = "Mouth", parent = shell })
	kit:block("LowerLip", V(1.3, 0.3, 0.35), V(0, 3.12, -1.82), TENT, {
		role = "Accent", parent = shell, joint = "Jaw", pivot = V(0, 3.3, -1.4),
	})
	for i, x in ipairs({ -0.45, 0, 0.45 }) do
		kit:block("Fang" .. i, V(0.22, 0.36, 0.2), V(x, 3.32, -2.02), rgb(252, 252, 246), { role = "Teeth", parent = shell })
	end
	-- Ojos sobre antenas
	local stalks = { { "L", V(-1.25, 7.0, 0), -22 }, { "Top", V(0, 7.35, 0.35), 0 }, { "R", V(1.25, 7.0, 0), 22 } }
	for _, def in ipairs(stalks) do
		local name, pos, tilt = def[1], def[2], def[3]
		local base = pos - V(0, 0.75, 0)
		local stalk = kit:cyl("Stalk" .. name, 0.3, 1.3, CFrame.new(pos) * rot(0, 0, -tilt), TENT, {
			role = "Accent", parent = shell, joint = "Eye" .. name, pivot = base,
		})
		local tip = (CFrame.new(pos) * rot(0, 0, -tilt) * CFrame.new(0, 0.95, 0)).Position
		kit:eye("StalkEye" .. name, 0.82, tip, { parent = stalk })
	end
	-- Aletas laterales
	for _, side in ipairs({ { "L", -1 }, { "R", 1 } }) do
		local name, sx = side[1], side[2]
		kit:wedge("Fin" .. name, V(0.3, 1.2, 1.5), CFrame.new(sx * 2.45, 4.6, 0.5) * rot(0, sx * 90, sx * 90), TENT, {
			role = "Accent", parent = shell, joint = "Arm" .. name, pivot = V(sx * 2.1, 4.6, 0.3),
		})
	end
	-- Tentáculos
	for i = 1, 5 do
		local angle = (i - 1) / 5 * math.pi * 2 + 0.3
		local x, z = math.sin(angle) * 1.3, math.cos(angle) * 1.3
		local top = kit:ball("Tent" .. i .. "a", 1.0, V(x, 2.35, z), TENT, {
			role = "Accent", parent = shell, joint = "Tent" .. i, pivot = V(x * 0.85, 2.9, z * 0.85),
		})
		kit:ball("Tent" .. i .. "b", 0.75, V(x * 1.08, 1.55, z * 1.08), TENT, { role = "Accent", parent = top })
		kit:ball("Tent" .. i .. "c", 0.5, V(x * 1.14, 0.9, z * 1.14), CORE, { role = "Detail", parent = top, material = Enum.Material.Neon })
	end

	kit:anchor("Mouth", V(0, 3.4, -2.4))
	kit:anchor("Head", V(0, 5.6, -1.2))
	kit:anchor("Top", V(0, 8.6, 0))
	kit:anchor("AuraAnchor", V(0, 4.5, 0))
	kit:anchor("Ground", V(0, 0.05, 0), kit.root)
	return { radius = 3, height = 8.5, center = V(0, 4.5, 0) }
end

-- Idle "Float": flota, gira despacio, mira alrededor y ondula los tentáculos.
function Glorb.idle(v, t)
	v:pose("Body", CFrame.new(0, math.sin(t * 1.4) * 0.4, 0) * rot(math.sin(t * 0.9) * 3, math.sin(t * 0.5) * 12, 0))
	v:pose("EyeMain", rot(Anim.wobble(t * 0.8, 1) * 10, Anim.wobble(t * 0.8, 4) * 16, 0))
	v:pose("EyeL", rot(math.sin(t * 2.1) * 10, 0, math.sin(t * 1.4 + 1) * 12))
	v:pose("EyeR", rot(math.sin(t * 2.1 + 2) * 10, 0, math.sin(t * 1.4 + 3) * 12))
	v:pose("EyeTop", rot(math.sin(t * 1.9 + 4) * 12, 0, math.sin(t * 1.6) * 8))
	v:pose("ArmL", rot(0, 0, math.sin(t * 2.8) * 16))
	v:pose("ArmR", rot(0, 0, -math.sin(t * 2.8) * 16))
	for i = 1, 5 do
		local phase = t * 2 + i * 1.3
		v:pose("Tent" .. i, rot(math.sin(phase) * 16, 0, math.cos(phase * 0.8) * 14))
	end
	v:pose("Jaw", rot(-math.max(0, math.sin(t * 1.1)) * 8, 0, 0))
end

function Glorb.eat(v, a)
	local open = Anim.chomp(a, 3)
	local lean = Anim.bump(a, 0.2)
	v:pose("Body", rot(-16 * lean, 0, 0), true)
	v:pose("Jaw", rot(-open * 40, 0, 0))
	v:pose("EyeMain", rot(-14 * lean, 0, 0))
	for i = 1, 5 do
		v:pose("Tent" .. i, rot(-30 * open, 0, 0), true)
	end
end

return Glorb
