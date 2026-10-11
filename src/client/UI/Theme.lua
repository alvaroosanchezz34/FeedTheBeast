-- Identidad visual de la interfaz y piezas reutilizables. Todo se construye por código con
-- instancias nativas (sin imágenes externas): paneles oscuros redondeados con borde grueso,
-- botones "gordos" con labio inferior que se hunden al pulsar, y color por rareza.
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RarityConfig = require(Shared.Config.RarityConfig)

local Theme = {}

local rgb = Color3.fromRGB

Theme.Colors = {
	Ink = rgb(23, 26, 43), -- contornos y sombras
	Panel = rgb(33, 38, 64),
	PanelDark = rgb(25, 29, 50),
	PanelLight = rgb(48, 55, 92),
	Line = rgb(70, 79, 128),
	Text = rgb(255, 255, 255),
	TextDim = rgb(176, 184, 224),
	Gold = rgb(255, 201, 60),
	Green = rgb(110, 214, 86),
	Orange = rgb(255, 138, 40),
	Red = rgb(240, 82, 82),
	Blue = rgb(74, 160, 255),
	Pink = rgb(255, 92, 160),
	Purple = rgb(164, 108, 255),
	Grey = rgb(120, 128, 160),
}

Theme.Fonts = {
	Display = Enum.Font.FredokaOne,
	Body = Enum.Font.GothamBold,
	Regular = Enum.Font.GothamMedium,
}

-- Tamaño mínimo cómodo para el dedo (en píxeles virtuales; ver UIController para la escala).
Theme.TouchSize = 64

Theme.onClick = nil -- UIController asigna aquí el sonido de clic

function Theme.darken(color, amount)
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

function Theme.lighten(color, amount)
	return color:Lerp(Color3.new(1, 1, 1), amount)
end

function Theme.rarityColor(rarityId)
	local rarity = RarityConfig.Rarities[rarityId]
	return rarity and rarity.color or Theme.Colors.TextDim
end

-- Constructor genérico: Theme.new("Frame", { Size = ... }, parent)
function Theme.new(className, props, parent)
	local instance = Instance.new(className)
	if props then
		for key, value in pairs(props) do
			instance[key] = value
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function Theme.corner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 12)
	corner.Parent = parent
	return corner
end

function Theme.stroke(parent, color, thickness, transparency)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Theme.Colors.Ink
	stroke.Thickness = thickness or 3
	stroke.Transparency = transparency or 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

function Theme.padding(parent, left, top, right, bottom)
	local padding = Instance.new("UIPadding")
	top = top or left
	right = right or left
	bottom = bottom or top
	padding.PaddingLeft = UDim.new(0, left)
	padding.PaddingTop = UDim.new(0, top)
	padding.PaddingRight = UDim.new(0, right)
	padding.PaddingBottom = UDim.new(0, bottom)
	padding.Parent = parent
	return padding
end

-- direction: "V" | "H"
function Theme.list(parent, direction, gap, hAlign, vAlign)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction == "H" and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, gap or 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = vAlign or Enum.VerticalAlignment.Top
	layout.Parent = parent
	return layout
end

