-- Cajas de comida transportables y robables (nunca se roban criaturas).
-- Cada caja tiene una StealStateMachine pura; este servicio valida en servidor distancia,
-- cooldowns, protección de novatos, capacidad (una caja por jugador) y velocidad del portador,
-- y aplica los efectos en el mundo. Las desconexiones se resuelven sin duplicar ni perder cajas.
--
-- API:
--   TheftService.tryDeliver(userId)        -- llamado por PlotService al pisar la zona de entrega
--   TheftService.dropCarried(userId)
--   TheftService.refreshSpeed(userId)
--   TheftService.spawnCrate(tierId, position) -> entry
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local TheftConfig = require(Shared.Config.TheftConfig)
local FoodConfig = require(Shared.Config.FoodConfig)
local Constants = require(Shared.Constants)
local EconomyMath = require(Shared.Logic.EconomyMath)
local StealStateMachine = require(Shared.Logic.StealStateMachine)
local Rolls = require(Shared.Logic.Rolls)
local PlotLayout = require(Shared.Logic.PlotLayout)
local Utilities = require(Shared.Utilities)
local Clock = require(Shared.Clock)

local TheftService = {}

local S = StealStateMachine.States
local A = Constants.CrateAttr

local services
local folder
local crates = {} -- crateId -> entry
local carrying = {} -- userId -> crateId
local stealCooldown = {} -- userId -> reloj
local noPickupUntil = {} -- userId -> reloj
local lastPositions = {} -- userId -> { position, time }
local nextId = 1
local spawnTimer = 0
local scanTimer = 0
local speedTimer = 0
local rng = Random.new()

local GROUND_Y = 1.9
local CARRY_OFFSET = CFrame.new(0, 4.6, 0)

local function rnd()
	return rng:NextNumber()
end

local function sync(entry)
	local machine = entry.machine
	entry.part:SetAttribute(A.State, machine.state)
	entry.part:SetAttribute(A.Carrier, machine.carrier or 0)
	entry.prompt.Enabled = machine.state == S.CARRIED or machine.state == S.BEING_STOLEN
end

local function detach(entry)
	if entry.weld then
		entry.weld:Destroy()
		entry.weld = nil
	end
end

local function attach(entry, userId)
	detach(entry)
	local root = services.CharacterService.rootOf(userId)
	if not root then
		return false
	end
	local part = entry.part
	part.Anchored = false
	part.CFrame = root.CFrame * CARRY_OFFSET
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
	entry.weld = weld
	return true
end

function TheftService.refreshSpeed(userId)
	local session = services.PlayerDataService.getSession(userId)
	if not session then
		return
	end
	local mult = 1
	if carrying[userId] then
		mult = EconomyMath.carrySpeedMult(session.profile)
	end
	services.CharacterService.setSpeedMult(userId, mult)
end

local function setCarrier(entry, userId)
	carrying[userId] = entry.id
	-- El punto de partida del control de velocidad es donde se recoge la caja.
	local position = services.CharacterService.positionOf(userId)
	lastPositions[userId] = position and { position = position, time = Clock.now() } or nil
	TheftService.refreshSpeed(userId)
end

local function clearCarrier(userId)
	carrying[userId] = nil
	lastPositions[userId] = nil
	TheftService.refreshSpeed(userId)
end

-- Deja la caja en el suelo en `position` (se acota al mapa).
local function placeOnGround(entry, position)
	detach(entry)
	local limit = GameConfig.World.GroundSize / 2 - 6
	local x = math.clamp(position.X, -limit, limit)
	local z = math.clamp(position.Z, -limit, limit)
	entry.position = Vector3.new(x, GROUND_Y, z)
	entry.part.Anchored = true
	entry.part.CFrame = CFrame.new(entry.position)
	entry.groundSince = Clock.now()
	sync(entry)
end

local function destroyCrate(entry)
	crates[entry.id] = nil
	detach(entry)
	entry.part:Destroy()
end

