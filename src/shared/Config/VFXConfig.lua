-- Configuración centralizada de efectos visuales (auras persistentes y efectos puntuales).
-- Solo usa instancias nativas (ParticleEmitter, Beam, Highlight, PointLight, Parts) y las tres
-- texturas de partículas incluidas en el motor. No hay IDs de assets externos.
--
-- Reglas de seguridad visual: ningún efecto parpadea más de ~2 veces por segundo, los destellos
-- son un único fundido suave y las luces nunca saltan de brillo bruscamente.
local VFXConfig = {}

local function ns(points)
	local keys = {}
	for _, p in ipairs(points) do
		table.insert(keys, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(keys)
end

local function cs(colors)
	if #colors == 1 then
		return ColorSequence.new(colors[1])
	end
	local keys = {}
	for i, c in ipairs(colors) do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), c))
	end
	return ColorSequence.new(keys)
end

local rgb = Color3.fromRGB

-- Texturas incluidas con el cliente de Roblox (no son assets subidos).
VFXConfig.Textures = {
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
}
local TEX = VFXConfig.Textures

---------------------------------------------------------------------------------------------
-- Calidad gráfica
---------------------------------------------------------------------------------------------
VFXConfig.QualityOrder = { "Low", "Medium", "High" }
VFXConfig.DefaultQuality = "Medium"

VFXConfig.Quality = {
	Low = {
		rank = 1,
		auraDistance = 55, -- más lejos que esto el aura se apaga
		maxActiveAuras = 6,
		maxAuraParticles = 24, -- partículas vivas estimadas por aura (rate * lifetime)
		particleScale = 0.3,
		maxLights = 0,
		maxOneShots = 6, -- efectos puntuales simultáneos
		burstScale = 0.35,
		animDistance = 50,
		animHz = 20,
		orbiters = false,
		arcs = false,
		rings = false,
		highlights = false,
	},
	Medium = {
		rank = 2,
		auraDistance = 95,
		maxActiveAuras = 12,
		maxAuraParticles = 60,
		particleScale = 0.6,
		maxLights = 2,
		maxOneShots = 12,
		burstScale = 0.65,
		animDistance = 85,
		animHz = 30,
		orbiters = true,
		arcs = true,
		rings = true,
		highlights = true,
	},
	High = {
		rank = 3,
		auraDistance = 150,
		maxActiveAuras = 24,
		maxAuraParticles = 130,
		particleScale = 1,
		maxLights = 6,
		maxOneShots = 24,
		burstScale = 1,
		animDistance = 130,
		animHz = 60,
		orbiters = true,
		arcs = true,
		rings = true,
		highlights = true,
	},
}

VFXConfig.Limits = {
	LodInterval = 0.5, -- cada cuánto se recalcula qué auras están activas
	MaxOrbitersPerAura = 6,
	MaxRingsPerAura = 2,
	MaxArcsPerAura = 2,
	OneShotPoolSize = 24,
	OneShotMaxLifetime = 4,
	RebuildScaleDelta = 0.12, -- cambio relativo de escala que fuerza reconstruir el aura
}

