--!nocheck
-- Utilidades comunes de las baterías de pruebas.
local Harness = require("./Harness")

local Fixtures = {}

local roblox = Harness.roblox
Fixtures.Vector3 = roblox.Vector3
Fixtures.CFrame = roblox.CFrame

local STORE = "FTB_PlayerData_v1"
Fixtures.STORE = STORE

-- Servidor arrancado y determinista: sin eventos ni cajas aleatorias salvo que se pidan.
-- opts = { isStudio, events = bool, crates = bool, store = tabla de datos previos, datastoreUnavailable }
function Fixtures.server(opts)
	opts = opts or {}
	local h = Harness.new({ isStudio = opts.isStudio == true })
	if opts.store then
		h.datastore.stores[STORE] = opts.store
	end
	if opts.datastoreUnavailable then
		h.datastore.unavailable = true
	end
	local EventConfig = h:require("ReplicatedStorage.Shared.Config.EventConfig")
	EventConfig.Enabled = opts.events == true
	local TheftConfig = h:require("ReplicatedStorage.Shared.Config.TheftConfig")
	if not opts.crates then
		TheftConfig.SpawnInterval = math.huge
	end
	if opts.before then
		opts.before(h)
	end
	local s = h:bootServer()
	return h, s
end

function Fixtures.config(h, name)
	return h:require("ReplicatedStorage.Shared.Config." .. name)
end

function Fixtures.logic(h, name)
	return h:require("ReplicatedStorage.Shared.Logic." .. name)
end

function Fixtures.storeData(h)
	return h.datastore.stores[STORE]
end

function Fixtures.saved(h, userId)
	local data = h.datastore.stores[STORE]
	return data and data["player_" .. tostring(userId)]
end

function Fixtures.deepCopy(t)
	if type(t) ~= "table" then
		return t
	end
	local copy = {}
	for k, v in pairs(t) do
		copy[k] = Fixtures.deepCopy(v)
	end
	return copy
end

function Fixtures.count(t)
	local n = 0
	for _ in pairs(t) do
		n += 1
	end
	return n
end

-- Primera criatura del perfil (la inicial).
function Fixtures.firstCreature(session)
	local ids = {}
	for id in pairs(session.profile.creatures) do
		table.insert(ids, id)
	end
	table.sort(ids)
	return session.profile.creatures[ids[1]], ids[1]
end

-- Coloca al jugador junto a una de sus criaturas (o la de otro jugador con `ownerSession`).
function Fixtures.goToCreature(h, s, player, ownerSession, creatureId)
	local position = s.CreatureService.positionOf(ownerSession, creatureId)
	assert(position, "creature has no position")
	h:moveTo(player, position + Fixtures.Vector3.new(0, 3, -6))
	return position
end

function Fixtures.goTo(h, player, position, lift)
	h:moveTo(player, Fixtures.Vector3.new(position.X, position.Y + (lift or 3), position.Z))
end

-- Dispara un remoto dejando pasar tiempo suficiente para no chocar con el rate limit.
function Fixtures.act(h, player, name, ...)
	h:advance(1.5)
	h:fire(player, name, ...)
end

function Fixtures.lastNotification(h, userId)
	local list = h:notifications(userId)
	return list[#list]
end

function Fixtures.hasWarning(h, pattern)
	for _, text in ipairs(h.warnings) do
		if string.find(text, pattern, 1, true) then
			return true
		end
	end
	return false
end

return Fixtures
