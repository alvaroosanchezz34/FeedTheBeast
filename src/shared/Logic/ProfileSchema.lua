-- Esquema del perfil del jugador: valores por defecto, migraciones y validación (puro).
--
-- Política: `migrate` y `validate` NUNCA devuelven un perfil vacío ante datos raros. Si los datos
-- no se pueden interpretar con seguridad devuelven error y el llamador debe negarse a cargar
-- (y por tanto a guardar), para no sobrescribir datos válidos anteriores.
local Config = script.Parent.Parent.Config
local GameConfig = require(Config.GameConfig)
local CreatureConfig = require(Config.CreatureConfig)
local MutationConfig = require(Config.MutationConfig)
local FoodConfig = require(Config.FoodConfig)
local UpgradeConfig = require(Config.UpgradeConfig)
local EconomyConfig = require(Config.EconomyConfig)
local MonetizationConfig = require(Config.MonetizationConfig)
local VFXConfig = require(Config.VFXConfig)
local QuestConfig = require(Config.QuestConfig)

local ProfileSchema = {}

ProfileSchema.CURRENT_VERSION = 3

local function isFinite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

function ProfileSchema.default(now)
	now = now or 0
	local profile = {
		version = ProfileSchema.CURRENT_VERSION,
		createdAt = now,
		lastSave = now,
		coins = GameConfig.StartingCoins,
		pendingCoins = 0,
		pendingOffline = 0,
		inventory = {},
		creatures = {},
		nextCreatureId = 1,
		collection = {},
		upgrades = {},
		rebirths = 0,
		boosts = {},
		cosmetics = {},
		stats = {
			playTime = 0,
			foodsCollected = 0,
			foodsFed = 0,
			eggsHatched = 0,
			cratesDelivered = 0,
			cratesStolen = 0,
			cratesRecovered = 0,
			totalCoinsEarned = 0,
			giantFeeds = 0,
			questsClaimed = 0,
		},
		flags = {},
		settings = { vfxQuality = "Auto", sfxVolume = 1, musicVolume = 1 },
		receipts = {},
		-- Tareas diarias: día UTC del tablero, lista { id, progress, claimed } y premio extra.
		quests = { day = 0, list = {}, bonusClaimed = false },
	}
	return profile
end

function ProfileSchema.collectionKey(speciesId, mutationId)
	return speciesId .. ":" .. mutationId
end

-- Crea una criatura nueva dentro del perfil y la devuelve.
function ProfileSchema.addCreature(profile, speciesId, mutationId, slot, now)
	local id = "c" .. tostring(profile.nextCreatureId)
	profile.nextCreatureId += 1
	local creature = {
		id = id,
		species = speciesId,
		mutation = mutationId or "NORMAL",
		growth = 0,
		slot = slot or 0, -- 0 = guardada (no colocada)
		born = now or 0,
	}
	profile.creatures[id] = creature
	profile.collection[ProfileSchema.collectionKey(speciesId, creature.mutation)] = true
	return creature
end

function ProfileSchema.creatureCount(profile)
	local n = 0
	for _ in pairs(profile.creatures) do
		n += 1
	end
	return n
end

---------------------------------------------------------------------------------------------
-- Migraciones: MIGRATIONS[v] transforma un perfil de versión v a v + 1.
---------------------------------------------------------------------------------------------
local MIGRATIONS = {
	-- v1 -> v2: se añaden colección, ajustes, cosméticos, recibos y ganancias offline pendientes.
	[1] = function(data)
		data.collection = data.collection or {}
		if type(data.creatures) == "table" then
			for _, creature in pairs(data.creatures) do
				if type(creature) == "table" and type(creature.species) == "string" then
					local mutation = type(creature.mutation) == "string" and creature.mutation or "NORMAL"
					data.collection[creature.species .. ":" .. mutation] = true
				end
			end
		end
		data.settings = data.settings or { vfxQuality = "Auto", sfxVolume = 1, musicVolume = 1 }
		data.cosmetics = data.cosmetics or {}
		data.receipts = data.receipts or {}
		data.pendingOffline = data.pendingOffline or 0
		data.flags = data.flags or {}
		data.version = 2
		return data
	end,
	-- v2 -> v3: tareas diarias (el tablero se genera en la primera sesión).
	[2] = function(data)
		if type(data.quests) ~= "table" then
			data.quests = { day = 0, list = {}, bonusClaimed = false }
		end
		data.version = 3
		return data
	end,
}