---------------------------------------------------------------------------------------------
-- Auras persistentes
-- Tipos de capa: Emitter, Light, Highlight, Orbit, GroundRing, Ring, Arc, Glitch
-- `quality` = calidad mínima para que la capa exista.
-- Emitter.target: "Volume" (volumen alrededor del cuerpo) o un anclaje ("Ground", "Head", "Top"...).
-- Las medidas de Orbit/Ring/GroundRing son múltiplos del radio de la criatura.
---------------------------------------------------------------------------------------------
VFXConfig.Auras = {
	GOLDEN = {
		id = "GOLDEN",
		layers = {
			{
				type = "Emitter", name = "GoldDust", target = "Volume", quality = "Low",
				props = {
					Texture = TEX.Sparkle, Rate = 7, Lifetime = NumberRange.new(1.6, 2.4), Speed = NumberRange.new(0.5, 1.3),
					Acceleration = Vector3.new(0, 1.6, 0), SpreadAngle = Vector2.new(25, 25),
					Size = ns({ { 0, 0 }, { 0.2, 0.28 }, { 1, 0.06 } }), Transparency = ns({ { 0, 0.1 }, { 0.7, 0.3 }, { 1, 1 } }),
					Color = cs({ rgb(255, 240, 170), rgb(255, 196, 40), rgb(230, 140, 20) }),
					LightEmission = 0.7, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-40, 40),
				},
			},
			{
				type = "Emitter", name = "GoldGlint", target = "Volume", quality = "Medium",
				props = {
					Texture = TEX.Sparkle, Rate = 1.6, Lifetime = NumberRange.new(0.4, 0.65), Speed = NumberRange.new(0, 0),
					Size = ns({ { 0, 0 }, { 0.4, 1.1 }, { 1, 0 } }), Transparency = ns({ { 0, 0.2 }, { 1, 0.6 } }),
					Color = cs({ rgb(255, 255, 235) }), LightEmission = 1, Rotation = NumberRange.new(0, 360), ZOffset = 1,
				},
			},
			{ type = "GroundRing", quality = "Low", color = rgb(255, 200, 50), radius = 1.3, transparency = 0.55, pulse = 0.12, pulseSpeed = 1.4 },
			{ type = "Orbit", quality = "Medium", shape = "Coin", count = { Medium = 3, High = 5 }, radius = 1.4, height = 0.5, speed = 0.75, bob = 0.18, tilt = 0, color = rgb(255, 200, 50), size = 0.55 },
			{ type = "Highlight", quality = "Medium", outline = rgb(255, 214, 90), fill = rgb(255, 200, 50), fillTransparency = 0.88, outlineTransparency = 0.25 },
			{ type = "Light", quality = "High", color = rgb(255, 205, 90), brightness = 0.9, range = 4.5, pulse = 0.15, pulseSpeed = 0.8 },
		},
	},

	ELECTRIC = {
		id = "ELECTRIC",
		layers = {
			{
				type = "Emitter", name = "Sparks", target = "Volume", quality = "Low",
				props = {
					Texture = TEX.Sparkle, Rate = 9, Lifetime = NumberRange.new(0.18, 0.4), Speed = NumberRange.new(4, 9),
					Drag = 4, SpreadAngle = Vector2.new(180, 180),
					Size = ns({ { 0, 0.22 }, { 1, 0 } }), Transparency = ns({ { 0, 0 }, { 1, 0.6 } }),
					Color = cs({ rgb(230, 250, 255), rgb(70, 220, 255), rgb(150, 90, 255) }), LightEmission = 1,
				},
			},
			{
				type = "Emitter", name = "Pulse", target = "AuraAnchor", quality = "Medium",
				props = {
					Texture = TEX.Sparkle, Rate = 0.8, Lifetime = NumberRange.new(0.55, 0.7), Speed = NumberRange.new(0, 0),
					Size = ns({ { 0, 0.6 }, { 1, 4.2 } }), Transparency = ns({ { 0, 0.55 }, { 1, 1 } }),
					Color = cs({ rgb(90, 230, 255), rgb(150, 90, 255) }), LightEmission = 1, LockedToPart = true, ZOffset = -1,
				},
				scaleSize = true,
			},
			{
				type = "Emitter", name = "GroundZap", target = "Ground", quality = "Medium",
				props = {
					Texture = TEX.Sparkle, Rate = 1.4, Lifetime = NumberRange.new(0.2, 0.35), Speed = NumberRange.new(5, 9),
					SpreadAngle = Vector2.new(85, 85), Drag = 5,
					Size = ns({ { 0, 0.3 }, { 1, 0 } }), Color = cs({ rgb(200, 245, 255), rgb(120, 110, 255) }), LightEmission = 1,
				},
			},
			{ type = "Arc", quality = "Medium", count = { Medium = 1, High = 2 }, interval = { 0.55, 1.5 }, duration = { 0.1, 0.16 }, jitter = 0.45, width = 0.14, colors = { rgb(120, 235, 255), rgb(170, 110, 255) }, sound = "ElectricZap" },
			{ type = "GroundRing", quality = "Low", color = rgb(80, 150, 255), radius = 1.25, transparency = 0.6, pulse = 0.2, pulseSpeed = 2.2 },
			{ type = "Highlight", quality = "Medium", outline = rgb(90, 230, 255), fill = rgb(90, 140, 255), fillTransparency = 0.9, outlineTransparency = 0.15 },
			{ type = "Light", quality = "High", color = rgb(110, 210, 255), brightness = 1, range = 4.5, pulse = 0.2, pulseSpeed = 1.6 },
		},
	},

	COSMIC = {
		id = "COSMIC",
		layers = {
			{
				type = "Emitter", name = "Stars", target = "Volume", quality = "Low",
				props = {
					Texture = TEX.Sparkle, Rate = 8, Lifetime = NumberRange.new(1.5, 2.6), Speed = NumberRange.new(0.15, 0.6),
					SpreadAngle = Vector2.new(180, 180),
					Size = ns({ { 0, 0 }, { 0.2, 0.34 }, { 0.5, 0.12 }, { 0.8, 0.36 }, { 1, 0 } }),
					Color = cs({ rgb(255, 255, 255), rgb(140, 240, 255), rgb(255, 130, 230) }), LightEmission = 1,
					Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-60, 60),
				},
			},
			{
				type = "Emitter", name = "Nebula", target = "Volume", quality = "Medium",
				props = {
					Texture = TEX.Smoke, Rate = 2.2, Lifetime = NumberRange.new(2, 3), Speed = NumberRange.new(0.1, 0.4),
					SpreadAngle = Vector2.new(180, 180),
					Size = ns({ { 0, 1.6 }, { 1, 3.2 } }), Transparency = ns({ { 0, 1 }, { 0.25, 0.82 }, { 0.7, 0.9 }, { 1, 1 } }),
					Color = cs({ rgb(120, 60, 220), rgb(60, 110, 255), rgb(255, 90, 210) }), LightEmission = 0.45,
					Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-15, 15), ZOffset = -1.5,
				},
				scaleSize = true,
			},
			{ type = "Ring", quality = "Medium", radius = 1.55, tilt = 28, tiltAxis = "X", speed = 0.9, width = 0.16, colors = { rgb(255, 120, 230), rgb(150, 110, 255) }, height = 0.5 },
			{ type = "Ring", quality = "High", radius = 1.9, tilt = -40, tiltAxis = "Z", speed = -0.55, width = 0.1, colors = { rgb(130, 240, 255), rgb(90, 120, 255) }, height = 0.55 },
			{ type = "Orbit", quality = "Medium", shape = "Planet", count = { Medium = 2, High = 4 }, radius = 1.75, height = 0.55, speed = 0.6, speedVariance = 0.5, bob = 0.3, tilt = 18, color = rgb(140, 240, 255), size = 0.5 },
			{ type = "GroundRing", quality = "Low", color = rgb(150, 80, 255), radius = 1.4, transparency = 0.5, pulse = 0.15, pulseSpeed = 0.9, inner = rgb(255, 120, 230) },
			{ type = "Highlight", quality = "Medium", outline = rgb(220, 140, 255), fill = rgb(90, 40, 200), fillTransparency = 0.82, outlineTransparency = 0.1 },
			{ type = "Light", quality = "High", color = rgb(190, 120, 255), brightness = 1.1, range = 5, pulse = 0.25, pulseSpeed = 0.6 },
		},
	},

	-- Aura exclusiva de la rareza SECRET (se combina con la de la mutación).
	SECRET = {
		id = "SECRET",
		layers = {
			{
				type = "Emitter", name = "Fragments", target = "Volume", quality = "Low",
				props = {
					Texture = TEX.Sparkle, Rate = 5, Lifetime = NumberRange.new(0.5, 1), Speed = NumberRange.new(1, 2.5),
					SpreadAngle = Vector2.new(180, 180), Drag = 1,
					Size = ns({ { 0, 0.3 }, { 0.8, 0.3 }, { 1, 0 } }),
					Color = cs({ rgb(255, 70, 160), rgb(80, 255, 240), rgb(255, 255, 255) }), LightEmission = 0.9,
					Rotation = NumberRange.new(0, 0),
				},
			},
			{
				type = "Emitter", name = "VoidWisps", target = "Ground", quality = "Medium",
				props = {
					Texture = TEX.Smoke, Rate = 2, Lifetime = NumberRange.new(1.2, 1.8), Speed = NumberRange.new(1, 2),
					SpreadAngle = Vector2.new(20, 20), Acceleration = Vector3.new(0, 1, 0),
					Size = ns({ { 0, 0.8 }, { 1, 2 } }), Transparency = ns({ { 0, 1 }, { 0.2, 0.75 }, { 1, 1 } }),
					Color = cs({ rgb(40, 10, 60), rgb(255, 70, 160) }), LightEmission = 0.2, ZOffset = -1,
				},
				scaleSize = true,
			},
			{ type = "Ring", quality = "Medium", radius = 1.35, tilt = 90, tiltAxis = "X", speed = 1.6, width = 0.12, colors = { rgb(255, 255, 255), rgb(255, 70, 160) }, height = 0.5 },
			{ type = "Orbit", quality = "Medium", shape = "Cube", count = { Medium = 3, High = 6 }, radius = 1.55, height = 0.75, speed = -0.9, speedVariance = 0.3, bob = 0.5, tilt = 0, color = rgb(255, 70, 160), altColor = rgb(20, 20, 24), size = 0.42 },
			{ type = "Glitch", quality = "Medium", interval = { 1.4, 3.2 }, duration = 0.12, amplitude = 0.22 },
			{ type = "GroundRing", quality = "Low", color = rgb(255, 70, 160), radius = 1.55, transparency = 0.45, pulse = 0.2, pulseSpeed = 1.1, inner = rgb(80, 255, 240) },
			{ type = "Highlight", quality = "Low", outline = rgb(255, 80, 170), fill = rgb(0, 0, 0), fillTransparency = 0.92, outlineTransparency = 0 },
			{ type = "Light", quality = "High", color = rgb(255, 90, 170), brightness = 1, range = 5, pulse = 0.3, pulseSpeed = 0.7 },
		},
	},

	-- Brillo sutil para Legendary (no es mutación).
	LEGENDARY = {
		id = "LEGENDARY",
		layers = {
			{
				type = "Emitter", name = "Shimmer", target = "Volume", quality = "Medium",
				props = {
					Texture = TEX.Sparkle, Rate = 2, Lifetime = NumberRange.new(0.8, 1.2), Speed = NumberRange.new(0.2, 0.6),
					Size = ns({ { 0, 0 }, { 0.5, 0.3 }, { 1, 0 } }), Color = cs({ rgb(255, 220, 140) }), LightEmission = 1,
				},
			},
			{ type = "GroundRing", quality = "Low", color = rgb(255, 176, 46), radius = 1.15, transparency = 0.7, pulse = 0.1, pulseSpeed = 1 },
		},
	},
}

