-- Kit de construcción modular de criaturas a partir de Parts nativas.
--
-- Cada especie se construye en espacio de modelo (origen = punto de apoyo en el suelo, +Y arriba,
-- frente = -Z). Todas las piezas se unen con `Weld` (C0/C1 explícitos), de modo que:
--   * la escala se aplica de forma determinista (Visual:setScale) sin depender de Model:ScaleTo,
--   * las articulaciones con nombre (`joint`) se animan cambiando solo C0,
--   * el modelo completo se puede sustituir más adelante por un MeshPart con los mismos anclajes.
--
-- Roles de material (los usa MutationVisuals): Body, Belly, Accent, Detail.
-- Los roles Eye, Pupil, Mouth, Teeth, Tongue nunca se recolorean para conservar la cara.
local Kit = {}
Kit.__index = Kit

local Visual = {}
Visual.__index = Visual

Kit.RequiredAnchors = { "Head", "Mouth", "Top", "AuraAnchor", "Ground" }

local function scaleCFrame(cf, s)
	return CFrame.new(cf.Position * s) * cf.Rotation
end

function Kit.new(speciesId, unit)
	local model = Instance.new("Model")
	model.Name = "Visual_" .. speciesId

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.5, 0.5, 0.5)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.CFrame = CFrame.new()
	root.Parent = model
	model.PrimaryPart = root

	local self = setmetatable({
		speciesId = speciesId,
		unit = unit or 1,
		model = model,
		root = root,
		records = {},
		joints = {},
		anchors = {},
		attachments = {},
		partsByName = {},
		eyes = {},
	}, Kit)

	-- Núcleo invisible: todo el cuerpo cuelga de aquí. La articulación "Body" mueve la criatura entera.
	self.core = self:_make("Part", "Core", Vector3.new(0.5, 0.5, 0.5), CFrame.new(), Color3.new(1, 1, 1), {
		transparency = 1,
		parent = root,
		joint = "Body",
		raw = true,
	})
	return self
end

function Kit:_make(className, name, size, cf, color, opts)
	opts = opts or {}
	local unit = opts.raw and 1 or self.unit
	local part = Instance.new(className)
	part.Name = name
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = opts.shadow == true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = opts.material or Enum.Material.SmoothPlastic
	part.Color = color
	part.Transparency = opts.transparency or 0
	part.Reflectance = opts.reflectance or 0
	if opts.shape then
		part.Shape = opts.shape
	end
	local scaledSize = size * unit
	local scaledCf = scaleCFrame(cf, unit)
	part.Size = scaledSize
	part.CFrame = scaledCf

	local parent = opts.parent or self.core
	local pivot = scaledCf
	if opts.pivot then
		pivot = CFrame.new(opts.pivot * unit)
	end
	local weld = Instance.new("Weld")
	weld.Name = opts.joint and ("Joint_" .. opts.joint) or "Weld"
	weld.Part0 = parent
	weld.Part1 = part
	weld.C0 = parent.CFrame:ToObjectSpace(pivot)
	weld.C1 = scaledCf:ToObjectSpace(pivot)
	weld.Parent = part

	if opts.role then
		part:SetAttribute("Role", opts.role)
	end
	if opts.ellipsoid then
		-- Elipsoide: una malla esférica que ocupa el tamaño de la pieza. Permite cuerpos
		-- orgánicos (huevos, gotas, lentejas) con una sola pieza y sin assets externos.
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	end
	-- Piezas de evolución: existen siempre, pero solo se ven a partir de su etapa.
	local hidden = opts.stage ~= nil and opts.stage > 1
	if hidden then
		part.Transparency = 1
	end
	part.Parent = self.model

	local record = {
		part = part,
		weld = weld,
		baseSize = scaledSize,
		baseC0 = weld.C0,
		baseC1 = weld.C1,
		role = opts.role,
		baseColor = color,
		baseMaterial = part.Material,
		baseReflectance = part.Reflectance,
		baseTransparency = opts.transparency or 0,
		stage = opts.stage,
		hidden = hidden,
	}
	table.insert(self.records, record)
	self.partsByName[name] = part
	if opts.joint then
		assert(self.joints[opts.joint] == nil, "duplicate joint " .. opts.joint)
		self.joints[opts.joint] = record
	end
	return part
