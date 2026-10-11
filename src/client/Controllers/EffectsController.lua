-- Reproducción local de efectos puntuales (one-shots) definidos en VFXConfig.Effects.
-- Es puramente cosmético: el servidor solo dice "qué efecto y dónde".
--
--   * Reutiliza emisores de un pool (no crea emisores nuevos en cada efecto).
--   * Respeta la calidad gráfica: nº de partículas, luces y efectos simultáneos.
--   * Descarta efectos lejanos y limpia todo mediante EffectCleanup.
--
-- API:
--   EffectsController.play(effectId, payload)   payload = { model?, position?, radius? }
--   EffectsController.clear()
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local VFXConfig = require(Shared.Config.VFXConfig)
local Constants = require(Shared.Constants)

local EffectsController = {}

local controllers
local SettingsController
local EffectCleanup
local AudioController

local folder
local pool = {} -- hosts libres: { part, attachment, emitter }
local hostCount = 0
local activeEffects = 0
local activeLights = 0
local rings = {} -- { part, elapsed, time, from, to }
local flashes = {} -- { light, part, elapsed, time, brightness }

local function getFolder()
	if folder and folder.Parent then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = Constants.Folders.ClientFX
	folder.Parent = workspace
	return folder
end

local function newHostPart(name)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	return part
end

local function acquireHost()
	local host = table.remove(pool)
	if host then
		return host
	end
	if hostCount >= VFXConfig.Limits.OneShotPoolSize * 3 then
		return nil
	end
	hostCount += 1
	local part = newHostPart("FXHost")
	local attachment = Instance.new("Attachment")
	attachment.Parent = part
	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	emitter.Rate = 0
	emitter.Parent = attachment
	part.Parent = getFolder()
	return { part = part, attachment = attachment, emitter = emitter }
end

local function releaseHost(host)
	if host.part.Parent then
		table.insert(pool, host)
	else
		hostCount = math.max(0, hostCount - 1)
	end
end

-- Escala los valores de un NumberSequence.
local function scaleSequence(sequence, factor)
	if factor == 1 then
		return sequence
	end
	local keys = {}
	for _, key in ipairs(sequence.Keypoints) do
		table.insert(keys, NumberSequenceKeypoint.new(key.Time, key.Value * factor, key.Envelope * factor))
	end
	return NumberSequence.new(keys)
end
EffectsController.scaleSequence = scaleSequence

-- Valores neutros de las propiedades que usa VFXConfig. Los emisores del pool se reutilizan,
-- así que antes de cada ráfaga se restablecen para no heredar ajustes del efecto anterior.
local EMITTER_DEFAULTS = {
	Acceleration = Vector3.new(0, 0, 0),
	Drag = 0,
	SpreadAngle = Vector2.new(0, 0),
	Rotation = NumberRange.new(0),
	RotSpeed = NumberRange.new(0),
	Speed = NumberRange.new(5),
	Lifetime = NumberRange.new(1),
	Transparency = NumberSequence.new(0),
	Size = NumberSequence.new(1),
	LightEmission = 0,
	ZOffset = 0,
	LockedToPart = false,
}

-- Aplica una tabla de propiedades de VFXConfig a un ParticleEmitter.
-- Con `reset` restablece primero las propiedades que `props` no define.
function EffectsController.applyEmitterProps(emitter, props, sizeFactor, reset)
	if reset then
		for key, value in pairs(EMITTER_DEFAULTS) do
			if props[key] == nil then
				emitter[key] = value
			end
		end
	end
	for key, value in pairs(props) do
		if key == "Size" then
			emitter.Size = scaleSequence(value, sizeFactor or 1)
		elseif key == "Speed" and sizeFactor and sizeFactor ~= 1 then
			emitter.Speed = NumberRange.new(value.Min * sizeFactor, value.Max * sizeFactor)
		elseif key ~= "Rate" then
			emitter[key] = value
		end
	end
end

-- Resuelve dónde ocurre el efecto. Devuelve función(anclaje) -> Vector3, radio.
local function resolveTarget(payload)
	local model = payload.model
	if typeof(model) == "Instance" and model.Parent then
		local visual, scale = controllers.CreatureController.visualFor(model)
		if visual then
			local radius = visual.radius * scale
			return function(anchorName)
				if anchorName == "Center" then
					return visual:anchorWorld("AuraAnchor")
				end
				return visual:anchorWorld(anchorName)
			end, radius
		end
		if model:IsA("PVInstance") then
			local position = model:GetPivot().Position
			return function()
				return position
			end, payload.radius or 2.5
		end
	end
	local position = payload.position
	if typeof(position) ~= "Vector3" then
		return nil, 0
	end
	local radius = type(payload.radius) == "number" and payload.radius or 2
	return function(anchorName)
		if anchorName == "Ground" then
			return position - Vector3.new(0, 2.5, 0)
		elseif anchorName == "Top" then
			return position + Vector3.new(0, radius, 0)
		end
		return position
	end, radius
end

local function spawnRing(def, position, radius)
	local part = Instance.new("Part")
	part.Name = "FXRing"
	part.Shape = Enum.PartType.Cylinder
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = def.color
	part.Transparency = 0.35
	local from = def.from * radius * 2
	part.Size = Vector3.new(0.15, from, from)
	part.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	part.Parent = getFolder()
	table.insert(rings, { part = part, elapsed = 0, time = def.time, from = from, to = def.to * radius * 2 })
end