function TheftService.spawnCrate(tierId, position)
	local tier = TheftConfig.Tiers[tierId]
	if not tier then
		return nil
	end
	local id = "crate" .. nextId
	nextId += 1

	local part = Instance.new("Part")
	part.Name = "Crate_" .. tierId
	part.Size = Vector3.new(3.2, 3.2, 3.2)
	part.Color = tier.color
	part.Material = tier.material
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = CFrame.new(position)
	part:SetAttribute(A.Id, id)
	part:SetAttribute(A.Tier, tierId)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StealPrompt"
	prompt.ActionText = "Steal"
	prompt.ObjectText = tier.name
	prompt.HoldDuration = TheftConfig.HoldDuration
	prompt.MaxActivationDistance = TheftConfig.StealDistance
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = part

	local entry = {
		id = id,
		tier = tier,
		part = part,
		prompt = prompt,
		machine = StealStateMachine.new(id, tierId),
		position = position,
		groundSince = Clock.now(),
		stealBeganAt = nil,
	}
	crates[id] = entry

	prompt.PromptButtonHoldBegan:Connect(function(player)
		TheftService.beginSteal(player, entry)
	end)
	prompt.PromptButtonHoldEnded:Connect(function(player)
		TheftService.cancelSteal(player, entry)
	end)
	prompt.Triggered:Connect(function(player)
		TheftService.completeSteal(player, entry)
	end)

	sync(entry)
	part.Parent = folder
	CollectionService:AddTag(part, Constants.Tags.Crate)
	return entry
end

local function isNewbie(session)
	return services.PlayerDataService.playTime(session) < GameConfig.NewPlayerProtectionSeconds
end

local function pickup(session, entry)
	local userId = session.userId
	local shield = EconomyMath.shieldSeconds(session.profile)
	local ok = entry.machine:pickup(userId, Clock.now(), shield)
	if not ok then
		return false
	end
	if not attach(entry, userId) then
		entry.machine:drop()
		sync(entry)
		return false
	end
	setCarrier(entry, userId)
	sync(entry)
	services.ValidationService.notify(session.player, "You grabbed a " .. entry.tier.name .. "! Bring it to your blue pad.", "info", "📦")
	return true
end

-- Validaciones comunes de un intento de robo. Devuelve (sesiónLadrón, sesiónVíctima) o nil, motivo.
local function validateSteal(player, entry, extraDistance)
	local thief = services.PlayerDataService.sessionOf(player)
	if not thief or crates[entry.id] ~= entry then
		return nil, "invalid"
	end
	local victimId = entry.machine.carrier
	if not victimId or victimId == thief.userId then
		return nil, "own_crate"
	end
	local victim = services.PlayerDataService.getSession(victimId)
	if not victim then
		return nil, "invalid"
	end
	if carrying[thief.userId] then
		return nil, "already_carrying"
	end
	local thiefPos = services.CharacterService.positionOf(thief.userId)
	local victimPos = services.CharacterService.positionOf(victimId)
	if not thiefPos or not victimPos then
		return nil, "no_character"
	end
	if (thiefPos - victimPos).Magnitude > TheftConfig.StealDistance + (extraDistance or 0) then
		return nil, "too_far"
	end
	return thief, victim
end

function TheftService.beginSteal(player, entry)
	local thief, victim = validateSteal(player, entry, 2)
	if not thief then
		return false, victim
	end
	local now = Clock.now()
	if now < (stealCooldown[thief.userId] or 0) then
		return false, "cooldown"
	end
	local ok, reason = entry.machine:beginSteal(thief.userId, now, { victimProtected = isNewbie(victim) })
	if not ok then
		if reason == "victim_protected" then
			services.ValidationService.notify(player, "That player is new and protected.", "info", "🛡️")
		elseif reason == "protected" then
			services.ValidationService.notify(player, "That crate is shielded!", "info", "🛡️")
		end
		sync(entry)
		return false, reason
	end
	entry.stealBeganAt = now
	sync(entry)
	return true, nil