-- Devuelve (perfil, nil) o (nil, motivoError). No modifica `data` si falla antes de migrar.
function ProfileSchema.migrate(data)
	if type(data) ~= "table" then
		return nil, "not_a_table"
	end
	local version = data.version
	if type(version) ~= "number" or version % 1 ~= 0 or version < 1 then
		return nil, "bad_version"
	end
	if version > ProfileSchema.CURRENT_VERSION then
		-- Datos de una versión más nueva del juego: no se tocan.
		return nil, "newer_version"
	end
	while version < ProfileSchema.CURRENT_VERSION do
		local step = MIGRATIONS[version]
		if not step then
			return nil, "missing_migration_" .. version
		end
		local ok, result = pcall(step, data)
		if not ok or type(result) ~= "table" then
			return nil, "migration_failed_" .. version
		end
		data = result
		if data.version ~= version + 1 then
			return nil, "migration_bad_version_" .. version
		end
		version = data.version
	end
	return data, nil
end

---------------------------------------------------------------------------------------------
-- Validación estructural estricta (errores graves => no cargar).
---------------------------------------------------------------------------------------------
function ProfileSchema.validate(profile)
	if type(profile) ~= "table" then
		return false, "not_a_table"
	end
	if profile.version ~= ProfileSchema.CURRENT_VERSION then
		return false, "wrong_version"
	end
	if not isFinite(profile.coins) then
		return false, "coins_not_finite"
	end
	for _, field in ipairs({ "inventory", "creatures", "collection", "upgrades", "stats", "flags", "settings", "receipts", "boosts", "cosmetics", "quests" }) do
		if type(profile[field]) ~= "table" then
			return false, field .. "_not_a_table"
		end
	end
	if not isFinite(profile.rebirths) or not isFinite(profile.nextCreatureId) then
		return false, "counters_not_finite"
	end
	return true, nil
end

