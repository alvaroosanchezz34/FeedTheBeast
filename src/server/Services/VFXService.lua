-- Coordinación de efectos desde el servidor. Solo envía "qué efecto y dónde"; la reproducción
-- (partículas, luces, sonido) es cosmética y ocurre en cada cliente con sus propios límites.
--
-- API:
--   VFXService.playAll(effectId, payload)            payload = { model?, position?, radius? }
--   VFXService.playFor(player, effectId, payload)
--   VFXService.announce(text, color)                 mensaje destacado para todos
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local VFXConfig = require(Shared.Config.VFXConfig)

local VFXService = {}

local services

function VFXService.Init(allServices)
	services = allServices
end

function VFXService.playAll(effectId, payload)
	if not VFXConfig.Effects[effectId] then
		warn("[VFX] unknown effect " .. tostring(effectId))
		return
	end
	services.ValidationService.fireAll("Effect", effectId, payload or {})
end

function VFXService.playFor(player, effectId, payload)
	if not VFXConfig.Effects[effectId] then
		warn("[VFX] unknown effect " .. tostring(effectId))
		return
	end
	services.ValidationService.fireClient(player, "Effect", effectId, payload or {})
end

function VFXService.announce(text, color)
	services.ValidationService.fireAll("Notify", { text = text, kind = "announce", color = color })
end

return VFXService
