-- Geometría pura del mapa: posición de parcelas, espacios y zonas. Solo números.
-- Convención: el centro del mapa es (0, 0); cada parcela mira hacia el centro.
local GameConfig = require(script.Parent.Parent.Config.GameConfig)

local PlotLayout = {}

local W = GameConfig.World

-- Devuelve { x, z, yaw } del centro de la parcela `index` (1..PlotCount).
-- yaw (radianes) orienta el eje -Z local (frente) hacia el centro del mapa.
function PlotLayout.plot(index)
	local angle = (index - 1) / GameConfig.PlotCount * math.pi * 2
	local x = math.sin(angle) * W.PlotRingRadius
	local z = math.cos(angle) * W.PlotRingRadius
	-- Frente (-Z local) apuntando a (0,0): rotación Y = angle.
	return { x = x, z = z, yaw = angle, angle = angle }
end

-- Posiciones locales (x, z) dentro de la parcela. Frente = z negativo.
local SLOT_X = { -17, 0, 17 }
local SLOT_Z = { 4, 20 }

function PlotLayout.slotLocal(slot)
	local col = (slot - 1) % 3 + 1
	local row = math.floor((slot - 1) / 3) + 1
	return { x = SLOT_X[col], z = SLOT_Z[row] }
end

-- El jugador aparece en la entrada MIRANDO hacia sus criaturas (fondo de la parcela, +Z local):
-- lo primero que ve es su criatura inicial, con la comida de bienvenida en línea recta hacia ella.
PlotLayout.Local = {
	Spawn = { x = 0, z = -18 },
	CollectPad = { x = 17, z = -19 },
	DeliveryPad = { x = -17, z = -19 },
	Sign = { x = 0, z = -27.4 },
	StarterFood = { { x = -4, z = -11 }, { x = 0, z = -10 }, { x = 4, z = -11 } },
}

-- Convierte coordenadas locales de parcela a mundo. Devuelve x, z.
function PlotLayout.toWorld(plot, localX, localZ)
	local cos, sin = math.cos(plot.yaw), math.sin(plot.yaw)
	-- Rotación Y de Roblox: x' = x*cos + z*sin ; z' = -x*sin + z*cos
	return plot.x + localX * cos + localZ * sin, plot.z - localX * sin + localZ * cos
end

-- Punto aleatorio en el anillo de comida. rnd() en [0,1).
function PlotLayout.foodPoint(rnd, inner, outer)
	inner = inner or W.FoodRingInner
	outer = outer or W.FoodRingOuter
	local angle = rnd() * math.pi * 2
	-- Distribución uniforme en área.
	local r = math.sqrt(inner * inner + (outer * outer - inner * inner) * rnd())
	return math.sin(angle) * r, math.cos(angle) * r
end

-- Kioscos situados entre parcelas (ángulos intermedios).
function PlotLayout.kiosk(index)
	local angle = ((index - 1) * 2 + 0.5) / GameConfig.PlotCount * math.pi * 2
	return { x = math.sin(angle) * W.KioskRadius, z = math.cos(angle) * W.KioskRadius, yaw = angle }
end

return PlotLayout
