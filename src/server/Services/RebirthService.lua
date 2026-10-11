-- Renacimiento. Requiere dos pasos: el cliente pide la información (requisitos y consecuencias)
-- y recibe un código de un solo uso; solo confirmando con ese código, dentro de un tiempo
-- limitado, se ejecuta. Así no puede activarse por un clic accidental ni por un remoto suelto.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RebirthLogic = require(Shared.Logic.RebirthLogic)
local Clock = require(Shared.Clock)

local RebirthService = {}

local services
local rng = Random.new()
local NONCE_LIFETIME = 60

local function newNonce()
	return string.format("%08x%08x", rng:NextInteger(0, 0x7FFFFFFF), rng:NextInteger(0, 0x7FFFFFFF))
end

function RebirthService.info(session)
	local info = RebirthLogic.info(session.profile)
	if info.canRebirth then
		session.rebirthNonce = { value = newNonce(), expires = Clock.now() + NONCE_LIFETIME }
		info.nonce = session.rebirthNonce.value
	else
		session.rebirthNonce = nil
	end
	return info
end

function RebirthService.confirm(session, nonce)
	local stored = session.rebirthNonce
	session.rebirthNonce = nil -- un solo uso, acierte o no
	if not stored or stored.value ~= nonce or Clock.now() > stored.expires then
		return false, "bad_nonce"
	end
	-- Suelta cualquier caja antes de reiniciar el progreso.
	services.TheftService.dropCarried(session.userId)
	local ok, reason = RebirthLogic.apply(session.profile)
	if not ok then
		return false, reason
	end
	session.eating = nil
	services.CreatureService.respawnAll(session)
	services.PlotService.refresh(session)
	services.TheftService.refreshSpeed(session.userId)
	services.EconomyService.incomeChanged(session.userId)
	services.StateService.pushAll(session.userId)
	return true, nil
end

function RebirthService.Init(allServices)
	services = allServices
end

function RebirthService.Start()
	services.ValidationService.onInvoke("GetRebirthInfo", function(player)
		local session = services.PlayerDataService.sessionOf(player)
		if not session then
			return nil
		end
		return RebirthService.info(session)
	end)

	services.ValidationService.on("ConfirmRebirth", function(player, nonce)
		local session = services.PlayerDataService.sessionOf(player)
		if not session then
			return
		end
		local ok, reason = RebirthService.confirm(session, nonce)
		if ok then
			local rebirths = session.profile.rebirths
			services.ValidationService.notify(player, "REBIRTH " .. rebirths .. "! Permanent coin bonus increased.", "reward", "🔥")
			local pos = services.CharacterService.positionOf(session.userId)
			if pos then
				services.VFXService.playAll("Rebirth", { position = pos, radius = 3 })
			end
			services.VFXService.announce(string.format("%s was reborn! (Rebirth %d)", player.DisplayName, rebirths), Color3.fromRGB(255, 150, 80))
			task.spawn(services.PlayerDataService.save, session.userId, false)
		elseif reason == "bad_nonce" then
			services.ValidationService.notify(player, "Rebirth confirmation expired. Open the menu again.", "error", "⌛")
		else
			services.ValidationService.notify(player, "You don't meet the rebirth requirements.", "error", "🚫")
		end
	end)
end

return RebirthService
