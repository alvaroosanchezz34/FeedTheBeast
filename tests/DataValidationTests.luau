--!nocheck
local TestKit = require("./lib/TestKit")
local Fixtures = require("./lib/Fixtures")
local expect = TestKit.expect
local test = TestKit.test

return function()
	TestKit.suite("Datos: esquema, migraciones y validación (puro)")

	local function schema()
		local h = Fixtures.server()
		return Fixtures.logic(h, "ProfileSchema"), h
	end

	test("el perfil por defecto es válido y no necesita saneado", function()
		local Schema = schema()
		local profile = Schema.default(1000)
		expect.truthy(Schema.validate(profile))
		local prepared, err, warnings = Schema.prepare(profile, 1000)
		expect.truthy(prepared, tostring(err))
		expect.equal(#warnings, 0)
		expect.equal(prepared.version, Schema.CURRENT_VERSION)
	end)

	test("un perfil v1 se migra a la versión actual conservando su progreso", function()
		local Schema = schema()
		local v1 = {
			version = 1,
			createdAt = 5,
			lastSave = 500,
			coins = 1234,
			pendingCoins = 7,
			inventory = { APPLE = 3 },
			creatures = { c1 = { id = "c1", species = "GOBBLO", mutation = "GOLDEN", growth = 42, slot = 1, born = 5 } },
			nextCreatureId = 2,
			upgrades = { INVENTORY = 2 },
			rebirths = 1,
			boosts = {},
			stats = { foodsFed = 9 },
		}
		local profile, err = Schema.prepare(v1, 1000)
		expect.truthy(profile, tostring(err))
		expect.equal(profile.version, Schema.CURRENT_VERSION)
		expect.equal(profile.coins, 1234)
		expect.equal(profile.inventory.APPLE, 3)
		expect.equal(profile.creatures.c1.growth, 42)
		expect.equal(profile.creatures.c1.mutation, "GOLDEN")
		expect.equal(profile.rebirths, 1)
		expect.equal(profile.stats.foodsFed, 9)
		expect.equal(profile.stats.cratesStolen, 0, "estadísticas nuevas rellenadas")
		expect.truthy(profile.collection["GOBBLO:GOLDEN"], "colección reconstruida")
		expect.equal(profile.settings.vfxQuality, "Auto")
		expect.equal(type(profile.receipts), "table")
	end)

	test("los datos que no se pueden interpretar se rechazan (nunca se sustituyen por un perfil vacío)", function()
		local Schema = schema()
		local cases = {
			{ "texto", "not_a_table" },
			{ 42, "not_a_table" },
			{ {}, "bad_version" },
			{ { version = "2" }, "bad_version" },
			{ { version = 1.5 }, "bad_version" },
			{ { version = 0 }, "bad_version" },
			{ { version = Schema.CURRENT_VERSION + 1, coins = 5 }, "newer_version" },
		}
		for _, case in ipairs(cases) do
			local profile, err = Schema.prepare(case[1], 1000)
			expect.equal(profile, nil)
			expect.equal(err, case[2])
		end
		local broken = Schema.default(0)
		broken.coins = "muchas"
		local profile, err = Schema.prepare(broken, 0)
		expect.equal(profile, nil)
		expect.equal(err, "coins_not_finite")
		broken = Schema.default(0)
		broken.creatures = "ninguna"
		profile, err = Schema.prepare(broken, 0)
		expect.equal(profile, nil)
		expect.equal(err, "creatures_not_a_table")
	end)

	test("el saneado corrige valores fuera de rango sin destruir el resto", function()
		local Schema = schema()
		local profile = Schema.default(1000)
		profile.coins = 1e30
		profile.rebirths = -3
		profile.inventory = { APPLE = 2.7, FAKE_FOOD = 5, PIZZA = -4 }
		profile.upgrades = { INVENTORY = 999, FAKE = 2 }
		profile.creatures = {
			c1 = { species = "GOBBLO", mutation = "RAINBOW", growth = -5, slot = 1, born = 1 },
			c2 = { species = "CHOMPITO", mutation = "GOLDEN", growth = 10, slot = 1, born = 1 }, -- espacio duplicado
			c7 = { species = "GLORB", mutation = "NORMAL", growth = 0, slot = 99, born = 1 },
			bad = { species = "DRAGON" },
			[5] = "x",
		}
		profile.nextCreatureId = 1
		profile.settings.vfxQuality = "Ultra"
		profile.settings.sfxVolume = 7
		profile.boosts = { Growth = 1000 + 1e9, Bad = "x" }
		profile.receipts = { "a", 5, string.rep("z", 500), "b" }
		profile.collection = { ["GOBBLO:NORMAL"] = true, ["FAKE:NORMAL"] = true, ["GOBBLO:GOLDEN"] = "yes" }
		local prepared, err, warnings = Schema.prepare(profile, 1000)
		expect.truthy(prepared, tostring(err))
		expect.greater(#warnings, 0)
		expect.equal(prepared.coins, 1e15)
		expect.equal(prepared.rebirths, 0)
		expect.equal(prepared.inventory.APPLE, 2)
		expect.equal(prepared.inventory.FAKE_FOOD, nil)
		expect.equal(prepared.inventory.PIZZA, nil)
		expect.equal(prepared.upgrades.INVENTORY, 10)
		expect.equal(prepared.upgrades.FAKE, nil)
		expect.equal(prepared.creatures.c1.mutation, "NORMAL")
		expect.equal(prepared.creatures.c1.growth, 0)
		expect.equal(prepared.creatures.c1.slot, 1)
		expect.equal(prepared.creatures.c2.slot, 0, "espacio duplicado liberado")
		expect.equal(prepared.creatures.c2.mutation, "GOLDEN", "lo válido se conserva")
		expect.equal(prepared.creatures.c7.slot, 6, "espacio acotado")
		expect.equal(prepared.creatures.bad, nil)
		expect.equal(prepared.creatures[5], nil)
		expect.equal(prepared.nextCreatureId, 8, "no reutiliza ids")
		expect.equal(prepared.settings.vfxQuality, "Auto")
		expect.equal(prepared.settings.sfxVolume, 1)
		expect.equal(prepared.boosts.Growth, 1000 + 24 * 3600)
		expect.equal(prepared.boosts.Bad, nil)
		expect.equal(#prepared.receipts, 2)
		expect.equal(prepared.collection["FAKE:NORMAL"], nil)
		expect.equal(prepared.collection["GOBBLO:GOLDEN"], nil)
		expect.truthy(prepared.collection["CHOMPITO:GOLDEN"])
	end)

	TestKit.suite("Datos: persistencia con DataStore")

	test("el progreso se guarda al salir y se recupera al volver (monedas, criaturas, mutaciones, mejoras)", function()
		local h, s = Fixtures.server()
		local player, session = h:joinPlayer(1, "Ana")
		local creature, id = Fixtures.firstCreature(session)
		s.EconomyService.addCoins(1, 5000)
		s.ShopService.buyUpgrade(session, "INVENTORY")
		s.FoodService.give(session, "PIZZA", 4)
		creature.growth = 77
		s.MutationService.apply(session, creature, "COSMIC", true)
		local extra = s.CreatureService.add(session, "GLORB", "GOLDEN")
		session.profile.settings.vfxQuality = "Low"
		local coins = session.profile.coins
		h:removePlayer(player)

		local saved = Fixtures.saved(h, 1)
		expect.truthy(saved)
		expect.equal(saved.session, nil, "bloqueo liberado al salir")
		expect.equal(saved.coins, coins)

		local _, again = h:joinPlayer(1, "Ana")
		local p = again.profile
		expect.equal(p.coins, coins)
		expect.equal(p.upgrades.INVENTORY, 1)
		expect.equal(p.inventory.PIZZA, 4)
		expect.equal(p.creatures[id].growth, 77)
		expect.equal(p.creatures[id].mutation, "COSMIC")
		expect.equal(p.creatures[extra.id].species, "GLORB")
		expect.equal(p.creatures[extra.id].mutation, "GOLDEN")
		expect.truthy(p.collection["GOBBLO:COSMIC"])
		expect.equal(p.settings.vfxQuality, "Low")
		expect.falsy(again.isNew)
		-- El modelo replicado refleja la mutación guardada.
		expect.equal(s.CreatureService.modelOf(1, id):GetAttribute("Mutation"), "COSMIC")
	end)

	test("guardado periódico y al cerrar el servidor (BindToClose)", function()
		local h, s = Fixtures.server()
		local player, session = h:joinPlayer(1, "Ana")
		local beto, betoSession = h:joinPlayer(2, "Beto")
		s.EconomyService.addCoins(1, 111)
		h:step(5, 30) -- 150 s: supera el intervalo de autoguardado (120 s)
		expect.equal(Fixtures.saved(h, 1).coins, 161, "autoguardado")
		expect.truthy(Fixtures.saved(h, 1).session, "mantiene el bloqueo mientras juega")
		s.EconomyService.addCoins(2, 999)
		h:close()
		expect.equal(Fixtures.saved(h, 2).coins, 1049, "guardado al cerrar")
		expect.equal(Fixtures.saved(h, 1).session, nil)
		expect.equal(Fixtures.saved(h, 2).session, nil)
	end)

	test("lo que se guarda es serializable (sin NaN, sin claves mixtas, sin instancias)", function()
		local h, s = Fixtures.server()
		local player, session = h:joinPlayer(1, "Ana")
		local creature, id = Fixtures.firstCreature(session)
		s.FoodService.give(session, "APPLE", 2)
		Fixtures.goToCreature(h, s, player, session, id)
		Fixtures.act(h, player, "Feed", id, "APPLE")
		s.EconomyService.addCoins(1, 100000)
		Fixtures.act(h, player, "BuyEgg", "BASIC")
		Fixtures.act(h, player, "BuyUpgrade", "PRODUCTION")
		h:step(1, 5)
		-- El DataStore simulado lanza error ante cualquier valor que Roblox no podría guardar.
		expect.truthy(s.PlayerDataService.save(1, false, true))
		expect.falsy(Fixtures.hasWarning(h, "SAVE FAILED"))
	end)

	test("si la carga falla, se expulsa al jugador y los datos anteriores NO se sobrescriben", function()
		local h1, s1 = Fixtures.server()
		local player = h1:joinPlayer(1, "Ana")
		s1.EconomyService.addCoins(1, 7777)
		h1:removePlayer(player)
		local store = Fixtures.deepCopy(Fixtures.storeData(h1))
		expect.equal(store.player_1.coins, 7827)

		local h2, s2 = Fixtures.server({ store = store })
		h2.datastore.failAlways = true
		local p2, session = h2:joinPlayer(1, "Ana")
		expect.equal(session, nil)
		expect.equal(#h2.kicks, 1, "expulsado")
		expect.truthy(string.find(h2.kicks[1].message, "NO se ha sobrescrito", 1, true))
		expect.equal(s2.PlayerDataService.getSession(1), nil)
		h2.datastore.failAlways = false
		expect.equal(Fixtures.saved(h2, 1).coins, 7827, "datos intactos")
		-- Cuando el servicio vuelve, entra con su progreso.
		local _, ok = h2:joinPlayer(1, "Ana")
		expect.truthy(ok)
		expect.equal(ok.profile.coins, 7827)
	end)

	test("los fallos puntuales se reintentan con backoff", function()
		local h, s = Fixtures.server()
		h.datastore.failNext = 3
		local t0 = h.clock.t
		local _, session = h:joinPlayer(1, "Ana")
		expect.truthy(session, "entra tras reintentar")
		expect.greater(h.clock.t - t0, 6, "esperó 1 + 2 + 4 s entre intentos")
		expect.truthy(Fixtures.hasWarning(h, "attempt 1/5 failed"))
	end)

	test("datos corruptos: no se carga, no se guarda y no se tocan", function()
		for _, bad in ipairs({ "corrupto", { version = 99, coins = 1 }, { version = 2, coins = "x" } }) do
			local h, s = Fixtures.server({ store = { player_1 = Fixtures.deepCopy(bad) } })
			local _, session = h:joinPlayer(1, "Ana")
			expect.equal(session, nil)
			expect.equal(#h.kicks, 1)
			local now = Fixtures.saved(h, 1)
			if type(bad) == "table" then
				expect.equal(now.version, bad.version)
				expect.equal(now.coins, bad.coins)
				expect.equal(now.session, nil, "ni siquiera se escribe el bloqueo")
			else
				expect.equal(now, bad)
			end
			h:close()
			expect.equal(type(Fixtures.saved(h, 1)), type(bad))
		end
	end)

	test("bloqueo de sesión: una partida abierta en otro servidor impide cargar", function()
		local h1, s1 = Fixtures.server()
		local _, session1 = h1:joinPlayer(1, "Ana")
		s1.PlayerDataService.save(1, false, true)
		local store = Fixtures.deepCopy(Fixtures.storeData(h1))
		expect.equal(store.player_1.session.jobId, "test-job")

		local h2, s2 = Fixtures.server({
			store = store,
			before = function(h)
				h.jobId = "otro-servidor"
			end,
		})
		local _, session2 = h2:joinPlayer(1, "Ana")
		expect.equal(session2, nil)
		expect.equal(#h2.kicks, 1)
		expect.truthy(string.find(h2.kicks[1].message, "otro servidor", 1, true))
		expect.equal(Fixtures.saved(h2, 1).session.jobId, "test-job", "el bloqueo ajeno no se pisa")
	end)

	test("bloqueo de sesión: un bloqueo abandonado caduca y se puede tomar", function()
		local h1, s1 = Fixtures.server()
		local _, session1 = h1:joinPlayer(1, "Ana")
		s1.EconomyService.addCoins(1, 500)
		s1.PlayerDataService.save(1, false, true)
		local store = Fixtures.deepCopy(Fixtures.storeData(h1))

		local h2, s2 = Fixtures.server({
			store = store,
			before = function(h)
				h.jobId = "otro-servidor"
			end,
		})
		h2:advance(3600) -- el servidor original murió hace una hora
		local _, session2 = h2:joinPlayer(1, "Ana")
		expect.truthy(session2)
		expect.equal(session2.profile.coins, 550)
		expect.equal(Fixtures.saved(h2, 1).session.jobId, "otro-servidor")
	end)

	test("si otro servidor toma el bloqueo, este deja de guardar y expulsa al jugador", function()
		local h, s = Fixtures.server()
		local player, session = h:joinPlayer(1, "Ana")
		s.EconomyService.addCoins(1, 100)
		-- Otro servidor se queda con el perfil.
		local data = Fixtures.saved(h, 1)
		data.session = { jobId = "ladron-de-sesion", time = h.clock.unix }
		data.coins = 999999
		expect.falsy(s.PlayerDataService.save(1, false, true))
		expect.equal(Fixtures.saved(h, 1).coins, 999999, "no se pisa lo que guardó el otro servidor")
		expect.equal(#h.kicks, 1)
		expect.equal(s.PlayerDataService.getSession(1), nil)
		expect.truthy(Fixtures.hasWarning(h, "session lock lost"))
	end)

	test("los errores de guardado se registran y no rompen la sesión", function()
		local h, s = Fixtures.server()
		local player, session = h:joinPlayer(1, "Ana")
		s.EconomyService.addCoins(1, 100)
		h.datastore.failAlways = true
		expect.falsy(s.PlayerDataService.save(1, false, true))
		expect.truthy(Fixtures.hasWarning(h, "SAVE FAILED for 1"))
		expect.equal(Fixtures.saved(h, 1).coins, 50, "el último guardado correcto sigue ahí")
		h.datastore.failAlways = false
		expect.truthy(s.PlayerDataService.save(1, false, true))
		expect.equal(Fixtures.saved(h, 1).coins, 150)
	end)

	test("Studio sin DataStores: perfil en memoria que nunca se guarda", function()
		local h, s = Fixtures.server({ isStudio = true, datastoreUnavailable = true })
		local player, session = h:joinPlayer(1, "Ana")
		expect.truthy(session)
		expect.truthy(session.ephemeral)
		expect.equal(h:stateFor(1).ephemeral, true, "el cliente lo sabe")
		s.EconomyService.addCoins(1, 100)
		h:removePlayer(player)
		expect.equal(Fixtures.storeData(h), nil, "nada escrito")
	end)

	test("fuera de Studio, sin DataStores no se juega con un perfil vacío", function()
		local h, s = Fixtures.server({ isStudio = false, datastoreUnavailable = true })
		local _, session = h:joinPlayer(1, "Ana")
		expect.equal(session, nil)
		expect.equal(#h.kicks, 1)
	end)

	test("entrar y salir mientras carga no deja bloqueos huérfanos", function()
		local h, s = Fixtures.server()
		local player = h:addPlayer(1, "Ana")
		h:removePlayer(player)
		h:settle(6)
		expect.equal(s.PlayerDataService.getSession(1), nil)
		local saved = Fixtures.saved(h, 1)
		expect.truthy(saved == nil or saved.session == nil, "sin bloqueo")
		local _, session = h:joinPlayer(1, "Ana")
		expect.truthy(session, "puede volver a entrar")
	end)

	test("el tiempo de juego se acumula entre sesiones", function()
		local h, s = Fixtures.server()
		local player, session = h:joinPlayer(1, "Ana")
		h:advance(100)
		h:removePlayer(player)
		expect.near(Fixtures.saved(h, 1).stats.playTime, 100, 2)
		local p2, s2 = h:joinPlayer(1, "Ana")
		h:advance(50)
		expect.near(s.PlayerDataService.playTime(s2), 150, 3)
	end)
end