function Theme.grid(parent, cellSize, gap)
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = cellSize
	layout.CellPadding = UDim2.fromOffset(gap or 10, gap or 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = parent
	return layout
end

-- Texto. props: text, size, position, anchor, color, font, textSize, scaled, alignX, alignY,
-- wrapped, rich, stroke (true = contorno oscuro), order, name, zindex
function Theme.label(props, parent)
	local label = Instance.new("TextLabel")
	label.Name = props.name or "Label"
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Size = props.size or UDim2.fromScale(1, 1)
	label.Position = props.position or UDim2.new()
	label.AnchorPoint = props.anchor or Vector2.new(0, 0)
	label.Font = props.font or Theme.Fonts.Body
	label.Text = props.text or ""
	label.TextColor3 = props.color or Theme.Colors.Text
	label.TextSize = props.textSize or 18
	label.TextScaled = props.scaled == true
	label.TextWrapped = props.wrapped == true or props.scaled == true
	label.RichText = props.rich == true
	label.TextXAlignment = props.alignX or Enum.TextXAlignment.Center
	label.TextYAlignment = props.alignY or Enum.TextYAlignment.Center
	label.LayoutOrder = props.order or 0
	label.ZIndex = props.zindex or 1
	if props.truncate then
		label.TextTruncate = Enum.TextTruncate.AtEnd
	end
	if props.stroke then
		label.TextStrokeColor3 = Theme.Colors.Ink
		label.TextStrokeTransparency = 0.25
	end
	if props.scaled and props.maxTextSize then
		local constraint = Instance.new("UITextSizeConstraint")
		constraint.MaxTextSize = props.maxTextSize
		constraint.MinTextSize = props.minTextSize or 8
		constraint.Parent = label
	end
	if parent then
		label.Parent = parent
	end
	return label
end

-- Panel redondeado. props: size, position, anchor, color, radius, stroke (false para quitarlo),
-- strokeColor, transparency, name, order, clips
function Theme.panel(props, parent)
	local frame = Instance.new("Frame")
	frame.Name = props.name or "Panel"
	frame.Size = props.size or UDim2.fromScale(1, 1)
	frame.Position = props.position or UDim2.new()
	frame.AnchorPoint = props.anchor or Vector2.new(0, 0)
	frame.BackgroundColor3 = props.color or Theme.Colors.Panel
	frame.BackgroundTransparency = props.transparency or 0
	frame.BorderSizePixel = 0
	frame.LayoutOrder = props.order or 0
	frame.ClipsDescendants = props.clips == true
	frame.ZIndex = props.zindex or 1
	Theme.corner(frame, props.radius or 14)
	if props.stroke ~= false then
		Theme.stroke(frame, props.strokeColor or Theme.Colors.Ink, props.strokeThickness or 3)
	end
	if parent then
		frame.Parent = parent
	end
	return frame
end

-- Contenedor invisible.
function Theme.box(props, parent)
	local frame = Instance.new("Frame")
	frame.Name = props.name or "Box"
	frame.Size = props.size or UDim2.fromScale(1, 1)
	frame.Position = props.position or UDim2.new()
	frame.AnchorPoint = props.anchor or Vector2.new(0, 0)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.LayoutOrder = props.order or 0
	frame.ZIndex = props.zindex or 1
	if props.automatic then
		frame.AutomaticSize = props.automatic
	end
	if parent then
		frame.Parent = parent
	end
	return frame
end

function Theme.scroll(props, parent)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = props.name or "Scroll"
	scroll.Size = props.size or UDim2.fromScale(1, 1)
	scroll.Position = props.position or UDim2.new()
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 8
	scroll.ScrollBarImageColor3 = Theme.Colors.Line
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Active = true
	if parent then
		scroll.Parent = parent
	end
	return scroll
end

function Theme.tween(instance, duration, goal, style, direction)
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		goal
	)
	tween:Play()
	return tween
end

-- Botón con labio inferior. props: text, icon, size, position, anchor, color, textColor,
-- textSize, onClick, name, order, font, radius, zindex
-- Devuelve un objeto: { instance, face, label, setText, setEnabled, setColor, enabled }
local LIP = 5