-- Aura extra por rareza (además de la aura de la mutación).
VFXConfig.RarityAuras = {
	Legendary = "LEGENDARY",
	Secret = "SECRET",
}

---------------------------------------------------------------------------------------------
-- Efectos puntuales (one-shots)
-- burst.at: "Mouth" | "Center" | "Ground" | "Top" | "Head"
-- ring: onda expansiva en el suelo (radios en múltiplos del radio del objetivo)
-- flash: un único fundido de luz (nunca estroboscópico)
-- pop: pulso de escala de la criatura (1.1 = +10%)
---------------------------------------------------------------------------------------------
local function burst(at, count, props, quality)
	return { at = at, count = count, props = props, quality = quality or "Low" }
end

local crumbs = function(c1, c2)
	return {
		Texture = TEX.Sparkle, Lifetime = NumberRange.new(0.35, 0.7), Speed = NumberRange.new(5, 10), SpreadAngle = Vector2.new(55, 55),
		Acceleration = Vector3.new(0, -28, 0), Size = ns({ { 0, 0.3 }, { 1, 0.05 } }), Color = cs({ c1, c2 }),
		LightEmission = 0.2, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-200, 200),
	}
end

local sparkleBurst = function(colors, speedMin, speedMax, size, life)
	return {
		Texture = TEX.Sparkle, Lifetime = NumberRange.new(life * 0.6, life), Speed = NumberRange.new(speedMin, speedMax),
		SpreadAngle = Vector2.new(180, 180), Drag = 3, Size = ns({ { 0, size }, { 0.3, size * 1.2 }, { 1, 0 } }),
		Color = cs(colors), LightEmission = 1, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-90, 90),
	}