end

function TheftService.cancelSteal(player, entry)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	if entry.machine:cancelSteal(player.UserId) then
		entry.stealBeganAt = nil
		sync(entry)
	end
end

function TheftService.completeSteal(player, entry)
	local machine = entry.machine
	-- Si el motor dispara Triggered sin HoldBegan (p. ej. mando), se inicia aquí con las mismas reglas.
	if machine.state == S.CARRIED or machine.state == S.PROTECTED then
		local began = TheftService.beginSteal(player, entry)
		if not began then
			return false
		end
		entry.stealBeganAt = Clock.now() - TheftConfig.HoldDuration
	end
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end
	if machine.state ~= S.BEING_STOLEN or machine.thief ~= player.UserId then
		return false
	end
	local thief, victim = validateSteal(player, entry, 5)
	local now = Clock.now()
	local heldLongEnough = entry.stealBeganAt ~= nil and (now - entry.stealBeganAt) >= TheftConfig.HoldDuration * 0.8
	if not thief or not heldLongEnough then
		machine:cancelSteal(player.UserId)
		entry.stealBeganAt = nil
		sync(entry)
		return false
	end

	local ok, info = machine:completeSteal(thief.userId, now, TheftConfig.TransferImmunity, TheftConfig.RecoveryWindow)
	if not ok then
		return false
	end
	entry.stealBeganAt = nil
	stealCooldown[thief.userId] = now + TheftConfig.StealCooldown
	clearCarrier(victim.userId)
	if not attach(entry, thief.userId) then
		-- El ladrón perdió el personaje justo ahora: la caja cae donde estaba la víctima.
		machine:drop()
		placeOnGround(entry, services.CharacterService.positionOf(victim.userId) or entry.position)
		return false
	end
	setCarrier(entry, thief.userId)
	sync(entry)

	local position = services.CharacterService.positionOf(thief.userId) or entry.position
	if info.recovered then
		thief.profile.stats.cratesRecovered += 1
		local bonus = TheftConfig.RecoveryBonusCoins + math.floor(services.EconomyService.income(thief) * TheftConfig.RecoveryBonusIncomeSeconds)
		services.EconomyService.addCoins(thief.userId, bonus)
		services.ValidationService.notify(thief.player, "Crate recovered! +" .. Utilities.formatNumber(bonus), "reward", "🦸")
		services.ValidationService.notify(victim.player, thief.player.DisplayName .. " took their crate back!", "alert", "😱")
		services.VFXService.playAll("Recover", { position = position, radius = 2.5 })
	else
		thief.profile.stats.cratesStolen += 1
		services.ValidationService.notify(thief.player, "Stolen! Run to your blue pad!", "reward", "😈")
		services.ValidationService.notify(victim.player, thief.player.DisplayName .. " stole your crate! Get it back!", "alert", "🚨")
		services.VFXService.playAll("StealSuccess", { position = position, radius = 2.5 })
	end
	services.StateService.push(thief.userId, "stats")
	return true
end

local function dropEntry(entry, position)
	local carrier = entry.machine.carrier
	local where = position or (carrier and services.CharacterService.positionOf(carrier)) or entry.position
	if not entry.machine:drop() then
		return false
	end
	if carrier then
		clearCarrier(carrier)
		noPickupUntil[carrier] = Clock.now() + 1.5
	end
	entry.stealBeganAt = nil
	placeOnGround(entry, where)
	return true
end

-- Anti-teleport: un portador que se ha movido muy por encima de su velocidad suelta la caja en
-- su última posición válida. Devuelve false si la soltó. Se comprueba periódicamente y también
-- justo antes de entregar (para que un salto directo a la zona de entrega no sirva de nada).
local function checkSpeed(userId, entry, now)
	local position = services.CharacterService.positionOf(userId)
	if not position then
		return true
	end
	local last = lastPositions[userId]
	if last then
		local elapsed = math.max(0.05, now - last.time)
		local moved = Vector3.new(position.X - last.position.X, 0, position.Z - last.position.Z).Magnitude
		local allowed = services.CharacterService.speedOf(userId) * TheftConfig.SpeedTolerance * elapsed + 6
		if moved > allowed then
			warn(string.format("[Theft] %d moved %.1f studs in %.2fs while carrying; dropping crate", userId, moved, elapsed))
			dropEntry(entry, last.position)
			return false
		end
	end
	lastPositions[userId] = { position = position, time = now }
	return true
