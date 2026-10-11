-- NULLABYTE (SECRET) — una pila de cubos "sin textura" que flota, con fragmentos orbitando
-- y un ojo-rendija con eco. Su identidad es la silueta dentada y los cuadros magenta.
local Anim = require(script.Parent.Parent.Anim)
local V = Vector3.new
local rgb = Color3.fromRGB
local rot = Anim.rot

local VOID = rgb(18, 18, 24)
local MAGENTA = rgb(255, 0, 220)
local CYAN = rgb(80, 255, 240)

local Nullabyte = { unit = 0.8 }

Nullabyte.Fragments = {
	{ V(2.7, 3.5, 0.5), 0.65, true },
	{ V(-2.6, 5.2, -0.4), 0.5, false },
	{ V(2.2, 6.5, 1.0), 0.45, false },
	{ V(-2.3, 2.1, 1.2), 0.6, true },
	{ V(0.3, 8.5, 0), 0.55, true },
	{ V(-0.9, 8.1, 0.7), 0.4, false },
}

function Nullabyte.build(kit)
	local c1 = kit:block("Cube1", V(3.4, 2.6, 3.4), CFrame.new(0, 2.3, 0) * rot(0, 8, 0), VOID, {
		role = "Body", shadow = true, joint = "Base", material = Enum.Material.SmoothPlastic,
	})
	local c2 = kit:block("Cube2", V(2.8, 2.2, 2.8), CFrame.new(0.35, 4.5, -0.15) * rot(0, -14, 6), VOID, {
		role = "Body", parent = c1, joint = "Torso", pivot = V(0.2, 3.5, 0), shadow = true,
	})
	local head = kit:block("Cube3", V(2.2, 2.0, 2.2), CFrame.new(-0.2, 6.5, 0.1) * rot(0, 20, -8), VOID, {
		role = "Body", parent = c2, joint = "Head", pivot = V(0, 5.6, 0), shadow = true,
	})
	-- Cuadros "missing texture"
	local tiles = {
		{ c1, V(1.0, 1.0, 0.12), CFrame.new(-0.85, 2.75, -1.74) * rot(0, 8, 0) },
		{ c1, V(1.0, 1.0, 0.12), CFrame.new(0.4, 1.75, -1.72) * rot(0, 8, 0) },
		{ c1, V(0.12, 1.0, 1.0), CFrame.new(1.72, 2.6, 0.3) * rot(0, 8, 0) },
		{ c1, V(0.12, 0.8, 0.8), CFrame.new(-1.72, 1.8, -0.5) * rot(0, 8, 0) },
		{ c2, V(0.9, 0.9, 0.12), CFrame.new(1.25, 5.0, -1.4) * rot(0, -14, 6) },
		{ c2, V(0.12, 0.9, 0.9), CFrame.new(-1.05, 4.3, 0.3) * rot(0, -14, 6) },
		{ head, V(0.7, 0.7, 0.12), CFrame.new(0.55, 7.0, -0.85) * rot(0, 20, -8) },
	}
	for i, def in ipairs(tiles) do
		kit:block("Tile" .. i, def[2], def[3], MAGENTA, { role = "Accent", parent = def[1], material = Enum.Material.Neon })
	end
	-- Boca dentada en el cubo central
	kit:block("MouthStrip", V(2.0, 0.55, 0.1), CFrame.new(0.3, 4.15, -1.56) * rot(0, -14, 6), rgb(60, 0, 50), { role = "Mouth", parent = c2 })
	for i = 1, 5 do
		local x = -0.8 + (i - 1) * 0.4
		local up = i % 2 == 0
		kit:block("Tooth" .. i, V(0.3, 0.42, 0.14), CFrame.new(0.3, 4.15, -1.6) * rot(0, -14, 6) * CFrame.new(x, up and 0.12 or -0.12, 0), up and CYAN or rgb(250, 250, 255), {
			role = "Teeth", parent = c2, material = Enum.Material.Neon,
		})
	end
	kit:block("JawBar", V(2.1, 0.3, 0.3), CFrame.new(0.3, 3.7, -1.5) * rot(0, -14, 6), VOID, {
		role = "Body", parent = c2, joint = "Jaw", pivot = V(0.3, 3.9, -1.0),
	})
	-- Ojo-rendija y su eco desplazado
	local eye = kit:block("EyeSlit", V(0.36, 1.3, 0.16), CFrame.new(-0.45, 6.6, -1.06) * rot(0, 20, -8), CYAN, {
		role = "Eye", parent = head, material = Enum.Material.Neon, joint = "EyeMain",
	})
	kit:block("EyeEcho", V(0.36, 1.3, 0.12), CFrame.new(0.15, 6.38, -1.2) * rot(0, 20, -8), CYAN, {
		role = "Pupil", parent = eye, material = Enum.Material.Neon, transparency = 0.6,
	})
	-- Fragmentos flotantes
	for i, def in ipairs(Nullabyte.Fragments) do
		local pos, size, neon = def[1], def[2], def[3]
		kit:block("Frag" .. i, V(size, size, size), CFrame.new(pos) * rot(i * 23, i * 41, i * 17), neon and MAGENTA or VOID, {
			role = neon and "Detail" or "Body", joint = "Frag" .. i, material = neon and Enum.Material.Neon or Enum.Material.SmoothPlastic,
		})
	end

	-- Evolución: más fragmentos (etapa 2) y un halo roto de cubos cian (etapa 3).
	for i, def in ipairs({ V(-3.1, 6.9, 0.6), V(3.0, 5.0, -0.7), V(1.6, 1.5, 1.6) }) do
		kit:block("Shard" .. i, V(0.5, 0.5, 0.5), CFrame.new(def) * rot(i * 31, i * 17, i * 43), MAGENTA, { role = "Detail", material = Enum.Material.Neon, stage = 2 })
	end
	for i = 1, 5 do
		local angle = (i - 1) / 5 * math.pi * 2 + 0.4
		kit:block("Halo" .. i, V(0.6, 0.22, 0.6), CFrame.new(-0.2 + math.sin(angle) * 1.9, 8.25, 0.1 + math.cos(angle) * 1.9) * rot(0, math.deg(angle), 8), CYAN, { role = "Detail", parent = head, material = Enum.Material.Neon, stage = 3 })
	end

	kit:anchor("Mouth", V(0.3, 4.1, -2.0))
	kit:anchor("Head", V(-0.2, 6.6, -1.0))
	kit:anchor("Top", V(0, 9.1, 0))
	kit:anchor("AuraAnchor", V(0, 4.6, 0))
	kit:anchor("Ground", V(0, 0.05, 0), kit.root)
	return { radius = 3.1, height = 9, center = V(0, 4.6, 0) }
