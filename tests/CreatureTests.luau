--!nocheck
local TestKit = require("./lib/TestKit")
local Fixtures = require("./lib/Fixtures")
local expect = TestKit.expect
local test = TestKit.test

return function()
	TestKit.suite("Criaturas y alimentación")

	local function setup()
		local h, s = Fixtures.server()
		local player, session = h:joinPlayer(1, "Ana")
		local creature, id = Fixtures.firstCreature(session)
		return h, s, player, session, creature, id
	end

	test("la criatura inicial pertenece al jugador y está en su parcela, delante del spawn", function()
		local h, s, player, session, creature, id = setup()
		expect.equal(creature.species, "GOBBLO")
		expect.equal(creature.slot, 2)
		local model = s.CreatureService.modelOf(1, id)
		expect.truthy(model, "modelo en el mundo")
		expect.equal(model:GetAttribute("OwnerUserId"), 1)
		expect.equal(model:GetAttribute("Species"), "GOBBLO")
		expect.equal(model:GetAttribute("Mutation"), "NORMAL")
		local position = s.CreatureService.positionOf(session, id)
		expect.truthy(s.PlotService.isInside(session.plotIndex, position), "dentro de su parcela")
		-- El jugador aparece mirando hacia ella: está delante, a menos de 25 studs.
		local spawn = s.PlotService.spawnCFrame(session.plotIndex)
		local toCreature = position - spawn.Position
		expect.greater(spawn.LookVector:Dot(toCreature.Unit), 0.9, "la criatura queda de frente")
		expect.atMost(toCreature.Magnitude, 25)
		-- Reentrar no regala otra criatura inicial.
		h:removePlayer(player)
		local _, again = h:joinPlayer(1, "Ana")
		expect.equal(Fixtures.count(again.profile.creatures), 1)
	end)

	test("la comida de bienvenida está en el camino hacia la criatura y solo la recoge su dueño", function()
		local h, s, player, session, creature, id = setup()
		expect.equal(s.FoodService.count("starter"), 3)
		local other, otherSession = h:joinPlayer(2, "Beto")
		local plot = s.PlotService.plot(session.plotIndex)
		local spawn = s.PlotService.spawnCFrame(session.plotIndex)
		local target = s.CreatureService.positionOf(session, id)
		-- Beto pisa la comida de Ana: no se la lleva.
		local mid = spawn.Position:Lerp(target, 0.4)
		Fixtures.goTo(h, other, mid, 0)
		h:step(0.15, 3)
		expect.equal(Fixtures.count(otherSession.profile.inventory), 0)
		-- Ana camina en línea recta desde el spawn hacia su criatura.
		for i = 0, 10 do
			h:moveTo(player, spawn.Position:Lerp(target, i / 20))
			h:step(0.15, 1)
		end
		local total = 0
		for _, n in pairs(session.profile.inventory) do
			total += n
		end
		expect.equal(total, 3, "recoge las tres sin desviarse")
		expect.equal(session.profile.stats.foodsCollected, 3)
	end)

	test("alimentar consume una comida, hace crecer y recompensa (bonus de primera vez una sola vez)", function()
		local h, s, player, session, creature, id = setup()
		s.FoodService.give(session, "APPLE", 3)
		Fixtures.goToCreature(h, s, player, session, id)
		local model = s.CreatureService.modelOf(1, id)
		local scaleBefore = model:GetAttribute("Scale")
		Fixtures.act(h, player, "Feed", id, "APPLE")
		expect.equal(session.profile.inventory.APPLE, 2)
		expect.equal(creature.growth, 5)
		expect.equal(session.profile.coins, 50 + 5 + 25, "5 por la comida + 25 de primera vez")
		expect.greater(model:GetAttribute("Scale"), scaleBefore, "crecimiento visible replicado")
		local events = h:sentTo(1, "CreatureEvent")
		expect.equal(#events, 1)
		expect.equal(events[1][2], "Fed")
		expect.equal(events[1][3].first, true)
		Fixtures.act(h, player, "Feed", id, "APPLE")
		expect.equal(session.profile.coins, 50 + 5 + 25 + 5, "sin bonus la segunda vez")
		expect.equal(creature.growth, 10)
		expect.equal(model:GetAttribute("Level"), 1, "10 puntos = nivel 1")
		expect.equal(session.profile.stats.foodsFed, 2)
	end)

	test("la comida favorita da más crecimiento", function()
		local h, s, player, session, creature, id = setup()
		s.FoodService.give(session, "BREAD_CRUMB", 1)
		Fixtures.goToCreature(h, s, player, session, id)
		Fixtures.act(h, player, "Feed", id, "BREAD_CRUMB")
		expect.equal(creature.growth, 6) -- 4 * 1.5
	end)

	test("no se puede alimentar sin comida, ni con comida que no se tiene", function()
		local h, s, player, session, creature, id = setup()
		Fixtures.goToCreature(h, s, player, session, id)
		Fixtures.act(h, player, "Feed", id, "APPLE")
		expect.equal(creature.growth, 0)
		expect.equal(session.profile.coins, 50)
		s.FoodService.give(session, "APPLE", 1)
		Fixtures.act(h, player, "Feed", id, "PIZZA")
		expect.equal(creature.growth, 0)
		expect.equal(session.profile.inventory.APPLE, 1)
		Fixtures.act(h, player, "Feed", id, "NOPE")
		Fixtures.act(h, player, "Feed", "c999", "APPLE")
		expect.equal(session.profile.inventory.APPLE, 1)
		expect.equal(session.profile.coins, 50)
	end)

	test("una petición repetida no duplica el consumo ni la recompensa", function()
		local h, s, player, session, creature, id = setup()
		s.FoodService.give(session, "APPLE", 5)
		Fixtures.goToCreature(h, s, player, session, id)
		h:advance(5)
		-- Cinco peticiones en el mismo instante (sin que pase el tiempo de masticar).
		for _ = 1, 5 do
			h:fire(player, "Feed", id, "APPLE")
		end
		expect.equal(session.profile.inventory.APPLE, 4, "solo se consume una")
		expect.equal(creature.growth, 5)
		expect.equal(session.profile.coins, 50 + 5 + 25)
		expect.equal(#h:sentTo(1, "CreatureEvent"), 1)
		-- Pasado el tiempo de consumo vuelve a poder comer.
		h:advance(1)
		h:fire(player, "Feed", id, "APPLE")
		expect.equal(session.profile.inventory.APPLE, 3)
	end)

	test("no se puede alimentar desde lejos (la distancia se mide en el servidor)", function()
		local h, s, player, session, creature, id = setup()
		s.FoodService.give(session, "APPLE", 2)
		local position = s.CreatureService.positionOf(session, id)
		h:moveTo(player, position + Fixtures.Vector3.new(0, 3, -40))
		Fixtures.act(h, player, "Feed", id, "APPLE")
		expect.equal(creature.growth, 0)
		expect.equal(session.profile.inventory.APPLE, 2)
		expect.equal(Fixtures.lastNotification(h, 1).text, "Get closer to feed.")
		h:moveTo(player, Fixtures.Vector3.new(0, 5, 0)) -- el centro del mapa
		Fixtures.act(h, player, "Feed", id, "APPLE")
		expect.equal(creature.growth, 0)
		-- Sin personaje tampoco.
		h:kill(player)
		Fixtures.act(h, player, "Feed", id, "APPLE")
		expect.equal(creature.growth, 0)
	end)

	test("nadie puede alimentar ni tocar las criaturas de otro jugador", function()
		local h, s, ana, anaSession, creature, id = setup()
		local beto, betoSession = h:joinPlayer(2, "Beto")
		s.FoodService.give(betoSession, "APPLE", 2)
		Fixtures.goToCreature(h, s, beto, anaSession, id)
		-- Beto usa el id de la criatura de Ana. En SU perfil, ese id es su propia criatura (lejos).
		Fixtures.act(h, beto, "Feed", id, "APPLE")
		expect.equal(creature.growth, 0, "la de Ana no crece")
		expect.equal(betoSession.profile.inventory.APPLE, 2, "no consume: está lejos de la suya")
		for _, remote in ipairs({ "SellCreature", "StoreCreature" }) do
			Fixtures.act(h, beto, remote, id)
		end
		Fixtures.act(h, beto, "PlaceCreature", id, 3)
		expect.equal(Fixtures.count(anaSession.profile.creatures), 1)
		expect.equal(creature.slot, 2, "la criatura de Ana no se mueve")
	end)

	test("el crecimiento respeta el nivel máximo y al máximo no consume comida", function()
		local h, s, player, session, creature, id = setup()
		local Math = Fixtures.logic(h, "EconomyMath")
		local CreatureConfig = Fixtures.config(h, "CreatureConfig")
		creature.growth = Math.growthForLevel("GOBBLO", 50) - 2
		s.CreatureService.refresh(session, id)
		s.FoodService.give(session, "PIZZA", 3)
		Fixtures.goToCreature(h, s, player, session, id)
		Fixtures.act(h, player, "Feed", id, "PIZZA")
		expect.equal(creature.growth, Math.growthForLevel("GOBBLO", 50), "se acota al máximo")
		expect.equal(session.profile.inventory.PIZZA, 2)
		local model = s.CreatureService.modelOf(1, id)
		expect.equal(model:GetAttribute("Level"), 50)
		expect.near(model:GetAttribute("Scale"), CreatureConfig.Species.GOBBLO.maxScale, 1e-6)
		Fixtures.act(h, player, "Feed", id, "PIZZA")
		expect.equal(session.profile.inventory.PIZZA, 2, "al máximo no se gasta comida")
		-- El hitbox no crece tanto como la escala visual.
		local hitbox = model:FindFirstChild("Hitbox")
		local species = CreatureConfig.Species.GOBBLO
		expect.atMost(hitbox.Size.Y, species.baseRadius * 2 * CreatureConfig.HitboxMaxScale)
		-- Y la distancia de interacción sigue permitiendo alcanzarla.
		expect.atMost(s.CreatureService.interactRadius(creature, species.maxScale), species.baseRadius * CreatureConfig.HitboxMaxScale + 1e-9)
	end)

	test("ninguna criatura al tamaño máximo se sale de su espacio ni invade a la vecina", function()
		local h = Fixtures.server()
		local CreatureConfig = Fixtures.config(h, "CreatureConfig")
		local Layout = Fixtures.logic(h, "PlotLayout")
		local GameConfig = Fixtures.config(h, "GameConfig")
		local Builder = h:require("ReplicatedStorage.Shared.Creatures.CreatureBuilder")
		local a, b = Layout.slotLocal(1), Layout.slotLocal(2)
		local spacingX = math.abs(a.x - b.x)
		local spacingZ = math.abs(Layout.slotLocal(1).z - Layout.slotLocal(4).z)
		local half = GameConfig.World.PlotSize / 2
		for _, speciesId in ipairs(CreatureConfig.Order) do
			local species = CreatureConfig.Species[speciesId]
			local visual = Builder.build(speciesId)
			local radius = visual.radius * species.maxScale
			expect.atMost(radius * 2, spacingX, speciesId .. " cabe entre columnas")
			expect.atMost(radius * 2, spacingZ, speciesId .. " cabe entre filas")
			for slot = 1, GameConfig.World.MaxSlotsPerPlot do
				local p = Layout.slotLocal(slot)
				expect.atMost(math.abs(p.x) + radius, half - 1, speciesId .. " dentro de la valla (x)")
				expect.atMost(p.z + radius, half - 1, speciesId .. " dentro de la valla (z)")
			end
			visual:destroy()
		end
	end)

	test("mutación al alimentar: la decide el servidor, solo desde NORMAL y nunca baja de nivel", function()
		local h, s, player, session, creature, id = setup()
		local Rolls = Fixtures.logic(h, "Rolls")
		local original = Rolls.feedMutation
		Rolls.feedMutation = function(current)
			return current == "NORMAL" and "ELECTRIC" or nil
		end
		s.FoodService.give(session, "APPLE", 3)
		Fixtures.goToCreature(h, s, player, session, id)
		local incomeBefore = s.EconomyService.income(session)
		Fixtures.act(h, player, "Feed", id, "APPLE")
		Rolls.feedMutation = original
		expect.equal(creature.mutation, "ELECTRIC")
		local model = s.CreatureService.modelOf(1, id)
		expect.equal(model:GetAttribute("Mutation"), "ELECTRIC")
		expect.truthy(session.profile.collection["GOBBLO:ELECTRIC"], "colección")
		expect.near(s.EconomyService.income(session), incomeBefore * 3.5, 1e-6, "bonificación calculada en servidor")
		-- Efecto de transformación enviado a todos.
		local effects = h:sentTo(1, "Effect")
		local found = false
		for _, args in ipairs(effects) do
			if args[1] == "MutationElectric" then
				found = true
			end
		end
		expect.truthy(found, "efecto de transformación")
		-- No baja ni se sustituye por una de nivel inferior.
		expect.falsy(s.MutationService.apply(session, creature, "GOLDEN", false))
		expect.equal(creature.mutation, "ELECTRIC")
		expect.truthy(s.MutationService.apply(session, creature, "COSMIC", false))
		expect.falsy(s.MutationService.apply(session, creature, "NOPE", true))
	end)

	test("las probabilidades de mutación están centralizadas y suman lo esperado", function()
		local h = Fixtures.server()
		local Rolls = Fixtures.logic(h, "Rolls")
		local rng = h.Random.new(7)
		local function rnd()
			return rng:NextNumber()
		end
		local counts = { NORMAL = 0, GOLDEN = 0, ELECTRIC = 0, COSMIC = 0 }
		local n = 40000
		for _ = 1, n do
			counts[Rolls.hatchMutation(1, rnd)] += 1
		end
		expect.near(counts.GOLDEN / n, 0.06, 0.01)
		expect.near(counts.ELECTRIC / n, 0.025, 0.006)
		expect.near(counts.COSMIC / n, 0.006, 0.003)
		-- Una criatura ya mutada nunca vuelve a tirar.
		expect.equal(Rolls.feedMutation("GOLDEN", "VOID_TRUFFLE", function()
			return 0
		end), nil)
		-- Con tirada 0 una NORMAL muta siempre; con 0.999 nunca.
		expect.truthy(Rolls.feedMutation("NORMAL", "APPLE", function()
			return 0
		end))
		expect.equal(Rolls.feedMutation("NORMAL", "APPLE", function()
			return 0.999
		end), nil)
	end)

	test("huevos: cobran, añaden la criatura y respetan bloqueo y almacén", function()
		local h, s, player, session = setup()
		Fixtures.act(h, player, "BuyEgg", "BASIC") -- 150 > 50
		expect.equal(Fixtures.count(session.profile.creatures), 1)
		expect.equal(session.profile.coins, 50)
		s.EconomyService.addCoins(1, 100000)
		local before = session.profile.coins
		Fixtures.act(h, player, "BuyEgg", "BASIC")
		expect.equal(Fixtures.count(session.profile.creatures), 2)
		expect.equal(session.profile.coins, before - 150)
		expect.equal(session.profile.stats.eggsHatched, 1)
		Fixtures.act(h, player, "BuyEgg", "ROYAL") -- requiere Hatchery 2
		expect.equal(Fixtures.count(session.profile.creatures), 2)
		expect.equal(session.profile.coins, before - 150)
		Fixtures.act(h, player, "BuyEgg", "NOPE")
		expect.equal(session.profile.coins, before - 150)
		-- Con los 3 espacios llenos, la siguiente va al almacén (slot 0).
		Fixtures.act(h, player, "BuyEgg", "BASIC")
		Fixtures.act(h, player, "BuyEgg", "BASIC")
		local stored = 0
		for _, c in pairs(session.profile.creatures) do
			if c.slot == 0 then
				stored += 1
			end
		end
		expect.equal(Fixtures.count(session.profile.creatures), 4)
		expect.equal(stored, 1)
		-- Límite de criaturas: no cobra si no caben más.
		local CreatureConfig = Fixtures.config(h, "CreatureConfig")
		while Fixtures.count(session.profile.creatures) < CreatureConfig.MaxOwned do
			s.CreatureService.add(session, "GOBBLO", "NORMAL")
		end
		local coins = session.profile.coins
		Fixtures.act(h, player, "BuyEgg", "BASIC")
		expect.equal(session.profile.coins, coins)
		expect.equal(Fixtures.count(session.profile.creatures), CreatureConfig.MaxOwned)
	end)

	test("las tablas de huevos solo dan rarezas configuradas y los secretos son muy escasos", function()
		local h = Fixtures.server()
		local Rolls = Fixtures.logic(h, "Rolls")
		local EggConfig = Fixtures.config(h, "EggConfig")
		local CreatureConfig = Fixtures.config(h, "CreatureConfig")
		local rng = h.Random.new(99)
		local function rnd()
			return rng:NextNumber()
		end
		for _, eggId in ipairs(EggConfig.Order) do
			local egg = EggConfig.Eggs[eggId]
			local secrets = 0
			for _ = 1, 5000 do
				local speciesId = Rolls.species(egg, rnd)
				local rarity = CreatureConfig.Species[speciesId].rarity
				expect.truthy(egg.weights[rarity], eggId .. " no debería dar " .. rarity)
				if rarity == "Secret" then
					secrets += 1
				end
			end
			expect.atMost(secrets / 5000, 0.02, eggId .. " secretos")
		end
	end)

	test("colocar, intercambiar y guardar criaturas", function()
		local h, s, player, session, creature, id = setup()
		local second = s.CreatureService.add(session, "CHOMPITO", "NORMAL")
		expect.equal(second.slot, 1)
		Fixtures.act(h, player, "PlaceCreature", id, 1) -- intercambio
		expect.equal(creature.slot, 1)
		expect.equal(second.slot, 2)
		expect.truthy(s.CreatureService.modelOf(1, id))
		expect.truthy(s.CreatureService.modelOf(1, second.id))
		Fixtures.act(h, player, "PlaceCreature", id, 5) -- espacio bloqueado (solo 3)
		expect.equal(creature.slot, 1)
		Fixtures.act(h, player, "PlaceCreature", id, 7) -- fuera de rango: lo rechaza la validación
		expect.equal(creature.slot, 1)
		local income = s.EconomyService.income(session)
		Fixtures.act(h, player, "StoreCreature", second.id)
		expect.equal(second.slot, 0)
		expect.equal(s.CreatureService.modelOf(1, second.id), nil)
		expect.truthy(s.EconomyService.income(session) < income, "guardada no produce")
		-- Dos criaturas nunca comparten espacio.
		Fixtures.act(h, player, "PlaceCreature", second.id, 1)
		expect.equal(second.slot, 1)
		expect.equal(creature.slot, 0)
	end)

	test("alimentación automática (pase): alimenta sin distancia pero con las mismas reglas", function()
		local h, s, player, session, creature, id = setup()
		s.FoodService.give(session, "APPLE", 2)
		h:step(1, 5)
		expect.equal(creature.growth, 0, "sin pase no hay auto-feed")
		s.MonetizationService.setPass(session, "AUTO_FEED", true)
		creature = session.profile.creatures[id]
		h:step(1, 2)
		expect.atMost(creature.growth, 5, "como mucho una comida cada 3 s")
		h:step(1, 8)
		expect.equal(creature.growth, 10)
		expect.equal(session.profile.inventory.APPLE, nil)
		h:step(1, 6)
		expect.equal(creature.growth, 10, "sin comida no crece")
	end)

	test("los remotos rechazan tipos y valores maliciosos sin romper el servidor", function()
		local h, s, player, session, creature, id = setup()
		s.FoodService.give(session, "APPLE", 2)
		Fixtures.goToCreature(h, s, player, session, id)
		local bad = { 5, true, {}, "", string.rep("a", 500), "c1; drop", 0 / 0, Fixtures.Vector3.new(1, 2, 3) }
		for _, value in ipairs(bad) do
			Fixtures.act(h, player, "Feed", value, "APPLE")
			Fixtures.act(h, player, "Feed", id, value)
		end
		Fixtures.act(h, player, "Feed")
		Fixtures.act(h, player, "Feed", id)
		Fixtures.act(h, player, "Feed", id, "APPLE", "extra")
		expect.equal(creature.growth, 0)
		expect.equal(session.profile.inventory.APPLE, 2)
		expect.greater(s.ValidationService.rejectedCount(1), 10)
		for _, text in ipairs(h.warnings) do
			expect.falsy(string.find(text, "handler error", 1, true), "ningún handler debe fallar: " .. text)
		end
		-- Y después de todo eso el juego sigue funcionando.
		Fixtures.act(h, player, "Feed", id, "APPLE")
		expect.equal(creature.growth, 5)
	end)

	test("validador de argumentos (puro)", function()
		local h = Fixtures.server()
		local Validate = Fixtures.logic(h, "Validate")
		expect.truthy(Validate.isId("GOBBLO_1"))
		expect.falsy(Validate.isId("has space"))
		expect.falsy(Validate.isId(""))
		expect.falsy(Validate.isId(string.rep("x", 41)))
		expect.truthy(Validate.isInteger(5, 1, 10))
		expect.falsy(Validate.isInteger(5.5))
		expect.falsy(Validate.isInteger(0 / 0))
		expect.falsy(Validate.isInteger(math.huge))
		expect.falsy(Validate.isInteger(11, 1, 10))
		local ok, reason = Validate.args({ { type = "id" } }, { "a", "b" }, 2)
		expect.falsy(ok)
		expect.equal(reason, "too_many_args")
		expect.truthy(Validate.args({ { type = "id" }, { type = "string", optional = true } }, { "a" }, 1))
		expect.falsy(Validate.args({ { type = "wat" } }, { "a" }, 1))
	end)

	test("token bucket del rate limiter", function()
		local h = Fixtures.server()
		local RateLimiter = Fixtures.logic(h, "RateLimiter")
		local limiter = RateLimiter.new(2, 3)
		local allowed = 0
		for _ = 1, 10 do
			if limiter:allow("k", 0) then
				allowed += 1
			end
		end
		expect.equal(allowed, 3)
		expect.truthy(limiter:allow("k", 0.5)) -- +1 token
		expect.falsy(limiter:allow("k", 0.5))
		expect.truthy(limiter:allow("other", 0.5), "claves independientes")
		limiter:forget("k")
		expect.truthy(limiter:allow("k", 0.5))
	end)
end
