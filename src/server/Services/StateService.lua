-- Envía al cliente la vista de su propio estado (nunca al revés). Los servicios marcan campos
-- como sucios con StateService.push y se envían agrupados una vez por frame.
--
-- API:
--   StateService.push(userId, "coins", "inventory", ...)
--   StateService.pushAll(userId)
--   StateService.flush()
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyMath = require(Shared.Logic.EconomyMath)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local GameConfig = require(Shared.Config.GameConfig)
local VFXConfig = require(Shared.Config.VFXConfig)
local Utilities = require(Shared.Utilities)
local Clock = require(Shared.Clock)

local StateService = {}

local services
local dirty = {} -- userId -> { campo = true }

local providers = {}

providers.coins = function(session)
	return session.profile.coins
end
providers.pendingOffline = function(session)
	return session.profile.pendingOffline
end
providers.income = function(session)
	return services.EconomyService.income(session)
end
providers.multipliers = function(session)
	return services.EconomyService.multipliers(session)
end
providers.inventory = function(session)
	return Utilities.shallowCopy(session.profile.inventory)
end
providers.capacity = function(session)
	return EconomyMath.inventoryCapacity(session.profile)
end
providers.creatures = function(session)
	return services.CreatureService.view(session)
end
providers.collection = function(session)
	return Utilities.shallowCopy(session.profile.collection)
end
providers.upgrades = function(session)
	local levels, costs = {}, {}
	for _, id in ipairs(UpgradeConfig.Order) do
		local level = EconomyMath.upgradeLevel(session.profile, id)
		levels[id] = level
		costs[id] = EconomyMath.upgradeCost(id, level) or -1 -- -1 = nivel máximo
	end
	return { levels = levels, costs = costs }
end
providers.rebirths = function(session)
	return session.profile.rebirths
end
providers.slots = function(session)
	return services.CreatureService.slotCount(session)
end
providers.maxLevel = function(session)
	return EconomyMath.maxLevel(session.profile.rebirths)
end
providers.boosts = function(session)
	-- Segundos restantes de cada boost (el cliente hace la cuenta atrás).
	local now = Clock.unix()
	local result = {}
	for id, expires in pairs(session.profile.boosts) do
		if expires > now then
			result[id] = expires - now
		end
	end
	return result
end
providers.cosmetics = function(session)
	return Utilities.shallowCopy(session.profile.cosmetics)
end
providers.flags = function(session)
	return Utilities.shallowCopy(session.profile.flags)
end
providers.settings = function(session)
	return Utilities.shallowCopy(session.profile.settings)
end
providers.passes = function(session)
	return Utilities.shallowCopy(session.passes)
end
providers.stats = function(session)
	return Utilities.shallowCopy(session.profile.stats)
end
providers.quests = function(session)
	return services.QuestService.view(session)
end
providers.plotIndex = function(session)
	return session.plotIndex or 0
end
providers.protection = function(session)
	local left = GameConfig.NewPlayerProtectionSeconds - services.PlayerDataService.playTime(session)
	return math.max(0, math.floor(left))
end
providers.isAdmin = function(session)
	return services.AdminService.isAdmin(session.player)
end
providers.ephemeral = function(session)
	return session.ephemeral == true
end

function StateService.Init(allServices)
	services = allServices
end

function StateService.Start()
	services.PlayerDataService.SessionEnding:Connect(function(session)
		dirty[session.userId] = nil
	end)
	-- El cliente pide el estado completo cuando su interfaz está lista.
	services.ValidationService.on("ClientReady", function(player)
		local session = services.PlayerDataService.sessionOf(player)
		if session then
			session.clientReady = true
			StateService.pushAll(session.userId)
		end
	end)
	services.PlayerDataService.SessionStarted:Connect(function(session)
		StateService.pushAll(session.userId)
	end)
	-- Ajustes del jugador (solo preferencias de presentación; se validan igualmente).
	services.ValidationService.on("SetSetting", function(player, key, value)
		local session = services.PlayerDataService.sessionOf(player)
		if not session then
			return
		end
		local settings = session.profile.settings
		if key == "vfxQuality" then
			if value == "Auto" or (type(value) == "string" and VFXConfig.Quality[value] ~= nil) then
				settings.vfxQuality = value
			end
		elseif key == "sfxVolume" or key == "musicVolume" then
			if type(value) == "number" and value == value then
				settings[key] = math.clamp(value, 0, 1)
			end
		end
	end)
end

function StateService.push(userId, ...)
	local set = dirty[userId]
	if not set then
		set = {}
		dirty[userId] = set
	end
	for i = 1, select("#", ...) do
		local key = select(i, ...)
		assert(providers[key], "unknown state field " .. tostring(key))
		set[key] = true
	end
end

function StateService.pushAll(userId)
	local set = dirty[userId]
	if not set then
		set = {}
		dirty[userId] = set
	end
	for key in pairs(providers) do
		set[key] = true
	end
end

function StateService.flush()
	for userId, set in pairs(dirty) do
		dirty[userId] = nil
		local session = services.PlayerDataService.getSession(userId)
		if session and session.player and session.player.Parent then
			local patch = {}
			local any = false
			for key in pairs(set) do
				local ok, value = pcall(providers[key], session)
				if ok then
					patch[key] = value
					any = true
				else
					warn("[State] provider " .. key .. " failed: " .. tostring(value))
				end
			end
			if any then
				services.ValidationService.fireClient(session.player, "State", patch)
			end
		end
	end
end

function StateService.Update()
	StateService.flush()
end

return StateService
