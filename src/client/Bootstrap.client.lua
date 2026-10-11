-- Punto de entrada del cliente. Carga los controladores en orden, los inicializa y ejecuta un
-- único bucle de actualización. Todo lo que hace el cliente es presentación e intención: el
-- estado real (monedas, criaturas, mutaciones, recompensas) vive en el servidor.
local RunService = game:GetService("RunService")

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local ControllersFolder = script.Parent:WaitForChild("Controllers")

-- El orden importa en Init/Start: StateController crea el acceso a remotos y se inicia el ÚLTIMO
-- (pide el estado completo cuando todos los demás ya están suscritos).
local ORDER = {
	"StateController",
	"SettingsController",
	"EffectCleanup",
	"AudioController",
	"EffectsController",
	"AuraController",
	"CreatureController",
	"CameraController",
	"WorldController",
	"InputController",
	"UIController",
}

local controllers = {}
for _, name in ipairs(ORDER) do
	controllers[name] = require(ControllersFolder:WaitForChild(name))
end

for _, name in ipairs(ORDER) do
	local controller = controllers[name]
	if controller.Init then
		controller.Init(controllers)
	end
end

for index = #ORDER, 1, -1 do
	-- Orden inverso: la interfaz y el mundo se suscriben antes de que llegue el primer estado.
	local controller = controllers[ORDER[index]]
	if controller.Start then
		local ok, err = xpcall(controller.Start, debug.traceback)
		if not ok then
			warn("[Client] " .. ORDER[index] .. ".Start failed: " .. tostring(err))
		end
	end
end

local updaters = {}
for _, name in ipairs(ORDER) do
	local controller = controllers[name]
	if controller.Update then
		table.insert(updaters, { name = name, fn = controller.Update })
	end
end

RunService.RenderStepped:Connect(function(dt)
	-- Un frame muy largo (pérdida de foco, carga) no debe disparar animaciones ni temporizadores.
	dt = math.min(dt, 0.1)
	for _, updater in ipairs(updaters) do
		local ok, err = xpcall(updater.fn, debug.traceback, dt)
		if not ok then
			warn("[Client] " .. updater.name .. ".Update failed: " .. tostring(err))
		end
	end
end)
