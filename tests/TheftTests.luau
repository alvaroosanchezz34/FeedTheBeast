--!nocheck
local TestKit = require("./lib/TestKit")
local Fixtures = require("./lib/Fixtures")
local Harness = require("./lib/Harness")
local expect = TestKit.expect
local test = TestKit.test
local V3 = Fixtures.Vector3

return function()
	TestKit.suite("Robo: máquina de estados (pura)")

	local function machineLib()
		local h = Fixtures.server()
		return Fixtures.logic(h, "StealStateMachine")
	end

	test("solo existen las transiciones permitidas y DELIVERED es terminal", function()
		local M = machineLib()
		local S = M.States
		expect.truthy(M.canTransition(S.AVAILABLE, S.CARRIED))
		expect.truthy(M.canTransition(S.CARRIED, S.BEING_STOLEN))
		expect.truthy(M.canTransition(S.BEING_STOLEN, S.RECOVERED))
		expect.falsy(M.canTransition(S.AVAILABLE, S.BEING_STOLEN), "no se roba del suelo")
		expect.falsy(M.canTransition(S.AVAILABLE, S.DELIVERED), "no se entrega sin llevarla")
		expect.falsy(M.canTransition(S.PROTECTED, S.BEING_STOLEN), "protegida no se roba")
		for _, to in pairs(S) do
			expect.falsy(M.canTransition(S.DELIVERED, to), "DELIVERED -> " .. to)
		end
		expect.falsy(M.canTransition("NOPE", S.CARRIED))
	end)

	test("ciclo completo: recoger, robar, recuperar y entregar", function()
		local M = machineLib()
		local S = M.States
		local m = M.new("c1", "WOOD")
		expect.falsy(m:beginSteal(2, 0), "en el suelo no se puede robar")
		expect.truthy(m:pickup(1, 0, 0))
		expect.falsy(m:pickup(2, 0, 0), "ya la lleva alguien")
		expect.equal(m.state, S.CARRIED)
		local ok, reason = m:beginSteal(1, 1)
		expect.falsy(ok)
		expect.equal(reason, "own_crate")
		expect.truthy(m:beginSteal(2, 1))
		expect.equal(m.state, S.BEING_STOLEN)
		expect.falsy(m:beginSteal(3, 1), "solo un ladrón a la vez")
		local okc, info = m:completeSteal(3, 2, 3, 25)
		expect.falsy(okc, "otro jugador no puede completar el robo ajeno")
		okc, info = m:completeSteal(2, 2, 3, 25)
		expect.truthy(okc)
		expect.equal(info.victim, 1)
		expect.falsy(info.recovered)
		expect.equal(m.state, S.PROTECTED)
		expect.equal(m.carrier, 2)
		-- Durante la inmunidad nadie la roba.
		ok, reason = m:beginSteal(1, 3)
		expect.falsy(ok)
		expect.equal(reason, "protected")
		-- Pasada la inmunidad, la víctima la recupera dentro de la ventana.
		expect.truthy(m:beginSteal(1, 6))
		okc, info = m:completeSteal(1, 7, 3, 25)
		expect.truthy(okc)
		expect.truthy(info.recovered, "cuenta como recuperación")
		expect.equal(m.carrier, 1)
		-- Entrega: la recogió originalmente el propio 1, así que no es un atraco.
		local okd, dinfo = m:deliver(1)
		expect.truthy(okd)
		expect.falsy(dinfo.stolen)
		expect.equal(m.state, S.DELIVERED)
		expect.falsy(m:deliver(1), "no se entrega dos veces")
		expect.falsy(m:pickup(1, 9, 0))
		expect.falsy(m:drop())
		expect.equal(m:playerLeft(1), nil)
	end)

	test("entregar una caja robada cuenta como atraco; la víctima protegida no se roba", function()
		local M = machineLib()
		local m = M.new("c1", "WOOD")
		m:pickup(1, 0, 0)
		local ok, reason = m:beginSteal(2, 1, { victimProtected = true })
		expect.falsy(ok)
		expect.equal(reason, "victim_protected")
		m:beginSteal(2, 1)
		m:completeSteal(2, 2, 0, 25)
		expect.falsy(m:deliver(1), "quien ya no la lleva no la entrega")
		local okd, info = m:deliver(2)
		expect.truthy(okd)
		expect.truthy(info.stolen)
	end)

	test("cancelar un robo y desconexiones dejan un estado coherente", function()
		local M = machineLib()
		local S = M.States
		local m = M.new("c1", "WOOD")
		m:pickup(1, 0, 0)
		m:beginSteal(2, 1)
		expect.falsy(m:cancelSteal(3), "otro jugador no cancela")
		expect.truthy(m:cancelSteal(2))
		expect.equal(m.state, S.CARRIED)
		-- El ladrón se va a mitad del robo.
		m:beginSteal(2, 2)
		expect.equal(m:playerLeft(2), "cancelled")
		expect.equal(m.state, S.CARRIED)
		expect.equal(m.carrier, 1)
		-- El portador se va mientras le roban: la caja cae, no pasa al ladrón.
		m:beginSteal(2, 3)
		expect.equal(m:playerLeft(1), "dropped")
		expect.equal(m.state, S.AVAILABLE)
		expect.equal(m.carrier, nil)
		expect.equal(m.thief, nil)
		expect.falsy(m:completeSteal(2, 4, 3, 25), "el robo en curso ya no se puede completar")
		-- Y vuelve a estar disponible para cualquiera.
		expect.truthy(m:pickup(3, 5, 2))
		expect.equal(m.state, S.PROTECTED)
		expect.falsy(m:tick(6))
		expect.truthy(m:tick(7.1))
		expect.equal(m.state, S.CARRIED)
	end)

	TestKit.suite("Robo: servidor")

	local function setup()
		local h, s = Fixtures.server()
		local ana, anaSession = h:joinPlayer(1, "Ana")
		local beto, betoSession = h:joinPlayer(2, "Beto")
		-- Fuera de la protección de novatos.
		h:advance(300)
		return h, s, ana, anaSession, beto, betoSession
	end

	local function crateCount(s)
		return Fixtures.count(s.TheftService.debugCrates())
	end

	local function hold(h, player, entry)
		Harness.signalOf(entry.prompt, "PromptButtonHoldBegan"):Fire(player)
		h:settle(2)
	end

	local function trigger(h, player, entry)
		Harness.signalOf(entry.prompt, "Triggered"):Fire(player)
		h:settle(2)
	end

	local function steal(h, player, entry)
		hold(h, player, entry)
		h:advance(0.75)
		trigger(h, player, entry)
	end

	local SPOT = V3.new(30, 1.9, 30)

	test("se recoge por proximidad, una por jugador, y transportarla ralentiza", function()
		local h, s, ana, anaSession = setup()
		local entry = s.TheftService.spawnCrate("WOOD", SPOT)
		local second = s.TheftService.spawnCrate("WOOD", SPOT + V3.new(2, 0, 0))
		expect.equal(s.CharacterService.speedOf(1), 18)
		h:moveTo(ana, SPOT + V3.new(0, 3, 40))
		h:step(0.2, 2)
		expect.equal(entry.machine.state, "AVAILABLE", "lejos no se recoge")
		h:moveTo(ana, SPOT + V3.new(0, 3, 0))
		h:step(0.2, 3)
		local carried = s.TheftService.carriedBy(1)
		expect.truthy(carried, "lleva una caja")
		local other = carried == entry and second or entry
		expect.equal(other.machine.state, "AVAILABLE", "solo una caja a la vez")
		expect.equal(carried.part:GetAttribute("CarrierUserId"), 1)
		expect.near(s.CharacterService.speedOf(1), 18 * 0.78, 1e-6)
		expect.greater(s.CharacterService.speedOf(1), 18 * 0.6, "el castigo no impide escapar")
	end)

	test("robar exige cercanía real, mantener el botón y respeta el cooldown", function()
		local h, s, ana, anaSession, beto, betoSession = setup()
		local entry = s.TheftService.spawnCrate("WOOD", SPOT)
		h:moveTo(ana, SPOT + V3.new(0, 3, 0))
		h:step(0.2, 3)
		expect.equal(entry.machine.carrier, 1)
		expect.truthy(entry.prompt.Enabled, "el prompt de robo se activa al llevarla")
		-- Lejos: aunque el cliente dispare el prompt, el servidor lo rechaza.
		h:moveTo(beto, SPOT + V3.new(60, 3, 0))
		steal(h, beto, entry)
		expect.equal(entry.machine.carrier, 1)
		expect.equal(entry.machine.state, "CARRIED")
		-- Cerca pero soltando demasiado pronto.
		h:moveTo(beto, SPOT + V3.new(4, 3, 0))
		hold(h, beto, entry)
		expect.equal(entry.machine.state, "BEING_STOLEN")
		h:advance(0.1)
		trigger(h, beto, entry)
		expect.equal(entry.machine.carrier, 1, "sin mantener el tiempo no hay robo")
		expect.equal(entry.machine.state, "CARRIED")
		-- Robo correcto.
		steal(h, beto, entry)
		expect.equal(entry.machine.carrier, 2)
		expect.equal(entry.machine.state, "PROTECTED")
		expect.equal(s.TheftService.carriedBy(1), nil)
		expect.equal(s.TheftService.carriedBy(2), entry)
		expect.equal(betoSession.profile.stats.cratesStolen, 1)
		expect.equal(s.CharacterService.speedOf(1), 18, "la víctima recupera su velocidad")
		expect.equal(crateCount(s), 1, "ni se duplica ni desaparece")
		-- La víctima recibe la alerta.
		local alert = Fixtures.lastNotification(h, 1)
		expect.equal(alert.kind, "alert")
		-- Inmunidad tras el traspaso.
		steal(h, ana, entry)
		expect.equal(entry.machine.carrier, 2, "protegida 3 s")
	end)

	test("recuperar la caja propia da bonificación y cuenta como recuperación", function()
		local h, s, ana, anaSession, beto, betoSession = setup()
		local entry = s.TheftService.spawnCrate("WOOD", SPOT)
		h:moveTo(ana, SPOT + V3.new(0, 3, 0))
		h:step(0.2, 3)
		h:moveTo(beto, SPOT + V3.new(4, 3, 0))
		steal(h, beto, entry)
		expect.equal(entry.machine.carrier, 2)
		h:step(0.2, 20) -- 4 s: termina la inmunidad
		expect.equal(entry.machine.state, "CARRIED")
		local coins = anaSession.profile.coins
		steal(h, ana, entry)
		expect.equal(entry.machine.carrier, 1)
		expect.equal(anaSession.profile.stats.cratesRecovered, 1)
		expect.equal(anaSession.profile.stats.cratesStolen, 0)
		expect.greater(anaSession.profile.coins, coins, "bonus de recuperación")
		expect.equal(crateCount(s), 1)
	end)

	test("cooldown de robo por ladrón", function()
		local h, s, ana, anaSession, beto, betoSession = setup()
		local carla = h:joinPlayer(3, "Carla")
		h:advance(300)
		local a = s.TheftService.spawnCrate("WOOD", SPOT)
		h:moveTo(ana, SPOT + V3.new(0, 3, 0))
		h:step(0.2, 3)
		local b = s.TheftService.spawnCrate("WOOD", SPOT + V3.new(0, 0, 60))
		h:moveTo(carla, SPOT + V3.new(0, 3, 60))
		h:step(0.2, 3)
		expect.equal(b.machine.carrier, 3)
		h:moveTo(beto, SPOT + V3.new(4, 3, 0))
		steal(h, beto, a)
		expect.equal(a.machine.carrier, 2)
		-- Beto suelta la suya e intenta robar otra inmediatamente.
		h:fire(beto, "DropCrate")
		expect.equal(a.machine.state, "AVAILABLE")
		h:moveTo(beto, SPOT + V3.new(4, 3, 60))
		steal(h, beto, b)
		expect.equal(b.machine.carrier, 3, "cooldown activo")
		h:advance(5)
		steal(h, beto, b)
		expect.equal(b.machine.carrier, 2, "pasado el cooldown sí")
	end)

	test("los jugadores nuevos están protegidos", function()
		local h, s = Fixtures.server()
		local ana, anaSession = h:joinPlayer(1, "Ana")
		local beto = h:joinPlayer(2, "Beto")
		local entry = s.TheftService.spawnCrate("WOOD", SPOT)
		h:moveTo(ana, SPOT + V3.new(0, 3, 0))
		h:step(0.2, 3)
		h:moveTo(beto, SPOT + V3.new(4, 3, 0))
		steal(h, beto, entry)
		expect.equal(entry.machine.carrier, 1)
		expect.equal(Fixtures.lastNotification(h, 2).text, "That player is new and protected.")
		expect.greater(h:stateFor(1).protection, 0, "el cliente conoce su protección")
	end)

	test("entregar en la propia zona azul recompensa una sola vez", function()
		local h, s, ana, anaSession = setup()
		local entry = s.TheftService.spawnCrate("WOOD", SPOT)
		h:moveTo(ana, SPOT + V3.new(0, 3, 0))
		h:step(0.2, 3)
		local coins = anaSession.profile.coins
		local pending = anaSession.profile.pendingCoins
		local plot = s.PlotService.plot(anaSession.plotIndex)
		-- Teletransportarse con la caja la hace caer (anti-trampas); hay que llevarla andando.
		Fixtures.goTo(h, ana, plot.deliveryPos)
		h:step(0.5, 2)
		expect.equal(entry.machine.state, "AVAILABLE", "el salto imposible suelta la caja")
		expect.equal(anaSession.profile.coins, coins)
		expect.truthy(Fixtures.hasWarning(h, "while carrying"), "queda registrado")
		-- Ahora de verdad: recoger y caminar a velocidad válida.
		h:moveTo(ana, entry.position + V3.new(0, 3, 0))
		h:step(0.2, 12)
		expect.equal(entry.machine.carrier, 1)
		local from = h:positionOf(ana)
		local to = plot.deliveryPos + V3.new(0, 3, 0)
		local distance = (to - from).Magnitude
		local steps = math.ceil(distance / (14 * 0.25))
		for i = 1, steps do
			h:moveTo(ana, from:Lerp(to, i / steps))
			h:step(0.25, 1)
		end
		h:step(0.2, 3)
		expect.equal(entry.machine.state, "DELIVERED")
		expect.equal(crateCount(s), 0, "la caja desaparece al entregarla")
		expect.equal(s.TheftService.carriedBy(1), nil)
		expect.equal(anaSession.profile.stats.cratesDelivered, 1)
		local gained = anaSession.profile.coins - coins
		expect.truthy(gained >= 70, "recompensa de monedas: " .. gained)
		local foods = 0
		for _, n in pairs(anaSession.profile.inventory) do
			foods += n
		end
		expect.equal(foods, 3, "tres comidas")
		expect.equal(s.CharacterService.speedOf(1), 18)
		-- Seguir en la zona no vuelve a pagar.
		local after = anaSession.profile.coins
		h:step(0.2, 5)
		expect.equal(anaSession.profile.coins, after)
		expect.falsy(s.TheftService.tryDeliver(1))
	end)

	test("no se puede entregar en la zona de otro jugador ni lejos de la propia", function()
		local h, s, ana, anaSession, beto, betoSession = setup()
		local entry = s.TheftService.spawnCrate("WOOD", SPOT)
		h:moveTo(ana, SPOT + V3.new(0, 3, 0))
		h:step(0.2, 3)
		expect.falsy(s.TheftService.tryDeliver(1), "lejos de la zona")
		expect.equal(entry.machine.state, "CARRIED")
		expect.falsy(s.TheftService.tryDeliver(2), "quien no lleva nada no entrega")
		expect.equal(crateCount(s), 1)
	end)

	test("si el portador se desconecta la caja cae donde estaba; no se pierde ni se duplica", function()
		local h, s, ana, anaSession, beto = setup()
		local entry = s.TheftService.spawnCrate("SILVER", SPOT)
		h:moveTo(ana, SPOT + V3.new(0, 3, 0))
		h:step(0.2, 3)
		h:moveTo(beto, SPOT + V3.new(4, 3, 0))
		hold(h, beto, entry) -- robo en curso cuando Ana se va
		expect.equal(entry.machine.state, "BEING_STOLEN")
		h:removePlayer(ana)
		expect.equal(entry.machine.state, "AVAILABLE")
		expect.equal(entry.machine.carrier, nil)
		expect.equal(crateCount(s), 1)
		expect.truthy(entry.part.Anchored, "queda en el suelo")
		expect.near(entry.position.X, SPOT.X, 1)
		-- El robo que estaba en curso no se puede completar a posteriori.
		h:advance(0.75)
		trigger(h, beto, entry)
		expect.equal(s.TheftService.carriedBy(2), nil)
		-- Beto puede recogerla del suelo normalmente.
		h:moveTo(beto, entry.position + V3.new(0, 3, 0))
		h:step(0.2, 3)
		expect.equal(entry.machine.carrier, 2)
		expect.equal(crateCount(s), 1)
	end)

	test("si el ladrón se desconecta a mitad, el robo se cancela y la víctima conserva la caja", function()
		local h, s, ana, anaSession, beto = setup()
		local entry = s.TheftService.spawnCrate("WOOD", SPOT)
		h:moveTo(ana, SPOT + V3.new(0, 3, 0))
		h:step(0.2, 3)
		h:moveTo(beto, SPOT + V3.new(4, 3, 0))
		hold(h, beto, entry)
		h:removePlayer(beto)
		expect.equal(entry.machine.state, "CARRIED")
		expect.equal(entry.machine.carrier, 1)
		expect.equal(s.TheftService.carriedBy(1), entry)
	end)

	test("morir o soltar deja la caja en el suelo; un robo abandonado caduca", function()
		local h, s, ana, anaSession, beto = setup()
		local entry = s.TheftService.spawnCrate("WOOD", SPOT)
		h:moveTo(ana, SPOT + V3.new(0, 3, 0))
		h:step(0.2, 3)
		h:moveTo(beto, SPOT + V3.new(4, 3, 0))
		hold(h, beto, entry) -- y nunca termina
		h:step(0.2, 15)
		expect.equal(entry.machine.state, "CARRIED", "el robo abandonado se cancela solo")
		h:kill(ana)
		expect.equal(entry.machine.state, "AVAILABLE")
		expect.equal(s.TheftService.carriedBy(1), nil)
		expect.equal(crateCount(s), 1)
	end)

	test("las cajas del suelo caducan y el generador respeta el máximo", function()
		local h, s = Fixtures.server({ crates = true })
		local ana = h:joinPlayer(1, "Ana")
		local TheftConfig = Fixtures.config(h, "TheftConfig")
		TheftConfig.SpawnInterval = 1
		h:step(0.5, 30)
		expect.equal(crateCount(s), TheftConfig.MaxActive)
		TheftConfig.SpawnInterval = math.huge
		h:step(1, TheftConfig.GroundLifetime + 5)
		expect.equal(crateCount(s), 0)
	end)

	test("el contenido de las cajas sale de su tabla de rarezas", function()
		local h, s, ana, anaSession = setup()
		local FoodConfig = Fixtures.config(h, "FoodConfig")
		local TheftConfig = Fixtures.config(h, "TheftConfig")
		local Rolls = Fixtures.logic(h, "Rolls")
		local rng = h.Random.new(5)
		local function rnd()
			return rng:NextNumber()
		end
		for _, tierId in ipairs(TheftConfig.TierOrder) do
			local tier = TheftConfig.Tiers[tierId]
			for _ = 1, 300 do
				local rarity = Rolls.weighted(tier.rarities, rnd)
				local foodId = Rolls.foodOfRarity(rarity, rnd)
				expect.truthy(foodId, tierId .. " sin comida de rareza " .. tostring(rarity))
				expect.equal(FoodConfig.Foods[foodId].rarity, rarity)
				expect.greater(FoodConfig.Foods[foodId].price, 0, "nunca comida exclusiva de evento")
			end
		end
	end)
end
