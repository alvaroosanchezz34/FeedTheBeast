--!nocheck
local TestKit = require("./lib/TestKit")
local Fixtures = require("./lib/Fixtures")
local expect = TestKit.expect
local test = TestKit.test

return function()
	TestKit.suite("Monetización")

	local function receipt(purchaseId, productId, playerId)
		return { PurchaseId = purchaseId, ProductId = productId, PlayerId = playerId or 1, CurrencySpent = 49 }
	end

	local function setup(configure)
		local h, s = Fixtures.server({
			before = function(h)
				local Config = Fixtures.config(h, "MonetizationConfig")
				if configure then
					configure(Config, h)
				end
			end,
		})
		local Config = Fixtures.config(h, "MonetizationConfig")
		return h, s, Config
	end

	local function decide(h, info)
		local decision = h.marketplace.ProcessReceipt(info)
		h:settle(2)
		return decision.Name
	end

	test("todos los IDs son placeholders explícitos (0) y no hay ninguno inventado", function()
		local h, s, Config = setup()
		for key, def in pairs(Config.GamePasses) do
			expect.equal(def.id, 0, "pase " .. key)
			expect.falsy(Config.isConfigured(def))
		end
		for key, def in pairs(Config.Products) do
			expect.equal(def.id, 0, "producto " .. key)
			expect.falsy(Config.isConfigured(def))
		end
		expect.equal(Config.productById(0), nil, "un id 0 nunca identifica un producto")
		expect.equal(Config.PLACEHOLDER_ID, 0)
	end)

	test("con placeholders no se concede nada: los recibos quedan sin procesar", function()
		local h, s = setup()
		local player, session = h:joinPlayer(1, "Ana")
		expect.equal(type(h.marketplace.ProcessReceipt), "function", "ProcessReceipt instalado")
		expect.equal(decide(h, receipt("p1", 0)), "NotProcessedYet")
		expect.equal(decide(h, receipt("p2", 123456)), "NotProcessedYet")
		expect.equal(Fixtures.count(session.profile.boosts), 0)
		expect.equal(#session.profile.receipts, 0)
		expect.truthy(Fixtures.hasWarning(h, "not granted"), "queda registrado")
	end)

	test("un producto configurado se concede una sola vez y solo tras guardarse", function()
		local h, s, Config = setup(function(Config)
			Config.Products.GROWTH_BOOST.id = 555
		end)
		local player, session = h:joinPlayer(1, "Ana")
		local now = h.clock.unix
		expect.equal(decide(h, receipt("abc", 555)), "PurchaseGranted")
		expect.near(session.profile.boosts.Growth, now + 900, 2)
		expect.equal(#session.profile.receipts, 1)
		local saved = Fixtures.saved(h, 1)
		expect.equal(saved.receipts[1], "abc", "el recibo se persiste junto con la recompensa")
		expect.near(saved.boosts.Growth, now + 900, 2)
		-- Roblox reintenta el mismo recibo: no se concede dos veces.
		local expires = session.profile.boosts.Growth
		expect.equal(decide(h, receipt("abc", 555)), "PurchaseGranted")
		expect.equal(session.profile.boosts.Growth, expires)
		expect.equal(#session.profile.receipts, 1)
		-- Una compra distinta sí acumula tiempo.
		expect.equal(decide(h, receipt("def", 555)), "PurchaseGranted")
		expect.near(session.profile.boosts.Growth, expires + 900, 2)
	end)

	test("si el guardado falla no se confirma la compra, y el reintento no duplica la recompensa", function()
		local h, s, Config = setup(function(Config)
			Config.Products.GROWTH_BOOST.id = 555
		end)
		local player, session = h:joinPlayer(1, "Ana")
		h.datastore.failAlways = true
		expect.equal(decide(h, receipt("abc", 555)), "NotProcessedYet")
		local expires = session.profile.boosts.Growth
		expect.truthy(expires, "la recompensa está en memoria...")
		h.datastore.failAlways = false
		expect.equal(decide(h, receipt("abc", 555)), "PurchaseGranted")
		expect.equal(session.profile.boosts.Growth, expires, "...pero no se suma otra vez")
		expect.equal(Fixtures.saved(h, 1).receipts[1], "abc")
	end)

	test("recibos de jugadores ausentes o mal formados no conceden nada", function()
		local h, s, Config = setup(function(Config)
			Config.Products.GROWTH_BOOST.id = 555
		end)
		expect.equal(decide(h, receipt("abc", 555, 42)), "NotProcessedYet") -- no está en el servidor
		local player, session = h:joinPlayer(1, "Ana")
		expect.equal(decide(h, { PurchaseId = 5, ProductId = 555, PlayerId = 1 }), "NotProcessedYet")
		expect.equal(decide(h, { PurchaseId = "x", ProductId = "555", PlayerId = 1 }), "NotProcessedYet")
		expect.equal(Fixtures.count(session.profile.boosts), 0)
	end)

	test("el boost de crecimiento duplica el crecimiento mientras dura y tiene tope de acumulación", function()
		local h, s, Config = setup(function(Config)
			Config.Products.GROWTH_BOOST.id = 555
		end)
		local player, session = h:joinPlayer(1, "Ana")
		local creature, id = Fixtures.firstCreature(session)
		decide(h, receipt("abc", 555))
		s.FoodService.give(session, "APPLE", 2)
		Fixtures.goToCreature(h, s, player, session, id)
		Fixtures.act(h, player, "Feed", id, "APPLE")
		expect.equal(creature.growth, 10, "x2")
		h:advance(1000) -- caduca
		Fixtures.act(h, player, "Feed", id, "APPLE")
		expect.equal(creature.growth, 15, "sin boost")
		local Receipt = Fixtures.logic(h, "ReceiptLogic")
		for i = 1, 200 do
			Receipt.process(session.profile, receipt("r" .. i, 555), h.clock.unix)
		end
		expect.atMost(session.profile.boosts.Growth, h.clock.unix + Config.MaxBoostSeconds)
		expect.atMost(#session.profile.receipts, Config.ReceiptHistory)
	end)

	test("pases: se verifican con Roblox; un error de verificación no regala el pase", function()
		local h, s, Config = setup(function(Config, h)
			Config.GamePasses.VIP.id = 777
			Config.GamePasses.EXTRA_SLOT.id = 778
			h.marketplace.passes[1] = { [777] = true }
			h.marketplace.passes[3] = { [777] = true, [778] = true }
		end)
		local ana, anaSession = h:joinPlayer(1, "Ana")
		local beto, betoSession = h:joinPlayer(2, "Beto")
		expect.equal(anaSession.passes.VIP, true)
		expect.falsy(anaSession.passes.EXTRA_SLOT)
		expect.falsy(betoSession.passes.VIP)
		expect.near(s.EconomyService.income(anaSession), 1.2, 1e-6, "+20% VIP")
		expect.near(s.EconomyService.income(betoSession), 1, 1e-6)
		expect.equal(h:stateFor(1).passes.VIP, true)
		-- Roblox no responde: nadie recibe pases que no se han podido comprobar.
		h.marketplace.failPassChecks = true
		local carla, carlaSession = h:joinPlayer(3, "Carla")
		expect.falsy(carlaSession.passes.VIP)
		expect.falsy(carlaSession.passes.EXTRA_SLOT)
		expect.equal(s.CreatureService.slotCount(carlaSession), 3)
	end)

	test("comprar un pase en partida: solo se aplica si Roblox confirma la propiedad", function()
		local h, s, Config = setup(function(Config)
			Config.GamePasses.EXTRA_SLOT.id = 778
		end)
		local ana, session = h:joinPlayer(1, "Ana")
		expect.equal(s.CreatureService.slotCount(session), 3)
		-- El evento dice "comprado" pero Roblox no lo confirma (posible evento falso).
		h.marketplace.PromptGamePassPurchaseFinished:Fire(ana, 778, true)
		h:settle(4)
		expect.falsy(session.passes.EXTRA_SLOT)
		expect.truthy(Fixtures.hasWarning(h, "could not be verified"))
		-- Compra cancelada.
		h.marketplace.passes[1] = { [778] = true }
		h.marketplace.PromptGamePassPurchaseFinished:Fire(ana, 778, false)
		h:settle(4)
		expect.falsy(session.passes.EXTRA_SLOT)
		-- Compra real.
		h.marketplace.PromptGamePassPurchaseFinished:Fire(ana, 778, true)
		h:settle(4)
		expect.equal(session.passes.EXTRA_SLOT, true)
		expect.equal(s.CreatureService.slotCount(session), 4)
		expect.equal(s.PlotService.plot(session.plotIndex).model:GetAttribute("Slots"), 4)
	end)

	test("el cosmético de parcela no da ventaja económica", function()
		local h, s, Config = setup(function(Config)
			Config.Products.PLOT_AURA.id = 556
		end)
		local ana, session = h:joinPlayer(1, "Ana")
		local income = s.EconomyService.income(session)
		expect.equal(decide(h, receipt("aura1", 556)), "PurchaseGranted")
		expect.equal(session.profile.cosmetics.PLOT_AURA, true)
		expect.equal(s.PlotService.plot(session.plotIndex).model:GetAttribute("PlotAura"), true)
		expect.equal(s.EconomyService.income(session), income)
	end)

	test("ningún producto permite robar criaturas ni concede monedas directamente", function()
		local h, s, Config = setup()
		for key, def in pairs(Config.Products) do
			expect.truthy(def.grant.type == "Boost" or def.grant.type == "Cosmetic", key)
		end
	end)
end
