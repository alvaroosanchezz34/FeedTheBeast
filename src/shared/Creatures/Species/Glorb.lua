-- GLORB — una medusa-orbe que flota: caparazón translúcido con el núcleo brillando dentro,
-- un ojo enorme, tres ojos más sobre antenas y tentáculos que ondulan.
local Anim = require(script.Parent.Parent.Anim)
local V = Vector3.new
local rgb = Color3.fromRGB
local rot = Anim.rot

local SHELL = rgb(156, 98, 236)
local CORE = rgb(84, 236, 214)
local TENT = rgb(122, 72, 208)
local IRIS = rgb(255, 150, 40)
local MOUTH = rgb(58, 18, 70)
local WHITE = rgb(252, 252, 246)

local Glorb = { unit = 0.8 }

function Glorb.build(kit)
	local shell = kit:blob("Shell", V(4.7, 4.3, 4.5), V(0, 4.9, 0), SHELL, { role = "Body", material = Enum.Material.Glass, transparency = 0.25, shadow = true })
	kit:blob("Core", V(2.5, 2.3, 2.3), V(0, 4.7, 0.4), CORE, { role = "Belly", material = Enum.Material.Neon, parent = shell })
	kit:eyeball("EyeMain", 2.5, V(0, 5.2, -1.62), { parent = shell, iris = IRIS, lid = SHELL, irisScale = 0.62 })
	-- Boca pequeña con dos colmillos.
	kit:blob("Mouth", V(1.5, 0.6, 0.7), V(0, 3.55, -1.72), MOUTH, { role = "Mouth", parent = shell })
	kit:blob("Lip", V(1.7, 0.5, 0.9), V(0, 3.28, -1.62), TENT, { role = "Accent", parent = shell, joint = "Jaw", pivot = V(0, 3.4, -1.1) })
	kit:blob("FangL", V(0.24, 0.5, 0.24), V(-0.42, 3.5, -2.0), WHITE, { role = "Teeth", parent = shell })
	kit:blob("FangR", V(0.24, 0.5, 0.24), V(0.42, 3.5, -2.0), WHITE, { role = "Teeth", parent = shell })
	-- Ojos sobre antenas.
	local stalks = { { "L", V(-1.35, 7.25, 0), 24 }, { "Top", V(0, 7.6, 0.35), 0 }, { "R", V(1.35, 7.25, 0), -24 } }
	for _, def in ipairs(stalks) do
		local name, pos, tilt = def[1], def[2], def[3]
		local frame = CFrame.new(pos) * rot(0, 0, tilt)
		local stalk = kit:cyl("Stalk" .. name, 0.34, 1.5, frame, TENT, { role = "Accent", parent = shell, joint = "Eye" .. name, pivot = (frame * CFrame.new(0, -0.75, 0)).Position })
		kit:eyeball("StalkEye" .. name, 0.95, (frame * CFrame.new(0, 1.05, -0.1)).Position, { parent = stalk, lid = TENT, lidRole = "Accent" })
	end
	-- Aletas laterales.
	for _, side in ipairs({ { "L", -1 }, { "R", 1 } }) do
		local name, sx = side[1], side[2]
		kit:blob("Fin" .. name, V(1.9, 0.35, 1.3), CFrame.new(sx * 2.85, 4.7, 0.3) * rot(0, 0, sx * 12), TENT, { role = "Accent", parent = shell, joint = "Arm" .. name, pivot = V(sx * 2.2, 4.7, 0.3) })
	end
	-- Tentáculos: dos tramos que se estrechan y una punta luminosa.
	for i = 1, 5 do
		local angle = (i - 1) / 5 * math.pi * 2 + 0.3
		local x, z = math.sin(angle) * 1.25, math.cos(angle) * 1.25
		local top = kit:blob("Tent" .. i .. "a", V(0.9, 1.7, 0.9), V(x, 2.35, z), TENT, { role = "Accent", parent = shell, joint = "Tent" .. i, pivot = V(x * 0.85, 3.0, z * 0.85) })
		local mid = kit:blob("Tent" .. i .. "b", V(0.6, 1.4, 0.6), V(x * 1.1, 1.25, z * 1.1), TENT, { role = "Accent", parent = top, joint = "Tent" .. i .. "b", pivot = V(x * 1.05, 1.75, z * 1.05) })
		kit:blob("Tent" .. i .. "c", V(0.5, 0.5, 0.5), V(x * 1.14, 0.55, z * 1.14), CORE, { role = "Detail", parent = mid, material = Enum.Material.Neon })
	end
	-- Evolución: más ojos (etapa 2) y una corona de cuentas luminosas (etapa 3).
	for _, def in ipairs({ { "B1", V(-0.75, 7.0, 0.9), 12 }, { "B2", V(0.75, 7.0, 0.9), -12 } }) do
		local frame = CFrame.new(def[2]) * rot(-12, 0, def[3])
		local stalk = kit:cyl("Stalk" .. def[1], 0.3, 1.2, frame, TENT, { role = "Accent", parent = shell, stage = 2 })
		kit:eyeball("StalkEye" .. def[1], 0.8, (frame * CFrame.new(0, 0.85, -0.1)).Position, { parent = stalk, lid = TENT, lidRole = "Accent", stage = 2 })
	end
	for i = 1, 6 do
		local angle = (i - 1) / 6 * math.pi * 2
		kit:blob("Bead" .. i, V(0.45, 0.45, 0.45), V(math.sin(angle) * 2.75, 6.1, math.cos(angle) * 2.75), CORE, { role = "Detail", parent = shell, material = Enum.Material.Neon, stage = 3 })
	end

	kit:anchor("Mouth", V(0, 3.5, -2.4))
	kit:anchor("Head", V(0, 5.6, -1.4))
	kit:anchor("Top", V(0, 9.0, 0))
	kit:anchor("AuraAnchor", V(0, 4.7, 0))
	kit:anchor("Ground", V(0, 0.05, 0), kit.root)
	return { radius = 3.1, height = 8.8, center = V(0, 4.7, 0) }
