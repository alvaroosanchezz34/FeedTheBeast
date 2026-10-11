-- Traduce la interacción del jugador en INTENCIONES que se envían al servidor (alimentar,
-- alimentar a la bestia gigante, soltar caja). No decide resultados: el servidor valida todo.
--
-- API:
--   InputController.feed(entry) -> bool                  (entry de CreatureController)
--   InputController.pickFood(speciesId) -> foodId | nil  (comida que se usaría ahora mismo)
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FoodConfig = require(Shared.Config.FoodConfig)

local InputController = {}

local controllers
local StateController
local CreatureController

local HOLD_MARGIN = 0.08 -- margen sobre el tiempo de consumo al mantener pulsado el prompt
local held = nil -- { entry, nextAt }
local clock = 0
local lastEmptyNotice = -math.huge

-- Comida que se usará: la seleccionada en la barra si queda; si no, automática.
-- Automática = primero la favorita de la especie y, si no hay, la de menor crecimiento
-- (así la comida rara se reserva para cuando el jugador la elige a propósito).
function InputController.pickFood(speciesId)
	local selected = StateController.selectedFood()
	if selected then
		return selected
	end
	local inventory = StateController.get("inventory") or {}
	local best, bestScore = nil, math.huge
	for _, foodId in ipairs(FoodConfig.Order) do
		if (inventory[foodId] or 0) > 0 then
			local def = FoodConfig.Foods[foodId]
			local score = def.growth
			if speciesId and table.find(def.favoriteOf, speciesId) then
				score -= 1e6
			end
			if score < bestScore then
				best, bestScore = foodId, score
			end
		end
	end
	return best
end

local function notifyLocal(text, icon)
	StateController.Notified:Fire({ text = text, kind = "error", icon = icon })
end

-- Envía la intención de alimentar. Devuelve (enviado, foodId).
function InputController.feed(entry)
	if not entry or not entry.model or not entry.model.Parent then
		return false
	end
	local foodId = InputController.pickFood(entry.speciesId)
	if not foodId then
		if clock - lastEmptyNotice > 3 then
			lastEmptyNotice = clock
			notifyLocal("No food! Grab some in the plaza or buy it in the shop.", "🍽️")
		end
		return false
	end
	if entry.isGiant then
		StateController.send("GiantFeed", foodId)
	else
		StateController.send("Feed", entry.creatureId, foodId)
	end
	return true, foodId
end

-- Tiempo hasta el siguiente intento mientras se mantiene pulsado: lo que tarda en comerse esa
-- comida (el servidor rechazaría antes por "ocupada") más un pequeño margen.
local function repeatDelay(entry, foodId)
	if entry.isGiant then
		return 0.45
	end
	local def = foodId and FoodConfig.Foods[foodId]
	return (def and def.consumeTime or 0.8) + HOLD_MARGIN
end

function InputController.dropCrate()
	StateController.send("DropCrate")
end

function InputController.Init(allControllers)
	controllers = allControllers
	StateController = controllers.StateController
	CreatureController = controllers.CreatureController
end

function InputController.Start()
	CreatureController.FeedRequested:Connect(function(entry)
		local sent, foodId = InputController.feed(entry)
		if sent then
			-- Mantener pulsado sigue alimentando (el servidor marca el ritmo real).
			held = { entry = entry, nextAt = clock + repeatDelay(entry, foodId) }
		end
	end)
	CreatureController.FeedReleased:Connect(function(entry)
		if held and held.entry == entry then
			held = nil
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.G then
			InputController.dropCrate()
		end
	end)
end

function InputController.Update(dt)
	clock += dt
	if not held then
		return
	end
	local entry = held.entry
	if not entry.model or not entry.model.Parent then
		held = nil
		return
	end
	if clock >= held.nextAt then
		local sent, foodId = InputController.feed(entry)
		if sent then
			held.nextAt = clock + repeatDelay(entry, foodId)
		else
			held = nil
		end
	end
end

return InputController
