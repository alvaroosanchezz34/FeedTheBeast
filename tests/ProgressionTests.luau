--!nocheck
local TestKit = require("./lib/TestKit")
local Fixtures = require("./lib/Fixtures")
local expect = TestKit.expect
local test = TestKit.test
local V3 = Fixtures.Vector3

return function()
	TestKit.suite("Mapa y parcelas")

	test("8 parcelas dentro del mapa, sin solaparse entre sí ni con la plaza", function()
		local h, s = Fixtures.server()
		local GameConfig = Fixtures.config(h, "GameConfig")
		local Layout = Fixtures.logic(h, "PlotLayout")
		local W = GameConfig.World
		expect.equal(GameConfig.PlotCount, 8)
		local half = W.PlotSize / 2
		local corners = { { -half, -half }, { half, -half }, { -half, half }, { half, half } }
		local plots = {}
		for i = 1, GameConfig.PlotCount do
			plots[i] = Layout.plot(i)
			for _, c in ipairs(corners) do
				local x, z = Layout.toWorld(plots[i], c[1], c[2])
				expect.atMost(math.abs(x), W.GroundSize / 2 - 2, "parcela " .. i .. " dentro del suelo (x)")
				expect.atMost(math.abs(z), W.GroundSize / 2 - 2, "parcela " .. i .. " dentro del suelo (z)")
				expect.greater(math.sqrt(x * x + z * z), W.PlazaRadius + 4, "parcela " .. i .. " fuera de la plaza")
			end
		end
		-- Dos cuadrados no se solapan si sus centros distan más que la diagonal.
		local diagonal = W.PlotSize * math.sqrt(2)
		for i = 1, #plots do
			for j = i + 1, #plots do
				local d = math.sqrt((plots[i].x - plots[j].x) ^ 2 + (plots[i].z - plots[j].z) ^ 2)
				expect.greater(d, diagonal, string.format("parcelas %d y %d", i, j))
			end
		end
	end)

	test("espacios, zonas y aparición están dentro de la parcela y no se pisan", function()
		local h, s = Fixtures.server()
		local GameConfig = Fixtures.config(h, "GameConfig")
		local Layout = Fixtures.logic(h, "PlotLayout")
		local half = GameConfig.World.PlotSize / 2
		local points = {}
		for slot = 1, GameConfig.World.MaxSlotsPerPlot do
			local p = Layout.slotLocal(slot)
			table.insert(points, { "slot" .. slot, p.x, p.z, 6 })
		end
		for _, name in ipairs({ "Spawn", "CollectPad", "DeliveryPad" }) do
			local p = Layout.Local[name]
			table.insert(points, { name, p.x, p.z, 4.5 })
		end
		for _, p in ipairs(points) do
			expect.atMost(math.abs(p[2]) + p[4], half, p[1] .. " dentro (x)")
			expect.atMost(math.abs(p[3]) + p[4], half, p[1] .. " dentro (z)")
		end
		for i = 1, #points do
			for j = i + 1, #points do
				local a, b = points[i], points[j]
				local d = math.sqrt((a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2)
				expect.greater(d, a[4] + b[4] - 0.01, a[1] .. " y " .. b[1] .. " se solapan")
			end
		end
		-- La comida de bienvenida no cae sobre una zona de recogida/entrega.
		for _, f in ipairs(Layout.Local.StarterFood) do
			for _, name in ipairs({ "CollectPad", "DeliveryPad" }) do
				local p = Layout.Local[name]
				expect.greater(math.sqrt((f.x - p.x) ^ 2 + (f.z - p.z) ^ 2), 9)
			end
		end
	end)

	test("el mundo construido tiene todas las piezas y cada parcela mira al centro", function()
		local h, s = Fixtures.server()
		local world = s.PlotService.world()
		local workspace = h.game:GetService("Workspace")
		expect.truthy(workspace:FindFirstChild("FTB_World"))
		for _, name in ipairs({ "FTB_Creatures", "FTB_Pickups", "FTB_Crates" }) do
			expect.truthy(workspace:FindFirstChild(name), name)
		end
		for _, id in ipairs({ "Shop", "Collection", "Upgrades", "Rebirth" }) do
			expect.truthy(world.kiosks[id], "kiosco " .. id)
		end
		for i = 1, 8 do
			local plot = world.plots[i]
			expect.equal(#plot.slotPads, 6)
			expect.equal(plot.model:GetAttribute("PlotIndex"), i)
			-- La entrada (-Z local) apunta hacia el centro del mapa.
			local toCenter = (V3.new(0, plot.cframe.Position.Y, 0) - plot.cframe.Position).Unit
			expect.greater(plot.cframe.LookVector:Dot(toCenter), 0.999, "parcela " .. i)
			expect.truthy(s.PlotService.isInside(i, plot.collectPos))
			expect.truthy(s.PlotService.isInside(i, plot.deliveryPos))
			expect.truthy(s.PlotService.isInside(i, plot.spawnCFrame.Position))
			expect.falsy(s.PlotService.isInside(i, V3.new(0, 0, 0)))
		end
		-- La comida del campo aparece en la plaza, lejos de las parcelas.
		local GameConfig = Fixtures.config(h, "GameConfig")
		expect.equal(s.FoodService.count("field"), GameConfig.FoodField.BaseActive)
		for _, pickup in ipairs(workspace.FTB_Pickups:GetChildren()) do
			local p = pickup.CFrame.Position
			local r = math.sqrt(p.X ^ 2 + p.Z ^ 2)
			expect.truthy(r >= GameConfig.World.FoodRingInner - 0.01 and r <= GameConfig.World.FoodRingOuter + 0.01, "radio " .. r)
		end
	end)

	test("cada jugador recibe una parcela distinta, aparece en ella y se libera al salir", function()
		local h, s = Fixtures.server()
		local players, used = {}, {}
		for i = 1, 8 do
			local player, session = h:joinPlayer(i, "P" .. i)
			expect.truthy(session, "jugador " .. i)
			expect.falsy(used[session.plotIndex], "parcela repetida")
			used[session.plotIndex] = true
			players[i] = player
			local plot = s.PlotService.plot(session.plotIndex)
			expect.equal(plot.model:GetAttribute("OwnerUserId"), i)
			expect.equal(plot.model:GetAttribute("OwnerName"), "P" .. i)
			expect.truthy(s.PlotService.isInside(session.plotIndex, h:positionOf(player)), "aparece en su parcela")
		end
		-- El noveno no cabe: se le expulsa sin romper nada.
		local _, ninth = h:joinPlayer(9, "P9")
		expect.equal(ninth, nil)
		expect.equal(h.kicks[#h.kicks].userId, 9)
		-- Al irse el 3, su parcela queda libre y limpia para el siguiente.
		local session3 = s.PlayerDataService.getSession(3)
		local index = session3.plotIndex
		h:removePlayer(players[3])
		local plot = s.PlotService.plot(index)
		expect.equal(plot.model:GetAttribute("OwnerUserId"), 0)
		expect.equal(plot.model:GetAttribute("Pending"), 0)
		local creaturesLeft = 0
		for _, model in ipairs(h.game:GetService("Workspace").FTB_Creatures:GetChildren()) do
			if model:GetAttribute("OwnerUserId") == 3 then
				creaturesLeft += 1
			end
		end
		expect.equal(creaturesLeft, 0, "sus criaturas salen del mundo")
		local _, tenth = h:joinPlayer(10, "P10")
		expect.equal(tenth.plotIndex, index)
	end)

	test("la clasificación del servidor se actualiza", function()
		local h, s = Fixtures.server()
		local player, session = h:joinPlayer(1, "Ana")
		s.EconomyService.addCoins(1, 950)
		h:step(1, 3)
		local stats = player:FindFirstChild("leaderstats")
		expect.truthy(stats)
		expect.equal(stats.Coins.Value, 1000)
		expect.equal(stats.Rebirths.Value, 0)
	end)

	TestKit.suite("Renacimiento")

	local function ready(h, s, session)
		local Math = Fixtures.logic(h, "EconomyMath")
		local creature = Fixtures.firstCreature(session)
		creature.growth = Math.growthForLevel(creature.species, 15)
		s.EconomyService.addCoins(session.userId, 30000)
	end

	test("requisitos: nivel y monedas; la información explica qué se pierde y qué se conserva", function()
		local h, s = Fixtures.server()
		local player, session = h:joinPlayer(1, "Ana")
		local info = h:invoke(player, "GetRebirthInfo")
		expect.falsy(info.canRebirth)
		expect.equal(info.nonce, nil, "sin requisitos no hay código de confirmación")
		expect.equal(info.cost, 25000)
		expect.equal(info.requiredLevel, 15)
		expect.greater(#info.resets, 0)
		expect.greater(#info.keeps, 0)
		expect.near(info.nextMult, 1.5)
		s.EconomyService.addCoins(1, 30000)
		info = h:invoke(player, "GetRebirthInfo")
		expect.equal(info.reason, "level_too_low")
		ready(h, s, session)
		info = h:invoke(player, "GetRebirthInfo")
		expect.truthy(info.canRebirth)
		expect.equal(type(info.nonce), "string")
	end)

	test("no se puede renacer con un solo mensaje: hace falta el código de confirmación vigente", function()
		local h, s = Fixtures.server()
		local player, session = h:joinPlayer(1, "Ana")
		ready(h, s, session)
		local coins = session.profile.coins
		Fixtures.act(h, player, "ConfirmRebirth", "")
		Fixtures.act(h, player, "ConfirmRebirth", "adivinado")
		expect.equal(session.profile.rebirths, 0)
		expect.equal(session.profile.coins, coins)
		-- Código caducado.
		local info = h:invoke(player, "GetRebirthInfo")
		h:advance(120)
		h:fire(player, "ConfirmRebirth", info.nonce)
		expect.equal(session.profile.rebirths, 0)
		-- Un intento fallido invalida el código.
		info = h:invoke(player, "GetRebirthInfo")
		Fixtures.act(h, player, "ConfirmRebirth", "otro")
		Fixtures.act(h, player, "ConfirmRebirth", info.nonce)
		expect.equal(session.profile.rebirths, 0, "código de un solo uso")
	end)

	test("renacer reinicia lo anunciado, conserva lo anunciado y aplica la bonificación", function()
		local h, s = Fixtures.server()
		local player, session = h:joinPlayer(1, "Ana")
		ready(h, s, session)
		local profile = session.profile
		s.ShopService.buyUpgrade(session, "INVENTORY")
		s.ShopService.buyUpgrade(session, "PLOT_STYLE")
		s.ShopService.buyUpgrade(session, "SLOTS")
		s.FoodService.give(session, "PIZZA", 3)
		local golden = s.CreatureService.add(session, "CHOMPITO", "GOLDEN")
		local fourth = s.CreatureService.add(session, "GLORB", "NORMAL")
		local fifth = s.CreatureService.add(session, "GOBBLO", "NORMAL")
		expect.equal(fifth.slot, 4, "usa el espacio extra comprado")
		profile.pendingCoins = 400
		s.EconomyService.addCoins(1, 30000)
		local statsFed = profile.stats.foodsFed
		local incomeBefore = s.EconomyService.income(session)

		local info = h:invoke(player, "GetRebirthInfo")
		expect.truthy(info.canRebirth)
		Fixtures.act(h, player, "ConfirmRebirth", info.nonce)

		expect.equal(profile.rebirths, 1)
		expect.equal(profile.coins, 0)
		expect.equal(profile.pendingCoins, 0)
		expect.equal(Fixtures.count(profile.inventory), 0)
		expect.equal(profile.upgrades.INVENTORY, nil)
		expect.equal(profile.upgrades.SLOTS, nil)
		expect.equal(profile.upgrades.PLOT_STYLE, 1, "la apariencia se conserva")
		expect.equal(Fixtures.count(profile.creatures), 4, "todas las criaturas se conservan")
		expect.equal(profile.creatures[golden.id].mutation, "GOLDEN", "y sus mutaciones")
		for _, creature in pairs(profile.creatures) do
			expect.equal(creature.growth, 0)
			expect.atMost(creature.slot, 3, "lo que no cabe vuelve al almacén")
		end
		expect.equal(profile.creatures[fifth.id].slot, 0)
		expect.equal(s.CreatureService.modelOf(1, fifth.id), nil)
		expect.truthy(profile.collection["CHOMPITO:GOLDEN"])
		expect.equal(profile.stats.foodsFed, statsFed)
		-- Bonificación permanente: x1.5 sobre la producción base de nivel 0.
		local Math = Fixtures.logic(h, "EconomyMath")
		expect.near(Math.multipliers(profile, {}).rebirth, 1.5)
		expect.equal(Math.maxLevel(profile.rebirths), 55, "sube el nivel máximo")
		-- El segundo exige más.
		local next = h:invoke(player, "GetRebirthInfo")
		expect.equal(next.cost, 100000)
		expect.equal(next.requiredLevel, 20)
		expect.falsy(next.canRebirth)
		-- Se guarda enseguida.
		h:settle(4)
		expect.equal(Fixtures.saved(h, 1).rebirths, 1)
		-- Repetir la confirmación no hace nada.
		Fixtures.act(h, player, "ConfirmRebirth", info.nonce)
		expect.equal(profile.rebirths, 1)
	end)

	TestKit.suite("Eventos globales")

	local function eventState(h)
		return h.game:GetService("ReplicatedStorage"):FindFirstChild("FTB_EventState")
	end

	test("ciclo automático: anuncio con temporizador, evento activo y limpieza", function()
		local h, s = Fixtures.server({ events = true })
		local EventConfig = Fixtures.config(h, "EventConfig")
		local folder = eventState(h)
		expect.equal(folder:GetAttribute("Phase"), "Idle")
		h:step(1, 50)
		expect.equal(folder:GetAttribute("Phase"), "Idle", "sin jugadores no hay eventos")
		local player, session = h:joinPlayer(1, "Ana")
		local waited = 0
		while folder:GetAttribute("Phase") == "Idle" and waited < EventConfig.FirstDelay do
			h:step(1, 1)
			waited += 1
		end
		expect.equal(folder:GetAttribute("Phase"), "Announce", "primero se anuncia")
		local eventId = folder:GetAttribute("EventId")
		expect.truthy(EventConfig.Events[eventId], "evento anunciado: " .. tostring(eventId))
		expect.near(folder:GetAttribute("StartsAt") - h.clock.server, EventConfig.AnnounceLead, 1.5, "cuenta atrás replicada")
		h:step(1, EventConfig.AnnounceLead + 1)
		expect.equal(folder:GetAttribute("Phase"), "Active")
		expect.near(folder:GetAttribute("EndsAt") - folder:GetAttribute("StartsAt"), EventConfig.Events[eventId].duration, 1.5)
		h:step(1, EventConfig.Events[eventId].duration + 2)
		expect.equal(folder:GetAttribute("Phase"), "Idle")
		expect.equal(folder:GetAttribute("EventId"), "")
		expect.equal(s.FoodService.count("event"), 0, "la comida del evento se limpia")
		-- Hay descanso antes del siguiente.
		h:step(1, EventConfig.CooldownMin - 10)
		expect.equal(folder:GetAttribute("Phase"), "Idle")
		h:step(1, EventConfig.CooldownMax - EventConfig.CooldownMin + 15)
		expect.truthy(folder:GetAttribute("Phase") ~= "Idle", "llega el siguiente")
		expect.truthy(folder:GetAttribute("EventId") ~= eventId, "no repite el mismo evento seguido")
	end)

	test("FOOD_RAIN: llueve comida de evento con tope y se puede recoger tras caer", function()
		local h, s = Fixtures.server()
		local player, session = h:joinPlayer(1, "Ana")
		local EventConfig = Fixtures.config(h, "EventConfig")
		local FoodConfig = Fixtures.config(h, "FoodConfig")
		expect.truthy(s.EventService.forceStart("FOOD_RAIN"))
		h:step(0.5, 80)
		local count = s.FoodService.count("event")
		expect.greater(count, 20)
		expect.atMost(count, EventConfig.Events.FOOD_RAIN.maxActive)
		local pickups = h.game:GetService("Workspace").FTB_Pickups:GetChildren()
		local rained
		for _, pickup in ipairs(pickups) do
			if pickup:GetAttribute("DropFrom") > 0 then
				rained = pickup
				local foodId = pickup:GetAttribute("FoodId")
				expect.truthy(table.find(FoodConfig.Foods[foodId].events, "FOOD_RAIN"), foodId .. " no es de este evento")
			end
		end
		expect.truthy(rained, "hay comida cayendo")
		h:moveTo(player, rained.CFrame.Position)
		h:step(0.5, 4)
		expect.greater(Fixtures.count(session.profile.inventory), 0, "se recoge")
		s.EventService.stop()
		expect.equal(s.FoodService.count("event"), 0)
		expect.greater(s.FoodService.count("field"), 0, "la comida normal no se borra")
	end)

	test("GOLDEN_FEAST: comida dorada y producción aumentada solo mientras dura", function()
		local h, s = Fixtures.server()
		local player, session = h:joinPlayer(1, "Ana")
		local base = s.EconomyService.income(session)
		s.EventService.forceStart("GOLDEN_FEAST")
		expect.near(s.EconomyService.income(session), base * 1.5, 1e-6)
		expect.equal(s.EventService.crateMult(), 2)
		h:step(0.5, 20)
		local golden = 0
		for _, pickup in ipairs(h.game:GetService("Workspace").FTB_Pickups:GetChildren()) do
			if pickup:GetAttribute("Golden") then
				golden += 1
			end
		end
		expect.greater(golden, 0)
		h:step(1, 70)
		expect.equal(eventState(h):GetAttribute("Phase"), "Idle")
		expect.near(s.EconomyService.income(session), base, 1e-6)
		expect.equal(s.EventService.crateMult(), 1)
	end)

	test("GIANT_BEAST: recompensas proporcionales a la contribución válida, una sola vez", function()
		local h, s = Fixtures.server()
		local ana, anaSession = h:joinPlayer(1, "Ana")
		local beto, betoSession = h:joinPlayer(2, "Beto")
		local carla, carlaSession = h:joinPlayer(3, "Carla")
		s.EventService.forceStart("GIANT_BEAST")
		local folder = eventState(h)
		expect.equal(folder:GetAttribute("Goal"), 120 + 100 * 3)
		local giant
		for _, model in ipairs(h.game:GetService("Workspace").FTB_Creatures:GetChildren()) do
			if model:GetAttribute("IsGiant") then
				giant = model
			end
		end
		expect.truthy(giant, "la bestia aparece")
		for _, session in ipairs({ anaSession, betoSession }) do
			session.profile.upgrades.INVENTORY = 10
			s.FoodService.give(session, "PIZZA", 30) -- 14 puntos cada una
		end
		-- Lejos del pedestal no cuenta.
		Fixtures.act(h, ana, "GiantFeed", "PIZZA")
		expect.equal(folder:GetAttribute("Progress"), 0)
		expect.equal(anaSession.profile.inventory.PIZZA, 30)
		h:moveTo(ana, V3.new(0, 5, 20))
		h:moveTo(beto, V3.new(10, 5, 15))
		for _ = 1, 20 do
			Fixtures.act(h, ana, "GiantFeed", "PIZZA")
		end
		for _ = 1, 5 do
			Fixtures.act(h, beto, "GiantFeed", "PIZZA")
		end
		Fixtures.act(h, beto, "GiantFeed", "LAVA_RAMEN") -- no tiene
		expect.equal(folder:GetAttribute("Progress"), 25 * 14)
		expect.equal(anaSession.profile.inventory.PIZZA, 10)
		local anaCoins, betoCoins, carlaCoins = anaSession.profile.coins, betoSession.profile.coins, carlaSession.profile.coins
		-- Se acaba el tiempo sin completar.
		h:step(1, 95)
		expect.equal(folder:GetAttribute("Phase"), "Idle")
		expect.equal(anaSession.profile.coins - anaCoins, 20 * 14 * 3)
		expect.equal(betoSession.profile.coins - betoCoins, 5 * 14 * 3)
		expect.equal(carlaSession.profile.coins, carlaCoins, "sin participar no hay premio")
		expect.equal(giant.Parent, nil, "la bestia desaparece")
		-- Terminar otra vez no vuelve a pagar.
		s.EventService.finish(true)
		s.EventService.stop()
		expect.equal(anaSession.profile.coins - anaCoins, 20 * 14 * 3)
	end)

	test("GIANT_BEAST: completar el objetivo duplica el premio y lo termina al instante", function()
		local h, s = Fixtures.server()
		local ana, anaSession = h:joinPlayer(1, "Ana")
		s.EventService.forceStart("GIANT_BEAST")
		anaSession.profile.upgrades.INVENTORY = 10
		s.FoodService.give(anaSession, "MEGA_MELON", 10) -- 50 puntos; objetivo 220
		h:moveTo(ana, V3.new(0, 5, 20))
		local coins = anaSession.profile.coins
		for _ = 1, 10 do
			Fixtures.act(h, ana, "GiantFeed", "MEGA_MELON")
		end
		expect.equal(eventState(h):GetAttribute("Phase"), "Idle", "termina al llegar al objetivo")
		expect.equal(anaSession.profile.inventory.MEGA_MELON, 5, "no consume comida de más")
		expect.equal(anaSession.profile.coins - coins, 250 * 3 * 2)
		expect.equal(anaSession.profile.stats.giantFeeds, 5)
	end)

	test("recompensas de la bestia (puro): tope por jugador y sin duplicados", function()
		local h = Fixtures.server()
		local Logic = Fixtures.logic(h, "EventLogic")
		local rewards, total = Logic.giantRewards({ [1] = 300, [2] = 100, [3] = 0, [4] = -5, [5] = 0 / 0 }, true)
		expect.equal(total, 400)
		expect.equal(Fixtures.count(rewards), 2)
		expect.equal(rewards[1].coins, 300 * 3 * 2)
		expect.near(rewards[1].share, 0.75)
		expect.truthy(rewards[1].top)
		expect.falsy(rewards[2].top)
		local big = Logic.giantRewards({ [1] = 1e12 }, true)
		expect.equal(big[1].coins, 250000)
		expect.equal(Logic.truffleChance(rewards[1], true), 0.2)
		expect.equal(Logic.truffleChance(rewards[2], true), 0.05)
		expect.equal(Logic.truffleChance(rewards[1], false), 0)
		expect.equal(Logic.truffleChance({ share = 0.01, top = false }, true), 0)
	end)

	test("quien entra a mitad de evento lo ve activo y puede participar", function()
		local h, s = Fixtures.server()
		local ana = h:joinPlayer(1, "Ana")
		s.EventService.forceStart("GIANT_BEAST")
		h:step(1, 10)
		local beto, betoSession = h:joinPlayer(2, "Beto")
		local folder = eventState(h)
		expect.equal(folder:GetAttribute("EventId"), "GIANT_BEAST")
		expect.equal(folder:GetAttribute("Phase"), "Active")
		expect.greater(folder:GetAttribute("EndsAt"), h.clock.server)
		s.FoodService.give(betoSession, "PIZZA", 1)
		h:moveTo(beto, V3.new(0, 5, 20))
		Fixtures.act(h, beto, "GiantFeed", "PIZZA")
		expect.equal(folder:GetAttribute("Progress"), 14)
	end)

	TestKit.suite("Administración")

	test("un jugador normal no puede ejecutar comandos de administración", function()
		local h, s = Fixtures.server({ isStudio = false })
		local player, session = h:joinPlayer(1, "Ana")
		expect.falsy(s.AdminService.isAdmin(player))
		expect.equal(h:stateFor(1).isAdmin, false)
		for _, command in ipairs({ { "coins", "1000000" }, { "egg", "NULLABYTE", "COSMIC" }, { "event", "FOOD_RAIN" }, { "pass", "VIP" }, { "mutate", "all", "COSMIC" } }) do
			Fixtures.act(h, player, "Admin", command[1], command[2], command[3])
		end
		expect.equal(session.profile.coins, 50)
		expect.equal(Fixtures.count(session.profile.creatures), 1)
		expect.equal((s.EventService.current()), nil)
		expect.falsy(session.passes.VIP)
		expect.truthy(Fixtures.hasWarning(h, "[Admin] DENIED"), "queda registrado")
	end)

	test("los administradores autorizados (lista explícita o creador) sí pueden", function()
		local h, s = Fixtures.server({
			isStudio = false,
			before = function(h)
				Fixtures.config(h, "GameConfig").Admins.UserIds = { 7 }
				h.creatorId = 8
			end,
		})
		local admin, session = h:joinPlayer(7, "Admin")
		local creator = h:joinPlayer(8, "Creador")
		local normal = h:joinPlayer(9, "Normal")
		expect.truthy(s.AdminService.isAdmin(admin))
		expect.truthy(s.AdminService.isAdmin(creator))
		expect.falsy(s.AdminService.isAdmin(normal))
		Fixtures.act(h, admin, "Admin", "coins", "1000")
		expect.equal(session.profile.coins, 1050)
		Fixtures.act(h, admin, "Admin", "egg", "NULLABYTE", "COSMIC")
		expect.equal(Fixtures.count(session.profile.creatures), 2)
		Fixtures.act(h, admin, "Admin", "event", "FOOD_RAIN")
		expect.equal((s.EventService.current()), "FOOD_RAIN")
		Fixtures.act(h, admin, "Admin", "noexiste")
		Fixtures.act(h, admin, "Admin", "coins", "-5")
		expect.equal(session.profile.coins, 1050)
	end)
end