end

-- Idle "Glitch": flota, los cubos giran en sentidos opuestos, los fragmentos orbitan y de vez
-- en cuando la cabeza da un pequeño salto lateral (como máximo una vez cada ~3 s).
function Nullabyte.idle(v, t)
	v:pose("Body", CFrame.new(0, 0.45 + math.sin(t * 1.2) * 0.3, 0))
	v:pose("Base", rot(0, math.sin(t * 0.6) * 14, 0))
	v:pose("Torso", rot(0, -math.sin(t * 0.6 + 0.8) * 22, math.sin(t * 0.9) * 2))
	local glitch = Anim.window(t, 3.1, 0.14)
	if glitch then
		v:pose("Head", CFrame.new(0.35, 0, 0) * rot(0, 30, 0))
	else
		v:pose("Head", rot(math.sin(t * 1.1) * 4, math.sin(t * 0.7 + 2) * 26, 0))
	end
	v:pose("EyeMain", CFrame.new(math.sin(t * 2.3) * 0.08, 0, 0))
	v:pose("Jaw", CFrame.new(0, -0.08 - math.max(0, math.sin(t * 1.7)) * 0.12, 0))
	for i = 1, #Nullabyte.Fragments do
		local phase = t * (0.8 + i * 0.13) + i * 1.9
		v:pose("Frag" .. i, CFrame.new(math.sin(phase) * 0.4, math.cos(phase * 1.3) * 0.35, math.cos(phase) * 0.4) * rot(t * 40 + i * 30, t * 25, 0))
	end
end

function Nullabyte.eat(v, a)
	local open = Anim.chomp(a, 3)
	local pull = Anim.bump(a, 0.35)
	v:pose("Head", CFrame.new(0, open * 0.5, 0) * rot(-open * 22, 0, 0))
	v:pose("Jaw", CFrame.new(0, -open * 0.55, 0))
	-- Los fragmentos se acercan al cuerpo y vuelven a salir.
	for i, def in ipairs(Nullabyte.Fragments) do
		local toCenter = (V(0, 4.6, 0) - def[1]) * (0.55 * pull)
		v:pose("Frag" .. i, CFrame.new(toCenter) * rot(a * 360, a * 200, 0))
	end
end

-- Satisfacción: los cubos se desalinean un instante y vuelven a encajar.
function Nullabyte.happy(v, a)
	local k = Anim.bump(a, 0.2)
	v:pose("Torso", CFrame.new(0.5 * k, 0, 0) * rot(0, 90 * k, 0), true)
	v:pose("Head", CFrame.new(-0.5 * k, 0.4 * k, 0) * rot(0, -120 * k, 0))
end

return Nullabyte
