-- Curvas de animación procedural compartidas por las especies.
local Anim = {}

-- CFrame de rotación en grados.
function Anim.rot(x, y, z)
	return CFrame.Angles(math.rad(x or 0), math.rad(y or 0), math.rad(z or 0))
end

-- Apertura de mandíbula 0..1 para `n` mordiscos a lo largo de a ∈ [0,1].
function Anim.chomp(a, n)
	a = math.clamp(a, 0, 1)
	return math.abs(math.sin(a * (n or 3) * math.pi)) * (1 - a * 0.35)
end

-- Sube rápido y baja suave: 0 -> 1 -> 0 con pico en `peak`.
function Anim.bump(a, peak)
	a = math.clamp(a, 0, 1)
	peak = peak or 0.3
	if a < peak then
		return a / peak
	end
	return 1 - (a - peak) / (1 - peak)
end

-- Ruido determinista suave en [-1, 1] (suma de senos) para movimientos orgánicos.
function Anim.wobble(t, seed)
	seed = seed or 0
	return (math.sin(t * 1.3 + seed) + math.sin(t * 2.1 + seed * 1.7) * 0.5 + math.sin(t * 0.7 + seed * 0.3) * 0.5) / 2
end

-- 1 durante una ventana corta que se repite cada `period` segundos (para tics ocasionales).
function Anim.window(t, period, length, offset)
	local phase = (t + (offset or 0)) % period
	if phase < length then
		return phase / length
	end
	return nil
end

return Anim