end

-- Esfera de diámetro `d` centrada en `pos`.
function Kit:ball(name, d, pos, color, opts)
	opts = opts or {}
	opts.shape = Enum.PartType.Ball
	return self:_make("Part", name, Vector3.new(d, d, d), CFrame.new(pos), color, opts)
end

-- Elipsoide de tamaño `size` (Vector3). `cf` puede ser Vector3 o CFrame.
function Kit:blob(name, size, cf, color, opts)
	if typeof(cf) == "Vector3" then
		cf = CFrame.new(cf)
	end
	opts = opts or {}
	opts.ellipsoid = true
	return self:_make("Part", name, size, cf, color, opts)
end

-- Ojo integrado en la cara: globo achatado hundido en la cabeza, iris y pupila que se pueden
-- desplazar (mirada) y un párpado oculto que sale hacia delante para parpadear.
--   opts = { parent, dir (hacia dónde mira, por defecto -Z), iris (Color3), lid (Color3),
--            lidRole, irisScale, stage }
function Kit:eyeball(name, d, pos, opts)
	opts = opts or {}
	local dir = (opts.dir or Vector3.new(0, 0, -1)).Unit
	-- Base ortonormal propia (-Z local = dirección de la mirada, +Y lo más vertical posible).
	local right = dir:Cross(Vector3.new(0, 1, 0))
	if right.Magnitude < 1e-4 then
		right = Vector3.new(1, 0, 0)
	end
	right = right.Unit
	local upVector = right:Cross(dir).Unit
	local frame = CFrame.fromMatrix(pos, right, upVector, -dir)
	local function at(forward, right, up)
		return frame * CFrame.new(right or 0, up or 0, -forward)
	end
	local sclera = self:blob(name, Vector3.new(d, d, d * 0.62), frame, opts.color or Color3.fromRGB(252, 252, 250), {
		role = "Eye", parent = opts.parent, stage = opts.stage,
	})
	local irisD = d * (opts.irisScale or 0.6)
	local iris = self:blob(name .. "Iris", Vector3.new(irisD, irisD, d * 0.2), at(d * 0.25), opts.iris or Color3.fromRGB(40, 44, 60), {
		role = "Pupil", parent = sclera, joint = "Iris_" .. name, stage = opts.stage,
	})
	self:blob(name .. "Pupil", Vector3.new(irisD * 0.55, irisD * 0.55, d * 0.2), at(d * 0.3), Color3.fromRGB(12, 12, 18), {
		role = "Pupil", parent = iris, stage = opts.stage,
	})
	self:blob(name .. "Glint", Vector3.new(d * 0.17, d * 0.17, d * 0.1), at(d * 0.38, irisD * 0.18, irisD * 0.2), Color3.fromRGB(255, 255, 255), {
		role = "Pupil", parent = iris, material = Enum.Material.Neon, stage = opts.stage,
	})
	-- Párpado: en reposo queda detrás de la superficie del ojo (no se ve).
	self:blob(name .. "Lid", Vector3.new(d * 1.06, d * 1.06, d * 0.5), at(-d * 0.08), opts.lid or Color3.fromRGB(120, 120, 120), {
		role = opts.lidRole or "Body", parent = sclera, joint = "Lid_" .. name, stage = opts.stage,
	})
	local up = upVector
	table.insert(self.eyes, {
		name = name,
		iris = "Iris_" .. name,
		lid = "Lid_" .. name,
		dir = dir,
		right = right,
		up = up,
		range = d * 0.16, -- cuánto puede desplazarse el iris
		blink = d * 0.5, -- cuánto avanza el párpado para tapar el ojo
	})
	return sclera
end