end

local riseBurst = function(colors, size, life)
	return {
		Texture = TEX.Sparkle, Lifetime = NumberRange.new(life * 0.7, life), Speed = NumberRange.new(3, 7),
		SpreadAngle = Vector2.new(30, 30), Acceleration = Vector3.new(0, 4, 0), Drag = 1.5,
		Size = ns({ { 0, 0 }, { 0.2, size }, { 1, 0 } }), Color = cs(colors), LightEmission = 0.9,
	}
end

local smokePuff = function(colors, size)
	return {
		Texture = TEX.Smoke, Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(3, 7), SpreadAngle = Vector2.new(180, 180),
		Drag = 4, Size = ns({ { 0, size * 0.5 }, { 1, size } }), Transparency = ns({ { 0, 0.35 }, { 1, 1 } }),
		Color = cs(colors), LightEmission = 0.1, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-60, 60),
	}
end

local GOLD = { rgb(255, 250, 200), rgb(255, 200, 50), rgb(230, 140, 20) }
local ELEC = { rgb(235, 250, 255), rgb(70, 220, 255), rgb(150, 90, 255) }
local COSM = { rgb(255, 255, 255), rgb(255, 120, 230), rgb(110, 90, 255) }
local SECR = { rgb(255, 255, 255), rgb(255, 70, 160), rgb(80, 255, 240) }

