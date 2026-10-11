-- Pequeños acentos de cámara para los momentos importantes. Deliberadamente suaves: un único
-- pulso de campo de visión (sin sacudidas ni giros) que no quita el control al jugador.
--
-- API:
--   CameraController.bump(strength)     strength 0..1
local CameraController = {}

local MAX_FOV_KICK = 4 -- grados
local DURATION = 0.4

local active = nil -- { elapsed, amount, base }

function CameraController.bump(strength)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local amount = math.clamp(strength or 0.3, 0, 1) * MAX_FOV_KICK
	if active then
		-- Ya hay un pulso: se reinicia sin acumular (nunca se aleja más de MAX_FOV_KICK).
		active.elapsed = 0
		active.amount = math.max(active.amount, amount)
		return
	end
	active = { elapsed = 0, amount = amount, base = camera.FieldOfView }
end

function CameraController.Update(dt)
	if not active then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		active = nil
		return
	end
	active.elapsed += dt
	local a = active.elapsed / DURATION
	if a >= 1 then
		camera.FieldOfView = active.base
		active = nil
		return
	end
	camera.FieldOfView = active.base + math.sin(a * math.pi) * active.amount
end

return CameraController
