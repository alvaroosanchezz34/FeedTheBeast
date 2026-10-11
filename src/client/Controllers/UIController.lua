-- Interfaz del jugador. Monta el ScreenGui, la escala adaptable (móvil / tablet / PC) y los
-- módulos de UI: HUD, avisos, ventanas y tutorial. La interfaz solo muestra el estado que envía
-- el servidor y envía intenciones; nunca concede nada por sí misma.
--
-- API:
--   UIController.open(name, tab?)    "shop" | "beasts" | "upgrades" | "rebirth" | "settings"
--   UIController.close()
--   UIController.toggle(name)
--   UIController.toast(text, kind?, icon?)
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local StarterGui = game:GetService("StarterGui")

local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local Hud = require(UI:WaitForChild("Hud"))
local Toasts = require(UI:WaitForChild("Toasts"))
local Windows = require(UI:WaitForChild("Windows"))
local ShopWindow = require(UI:WaitForChild("ShopWindow"))
local BeastsWindow = require(UI:WaitForChild("BeastsWindow"))
local MiscWindows = require(UI:WaitForChild("MiscWindows"))
local TasksWindow = require(UI:WaitForChild("TasksWindow"))
local Tutorial = require(UI:WaitForChild("Tutorial"))

local UIController = {}

-- Lienzo virtual de diseño. La escala se elige para que quepa en cualquier pantalla y para que
-- en móvil los botones no bajen de un tamaño cómodo para el dedo.
local DESIGN_WIDTH = 1180
local DESIGN_HEIGHT = 680
local MIN_SCALE = 0.5
local MAX_SCALE = 1.3
local MIN_TOUCH_SCALE = 0.68

local KIOSK_WINDOWS = {
	Shop = { "shop" },
	Collection = { "beasts", "collection" },
	Upgrades = { "upgrades" },
	Rebirth = { "rebirth" },
}

local controllers
local gui
local layers = {}
local scales = {}
local hud, toasts, windows, tutorial
local clock = 0
local currentScale = 1
local guides: { [string]: any } = {}

-- Escala para un tamaño de pantalla dado (pura: la usan los tests con distintos dispositivos).
function UIController.scaleFor(size, touchOnly)
	if size.X <= 0 or size.Y <= 0 then
		return 1
	end
	local scale = math.clamp(math.min(size.X / DESIGN_WIDTH, size.Y / DESIGN_HEIGHT), MIN_SCALE, MAX_SCALE)
	if touchOnly then
		scale = math.max(scale, MIN_TOUCH_SCALE)
	end
	return scale
end

local function viewportSize()
	local camera = workspace.CurrentCamera
	if camera then
		-- pcall: la cámara puede estar a medio crear durante la carga.
		local ok, size = pcall(function()
			return camera.ViewportSize
		end)
		if ok and typeof(size) == "Vector2" then
			return size
		end
	end
	return Vector2.new(DESIGN_WIDTH, DESIGN_HEIGHT)
end

local function computeScale()
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	return UIController.scaleFor(viewportSize(), touchOnly)
end

local function applyScale()
	currentScale = computeScale()
	for name, layer in pairs(layers) do
		-- La capa mide pantalla/escala y se escala de vuelta: su contenido trabaja en píxeles
		-- virtuales y siempre cubre la pantalla entera.
		layer.Size = UDim2.fromScale(1 / currentScale, 1 / currentScale)
		scales[name].Scale = currentScale
	end
end

local function makeLayer(name, order)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.ZIndex = order
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	frame.Parent = gui
	layers[name] = frame
	scales[name] = scale
	return frame
end

local function applyGuide()
	local World = controllers.WorldController
	-- Llevar una caja tiene prioridad sobre el tutorial.
	local active = guides.carry or guides.tutorial
	if active then
		World.guideTo(active.position, active.color)
	else
		World.guideTo(nil)
	end
end

function UIController.open(name, tab)
	return windows ~= nil and windows.open(name, tab)
end

function UIController.close()
	if windows then
		windows.close()
	end
end

function UIController.toggle(name)
	if windows then
		windows.toggle(name)
	end
end

function UIController.toast(text, kind, icon)
	if toasts then
		toasts.toast(text, kind, icon)
	end
end

function UIController.scale()
	return currentScale
end

-- Acceso para pruebas y depuración.
function UIController.parts()
	return { gui = gui, hud = hud, toasts = toasts, windows = windows, tutorial = tutorial, layers = layers }
end

function UIController.Init(allControllers)
	controllers = allControllers
end

function UIController.Start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	gui = Instance.new("ScreenGui")
	gui.Name = "FTB_UI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 5

	makeLayer("hud", 1)
	makeLayer("windows", 2)
	makeLayer("overlay", 3)
	applyScale()

	local Audio = controllers.AudioController
	Theme.onClick = function()
		Audio.play("Click")
	end

	local ctx = {
		State = controllers.StateController,
		Settings = controllers.SettingsController,
		World = controllers.WorldController,
		Input = controllers.InputController,
		Creatures = controllers.CreatureController,
		Audio = Audio,
		layers = layers,
		clock = function()
			return clock
		end,
		toggle = UIController.toggle,
		open = UIController.open,
		close = UIController.close,
		toast = UIController.toast,
		setGuide = function(owner, position, color)
			guides[owner] = position and { position = position, color = color } or nil
			applyGuide()
		end,
		-- Con una ventana abierta los prompts del mundo se apagan para no alimentar sin querer.
		onWindowChanged = function(name)
			ProximityPromptService.Enabled = name == nil
		end,
	}

	toasts = Toasts.create(ctx)
	hud = Hud.create(ctx)
	windows = Windows.create(ctx)
	ShopWindow.register(windows, ctx)
	BeastsWindow.register(windows, ctx)
	MiscWindows.register(windows, ctx)
	TasksWindow.register(windows, ctx)
	tutorial = Tutorial.create(ctx, hud)

	controllers.WorldController.KioskOpened:Connect(function(kioskId)
		local target = KIOSK_WINDOWS[kioskId]
		if target then
			UIController.open(target[1], target[2])
		end
	end)

	-- El juego no usa la mochila ni la barra de vida de Roblox.
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	end)

	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyScale)
	end

	gui.Parent = playerGui
end

function UIController.Update(dt)
	clock += dt
	if not hud then
		return
	end
	hud.update(dt)
	toasts.update(dt)
	windows.update()
	tutorial.update(dt)
end

return UIController