end

function TheftService.dropCarried(userId)
	local entry = carrying[userId] and crates[carrying[userId]]
	if not entry then
		return false
	end
	return dropEntry(entry, nil)
end

function TheftService.carriedBy(userId)
	return carrying[userId] and crates[carrying[userId]] or nil
end

-- Recompensas de una caja entregada.
local function reward(session, entry, stolen)
	local tier = entry.tier
	local profile = session.profile
	local mult = services.EventService.crateMult()
	local coins = (tier.coins + services.EconomyService.income(session) * tier.incomeSeconds) * mult
	if stolen then
		coins *= TheftConfig.HeistBonusMult
	end
	local foods = {}
	local overflowCoins = 0
	for _ = 1, tier.rolls do
		local rarity = Rolls.weighted(tier.rarities, rnd)
		local foodId = rarity and Rolls.foodOfRarity(rarity, rnd)
		if foodId then
			if services.FoodService.give(session, foodId, 1) > 0 then
				foods[foodId] = (foods[foodId] or 0) + 1
			else
				-- Mochila llena: se convierte en monedas para no perder la recompensa.
				overflowCoins += FoodConfig.Foods[foodId].price
			end
		end
	end
	coins = math.floor(coins + overflowCoins)
	services.EconomyService.addCoins(session.userId, coins)
	profile.stats.cratesDelivered += 1
	services.QuestService.progress(session, "CrateDelivered", 1)
	services.StateService.push(session.userId, "stats")

	local parts = {}
	for foodId, count in pairs(foods) do
		table.insert(parts, string.format("%dx %s", count, FoodConfig.Foods[foodId].icon))
	end
	table.sort(parts)
	local text = string.format("%s delivered! +%s coins %s", stolen and "HEIST" or "Crate", Utilities.formatNumber(coins), table.concat(parts, " "))
	services.ValidationService.notify(session.player, text, "reward", "📦")
end

function TheftService.tryDeliver(userId)
	local entry = carrying[userId] and crates[carrying[userId]]
	if not entry then
		return false
	end
	local session = services.PlayerDataService.getSession(userId)
	if not session or not session.plotIndex then
		return false
	end
	if not checkSpeed(userId, entry, Clock.now()) then
		return false
	end
	-- Doble comprobación de posición en servidor.
	local position = services.CharacterService.positionOf(userId)
	local plot = services.PlotService.plot(session.plotIndex)
	if not position or not plot or (Vector3.new(position.X, plot.deliveryPos.Y, position.Z) - plot.deliveryPos).Magnitude > TheftConfig.DeliverDistance then
		return false
	end
	local ok, info = entry.machine:deliver(userId)
	if not ok then
		return false
	end
	clearCarrier(userId)
	local effectPos = plot.deliveryPos
	destroyCrate(entry)
	reward(session, entry, info.stolen)
	services.VFXService.playAll("CrateDeliver", { position = effectPos, radius = 3 })
	return true
end

local function spawnRandomCrate()
	local available = 0
	for _, entry in pairs(crates) do
		if entry.machine.state == S.AVAILABLE then
			available += 1
		end
	end
	if available >= TheftConfig.MaxActive then
		return
	end
	local weights = {}
	for _, id in ipairs(TheftConfig.TierOrder) do
		weights[id] = TheftConfig.Tiers[id].weight
	end
	local tierId = Rolls.weighted(weights, rnd, TheftConfig.TierOrder)
	local x, z = PlotLayout.foodPoint(rnd)
	local entry = TheftService.spawnCrate(tierId, Vector3.new(x, GROUND_Y, z))
	if entry and tierId ~= "WOOD" then
		services.VFXService.announce("A " .. entry.tier.name .. " appeared in the plaza!", entry.tier.color)
	end