-- Bloque. `cf` puede ser Vector3 o CFrame.
function Kit:block(name, size, cf, color, opts)
	if typeof(cf) == "Vector3" then
		cf = CFrame.new(cf)
	end
	return self:_make("Part", name, size, cf, color, opts)
end

-- Cilindro vertical (eje Y de `cf`). `cf` puede ser Vector3 o CFrame.
function Kit:cyl(name, d, height, cf, color, opts)
	if typeof(cf) == "Vector3" then
		cf = CFrame.new(cf)
	end
	opts = opts or {}
	opts.shape = Enum.PartType.Cylinder
	-- El eje del cilindro de Roblox es X: se rota 90° para alinearlo con Y.
	return self:_make("Part", name, Vector3.new(height, d, d), cf * CFrame.Angles(0, 0, math.rad(90)), color, opts)
end

-- Extremidad: cilindro que une dos puntos (hombro -> mano). Evita piezas "flotando" por un
-- ángulo mal calculado.
function Kit:limb(name, from, to, d, color, opts)
	local axis = to - from
	local up = axis.Unit
	local right = up:Cross(Vector3.new(0, 0, 1))
	if right.Magnitude < 1e-3 then
		right = Vector3.new(1, 0, 0)
	end
	right = right.Unit
	local back = right:Cross(up).Unit
	local cf = CFrame.fromMatrix((from + to) / 2, right, up, back)
	opts = opts or {}
	opts.pivot = opts.pivot or from
	return self:cyl(name, d, axis.Magnitude, cf, color, opts)
end

-- Cuña (WedgePart). La pendiente baja hacia -Z local.
function Kit:wedge(name, size, cf, color, opts)
	if typeof(cf) == "Vector3" then
		cf = CFrame.new(cf)
	end
	return self:_make("WedgePart", name, size, cf, color, opts)
end

-- Ojo completo: globo blanco + pupila + brillo. `dir` = dirección de la mirada (por defecto -Z).
function Kit:eye(name, d, pos, opts)
	opts = opts or {}
	local dir = (opts.dir or Vector3.new(0, 0, -1)).Unit
	local eye = self:ball(name, d, pos, opts.color or Color3.fromRGB(250, 250, 250), {
		role = "Eye",
		parent = opts.parent,
		joint = opts.joint,
		pivot = opts.pivot,
	})
	local pupilD = d * (opts.pupil or 0.5)
	self:ball(name .. "Pupil", pupilD, pos + dir * (d * 0.5 - pupilD * 0.28), opts.pupilColor or Color3.fromRGB(15, 15, 20), {
		role = "Pupil",
		parent = eye,
	})
	local up = Vector3.new(0, 1, 0)
	local right = dir:Cross(up)
	if right.Magnitude < 0.01 then
		right = Vector3.new(1, 0, 0)
	end
	self:ball(
		name .. "Glint",
		d * 0.16,
		pos + dir * (d * 0.5) + up * (pupilD * 0.3) + right.Unit * (pupilD * 0.25),
		Color3.fromRGB(255, 255, 255),
		{ role = "Pupil", parent = eye, material = Enum.Material.Neon }
	)
	return eye
end

-- Punto de anclaje para efectos (Attachment). `pos` en espacio de modelo.
function Kit:anchor(name, pos, parentPart)
	local parent = parentPart or self.core
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	local scaled = pos * self.unit
	attachment.CFrame = parent.CFrame:ToObjectSpace(CFrame.new(scaled))
	attachment.Parent = parent
	self.anchors[name] = attachment
	table.insert(self.attachments, { attachment = attachment, base = attachment.CFrame })
	return attachment
end

-- info = { radius = radio horizontal aproximado, height = altura, center = Vector3 centro del cuerpo }
-- `prop = true` para objetos que no son criaturas (comida, decoración): no exige anclajes.
function Kit:finish(info, prop)
	if not prop then
		for _, name in ipairs(Kit.RequiredAnchors) do
			assert(self.anchors[name], self.speciesId .. " is missing anchor " .. name)
		end
	end
	local unit = self.unit
	return setmetatable({
		speciesId = self.speciesId,
		model = self.model,
		root = self.root,
		core = self.core,
		records = self.records,
		joints = self.joints,
		anchors = self.anchors,
		attachments = self.attachments,
		parts = self.partsByName,
		eyes = self.eyes,
		stage = 1,
		radius = info.radius * unit,
		height = info.height * unit,
		center = info.center * unit,
		unit = unit,
		scale = 1,
		poses = {},
		posed = {},
	}, Visual)
