--!nocheck
-- Arnés de pruebas para ejecutar el código del juego FUERA de Roblox con Lune.
--
-- Qué hace:
--   1. Carga el lugar generado por `rojo build` (el mismo árbol que verá Roblox Studio).
--   2. Ejecuta los ModuleScripts reales con un `require` por instancia, igual que en Roblox.
--   3. Usa las instancias y tipos de datos de `@lune/roblox`, que validan nombres de clases,
--      propiedades y enums contra la base de datos de reflexión de Roblox.
--   4. Simula lo que Lune no trae: señales/eventos, servicios (Players, DataStoreService,
--      MarketplaceService, RunService...), remotos y un reloj controlable.
--
-- Qué NO hace: física, renderizado, replicación real, red, ni la interfaz. Lo que dependa de eso
-- sigue necesitando Roblox Studio (ver docs/STUDIO_CHECKLIST.md).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local luneTask = require("@lune/task")

local Harness = {}
Harness.__index = Harness

local BUILD_PATH = "build/test.rbxl"
local built = false
local placeBytes = nil

---------------------------------------------------------------------------------------------
-- Señales
---------------------------------------------------------------------------------------------
local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ handlers = {}, waiting = {} }, Signal)
end

function Signal:Connect(fn)
	local connection = { Connected = true }
	local handlers = self.handlers
	local entry = { fn = fn, connection = connection }
	table.insert(handlers, entry)
	function connection:Disconnect()
		connection.Connected = false
		local index = table.find(handlers, entry)
		if index then
			table.remove(handlers, index)
		end
	end
	return connection
end

function Signal:Once(fn)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		fn(...)
	end)
	return connection
end

function Signal:Wait()
	local thread = coroutine.running()
	table.insert(self.waiting, thread)
	return coroutine.yield()
end

function Signal:Fire(...)
	for _, entry in ipairs(table.clone(self.handlers)) do
		if entry.connection.Connected then
			luneTask.spawn(Harness.guarded(entry.fn), ...)
		end
	end
	local waiting = self.waiting
	self.waiting = {}
	for _, thread in ipairs(waiting) do
		luneTask.spawn(thread, ...)
	end
end

Harness.Signal = Signal

-- Errores no capturados en hilos lanzados por el código del juego (task.spawn, señales...).
-- En Roblox aparecerían en rojo en la consola; aquí se acumulan para que los tests fallen.
Harness.uncaught = {}

local function guarded(fn)
	return function(...)
		local ok, err = xpcall(fn, function(message)
			return tostring(message) .. "\n" .. debug.traceback("", 2)
		end, ...)
		if not ok then
			table.insert(Harness.uncaught, err)
		end
	end
end
Harness.guarded = guarded

---------------------------------------------------------------------------------------------
-- Estado por instancia (las instancias de Lune no sirven como claves de tabla)
---------------------------------------------------------------------------------------------
local nextUid = 0
local instanceState = {} -- uid -> tabla

local function stateOf(instance)
	local id = instance:GetAttribute("TestUid")
	if id == nil then
		nextUid += 1
		id = nextUid
		instance:SetAttribute("TestUid", id)
	end
	local state = instanceState[id]
	if not state then
		state = { signals = {}, props = {}, instance = instance, watched = {} }
		instanceState[id] = state
	end
	return state
end

local function signalOf(instance, name)
	local state = stateOf(instance)
	local signal = state.signals[name]
	if not signal then
		signal = Signal.new()
		state.signals[name] = signal
	end
	return signal
end

Harness.signalOf = signalOf
Harness.stateOf = stateOf

local current = nil -- arnés activo (los mocks globales lo consultan)

-- Lune no emite señales de cambio por sí mismo. `sweep` las reconstruye comparando el estado
-- actual con el último visto, para las instancias que tienen algún oyente:
--   * GetAttributeChangedSignal / AttributeChanged
--   * GetPropertyChangedSignal
--   * CollectionService:GetInstanceRemovedSignal (instancias destruidas o fuera del árbol)
local TEST_ATTRIBUTE = "TestUid"

local function alive(instance)
	local ok, parent = pcall(function()
		return instance.Parent
	end)
	return ok, parent
end

local function sweepInstance(state)
	local instance = state.instance
	if not instance or not alive(instance) then
		return
	end
	for name, signal in pairs(state.signals) do
		local kind, key = string.match(name, "^(%a+):(.+)$")
		if kind == "attr" or kind == "prop" then
			local ok, value = pcall(function()
				if kind == "attr" then
					return instance:GetAttribute(key)
				end
				return instance[key]
			end)
			if ok then
				local seen = state.watched[name]
				if seen == nil then
					state.watched[name] = { value = value }
				elseif seen.value ~= value then
					seen.value = value
					signal:Fire()
				end
			end
		elseif name == "AttributeChanged" and #signal.handlers > 0 then
			local attributes = instance:GetAttributes()
			local seen = state.watched[name]
			if seen == nil then
				state.watched[name] = attributes
			else
				state.watched[name] = attributes
				for attribute, value in pairs(attributes) do
					if attribute ~= TEST_ATTRIBUTE and seen[attribute] ~= value then
						signal:Fire(attribute)
					end
				end
			end
		end
	end
