-- Monetización con MarketplaceService.
--   * Game Passes y Developer Products separados (MonetizationConfig).
--   * Los IDs son placeholders (0) hasta configurarlos: un producto sin ID no se concede nunca.
--   * ProcessReceipt es idempotente: el PurchaseId se guarda en el perfil junto con la recompensa
--     y solo se devuelve PurchaseGranted cuando el guardado se ha confirmado.
--   * Ante cualquier error se devuelve NotProcessedYet (Roblox reintenta); nunca se regala nada.
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local ReceiptLogic = require(Shared.Logic.ReceiptLogic)
local Clock = require(Shared.Clock)

local MonetizationService = {}

local services

local function ownsPass(userId, passId)
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(userId, passId)
	end)
	return ok and owns == true, ok
end

local function applyPassEffects(session)
	services.CreatureService.respawnAll(session)
	services.PlotService.refresh(session)
	services.EconomyService.incomeChanged(session.userId)
	services.StateService.push(session.userId, "passes", "slots", "creatures")
end

-- Cambia un pase en la sesión (lo usan la verificación real y las herramientas de admin).
function MonetizationService.setPass(session, key, owned)
	if not MonetizationConfig.GamePasses[key] then
		return false
	end
	owned = owned == true
	if session.passes[key] == owned then
		return true
	end
	session.passes[key] = owned
	applyPassEffects(session)
	return true
end

local function loadPasses(session)
	for key, def in pairs(MonetizationConfig.GamePasses) do
		if MonetizationConfig.isConfigured(def) then
			local owns = ownsPass(session.userId, def.id)
			if services.PlayerDataService.getSession(session.userId) == session then
				MonetizationService.setPass(session, key, owns)
			end
		end
	end
end

-- Flujo oficial: devolver PurchaseGranted solo cuando la recompensa está concedida Y persistida.
function MonetizationService.processReceipt(receiptInfo)
	local NotProcessed = Enum.ProductPurchaseDecision.NotProcessedYet
	local Granted = Enum.ProductPurchaseDecision.PurchaseGranted

	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return NotProcessed
	end
	local session = services.PlayerDataService.getSession(receiptInfo.PlayerId)
	if not session or session.ending then
		return NotProcessed
	end

	local status = ReceiptLogic.process(session.profile, receiptInfo, Clock.unix())
	if status == ReceiptLogic.Status.Granted then
		services.StateService.push(session.userId, "boosts", "cosmetics")
		services.PlotService.refresh(session)
		local def = MonetizationConfig.productById(receiptInfo.ProductId)
		services.ValidationService.notify(player, "Purchase complete: " .. (def and def.name or "item"), "reward", "🛍️")
	elseif status ~= ReceiptLogic.Status.AlreadyGranted then
		warn(string.format("[Monetization] receipt %s not granted: %s (product %s)", tostring(receiptInfo.PurchaseId), status, tostring(receiptInfo.ProductId)))
		return NotProcessed
	end

	-- Concedido (ahora o en un intento anterior): confirmar la persistencia antes de aceptar.
	if session.ephemeral then
		return Granted
	end
	if services.PlayerDataService.save(session.userId, false, true) then
		return Granted
	end
	return NotProcessed
end

function MonetizationService.Init(allServices)
	services = allServices
end

function MonetizationService.Start()
	MarketplaceService.ProcessReceipt = MonetizationService.processReceipt

	services.PlayerDataService.SessionStarted:Connect(function(session)
		loadPasses(session)
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
		if not wasPurchased then
			return
		end
		local session = services.PlayerDataService.sessionOf(player)
		if not session then
			return
		end
		for key, def in pairs(MonetizationConfig.GamePasses) do
			if MonetizationConfig.isConfigured(def) and def.id == passId then
				-- Se verifica con Roblox antes de conceder (la propiedad puede tardar en reflejarse).
				for attempt = 1, 4 do
					if ownsPass(session.userId, passId) then
						if services.PlayerDataService.getSession(session.userId) == session then
							MonetizationService.setPass(session, key, true)
							services.ValidationService.notify(player, def.name .. " unlocked!", "reward", def.icon)
						end
						return
					end
					Clock.sleep(attempt * 1.5)
				end
				warn(string.format("[Monetization] pass %d for %d could not be verified; it will apply on next join", passId, session.userId))
				return
			end
		end
	end)
end

return MonetizationService
