-- Economía autoritativa: monedas, producción periódica, recogida y ganancias offline.
-- El cliente nunca decide cuánto gana un jugador.
--
-- API:
--   EconomyService.addCoins(userId, amount) -> cantidad añadida
--   EconomyService.spend(userId, amount) -> bool
--   EconomyService.income(session) -> monedas/segundo
--   EconomyService.multipliers(session) -> desglose
--   EconomyService.collect(userId) -> cantidad recogida
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyConfig = require(Shared.Config.EconomyConfig)
local EconomyMath = require(Shared.Logic.EconomyMath)
local OfflineEarnings = require(Shared.Logic.OfflineEarnings)
local Utilities = require(Shared.Utilities)
local Clock = require(Shared.Clock)

local EconomyService = {}

local services
local tickTimer = 0

local function context(session)
	return {
		vip = session.passes.VIP == true,
		eventMult = services.EventService.incomeMult(),
	}
end

function EconomyService.income(session)
	return EconomyMath.totalIncome(session.profile, context(session))
end

function EconomyService.multipliers(session)
	return EconomyMath.multipliers(session.profile, context(session))
end

function EconomyService.addCoins(userId, amount)
	local profile = services.PlayerDataService.getProfile(userId)
	if not profile or not EconomyMath.isFinite(amount) or amount <= 0 then
		return 0
	end
	amount = math.floor(amount)
	local before = profile.coins
	profile.coins = EconomyMath.clampCoins(before + amount)
	local added = profile.coins - before
	profile.stats.totalCoinsEarned += added
	services.StateService.push(userId, "coins")
	return added
end

-- Descuenta exactamente `amount` o no descuenta nada.
function EconomyService.spend(userId, amount)
	local profile = services.PlayerDataService.getProfile(userId)
	if not profile or not EconomyMath.isFinite(amount) or amount < 0 then
		return false
	end
	amount = math.ceil(amount)
	if profile.coins < amount then
		return false
	end
	profile.coins -= amount
	services.StateService.push(userId, "coins")
	return true
end

-- Pasa las ganancias pendientes de la parcela al saldo.
function EconomyService.collect(userId)
	local session = services.PlayerDataService.getSession(userId)
	if not session then
		return 0
	end
	local profile = session.profile
	local amount = math.floor(profile.pendingCoins)
	if amount <= 0 then
		return 0
	end
	profile.pendingCoins -= amount
	local added = EconomyService.addCoins(userId, amount)
	EconomyService.refreshPlot(session)
	if added > 0 then
		services.QuestService.progress(session, "PadCollected", 1)
		if not profile.flags.firstCollect then
			profile.flags.firstCollect = true
			services.StateService.push(userId, "flags")
		end
		services.ValidationService.notify(session.player, "+" .. Utilities.formatNumber(added) .. " coins", "reward", "💰")
		local pos = services.CharacterService.positionOf(userId)
		if pos then
			services.VFXService.playFor(session.player, "CoinCollect", { position = pos, radius = 2 })
		end
	end
	return added
end

function EconomyService.refreshPlot(session)
	if session.plotIndex then
		local income = EconomyService.income(session)
		services.PlotService.setEconomy(session.plotIndex, income, session.profile.pendingCoins, EconomyMath.pendingCap(income))
	end
end

-- Recalcula y notifica ingresos (tras alimentar, comprar, mutar, colocar...).
function EconomyService.incomeChanged(userId)
	local session = services.PlayerDataService.getSession(userId)
	if session then
		EconomyService.refreshPlot(session)
		services.StateService.push(userId, "income", "multipliers")
	end
end

local function grantOffline(session)
	local profile = session.profile
	-- Sin VIP ni eventos: solo lo que consta en los datos guardados.
	local income = EconomyMath.totalIncome(profile, {})
	local amount = OfflineEarnings.compute(session.previousLastSave, Clock.unix(), income)
	-- Se mueve a `pendingOffline` y se avanza lastSave en el mismo perfil: se persisten juntos,
	-- así un fallo antes de guardar no duplica ni pierde la recompensa.
	profile.lastSave = Clock.unix()
	session.previousLastSave = profile.lastSave
	if amount > 0 then
		profile.pendingOffline = EconomyMath.clampCoins(profile.pendingOffline + amount)
	end
end

function EconomyService.Init(allServices)
	services = allServices
end

function EconomyService.Start()
	services.PlayerDataService.SessionStarted:Connect(function(session)
		if not session.isNew then
			grantOffline(session)
		end
		EconomyService.refreshPlot(session)
	end)

	services.ValidationService.on("ClaimOffline", function(player)
		local session = services.PlayerDataService.sessionOf(player)
		if not session then
			return
		end
		local amount = session.profile.pendingOffline
		if amount <= 0 then
			return
		end
		session.profile.pendingOffline = 0
		local added = EconomyService.addCoins(session.userId, amount)
		services.StateService.push(session.userId, "pendingOffline")
		services.ValidationService.notify(player, "Offline earnings: +" .. Utilities.formatNumber(added), "reward", "💤")
	end)
end

function EconomyService.Update(dt)
	tickTimer += dt
	local tick = EconomyConfig.ProductionTick
	if tickTimer < tick then
		return
	end
	local elapsed = tickTimer
	tickTimer = 0
	services.PlayerDataService.forEach(function(session)
		if not session.plotIndex then
			return
		end
		local profile = session.profile
		local income = EconomyService.income(session)
		local cap = EconomyMath.pendingCap(income)
		if income > 0 and profile.pendingCoins < cap then
			profile.pendingCoins = math.min(cap, profile.pendingCoins + income * elapsed)
		end
		services.PlotService.setEconomy(session.plotIndex, income, profile.pendingCoins, cap)
	end)
end

return EconomyService
