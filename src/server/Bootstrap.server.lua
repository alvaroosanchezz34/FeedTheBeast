-- Punto de entrada del servidor. Carga los servicios en orden, los inicializa y ejecuta un
-- único bucle de actualización (los servicios no crean sus propios bucles por objeto).
local RunService = game:GetService("RunService")

local ServicesFolder = script.Parent:WaitForChild("Services")

-- El orden importa:
--   * Init: ValidationService crea los remotos; PlotService construye el mundo.
--   * Start: PlotService se suscribe el primero a SessionStarted (asigna parcela antes de que
--     los demás reaccionen) y PlayerDataService arranca el último (empieza a cargar jugadores).
local ORDER = {
	"ValidationService",
	"PlotService",
	"CharacterService",
	"StateService",
	"EconomyService",
	"CreatureService",
	"MutationService",
	"VFXService",
	"FoodService",
	"FeedingService",
	"ShopService",
	"RebirthService",
	"TheftService",
	"EventService",
	"QuestService",
	"MonetizationService",
	"LeaderboardService",
	"AdminService",
	"PlayerDataService",
}

local services = {}
for _, name in ipairs(ORDER) do
	services[name] = require(ServicesFolder:WaitForChild(name))
end

for _, name in ipairs(ORDER) do
	local service = services[name]
	if service.Init then
		service.Init(services)
	end
end

for _, name in ipairs(ORDER) do
	local service = services[name]
	if service.Start then
		service.Start()
	end
end

local updaters = {}
for _, name in ipairs(ORDER) do
	local service = services[name]
	if service.Update then
		table.insert(updaters, { name = name, fn = service.Update })
	end
end

RunService.Heartbeat:Connect(function(dt)
	for _, updater in ipairs(updaters) do
		local ok, err = xpcall(updater.fn, debug.traceback, dt)
		if not ok then
			warn("[Bootstrap] " .. updater.name .. ".Update failed: " .. tostring(err))
		end
	end
end)

print("[FeedTheBeast] server ready")