end

---------------------------------------------------------------------------------------------
-- Visual: resultado de construir una criatura.
---------------------------------------------------------------------------------------------

-- Aplica una escala uniforme absoluta (1 = tamaño de construcción).
function Visual:setScale(s)
	if s == self.scale then
		return
	end
	self.scale = s
	for _, record in ipairs(self.records) do
		record.part.Size = record.baseSize * s
		record.weld.C1 = scaleCFrame(record.baseC1, s)
		record.weld.C0 = scaleCFrame(record.baseC0, s)
	end
	for _, entry in ipairs(self.attachments) do
		entry.attachment.CFrame = scaleCFrame(entry.base, s)
	end
	-- Las poses activas se reaplican en el siguiente applyPoses().
	for name in pairs(self.posed) do
		self.poses[name] = self.poses[name] or CFrame.new()
	end
end

-- Define el desplazamiento de una articulación para este frame. Con `additive` se compone con
-- la pose ya definida (p. ej. comer encima del idle).
function Visual:pose(jointName, offset, additive)
	if not self.joints[jointName] then
		return
	end
	local current = self.poses[jointName]
	if additive and current then
		self.poses[jointName] = current * offset
	else
		self.poses[jointName] = offset
	end
end

-- Escribe las poses en los Welds. Las articulaciones sin pose vuelven a reposo.
function Visual:applyPoses()
	local s = self.scale
	for name, record in pairs(self.joints) do
		local offset = self.poses[name]
		if offset then
			record.weld.C0 = scaleCFrame(record.baseC0, s) * scaleCFrame(offset, s * self.unit)
			self.posed[name] = true
		elseif self.posed[name] then
			record.weld.C0 = scaleCFrame(record.baseC0, s)
			self.posed[name] = nil
		end
	end
	table.clear(self.poses)
end

-- Parpadeo: a = 0 (abierto) .. 1 (cerrado). Se llama antes de applyPoses().
function Visual:setBlink(a)
	if a <= 0 then
		return
	end
	for _, eye in ipairs(self.eyes) do
		-- El desplazamiento va en el espacio local del ojo (-Z = hacia donde mira).
		self:pose(eye.lid, CFrame.new(0, 0, -eye.blink * a), true)
	end
end

-- Mirada: x, y en [-1, 1] (derecha / arriba de la criatura). Se llama antes de applyPoses().
function Visual:setLook(x, y)
	if x == 0 and y == 0 then
		return
	end
	for _, eye in ipairs(self.eyes) do
		self:pose(eye.iris, CFrame.new(x * eye.range, y * eye.range, 0), true)
	end
end

-- Etapa de evolución (1..n): muestra las piezas cuya etapa ya se ha alcanzado.
function Visual:setStage(stage)
	self.stage = stage
	for _, record in ipairs(self.records) do
		if record.stage and record.stage > 1 then
			record.hidden = record.stage > stage
			record.part.Transparency = record.hidden and 1 or record.baseTransparency
		end
	end
end

function Visual:resetPoses()
	table.clear(self.poses)
	self:applyPoses()
end

-- Posición en el mundo de un anclaje. No depende de Attachment.WorldPosition para que funcione
-- también con piezas recién creadas.
function Visual:anchorWorld(name)
	local attachment = self.anchors[name]
	if not attachment then
		return self.root.CFrame.Position
	end
	local parent = attachment.Parent
	return (parent.CFrame * attachment.CFrame).Position
end

function Visual:destroy()
	if self.model then
		self.model:Destroy()
		self.model = nil
	end
end

Kit.Visual = Visual
Kit.scaleCFrame = scaleCFrame

return Kit
