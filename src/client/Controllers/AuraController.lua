-- Auras persistentes de las criaturas (mutaciones y rareza SECRET), totalmente dirigidas por
-- VFXConfig.Auras. Un mismo controlador sirve para todas las especies: usa los anclajes y el
-- radio/altura del Visual, de modo que el aura se adapta al tamaño y la anatomía de cada una.
--
-- Rendimiento:
--   * Solo las auras más cercanas a la cámara están construidas (LOD cada LodInterval s);
--     las lejanas no tienen NINGUNA instancia.
--   * Presupuesto de partículas, luces, orbitadores, anillos y arcos según la calidad.
--   * Un único bucle actualiza todas las auras activas; nada crea emisores por frame.
--   * Al destruirse la criatura o cambiar la calidad, se limpia todo.
--
-- API:
--   AuraController.attach(key, visual, mutationId, rarity, scale)
--   AuraController.detach(key)
--   AuraController.rebuildAll()
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local VFXConfig = require(Shared.Config.VFXConfig)
local MutationConfig = require(Shared.Config.MutationConfig)

local AuraController = {}

local controllers
local SettingsController
local EffectsController
local AudioController

local auras = {} -- key -> aura
local order = {} -- lista de claves (para iterar de forma estable)
local lodTimer = 0
local clock = 0
local rng = Random.new()

local function fxPart(name, anchored)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = anchored
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

---------------------------------------------------------------------------------------------
-- Construcción de capas
---------------------------------------------------------------------------------------------
local builders = {}

function builders.Emitter(aura, layer, ctx)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = layer.name or "AuraEmitter"
	EffectsController.applyEmitterProps(emitter, layer.props, ctx.sizeFactor)
	emitter.Rate = layer.props.Rate * ctx.rateFactor
	if layer.target == "Volume" then
		emitter.Shape = Enum.ParticleEmitterShape.Sphere
		emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		emitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
		emitter.Parent = ctx.volume
	else
		local anchor = aura.visual.anchors[layer.target] or aura.visual.anchors.AuraAnchor
		emitter.Parent = anchor
	end
	table.insert(aura.instances, emitter)
	ctx.particles += VFXConfig.estimateParticles(layer.props, ctx.rateFactor)
end

function builders.Light(aura, layer, ctx)
	if aura.light or not ctx.allowLight then
		return
	end
	local light = Instance.new("PointLight")
	light.Color = layer.color
	light.Brightness = layer.brightness
	light.Range = math.min(40, layer.range * ctx.radius)
	light.Shadows = false
	light.Parent = ctx.volume
	aura.light = { light = light, base = layer.brightness, pulse = layer.pulse or 0, speed = layer.pulseSpeed or 1 }
	table.insert(aura.instances, light)
end

function builders.Highlight(aura, layer, ctx)
	if not ctx.quality.highlights and layer.quality ~= "Low" then
		return
	end
	local highlight = aura.highlight
	if not highlight then
		highlight = Instance.new("Highlight")
		highlight.Name = "AuraHighlight"
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Adornee = aura.visual.model
		highlight.Parent = aura.container
		aura.highlight = highlight
	end
	highlight.OutlineColor = layer.outline
	highlight.FillColor = layer.fill
	highlight.FillTransparency = layer.fillTransparency
	highlight.OutlineTransparency = layer.outlineTransparency
end

function builders.GroundRing(aura, layer, ctx)
	local function ring(color, diameter, transparency, lift)
		local part = fxPart("AuraGround", true)
		part.Shape = Enum.PartType.Cylinder
		part.Material = Enum.Material.Neon
		part.Color = color
		part.Transparency = transparency
		part.Size = Vector3.new(0.08, diameter, diameter)
		part.CFrame = CFrame.new(ctx.ground + Vector3.new(0, lift, 0)) * CFrame.Angles(0, 0, math.rad(90))
		part.Parent = aura.container
		return part
	end
	local diameter = layer.radius * ctx.radius * 2
	local outer = ring(layer.color, diameter, layer.transparency, 0.06)
	table.insert(aura.groundRings, {
		part = outer,
		base = layer.transparency,
		pulse = layer.pulse or 0,
		speed = layer.pulseSpeed or 1,
		phase = 0,
	})
	if layer.inner then
		local inner = ring(layer.inner, diameter * 0.62, math.min(0.9, layer.transparency + 0.15), 0.1)
		table.insert(aura.groundRings, {
			part = inner,
			base = math.min(0.9, layer.transparency + 0.15),
			pulse = layer.pulse or 0,
			speed = layer.pulseSpeed or 1,
			phase = math.pi,
		})
	end