end

-- Idle: flota, gira despacio, mira alrededor y ondula los tentáculos.
function Glorb.idle(v, t)
	v:pose("Body", CFrame.new(0, math.sin(t * 1.4) * 0.35, 0) * rot(math.sin(t * 0.9) * 3, math.sin(t * 0.5) * 10, 0))
	v:pose("EyeL", rot(math.sin(t * 2.1) * 9, 0, math.sin(t * 1.4 + 1) * 10))
	v:pose("EyeR", rot(math.sin(t * 2.1 + 2) * 9, 0, math.sin(t * 1.4 + 3) * 10))
	v:pose("EyeTop", rot(math.sin(t * 1.9 + 4) * 11, 0, math.sin(t * 1.6) * 8))
	v:pose("ArmL", rot(0, 0, math.sin(t * 2.6) * 18))
	v:pose("ArmR", rot(0, 0, -math.sin(t * 2.6) * 18))
	for i = 1, 5 do
		local phase = t * 2 + i * 1.3
		v:pose("Tent" .. i, rot(math.sin(phase) * 14, 0, math.cos(phase * 0.8) * 12))
		v:pose("Tent" .. i .. "b", rot(math.sin(phase - 0.8) * 20, 0, math.cos(phase * 0.8 - 0.8) * 16))
	end
	v:pose("Jaw", rot(-math.max(0, math.sin(t * 1.1)) * 8, 0, 0))
end

function Glorb.eat(v, a)
	local open = Anim.chomp(a, 3)
	local lean = Anim.bump(a, 0.2)
	v:pose("Body", rot(-16 * lean, 0, 0), true)
	v:pose("Jaw", rot(-open * 38, 0, 0))
	for i = 1, 5 do
		v:pose("Tent" .. i, rot(-28 * open, 0, 0), true)
	end
end

-- Satisfacción: pirueta lenta con los tentáculos abiertos.
function Glorb.happy(v, a)
	local up = Anim.bump(a, 0.3)
	v:pose("Body", CFrame.new(0, up * 0.8, 0) * rot(0, a * 360, 0), true)
	for i = 1, 5 do
		v:pose("Tent" .. i, rot(30 * up, 0, 0), true)
	end
end

return Glorb
