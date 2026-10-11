-- Ganancias offline (puro). Se calculan a partir de los datos guardados y el tiempo transcurrido.
local EconomyConfig = require(script.Parent.Parent.Config.EconomyConfig)

local OfflineEarnings = {}

-- lastSave y now son timestamps unix del SERVIDOR. Devuelve (monedas, segundosContados).
function OfflineEarnings.compute(lastSave, now, incomePerSecond)
	local cfg = EconomyConfig.Offline
	if type(lastSave) ~= "number" or type(now) ~= "number" or type(incomePerSecond) ~= "number" then
		return 0, 0
	end
	if lastSave ~= lastSave or now ~= now or incomePerSecond ~= incomePerSecond then
		return 0, 0
	end
	if lastSave <= 0 or incomePerSecond <= 0 then
		return 0, 0
	end
	local elapsed = now - lastSave
	-- Reloj hacia atrás o sesión demasiado corta: nada.
	if elapsed < cfg.MinSeconds then
		return 0, 0
	end
	elapsed = math.min(elapsed, cfg.MaxSeconds)
	local amount = math.floor(incomePerSecond * elapsed * cfg.Rate)
	if amount ~= amount or amount == math.huge then
		return 0, 0
	end
	return math.clamp(amount, 0, EconomyConfig.MaxCoins), elapsed
end

return OfflineEarnings