VFXConfig.Effects = {
	PickupFood = { priority = 1, maxDistance = 80, bursts = { burst("Center", 8, sparkleBurst({ rgb(255, 255, 255), rgb(255, 230, 140) }, 3, 7, 0.3, 0.5)) }, sound = "PickupFood" },

	-- Alimentación según el tipo de comida (FoodConfig.vfx)
	FeedCrumbs = { priority = 2, maxDistance = 110, pop = 1.07, bursts = { burst("Mouth", 14, crumbs(rgb(240, 200, 130), rgb(170, 110, 60))) }, sound = "Eat" },
	FeedJuice = { priority = 2, maxDistance = 110, pop = 1.07, bursts = { burst("Mouth", 14, crumbs(rgb(255, 120, 140), rgb(200, 40, 80))) }, sound = "Eat" },
	FeedSparkle = { priority = 2, maxDistance = 110, pop = 1.08, bursts = { burst("Mouth", 10, crumbs(rgb(255, 220, 240), rgb(255, 150, 200))), burst("Mouth", 8, sparkleBurst({ rgb(255, 255, 255), rgb(255, 180, 230) }, 3, 6, 0.35, 0.6), "Medium") }, sound = "Eat" },
	FeedGold = { priority = 2, maxDistance = 120, pop = 1.1, bursts = { burst("Mouth", 16, sparkleBurst(GOLD, 4, 9, 0.4, 0.7)) }, flash = { color = rgb(255, 210, 100), brightness = 1.2, range = 3.5, time = 0.45 }, sound = "Eat" },
	FeedCosmic = { priority = 2, maxDistance = 120, pop = 1.1, bursts = { burst("Mouth", 16, sparkleBurst(COSM, 4, 9, 0.4, 0.8)) }, flash = { color = rgb(200, 130, 255), brightness = 1.2, range = 3.5, time = 0.5 }, sound = "Eat" },
	FirstFeed = { priority = 3, maxDistance = 120, pop = 1.15, bursts = { burst("Top", 24, sparkleBurst({ rgb(255, 255, 255), rgb(120, 255, 160), rgb(255, 230, 120) }, 5, 11, 0.45, 0.9)) }, ring = { color = rgb(120, 255, 160), from = 0.6, to = 3, time = 0.5 }, sound = "Grow" },

	-- Extra al alimentar una criatura mutada
	FeedGolden = { priority = 1, maxDistance = 90, quality = "Medium", bursts = { burst("Center", 10, riseBurst(GOLD, 0.35, 0.9)) }, flash = { color = rgb(255, 210, 100), brightness = 1, range = 3.5, time = 0.4 } },
	FeedElectric = { priority = 1, maxDistance = 90, quality = "Medium", bursts = { burst("Mouth", 16, sparkleBurst(ELEC, 8, 16, 0.25, 0.3)) } },
	FeedCosmic2 = { priority = 1, maxDistance = 90, quality = "Medium", bursts = { burst("Center", 12, sparkleBurst(COSM, 2, 5, 0.4, 1)) } },

	-- Crecimiento (subida de nivel)
	Grow = { priority = 2, maxDistance = 120, pop = 1.14, bursts = { burst("Ground", 14, riseBurst({ rgb(255, 255, 255), rgb(140, 255, 170) }, 0.4, 0.8)) }, ring = { color = rgb(140, 255, 170), from = 0.7, to = 2.4, time = 0.45 }, sound = "Grow" },
	GrowGolden = { priority = 2, maxDistance = 120, pop = 1.16, bursts = { burst("Ground", 18, riseBurst(GOLD, 0.45, 1)) }, ring = { color = rgb(255, 200, 50), from = 0.7, to = 2.8, time = 0.5 }, sound = "Grow" },
	GrowElectric = { priority = 2, maxDistance = 120, pop = 1.16, bursts = { burst("Center", 22, sparkleBurst(ELEC, 9, 18, 0.3, 0.35)) }, ring = { color = rgb(90, 230, 255), from = 0.7, to = 2.8, time = 0.35 }, flash = { color = rgb(120, 220, 255), brightness = 1.3, range = 4, time = 0.4 }, sound = "Grow" },
	GrowCosmic = { priority = 2, maxDistance = 120, pop = 1.18, bursts = { burst("Center", 22, sparkleBurst(COSM, 3, 8, 0.45, 1.2)), burst("Ground", 6, smokePuff({ rgb(120, 60, 220), rgb(255, 90, 210) }, 3), "Medium") }, ring = { color = rgb(200, 120, 255), from = 0.7, to = 3.2, time = 0.6 }, sound = "Grow" },

	-- Transformaciones de mutación
	MutationGolden = {
		priority = 3, maxDistance = 160, pop = 1.25, announce = true,
		bursts = { burst("Center", 40, sparkleBurst(GOLD, 6, 16, 0.55, 1.2)), burst("Ground", 20, riseBurst(GOLD, 0.5, 1.4), "Medium") },
		ring = { color = rgb(255, 200, 50), from = 0.5, to = 4.5, time = 0.7 }, flash = { color = rgb(255, 215, 110), brightness = 1.6, range = 6, time = 0.8 }, sound = "MutationGolden",
	},
	MutationElectric = {
		priority = 3, maxDistance = 160, pop = 1.25, announce = true,
		bursts = { burst("Center", 46, sparkleBurst(ELEC, 12, 26, 0.35, 0.5)), burst("Ground", 16, sparkleBurst(ELEC, 6, 12, 0.3, 0.4), "Medium") },
		ring = { color = rgb(90, 230, 255), from = 0.5, to = 4.5, time = 0.45 }, flash = { color = rgb(130, 225, 255), brightness = 1.6, range = 6, time = 0.7 }, sound = "MutationElectric",
	},
	MutationCosmic = {
		priority = 3, maxDistance = 180, pop = 1.3, announce = true,
		bursts = { burst("Center", 50, sparkleBurst(COSM, 4, 14, 0.6, 1.8)), burst("Center", 10, smokePuff({ rgb(120, 60, 220), rgb(60, 110, 255), rgb(255, 90, 210) }, 5), "Medium"), burst("Top", 16, riseBurst(COSM, 0.5, 1.6), "Medium") },
		ring = { color = rgb(200, 120, 255), from = 0.5, to = 5.5, time = 0.9 }, flash = { color = rgb(200, 140, 255), brightness = 1.7, range = 6.5, time = 1 }, sound = "MutationCosmic",
	},

	-- Aparición / descubrimiento
	Spawn = { priority = 2, maxDistance = 120, pop = 1.2, bursts = { burst("Center", 14, smokePuff({ rgb(255, 255, 255), rgb(220, 220, 230) }, 3)), burst("Center", 12, sparkleBurst({ rgb(255, 255, 255), rgb(255, 240, 180) }, 4, 9, 0.35, 0.6), "Medium") }, sound = "Hatch" },
	RareFind = { priority = 3, maxDistance = 160, pop = 1.2, bursts = { burst("Center", 30, sparkleBurst({ rgb(255, 255, 255), rgb(255, 200, 90), rgb(190, 110, 255) }, 6, 14, 0.5, 1.1)) }, ring = { color = rgb(255, 200, 90), from = 0.5, to = 4, time = 0.6 }, sound = "RareFind" },
	SecretReveal = {
		priority = 3, maxDistance = 220, pop = 1.3, announce = true,
		bursts = { burst("Center", 12, smokePuff({ rgb(20, 10, 30), rgb(255, 70, 160) }, 6)), burst("Center", 50, sparkleBurst(SECR, 5, 18, 0.55, 1.6)), burst("Top", 18, riseBurst(SECR, 0.5, 1.8), "Medium") },
		ring = { color = rgb(255, 70, 160), from = 0.5, to = 6, time = 1 }, flash = { color = rgb(255, 110, 180), brightness = 1.6, range = 7, time = 1.1 }, sound = "SecretReveal",
	},

	-- Economía / social
	CoinCollect = { priority = 1, maxDistance = 70, bursts = { burst("Center", 12, riseBurst(GOLD, 0.4, 0.8)) }, sound = "Coins" },
	Purchase = { priority = 2, maxDistance = 60, bursts = { burst("Center", 16, sparkleBurst({ rgb(255, 255, 255), rgb(140, 255, 170) }, 4, 9, 0.35, 0.7)) }, sound = "Purchase" },
	StealSuccess = { priority = 3, maxDistance = 140, bursts = { burst("Center", 20, sparkleBurst({ rgb(255, 255, 255), rgb(255, 90, 90) }, 6, 14, 0.4, 0.5)), burst("Center", 6, smokePuff({ rgb(255, 120, 120), rgb(120, 30, 30) }, 3), "Medium") }, ring = { color = rgb(255, 90, 90), from = 0.5, to = 3, time = 0.35 }, sound = "Steal" },
	Recover = { priority = 3, maxDistance = 140, bursts = { burst("Center", 20, sparkleBurst({ rgb(255, 255, 255), rgb(110, 200, 255) }, 6, 14, 0.4, 0.5)) }, ring = { color = rgb(110, 200, 255), from = 0.5, to = 3, time = 0.35 }, sound = "Recover" },
	CrateDeliver = { priority = 2, maxDistance = 120, bursts = { burst("Center", 26, riseBurst(GOLD, 0.5, 1.1)), burst("Center", 8, smokePuff({ rgb(255, 240, 200), rgb(200, 160, 90) }, 3), "Medium") }, ring = { color = rgb(255, 220, 120), from = 0.5, to = 3.5, time = 0.5 }, sound = "Deliver" },
	EventStart = { priority = 3, maxDistance = 400, bursts = { burst("Center", 40, riseBurst({ rgb(255, 255, 255), rgb(255, 220, 120), rgb(255, 120, 120) }, 0.8, 2)) }, ring = { color = rgb(255, 255, 255), from = 1, to = 10, time = 1.2 }, sound = "EventStart" },
	Rebirth = {
		priority = 3, maxDistance = 200, announce = true,
		bursts = { burst("Ground", 40, riseBurst({ rgb(255, 255, 255), rgb(255, 150, 80), rgb(255, 70, 160) }, 0.7, 2)), burst("Center", 30, sparkleBurst({ rgb(255, 255, 255), rgb(255, 180, 90) }, 6, 18, 0.5, 1.2)) },
		ring = { color = rgb(255, 170, 90), from = 0.5, to = 8, time = 1 }, flash = { color = rgb(255, 190, 120), brightness = 1.6, range = 8, time = 1 }, sound = "Rebirth",
	},
	Evolve = {
		priority = 3, maxDistance = 180, pop = 1.28, announce = true,
		bursts = { burst("Ground", 30, riseBurst({ rgb(255, 255, 255), rgb(140, 255, 200), rgb(255, 230, 120) }, 0.6, 1.6)), burst("Center", 24, sparkleBurst({ rgb(255, 255, 255), rgb(255, 230, 120) }, 6, 15, 0.5, 1.1), "Medium") },
		ring = { color = rgb(140, 255, 200), from = 0.5, to = 5, time = 0.8 }, flash = { color = rgb(200, 255, 220), brightness = 1.5, range = 6, time = 0.9 }, sound = "RareFind",
	},
	GiantBite = { priority = 2, maxDistance = 250, pop = 1.03, bursts = { burst("Mouth", 18, crumbs(rgb(255, 220, 150), rgb(220, 90, 60))) }, sound = "Eat" },
}

