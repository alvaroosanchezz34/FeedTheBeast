-- Persistencia de perfiles con DataStoreService.
--
-- Garantías que se intentan dar (ninguna persistencia es infalible):
--   * Bloqueo de sesión con UpdateAsync: un perfil solo está activo en un servidor.
--   * Si la carga falla o los datos no se pueden interpretar, NO se crea un perfil vacío ni se
--     guarda nada: se expulsa al jugador con un mensaje. Los datos anteriores quedan intactos.
--   * Reintentos con backoff, guardado periódico, al salir y en BindToClose.
--   * Si otro servidor nos quita el bloqueo, dejamos de guardar y expulsamos al jugador.
--   * En Studio sin acceso a DataStores se usa un perfil en memoria que nunca se guarda.
--
-- API:
--   PlayerDataService.getSession(userId) -> session | nil
--   PlayerDataService.getProfile(userId) -> profile | nil
--   PlayerDataService.forEach(fn(session))
--   PlayerDataService.SessionStarted / SessionEnding : Signal(session)
--   PlayerDataService.save(userId, release) -> ok
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local ProfileSchema = require(Shared.Logic.ProfileSchema)
local Utilities = require(Shared.Utilities)
local Signal = require(Shared.Signal)
local Clock = require(Shared.Clock)

local PlayerDataService = {}

PlayerDataService.SessionStarted = Signal.new()
PlayerDataService.SessionEnding = Signal.new()

local cfg = GameConfig.Data
local store = nil
local sessions = {} -- userId -> session
local loading = {} -- userId -> true mientras carga
local closing = false
local autosaveTimer = 0

local function jobId()
	local id = game.JobId
	if id == nil or id == "" then
		id = "studio"
	end
	return id
end

local function keyFor(userId)
	return cfg.KeyPrefix .. tostring(userId)
end

-- Ejecuta fn con reintentos y backoff exponencial. Devuelve (ok, resultado | error).
local function withRetries(fn)
	local lastErr
	for attempt = 1, cfg.MaxRetries do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		warn(string.format("[Data] attempt %d/%d failed: %s", attempt, cfg.MaxRetries, tostring(result)))
		if attempt < cfg.MaxRetries then
			Clock.sleep(cfg.RetryBaseDelay * 2 ^ (attempt - 1))
		end
	end
	return false, lastErr
end

-- Carga con bloqueo de sesión. Devuelve (profile, nil, isNew) o (nil, motivo).
local function loadProfile(userId)
	local key = keyFor(userId)
	local lockAttempts = 4
	for lockAttempt = 1, lockAttempts do
		local outcome = nil -- "ok" | "locked" | "invalid:<motivo>"
		local profile, isNew = nil, false
		local ok, err = withRetries(function()
			outcome, profile, isNew = nil, nil, false
			store:UpdateAsync(key, function(old)
				local now = Clock.unix()
				if old == nil then
					local fresh = ProfileSchema.default(now)
					fresh.session = { jobId = jobId(), time = now }
					profile, isNew, outcome = fresh, true, "ok"
					return fresh
				end
				if type(old) ~= "table" then
					outcome = "invalid:not_a_table"
					return nil -- cancela la escritura
				end
				local lock = old.session
				if type(lock) == "table" and lock.jobId ~= jobId() and type(lock.time) == "number" then
					if now - lock.time < cfg.SessionLockTimeout then
						outcome = "locked"
						return nil
					end
				end
				-- Se valida sobre una copia ANTES de decidir escribir: si los datos no son
				-- interpretables no se toca absolutamente nada.
				local prepared, perr, warnings = ProfileSchema.prepare(Utilities.deepCopy(old), now)
				if not prepared then
					outcome = "invalid:" .. tostring(perr)
					return nil
				end
				if warnings and #warnings > 0 then
					warn(string.format("[Data] profile %d sanitized: %s", userId, table.concat(warnings, "; ")))
				end
				prepared.session = { jobId = jobId(), time = now }
				profile, outcome = prepared, "ok"
				return prepared
			end)
			return true
		end)
		if not ok then
			return nil, "datastore_error:" .. tostring(err)
		end
		if outcome == "ok" and profile then
			profile.session = nil
			return profile, nil, isNew
		elseif outcome == "locked" then
			if lockAttempt < lockAttempts then
				Clock.sleep(cfg.RetryBaseDelay * 2 ^ lockAttempt)
			end
		else
			return nil, outcome or "unknown"
		end
	end
	return nil, "session_locked"
end

-- Guarda un perfil. `release` libera el bloqueo de sesión; `mustWrite` garantiza que esta llamada
-- escribe el estado actual (no se conforma con un guardado ya en curso). Devuelve ok.
function PlayerDataService.save(userId, release, mustWrite)
	local session = sessions[userId]
	if not session or session.ephemeral or session.lockLost or not store then
		return session ~= nil and session.ephemeral == true
	end
	if session.saving then
		-- Ya hay un guardado en curso; el siguiente ciclo recogerá los cambios, salvo que haya
		-- que liberar el bloqueo o confirmar una escritura (recibos): en ese caso se espera.
		if not release and not mustWrite then
			return true
		end
		local waited = 0
		while session.saving and waited < 10 do
			Clock.sleep(0.1)
			waited += 0.1
		end
	end
	session.saving = true
	local profile = session.profile
	profile.stats.playTime += math.max(0, Clock.now() - session.playTimeMark)
	session.playTimeMark = Clock.now()

	local lost = false
	local ok, err = withRetries(function()
		lost = false
		store:UpdateAsync(keyFor(userId), function(old)
			if type(old) == "table" and type(old.session) == "table" and old.session.jobId ~= jobId() then
				lost = true
				return nil
			end
			local now = Clock.unix()
			local data = Utilities.deepCopy(profile)
			data.lastSave = now
			data.session = (not release) and { jobId = jobId(), time = now } or nil
			return data
		end)
		return true
	end)
	session.saving = false
	if not ok then
		warn(string.format("[Data] SAVE FAILED for %d: %s", userId, tostring(err)))
		return false
	end
	if lost then
		warn(string.format("[Data] session lock lost for %d; no further saves", userId))
		session.lockLost = true
		if session.player and session.player.Parent then
			session.player:Kick("Tu sesión se abrió en otro servidor. Vuelve a entrar.")
		end
		return false
	end
	profile.lastSave = Clock.unix()
	session.lastSaveClock = Clock.now()
	return true