function Theme.button(props, parent)
	local color = props.color or Theme.Colors.Blue
	local button = Instance.new("TextButton")
	button.Name = props.name or "Button"
	button.Size = props.size or UDim2.fromOffset(160, Theme.TouchSize)
	button.Position = props.position or UDim2.new()
	button.AnchorPoint = props.anchor or Vector2.new(0, 0)
	button.BackgroundColor3 = Theme.darken(color, 0.45)
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = ""
	button.LayoutOrder = props.order or 0
	button.ZIndex = props.zindex or 1
	button.Selectable = true
	Theme.corner(button, props.radius or 12)
	Theme.stroke(button, Theme.Colors.Ink, 3)

	local face = Instance.new("Frame")
	face.Name = "Face"
	face.Size = UDim2.new(1, 0, 1, -LIP)
	face.BackgroundColor3 = color
	face.BorderSizePixel = 0
	face.ZIndex = button.ZIndex
	Theme.corner(face, props.radius or 12)
	face.Parent = button

	local text = props.text or ""
	if props.icon then
		text = props.icon .. (text ~= "" and ("  " .. text) or "")
	end
	local label = Theme.label({
		name = "Text",
		text = text,
		font = props.font or Theme.Fonts.Display,
		textSize = props.textSize or 22,
		color = props.textColor or Theme.Colors.Text,
		stroke = props.textColor == nil,
		scaled = props.scaled,
		maxTextSize = props.textSize or 22,
		zindex = button.ZIndex,
	}, face)
	if props.scaled then
		Theme.padding(label, 6, 4)
	end

	local object = { instance = button, face = face, label = label, enabled = true, color = color }

	local function press(down)
		face.Position = UDim2.fromOffset(0, down and LIP - 1 or 0)
	end

	button.MouseButton1Down:Connect(function()
		if object.enabled then
			press(true)
		end
	end)
	button.MouseButton1Up:Connect(function()
		press(false)
	end)
	button.MouseLeave:Connect(function()
		press(false)
	end)
	button.Activated:Connect(function()
		press(false)
		if not object.enabled then
			return
		end
		if Theme.onClick then
			Theme.onClick()
		end
		if props.onClick then
			props.onClick(object)
		end
	end)

	function object.setText(newText)
		label.Text = newText
	end

	function object.setColor(newColor)
		object.color = newColor
		if object.enabled then
			face.BackgroundColor3 = newColor
			button.BackgroundColor3 = Theme.darken(newColor, 0.45)
		end
	end

	function object.setEnabled(enabled)
		enabled = enabled == true
		if object.enabled == enabled then
			return
		end
		object.enabled = enabled
		button.Active = enabled
		if enabled then
			face.BackgroundColor3 = object.color
			button.BackgroundColor3 = Theme.darken(object.color, 0.45)
			label.TextTransparency = 0
		else
			face.BackgroundColor3 = Theme.Colors.Grey
			button.BackgroundColor3 = Theme.darken(Theme.Colors.Grey, 0.45)
			label.TextTransparency = 0.35
		end
	end

	if parent then
		button.Parent = parent
	end
	return object
end

-- Barra de progreso. Devuelve { instance, set(alpha, color?) }
function Theme.progress(props, parent)
	local back = Theme.panel({
		name = props.name or "Progress",
		size = props.size or UDim2.new(1, 0, 0, 14),
		position = props.position,
		anchor = props.anchor,
		color = Theme.Colors.PanelDark,
		radius = props.radius or 7,
		strokeThickness = 2,
		order = props.order,
		clips = true,
	}, parent)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = props.color or Theme.Colors.Green
	fill.Size = UDim2.fromScale(0, 1)
	Theme.corner(fill, props.radius or 7)
	fill.Parent = back
	local object = { instance = back, fill = fill }
	function object.set(alpha, color)
		fill.Size = UDim2.fromScale(math.clamp(alpha, 0, 1), 1)
		if color then
			fill.BackgroundColor3 = color
		end
	end
	return object
end

-- Etiqueta-píldora de color (rareza, mutación, "NEW"...).
function Theme.chip(props, parent)
	local frame = Theme.panel({
		name = props.name or "Chip",
		size = props.size or UDim2.fromOffset(90, 24),
		position = props.position,
		anchor = props.anchor,
		color = props.color or Theme.Colors.PanelLight,
		radius = 8,
		strokeThickness = 2,
		order = props.order,
		zindex = props.zindex,
	}, parent)
	local label = Theme.label({
		text = props.text or "",
		font = Theme.Fonts.Display,
		textSize = props.textSize or 14,
		color = props.textColor or Theme.Colors.Text,
		stroke = props.textColor == nil,
		zindex = props.zindex,
	}, frame)
	return frame, label
end

return Theme
