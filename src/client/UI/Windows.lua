-- Gestor de ventanas: una sola ventana abierta a la vez, con título, pestañas y cierre.
-- Cada ventana se registra con una función `render(content, tabId, window)` que construye su
-- contenido y puede devolver `{ update = fn, destroy = fn }`:
--   * update(): refresco en el sitio cuando cambia el estado que la ventana vigila (`watch`).
--   * sin update: el contenido se reconstruye conservando la posición de scroll.
local Theme = require(script.Parent.Theme)

local Windows = {}

local C = Theme.Colors

function Windows.create(ctx)
	local manager: { [string]: any } = {}
	local definitions = {}
	local current = nil -- { name, def, tab, handle, content }
	local dirty = false

	local layer = ctx.layers.windows

	-- Fondo oscurecido: tocar fuera cierra la ventana.
	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.45
	dim.BorderSizePixel = 0
	dim.AutoButtonColor = false
	dim.Text = ""
	dim.Visible = false
	dim.Parent = layer

	local frame = Theme.panel({
		name = "Window",
		size = UDim2.fromScale(0.94, 0.9),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		strokeThickness = 4,
	}, layer)
	frame.Visible = false
	frame.Active = true -- absorbe los toques para que no lleguen al fondo
	-- Nunca más grande que la pantalla (móviles en horizontal, tablets pequeñas).
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(780, 540)
	constraint.Parent = frame
	local popScale = Instance.new("UIScale")
	popScale.Parent = frame

	local header = Theme.panel({ name = "Header", size = UDim2.new(1, 0, 0, 58), color = C.PanelLight, stroke = false }, frame)
	local title = Theme.label({
		name = "Title",
		text = "",
		font = Theme.Fonts.Display,
		textSize = 28,
		stroke = true,
		size = UDim2.new(1, -90, 1, 0),
		position = UDim2.fromOffset(20, 0),
		alignX = Enum.TextXAlignment.Left,
	}, header)
	Theme.button({
		name = "Close",
		text = "X",
		color = C.Red,
		size = UDim2.fromOffset(52, 46),
		position = UDim2.new(1, -8, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		onClick = function()
			manager.close()
		end,
	}, header)

	local tabBar = Theme.box({ name = "Tabs", size = UDim2.new(1, -24, 0, 48), position = UDim2.fromOffset(12, 66) }, frame)
	Theme.list(tabBar, "H", 8)

	local content = Theme.box({ name = "Content", size = UDim2.new(1, -24, 1, -78), position = UDim2.fromOffset(12, 66) }, frame)

	local tabButtons = {}

	local function destroyHandle()
		if current and current.handle and current.handle.destroy then
			pcall(current.handle.destroy)
		end
		for _, child in ipairs(content:GetChildren()) do
			child:Destroy()
		end
	end

	local function scrollPosition()
		local scroll = content:FindFirstChildWhichIsA("ScrollingFrame", true)
		return scroll and scroll.CanvasPosition or nil
	end

	local function render(keepScroll)
		if not current then
			return
		end
		local saved = keepScroll and scrollPosition() or nil
		destroyHandle()
		local ok, handle = xpcall(current.def.render, debug.traceback, content, current.tab, manager)
		if not ok then
			warn("[UI] window " .. current.name .. " failed to render: " .. tostring(handle))
			handle = nil
		end
		current.handle = type(handle) == "table" and handle or nil
		if saved then
			local scroll = content:FindFirstChildWhichIsA("ScrollingFrame", true)
			if scroll then
				scroll.CanvasPosition = saved
			end
		end
	end

	local function buildTabs()
		for _, object in ipairs(tabButtons) do
			object.instance:Destroy()
		end
		tabButtons = {}
		local tabs = current.def.tabs
		local hasTabs = tabs ~= nil and #tabs > 1
		tabBar.Visible = hasTabs
		content.Position = UDim2.fromOffset(12, hasTabs and 122 or 66)
		content.Size = UDim2.new(1, -24, 1, hasTabs and -134 or -78)
		if not hasTabs then
			return
		end
		for index, tab in ipairs(tabs) do
			local selected = tab.id == current.tab
			local object = Theme.button({
				name = "Tab_" .. tab.id,
				text = tab.label,
				color = selected and current.def.color or C.PanelLight,
				size = UDim2.fromOffset(170, 46),
				textSize = 18,
				order = index,
				onClick = function()
					if current and current.tab ~= tab.id then
						manager.open(current.name, tab.id)
					end
				end,
			}, tabBar)
			table.insert(tabButtons, object)
		end
	end

	-- def = { title, icon, color, tabs = { { id, label } }, watch = { claves de estado }, render }
	function manager.register(name, def)
		definitions[name] = def
	end

	function manager.open(name, tabId)
		local def = definitions[name]
		if not def then
			return false
		end
		local wasOpen = current ~= nil
		destroyHandle()
		local tab = tabId or (def.tabs and def.tabs[1].id) or nil
		current = { name = name, def = def, tab = tab }
		title.Text = (def.icon and (def.icon .. "  ") or "") .. def.title
		header.BackgroundColor3 = Theme.darken(def.color or C.PanelLight, 0.35)
		buildTabs()
		dim.Visible = true
		frame.Visible = true
		render(false)
		if not wasOpen then
			popScale.Scale = 0.9
			Theme.tween(popScale, 0.16, { Scale = 1 }, Enum.EasingStyle.Back)
		end
		if ctx.onWindowChanged then
			ctx.onWindowChanged(name)
		end
		return true
	end

	function manager.close()
		if not current then
			return
		end
		destroyHandle()
		current = nil
		dim.Visible = false
		frame.Visible = false
		if ctx.onWindowChanged then
			ctx.onWindowChanged(nil)
		end
	end

	function manager.toggle(name)
		if current and current.name == name then
			manager.close()
		else
			manager.open(name)
		end
	end

	function manager.current()
		return current and current.name or nil, current and current.tab or nil
	end

	function manager.isOpen()
		return current ~= nil
	end

	-- Fuerza un refresco del contenido en el siguiente frame.
	function manager.invalidate()
		dirty = true
	end

	dim.Activated:Connect(function()
		manager.close()
	end)

	-- Cambios de estado: se agrupan y se aplican una vez por frame.
	ctx.State.Changed:Connect(function(key)
		if current and current.def.watch and table.find(current.def.watch, key) then
			dirty = true
		end
	end)

	function manager.update()
		-- `tick` opcional: lógica por frame de la ventana abierta (p. ej. botones con retardo).
		if current and current.handle and current.handle.tick then
			local ok, err = xpcall(current.handle.tick, debug.traceback)
			if not ok then
				warn("[UI] window " .. current.name .. " failed to tick: " .. tostring(err))
			end
		end
		if not dirty then
			return
		end
		dirty = false
		if not current then
			return
		end
		local handle = current.handle
		if handle and handle.update then
			local ok, err = xpcall(handle.update, debug.traceback)
			if not ok then
				warn("[UI] window " .. current.name .. " failed to update: " .. tostring(err))
			end
		else
			render(true)
		end
	end

	return manager
end

return Windows
