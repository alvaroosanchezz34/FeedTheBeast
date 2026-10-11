-- TOILETINI — un inodoro engreído con zapatillas; la tapa es su boca y lleva un desatascador de antena.
local Anim = require(script.Parent.Parent.Anim)
local V = Vector3.new
local rgb = Color3.fromRGB
local rot = Anim.rot

local PORCELAIN = rgb(246, 246, 250)
local SHADE = rgb(222, 224, 234)
local WATER = rgb(90, 200, 255)
local RED = rgb(226, 58, 58)
local WOOD = rgb(170, 120, 70)
local STEEL = rgb(200, 205, 215)

local Toiletini = { unit = 0.72 }

function Toiletini.build(kit)
	-- Patas de espagueti con zapatillas
	for _, side in ipairs({ { "L", -1 }, { "R", 1 } }) do
		local name, sx = side[1], side[2]
		local leg = kit:cyl("Leg" .. name, 0.32, 1.5, V(sx * 0.8, 0.95, 0), STEEL, {
			role = "Accent", joint = "Leg" .. name, pivot = V(sx * 0.8, 1.6, 0),
		})
		kit:block("Sneaker" .. name, V(0.95, 0.48, 1.6), V(sx * 0.8, 0.24, -0.3), RED, { role = "Detail", parent = leg })
	end
	-- Pedestal, taza y aro
	kit:cyl("Pedestal", 2.2, 1.3, V(0, 2.05, -0.2), PORCELAIN, { role = "Body", reflectance = 0.12, shadow = true })
	local bowl = kit:cyl("Bowl", 3.4, 1.5, V(0, 3.25, -0.5), PORCELAIN, { role = "Body", reflectance = 0.12, shadow = true })
	kit:cyl("Seat", 3.75, 0.3, V(0, 4.1, -0.5), SHADE, { role = "Belly", parent = bowl })
	kit:cyl("Water", 2.6, 0.12, V(0, 4.22, -0.5), WATER, { role = "Detail", material = Enum.Material.Neon, parent = bowl })
	-- Dientes de porcelana en el borde delantero
	for i = -2, 2 do
		local angle = math.rad(i * 26)
		kit:block("Tooth" .. (i + 3), V(0.32, 0.42, 0.32), CFrame.new(math.sin(angle) * 1.6, 4.42, -0.5 - math.cos(angle) * 1.6) * CFrame.Angles(0, -angle, 0), PORCELAIN, {
			role = "Teeth", parent = bowl,
		})
	end
	kit:block("Tongue", V(1.0, 0.2, 1.5), CFrame.new(0, 4.2, -2.05) * rot(-18, 0, 0), rgb(255, 120, 150), { role = "Tongue", parent = bowl })
	-- Tapa = mandíbula superior (bisagra detrás)
	kit:cyl("Lid", 3.6, 0.3, V(0, 4.45, -0.5), PORCELAIN, {
		role = "Body", joint = "Jaw", pivot = V(0, 4.3, 1.15), reflectance = 0.12,
	})
	-- Cisterna con cara
	local tank = kit:block("Tank", V(3.2, 2.6, 1.2), V(0, 5.6, 1.6), PORCELAIN, {
		role = "Body", reflectance = 0.12, joint = "Head", pivot = V(0, 4.3, 1.6), shadow = true,
	})
	kit:block("TankLid", V(3.5, 0.35, 1.5), V(0, 7.05, 1.6), SHADE, { role = "Belly", parent = tank })
	kit:cyl("Handle", 0.25, 0.7, CFrame.new(-1.3, 6.5, 0.9) * rot(0, 0, 90), STEEL, { role = "Detail", material = Enum.Material.Metal, parent = tank })
	for _, side in ipairs({ { "L", -1 }, { "R", 1 } }) do
		local name, sx = side[1], side[2]
		kit:eye("Eye" .. name, 1.0, V(sx * 0.78, 5.95, 0.95), { parent = tank })
		-- Párpados caídos: mirada de superioridad
		kit:block("Lid" .. name, V(1.12, 0.34, 0.5), CFrame.new(sx * 0.78, 6.38, 0.72) * rot(0, 0, -sx * 8), SHADE, { role = "Belly", parent = tank })
		local arm = kit:cyl("Arm" .. name, 0.26, 1.4, CFrame.new(sx * 2.3, 5.0, 1.4) * rot(0, 0, 90), STEEL, {
			role = "Accent", parent = tank, joint = "Arm" .. name, pivot = V(sx * 1.6, 5.0, 1.4),
		})
		kit:ball("Hand" .. name, 0.62, V(sx * 3.05, 5.0, 1.4), PORCELAIN, { role = "Body", parent = arm })
	end
	-- Desatascador de antena
	local stick = kit:cyl("PlungerStick", 0.25, 1.7, CFrame.new(0.95, 8.0, 1.6) * rot(0, 0, -12), WOOD, {
		role = "Accent", parent = tank, joint = "Tail", pivot = V(0.8, 7.2, 1.6),
	})
	kit:ball("PlungerCup", 1.05, V(1.15, 8.95, 1.6), RED, { role = "Detail", parent = stick })

	kit:anchor("Mouth", V(0, 4.5, -2.1))
	kit:anchor("Head", V(0, 6, 0.8))
	kit:anchor("Top", V(0, 9.7, 1))
	kit:anchor("AuraAnchor", V(0, 4.4, 0.3))
	kit:anchor("Ground", V(0, 0.05, 0), kit.root)
	return { radius = 3.3, height = 9.5, center = V(0, 4.4, 0.3) }
end

-- Idle "Wiggle": menea las caderas, parpadea con la tapa y hace vibrar el desatascador.
function Toiletini.idle(v, t)
	local wig = math.sin(t * 2.6)
	v:pose("Body", rot(0, wig * 7, wig * 2))
	v:pose("Head", rot(0, 0, math.sin(t * 1.3) * 3))
	v:pose("LegL", rot(wig * 12, 0, 0))
	v:pose("LegR", rot(-wig * 12, 0, 0))
	v:pose("Tail", rot(math.sin(t * 9) * 5, 0, math.sin(t * 7) * 6))
	v:pose("ArmL", rot(0, 0, 20 + math.sin(t * 2.6) * 18))
	v:pose("ArmR", rot(0, 0, -20 + math.sin(t * 2.6) * 18))
	local flap = Anim.window(t, 4, 0.5)
	if flap then
		v:pose("Jaw", rot(18 + math.sin(flap * math.pi) * 40, 0, 0))
	else
		v:pose("Jaw", rot(18 + math.sin(t * 1.3) * 4, 0, 0))
	end
end

function Toiletini.eat(v, a)
	local open = Anim.chomp(a, 2)
	v:pose("Jaw", rot(10 + open * 78, 0, 0))
	v:pose("Head", rot(-8 * Anim.bump(a, 0.2), 0, 0))
	v:pose("ArmL", rot(0, 0, 60 * open))
	v:pose("ArmR", rot(0, 0, -60 * open))
	v:pose("Body", CFrame.new(0, 0.25 * open, 0), true)
end

return Toiletini
