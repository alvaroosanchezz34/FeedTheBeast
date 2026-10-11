-- Limpieza centralizada de instancias y conexiones temporales de efectos.
-- Todo lo que crea un efecto puntual pasa por aquí con una caducidad, de modo que nada queda
-- huérfano aunque el efecto se interrumpa (cambio de calidad, criatura destruida, etc.).
local EffectCleanup = {}

local items = {} -- { instance?, connection?, callback?, expires }
local clock = 0

-- Destruye `instance` cuando pasen `lifetime` segundos.
function EffectCleanup.track(instance, lifetime)
	table.insert(items, { instance = instance, expires = clock + lifetime })
	return instance
end

function EffectCleanup.trackConnection(connection, lifetime)
	table.insert(items, { connection = connection, expires = clock + lifetime })
	return connection
end

-- Ejecuta `callback` cuando pasen `lifetime` segundos (p. ej. devolver un emisor al pool).
function EffectCleanup.after(lifetime, callback)
	table.insert(items, { callback = callback, expires = clock + lifetime })
end

local function dispose(item)
	if item.instance then
		item.instance:Destroy()
	end
	if item.connection then
		item.connection:Disconnect()
	end
	if item.callback then
		local ok, err = pcall(item.callback)
		if not ok then
			warn("[EffectCleanup] callback failed: " .. tostring(err))
		end
	end
end

function EffectCleanup.Update(dt)
	clock += dt
	local index = 1
	while index <= #items do
		local item = items[index]
		if clock >= item.expires then
			items[index] = items[#items]
			items[#items] = nil
			dispose(item)
		else
			index += 1
		end
	end
end

-- Elimina inmediatamente todo lo pendiente.
function EffectCleanup.clearAll()
	local pending = items
	items = {}
	for _, item in ipairs(pending) do
		dispose(item)
	end
end

function EffectCleanup.count()
	return #items
end

return EffectCleanup