---------------------------------------------------------------------------------------------
-- Saneado: corrige valores fuera de rango sin destruir el resto. Devuelve lista de avisos.
---------------------------------------------------------------------------------------------
function ProfileSchema.sanitize(profile, now)
	local warnings = {}
	local function warn(msg)
		table.insert(warnings, msg)
	end
	local function num(value, default, min, max, integer)
		if not isFinite(value) then
			return default, true
		end
		local v = value
		if integer then
			v = math.floor(v)
		end
		v = math.clamp(v, min, max)
		return v, v ~= value
	end

	local changed
	profile.coins, changed = num(profile.coins, 0, 0, EconomyConfig.MaxCoins, true)
	if changed then warn("coins clamped") end
	profile.pendingCoins = num(profile.pendingCoins, 0, 0, EconomyConfig.MaxCoins, true)
	profile.pendingOffline = num(profile.pendingOffline, 0, 0, EconomyConfig.MaxCoins, true)
	profile.rebirths, changed = num(profile.rebirths, 0, 0, EconomyConfig.Rebirth.MaxRebirths, true)
	if changed then warn("rebirths clamped") end
	profile.createdAt = num(profile.createdAt, now or 0, 0, 2 ^ 40, true)
	profile.lastSave = num(profile.lastSave, now or 0, 0, 2 ^ 40, true)

	-- Inventario
	for foodId, count in pairs(profile.inventory) do
		if type(foodId) ~= "string" or not FoodConfig.Foods[foodId] then
			profile.inventory[foodId] = nil
			warn("unknown food removed: " .. tostring(foodId))
		else
			local v = num(count, 0, 0, 100000, true)
			profile.inventory[foodId] = v > 0 and v or nil
		end
	end

	-- Mejoras
	for upgradeId, level in pairs(profile.upgrades) do
		local def = type(upgradeId) == "string" and UpgradeConfig.Upgrades[upgradeId] or nil
		if not def then
			profile.upgrades[upgradeId] = nil
			warn("unknown upgrade removed: " .. tostring(upgradeId))
		else
			profile.upgrades[upgradeId] = num(level, 0, 0, def.maxLevel, true)
		end
	end

	-- Criaturas
	local maxSlots = GameConfig.World.MaxSlotsPerPlot
	local usedSlots = {}
	local highestId = 0
	local ids = {}
	for id in pairs(profile.creatures) do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		return tostring(a) < tostring(b)
	end)
	for _, id in ipairs(ids) do
		local creature = profile.creatures[id]
		local valid = type(id) == "string"
			and type(creature) == "table"
			and type(creature.species) == "string"
			and CreatureConfig.Species[creature.species] ~= nil
		if not valid then
			profile.creatures[id] = nil
			warn("invalid creature removed: " .. tostring(id))
		else
			creature.id = id
			if not MutationConfig.Mutations[creature.mutation] then
				creature.mutation = "NORMAL"
				warn("unknown mutation reset on " .. id)
			end
			creature.growth = num(creature.growth, 0, 0, 1e12, false)
			creature.born = num(creature.born, 0, 0, 2 ^ 40, true)
			local slot = num(creature.slot, 0, 0, maxSlots, true)
			if slot > 0 and usedSlots[slot] then
				slot = 0
				warn("duplicate slot cleared on " .. id)
			end
			if slot > 0 then
				usedSlots[slot] = true
			end
			creature.slot = slot
			local n = tonumber(string.match(id, "^c(%d+)$"))
			if n and n > highestId then
				highestId = n
			end
			profile.collection[ProfileSchema.collectionKey(creature.species, creature.mutation)] = true
		end
	end
	profile.nextCreatureId = math.max(num(profile.nextCreatureId, 1, 1, 2 ^ 40, true), highestId + 1)

	-- Colección
	for key, value in pairs(profile.collection) do
		local species, mutation = nil, nil
		if type(key) == "string" then
			species, mutation = string.match(key, "^([%w_]+):([%w_]+)$")
		end
		if not species or not CreatureConfig.Species[species] or not MutationConfig.Mutations[mutation] or value ~= true then
			profile.collection[key] = nil
		end
	end

	-- Boosts (timestamps unix de caducidad)
	for key, expires in pairs(profile.boosts) do
		if type(key) ~= "string" or not isFinite(expires) then
			profile.boosts[key] = nil
		elseif now and expires > now + MonetizationConfig.MaxBoostSeconds then
			profile.boosts[key] = now + MonetizationConfig.MaxBoostSeconds
			warn("boost clamped: " .. key)
		end
	end

	-- Estadísticas
	local defaults = ProfileSchema.default(0).stats
	for key, default in pairs(defaults) do
		profile.stats[key] = num(profile.stats[key], default, 0, 1e15, false)
	end

	-- Ajustes
	local settings = profile.settings
	if settings.vfxQuality ~= "Auto" and not VFXConfig.Quality[settings.vfxQuality] then
		settings.vfxQuality = "Auto"
	end
	settings.sfxVolume = num(settings.sfxVolume, 1, 0, 1, false)
	settings.musicVolume = num(settings.musicVolume, 1, 0, 1, false)

	-- Tareas: entradas desconocidas fuera; progreso acotado; `claimed` exige progreso completo.
	local quests = profile.quests
	quests.day = num(quests.day, 0, 0, 2 ^ 31, true)
	quests.bonusClaimed = quests.bonusClaimed == true
	local list = {}
	if type(quests.list) == "table" then
		for _, entry in ipairs(quests.list) do
			local def = type(entry) == "table" and type(entry.id) == "string" and QuestConfig.Quests[entry.id] or nil
			if def and #list < QuestConfig.DailyCount then
				local progress = num(entry.progress, 0, 0, def.goal, true)
				table.insert(list, { id = def.id, progress = progress, claimed = entry.claimed == true and progress >= def.goal })
			else
				warn("invalid quest entry removed")
			end
		end
	end
	quests.list = list

	-- Recibos: lista de strings, acotada.
	local receipts = {}
	for _, r in ipairs(profile.receipts) do
		if type(r) == "string" and #r <= 100 then
			table.insert(receipts, r)
		end
	end
	while #receipts > MonetizationConfig.ReceiptHistory do
		table.remove(receipts, 1)
	end
	profile.receipts = receipts

	return warnings
end

-- Carga completa: migra + valida + sanea. Devuelve (perfil, nil, avisos) o (nil, error).
function ProfileSchema.prepare(data, now)
	local migrated, err = ProfileSchema.migrate(data)
	if not migrated then
		return nil, err
	end
	-- Rellena campos ausentes con valores por defecto (sin pisar los existentes).
	local defaults = ProfileSchema.default(now)
	for key, value in pairs(defaults) do
		if migrated[key] == nil then
			migrated[key] = value
		end
	end
	local ok, verr = ProfileSchema.validate(migrated)
	if not ok then
		return nil, verr
	end
	local warnings = ProfileSchema.sanitize(migrated, now)
	return migrated, nil, warnings
end

return ProfileSchema
