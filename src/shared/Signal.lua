-- Señal mínima. Cada handler se ejecuta con task.spawn para aislar errores y yields.
local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ handlers = {} }, Signal)
end

function Signal:Connect(fn)
	local connection = { fn = fn, connected = true }
	table.insert(self.handlers, connection)
	local handlers = self.handlers
	function connection.Disconnect()
		connection.connected = false
		local index = table.find(handlers, connection)
		if index then
			table.remove(handlers, index)
		end
	end
	return connection
end

function Signal:Fire(...)
	for _, connection in ipairs(table.clone(self.handlers)) do
		if connection.connected then
			task.spawn(connection.fn, ...)
		end
	end
end

return Signal