end

local function startSession(player)
	local userId = player.UserId
	if loading[userId] then
		return
	end
	loading[userId] = true
	-- Reentrada rápida al mismo servidor: esperar a que termine el guardado de la sesión anterior.
	local waited = 0
	while sessions[userId] and waited < 20 do
		Clock.sleep(0.1)
		waited += 0.1
	end
	if sessions[userId] then
		loading[userId] = nil
		if player.Parent then
			player:Kick("Tu sesión anterior todavía se está guardando. Vuelve a entrar en unos segundos.")
		end
		return
	end

	local profile, err, isNew
	local ephemeral = false
	if store then
		profile, err, isNew = loadProfile(userId)
	else
		err = "no_datastore"
	end
	if not profile and RunService:IsStudio() and (err == "no_datastore" or string.find(err or "", "datastore_error", 1, true)) then
		warn("[Data] DataStores no disponibles en Studio: usando perfil EN MEMORIA (no se guardará). " .. tostring(err))
		profile, isNew, ephemeral = ProfileSchema.default(Clock.unix()), true, true
	end
	loading[userId] = nil

	if not profile then
		warn(string.format("[Data] load failed for %d: %s", userId, tostring(err)))
		if player.Parent then
			local message = cfg.LoadKickMessage
			if err == "session_locked" then
				message = "Tu partida sigue abierta en otro servidor. Espera unos segundos y vuelve a entrar."
			end
			player:Kick(message)
		end
		return
	end

	-- El jugador pudo irse mientras cargaba: liberar el bloqueo sin tocar nada más.
	if not player.Parent then
		if not ephemeral then
			sessions[userId] = { userId = userId, profile = profile, playTimeMark = Clock.now() }
			PlayerDataService.save(userId, true)
			sessions[userId] = nil
		end
		return
	end

	local session = {
		userId = userId,
		player = player,
		profile = profile,
		isNew = isNew,
		ephemeral = ephemeral,
		previousLastSave = profile.lastSave,
		joinedClock = Clock.now(),
		playTimeMark = Clock.now(),
		lastSaveClock = Clock.now(),
		passes = {},
	}
	sessions[userId] = session
	PlayerDataService.SessionStarted:Fire(session)
end

local function endSession(player)
	local userId = player.UserId
	local session = sessions[userId]
	if not session then
		return
	end
	session.ending = true
	-- Los servicios resuelven su estado (cajas, parcelas...) antes del guardado final.
	PlayerDataService.SessionEnding:Fire(session)
	PlayerDataService.save(userId, true)
	sessions[userId] = nil
end

function PlayerDataService.Init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(cfg.StoreName)
	end)
	if ok then
		store = result
	else
		warn("[Data] GetDataStore failed: " .. tostring(result))
	end
end

function PlayerDataService.Start()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(startSession, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		task.spawn(endSession, player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(startSession, player)
	end

	game:BindToClose(function()
		closing = true
		local pending = 0
		for userId, session in pairs(sessions) do
			pending += 1
			task.spawn(function()
				if not session.ending then
					session.ending = true
					PlayerDataService.SessionEnding:Fire(session)
				end
				PlayerDataService.save(userId, true)
				pending -= 1
			end)
		end
		local waited = 0
		while pending > 0 and waited < 25 do
			Clock.sleep(0.2)
			waited += 0.2
		end
	end)
end

-- Llamado desde el bucle único del servidor.
function PlayerDataService.Update(dt)
	if closing then
		return
	end
	autosaveTimer += dt
	if autosaveTimer < 5 then
		return
	end
	autosaveTimer = 0
	local now = Clock.now()
	for userId, session in pairs(sessions) do
		if not session.ending and not session.saving and now - session.lastSaveClock >= cfg.AutosaveInterval then
			session.lastSaveClock = now -- evita relanzar mientras se guarda
			task.spawn(PlayerDataService.save, userId, false)
		end
	end
end

function PlayerDataService.getSession(userId)
	local session = sessions[userId]
	if session and not session.lockLost then
		return session
	end
	return nil
end

function PlayerDataService.getProfile(userId)
	local session = PlayerDataService.getSession(userId)
	return session and session.profile or nil
end

function PlayerDataService.sessionOf(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil
	end
	return PlayerDataService.getSession(player.UserId)
end

function PlayerDataService.forEach(fn)
	for _, session in pairs(sessions) do
		if not session.lockLost then
			fn(session)
		end
	end
end

function PlayerDataService.count()
	local n = 0
	for _ in pairs(sessions) do
		n += 1
	end
	return n
end

-- Tiempo total de juego (segundos), incluyendo la sesión actual.
function PlayerDataService.playTime(session)
	return session.profile.stats.playTime + math.max(0, Clock.now() - session.playTimeMark)
end

return PlayerDataService