end

function TheftService.Init(allServices)
	services = allServices
	folder = workspace:FindFirstChild(Constants.Folders.Crates)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Constants.Folders.Crates
		folder.Parent = workspace
	end
end

function TheftService.Start()
	services.ValidationService.on("DropCrate", function(player)
		TheftService.dropCarried(player.UserId)
	end)

	services.CharacterService.Died:Connect(function(userId)
		TheftService.dropCarried(userId)
	end)

	-- Desconexión: la caja cae donde estaba; un robo en curso del que se va se cancela.
	services.PlayerDataService.SessionEnding:Connect(function(session)
		local userId = session.userId
		local lastKnown = services.CharacterService.positionOf(userId) or (lastPositions[userId] and lastPositions[userId].position)
		for _, entry in pairs(crates) do
			local wasCarrier = entry.machine.carrier == userId
			local result = entry.machine:playerLeft(userId)
			if result == "dropped" then
				entry.stealBeganAt = nil
				placeOnGround(entry, lastKnown or entry.position)
			elseif result == "cancelled" then
				entry.stealBeganAt = nil
				sync(entry)
			end
			if wasCarrier then
				carrying[userId] = nil
			end
		end
		carrying[userId] = nil
		stealCooldown[userId] = nil
		noPickupUntil[userId] = nil
		lastPositions[userId] = nil
	end)
end

function TheftService.Update(dt)
	local now = Clock.now()

	spawnTimer += dt
	if spawnTimer >= TheftConfig.SpawnInterval then
		spawnTimer = 0
		if services.PlayerDataService.count() > 0 then
			spawnRandomCrate()
		end
	end

	scanTimer += dt
	if scanTimer >= 0.15 then
		scanTimer = 0
		for _, entry in pairs(crates) do
			local machine = entry.machine
			-- Fin de la protección temporal.
			if machine:tick(now) then
				sync(entry)
			end
			-- Robo que nunca se completó (el cliente dejó de responder).
			if machine.state == S.BEING_STOLEN and entry.stealBeganAt and now - entry.stealBeganAt > TheftConfig.HoldDuration + 1.5 then
				machine:cancelSteal(nil)
				entry.stealBeganAt = nil
				sync(entry)
			end
			-- Portador sin personaje (cayó al vacío, reapareció...).
			if machine.carrier and not services.CharacterService.positionOf(machine.carrier) then
				local last = lastPositions[machine.carrier]
				dropEntry(entry, last and last.position or entry.position)
			end
			if machine.state == S.AVAILABLE and now - entry.groundSince > TheftConfig.GroundLifetime then
				destroyCrate(entry)
			end
		end

		-- Recogida del suelo por proximidad (una caja por jugador).
		services.PlayerDataService.forEach(function(session)
			local userId = session.userId
			if carrying[userId] or now < (noPickupUntil[userId] or 0) then
				return
			end
			local position = services.CharacterService.positionOf(userId)
			if not position then
				return
			end
			for _, entry in pairs(crates) do
				if entry.machine.state == S.AVAILABLE then
					local delta = entry.position - position
					if math.abs(delta.Y) < 10 and delta.X * delta.X + delta.Z * delta.Z <= 5.5 * 5.5 then
						if pickup(session, entry) then
							break
						end
					end
				end
			end
		end)
	end

	-- Anti-teleport periódico.
	speedTimer += dt
	if speedTimer >= TheftConfig.SpeedCheckInterval then
		speedTimer = 0
		for userId, crateId in pairs(table.clone(carrying)) do
			local entry = crates[crateId]
			if entry then
				checkSpeed(userId, entry, now)
			end
		end
	end
end

function TheftService.debugCrates()
	return crates
end

return TheftService