end

local function orbiterPart(layer, index, size)
	local part = fxPart("AuraOrbiter", true)
	if layer.shape == "Coin" then
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(size * 0.18, size, size)
		part.Material = Enum.Material.Metal
		part.Reflectance = 0.35
		part.Color = layer.color
	elseif layer.shape == "Planet" then
		part.Shape = Enum.PartType.Ball
		local s = size * (0.7 + (index % 3) * 0.25)
		part.Size = Vector3.new(s, s, s)
		part.Material = Enum.Material.Neon
		part.Color = index % 2 == 0 and layer.color or Color3.fromRGB(255, 150, 235)
	else -- Cube
		part.Size = Vector3.new(size, size, size)
		local alt = layer.altColor ~= nil and index % 2 == 0
		part.Material = alt and Enum.Material.SmoothPlastic or Enum.Material.Neon
		part.Color = alt and layer.altColor or layer.color
	end
	return part
end

function builders.Orbit(aura, layer, ctx)
	if not ctx.quality.orbiters then
		return
	end
	local count = math.min(VFXConfig.countFor(layer, ctx.qualityName), VFXConfig.Limits.MaxOrbitersPerAura - #aura.orbiters)
	for index = 1, count do
		local part = orbiterPart(layer, index, layer.size * ctx.sizeFactor)
		part.Parent = aura.container
		local variance = layer.speedVariance or 0
		table.insert(aura.orbiters, {
			part = part,
			angle = (index - 1) / count * math.pi * 2,
			speed = layer.speed * (1 + variance * ((index % 3) - 1) * 0.5),
			radius = layer.radius * ctx.radius * (1 + ((index % 2) * 0.12)),
			height = (layer.height - 0.5) * ctx.height,
			bob = (layer.bob or 0) * ctx.radius,
			tilt = math.rad(layer.tilt or 0),
			spin = layer.shape == "Coin" and 3 or 1.2,
			phase = index * 1.7,
		})
	end
end

function builders.Ring(aura, layer, ctx)
	if not ctx.quality.rings or #aura.rings >= VFXConfig.Limits.MaxRingsPerAura then
		return
	end
	local radius = layer.radius * ctx.radius
	local rig = fxPart("AuraRing", true)
	rig.Transparency = 1
	rig.Size = Vector3.new(0.2, 0.2, 0.2)
	-- Dos anclajes opuestos con el eje X apuntando a +Z: con CurveSize = ±4r/3 dos Beams
	-- cúbicos dibujan un círculo casi perfecto con solo dos instancias.
	local a = Instance.new("Attachment")
	a.CFrame = CFrame.new(-radius, 0, 0) * CFrame.Angles(0, math.rad(-90), 0)
	a.Parent = rig
	local b = Instance.new("Attachment")
	b.CFrame = CFrame.new(radius, 0, 0) * CFrame.Angles(0, math.rad(-90), 0)
	b.Parent = rig
	local k = radius * 4 / 3
	local colors = ColorSequence.new(layer.colors[1], layer.colors[2] or layer.colors[1])
	for _, sign in ipairs({ 1, -1 }) do
		local beam = Instance.new("Beam")
		beam.Attachment0 = a
		beam.Attachment1 = b
		beam.CurveSize0 = k * sign
		beam.CurveSize1 = -k * sign
		beam.Segments = 24
		beam.Width0 = layer.width * ctx.sizeFactor
		beam.Width1 = layer.width * ctx.sizeFactor
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.Transparency = NumberSequence.new(0.15)
		beam.Color = colors
		beam.Parent = rig
	end
	rig.Parent = aura.container
	local tilt = math.rad(layer.tilt or 0)
	table.insert(aura.rings, {
		part = rig,
		tilt = layer.tiltAxis == "Z" and CFrame.Angles(0, 0, tilt) or CFrame.Angles(tilt, 0, 0),
		speed = layer.speed,
		height = (layer.height - 0.5) * ctx.height,
	})
end

function builders.Arc(aura, layer, ctx)
	if not ctx.quality.arcs then
		return
	end
	local count = math.min(VFXConfig.countFor(layer, ctx.qualityName), VFXConfig.Limits.MaxArcsPerAura - #aura.arcs)
	for index = 1, count do
		local a = Instance.new("Attachment")
		a.Name = "ArcA"
		a.Parent = ctx.volume
		local b = Instance.new("Attachment")
		b.Name = "ArcB"
		b.Parent = ctx.volume
		local beam = Instance.new("Beam")
		beam.Attachment0 = a
		beam.Attachment1 = b
		beam.Segments = 8
		beam.Width0 = layer.width * ctx.sizeFactor
		beam.Width1 = layer.width * ctx.sizeFactor * 0.6
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.Color = ColorSequence.new(layer.colors[(index - 1) % #layer.colors + 1])
		beam.Enabled = false
		beam.Parent = ctx.volume
		table.insert(aura.instances, a)
		table.insert(aura.instances, b)
		table.insert(aura.instances, beam)
		table.insert(aura.arcs, {
			a = a,
			b = b,
			beam = beam,
			layer = layer,
			radius = ctx.radius,
			nextAt = clock + rng:NextNumber(layer.interval[1], layer.interval[2]) * (0.3 + index * 0.4),
			offAt = 0,
		})
	end
end

function builders.Glitch(aura, layer)
	aura.glitch = {
		layer = layer,
		nextAt = clock + rng:NextNumber(layer.interval[1], layer.interval[2]),
		offAt = 0,
		active = false,
	}
end

---------------------------------------------------------------------------------------------
-- Ciclo de vida de un aura
---------------------------------------------------------------------------------------------
local function destroyInstances(aura)
	if aura.glitch and aura.glitch.active then
		aura.visual.root.CFrame = aura.baseRoot
	end
	for _, instance in ipairs(aura.instances) do
		instance:Destroy()
	end
	if aura.container then
		aura.container:Destroy()
	end
	aura.container = nil
	aura.instances = {}
	aura.orbiters = {}
	aura.rings = {}
	aura.arcs = {}
	aura.groundRings = {}
	aura.light = nil
	aura.highlight = nil
	aura.glitch = nil
	aura.built = false
	aura.particles = 0
end

local function build(aura, allowLight)
	destroyInstances(aura)
	if #aura.auraIds == 0 or not aura.visual.model then
		return
	end
	local qualityName = SettingsController.quality()
	local quality = VFXConfig.Quality[qualityName]
	local visual = aura.visual
	local scale = aura.scale
	local radius = visual.radius * scale
	local height = visual.height * scale

	local container = Instance.new("Folder")
	container.Name = "Aura"
	aura.container = container

	-- Volumen invisible soldado al núcleo: sigue a la criatura cuando se mueve o anima.
	local center = visual:anchorWorld("AuraAnchor")
	local volume = fxPart("AuraVolume", false)
	volume.Transparency = 1
	volume.Shape = Enum.PartType.Ball
	volume.Size = Vector3.new(radius * 2.1, radius * 2.1, radius * 2.1)
	volume.CFrame = CFrame.new(center)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = visual.core
	weld.Part1 = volume
	weld.Parent = volume
	volume.Parent = container

	local rateFactor = VFXConfig.rateScaleFor(aura.auraIds, qualityName)
	local ctx = {
		qualityName = qualityName,
		quality = quality,
		radius = radius,
		height = height,
		sizeFactor = math.clamp(radius / 2.5, 0.6, 4),
		rateFactor = rateFactor,
		volume = volume,
		ground = visual.root.CFrame.Position,
		allowLight = allowLight,
		particles = 0,
	}
	aura.baseRoot = visual.root.CFrame
	aura.center = center
	aura.height = height

	for _, auraId in ipairs(aura.auraIds) do
		local def = VFXConfig.Auras[auraId]
		for _, layer in ipairs(def.layers) do
			if VFXConfig.layerEnabled(layer, qualityName) then
				local builder = builders[layer.type]
				if builder then
					builder(aura, layer, ctx)
				end
			end
		end
	end

	container.Parent = visual.model
	aura.particles = ctx.particles
	aura.built = true
	aura.builtScale = scale
	aura.builtQuality = qualityName
end

function AuraController.attach(key, visual, mutationId, rarity, scale)
	local mutation = MutationConfig.Mutations[mutationId]
	local auraIds = VFXConfig.aurasFor(mutation and mutation.aura, rarity)
	local aura = auras[key]
	if not aura then
		aura = {
			key = key,
			instances = {},
			orbiters = {},
			rings = {},
			arcs = {},
			groundRings = {},
			built = false,
			particles = 0,
		}
		auras[key] = aura
		table.insert(order, key)
	else
		destroyInstances(aura)
	end
	aura.visual = visual
	aura.auraIds = auraIds
	aura.scale = scale
	-- Se construirá en el siguiente paso de LOD si está lo bastante cerca.
	lodTimer = math.huge
end

-- Actualiza la escala; reconstruye solo si el cambio es apreciable.
function AuraController.setScale(key, scale)
	local aura = auras[key]
	if not aura then
		return
	end
	aura.scale = scale
	if aura.built and math.abs(scale - aura.builtScale) / aura.builtScale > VFXConfig.Limits.RebuildScaleDelta then
		destroyInstances(aura)
		lodTimer = math.huge
	end
end

function AuraController.detach(key)
	local aura = auras[key]
	if not aura then
		return
	end
	destroyInstances(aura)
	auras[key] = nil
	local index = table.find(order, key)
	if index then
		table.remove(order, index)
	end
end

function AuraController.rebuildAll()
	for _, key in ipairs(order) do
		destroyInstances(auras[key])
	end
	lodTimer = math.huge
end

-- Diagnóstico (también lo usan los tests).
function AuraController.stats()
	local built, particles, lights = 0, 0, 0
	for _, key in ipairs(order) do
		local aura = auras[key]
		if aura.built then
			built += 1
			particles += aura.particles
			if aura.light then
				lights += 1
			end
		end
	end
	return { total = #order, built = built, particles = particles, lights = lights }
end

function AuraController.get(key)
	return auras[key]
end

---------------------------------------------------------------------------------------------
-- LOD y actualización
---------------------------------------------------------------------------------------------
local function hasLightLayer(aura, qualityName)
	for _, auraId in ipairs(aura.auraIds) do
		for _, layer in ipairs(VFXConfig.Auras[auraId].layers) do
			if layer.type == "Light" and VFXConfig.layerEnabled(layer, qualityName) then
				return true
			end
		end
	end
	return false
end

local function updateLod()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local qualityName = SettingsController.quality()
	local quality = VFXConfig.Quality[qualityName]
	local cameraPos = camera.CFrame.Position

	local candidates = {}
	for _, key in ipairs(order) do
		local aura = auras[key]
		if #aura.auraIds > 0 and aura.visual.model and aura.visual.model.Parent then
			local distance = (aura.visual.root.CFrame.Position - cameraPos).Magnitude
			-- Histéresis: una aura ya construida aguanta un poco más lejos.
			local limit = quality.auraDistance * (aura.built and 1.12 or 1)
			if distance <= limit then
				table.insert(candidates, { aura = aura, distance = distance })
			elseif aura.built then
				destroyInstances(aura)
			end
		elseif aura.built then
			destroyInstances(aura)
		end
	end
	table.sort(candidates, function(a, b)
		return a.distance < b.distance
	end)

	local lights = 0
	for index, candidate in ipairs(candidates) do
		local aura = candidate.aura
		if index > quality.maxActiveAuras then
			if aura.built then
				destroyInstances(aura)
			end
		else
			-- Las luces son el recurso más caro: solo las reciben las auras más cercanas.
			local allowLight = hasLightLayer(aura, qualityName) and lights < quality.maxLights
			local needsRebuild = not aura.built
				or aura.builtQuality ~= qualityName
				or (aura.light ~= nil) ~= allowLight
			if needsRebuild then
				build(aura, allowLight)
			end
			if aura.light then
				lights += 1
			end
		end
	end
end

local function randomOnSphere(radius)
	local theta = rng:NextNumber(0, math.pi * 2)
	local y = rng:NextNumber(-0.8, 0.8)
	local r = math.sqrt(1 - y * y)
	return Vector3.new(math.cos(theta) * r, y, math.sin(theta) * r) * radius
end

local function updateAura(aura, dt)
	local visual = aura.visual
	local center = visual:anchorWorld("AuraAnchor")

	for _, orbiter in ipairs(aura.orbiters) do
		orbiter.angle += orbiter.speed * dt
		local a = orbiter.angle
		local offset = Vector3.new(math.cos(a) * orbiter.radius, math.sin(clock * 1.3 + orbiter.phase) * orbiter.bob, math.sin(a) * orbiter.radius)
		if orbiter.tilt ~= 0 then
			offset = CFrame.Angles(orbiter.tilt, 0, 0):VectorToWorldSpace(offset)
		end
		orbiter.part.CFrame = CFrame.new(center + Vector3.new(0, orbiter.height, 0) + offset)
			* CFrame.Angles(0, clock * orbiter.spin + orbiter.phase, math.rad(90))
	end

	for _, ring in ipairs(aura.rings) do
		ring.part.CFrame = CFrame.new(center + Vector3.new(0, ring.height, 0)) * ring.tilt * CFrame.Angles(0, clock * ring.speed, 0)
	end

	for _, ground in ipairs(aura.groundRings) do
		if ground.pulse > 0 then
			ground.part.Transparency = math.clamp(ground.base + math.sin(clock * ground.speed + ground.phase) * ground.pulse, 0, 1)
		end
	end

	local light = aura.light
	if light and light.pulse > 0 then
		-- Variación suave y lenta (nunca parpadeo brusco).
		light.light.Brightness = light.base * (1 + math.sin(clock * light.speed) * light.pulse)
	end

	for _, arc in ipairs(aura.arcs) do
		if arc.beam.Enabled then
			if clock >= arc.offAt then
				arc.beam.Enabled = false
			end
		elseif clock >= arc.nextAt then
			local layer = arc.layer
			arc.a.CFrame = CFrame.new(randomOnSphere(arc.radius * 0.95))
			arc.b.CFrame = CFrame.new(randomOnSphere(arc.radius * 0.95))
			arc.beam.CurveSize0 = rng:NextNumber(-1, 1) * layer.jitter * arc.radius * 2
			arc.beam.CurveSize1 = rng:NextNumber(-1, 1) * layer.jitter * arc.radius * 2
			arc.beam.Enabled = true
			arc.offAt = clock + rng:NextNumber(layer.duration[1], layer.duration[2])
			arc.nextAt = clock + rng:NextNumber(layer.interval[1], layer.interval[2])
			if layer.sound then
				AudioController.play(layer.sound, center)
			end
		end
	end

	local glitch = aura.glitch
	if glitch then
		if glitch.active then
			if clock >= glitch.offAt then
				visual.root.CFrame = aura.baseRoot
				glitch.active = false
			end
		elseif clock >= glitch.nextAt then
			local amplitude = glitch.layer.amplitude * visual.radius * aura.scale
			visual.root.CFrame = aura.baseRoot * CFrame.new(rng:NextNumber(-1, 1) * amplitude, 0, rng:NextNumber(-1, 1) * amplitude)
			glitch.active = true
			glitch.offAt = clock + glitch.layer.duration
			glitch.nextAt = clock + rng:NextNumber(glitch.layer.interval[1], glitch.layer.interval[2])
		end
	end
end

function AuraController.Init(allControllers)
	controllers = allControllers
	SettingsController = controllers.SettingsController
	EffectsController = controllers.EffectsController
	AudioController = controllers.AudioController
end

function AuraController.Start()
	SettingsController.QualityChanged:Connect(function()
		AuraController.rebuildAll()
	end)
end

function AuraController.Update(dt)
	clock += dt
	lodTimer += dt
	if lodTimer >= VFXConfig.Limits.LodInterval then
		lodTimer = 0
		updateLod()
	end
	for _, key in ipairs(order) do
		local aura = auras[key]
		if aura.built then
			updateAura(aura, dt)
		end
	end
end

return AuraController
