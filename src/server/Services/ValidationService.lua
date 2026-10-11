-- Crea los remotos y aplica a cada petición del cliente: rate limiting + validación de tipos.
-- Los handlers reciben argumentos ya validados en forma; la validación de ESTADO (propiedad,
-- distancia, saldo...) la hace cada servicio.
--
-- API:
--   ValidationService.on(name, handler(player, ...))          -- RemoteEvent cliente->servidor
--   ValidationService.onInvoke(name, handler(player, ...))    -- RemoteFunction
--   ValidationService.fireClient(player, name, ...)
--   ValidationService.fireAll(name, ...)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteDefinitions = require(Shared.RemoteDefinitions)
local RateLimiter = require(Shared.Logic.RateLimiter)
local Validate = require(Shared.Logic.Validate)
local Clock = require(Shared.Clock)

local ValidationService = {}

local folder
local remotes = {}
local handlers = {}
local limiters = {}
-- Límite global por jugador sumando todos los remotos.
local globalLimiter = RateLimiter.new(20, 40)
local rejected = {} -- userId -> contador de peticiones rechazadas (diagnóstico)

local function reject(player, name, reason)
	local userId = player.UserId
	rejected[userId] = (rejected[userId] or 0) + 1
	-- Aviso con moderación para no llenar el log si alguien hace spam.
	local count = rejected[userId]
	if count <= 5 or count % 100 == 0 then
		warn(string.format("[Validation] rejected %s from %d: %s (total %d)", name, userId, reason, count))
	end
end

local function check(player, name, def, args)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end
	local now = Clock.now()
	local userId = player.UserId
	if not globalLimiter:allow(userId, now) then
		reject(player, name, "global_rate")
		return false
	end
	if not limiters[name]:allow(userId, now) then
		reject(player, name, "rate")
		return false
	end
	local ok, reason = Validate.args(def.args, args, args.n)
	if not ok then
		reject(player, name, reason)
		return false
	end
	return true
end

function ValidationService.Init()
	folder = Instance.new("Folder")
	folder.Name = RemoteDefinitions.FolderName

	for name, def in pairs(RemoteDefinitions.ServerEvents) do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		remotes[name] = remote
		limiters[name] = RateLimiter.new(def.rate, def.burst)
		remote.OnServerEvent:Connect(function(player, ...)
			local args = table.pack(...)
			if not check(player, name, def, args) then
				return
			end
			local handler = handlers[name]
			if handler then
				local ok, err = xpcall(handler, debug.traceback, player, table.unpack(args, 1, #def.args))
				if not ok then
					warn("[Validation] handler error in " .. name .. ": " .. tostring(err))
				end
			end
		end)
	end

	for name, def in pairs(RemoteDefinitions.ServerFunctions) do
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = folder
		remotes[name] = remote
		limiters[name] = RateLimiter.new(def.rate, def.burst)
		remote.OnServerInvoke = function(player, ...)
			local args = table.pack(...)
			if not check(player, name, def, args) then
				return nil
			end
			local handler = handlers[name]
			if not handler then
				return nil
			end
			local ok, result = xpcall(handler, debug.traceback, player, table.unpack(args, 1, #def.args))
			if not ok then
				warn("[Validation] handler error in " .. name .. ": " .. tostring(result))
				return nil
			end
			return result
		end
	end

	for _, name in ipairs(RemoteDefinitions.ClientEvents) do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		remotes[name] = remote
	end

	folder.Parent = ReplicatedStorage

	Players.PlayerRemoving:Connect(function(player)
		local userId = player.UserId
		globalLimiter:forget(userId)
		for _, limiter in pairs(limiters) do
			limiter:forget(userId)
		end
		rejected[userId] = nil
	end)
end

function ValidationService.on(name, handler)
	assert(RemoteDefinitions.ServerEvents[name], "unknown server event " .. tostring(name))
	assert(handlers[name] == nil, "handler already set for " .. name)
	handlers[name] = handler
end

function ValidationService.onInvoke(name, handler)
	assert(RemoteDefinitions.ServerFunctions[name], "unknown server function " .. tostring(name))
	assert(handlers[name] == nil, "handler already set for " .. name)
	handlers[name] = handler
end

function ValidationService.fireClient(player, name, ...)
	local remote = remotes[name]
	if remote and player and player.Parent then
		remote:FireClient(player, ...)
	end
end

function ValidationService.fireAll(name, ...)
	local remote = remotes[name]
	if remote then
		remote:FireAllClients(...)
	end
end

-- Notificación breve al jugador. kind: "info" | "success" | "error" | "reward" | "alert"
function ValidationService.notify(player, text, kind, icon)
	ValidationService.fireClient(player, "Notify", { text = text, kind = kind or "info", icon = icon })
end

function ValidationService.rejectedCount(userId)
	return rejected[userId] or 0
end

return ValidationService
