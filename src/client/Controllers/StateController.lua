-- Estado visible del jugador local. Solo refleja lo que envía el servidor (remoto "State");
-- el cliente nunca lo modifica para "ganar" nada. También guarda estado puramente local
-- (comida seleccionada) y da acceso a los remotos.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteDefinitions = require(Shared.RemoteDefinitions)
local Signal = require(Shared.Signal)

local StateController = {}

StateController.Changed = Signal.new() -- (clave, valor)
StateController.Notified = Signal.new() -- (datos de notificación)
StateController.SelectedFoodChanged = Signal.new()

local state = {}
local listeners = {} -- clave -> { fn }
local remotes
local selectedFood = nil
local boostsReceivedAt = 0

function StateController.remote(name)
	return remotes:WaitForChild(name)
end

-- Envía una intención al servidor.
function StateController.send(name, ...)
	local remote = remotes:FindFirstChild(name)
	if remote then
		remote:FireServer(...)
	end
end

function StateController.get(key)
	return state[key]
end

function StateController.all()
	return state
end

-- Ejecuta fn(valor) cuando cambie la clave (y ahora mismo si ya hay valor).
function StateController.observe(key, fn)
	listeners[key] = listeners[key] or {}
	table.insert(listeners[key], fn)
	if state[key] ~= nil then
		task.spawn(fn, state[key])
	end
end

function StateController.selectedFood()
	local inventory = state.inventory or {}
	if selectedFood and (inventory[selectedFood] or 0) > 0 then
		return selectedFood
	end
	return nil
end

function StateController.selectFood(foodId)
	if selectedFood ~= foodId then
		selectedFood = foodId
		StateController.SelectedFoodChanged:Fire(foodId)
	end
end

-- Segundos restantes de un boost (cuenta atrás local desde el último parche).
function StateController.boostRemaining(boostId)
	local boosts = state.boosts
	if not boosts or not boosts[boostId] then
		return 0
	end
	return math.max(0, boosts[boostId] - (os.clock() - boostsReceivedAt))
end

function StateController.localUserId()
	return Players.LocalPlayer.UserId
end

local function applyPatch(patch)
	if type(patch) ~= "table" then
		return
	end
	for key, value in pairs(patch) do
		state[key] = value
		if key == "boosts" then
			boostsReceivedAt = os.clock()
		end
	end
	for key, value in pairs(patch) do
		StateController.Changed:Fire(key, value)
		local list = listeners[key]
		if list then
			for _, fn in ipairs(list) do
				task.spawn(fn, value)
			end
		end
	end
end

function StateController.Init()
	remotes = ReplicatedStorage:WaitForChild(RemoteDefinitions.FolderName)
	StateController.remote("State").OnClientEvent:Connect(applyPatch)
	StateController.remote("Notify").OnClientEvent:Connect(function(data)
		if type(data) == "table" then
			StateController.Notified:Fire(data)
		end
	end)
end

function StateController.Start()
	-- Pide el estado completo cuando todos los controladores están suscritos.
	StateController.send("ClientReady")
end

return StateController