-- Efecto de alimentación extra por mutación (además del de la comida).
VFXConfig.MutationFeedEffects = { GOLDEN = "FeedGolden", ELECTRIC = "FeedElectric", COSMIC = "FeedCosmic2" }
VFXConfig.MutationGrowEffects = { NORMAL = "Grow", GOLDEN = "GrowGolden", ELECTRIC = "GrowElectric", COSMIC = "GrowCosmic" }
VFXConfig.MutationTransformEffects = { GOLDEN = "MutationGolden", ELECTRIC = "MutationElectric", COSMIC = "MutationCosmic" }
VFXConfig.FoodFeedEffects = { Crumbs = "FeedCrumbs", Juice = "FeedJuice", Sparkle = "FeedSparkle", Gold = "FeedGold", Cosmic = "FeedCosmic" }

---------------------------------------------------------------------------------------------
-- Utilidades puras (también las usan los tests)
---------------------------------------------------------------------------------------------
function VFXConfig.qualityRank(q)
	local def = VFXConfig.Quality[q]
	return def and def.rank or 0
end

function VFXConfig.layerEnabled(layer, quality)
	return VFXConfig.qualityRank(quality) >= VFXConfig.qualityRank(layer.quality or "Low")
end

-- Devuelve la cantidad (orbitadores/arcos) para una calidad dada.
function VFXConfig.countFor(layer, quality)
	local c = layer.count
	if type(c) == "number" then
		return c
	elseif type(c) == "table" then
		return c[quality] or 0
	end
	return 1
