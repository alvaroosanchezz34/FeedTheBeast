--!nocheck
-- Pruebas del cliente real (Bootstrap.client + controladores + interfaz) conectado al servidor
-- real dentro del mismo DataModel. Lune valida nombres y tipos de propiedades de cada instancia,
-- así que construir la interfaz aquí detecta propiedades mal escritas. NO comprueba el aspecto.
local TestKit = require("./lib/TestKit")
local Fixtures = require("./lib/Fixtures")
local Harness = require("./lib/Harness")
local expect = TestKit.expect
local test = TestKit.test
local V3 = Fixtures.Vector3

return function()
	TestKit.suite("Cliente: arranque, HUD y primer minuto")

	local function setup(opts)
		opts = opts or {}
		local h, s = Fixtures.server({ isStudio = opts.isStudio == true })
		local player, session = h:joinPlayer(1, "Ana")
		local c = h:bootClient(player, { touch = opts.touch })
		-- La cámara junto a la parcela del jugador, como en una partida real.
		h:lookAt(s.PlotService.plot(session.plotIndex).cframe.Position)
		h:tick(0.05, 6)
		local parts = c.UIController.parts()
		return h, s, player, session, c, parts
	end

	local function noProblems(h)
		for _, text in ipairs(h.warnings) do
			error("aviso inesperado: " .. text, 2)
		end
		expect.equal(#Harness.uncaught, 0, "errores en segundo plano")
	end

	local function ownEntry(c)
		for _, entry in pairs(c.CreatureController.entries()) do
			if entry.isOwn and not entry.isGiant then
				return entry
			end
		end
		return nil
	end

	local function text(root, name)
		local instance = root:FindFirstChild(name, true)
		return instance and instance.Text or nil
	end

	test("arranca sin avisos, construye la interfaz y refleja el estado del servidor", function()
		local h, s, player, session, c, parts = setup()
		noProblems(h)
		expect.truthy(parts.gui, "ScreenGui")
		expect.equal(parts.gui.Parent.Name, "PlayerGui")
		expect.equal(c.StateController.get("coins"), 50)
		expect.equal(text(parts.layers.hud, "Coins"), "50")
		expect.equal(text(parts.layers.hud, "Income"), "+1/s")
		expect.equal(text(parts.layers.hud, "Count"), "0/10")
		expect.truthy(parts.layers.hud:FindFirstChild("Empty", true).Visible, "aviso de mochila vacía")
		-- El mundo se presenta: comida, parcelas, kioscos y la criatura propia.
		local stats = c.WorldController.stats()
		expect.equal(stats.plots, 8)
		expect.equal(stats.kiosks, 4)
		expect.equal(stats.pickups, 25)
		local entry = ownEntry(c)
		expect.truthy(entry, "criatura propia visible")
		expect.truthy(entry.prompt, "con prompt de alimentar")
		expect.truthy(entry.nameplate, "y placa de nombre")
		-- Tutorial: primer objetivo y línea-guía hacia la criatura.
		expect.equal(parts.tutorial.step, "grab")
		expect.truthy(parts.layers.hud:FindFirstChild("Objective", true).Visible)
		h:tick(0.05, 2)
		expect.truthy(c.WorldController.stats().guide, "línea-guía activa")
	end)

	test("primer minuto: recoger, alimentar, ver crecer, cobrar (tutorial incluido)", function()
		local h, s, player, session, c, parts = setup()
		local creature, id = Fixtures.firstCreature(session)
		local spawn = s.PlotService.spawnCFrame(session.plotIndex)
		local target = s.CreatureService.positionOf(session, id)
		-- 1. Camina hacia la criatura: recoge la comida de bienvenida.
		for i = 0, 12 do
			h:moveTo(player, spawn.Position:Lerp(target, i / 20))
			h:tick(0.15, 1)
		end
		local inventory = c.StateController.get("inventory")
		expect.equal(Fixtures.count(inventory), 3, "tres comidas distintas en la mochila")
		expect.equal(text(parts.layers.hud, "Count"), "3/10")
		expect.equal(parts.tutorial.step, "feed")
		expect.truthy(parts.layers.hud:FindFirstChild("Food_APPLE", true), "aparece en la barra")
		expect.equal(c.WorldController.stats().pickups, s.FoodService.count(), "la comida recogida desaparece del mundo en el cliente")
		expect.equal(s.FoodService.count("starter"), 0)

		-- 2. Pulsa el prompt de su criatura.
		local entry = ownEntry(c)
		local scaleBefore = entry.targetScale
		Harness.signalOf(entry.prompt, "Triggered"):Fire()
		h:settle(4)
		Harness.signalOf(entry.prompt, "TriggerEnded"):Fire()
		h:tick(0.05, 3)
		expect.greater(creature.growth, 0, "el servidor aplicó la alimentación")
		expect.truthy(entry.eat ~= nil or entry.growAfter ~= nil or c.EffectsController.stats().active > 0, "respuesta visual inmediata")
		expect.greater(entry.targetScale, scaleBefore, "la escala objetivo sube")
		-- La favorita de GOBBLO (pan) se elige sola antes que el resto.
		expect.equal(session.profile.inventory.BREAD_CRUMB, nil, "modo automático: favorita primero")
		expect.greater(session.profile.coins, 50, "recompensa de la primera alimentación")

		-- 3. La animación termina, la criatura crece suavemente y las monedas suben en el HUD.
		h:tick(0.05, 60)
		expect.near(entry.displayScale, entry.targetScale, 0.02, "escala visual alcanzada")
		expect.equal(text(parts.layers.hud, "Coins"), tostring(session.profile.coins))
		expect.equal(parts.tutorial.step, "collect")
		expect.equal(c.EffectsController.stats().active, 0, "efectos puntuales terminados")

		-- 4. Pisa la zona dorada.
		h:tick(1, 3)
		local plot = s.PlotService.plot(session.plotIndex)
		local before = session.profile.coins
		Fixtures.goTo(h, player, plot.collectPos)
		h:tick(0.2, 3)
		expect.greater(session.profile.coins, before)
		expect.equal(parts.tutorial.step, "plaza")
		noProblems(h)

		-- 5. Tras recoger comida en la plaza y gastar, el tutorial desaparece.
		s.ShopService.buyUpgrade(session, "INVENTORY")
		h:tick(0.1, 3)
		expect.equal(parts.tutorial.step, nil)
		expect.falsy(parts.layers.hud:FindFirstChild("Objective", true).Visible)
		h:tick(0.1, 2)
		expect.falsy(c.WorldController.stats().guide, "línea-guía retirada")
	end)

	test("mantener pulsado sigue alimentando al ritmo que marca el servidor", function()
		local h, s, player, session, c = setup()
		local creature, id = Fixtures.firstCreature(session)
		session.profile.upgrades.INVENTORY = 2
		s.FoodService.give(session, "APPLE", 6)
		Fixtures.goToCreature(h, s, player, session, id)
		h:tick(0.05, 2)
		local entry = ownEntry(c)
		Harness.signalOf(entry.prompt, "Triggered"):Fire()
		h:tick(0.05, 80) -- 4 s manteniendo
		Harness.signalOf(entry.prompt, "TriggerEnded"):Fire()
		local eaten = 6 - (session.profile.inventory.APPLE or 0)
		expect.truthy(eaten >= 3 and eaten <= 5, "comió " .. eaten .. " en 4 s (0.8 s por bocado)")
		expect.equal(s.ValidationService.rejectedCount(1), 0, "sin peticiones rechazadas por spam")
		local after = session.profile.inventory.APPLE or 0
		h:tick(0.05, 40)
		expect.equal(session.profile.inventory.APPLE or 0, after, "al soltar deja de alimentar")
	end)

	test("elegir comida en la barra y aviso local si no queda", function()
		local h, s, player, session, c, parts = setup()
		local creature, id = Fixtures.firstCreature(session)
		s.FoodService.give(session, "APPLE", 1)
		s.FoodService.give(session, "PIZZA", 1)
		Fixtures.goToCreature(h, s, player, session, id)
		h:tick(0.05, 3)
		expect.equal(c.InputController.pickFood("GOBBLO"), "PIZZA", "automático: la favorita")
		expect.equal(c.InputController.pickFood("GLORB"), "APPLE", "automático: la más pequeña")
		h:click(parts.layers.hud:FindFirstChild("Food_APPLE", true))
		expect.equal(c.StateController.selectedFood(), "APPLE")
		expect.equal(c.InputController.pickFood("GOBBLO"), "APPLE", "manda la selección")
		h:click(parts.layers.hud:FindFirstChild("Food_APPLE", true))
		expect.equal(c.StateController.selectedFood(), nil, "tocar de nuevo vuelve a automático")
		-- Sin comida: no se envía nada y se avisa en local.
		session.profile.inventory = {}
		s.StateService.push(1, "inventory")
		h:tick(0.05, 3)
		expect.falsy(c.InputController.feed(ownEntry(c)))
		h:tick(0.05, 2)
		expect.equal(parts.toasts.count(), 1)
	end)

	TestKit.suite("Cliente: ventanas")

	test("todas las ventanas y pestañas se construyen y se cierran sin errores", function()
		local h, s, player, session, c, parts = setup({ isStudio = true })
		s.CreatureService.add(session, "GLORB", "COSMIC")
		s.CreatureService.add(session, "NULLABYTE", "GOLDEN")
		h:tick(0.05, 3)
		local windows = parts.windows
		local content = parts.layers.windows:FindFirstChild("Content", true)
		local cases = {
			{ "shop", "food" }, { "shop", "eggs" }, { "shop", "premium" }, { "upgrades" },
			{ "beasts", "mine" }, { "beasts", "collection" }, { "rebirth" }, { "settings", "settings" }, { "settings", "dev" },
		}
		for _, case in ipairs(cases) do
			expect.truthy(windows.open(case[1], case[2]), "abre " .. case[1])
			h:tick(0.05, 3)
			local name, tab = windows.current()
			expect.equal(name, case[1])
			expect.greater(#content:GetDescendants(), 3, case[1] .. "/" .. tostring(case[2]) .. " tiene contenido")
			-- Un cambio de estado con la ventana abierta la refresca sin romperse.
			s.EconomyService.addCoins(1, 777)
			s.StateService.pushAll(1)
			h:tick(0.05, 3)
		end
		windows.close()
		expect.falsy(windows.isOpen())
		expect.equal(#content:GetChildren(), 0, "el contenido se destruye al cerrar")
		expect.falsy(windows.open("noexiste"))
		noProblems(h)
	end)

	test("comprar comida, mejoras y huevos desde la interfaz", function()
		local h, s, player, session, c, parts = setup()
		local windows = parts.windows
		local layer = parts.layers.windows
		-- Comida
		windows.open("shop", "food")
		local card = layer:FindFirstChild("APPLE", true)
		h:advance(2)
		h:click(card:FindFirstChild("Buy"))
		h:tick(0.05, 2)
		expect.equal(session.profile.inventory.APPLE, 1)
		expect.equal(session.profile.coins, 44)
		h:advance(2)
		h:click(card:FindFirstChild("BuyFive"))
		h:tick(0.05, 2)
		expect.equal(session.profile.inventory.APPLE, 6)
		-- Comida bloqueada: sin botón, con candado.
		local locked = layer:FindFirstChild("DINO_STEAK", true)
		expect.falsy(locked:FindFirstChild("Buy").Visible)
		expect.truthy(string.find(locked:FindFirstChild("Lock").Text, "Market License", 1, true))
		-- Mejoras: el botón refleja el coste real y se desactiva sin monedas.
		windows.open("upgrades")
		local row = layer:FindFirstChild("INVENTORY", true)
		local buy = row:FindFirstChild("Buy")
		expect.truthy(string.find(buy:FindFirstChild("Text", true).Text, "40", 1, true), "coste mostrado")
		expect.falsy(buy.Active, "14 monedas: desactivado")
		h:advance(2)
		h:click(buy)
		expect.equal(session.profile.upgrades.INVENTORY, nil, "un botón desactivado no envía nada")
		s.EconomyService.addCoins(1, 5000)
		h:tick(0.05, 3)
		expect.truthy(buy.Active)
		h:advance(2)
		h:click(buy)
		h:tick(0.05, 3)
		expect.equal(session.profile.upgrades.INVENTORY, 1)
		expect.truthy(string.find(row:FindFirstChild("Level").Text, "1/10", 1, true), "nivel refrescado en el sitio")
		-- Huevo: tarjeta de eclosión y nueva fila en BEASTS.
		windows.open("shop", "eggs")
		local egg = layer:FindFirstChild("BASIC", true)
		expect.equal(#egg:FindFirstChild("Odds"):GetChildren(), 5, "4 rarezas con su porcentaje + layout")
		h:advance(2)
		h:click(egg:FindFirstChild("Buy"))
		h:tick(0.05, 3)
		expect.equal(Fixtures.count(session.profile.creatures), 2)
		local cardUI = parts.layers.overlay:FindFirstChild("HatchCard")
		expect.truthy(cardUI, "tarjeta de eclosión")
		expect.truthy(cardUI:FindFirstChild("CreatureIcon", true), "con retrato 3D")
		h:click(cardUI)
		expect.equal(parts.layers.overlay:FindFirstChild("HatchCard"), nil, "se cierra al tocarla")
		noProblems(h)
	end)

	test("BEASTS: guardar, colocar y vender (con confirmación) desde la interfaz", function()
		local h, s, player, session, c, parts = setup()
		local first, firstId = Fixtures.firstCreature(session)
		local extra = s.CreatureService.add(session, "CHOMPITO", "GOLDEN")
		h:tick(0.05, 3)
		local windows = parts.windows
		local layer = parts.layers.windows
		windows.open("beasts", "mine")
		local row = layer:FindFirstChild(extra.id, true)
		expect.truthy(row, "fila de la criatura")
		expect.truthy(row:FindFirstChild("CreatureIcon", true), "retrato")
		expect.truthy(string.find(layer:FindFirstChild("Summary", true).Text, "Pens 2/3", 1, true))
		-- Guardar
		h:advance(2)
		h:click(row:FindFirstChild("Move"))
		h:tick(0.05, 3)
		expect.equal(extra.slot, 0)
		row = layer:FindFirstChild(extra.id, true)
		expect.equal(row:FindFirstChild("Move"):FindFirstChild("Text", true).Text, "PLACE", "la fila se reconstruye")
		-- Colocar en el primer espacio libre
		h:advance(2)
		h:click(row:FindFirstChild("Move"))
		h:tick(0.05, 3)
		expect.equal(extra.slot, 1)
		-- Subir de nivel no reconstruye los retratos (misma instancia de fila).
		row = layer:FindFirstChild(extra.id, true)
		row:SetAttribute("Marker", 1)
		first.growth = 200
		s.StateService.push(1, "creatures")
		h:tick(0.05, 3)
		expect.equal(layer:FindFirstChild(extra.id, true):GetAttribute("Marker"), 1, "refresco en el sitio")
		expect.truthy(string.find(layer:FindFirstChild(firstId, true):FindFirstChild("Info").Text, "Lv 7", 1, true))
		-- Vender pide dos pulsaciones.
		local sell = row:FindFirstChild("Sell")
		h:advance(2)
		h:click(sell)
		h:tick(0.05, 2)
		expect.equal(Fixtures.count(session.profile.creatures), 2, "la primera pulsación solo arma la venta")
		expect.equal(sell:FindFirstChild("Text", true).Text, "SURE? TAP AGAIN")
		h:click(sell)
		h:tick(0.05, 3)
		expect.equal(Fixtures.count(session.profile.creatures), 1)
		expect.equal(layer:FindFirstChild(extra.id, true), nil, "la fila desaparece")
		-- La última no se puede vender: botón desactivado.
		expect.falsy(layer:FindFirstChild(firstId, true):FindFirstChild("Sell").Active)
		-- Colección
		windows.open("beasts", "collection")
		h:tick(0.05, 2)
		expect.truthy(string.find(layer:FindFirstChild("Summary", true).Text, "Discovered 2/24", 1, true))
		expect.equal(layer:FindFirstChild("GOBBLO_NORMAL", true):FindFirstChild("Label", true).Text, "Gobblo")
		expect.equal(layer:FindFirstChild("NULLABYTE_COSMIC", true):FindFirstChild("Label", true).Text, "???", "sin descubrir")
		noProblems(h)
	end)

	test("renacer desde la interfaz exige dos pasos y un botón que tarda en activarse", function()
		local h, s, player, session, c, parts = setup()
		local windows = parts.windows
		local layer = parts.layers.windows
		windows.open("rebirth")
		h:tick(0.05, 4)
		local button = layer:FindFirstChild("Rebirth", true)
		expect.truthy(button, "se muestra la información")
		expect.falsy(button.Active, "sin requisitos: desactivado")
		expect.truthy(layer:FindFirstChild("RESETS", true))
		expect.truthy(layer:FindFirstChild("YOU KEEP", true))
		-- Cumple requisitos.
		local Math = Fixtures.logic(h, "EconomyMath")
		local creature = Fixtures.firstCreature(session)
		creature.growth = Math.growthForLevel("GOBBLO", 15)
		s.EconomyService.addCoins(1, 30000)
		s.StateService.pushAll(1)
		h:tick(0.05, 3)
		expect.truthy(parts.layers.hud:FindFirstChild("Menu_rebirth", true):FindFirstChild("Badge").Visible, "indicador en el menú")
		windows.open("rebirth")
		h:tick(0.05, 4)
		button = layer:FindFirstChild("Rebirth", true)
		expect.truthy(button.Active)
		h:click(button)
		expect.equal(session.profile.rebirths, 0, "el primer botón solo abre la confirmación")
		local confirm = layer:FindFirstChild("Confirm", true)
		expect.truthy(confirm)
		expect.falsy(confirm.Active, "recién abierto: todavía no se puede confirmar")
		h:click(confirm)
		expect.equal(session.profile.rebirths, 0, "doble clic accidental no renace")
		h:tick(0.1, 20)
		expect.truthy(confirm.Active)
		h:advance(2)
		h:click(confirm)
		h:tick(0.05, 4)
		expect.equal(session.profile.rebirths, 1)
		expect.falsy(windows.isOpen())
		expect.equal(c.StateController.get("rebirths"), 1)
		expect.truthy(parts.layers.hud:FindFirstChild("Chip_rebirth", true).Visible, "chip de renacimiento")
		noProblems(h)
	end)

	test("ajustes: calidad y volumen se aplican en local y se guardan en el perfil", function()
		local h, s, player, session, c, parts = setup()
		local windows = parts.windows
		local layer = parts.layers.windows
		windows.open("settings")
		expect.equal(layer:FindFirstChild("Tab_dev", true), nil, "sin pestaña DEV para jugadores normales")
		h:advance(2)
		h:click(layer:FindFirstChild("Low", true))
		h:tick(0.05, 3)
		expect.equal(c.SettingsController.quality(), "Low")
		expect.equal(session.profile.settings.vfxQuality, "Low")
		h:advance(2)
		for _ = 1, 3 do
			h:click(layer:FindFirstChild("🔊 Sound effects", true):FindFirstChild("Less"))
		end
		h:tick(0.05, 3)
		expect.near(c.SettingsController.get("sfxVolume"), 0.7, 1e-6)
		expect.near(session.profile.settings.sfxVolume, 0.7, 1e-6)
		h:advance(2)
		h:click(layer:FindFirstChild("High", true))
		h:tick(0.05, 3)
		expect.equal(c.SettingsController.quality(), "High")
		noProblems(h)
	end)

	test("panel DEV: visible para administradores y sus comandos pasan por el servidor", function()
		local h, s, player, session, c, parts = setup({ isStudio = true })
		expect.equal(c.StateController.get("isAdmin"), true)
		local windows = parts.windows
		windows.open("settings", "dev")
		local layer = parts.layers.windows
		expect.truthy(layer:FindFirstChild("Tab_dev", true))
		h:advance(2)
		h:click(layer:FindFirstChild("+1K coins", true))
		h:tick(0.05, 3)
		expect.equal(session.profile.coins, 1050)
		h:advance(2)
		h:click(layer:FindFirstChild("FOOD RAIN", true))
		h:tick(0.3, 4)
		expect.equal((s.EventService.current()), "FOOD_RAIN")
		-- El banner de evento aparece en el HUD.
		local banner = parts.layers.hud:FindFirstChild("Event", true)
		expect.truthy(banner.Visible, "banner de evento")
		expect.truthy(string.find(banner:FindFirstChild("Title").Text, "FOOD RAIN", 1, true))
		s.EventService.stop()
		h:tick(0.3, 3)
		expect.falsy(banner.Visible)
	end)

	TestKit.suite("Cliente: mundo, avisos y dispositivos")

	test("cajas: etiqueta, aviso de transporte, línea-guía a la zona azul y soltar", function()
		local h, s, player, session, c, parts = setup()
		local beto = h:joinPlayer(2, "Beto")
		h:advance(300)
		local entry = s.TheftService.spawnCrate("SILVER", V3.new(30, 1.9, 30))
		h:tick(0.05, 3)
		expect.equal(c.WorldController.stats().crates, 1)
		expect.equal(entry.part:FindFirstChild("CrateLabel"):FindFirstChild("State").Text, "GRAB ME!")
		h:moveTo(player, V3.new(30, 5, 30))
		h:tick(0.2, 3)
		expect.equal(c.WorldController.carried().tier, "SILVER")
		local carry = parts.layers.hud:FindFirstChild("Carry", true)
		expect.truthy(carry.Visible, "aviso de caja")
		expect.truthy(c.WorldController.stats().guide, "guía hacia la zona de entrega")
		expect.falsy(entry.prompt.Enabled, "sin prompt de robo sobre la propia caja")
		h:advance(2)
		h:click(carry:FindFirstChild("Drop"))
		h:tick(0.2, 3)
		expect.equal(entry.machine.state, "AVAILABLE")
		expect.equal(c.WorldController.carried(), nil)
		expect.falsy(carry.Visible)
		-- La lleva otro jugador: se anima a robarla.
		h:moveTo(player, V3.new(-80, 5, -80))
		h:moveTo(beto, entry.position + V3.new(0, 3, 0))
		h:tick(0.2, 12)
		expect.equal(entry.machine.carrier, 2)
		expect.equal(entry.part:FindFirstChild("CrateLabel"):FindFirstChild("State").Text, "STEAL IT!")
		expect.truthy(entry.prompt.Enabled)
		noProblems(h)
	end)

	test("parcelas y kioscos: carteles, ganancias y apertura de ventanas", function()
		local h, s, player, session, c, parts = setup()
		local beto, betoSession = h:joinPlayer(2, "Beto")
		h:tick(1, 4)
		local own = s.PlotService.plot(session.plotIndex).model
		local other = s.PlotService.plot(betoSession.plotIndex).model
		local empty = s.PlotService.plot(8).model
		expect.equal(own.Sign.SignGuiFront.Label.Text, "YOUR PLOT")
		expect.equal(other.Sign.SignGuiFront.Label.Text, "Beto")
		expect.equal(empty.Sign.SignGuiBack.Label.Text, "EMPTY PLOT")
		expect.truthy(string.find(own.CollectPad.CollectInfo.Title.Text, "💰", 1, true))
		expect.truthy(string.find(own.CollectPad.CollectInfo.Info.Text, "step here", 1, true))
		expect.truthy(own.DeliveryPad.DeliveryInfo.Enabled)
		expect.falsy(other.DeliveryPad.DeliveryInfo.Enabled, "la zona de entrega ajena no se anuncia")
		expect.falsy(empty.CollectPad.CollectInfo.Enabled)
		expect.equal(c.WorldController.ownPlot().index, session.plotIndex)
		-- La comida de bienvenida de Beto no se le muestra a Ana.
		local hidden = 0
		for _, pickup in ipairs(h.game:GetService("Workspace").FTB_Pickups:GetChildren()) do
			if pickup:GetAttribute("Owner") == 2 then
				expect.equal(pickup:FindFirstChildOfClass("Model"), nil, "sin modelo para quien no puede cogerla")
				hidden += 1
			elseif pickup:GetAttribute("Owner") == 1 then
				expect.truthy(pickup:FindFirstChildOfClass("Model"), "la propia sí tiene modelo 3D")
			end
			expect.equal(pickup.Transparency, 1, "la pieza lógica del servidor es invisible")
			expect.equal(pickup:FindFirstChildOfClass("BillboardGui"), nil, "sin emoji flotante")
		end
		expect.equal(hidden, 3)
		-- Kioscos
		local world = s.PlotService.world()
		for kioskId, expected in pairs({ Shop = "shop", Upgrades = "upgrades", Rebirth = "rebirth", Collection = "beasts" }) do
			local prompt = world.kiosks[kioskId].Counter:FindFirstChild("KioskPrompt")
			expect.truthy(prompt, "prompt en " .. kioskId)
			Harness.signalOf(prompt, "Triggered"):Fire()
			h:settle(4)
			expect.equal((parts.windows.current()), expected)
		end
		local _, tab = parts.windows.current()
		parts.windows.close()
		noProblems(h)
	end)

	test("avisos: máximo simultáneo, caducidad, anuncios y ganancias offline", function()
		local h, s = Fixtures.server()
		local player = h:joinPlayer(1, "Ana")
		h:removePlayer(player)
		h:advance(3600)
		local player2, session = h:joinPlayer(1, "Ana")
		local c = h:bootClient(player2)
		h:tick(0.05, 4)
		local parts = c.UIController.parts()
		local overlay = parts.layers.overlay
		-- Ganancias offline
		local offline = overlay:FindFirstChild("Offline")
		expect.truthy(offline, "ventana de ganancias offline")
		expect.equal(offline:FindFirstChild("Amount").Text, "+1.8K coins")
		h:advance(2)
		h:click(offline:FindFirstChild("Claim"))
		h:tick(0.05, 3)
		expect.equal(session.profile.coins, 1850)
		expect.equal(overlay:FindFirstChild("Offline"), nil)
		-- Notificaciones
		h:tick(0.1, 40)
		for i = 1, 9 do
			s.ValidationService.notify(player2, "mensaje " .. i, "info")
		end
		s.ValidationService.notify(player2, "mensaje 9", "info") -- repetido: no ocupa otro hueco
		h:tick(0.05, 2)
		expect.equal(parts.toasts.count(), 4)
		h:tick(0.1, 40)
		expect.equal(parts.toasts.count(), 0, "caducan solos")
		expect.equal(#overlay:FindFirstChild("Toasts"):GetChildren(), 1, "solo queda el layout")
		-- Anuncio global
		s.VFXService.announce("Beto hatched a SECRET Nullabyte!!!", Harness.roblox.Color3.fromRGB(255, 70, 140))
		h:tick(0.05, 2)
		local announce = overlay:FindFirstChild("Announce")
		expect.truthy(announce.Visible)
		h:tick(0.1, 50)
		expect.falsy(announce.Visible)
		noProblems(h)
	end)

	test("escala de la interfaz por dispositivo", function()
		local h, s, player, session, c = setup()
		local V2 = Harness.roblox.Vector2
		local UI = c.UIController
		local cases = {
			{ "PC 1080p", V2.new(1920, 1080), false },
			{ "portátil", V2.new(1366, 768), false },
			{ "tablet", V2.new(1024, 768), true },
			{ "móvil grande", V2.new(932, 430), true },
			{ "móvil pequeño", V2.new(667, 375), true },
			{ "ventana diminuta", V2.new(320, 240), false },
		}
		for _, case in ipairs(cases) do
			local scale = UI.scaleFor(case[2], case[3])
			local virtual = case[2] / scale
			expect.truthy(scale >= 0.5 and scale <= 1.3, case[1] .. " escala " .. scale)
			if case[3] then
				-- Botones de menú de 58 px virtuales: al menos ~39 px reales en pantallas táctiles.
				expect.greater(58 * scale, 38, case[1] .. " tamaño táctil")
			end
			if case[2].X >= 660 then
				-- Monedas (264) + banner central (460) caben sin pisarse.
				expect.greater(virtual.X, 460 + 2 * 250, case[1] .. " ancho virtual " .. virtual.X)
				-- Menú izquierdo (4 botones) + monedas + 3 chips caben en vertical.
				expect.greater(virtual.Y, 500, case[1] .. " alto virtual " .. virtual.Y)
			end
		end
		expect.equal(UI.scaleFor(V2.new(0, 0), false), 1)
	end)

	test("modo táctil: la interfaz arranca igual y los botones no dependen del ratón", function()
		local h, s, player, session, c, parts = setup({ touch = true })
		noProblems(h)
		expect.greater(c.UIController.scale(), 0.67)
		-- Todas las acciones usan `Activated` (ratón, toque y mando), nunca hover.
		parts.windows.open("shop", "food")
		h:advance(2)
		h:click(parts.layers.windows:FindFirstChild("APPLE", true):FindFirstChild("Buy"))
		h:tick(0.05, 2)
		expect.equal(session.profile.inventory.APPLE, 1)
	end)

	test("el aviso de modo de prueba aparece cuando el progreso no se guarda", function()
		local h, s = Fixtures.server({ isStudio = true, datastoreUnavailable = true })
		local player, session = h:joinPlayer(1, "Ana")
		local c = h:bootClient(player)
		h:tick(0.05, 4)
		local chip = c.UIController.parts().layers.hud:FindFirstChild("Chip_ephemeral", true)
		expect.truthy(chip.Visible)
		expect.truthy(string.find(chip:FindFirstChild("Label").Text, "NOT saved", 1, true))
	end)
end
