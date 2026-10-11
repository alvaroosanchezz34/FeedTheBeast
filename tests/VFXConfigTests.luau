--!nocheck
-- Efectos visuales: integridad de la configuración, límites de rendimiento, criaturas x
-- mutaciones y limpieza. Comprueban estructura y presupuestos, NO el resultado artístico
-- (eso se revisa en Roblox Studio: docs/STUDIO_CHECKLIST.md).
local fs = require("@lune/fs")
local TestKit = require("./lib/TestKit")
local Fixtures = require("./lib/Fixtures")
local Harness = require("./lib/Harness")
local expect = TestKit.expect
local test = TestKit.test

return function()
	TestKit.suite("VFX: configuración")

	local function config()
		local h = Fixtures.server()
		return Fixtures.config(h, "VFXConfig"), h
	end

	test("no hay ningún ID de asset externo en el código (solo recursos del motor)", function()
		local found = {}
		local function scan(dir)
			for _, name in ipairs(fs.readDir(dir)) do
				local path = dir .. "/" .. name
				if fs.isDir(path) then
					scan(path)
				elseif string.match(name, "%.lua$") then
					local source = fs.readFile(path)
					for id in string.gmatch(source, "rbxassetid://%d+") do
						table.insert(found, path .. ": " .. id)
					end
					for id in string.gmatch(source, "roblox%.com/asset/%?id=%d+") do
						table.insert(found, path .. ": " .. id)
					end
				end
			end
		end
		scan("src")
		expect.equal(#found, 0, "IDs encontrados: " .. table.concat(found, ", "))
		local VFX = config()
		for name, texture in pairs(VFX.Textures) do
			expect.truthy(string.match(texture, "^rbxasset://textures/"), name .. " debe ser un recurso del motor")
		end
	end)

	test("audio: ningún ID inventado; las reservas son rutas del motor y se pueden apagar", function()
		local h = Fixtures.server()
		local Audio = Fixtures.config(h, "AudioConfig")
		for name, def in pairs(Audio.Sounds) do
			expect.equal(def.id, "", name .. " no debe tener id hasta que se asigne uno real")
			if def.fallback then
				expect.truthy(string.match(def.fallback, "^rbxasset://sounds/"), name .. " reserva del motor")
			end
			expect.greater(def.maxPerSecond or 0, 0, name .. " con límite de frecuencia")
		end
		for name, def in pairs(Audio.Music) do
			expect.equal(def.id, "", "música " .. name)
		end
	end)

	test("cada mutación tiene aura, efectos de transformación/crecimiento y aspecto propios", function()
		local VFX, h = config()
		local Mutations = Fixtures.config(h, "MutationConfig")
		expect.equal(#Mutations.Order, 4)
		local seenColors = {}
		for _, id in ipairs(Mutations.Order) do
			local def = Mutations.Mutations[id]
			expect.truthy(VFX.Effects[VFX.MutationGrowEffects[id]], id .. " efecto de crecimiento")
			if id ~= "NORMAL" then
				expect.truthy(VFX.Auras[def.aura], id .. " aura")
				expect.truthy(VFX.Effects[VFX.MutationTransformEffects[id]], id .. " transformación")
				expect.truthy(VFX.Effects[VFX.MutationFeedEffects[id]], id .. " efecto al comer")
				expect.truthy(VFX.Effects[def.transformEffect], id .. " transformEffect")
				expect.truthy(def.visual.Body and def.visual.Belly and def.visual.Accent and def.visual.Detail, id .. " materiales por rol")
				expect.truthy(def.incomeMult > 1, id .. " bonificación")
				local key = tostring(def.visual.Body.color)
				expect.falsy(seenColors[key], id .. " comparte color de cuerpo con " .. tostring(seenColors[key]))
				seenColors[key] = id
			end
		end
		-- Las auras se distinguen por estructura, no solo por color: capas características.
		local function has(auraId, layerType, shape)
			for _, layer in ipairs(VFX.Auras[auraId].layers) do
				if layer.type == layerType and (shape == nil or layer.shape == shape) then
					return true
				end
			end
			return false
		end
		expect.truthy(has("GOLDEN", "Orbit", "Coin"), "GOLDEN: monedas orbitando")
		expect.truthy(has("GOLDEN", "GroundRing"), "GOLDEN: halo en el suelo")
		expect.truthy(has("ELECTRIC", "Arc"), "ELECTRIC: arcos")
		expect.falsy(has("GOLDEN", "Arc") or has("COSMIC", "Arc"), "los arcos son exclusivos de ELECTRIC")
		expect.truthy(has("COSMIC", "Ring"), "COSMIC: anillos")
		expect.truthy(has("COSMIC", "Orbit", "Planet"), "COSMIC: planetas")
		expect.truthy(has("SECRET", "Glitch"), "SECRET: glitch")
		expect.truthy(has("SECRET", "Orbit", "Cube"), "SECRET: fragmentos")
		-- COSMIC es la más rica visualmente.
		expect.greater(#VFX.Auras.COSMIC.layers, #VFX.Auras.GOLDEN.layers)
		expect.equal(VFX.RarityAuras.Secret, "SECRET")
	end)

	test("todas las referencias entre tablas de efectos existen", function()
		local VFX, h = config()
		local Audio = Fixtures.config(h, "AudioConfig")
		local Foods = Fixtures.config(h, "FoodConfig")
		for group, map in pairs({ feed = VFX.MutationFeedEffects, grow = VFX.MutationGrowEffects, transform = VFX.MutationTransformEffects, food = VFX.FoodFeedEffects }) do
			for key, effectId in pairs(map) do
				expect.truthy(VFX.Effects[effectId], group .. "." .. key .. " -> " .. effectId)
			end
		end
		for _, foodId in ipairs(Foods.Order) do
			expect.truthy(VFX.FoodFeedEffects[Foods.Foods[foodId].vfx], foodId .. " vfx " .. tostring(Foods.Foods[foodId].vfx))
		end
		local anchors = { Mouth = true, Center = true, Ground = true, Top = true, Head = true }
		for effectId, def in pairs(VFX.Effects) do
			if def.sound then
				expect.truthy(Audio.Sounds[def.sound], effectId .. " sonido " .. def.sound)
			end
			expect.truthy(def.maxDistance and def.maxDistance > 0, effectId .. " distancia máxima")
			for _, burst in ipairs(def.bursts or {}) do
				expect.truthy(anchors[burst.at], effectId .. " anclaje " .. tostring(burst.at))
				expect.truthy(burst.count > 0 and burst.count <= 60, effectId .. " partículas por ráfaga")
				expect.atMost(burst.props.Lifetime.Max, VFX.Limits.OneShotMaxLifetime, effectId .. " duración")
			end
		end
		for auraId, aura in pairs(VFX.Auras) do
			for _, layer in ipairs(aura.layers) do
				expect.truthy(VFX.Quality[layer.quality or "Low"], auraId .. " calidad de capa")
				if layer.sound then
					expect.truthy(Audio.Sounds[layer.sound], auraId .. " sonido")
				end
			end
		end
	end)

	test("presupuesto de partículas por aura en cada calidad (incluida la combinación con SECRET)", function()
		local VFX = config()
		for _, quality in ipairs(VFX.QualityOrder) do
			local q = VFX.Quality[quality]
			for _, combo in ipairs({ { "GOLDEN" }, { "ELECTRIC" }, { "COSMIC" }, { "SECRET" }, { "COSMIC", "SECRET" }, { "GOLDEN", "LEGENDARY" } }) do
				local factor, total = VFX.rateScaleFor(combo, quality)
				expect.atMost(total, q.maxAuraParticles + 1e-6, quality .. " " .. table.concat(combo, "+"))
				expect.truthy(factor > 0 and factor <= 1, "factor")
			end
		end
		-- Las calidades están ordenadas de verdad: cada nivel permite menos que el siguiente.
		local low, medium, high = VFX.Quality.Low, VFX.Quality.Medium, VFX.Quality.High
		for _, key in ipairs({ "maxAuraParticles", "maxActiveAuras", "auraDistance", "maxOneShots", "maxLights", "burstScale" }) do
			expect.truthy(low[key] <= medium[key] and medium[key] <= high[key], key .. " monótono")
		end
		expect.equal(low.maxLights, 0, "Low: sin luces dinámicas")
		expect.falsy(low.orbiters or low.arcs or low.rings, "Low: solo lo esencial")
	end)

	test("seguridad visual: sin destellos rápidos ni parpadeos", function()
		local VFX = config()
		for effectId, def in pairs(VFX.Effects) do
			if def.flash then
				expect.truthy(def.flash.time >= 0.35, effectId .. ": el destello es un fundido lento")
				expect.atMost(def.flash.brightness, 2, effectId .. " brillo")
			end
		end
		for auraId, aura in pairs(VFX.Auras) do
			for _, layer in ipairs(aura.layers) do
				if layer.type == "Arc" or layer.type == "Glitch" then
					-- Como mucho ~2 por segundo.
					expect.truthy(layer.interval[1] >= 0.5, auraId .. " " .. layer.type .. " intervalo mínimo")
				end
				if layer.type == "Light" then
					expect.atMost(layer.pulse or 0, 0.35, auraId .. " luz: variación suave")
					expect.atMost(layer.pulseSpeed or 0, 3.2, auraId .. " luz: lenta (rad/s)")
				end
				if layer.type == "GroundRing" and layer.pulse then
					expect.atMost(layer.pulseSpeed, 6.3, auraId .. " anillo: < 1 Hz")
				end
			end
		end
	end)

	TestKit.suite("VFX: criaturas")

	test("las 6 especies se construyen con todos los anclajes, articulaciones y animaciones", function()
		local h = Fixtures.server()
		local Builder = h:require("ReplicatedStorage.Shared.Creatures.CreatureBuilder")
		local Kit = h:require("ReplicatedStorage.Shared.Creatures.Kit")
		local CreatureConfig = Fixtures.config(h, "CreatureConfig")
		expect.equal(#CreatureConfig.Order, 6)
		local signatures = {}
		for _, speciesId in ipairs(CreatureConfig.Order) do
			local species = CreatureConfig.Species[speciesId]
			local visual = Builder.build(speciesId)
			expect.truthy(visual, speciesId)
			for _, anchor in ipairs(Kit.RequiredAnchors) do
				expect.truthy(visual.anchors[anchor], speciesId .. " anclaje " .. anchor)
			end
			expect.truthy(visual.joints.Body, speciesId .. " articulación Body")
			expect.truthy(visual.joints.Jaw, speciesId .. " mandíbula (animación de comer)")
			expect.equal(type(visual.species.idle), "function", speciesId .. " idle")
			expect.equal(type(visual.species.eat), "function", speciesId .. " eat")
			-- Cara reconocible: al menos un ojo, y partes de varios roles (no es un bloque liso).
			local roles, parts = {}, 0
			for _, record in ipairs(visual.records) do
				parts += 1
				if record.role then
					roles[record.role] = (roles[record.role] or 0) + 1
				end
			end
			expect.greater(roles.Eye or 0, 0, speciesId .. " ojos")
			expect.greater(roles.Teeth or 0, 0, speciesId .. " dientes")
			for _, role in ipairs({ "Body", "Accent", "Detail" }) do
				expect.greater(roles[role] or 0, 0, speciesId .. " rol " .. role)
			end
			expect.greater(parts, 20, speciesId .. " nivel de detalle")
			expect.atMost(parts, 90, speciesId .. " presupuesto de piezas")
			-- La boca está por delante (frente = -Z) y por encima del suelo; la cima es lo más alto.
			local mouth = visual:anchorWorld("Mouth")
			expect.truthy(mouth.Z < -0.5, speciesId .. " boca al frente")
			expect.greater(mouth.Y, 0.5, speciesId .. " boca sobre el suelo")
			expect.greater(visual:anchorWorld("Top").Y, visual:anchorWorld("AuraAnchor").Y, speciesId .. " Top arriba")
			expect.atMost(math.abs(visual:anchorWorld("Ground").Y), 0.2, speciesId .. " Ground en el suelo")
			-- Las medidas declaradas en la config cuadran con el modelo (las usa el servidor).
			expect.near(visual.radius, species.baseRadius, 0.6, speciesId .. " radio")
			-- Ninguna pieza queda bajo el suelo.
			for _, record in ipairs(visual.records) do
				local bottom = record.part.CFrame.Position.Y - math.max(record.part.Size.X, record.part.Size.Y, record.part.Size.Z) / 2
				expect.greater(bottom, -1.3, speciesId .. " " .. record.part.Name .. " bajo el suelo")
			end
			-- Silueta distinta: proporción alto/ancho + número de piezas.
			local signature = string.format("%.1f/%d", visual.height / visual.radius, parts)
			expect.falsy(signatures[signature], speciesId .. " tiene la misma silueta que " .. tostring(signatures[signature]))
			signatures[signature] = speciesId
			-- Animar durante 5 s no produce errores ni valores no finitos.
			for frame = 0, 150 do
				visual.species.idle(visual, frame / 30)
				if frame % 30 < 24 then
					visual.species.eat(visual, (frame % 30) / 24)
				end
				visual:applyPoses()
			end
			for name, record in pairs(visual.joints) do
				local p = record.weld.C0.Position
				expect.truthy(p.X == p.X and p.Y == p.Y and p.Z == p.Z, speciesId .. " articulación " .. name .. " finita")
			end
			visual:resetPoses()
			for name, record in pairs(visual.joints) do
				expect.near((record.weld.C0.Position - record.baseC0.Position).Magnitude, 0, 1e-4, speciesId .. " " .. name .. " vuelve a reposo")
			end
			visual:destroy()
		end
	end)

	test("la escala se aplica de forma exacta y reversible", function()
		local h = Fixtures.server()
		local Builder = h:require("ReplicatedStorage.Shared.Creatures.CreatureBuilder")
		local visual = Builder.build("BANANOSAUR")
		local record = visual.records[5]
		local size, c0 = record.part.Size, record.weld.C0.Position
		local top = visual:anchorWorld("Top")
		visual:setScale(2)
		expect.near((record.part.Size - size * 2).Magnitude, 0, 1e-4)
		expect.near((record.weld.C0.Position - c0 * 2).Magnitude, 0, 1e-4)
		visual:setScale(0.6)
		visual:setScale(1)
		expect.near((record.part.Size - size).Magnitude, 0, 1e-4)
		expect.near((record.weld.C0.Position - c0).Magnitude, 0, 1e-4)
		expect.near((visual:anchorWorld("Top") - top).Magnitude, 0, 1e-3)
	end)

	test("las 4 mutaciones cambian visiblemente cada especie sin tocar ojos ni dientes", function()
		local h = Fixtures.server()
		local Builder = h:require("ReplicatedStorage.Shared.Creatures.CreatureBuilder")
		local MutationVisuals = h:require("ReplicatedStorage.Shared.Creatures.MutationVisuals")
		local CreatureConfig = Fixtures.config(h, "CreatureConfig")
		local function snapshot(visual)
			local list = {}
			for index, record in ipairs(visual.records) do
				list[index] = tostring(record.part.Color) .. "|" .. tostring(record.part.Material)
			end
			return list
		end
		for _, speciesId in ipairs(CreatureConfig.Order) do
			local visual = Builder.build(speciesId)
			local normal = snapshot(visual)
			local looks = { NORMAL = table.concat(normal, ";") }
			for _, mutationId in ipairs({ "GOLDEN", "ELECTRIC", "COSMIC" }) do
				MutationVisuals.apply(visual, mutationId)
				local now = snapshot(visual)
				local changed = 0
				for index, record in ipairs(visual.records) do
					if now[index] ~= normal[index] then
						changed += 1
						expect.truthy(record.role == "Body" or record.role == "Belly" or record.role == "Accent" or record.role == "Detail", speciesId .. " " .. mutationId .. " tocó el rol " .. tostring(record.role))
					end
				end
				expect.greater(changed / #visual.records, 0.3, speciesId .. " " .. mutationId .. ": cambia buena parte del modelo")
				expect.equal(changed > 0 and MutationVisuals.affectedCount(visual, mutationId) > 0, true)
				local look = table.concat(now, ";")
				for other, otherLook in pairs(looks) do
					expect.truthy(look ~= otherLook, speciesId .. ": " .. mutationId .. " se confunde con " .. other)
				end
				looks[mutationId] = look
			end
			-- Volver a NORMAL restaura exactamente el aspecto original.
			MutationVisuals.apply(visual, "NORMAL")
			expect.equal(table.concat(snapshot(visual), ";"), looks.NORMAL, speciesId .. " restaurada")
			visual:destroy()
		end
	end)

	TestKit.suite("VFX: auras y efectos en el cliente")

	local function clientSetup()
		local h, s = Fixtures.server({ isStudio = true })
		local player, session = h:joinPlayer(1, "Ana")
		local c = h:bootClient(player)
		h:lookAt(s.PlotService.plot(session.plotIndex).cframe.Position)
		session.profile.upgrades.SLOTS = 3
		s.PlotService.refresh(session)
		h:tick(0.05, 4)
		return h, s, player, session, c
	end

	local function countInstances(root, className)
		local n = 0
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA(className) then
				n += 1
			end
		end
		return n
	end

	test("cada mutación funciona con cada especie y respeta los límites de la calidad", function()
		local h, s, player, session, c = clientSetup()
		local CreatureConfig = Fixtures.config(h, "CreatureConfig")
		local VFX = Fixtures.config(h, "VFXConfig")
		local _, firstId = Fixtures.firstCreature(session)
		s.CreatureService.remove(session, firstId)
		for _, speciesId in ipairs(CreatureConfig.Order) do
			s.CreatureService.add(session, speciesId, "NORMAL")
		end
		h:tick(0.05, 12)
		expect.equal(Fixtures.count(c.CreatureController.entries()), 6)

		for _, quality in ipairs({ "High", "Medium", "Low" }) do
			c.SettingsController.set("vfxQuality", quality)
			local q = VFX.Quality[quality]
			for _, mutationId in ipairs({ "GOLDEN", "ELECTRIC", "COSMIC", "NORMAL" }) do
				for _, creature in pairs(session.profile.creatures) do
					s.MutationService.apply(session, creature, mutationId, true)
				end
				h:tick(0.05, 16)
				local stats = c.AuraController.stats()
				expect.equal(stats.total, 6, "un aura registrada por criatura")
				expect.atMost(stats.built, q.maxActiveAuras, quality .. " auras activas")
				expect.atMost(stats.lights, q.maxLights, quality .. " luces")
				for key, entry in pairs(c.CreatureController.entries()) do
					expect.equal(entry.mutationId, mutationId, "el cliente refleja la mutación")
					expect.equal(entry.visual.mutation, mutationId, "materiales aplicados")
					local aura = c.AuraController.get(key)
					local expectAura = mutationId ~= "NORMAL" or entry.rarity == "Legendary" or entry.rarity == "Secret"
					local label = quality .. " " .. entry.speciesId .. " " .. mutationId
					if expectAura then
						expect.truthy(aura.built, label .. ": aura construida")
						expect.atMost(aura.particles, q.maxAuraParticles + 1e-6, label .. " partículas")
						expect.atMost(#aura.orbiters, VFX.Limits.MaxOrbitersPerAura, label .. " orbitadores")
						expect.atMost(#aura.rings, VFX.Limits.MaxRingsPerAura, label .. " anillos")
						expect.atMost(#aura.arcs, VFX.Limits.MaxArcsPerAura, label .. " arcos")
						if quality == "Low" then
							expect.equal(#aura.orbiters + #aura.rings + #aura.arcs, 0, label .. " simplificada")
						end
						-- El aura cuelga del modelo visual: lo sigue y se destruye con él.
						expect.truthy(aura.container:IsDescendantOf(entry.visual.model), label .. " cuelga de la criatura")
						-- El suelo del aura está en el suelo de la criatura, no dentro ni flotando.
						for _, ground in ipairs(aura.groundRings) do
							expect.near(ground.part.CFrame.Position.Y, entry.visual.root.CFrame.Position.Y, 0.3, label .. " halo a ras de suelo")
						end
						-- Los orbitadores giran alrededor del cuerpo, fuera de él.
						for _, orbiter in ipairs(aura.orbiters) do
							expect.greater(orbiter.radius, entry.visual.radius * entry.displayScale * 0.9, label .. " órbita fuera del cuerpo")
						end
					else
						expect.falsy(aura.built, label .. ": sin aura")
						expect.equal(aura.container, nil)
					end
				end
			end
		end
		expect.equal(#h.warnings, 0, table.concat(h.warnings, " | "))
	end)

	test("el aura sigue a la criatura cuando crece y desaparece con ella", function()
		local h, s, player, session, c = clientSetup()
		c.SettingsController.set("vfxQuality", "High")
		local creature, id = Fixtures.firstCreature(session)
		s.MutationService.apply(session, creature, "COSMIC", true)
		h:tick(0.05, 16)
		local key = "1:" .. id
		local aura = c.AuraController.get(key)
		expect.truthy(aura and aura.built)
		local entry = c.CreatureController.entries()[key]
		local radiusBefore = aura.orbiters[1].radius
		-- El aura está centrada en el cuerpo de ESTA criatura (no en el origen ni en otra).
		local slot = s.CreatureService.positionOf(session, id)
		local center = entry.visual:anchorWorld("AuraAnchor")
		expect.near(center.X, slot.X, 0.5, "centro del aura (x)")
		expect.near(center.Z, slot.Z, 0.5, "centro del aura (z)")
		expect.greater(center.Y, slot.Y + 0.5, "a la altura del cuerpo")
		local orbit = aura.orbiters[1].part.CFrame.Position
		expect.atMost((Fixtures.Vector3.new(orbit.X, 0, orbit.Z) - Fixtures.Vector3.new(slot.X, 0, slot.Z)).Magnitude, radiusBefore * 1.3 + 0.5, "orbita alrededor de la criatura")
		-- Crece mucho: el aura se reconstruye a la nueva escala.
		local Math = Fixtures.logic(h, "EconomyMath")
		creature.growth = Math.growthForLevel("GOBBLO", 40)
		s.CreatureService.refresh(session, id)
		h:tick(0.05, 40)
		aura = c.AuraController.get(key)
		expect.truthy(aura.built)
		expect.greater(aura.orbiters[1].radius, radiusBefore * 1.5, "órbitas adaptadas al nuevo tamaño")
		expect.near(aura.builtScale, entry.targetScale, 0.15)
		-- Los orbitadores se mueven (no están congelados).
		local before = aura.orbiters[1].part.CFrame.Position
		h:tick(0.05, 10)
		expect.greater((aura.orbiters[1].part.CFrame.Position - before).Magnitude, 0.1, "orbitando")
		-- Se guarda la criatura: desaparecen entrada, aura e instancias.
		local workspace = h.game:GetService("Workspace")
		h:fire(player, "StoreCreature", id)
		h:tick(0.05, 6)
		expect.equal(c.CreatureController.entries()[key], nil)
		expect.equal(c.AuraController.get(key), nil)
		expect.equal(c.AuraController.stats().total, 0)
		expect.equal(countInstances(workspace.FTB_Creatures, "ParticleEmitter"), 0, "sin emisores huérfanos")
		expect.equal(countInstances(workspace.FTB_Creatures, "Beam"), 0)
	end)

	test("las auras lejanas no existen (LOD) y vuelven al acercarse", function()
		local h, s, player, session, c = clientSetup()
		local creature, id = Fixtures.firstCreature(session)
		s.MutationService.apply(session, creature, "GOLDEN", true)
		h:tick(0.05, 16)
		local key = "1:" .. id
		expect.truthy(c.AuraController.get(key).built)
		h:lookAt(Fixtures.Vector3.new(0, 0, 0) - s.PlotService.plot(session.plotIndex).cframe.Position)
		h:tick(0.05, 16)
		expect.falsy(c.AuraController.get(key).built, "lejos: ninguna instancia")
		expect.equal(c.AuraController.stats().particles, 0)
		h:lookAt(s.PlotService.plot(session.plotIndex).cframe.Position)
		h:tick(0.05, 16)
		expect.truthy(c.AuraController.get(key).built, "cerca: reconstruida")
	end)

	test("todos los efectos puntuales se reproducen y se limpian solos", function()
		local h, s, player, session, c = clientSetup()
		local VFX = Fixtures.config(h, "VFXConfig")
		c.SettingsController.set("vfxQuality", "High")
		h:tick(0.05, 3)
		local creature, id = Fixtures.firstCreature(session)
		local model = s.CreatureService.modelOf(1, id)
		local position = s.CreatureService.positionOf(session, id)
		local names = {}
		for effectId in pairs(VFX.Effects) do
			table.insert(names, effectId)
		end
		table.sort(names)
		for _, effectId in ipairs(names) do
			expect.truthy(c.EffectsController.play(effectId, { model = model }), effectId .. " sobre criatura")
			expect.truthy(c.EffectsController.play(effectId, { position = position, radius = 2 }), effectId .. " en posición")
			h:tick(0.1, 45)
			local stats = c.EffectsController.stats()
			expect.equal(stats.active, 0, effectId .. " terminado")
			expect.equal(stats.rings, 0, effectId .. " ondas eliminadas")
			expect.equal(stats.lights, 0, effectId .. " luces eliminadas")
			expect.equal(stats.pooled, stats.hosts, effectId .. " emisores devueltos al pool")
		end
		expect.equal(c.EffectCleanup.count(), 0, "nada pendiente de limpieza")
		expect.falsy(c.EffectsController.play("NoExiste", { position = position }))
		expect.falsy(c.EffectsController.play("Grow", {}), "sin objetivo no hace nada")
		expect.equal(#h.warnings, 0, table.concat(h.warnings, " | "))
	end)

	test("una avalancha de efectos no crea instancias sin límite", function()
		local h, s, player, session, c = clientSetup()
		local VFX = Fixtures.config(h, "VFXConfig")
		local creature, id = Fixtures.firstCreature(session)
		local position = s.CreatureService.positionOf(session, id)
		for _, quality in ipairs({ "Low", "Medium", "High" }) do
			c.SettingsController.set("vfxQuality", quality)
			h:tick(0.05, 2)
			local q = VFX.Quality[quality]
			for i = 1, 400 do
				c.EffectsController.play(i % 2 == 0 and "MutationCosmic" or "FeedCrumbs", { position = position, radius = 2 })
			end
			local stats = c.EffectsController.stats()
			expect.atMost(stats.active, q.maxOneShots * 2, quality .. " efectos simultáneos")
			expect.atMost(stats.hosts, VFX.Limits.OneShotPoolSize * 3, quality .. " emisores")
			expect.atMost(stats.lights, q.maxLights, quality .. " luces")
			local fx = h.game:GetService("Workspace"):FindFirstChild("FTB_ClientFX")
			expect.atMost(#fx:GetChildren(), VFX.Limits.OneShotPoolSize * 3 + q.maxOneShots * 2 + q.maxLights + 2, quality .. " instancias")
			h:tick(0.1, 50)
			expect.equal(c.EffectsController.stats().active, 0)
		end
		-- Cambiar de calidad limpia todo lo que hubiera.
		c.EffectsController.play("Rebirth", { position = position, radius = 3 })
		c.SettingsController.set("vfxQuality", "Low")
		h:tick(0.05, 2)
		local stats = c.EffectsController.stats()
		expect.equal(stats.active + stats.rings + stats.lights + stats.hosts, 0)
	end)

	test("el servidor solo dice qué efecto y dónde; el comando de limpieza funciona", function()
		local h, s, player, session, c = clientSetup()
		local creature, id = Fixtures.firstCreature(session)
		s.FoodService.give(session, "APPLE", 1)
		Fixtures.goToCreature(h, s, player, session, id)
		h:clearSent()
		Fixtures.act(h, player, "Feed", id, "APPLE")
		for _, message in ipairs(h.sent) do
			if message.name == "CreatureEvent" then
				local data = message.args[3]
				expect.equal(data.coins, nil, "los eventos cosméticos no llevan recompensas")
				expect.equal(data.growth, nil)
			end
		end
		c.EffectsController.play("MutationGolden", { position = Fixtures.Vector3.new(0, 5, 0), radius = 2 })
		h:fire(player, "Admin", "clearfx")
		h:tick(0.05, 3)
		local stats = c.EffectsController.stats()
		expect.equal(stats.active + stats.rings + stats.lights, 0)
	end)

	test("la bestia gigante y la rareza SECRET se presentan con sus efectos", function()
		local h, s, player, session, c = clientSetup()
		c.SettingsController.set("vfxQuality", "High")
		local secret = s.CreatureService.add(session, "NULLABYTE", "COSMIC")
		h:tick(0.05, 16)
		local aura = c.AuraController.get("1:" .. secret.id)
		expect.truthy(aura.built)
		expect.equal(#aura.auraIds, 2, "aura de mutación + aura SECRET")
		expect.truthy(aura.glitch, "glitch moderado")
		expect.truthy(aura.highlight, "contorno propio")
		-- Bestia gigante: visible para todos, con prompt y placa.
		s.EventService.forceStart("GIANT_BEAST")
		h:lookAt(Fixtures.Vector3.new(0, 0, 0))
		h:tick(0.05, 10)
		local giant
		for _, entry in pairs(c.CreatureController.entries()) do
			if entry.isGiant then
				giant = entry
			end
		end
		expect.truthy(giant, "la bestia gigante se construye en el cliente")
		expect.truthy(giant.prompt, "se puede alimentar")
		expect.near(giant.displayScale, 4.5, 0.01)
		session.profile.inventory.PIZZA = 2
		s.StateService.push(1, "inventory")
		h:moveTo(player, Fixtures.Vector3.new(0, 5, 20))
		h:tick(0.05, 3)
		Harness.signalOf(giant.prompt, "Triggered"):Fire()
		h:settle(4)
		Harness.signalOf(giant.prompt, "TriggerEnded"):Fire()
		h:tick(0.05, 3)
		expect.equal(session.profile.inventory.PIZZA, 1, "GiantFeed enviado y aceptado")
		s.EventService.stop()
		h:tick(0.05, 6)
		for _, entry in pairs(c.CreatureController.entries()) do
			expect.falsy(entry.isGiant, "desaparece al terminar")
		end
		expect.equal(#h.warnings, 0, table.concat(h.warnings, " | "))
	end)
end