end

local implemented = false

local function event(className, name)
	roblox.implementProperty(className, name, function(self)
		return signalOf(self, name)
	end)
end

local function storedProperty(className, name, default)
	roblox.implementProperty(className, name, function(self)
		local value = stateOf(self).props[name]
		if value == nil then
			return default
		end
		return value
	end, function(self, value)
		stateOf(self).props[name] = value
	end)
end

local function implementMocks()
	if implemented then
		return
	end
	implemented = true
	local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

	-- Instance
	for _, name in ipairs({ "ChildAdded", "ChildRemoved", "DescendantAdded", "DescendantRemoving", "AncestryChanged", "Destroying", "Changed", "AttributeChanged" }) do
		event("Instance", name)
	end
	roblox.implementMethod("Instance", "WaitForChild", function(self, name)
		return self:FindFirstChild(name)
	end)
	roblox.implementMethod("Instance", "GetAttributeChangedSignal", function(self, name)
		return signalOf(self, "attr:" .. name)
	end)
	roblox.implementMethod("Instance", "GetPropertyChangedSignal", function(self, name)
		return signalOf(self, "prop:" .. name)
	end)

	-- BasePart
	event("BasePart", "Touched")
	event("BasePart", "TouchEnded")
	roblox.implementProperty("BasePart", "Position", function(self)
		return self.CFrame.Position
	end, function(self, value)
		self.CFrame = CFrame.new(value) * self.CFrame.Rotation
	end)
	roblox.implementMethod("BasePart", "GetPivot", function(self)
		return self.CFrame
	end)
	roblox.implementMethod("BasePart", "PivotTo", function(self, cf)
		self.CFrame = cf
	end)
	roblox.implementMethod("BasePart", "SetNetworkOwner", function() end)

	-- Attachment
	roblox.implementProperty("Attachment", "WorldPosition", function(self)
		return (self.Parent.CFrame * self.CFrame).Position
	end)
	roblox.implementProperty("Attachment", "WorldCFrame", function(self)
		return self.Parent.CFrame * self.CFrame
	end)
	roblox.implementProperty("Attachment", "Position", function(self)
		return self.CFrame.Position
	end, function(self, value)
		self.CFrame = CFrame.new(value) * self.CFrame.Rotation
	end)

	-- Model
	roblox.implementMethod("Model", "GetPivot", function(self)
		local primary = self.PrimaryPart
		if primary then
			return primary.CFrame
		end
		for _, d in ipairs(self:GetDescendants()) do
			if d:IsA("BasePart") then
				return d.CFrame
			end
		end
		return CFrame.new()
	end)
	roblox.implementMethod("Model", "PivotTo", function(self, target)
		local pivot = self:GetPivot()
		local delta = target * pivot:Inverse()
		for _, d in ipairs(self:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CFrame = delta * d.CFrame
			end
		end
	end)
	roblox.implementMethod("Model", "ScaleTo", function(self, scale)
		stateOf(self).props.Scale = scale
	end)
	roblox.implementMethod("Model", "GetScale", function(self)
		return stateOf(self).props.Scale or 1
	end)
	roblox.implementMethod("Model", "GetBoundingBox", function(self)
		return self:GetPivot(), Vector3.new(4, 4, 4)
	end)

	-- ProximityPrompt
	for _, name in ipairs({ "Triggered", "TriggerEnded", "PromptButtonHoldBegan", "PromptButtonHoldEnded", "PromptShown", "PromptHidden" }) do
		event("ProximityPrompt", name)
	end

	-- Remotos
	event("RemoteEvent", "OnServerEvent")
	event("RemoteEvent", "OnClientEvent")
	roblox.implementMethod("RemoteEvent", "FireClient", function(self, player, ...)
		if current then
			current:_recordSend(player.UserId, self.Name, table.pack(...), self)
		end
	end)
	roblox.implementMethod("RemoteEvent", "FireAllClients", function(self, ...)
		if current then
			current:_recordSend("all", self.Name, table.pack(...), self)
		end
	end)
	roblox.implementMethod("RemoteEvent", "FireServer", function(self, ...)
		signalOf(self, "OnServerEvent"):Fire(current.localPlayer, ...)
	end)
	storedProperty("RemoteFunction", "OnServerInvoke", nil)
	roblox.implementMethod("RemoteFunction", "InvokeServer", function(self, ...)
		local fn = stateOf(self).props.OnServerInvoke
		return fn and fn(current.localPlayer, ...) or nil
	end)

	-- Player
	storedProperty("Player", "UserId", 0)
	storedProperty("Player", "DisplayName", "Player")
	storedProperty("Player", "Character", nil)
	storedProperty("Player", "RespawnLocation", nil)
	event("Player", "CharacterAdded")
	event("Player", "CharacterRemoving")
	roblox.implementMethod("Player", "Kick", function(self, message)
		if current then
			current:_kick(self, message)
		end
	end)

	-- Humanoid
	event("Humanoid", "Died")
	event("Humanoid", "HealthChanged")

	-- Players
	event("Players", "PlayerAdded")
	event("Players", "PlayerRemoving")
	roblox.implementMethod("Players", "GetPlayers", function(self)
		local list = {}
		for _, child in ipairs(self:GetChildren()) do
			if child:IsA("Player") then
				table.insert(list, child)
			end
		end
		return list
	end)
	roblox.implementMethod("Players", "GetPlayerByUserId", function(self, userId)
		for _, child in ipairs(self:GetChildren()) do
			if child:IsA("Player") and child.UserId == userId then
				return child
			end
		end
		return nil
	end)
	roblox.implementProperty("Players", "LocalPlayer", function()
		return current and current.localPlayer or nil
	end)

	-- Workspace
	roblox.implementMethod("Workspace", "GetServerTimeNow", function()
		return current and current.clock.server or 0
	end)

	-- DataModel
	storedProperty("DataModel", "JobId", "test-job")
	storedProperty("DataModel", "CreatorId", 0)
	storedProperty("DataModel", "PlaceId", 0)
	roblox.implementProperty("DataModel", "CreatorType", function()
		return roblox.Enum.CreatorType.User
	end)
	roblox.implementMethod("DataModel", "BindToClose", function(self, fn)
		if current then
			table.insert(current.closeCallbacks, fn)
		end
	end)
	roblox.implementMethod("DataModel", "IsLoaded", function()
		return true
	end)

	-- GUI
	for _, name in ipairs({ "Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up", "MouseEnter", "MouseLeave", "InputBegan", "InputEnded" }) do
		event("GuiObject", name)
	end
	event("TextBox", "FocusLost")
	roblox.implementProperty("GuiBase2d", "AbsoluteSize", function()
		return roblox.Vector2.new(1280, 720)
	end)
	roblox.implementProperty("GuiBase2d", "AbsolutePosition", function()
		return roblox.Vector2.new(0, 0)
	end)
	roblox.implementProperty("UIListLayout", "AbsoluteContentSize", function()
		return roblox.Vector2.new(100, 100)
	end)
	roblox.implementProperty("UIGridLayout", "AbsoluteContentSize", function()
		return roblox.Vector2.new(100, 100)
	end)
	-- Nota: las propiedades nativas de solo lectura sin valor por defecto (Camera.ViewportSize,
	-- GuiBase2d.AbsoluteSize, BasePart.Position...) no se pueden simular en Lune. El código del
	-- juego las lee de forma tolerante o usa equivalentes (CFrame.Position).

	-- Partículas / sonido
	roblox.implementMethod("ParticleEmitter", "Emit", function(self, count)
		local state = stateOf(self)
		state.props.Emitted = (state.props.Emitted or 0) + (count or 1)
	end)
	roblox.implementMethod("ParticleEmitter", "Clear", function() end)
	roblox.implementMethod("Sound", "Play", function(self)
		stateOf(self).props.Played = (stateOf(self).props.Played or 0) + 1
	end)
	roblox.implementMethod("Sound", "Stop", function() end)
	event("Sound", "Ended")
end

---------------------------------------------------------------------------------------------
-- Servicios simulados
---------------------------------------------------------------------------------------------
local function makeRandomLib()
	local Random = {}
	Random.__index = Random
	function Random.new(seed)
		return setmetatable({ state = (seed or 12345) % 2147483647 }, Random)
	end
	function Random:_next()
		self.state = (self.state * 48271) % 2147483647
		return self.state / 2147483647
	end
	function Random:NextNumber(min, max)
		local v = self:_next()
		if min and max then
			return min + (max - min) * v
		end
		return v
	end
	function Random:NextInteger(min, max)
		return math.min(max, min + math.floor(self:_next() * (max - min + 1)))
	end
	return Random
end

-- Comprueba que un valor se podría guardar en un DataStore (JSON) y devuelve una copia.
local function serialize(value, path)
	local t = type(value)
	if t == "nil" or t == "boolean" or t == "string" then
		return value
	elseif t == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			error("DataStore: non-finite number at " .. path)
		end
		return value
	elseif t == "table" then
		local copy = {}
		local arrayLen = #value
		local keyCount = 0
		for k, v in pairs(value) do
			keyCount += 1
			local kt = type(k)
			if kt == "number" then
				if k % 1 ~= 0 or k < 1 or k > arrayLen then
					error("DataStore: sparse/invalid numeric key at " .. path .. "[" .. tostring(k) .. "]")
				end
			elseif kt ~= "string" then
				error("DataStore: invalid key type " .. kt .. " at " .. path)
			end
			copy[k] = serialize(v, path .. "." .. tostring(k))
		end
		if arrayLen > 0 and keyCount ~= arrayLen then
			error("DataStore: mixed array/dictionary at " .. path)
		end
		return copy
	end
	error("DataStore: cannot store " .. typeof(value) .. " at " .. path)
end

local function makeDataStoreService(h)
	local service = { stores = {}, failNext = 0, failAlways = false, calls = 0 }
	h.datastore = service
	local function maybeFail()
		service.calls += 1
		if service.failAlways then
			error("DataStore request failed (simulated outage)")
		end
		if service.failNext > 0 then
			service.failNext -= 1
			error("DataStore request failed (simulated)")
		end
	end
	function service:GetDataStore(name)
		if service.unavailable then
			error("DataStoreService unavailable (simulated)")
		end
		local data = service.stores[name]
		if not data then
			data = {}
			service.stores[name] = data
		end
		local store = {}
		function store:GetAsync(key)
			maybeFail()
			return serialize(data[key], key)
		end
		function store:SetAsync(key, value)
			maybeFail()
			data[key] = serialize(value, key)
		end
		function store:UpdateAsync(key, transform)
			maybeFail()
			local result = transform(serialize(data[key], key))
			if result ~= nil then
				data[key] = serialize(result, key)
			end
			return result
		end
		function store:RemoveAsync(key)
			maybeFail()
			data[key] = nil
		end
		return store
	end
	return service
end

local function makeMarketplaceService(h)
	local service = {
		ProcessReceipt = nil,
		PromptGamePassPurchaseFinished = Signal.new(),
		PromptProductPurchaseFinished = Signal.new(),
		passes = {}, -- [userId] = { [passId] = true }
		failPassChecks = false,
		prompts = {},
	}
	h.marketplace = service
	function service:UserOwnsGamePassAsync(userId, passId)
		if service.failPassChecks then
			error("UserOwnsGamePassAsync failed (simulated)")
		end
		return service.passes[userId] ~= nil and service.passes[userId][passId] == true
	end
	function service:PromptGamePassPurchase(player, passId)
		table.insert(service.prompts, { kind = "pass", userId = player.UserId, id = passId })
	end
	function service:PromptProductPurchase(player, productId)
		table.insert(service.prompts, { kind = "product", userId = player.UserId, id = productId })
	end
	return service
end

local function makeRunService(h)
	local service = {
		Heartbeat = Signal.new(),
		RenderStepped = Signal.new(),
		Stepped = Signal.new(),
		PreRender = Signal.new(),
		PostSimulation = Signal.new(),
	}
	h.runService = service
	function service:IsStudio()
		return h.isStudio
	end
	function service:IsServer()
		return h.side == "server"
	end
	function service:IsClient()
		return h.side == "client"
	end
	function service:BindToRenderStep() end
	function service:UnbindFromRenderStep() end
	return service
end

local function makeTweenService()
	local service = {}
	function service:Create(instance, _info, goal)
		local tween = { Completed = Signal.new(), PlaybackState = "Begin" }
		function tween:Play()
			for prop, value in pairs(goal) do
				instance[prop] = value
			end
			tween.PlaybackState = "Completed"
			tween.Completed:Fire()
		end
		function tween:Cancel() end
		function tween:Pause() end
		function tween:Destroy() end
		return tween
	end
	function service:GetValue(alpha)
		return alpha
	end
	return service
end

local function makeCollectionService(h)
	-- Tabla propia (no la instancia): los métodos nativos Instance:AddTag/HasTag de Lune tendrían
	-- prioridad sobre cualquier implementación registrada para la clase CollectionService.
	local service = { added = {}, removed = {} }
	local function signal(map, tag)
		local s = map[tag]
		if not s then
			s = Signal.new()
			map[tag] = s
		end
		return s
	end
	service.tracked = {} -- tag -> lista de instancias etiquetadas
	function service:AddTag(instance, tag)
		if instance:HasTag(tag) then
			return
		end
		instance:AddTag(tag)
		service.tracked[tag] = service.tracked[tag] or {}
		table.insert(service.tracked[tag], instance)
		signal(service.added, tag):Fire(instance)
	end
	-- Detecta instancias etiquetadas que han salido del DataModel (destruidas o sin padre).
	function service:sweep()
		for tag, list in pairs(service.tracked) do
			for index = #list, 1, -1 do
				local instance = list[index]
				local ok, inTree = pcall(function()
					return instance:IsDescendantOf(h.game)
				end)
				if not ok or not inTree then
					table.remove(list, index)
					signal(service.removed, tag):Fire(instance)
				end
			end
		end
	end
	function service:RemoveTag(instance, tag)
		if not instance:HasTag(tag) then
			return
		end
		instance:RemoveTag(tag)
		signal(service.removed, tag):Fire(instance)
	end
	function service:HasTag(instance, tag)
		return instance:HasTag(tag)
	end
	function service:GetTagged(tag)
		local list = {}
		for _, d in ipairs(h.game:GetDescendants()) do
			if d:HasTag(tag) then
				table.insert(list, d)
			end
		end
		return list
	end
	function service:GetInstanceAddedSignal(tag)
		return signal(service.added, tag)
	end
	function service:GetInstanceRemovedSignal(tag)
		return signal(service.removed, tag)
	end
	return service
end

local function makeGenericService(extra)
	local service = extra or {}
	return setmetatable(service, {
		__index = function(_, key)
			-- Cualquier evento o método no modelado: señal inerte o función vacía.
			if type(key) == "string" and string.match(key, "^[A-Z]") then
				local known = rawget(service, "__signals")
				if not known then
					known = {}
					rawset(service, "__signals", known)
				end
				if not known[key] then
					local signal = Signal.new()
					local callable = setmetatable({}, {
						__index = signal,
						__call = function()
							return nil
						end,
					})
					known[key] = callable
				end
				return known[key]
			end
			return nil
		end,
	})
end

---------------------------------------------------------------------------------------------
-- Construcción
---------------------------------------------------------------------------------------------
local function ensureBuilt()
	if built then
		return
	end
	if not fs.isDir("build") then
		fs.writeDir("build")
	end
	local result = process.exec("rojo", { "build", "default.project.json", "-o", BUILD_PATH })
	if not result.ok then
		error("rojo build failed:\n" .. result.stderr .. result.stdout)
	end
	placeBytes = fs.readFile(BUILD_PATH)
	built = true
end

-- opts = { side = "server" | "client", isStudio = bool, seed = number }
function Harness.new(opts)
	opts = opts or {}
	ensureBuilt()
	implementMocks()

	local self = setmetatable({}, Harness)
	self.side = opts.side or "server"
	self.isStudio = opts.isStudio == true
	self.game = roblox.deserializePlace(placeBytes)
	self.clock = { t = 1000, unix = 1_750_000_000, server = 50_000 }
	self.sent = {}
	self.kicks = {}
	self.warnings = {}
	self.prints = {}
	self.closeCallbacks = {}
	self.modules = {}
	self.localPlayer = nil
	self.services = {}
	self.quietWarnings = opts.quietWarnings == true
	current = self
	-- Cada arnés empieza con su propio registro de instancias observadas.
	table.clear(instanceState)

	local game = self.game
	local Random = makeRandomLib()
	self.Random = Random

	self.services.RunService = makeRunService(self)
	self.services.DataStoreService = makeDataStoreService(self)
	self.services.MarketplaceService = makeMarketplaceService(self)
	self.services.TweenService = makeTweenService()
	self.services.CollectionService = makeCollectionService(self)
	self.services.Debris = makeGenericService({
		AddItem = function(_, item)
			item:Destroy()
		end,
	})
	self.services.HttpService = makeGenericService({
		GenerateGUID = function()
			return "guid-" .. tostring(math.random(1, 1e9))
		end,
	})
	self.services.UserInputService = makeGenericService({
		TouchEnabled = false,
		KeyboardEnabled = true,
		GamepadEnabled = false,
		MouseEnabled = true,
		GetLastInputType = function()
			return roblox.Enum.UserInputType.Keyboard
		end,
	})
	self.services.GuiService = makeGenericService({
		GetGuiInset = function()
			return roblox.Vector2.new(0, 36), roblox.Vector2.new(0, 0)
		end,
		IsTenFootInterface = function()
			return false
		end,
	})
	self.services.ContextActionService = makeGenericService()
	self.services.ProximityPromptService = makeGenericService()
	self.services.TextChatService = makeGenericService()
	self.services.ContentProvider = makeGenericService()
	self.services.StarterGui = makeGenericService({
		SetCore = function() end,
		SetCoreGuiEnabled = function() end,
	})

	local gameProxy = setmetatable({}, {
		__index = function(_, key)
			if key == "GetService" then
				return function(_, name)
					return self:service(name)
				end
			elseif key == "BindToClose" then
				return function(_, fn)
					table.insert(self.closeCallbacks, fn)
				end
			elseif key == "IsLoaded" then
				return function()
					return true
				end
			elseif key == "FindFirstChild" or key == "GetDescendants" or key == "GetChildren" or key == "WaitForChild" or key == "FindFirstChildOfClass" then
				return function(_, ...)
					return game[key](game, ...)
				end
			elseif key == "JobId" then
				return self.jobId or "test-job"
			elseif key == "CreatorId" then
				return self.creatorId or 0
			elseif key == "CreatorType" then
				return roblox.Enum.CreatorType.User
			elseif key == "PlaceId" then
				return 0
			elseif key == "Workspace" then
				return game:GetService("Workspace")
			elseif key == "Loaded" then
				return Signal.new()
			end
			return game[key]
		end,
	})
	self.gameProxy = gameProxy

	local env = {}
	for _, name in ipairs({
		"Vector3", "Vector2", "CFrame", "Color3", "UDim", "UDim2", "NumberRange", "NumberSequence",
		"NumberSequenceKeypoint", "ColorSequence", "ColorSequenceKeypoint", "BrickColor", "Rect", "Region3",
		"Ray", "Font", "PhysicalProperties", "Faces", "Axes", "Vector2int16", "Vector3int16", "Enum", "Instance",
	}) do
		env[name] = roblox[name]
	end
	env.Random = Random
	env.TweenInfo = {
		new = function(...)
			return { args = { ... } }
		end,
	}
	env.RaycastParams = {
		new = function()
			return {}
		end,
	}
	env.OverlapParams = env.RaycastParams
	env.game = gameProxy
	env.workspace = game:GetService("Workspace")
	local function wrap(fn)
		return type(fn) == "function" and guarded(fn) or fn
	end
	env.task = {
		spawn = function(fn, ...)
			return luneTask.spawn(wrap(fn), ...)
		end,
		defer = function(fn, ...)
			return luneTask.defer(wrap(fn), ...)
		end,
		delay = function(_, fn, ...)
			-- Los retardos reales no avanzan con el reloj simulado: se ejecutan en el siguiente ciclo.
			return luneTask.defer(wrap(fn), ...)
		end,
		cancel = luneTask.cancel,
		wait = function()
			luneTask.wait(0)
			return 0
		end,
	}
	env.wait = env.task.wait
	env.tick = function()
		return self.clock.t
	end
	env.time = env.tick
	env.os = {
		time = function()
			return math.floor(self.clock.unix)
		end,
		clock = function()
			return self.clock.t
		end,
		date = os.date,
	}
	env.print = function(...)
		local parts = table.pack(...)
		for i = 1, parts.n do
			parts[i] = tostring(parts[i])
		end
		table.insert(self.prints, table.concat(parts, " "))
	end
	env.warn = function(...)
		local parts = table.pack(...)
		for i = 1, parts.n do
			parts[i] = tostring(parts[i])
		end
		local text = table.concat(parts, " ")
		table.insert(self.warnings, text)
	end
	for _, name in ipairs({
		"assert", "error", "ipairs", "pairs", "next", "pcall", "xpcall", "select", "tonumber", "tostring", "type",
		"typeof", "unpack", "rawget", "rawset", "rawequal", "rawlen", "setmetatable", "getmetatable", "newproxy",
		"math", "string", "table", "coroutine", "utf8", "bit32", "buffer", "debug", "vector",
	}) do
		env[name] = _G[name] or getfenv()[name]
	end
	-- Los errores de Lune son userdata: `debug.traceback(err)` fallaría dentro de xpcall
	-- ("error in error handling"), así que se convierte a texto antes.
	env.debug = {
		traceback = function(message, level)
			local ok, trace = pcall(debug.traceback, "", (tonumber(level) or 1) + 1)
			return tostring(message) .. (ok and trace or "")
		end,
		info = debug.info,
		profilebegin = function() end,
		profileend = function() end,
	}
	self.env = env

	-- Reloj controlado.
	local Clock = self:require("ReplicatedStorage.Shared.Clock")
	Clock.now = function()
		return self.clock.t
	end
	Clock.unix = function()
		return math.floor(self.clock.unix)
	end
	Clock.server = function()
		return self.clock.server
	end
	Clock.sleep = function(seconds)
		self:advance(seconds or 0)
	end
	self.Clock = Clock

	return self
end

function Harness:service(name)
	local mock = self.services[name]
	if mock then
		return mock
	end
	if name == "Players" then
		-- `LocalPlayer` es una propiedad nativa (siempre nil en Lune): se sirve a través de un
		-- proxy que delega todo lo demás en la instancia real.
		local players = self.game:GetService("Players")
		local harness = self
		local proxy = setmetatable({}, {
			__index = function(_, key)
				if key == "LocalPlayer" then
					return harness.localPlayer
				end
				local value = players[key]
				if type(value) == "function" then
					return function(_, ...)
						return value(players, ...)
					end
				end
				return value
			end,
		})
		self.services.Players = proxy
		return proxy
	end
	return self.game:GetService(name)
end

function Harness:advance(seconds)
	self.clock.t += seconds
	self.clock.unix += seconds
	self.clock.server += seconds
end

-- Resuelve "ReplicatedStorage.Shared.Logic.EconomyMath" a una instancia.
function Harness:find(path)
	local parts = string.split(path, ".")
	local node = self.game:GetService(parts[1])
	for i = 2, #parts do
		local child = node:FindFirstChild(parts[i])
		if not child then
			error("path not found: " .. path .. " (at " .. parts[i] .. ")")
		end
		node = child
	end
	return node
end

function Harness:require(target)
	local instance = target
	if type(target) == "string" then
		instance = self:find(target)
	end
	if typeof(instance) ~= "Instance" then
		error("require: expected an Instance, got " .. typeof(instance), 2)
	end
	local key = instance:GetFullName()
	local cached = self.modules[key]
	if cached then
		if cached.loading then
			error("circular require detected: " .. key, 2)
		end
		return cached.value
	end
	if not instance:IsA("LuaSourceContainer") then
		error("require: " .. key .. " is not a script", 2)
	end
	local record = { loading = true }
	self.modules[key] = record

	local env = table.clone(self.env)
	env.script = instance
	env.require = function(inner)
		return self:require(inner)
	end
	env._G = env
	env.shared = env
	local fn = luau.load(instance.Source, { debugName = key, environment = env })
	local result = table.pack(fn())
	record.loading = false
	record.value = result[1]
	return result[1]
end

-- Ejecuta un Script/LocalScript (p. ej. Bootstrap).
function Harness:run(path)
	return self:require(path)
end

-- Lune no simula física: las piezas unidas con `Weld` no siguen a su Part0. Esta pasada coloca
-- cada Part1 donde la pondría el motor (Part0.CFrame * C0 * C1^-1) para los modelos visuales de
-- las criaturas, de modo que anclajes, auras y efectos se calculen en su posición real.
function Harness:solveWelds()
	local folder = self.game:GetService("Workspace"):FindFirstChild("FTB_Creatures")
	if not folder then
		return
	end
	for _, d in ipairs(folder:GetDescendants()) do
		if d.ClassName == "Weld" then
			local p0, p1 = d.Part0, d.Part1
			if p0 and p1 then
				p1.CFrame = p0.CFrame * d.C0 * d.C1:Inverse()
			end
		end
	end
end

-- Emite las señales de cambio pendientes (atributos, propiedades, instancias eliminadas).
function Harness:sweep()
	for _, state in pairs(instanceState) do
		if next(state.signals) ~= nil then
			sweepInstance(state)
		end
	end
	self.services.CollectionService:sweep()
end

function Harness:settle(rounds)
	for _ = 1, rounds or 4 do
		luneTask.wait(0)
	end
	self:sweep()
	luneTask.wait(0)
end

-- Avanza la simulación: `steps` latidos de `dt` segundos.
function Harness:step(dt, steps)
	current = self
	for _ = 1, steps or 1 do
		self:advance(dt)
		self.runService.Heartbeat:Fire(dt)
		luneTask.wait(0)
		self:sweep()
	end
	luneTask.wait(0)
end

---------------------------------------------------------------------------------------------
-- Remotos y jugadores
---------------------------------------------------------------------------------------------
function Harness:_recordSend(target, name, args, remote)
	table.insert(self.sent, { to = target, name = name, args = args })
	-- Con un cliente arrancado en el mismo DataModel, los mensajes del servidor le llegan de verdad.
	if self.clientBooted and remote and self.localPlayer and (target == "all" or target == self.localPlayer.UserId) then
		-- Como en Roblox, la eliminación de instancias llega al cliente antes que los eventos
		-- remotos posteriores.
		self.services.CollectionService:sweep()
		signalOf(remote, "OnClientEvent"):Fire(table.unpack(args, 1, args.n))
	end
end

function Harness:_kick(player, message)
	table.insert(self.kicks, { userId = player.UserId, message = message })
	self:removePlayer(player)
end

function Harness:remote(name)
	local folder = self.game:GetService("ReplicatedStorage"):FindFirstChild("FTB_Remotes")
	return folder and folder:FindFirstChild(name)
end

function Harness:fire(player, name, ...)
	current = self
	local remote = self:remote(name)
	assert(remote, "no remote " .. name)
	signalOf(remote, "OnServerEvent"):Fire(player, ...)
	self:settle(2)
end

function Harness:invoke(player, name, ...)
	current = self
	local remote = self:remote(name)
	assert(remote, "no remote " .. name)
	local fn = stateOf(remote).props.OnServerInvoke
	assert(fn, "no OnServerInvoke for " .. name)
	return fn(player, ...)
end

-- Mensajes enviados a un jugador (incluye los enviados a todos).
function Harness:sentTo(userId, name)
	local list = {}
	for _, message in ipairs(self.sent) do
		if message.name == name and (message.to == userId or message.to == "all") then
			table.insert(list, message.args)
		end
	end
	return list
end

function Harness:clearSent()
	self.sent = {}
end

-- Estado visible acumulado de un jugador (fusiona todos los parches "State").
function Harness:stateFor(userId)
	local view = {}
	for _, message in ipairs(self.sent) do
		if message.name == "State" and message.to == userId then
			for key, value in pairs(message.args[1]) do
				view[key] = value
			end
		end
	end
	return view
end

function Harness:notifications(userId)
	local list = {}
	for _, args in ipairs(self:sentTo(userId, "Notify")) do
		table.insert(list, args[1])
	end
	return list
end

function Harness:addPlayer(userId, name)
	current = self
	local Players = self.game:GetService("Players")
	local player = roblox.Instance.new("Player")
	player.Name = name or ("Player" .. userId)
	player.UserId = userId
	player.DisplayName = name or ("Player" .. userId)
	player.Parent = Players
	signalOf(Players, "PlayerAdded"):Fire(player)
	self:settle(6)
	return player
end

function Harness:spawnCharacter(player, position)
	current = self
	local Instance, CFrame, Vector3 = roblox.Instance, roblox.CFrame, roblox.Vector3
	local character = Instance.new("Model")
	character.Name = player.Name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(position or Vector3.new(0, 5, 0))
	root.Parent = character
	character.PrimaryPart = root
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = character
	character.Parent = self.game:GetService("Workspace")
	player.Character = character
	signalOf(player, "CharacterAdded"):Fire(character)
	self:settle(8)
	return character
end

function Harness:rootOf(player)
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

function Harness:moveTo(player, position)
	local root = self:rootOf(player)
	assert(root, "player has no character")
	root.CFrame = roblox.CFrame.new(position)
end

function Harness:positionOf(player)
	return self:rootOf(player).CFrame.Position
end

function Harness:kill(player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	assert(humanoid, "no humanoid")
	signalOf(humanoid, "Died"):Fire()
	self:settle(3)
end

function Harness:removePlayer(player)
	current = self
	local Players = self.game:GetService("Players")
	if player.Parent == nil then
		return
	end
	signalOf(Players, "PlayerRemoving"):Fire(player)
	self:settle(6)
	-- Como en Roblox, el personaje sale del árbol; no se destruye para que el código que aún
	-- tenga una referencia pueda leer `.Parent` (nil) sin error.
	local character = player.Character
	if character then
		character.Parent = nil
	end
	player.Parent = nil
end

-- Simula el cierre del servidor (BindToClose).
function Harness:close()
	current = self
	for _, fn in ipairs(self.closeCallbacks) do
		fn()
	end
	self:settle(4)
end

-- Arranca el servidor completo y devuelve la tabla de servicios.
function Harness:bootServer()
	current = self
	self:run("ServerScriptService.Server.Bootstrap")
	self:settle(4)
	local names = {
		"ValidationService", "PlotService", "CharacterService", "StateService", "EconomyService", "CreatureService",
		"MutationService", "VFXService", "FoodService", "FeedingService", "ShopService", "RebirthService",
		"TheftService", "EventService", "MonetizationService", "LeaderboardService", "AdminService", "PlayerDataService",
	}
	local services = {}
	for _, name in ipairs(names) do
		services[name] = self:require("ServerScriptService.Server.Services." .. name)
	end
	self.server = services
	return services
end

-- Jugador listo para jugar: sesión cargada, personaje en su parcela.
function Harness:joinPlayer(userId, name)
	local player = self:addPlayer(userId, name)
	if player.Parent == nil then
		return player, nil
	end
	self:spawnCharacter(player)
	self:step(0.1, 2)
	local session = self.server.PlayerDataService.getSession(userId)
	return player, session
end

---------------------------------------------------------------------------------------------
-- Cliente
---------------------------------------------------------------------------------------------
-- Arranca el cliente real (Bootstrap.client) para `player` en el MISMO DataModel que el servidor:
-- los remotos quedan conectados en ambos sentidos. opts = { touch = bool }
function Harness:bootClient(player, opts)
	opts = opts or {}
	current = self
	self.localPlayer = player
	if opts.touch then
		self.services.UserInputService.TouchEnabled = true
		self.services.UserInputService.KeyboardEnabled = false
	end
	local playerGui = roblox.Instance.new("PlayerGui")
	playerGui.Name = "PlayerGui"
	playerGui.Parent = player
	self.playerGui = playerGui
	local camera = roblox.Instance.new("Camera")
	camera.Name = "Camera"
	camera.CFrame = roblox.CFrame.new(0, 20, 40)
	camera.Parent = self.game:GetService("Workspace")
	self.game:GetService("Workspace").CurrentCamera = camera
	self.camera = camera
	self.clientBooted = true
	self:run("StarterPlayer.StarterPlayerScripts.Client.Bootstrap")
	self:settle(6)
	local names = {
		"StateController", "SettingsController", "EffectCleanup", "AudioController", "EffectsController",
		"AuraController", "CreatureController", "CameraController", "WorldController", "InputController", "UIController",
	}
	local controllers = {}
	for _, name in ipairs(names) do
		controllers[name] = self:require("StarterPlayer.StarterPlayerScripts.Client.Controllers." .. name)
	end
	self.client = controllers
	return controllers
end

-- Avanza el cliente: `steps` frames de `dt` segundos (también avanza el reloj).
function Harness:frame(dt, steps)
	current = self
	for _ = 1, steps or 1 do
		self:advance(dt)
		self:solveWelds()
		self.runService.RenderStepped:Fire(dt)
		luneTask.wait(0)
		self:sweep()
	end
	luneTask.wait(0)
end

-- Servidor y cliente a la vez.
function Harness:tick(dt, steps)
	current = self
	for _ = 1, steps or 1 do
		self:advance(dt)
		self.runService.Heartbeat:Fire(dt)
		luneTask.wait(0)
		self:sweep()
		luneTask.wait(0)
		self:solveWelds()
		self.runService.RenderStepped:Fire(dt)
		luneTask.wait(0)
	end
	luneTask.wait(0)
end

-- Coloca la cámara del cliente cerca de un punto (el LOD de animaciones y auras depende de ella).
function Harness:lookAt(position)
	self.camera.CFrame = roblox.CFrame.new(position + roblox.Vector3.new(0, 12, -24))
end

-- Simula la pulsación de un botón de la interfaz.
function Harness:click(button)
	current = self
	signalOf(button, "Activated"):Fire()
	self:settle(3)
end

-- Busca un descendiente por nombre (búsqueda en profundidad).
function Harness:findUI(rootInstance, name)
	return rootInstance:FindFirstChild(name, true)
end

function Harness:use()
	current = self
end

Harness.roblox = roblox

return Harness
