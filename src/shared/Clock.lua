-- Fuente de tiempo única. Los tests sustituyen estas funciones para controlar el reloj.
local Clock = {}

-- Reloj monotónico (segundos) para cooldowns y temporizadores internos.
function Clock.now()
	return os.clock()
end

-- Timestamp unix del servidor para datos persistentes.
function Clock.unix()
	return os.time()
end

-- Tiempo de servidor sincronizado con los clientes (para temporizadores replicados).
function Clock.server()
	return workspace:GetServerTimeNow()
end

function Clock.sleep(seconds)
	task.wait(seconds)
end

return Clock