end

-- Partículas vivas estimadas de un emisor: rate * lifetime máximo.
function VFXConfig.estimateParticles(props, rateScale)
	local life = props.Lifetime and props.Lifetime.Max or 1
	return (props.Rate or 0) * (rateScale or 1) * life
end

-- Calcula el factor de escala de Rate que hay que aplicar a una lista de auras para respetar
-- el presupuesto de partículas de la calidad. Devuelve (factor, estimadoFinal).
function VFXConfig.rateScaleFor(auraIds, quality)
	local q = VFXConfig.Quality[quality]
	local total = 0
	for _, auraId in ipairs(auraIds) do
		local aura = VFXConfig.Auras[auraId]
		if aura then
			for _, layer in ipairs(aura.layers) do
				if layer.type == "Emitter" and VFXConfig.layerEnabled(layer, quality) then
					total += VFXConfig.estimateParticles(layer.props, q.particleScale)
				end
			end
		end
	end
	local factor = q.particleScale
	if total > q.maxAuraParticles and total > 0 then
		factor = factor * (q.maxAuraParticles / total)
		total = q.maxAuraParticles
	end
	return factor, total
end

function VFXConfig.aurasFor(mutationAura, rarity)
	local list = {}
	if mutationAura and VFXConfig.Auras[mutationAura] then
		table.insert(list, mutationAura)
	end
	local rarityAura = VFXConfig.RarityAuras[rarity]
	if rarityAura and VFXConfig.Auras[rarityAura] then
		table.insert(list, rarityAura)
	end
	return list
end

return VFXConfig
