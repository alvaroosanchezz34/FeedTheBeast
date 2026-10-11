--!nocheck
-- Pruebas de la ampliación: tareas diarias, evolución, modelos 3D de comida y mapa.
-- Comprueban lógica y estructura. NO comprueban el aspecto: eso hay que mirarlo en Studio.
local TestKit = require("./lib/TestKit")
local Fixtures = require("./lib/Fixtures")
local expect = TestKit.expect
local test = TestKit.test

return function()
	TestKit.suite("Tareas diarias")

	local function board(session, ids)
		local list = {}
		for _, id in ipairs(ids) do
			table.insert(list, { id = id, progress = 0, claimed = false })
		end
		session.profile.quests.list = list
		session.profile.quests.bonusClaimed = false
	end

	test("el tablero es determinista, de categorías distintas y cambia con los días", function()
		local h = Fixtures.server()
		local Logic = Fixtures.logic(h, "QuestLogic")
		local Config = Fixtures.config(h, "QuestConfig")
		local different = 0
		for day = 20000, 20040 do
			local a, b = Logic.pick(day, 1), Logic.pick(day, 1)
			expect.equal(#a, Config.DailyCount)
			local categories = {}
			for i, entry in ipairs(a) do
				expect.equal(entry.id, b[i].id, "mismo día y jugador = mismas tareas")
				local def = Config.Quests[entry.id]
				expect.truthy(def, entry.id)
				expect.falsy(categories[def.category], "categoría repetida el día " .. day)
				categories[def.category] = true
				expect.equal(entry.progress, 0)
				expect.equal(entry.claimed, false)
			end
			local nextDay = Logic.pick(day + 1, 1)
			if nextDay[1].id ~= a[1].id or nextDay[2].id ~= a[2].id or nextDay[3].id ~= a[3].id then
				different += 1
			end
		end
		expect.greater(different, 25, "los tableros varían de un día a otro")
	end)

	test("todas las tareas del catálogo son coherentes y alcanzables", function()
		local h = Fixtures.server()
		local Config = Fixtures.config(h, "QuestConfig")
		local FoodConfig = Fixtures.config(h, "FoodConfig")
		local events = { FoodCollected = true, Fed = true, FedRare = true, FedFavorite = true, LevelUp = true, PadCollected = true, Hatched = true, CrateDelivered = true, EventAction = true, UpgradeBought = true }
		local categories = {}
		for _, id in ipairs(Config.Order) do
			local def = Config.Quests[id]
			expect.truthy(def, id)
			expect.equal(def.id, id)
			expect.truthy(events[def.event], id .. " usa un evento que algún servicio emite")
			expect.greater(def.goal, 0)
			expect.greater(def.coins, 0)
			expect.truthy(string.find(string.format(def.desc, def.goal), tostring(def.goal), 1, true))
			if def.food then
				expect.truthy(FoodConfig.Foods[def.food], id .. " premia una comida existente")
			end
			categories[def.category] = true
		end
		expect.equal(Fixtures.count(Config.Quests), #Config.Order)
		expect.greater(Fixtures.count(categories), Config.DailyCount - 1, "categorías suficientes para llenar el tablero")
		expect.truthy(FoodConfig.Foods[Config.Bonus.food])
	end)

	test("el progreso solo cuenta para su evento, se acota y no acepta cantidades raras", function()
		local h, s = Fixtures.server()
		local Logic = Fixtures.logic(h, "QuestLogic")
		local _, session = h:joinPlayer(1, "Ana")
		board(session, { "FEED", "COINS", "HATCH" })
		local list = session.profile.quests.list
		Logic.progress(session.profile, "Fed", 5)
		expect.equal(list[1].progress, 5)
		expect.equal(list[2].progress, 0)
		Logic.progress(session.profile, "Fed", -3)
		Logic.progress(session.profile, "Fed", 0 / 0)
		Logic.progress(session.profile, "Fed", "7")
		Logic.progress(session.profile, "NoExiste", 5)
		expect.equal(list[1].progress, 5)
		local completed = Logic.progress(session.profile, "Fed", 1e9)
		expect.equal(list[1].progress, 12, "acotado al objetivo")
		expect.equal(completed[1], 1)
		expect.equal(#Logic.progress(session.profile, "Fed", 1), 0, "no se completa dos veces")
	end)

	test("jugar hace avanzar las tareas: dar de comer, cobrar, comprar y eclosionar", function()
		local h, s = Fixtures.server()
		local player, session = h:joinPlayer(1, "Ana")
		board(session, { "FEED", "SHOP", "HATCH" })
		local _, creatureId = Fixtures.firstCreature(session)
		s.FoodService.give(session, "APPLE", 3)
		for _ = 1, 3 do
			h:advance(5)
			expect.truthy(s.FeedingService.feed(session, creatureId, "APPLE", { skipDistance = true }))
		end
		expect.equal(session.profile.quests.list[1].progress, 3)
		s.EconomyService.addCoins(1, 1e6)
		expect.truthy(s.ShopService.buyUpgrade(session, "INVENTORY"))
		expect.equal(session.profile.quests.list[2].progress, 1)
		local EggConfig = Fixtures.config(h, "EggConfig")
		expect.truthy(s.ShopService.buyEgg(session, EggConfig.Order[1]))
		expect.equal(session.profile.quests.list[3].progress, 1)
		h:step(0.1, 2)
		local view = h:stateFor(1).quests
		expect.equal(#view.list, 3)
		expect.equal(view.list[2].done, true)
		expect.equal(view.list[1].done, false)
		expect.greater(view.resetAt, h.clock.unix)
	end)

	test("reclamar paga una sola vez aunque el cliente repita la petición", function()
		local h, s = Fixtures.server()
		local player, session = h:joinPlayer(1, "Ana")
		local Logic = Fixtures.logic(h, "QuestLogic")
		local Config = Fixtures.config(h, "QuestConfig")
		board(session, { "COINS", "SHOP", "HATCH" })
		local profile = session.profile

		-- Sin terminar: no paga.
		local before = profile.coins
		Fixtures.act(h, player, "ClaimQuest", 1)
		expect.equal(profile.coins, before, "tarea sin terminar")
		expect.equal(profile.quests.list[1].claimed, false)

		s.QuestService.progress(session, "PadCollected", 5)
		local expected = Logic.rewardCoins(Config.Quests.COINS, s.EconomyService.income(session))
		expect.greater(expected, 0)
		Fixtures.act(h, player, "ClaimQuest", 1)
		expect.equal(profile.coins, before + expected)
		expect.equal(profile.quests.list[1].claimed, true)
		expect.equal(profile.stats.questsClaimed, 1)
		for _ = 1, 4 do
			Fixtures.act(h, player, "ClaimQuest", 1)
		end
		h:fire(player, "ClaimQuest", 1)
		h:fire(player, "ClaimQuest", 1)
		expect.equal(profile.coins, before + expected, "no se cobra dos veces")
		expect.equal(profile.stats.questsClaimed, 1)

		-- Índices inválidos: ni error ni pago.
		for _, bad in ipairs({ 0, 4, 99, -1, 1.5, "1" }) do
			Fixtures.act(h, player, "ClaimQuest", bad)
		end
		expect.equal(profile.coins, before + expected)
	end)

	test("el premio extra exige las tres reclamadas y también es de un solo uso", function()
		local h, s = Fixtures.server()
		local player, session = h:joinPlayer(1, "Ana")
		local Config = Fixtures.config(h, "QuestConfig")
		local Inventory = Fixtures.logic(h, "Inventory")
		board(session, { "COINS", "SHOP", "CRATE" })
		local profile = session.profile
		s.QuestService.progress(session, "PadCollected", 5)
		s.QuestService.progress(session, "UpgradeBought", 1)
		Fixtures.act(h, player, "ClaimQuest", 1)
		Fixtures.act(h, player, "ClaimQuest", 2)
		local before = profile.coins
		Fixtures.act(h, player, "ClaimQuestBonus")
		expect.equal(profile.coins, before, "faltaba una tarea")
		h:step(0.1, 2)
		expect.equal(h:stateFor(1).quests.bonus.ready, false)

		s.QuestService.progress(session, "CrateDelivered", 1)
		Fixtures.act(h, player, "ClaimQuest", 3)
		h:step(0.1, 2)
		expect.equal(h:stateFor(1).quests.bonus.ready, true)
		before = profile.coins
		local cakes = Inventory.get(profile, Config.Bonus.food)
		Fixtures.act(h, player, "ClaimQuestBonus")
		expect.greater(profile.coins, before)
		expect.equal(Inventory.get(profile, Config.Bonus.food), cakes + Config.Bonus.foodAmount)
		local after = profile.coins
		Fixtures.act(h, player, "ClaimQuestBonus")
		Fixtures.act(h, player, "ClaimQuestBonus")
		h:step(0.1, 2)
		expect.equal(profile.coins, after)
		expect.equal(Inventory.get(profile, Config.Bonus.food), cakes + Config.Bonus.foodAmount)
		expect.equal(h:stateFor(1).quests.bonus.claimed, true)
	end)

	test("con la mochila llena la comida del premio se paga en monedas", function()
		local h, s = Fixtures.server()
		local player, session = h:joinPlayer(1, "Ana")
		local Config = Fixtures.config(h, "QuestConfig")
		local FoodConfig = Fixtures.config(h, "FoodConfig")
		local Logic = Fixtures.logic(h, "QuestLogic")
		local Inventory = Fixtures.logic(h, "Inventory")
		board(session, { "HATCH", "SHOP", "COINS" })
		s.FoodService.give(session, "APPLE", 9999)
		local count = Inventory.count(session.profile)
		s.QuestService.progress(session, "Hatched", 1)
		local before = session.profile.coins
		Fixtures.act(h, player, "ClaimQuest", 1)
		local def = Config.Quests.HATCH
		local expected = Logic.rewardCoins(def, s.EconomyService.income(session)) + FoodConfig.Foods[def.food].price
		expect.equal(session.profile.coins, before + expected)
		expect.equal(Inventory.count(session.profile), count, "la mochila no supera su capacidad")
	end)

	test("el tablero se conserva al salir y entrar el mismo día y se renueva al cambiar de día", function()
		local h, s = Fixtures.server()
		local Logic = Fixtures.logic(h, "QuestLogic")
		local player, session = h:joinPlayer(1, "Ana")
		local day = session.profile.quests.day
		expect.equal(day, Logic.dayOf(h.clock.unix))
		expect.equal(#session.profile.quests.list, 3)
		local first = session.profile.quests.list[1]
		s.QuestService.progress(session, Fixtures.config(h, "QuestConfig").Quests[first.id].event, 1)
		expect.equal(first.progress, 1)
		local ids = { session.profile.quests.list[1].id, session.profile.quests.list[2].id, session.profile.quests.list[3].id }
		h:removePlayer(player)

		local player2, again = h:joinPlayer(1, "Ana")
		expect.equal(again.profile.quests.day, day)
		for i = 1, 3 do
			expect.equal(again.profile.quests.list[i].id, ids[i])
		end
		expect.equal(again.profile.quests.list[1].progress, 1, "progreso guardado")

		-- Mismo día, más tarde: nada cambia.
		h:step(1, 30)
		expect.equal(again.profile.quests.list[1].progress, 1)
		-- Pasa la medianoche UTC con el jugador conectado.
		h:advance(Logic.secondsLeft(h.clock.unix) + 5)
		h:step(1, 25)
		expect.equal(again.profile.quests.day, day + 1)
		expect.equal(again.profile.quests.list[1].progress, 0)
		expect.equal(again.profile.quests.bonusClaimed, false)
		expect.equal(#h:stateFor(1).quests.list, 3)
	end)

	test("un perfil v2 se migra y los datos de tareas manipulados se sanean", function()
		local h = Fixtures.server()
		local Schema = Fixtures.logic(h, "ProfileSchema")
		local v2 = Schema.default(1000)
		v2.version = 2
		v2.quests = nil
		v2.stats.questsClaimed = nil
		v2.coins = 4321
		local profile, err = Schema.prepare(v2, 1000)
		expect.truthy(profile, tostring(err))
		expect.equal(profile.version, 3)
		expect.equal(profile.coins, 4321)
		expect.equal(#profile.quests.list, 0)
		expect.equal(profile.stats.questsClaimed, 0)

		local bad = Schema.default(1000)
		bad.quests = {
			day = "hoy",
			bonusClaimed = "si",
			list = {
				{ id = "FEED", progress = 1e9, claimed = true },
				{ id = "COINS", progress = 2, claimed = true },
				{ id = "NO_EXISTE", progress = 1, claimed = false },
				"basura",
				{ id = "HATCH", progress = -5 },
				{ id = "CRATE", progress = 0 },
			},
		}
		local fixed = Schema.prepare(bad, 1000)
		expect.truthy(fixed)
		expect.equal(fixed.quests.day, 0)
		expect.equal(fixed.quests.bonusClaimed, false)
		expect.equal(#fixed.quests.list, 3)
		expect.equal(fixed.quests.list[1].progress, 12, "progreso acotado al objetivo")
		expect.equal(fixed.quests.list[1].claimed, true)
		expect.equal(fixed.quests.list[2].claimed, false, "no puede estar cobrada sin terminar")
		expect.equal(fixed.quests.list[3].progress, 0)

		local broken = Schema.default(1000)
		broken.quests = "x"
		local nothing, reason = Schema.prepare(broken, 1000)
		expect.equal(nothing, nil)
		expect.equal(reason, "quests_not_a_table")
	end)

	TestKit.suite("Evolución")

	test("las fases dependen del nivel y suben la producción", function()
		local h = Fixtures.server()
		local Math = Fixtures.logic(h, "EconomyMath")
		local CreatureConfig = Fixtures.config(h, "CreatureConfig")
		local a, b = CreatureConfig.EvolutionLevels[1], CreatureConfig.EvolutionLevels[2]
		expect.greater(b, a)
		expect.equal(Math.stageFor(0), 1)
		expect.equal(Math.stageFor(a - 1), 1)
		expect.equal(Math.stageFor(a), 2)
		expect.equal(Math.stageFor(b - 1), 2)
		expect.equal(Math.stageFor(b), 3)
		expect.equal(Math.stageFor(9999), 3)
		expect.equal(#CreatureConfig.StageIncomeMult, 3)
		expect.equal(CreatureConfig.StageIncomeMult[1], 1)
		expect.greater(CreatureConfig.StageIncomeMult[2], 1)
		expect.greater(CreatureConfig.StageIncomeMult[3], CreatureConfig.StageIncomeMult[2])
	end)

	test("cada especie gana piezas visibles en cada fase y nunca las pierde", function()
		local h = Fixtures.server()
		local Builder = h:require("ReplicatedStorage.Shared.Creatures.CreatureBuilder")
		local CreatureConfig = Fixtures.config(h, "CreatureConfig")
		for _, speciesId in ipairs(CreatureConfig.Order) do
			local visual = Builder.build(speciesId)
			local counts = {}
			for stage = 1, 3 do
				visual:setStage(stage)
				local n = 0
				for _, record in ipairs(visual.records) do
					if record.part.Transparency < 1 then
						n += 1
					end
				end
				counts[stage] = n
			end
			expect.greater(counts[2], counts[1], speciesId .. " fase 2")
			expect.greater(counts[3], counts[2], speciesId .. " fase 3")
			visual:setStage(1)
			local back = 0
			for _, record in ipairs(visual.records) do
				if record.part.Transparency < 1 then
					back += 1
				end
			end
			expect.equal(back, counts[1], speciesId .. " reversible")
			expect.truthy(type(visual.species.happy) == "function", speciesId .. " tiene reacción de satisfacción")
			if speciesId ~= "NULLABYTE" then -- el secreto es un "glitch": sus ojos son píxeles, no globos
				expect.greater(#visual.eyes, 0, speciesId .. " tiene ojos articulados")
			end
			visual:destroy()
		end
	end)

	test("al cruzar el nivel de evolución el servidor lo anuncia una sola vez", function()
		local h, s = Fixtures.server()
		local Math = Fixtures.logic(h, "EconomyMath")
		local CreatureConfig = Fixtures.config(h, "CreatureConfig")
		local player, session = h:joinPlayer(1, "Ana")
		local creature, creatureId = Fixtures.firstCreature(session)
		local maxLevel = Math.maxLevel(session.profile.rebirths)
		-- Justo por debajo del nivel de evolución.
		local target = CreatureConfig.EvolutionLevels[1]
		local low, high = 0, Math.maxGrowth(creature.species, maxLevel)
		for _ = 1, 60 do
			local mid = (low + high) / 2
			local _, level = Math.scaleFromGrowth(creature.species, mid, maxLevel)
			if level >= target then
				high = mid
			else
				low = mid
			end
		end
		creature.growth = low
		local _, levelBefore = Math.scaleFromGrowth(creature.species, creature.growth, maxLevel)
		expect.equal(levelBefore, target - 1)
		s.FoodService.give(session, "PIZZA", 2)
		h:clearSent()
		expect.truthy(s.FeedingService.feed(session, creatureId, "PIZZA", { skipDistance = true }))
		local evolvedEvents = 0
		for _, sent in ipairs(h:sentTo(1, "CreatureEvent")) do
			if sent[2] == "Fed" and sent[3].evolved == 2 then
				evolvedEvents += 1
			end
		end
		expect.equal(evolvedEvents, 1)
		h:advance(10)
		h:clearSent()
		expect.truthy(s.FeedingService.feed(session, creatureId, "PIZZA", { skipDistance = true }))
		for _, sent in ipairs(h:sentTo(1, "CreatureEvent")) do
			if sent[2] == "Fed" then
				expect.equal(sent[3].evolved, nil, "no se repite")
			end
		end
	end)

	TestKit.suite("Comida 3D")

	test("las 20 comidas tienen modelo propio, reconocible por piezas y colores distintos", function()
		local h = Fixtures.server()
		local FoodModels = h:require("ReplicatedStorage.Shared.Food.FoodModels")
		local FoodConfig = Fixtures.config(h, "FoodConfig")
		expect.equal(#FoodConfig.Order, 20)
		local signatures = {}
		for _, foodId in ipairs(FoodConfig.Order) do
			expect.truthy(FoodModels.has(foodId), foodId .. " tiene modelo")
			local visual = FoodModels.build(foodId)
			expect.truthy(visual, foodId)
			local parts, colors, sig, casters = 0, {}, {}, 0
			for _, record in ipairs(visual.records) do
				local part = record.part
				parts += 1
				expect.equal(part.CanCollide, false, foodId .. " sin colisión")
				if part.CastShadow then
					casters += 1
				end
				local key = string.format("%d,%d,%d", part.Color.R * 255, part.Color.G * 255, part.Color.B * 255)
				colors[key] = true
				table.insert(sig, string.format("%s:%.1f,%.1f,%.1f:%s", part.ClassName, part.Size.X, part.Size.Y, part.Size.Z, key))
			end
			expect.atMost(casters, 3, foodId .. ": solo las piezas principales proyectan sombra")
			expect.greater(parts, 3, foodId .. " no es una sola forma")
			expect.atMost(parts, 40, foodId .. " dentro del presupuesto de piezas")
			expect.greater(Fixtures.count(colors), 1, foodId .. " tiene más de un color")
			expect.greater(visual.height, 0.5)
			expect.atMost(visual.height, 6)
			table.sort(sig)
			local signature = table.concat(sig, "|")
			expect.falsy(signatures[signature], foodId .. " es idéntica a " .. tostring(signatures[signature]))
			signatures[signature] = foodId
			visual:destroy()
		end
		expect.falsy(FoodModels.has("NO_EXISTE"))
		expect.equal(FoodModels.build("NO_EXISTE"), nil)
	end)

	test("la comida del mapa es un ancla lógica: el aspecto lo pone el cliente", function()
		local h, s = Fixtures.server()
		local Constants = h:require("ReplicatedStorage.Shared.Constants")
		local folder = h.game:GetService("Workspace"):FindFirstChild("FTB_Pickups")
		h:step(1, 5)
		local seen = 0
		for _, part in ipairs(folder:GetChildren()) do
			seen += 1
			expect.equal(part.Transparency, 1)
			expect.truthy(part:GetAttribute(Constants.PickupAttr.Food))
			expect.equal(part:FindFirstChildWhichIsA("BillboardGui", true), nil, "sin emoji flotante")
		end
		expect.greater(seen, 0)
	end)

	TestKit.suite("Mapa")

	test("la decoración no invade parcelas, plaza ni caminos y respeta el presupuesto de piezas", function()
		local h, s = Fixtures.server()
		local world = s.PlotService.world()
		local Scenery = h:require("ServerScriptService.Server.World.Scenery")
		local GameConfig = Fixtures.config(h, "GameConfig")
		local Layout = Fixtures.logic(h, "PlotLayout")
		expect.greater(#world.scenery.positions, 40, "hay decoración")
		local half = GameConfig.World.PlotSize / 2
		for _, item in ipairs(world.scenery.positions) do
			expect.truthy(Scenery.isFree(item.x, item.z, item.margin), "pieza de decoración en zona libre")
			expect.greater(math.sqrt(item.x ^ 2 + item.z ^ 2), GameConfig.World.PlazaRadius, "fuera de la plaza")
			for i = 1, GameConfig.PlotCount do
				local plot = Layout.plot(i)
				local dx, dz = item.x - plot.x, item.z - plot.z
				expect.truthy(math.sqrt(dx * dx + dz * dz) > half, "fuera de la parcela " .. i)
			end
		end
		expect.falsy(Scenery.isFree(0, 0, 0), "el centro de la plaza está ocupado")
		local parts = 0
		for _, d in ipairs(world.folder:GetDescendants()) do
			if d:IsA("BasePart") then
				parts += 1
			end
		end
		expect.atMost(parts, 6000, "piezas del mapa")
		expect.greater(parts, 800, "el mapa no está vacío")
	end)

	test("la mejora de parcela enseña más decoración por niveles", function()
		local h, s = Fixtures.server()
		local player, session = h:joinPlayer(1, "Ana")
		local plot = s.PlotService.plot(session.plotIndex)
		expect.equal(#plot.decor, 4)
		local function visible(level)
			local n = 0
			for _, part in ipairs(plot.decor[level]) do
				expect.greater(#plot.decor[level], 0)
				if part.Transparency < 1 then
					n += 1
				end
			end
			return n
		end
		for level = 1, 4 do
			expect.equal(visible(level), 0, "nivel " .. level .. " oculto al empezar")
		end
		s.EconomyService.addCoins(1, 1e12)
		for level = 1, 4 do
			expect.truthy(s.ShopService.buyUpgrade(session, "PLOT_STYLE"))
			expect.greater(visible(level), 0, "nivel " .. level .. " visible")
			if level < 4 then
				expect.equal(visible(level + 1), 0)
			end
		end
	end)

	TestKit.suite("Cliente: tareas")

	test("la ventana de tareas muestra progreso, deja reclamar y avisa en el menú", function()
		local h, s = Fixtures.server()
		local player, session = h:joinPlayer(1, "Ana")
		local c = h:bootClient(player, {})
		h:lookAt(s.PlotService.plot(session.plotIndex).cframe.Position)
		board(session, { "COINS", "SHOP", "HATCH" })
		s.StateService.push(1, "quests")
		h:tick(0.05, 6)
		local parts = c.UIController.parts()
		local badge = parts.layers.hud:FindFirstChild("Menu_tasks", true):FindFirstChild("Badge")
		expect.equal(badge.Visible, false)

		expect.truthy(parts.windows.open("tasks"))
		local layer = parts.layers.windows
		for index = 1, 3 do
			expect.truthy(layer:FindFirstChild("Task_" .. index, true), "fila " .. index)
		end
		local row = layer:FindFirstChild("Task_1", true)
		expect.equal(row:FindFirstChild("Count", true).Text, "0 / 5")
		expect.truthy(string.find(layer:FindFirstChild("Timer", true).Text, "New tasks in", 1, true))

		s.QuestService.progress(session, "PadCollected", 5)
		h:tick(0.05, 6)
		expect.equal(badge.Visible, true, "indicador de recompensa pendiente")
		row = layer:FindFirstChild("Task_1", true)
		expect.equal(row:FindFirstChild("Count", true).Text, "5 / 5")
		local before = session.profile.coins
		h:advance(2)
		h:click(row:FindFirstChild("Claim"))
		h:tick(0.05, 6)
		expect.greater(session.profile.coins, before)
		expect.equal(session.profile.quests.list[1].claimed, true)
		expect.equal(badge.Visible, false)
		local after = session.profile.coins
		row = layer:FindFirstChild("Task_1", true)
		h:advance(2)
		h:click(row:FindFirstChild("Claim"))
		h:tick(0.05, 6)
		expect.equal(session.profile.coins, after, "el botón ya no cobra")
		for _, text in ipairs(h.warnings) do
			error("aviso inesperado: " .. text)
		end
	end)
end
