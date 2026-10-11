-- Retrato 3D de una criatura dentro de la interfaz (ViewportFrame). Usa el mismo constructor y
-- las mismas mutaciones que el mundo, así que no hace falta ninguna imagen: el icono es la criatura.
--
-- CreatureIcon.new({ species, mutation, silhouette, size, position, anchor, order }, parent)
--   -> ViewportFrame | nil
-- Destruir el ViewportFrame libera el modelo.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CreatureBuilder = require(Shared.Creatures.CreatureBuilder)
local MutationVisuals = require(Shared.Creatures.MutationVisuals)

local CreatureIcon = {}

local BLACK = Color3.fromRGB(10, 12, 22)

function CreatureIcon.new(props, parent)
	local visual = CreatureBuilder.build(props.species)
	if not visual then
		return nil
	end
	if props.silhouette then
		-- Sin descubrir: solo la silueta.
		for _, record in ipairs(visual.records) do
			record.part.Color = BLACK
			record.part.Material = Enum.Material.SmoothPlastic
			record.part.Reflectance = 0
			if record.part.Transparency < 1 then
				record.part.Transparency = 0
			end
		end
	else
		MutationVisuals.apply(visual, props.mutation or "NORMAL")
	end

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "CreatureIcon"
	viewport.Size = props.size or UDim2.fromScale(1, 1)
	viewport.Position = props.position or UDim2.new()
	viewport.AnchorPoint = props.anchor or Vector2.new(0, 0)
	viewport.BackgroundTransparency = 1
	viewport.BorderSizePixel = 0
	viewport.LayoutOrder = props.order or 0
	viewport.Ambient = props.silhouette and BLACK or Color3.fromRGB(170, 170, 185)
	viewport.LightColor = props.silhouette and BLACK or Color3.fromRGB(255, 255, 255)
	viewport.LightDirection = Vector3.new(0.4, -1, 0.6)

	-- Encuadre: de frente (el frente de la criatura es -Z), ligeramente desde arriba y de lado.
	local center = Vector3.new(0, visual.height * 0.5, 0)
	local reach = math.max(visual.height, visual.radius * 2.2)
	local fov = 30
	local distance = (reach * 0.5) / math.tan(math.rad(fov * 0.5)) * 1.18
	local direction = Vector3.new(-0.42, 0.22, -1).Unit
	local camera = Instance.new("Camera")
	camera.FieldOfView = fov
	camera.CFrame = CFrame.lookAt(center + direction * distance, center)
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	-- En un ViewportFrame no hay física: las piezas se quedan donde el Kit las construyó.
	visual.model.Parent = viewport
	if parent then
		viewport.Parent = parent
	end
	return viewport
end

return CreatureIcon