local function spawnFlash(def, position, radius)
	local quality = SettingsController.qualityConfig()
	if activeLights >= quality.maxLights then
		return
	end
	local part = newHostPart("FXFlash")
	part.CFrame = CFrame.new(position)
	local light = Instance.new("PointLight")
	light.Color = def.color
	light.Brightness = 0
	light.Range = math.min(40, def.range * radius)
	light.Shadows = false
	light.Parent = part
	part.Parent = getFolder()
	activeLights += 1
	table.insert(flashes, { part = part, light = light, elapsed = 0, time = def.time, brightness = def.brightness })
end

function EffectsController.play(effectId, payload)
	local def = VFXConfig.Effects[effectId]
	if not def or type(payload) ~= "table" then
		return false
	end
	local qualityName = SettingsController.quality()
	local quality = VFXConfig.Quality[qualityName]
	if not VFXConfig.layerEnabled(def, qualityName) then
		return false
	end
	local anchorAt, radius = resolveTarget(payload)
	if not anchorAt then
		return false
	end
	local center = anchorAt("Center")

	-- El sonido y el "pop" no dependen del presupuesto de partículas.
	if def.sound then
		AudioController.play(def.sound, center)
	end
	if def.pop and typeof(payload.model) == "Instance" then
		controllers.CreatureController.pop(payload.model, def.pop)
	end

	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - center).Magnitude > (def.maxDistance or 120) then
		return false
	end
	-- Límite de efectos simultáneos: los de prioridad baja se descartan primero.
	if activeEffects >= quality.maxOneShots and (def.priority or 1) < 3 then
		return false
	end
	if activeEffects >= quality.maxOneShots * 2 then
		return false
	end

	local sizeFactor = math.clamp(radius / 2.5, 0.6, 3.5)
	local longest = 0.2
	for _, burst in ipairs(def.bursts or {}) do
		if VFXConfig.layerEnabled(burst, qualityName) then
			local host = acquireHost()
			if host then
				host.part.CFrame = CFrame.new(anchorAt(burst.at))
				EffectsController.applyEmitterProps(host.emitter, burst.props, sizeFactor, true)
				local count = math.max(1, math.floor(burst.count * quality.burstScale + 0.5))
				host.emitter:Emit(count)
				local life = burst.props.Lifetime and burst.props.Lifetime.Max or 1
				longest = math.max(longest, life)
				EffectCleanup.after(math.min(VFXConfig.Limits.OneShotMaxLifetime, life + 0.1), function()
					releaseHost(host)
				end)
			end
		end
	end
	if def.ring then
		spawnRing(def.ring, anchorAt("Ground") + Vector3.new(0, 0.15, 0), radius)
		longest = math.max(longest, def.ring.time)
	end
	if def.flash then
		spawnFlash(def.flash, center, sizeFactor)
		longest = math.max(longest, def.flash.time)
	end
	if def.priority == 3 and controllers.CameraController then
		controllers.CameraController.bump(0.35)
	end

	activeEffects += 1
	EffectCleanup.after(math.min(VFXConfig.Limits.OneShotMaxLifetime, longest), function()
		activeEffects = math.max(0, activeEffects - 1)
	end)
	return true
end

-- Elimina todos los efectos en curso (cambio de calidad, comando de admin...).
function EffectsController.clear()
	for _, ring in ipairs(rings) do
		ring.part:Destroy()
	end
	rings = {}
	for _, flash in ipairs(flashes) do
		flash.part:Destroy()
	end
	flashes = {}
	activeLights = 0
	EffectCleanup.clearAll()
	activeEffects = 0
	for _, host in ipairs(pool) do
		host.part:Destroy()
	end
	pool = {}
	hostCount = 0
	if folder then
		folder:ClearAllChildren()
	end
end

function EffectsController.stats()
	return { active = activeEffects, hosts = hostCount, pooled = #pool, rings = #rings, lights = activeLights }
end

function EffectsController.Init(allControllers)
	controllers = allControllers
	SettingsController = controllers.SettingsController
	EffectCleanup = controllers.EffectCleanup
	AudioController = controllers.AudioController
end

function EffectsController.Start()
	controllers.StateController.remote("Effect").OnClientEvent:Connect(function(effectId, payload)
		if effectId == "__clear" then
			EffectsController.clear()
			controllers.AuraController.rebuildAll()
			return
		end
		if type(effectId) == "string" and type(payload) == "table" then
			EffectsController.play(effectId, payload)
		end
	end)
	SettingsController.QualityChanged:Connect(function()
		EffectsController.clear()
	end)
end

function EffectsController.Update(dt)
	-- Ondas expansivas
	local index = 1
	while index <= #rings do
		local ring = rings[index]
		ring.elapsed += dt
		local a = math.clamp(ring.elapsed / ring.time, 0, 1)
		if a >= 1 then
			ring.part:Destroy()
			rings[index] = rings[#rings]
			rings[#rings] = nil
		else
			local eased = 1 - (1 - a) * (1 - a)
			local d = ring.from + (ring.to - ring.from) * eased
			ring.part.Size = Vector3.new(0.15, d, d)
			ring.part.Transparency = 0.35 + 0.65 * a
			index += 1
		end
	end
	-- Destellos: un único fundido suave (sube y baja una sola vez).
	index = 1
	while index <= #flashes do
		local flash = flashes[index]
		flash.elapsed += dt
		local a = math.clamp(flash.elapsed / flash.time, 0, 1)
		if a >= 1 then
			flash.part:Destroy()
			activeLights = math.max(0, activeLights - 1)
			flashes[index] = flashes[#flashes]
			flashes[#flashes] = nil
		else
			flash.light.Brightness = flash.brightness * math.sin(a * math.pi)
			index += 1
		end
	end
end

return EffectsController
