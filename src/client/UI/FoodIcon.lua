-- Icono 3D de un alimento para la interfaz (ViewportFrame con el mismo modelo que el mundo).
--
-- FoodIcon.new({ food, size, position, anchor, order, zindex }, parent) -> ViewportFrame | nil
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FoodModels = require(Shared.Food.FoodModels)

local FoodIcon = {}

function FoodIcon.new(props, parent)
	local visual = FoodModels.build(props.food)
	if not visual then
		return nil
	end
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "FoodIcon"
	viewport.Size = props.size or UDim2.fromScale(1, 1)
	viewport.Position = props.position or UDim2.new()
	viewport.AnchorPoint = props.anchor or Vector2.new(0, 0)
	viewport.BackgroundTransparency = 1
	viewport.BorderSizePixel = 0
	viewport.LayoutOrder = props.order or 0
	viewport.ZIndex = props.zindex or 1
	viewport.Ambient = Color3.fromRGB(180, 180, 190)
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	viewport.LightDirection = Vector3.new(0.4, -1, 0.6)

	local center = Vector3.new(0, visual.height * 0.5, 0)
	local reach = math.max(visual.height, visual.radius * 2.1)
	local fov = 30
	local distance = (reach * 0.5) / math.tan(math.rad(fov * 0.5)) * 1.2
	local direction = Vector3.new(-0.5, 0.45, -1).Unit
	local camera = Instance.new("Camera")
	camera.FieldOfView = fov
	camera.CFrame = CFrame.lookAt(center + direction * distance, center)
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	visual.model.Parent = viewport
	if parent then
		viewport.Parent = parent
	end
	return viewport
end

return FoodIcon
