-- Primitivas de construcción del mundo (todas ancladas). Formas disponibles sin assets externos:
-- bloque, cuña, cilindro, disco y elipsoide (SpecialMesh esférico sobre una pieza).
local Build = {}

local function base(props, className)
	local p = Instance.new(className or "Part")
	p.Name = props.name or "Part"
	p.Anchored = true
	p.Size = props.size
	p.CFrame = props.cf
	p.Color = props.color or Color3.fromRGB(200, 200, 200)
	p.Material = props.material or Enum.Material.SmoothPlastic
	p.Transparency = props.transparency or 0
	p.Reflectance = props.reflectance or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props.shape then
		p.Shape = props.shape
	end
	-- La decoración no colisiona ni participa en consultas salvo que se pida.
	p.CanCollide = props.collide == true
	p.CanTouch = false
	p.CanQuery = props.collide == true
	p.CastShadow = props.shadow ~= false
	return p
end

function Build.block(props)
	local p = base(props)
	p.Parent = props.parent
	return p
end

function Build.wedge(props)
	local p = base(props, "WedgePart")
	p.Parent = props.parent
	return p
end

-- Elipsoide de tamaño `size`.
function Build.blob(props)
	local p = base(props)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	p.Parent = props.parent
	return p
end

-- Cilindro vertical: `diameter`, `height`, centro en `position` (o `cf` con el eje en Y).
function Build.cyl(props)
	local cf = props.cf or CFrame.new(props.position)
	props.size = Vector3.new(props.height, props.diameter, props.diameter)
	props.cf = cf * CFrame.Angles(0, 0, math.rad(90))
	props.shape = Enum.PartType.Cylinder
	local p = base(props)
	p.Parent = props.parent
	return p
end

-- Disco horizontal con la cara superior en `top`.
function Build.disc(props)
	return Build.cyl({
		name = props.name,
		diameter = props.diameter,
		height = props.height or 0.2,
		position = Vector3.new(props.x, props.top - (props.height or 0.2) / 2, props.z),
		color = props.color,
		material = props.material,
		transparency = props.transparency,
		collide = props.collide,
		shadow = props.shadow,
		parent = props.parent,
	})
end

function Build.folder(name, parent)
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

return Build
