--!nocheck
local TestKit = require("./lib/TestKit")
local Fixtures = require("./lib/Fixtures")
local expect = TestKit.expect
local test = TestKit.test

return function()
	TestKit.suite("Economía: fórmulas puras")

	test("nivel <-> crecimiento es coherente y el progreso está en [0,1]", function()
		local h = Fixtures.server()
		local Math = Fixtures.logic(h, "EconomyMath")
		local CreatureConfig = Fixtures.config(h, "CreatureConfig")
		for _, speciesId in ipairs(CreatureConfig.Order) do
			for level = 0, 60 do
				local growth = Math.growthForLevel(speciesId, level)
				local got, progress = Math.levelFromGrowth(speciesId, growth, 100)
				expect.equal(got, level, speciesId .. " L" .. level)
				expect.truthy(progress >= 0 and progress <= 1, "progress range")
			end
		end
		local level = Math.levelFromGrowth("GOBBLO", 1e12, 50)
		expect.equal(level, 50, "tope de nivel")
		expect.equal((Math.levelFromGrowth("GOBBLO", 0 / 0, 50)), 0, "NaN")
		expect.equal((Math.levelFromGrowth("NOPE", 100, 50)), 0, "especie desconocida")
	end)

	test("la escala crece con el nivel pero nunca supera maxScale; el hitbox tiene su propio tope", function()
		local h = Fixtures.server()
		local Math = Fixtures.logic(h, "EconomyMath")
		local CreatureConfig = Fixtures.config(h, "CreatureConfig")
		for _, speciesId in ipairs(CreatureConfig.Order) do
			local species = CreatureConfig.Species[speciesId]
			local previous = 0
			for level = 0, 100 do
				local scale = Math.scaleFor(speciesId, level, 0)
				expect.truthy(scale >= previous, "monótona")
				expect.atMost(scale, species.maxScale + 1e-9, "maxScale")
				expect.atMost(Math.hitboxScale(scale), CreatureConfig.HitboxMaxScale, "hitbox")
				previous = scale
			end
			expect.greater(Math.scaleFor(speciesId, 1, 0), Math.scaleFor(speciesId, 0, 0), "el primer nivel ya se nota")
		end
	end)

	test("los multiplicadores se combinan correctamente", function()
		local h = Fixtures.server()
		local Math = Fixtures.logic(h, "EconomyMath")
		local Schema = Fixtures.logic(h, "ProfileSchema")
		local profile = Schema.default(0)
		Schema.addCreature(profile, "GOBBLO", "NORMAL", 1, 0)
		expect.near(Math.totalIncome(profile, {}), 1)
		profile.upgrades.PRODUCTION = 5 -- +50%
		expect.near(Math.totalIncome(profile, {}), 1.5)
		profile.rebirths = 2 -- x2
		expect.near(Math.totalIncome(profile, {}), 3)
		expect.near(Math.totalIncome(profile, { vip = true }), 3.6)
		expect.near(Math.totalIncome(profile, { vip = true, eventMult = 1.5 }), 5.4)
		-- Mutación y nivel
		local creature = profile.creatures.c1
		creature.mutation = "GOLDEN"
		expect.near(Math.totalIncome(profile, {}), 6)
		creature.growth = Math.growthForLevel("GOBBLO", 10)
		expect.near(Math.totalIncome(profile, {}), 6 * (1 + 10 * 0.12))
		-- Las criaturas guardadas no producen.
		creature.slot = 0
		expect.near(Math.totalIncome(profile, {}), 0)
		-- Un nivel de mejora manipulado no da más que el máximo.
		profile.upgrades.PRODUCTION = 9999
		expect.near(Math.multipliers(profile, {}).upgrades, 3)
	end)

	test("costes de mejoras: crecen, se redondean y terminan en el nivel máximo", function()
		local h = Fixtures.server()
		local Math = Fixtures.logic(h, "EconomyMath")
		local UpgradeConfig = Fixtures.config(h, "UpgradeConfig")
		for _, id in ipairs(UpgradeConfig.Order) do
			local def = UpgradeConfig.Upgrades[id]
			local previous = 0
			for level = 0, def.maxLevel - 1 do
				local cost = Math.upgradeCost(id, level)
				expect.truthy(cost and cost % 1 == 0 and cost > previous, id .. " coste creciente")
				previous = cost
			end
			expect.equal(Math.upgradeCost(id, def.maxLevel), nil, id .. " máximo")
		end
		expect.equal(Math.upgradeCost("NOPE", 0), nil)
	end)

	test("ganancias offline: 50%, tope de 8 h y sin recompensas con relojes raros", function()
		local h = Fixtures.server()
		local Offline = Fixtures.logic(h, "OfflineEarnings")
		local now = 2_000_000
		expect.equal((Offline.compute(now - 3600, now, 10)), 18000) -- 1 h * 10/s * 50%
		expect.equal((Offline.compute(now - 100 * 3600, now, 10)), 8 * 3600 * 10 * 0.5) -- tope 8 h
		expect.equal((Offline.compute(now - 30, now, 10)), 0) -- menos del mínimo
		expect.equal((Offline.compute(now + 5000, now, 10)), 0) -- reloj hacia atrás
		expect.equal((Offline.compute(0, now, 10)), 0) -- sin guardado previo
		expect.equal((Offline.compute(now - 3600, now, 0 / 0)), 0)
		expect.equal((Offline.compute(now - 3600, now, math.huge)), 0)
		expect.equal((Offline.compute(now - 3600, now, -5)), 0)
		expect.equal((Offline.compute("x", now, 5)), 0)
	end)

	test("formatNumber y formatTime", function()
		local h = Fixtures.server()
		local U = h:require("ReplicatedStorage.Shared.Utilities")
		expect.equal(U.formatNumber(0), "0")
		expect.equal(U.formatNumber(999), "999")
		expect.equal(U.formatNumber(1234), "1.23K")
		expect.equal(U.formatNumber(1500000), "1.5M")
		expect.equal(U.formatNumber(2e9), "2B")
		expect.equal(U.formatNumber(0 / 0), "0")
		expect.equal(U.formatTime(75), "1:15")
		expect.equal(U.formatTime(3725), "1h 2m")
	end)

	TestKit.suite("Economía: servidor")

	test("una compra válida descuenta exactamente el precio y añade la comida", function()
		local h, s = Fixtures.server()
		local player, session = h:joinPlayer(1, "Ana")
		expect.equal(session.profile.coins, 50)
		Fixtures.act(h, player, "BuyFood", "APPLE", 3) -- 6 monedas cada una
		expect.equal(session.profile.coins, 50 - 18)
		expect.equal(session.profile.inventory.APPLE, 3)
		h:step(0.05)
		expect.equal(h:stateFor(1).coins, 32, "el cliente recibe el saldo")
		expect.equal(h:stateFor(1).inventory.APPLE, 3)
	end)

	test("una compra inválida no modifica el saldo ni el inventario", function()
		local h, s = Fixtures.server()
		local player, session = h:joinPlayer(1, "Ana")
		local function unchanged(label)
			expect.equal(session.profile.coins, 50, label .. " (saldo)")
			expect.equal(Fixtures.count(session.profile.inventory), 0, label .. " (inventario)")
		end
		Fixtures.act(h, player, "BuyFood", "PIZZA", 2) -- 60 > 50
		unchanged("sin monedas")
		Fixtures.act(h, player, "BuyFood", "GOLDEN_APPLE", 1) -- no se vende
		unchanged("no en venta")
		Fixtures.act(h, player, "BuyFood", "DINO_STEAK", 1) -- requiere licencia
		unchanged("bloqueada")
		Fixtures.act(h, player, "BuyFood", "NOPE", 1)
		unchanged("inexistente")
		-- Argumentos mal formados: ni siquiera llegan al servicio.
		for _, bad in ipairs({ 0, -1, 1.5, 51, 0 / 0, math.huge, "3" }) do
			Fixtures.act(h, player, "BuyFood", "APPLE", bad)
			unchanged("cantidad " .. tostring(bad))
		end
		Fixtures.act(h, player, "BuyFood", { "APPLE" }, 1)
		unchanged("id tabla")
		Fixtures.act(h, player, "BuyFood", "APPLE", 1, "extra")
		unchanged("argumentos de más")
		Fixtures.act(h, player, "BuyFood")
		unchanged("sin argumentos")
	end)

	test("comprar más de lo que cabe solo cobra lo que cabe", function()
		local h, s = Fixtures.server()
		local player, session = h:joinPlayer(1, "Ana")
		s.EconomyService.addCoins(1, 1000)
		s.FoodService.give(session, "CARROT", 8) -- capacidad 10
		local before = session.profile.coins
		Fixtures.act(h, player, "BuyFood", "APPLE", 10)
		expect.equal(session.profile.inventory.APPLE, 2)
		expect.equal(session.profile.coins, before - 12)
		Fixtures.act(h, player, "BuyFood", "APPLE", 1) -- llena
		expect.equal(session.profile.coins, before - 12)
	end)

	test("spend/addCoins rechazan cantidades no válidas y el saldo nunca es negativo", function()
		local h, s = Fixtures.server()
		local player, session = h:joinPlayer(1, "Ana")
		local E = s.EconomyService
		expect.falsy(E.spend(1, 51))
		expect.falsy(E.spend(1, -5))
		expect.falsy(E.spend(1, 0 / 0))
		expect.falsy(E.spend(1, math.huge))
		expect.equal(session.profile.coins, 50)
		expect.truthy(E.spend(1, 50))
		expect.equal(session.profile.coins, 0)
		expect.falsy(E.spend(1, 1))
		expect.equal(E.addCoins(1, -10), 0)
		expect.equal(E.addCoins(1, 0 / 0), 0)
		expect.equal(E.addCoins(1, math.huge), 0)
		expect.equal(session.profile.coins, 0)
		expect.equal(E.addCoins(1, 10.9), 10)
		E.addCoins(1, 1e18)
		expect.equal(session.profile.coins, 1e15, "tope de monedas")
		expect.equal(E.spend(999, 1), false, "jugador sin sesión")
		expect.equal(E.addCoins(999, 5), 0)
	end)

	test("las criaturas producen monedas; se recogen una sola vez en la zona dorada", function()
		local h, s = Fixtures.server()
		local player, session = h:joinPlayer(1, "Ana")
		h:step(1, 10)
		local pending = session.profile.pendingCoins
		expect.near(pending, 10, 1.01, "≈1 moneda/s")
		expect.equal(session.profile.coins, 50, "todavía sin recoger")
		local plot = s.PlotService.plot(session.plotIndex)
		expect.equal(plot.model:GetAttribute("Pending"), math.floor(pending), "indicador de la parcela")
		Fixtures.goTo(h, player, plot.collectPos)
		h:step(0.2, 2)
		local collected = session.profile.coins - 50
		expect.truthy(collected >= 9 and collected <= 11, "recogido " .. collected)
		expect.truthy(session.profile.pendingCoins < 1.5, "pendiente vaciado")
		expect.truthy(session.profile.flags.firstCollect, "flag de tutorial")
		-- Quedarse quieto no vuelve a pagar lo mismo.
		local after = session.profile.coins
		h:step(0.05, 4)
		expect.equal(session.profile.coins, after)
		expect.equal(s.EconomyService.collect(999), 0)
	end)

	test("las ganancias pendientes tienen tope", function()
		local h, s = Fixtures.server()
		local player, session = h:joinPlayer(1, "Ana")
		h:step(60, 100) -- 6000 s a 1/s
		local Math = Fixtures.logic(h, "EconomyMath")
		expect.equal(session.profile.pendingCoins, Math.pendingCap(1))
		expect.equal(Math.pendingCap(1), 1800)
		expect.equal(Math.pendingCap(0), 250)
	end)

	test("mejoras: se cobran, suben de nivel y no pasan del máximo", function()
		local h, s = Fixtures.server()
		local player, session = h:joinPlayer(1, "Ana")
		Fixtures.act(h, player, "BuyUpgrade", "INVENTORY") -- 40
		expect.equal(session.profile.coins, 10)
		expect.equal(session.profile.upgrades.INVENTORY, 1)
		Fixtures.act(h, player, "BuyUpgrade", "INVENTORY") -- 68: no llega
		expect.equal(session.profile.coins, 10)
		expect.equal(session.profile.upgrades.INVENTORY, 1)
		s.EconomyService.addCoins(1, 1e9)
		for _ = 1, 12 do
			Fixtures.act(h, player, "BuyUpgrade", "HARVEST")
		end
		expect.equal(session.profile.upgrades.HARVEST, 5)
		local before = session.profile.coins
		Fixtures.act(h, player, "BuyUpgrade", "HARVEST")
		expect.equal(session.profile.coins, before, "al máximo no cobra")
		Fixtures.act(h, player, "BuyUpgrade", "NOPE")
		expect.equal(session.profile.coins, before)
		-- La mejora de producción cambia los ingresos de inmediato.
		local income = s.EconomyService.income(session)
		Fixtures.act(h, player, "BuyUpgrade", "PRODUCTION")
		expect.near(s.EconomyService.income(session), income * 1.1)
	end)

	test("la primera mejora es asequible con las monedas iniciales (inicio rápido)", function()
		local h = Fixtures.server()
		local Math = Fixtures.logic(h, "EconomyMath")
		local GameConfig = Fixtures.config(h, "GameConfig")
		expect.atMost(Math.upgradeCost("INVENTORY", 0), GameConfig.StartingCoins)
	end)

	test("vender: paga el valor calculado en servidor y nunca la última criatura", function()
		local h, s = Fixtures.server()
		local player, session = h:joinPlayer(1, "Ana")
		local _, firstId = Fixtures.firstCreature(session)
		Fixtures.act(h, player, "SellCreature", firstId)
		expect.equal(Fixtures.count(session.profile.creatures), 1, "no vende la última")
		local extra = s.CreatureService.add(session, "CHOMPITO", "GOLDEN")
		local Math = Fixtures.logic(h, "EconomyMath")
		local value = Math.sellValue(extra, 50)
		expect.equal(value, math.floor(220 * 3 * 0.5))
		Fixtures.act(h, player, "SellCreature", extra.id)
		expect.equal(session.profile.coins, 50 + value)
		expect.equal(session.profile.creatures[extra.id], nil)
		-- Repetir la petición no paga dos veces.
		Fixtures.act(h, player, "SellCreature", extra.id)
		expect.equal(session.profile.coins, 50 + value)
	end)

	test("ganancias offline: se conceden una vez al volver y se reclaman una vez", function()
		local h, s = Fixtures.server()
		local player, session = h:joinPlayer(1, "Ana")
		h:removePlayer(player)
		local saved = Fixtures.saved(h, 1)
		expect.truthy(saved, "perfil guardado")
		expect.equal(saved.session, nil, "bloqueo liberado")
		h:advance(2 * 3600)
		local player2, session2 = h:joinPlayer(1, "Ana")
		-- 2 h * 1 moneda/s * 50%
		expect.equal(session2.profile.pendingOffline, 3600)
		expect.equal(session2.profile.coins, 50, "no se suman solas")
		Fixtures.act(h, player2, "ClaimOffline")
		expect.equal(session2.profile.coins, 50 + 3600)
		expect.equal(session2.profile.pendingOffline, 0)
		Fixtures.act(h, player2, "ClaimOffline")
		expect.equal(session2.profile.coins, 50 + 3600, "no se reclama dos veces")
	end)

	test("ganancias offline: salir y entrar rápido no acumula; el tope es de 8 h", function()
		local h, s = Fixtures.server()
		local player, session = h:joinPlayer(1, "Ana")
		h:removePlayer(player)
		h:advance(20)
		local player2, session2 = h:joinPlayer(1, "Ana")
		expect.equal(session2.profile.pendingOffline, 0, "reconexión rápida")
		h:removePlayer(player2)
		h:advance(40 * 3600)
		local _, session3 = h:joinPlayer(1, "Ana")
		expect.equal(session3.profile.pendingOffline, 8 * 3600 * 0.5, "tope 8 h al 50%")
	end)

	test("las ganancias offline sin reclamar sobreviven a otra desconexión sin duplicarse", function()
		local h, s = Fixtures.server()
		local player = h:joinPlayer(1, "Ana")
		h:removePlayer(player)
		h:advance(3600)
		local player2, session2 = h:joinPlayer(1, "Ana")
		expect.equal(session2.profile.pendingOffline, 1800)
		h:removePlayer(player2)
		h:advance(5) -- vuelve enseguida: no debe sumarse otra hora
		local _, session3 = h:joinPlayer(1, "Ana")
		expect.equal(session3.profile.pendingOffline, 1800)
	end)

	test("rate limiting: una ráfaga de compras no pasa del límite", function()
		local h, s = Fixtures.server()
		local player, session = h:joinPlayer(1, "Ana")
		s.EconomyService.addCoins(1, 10000)
		s.ShopService.buyUpgrade(session, "INVENTORY")
		s.ShopService.buyUpgrade(session, "INVENTORY")
		s.ShopService.buyUpgrade(session, "INVENTORY") -- capacidad 25
		h:advance(5)
		for _ = 1, 30 do
			h:fire(player, "BuyFood", "APPLE", 1)
		end
		expect.equal(session.profile.inventory.APPLE, 8, "burst = 8")
		expect.greater(s.ValidationService.rejectedCount(1), 0)
	end)
end
