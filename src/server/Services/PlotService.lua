-- Parcelas: asignación, propietario, estilo y zonas de interacción (recogida y entrega).
-- Las zonas se comprueban por distancia en el servidor (no se confía en Touched ni en el cliente).
--
-- API:
--   PlotService.plot(index) -> plotInfo
--   PlotService.spawnCFrame(index), PlotService.slotCFrame(index, slot)
--   PlotService.setEconomy(index, income, pending, cap)
--   PlotService.refresh(session)      -- estilo, espacios desbloqueados, aura
--   PlotService.isInside(index, position) -> bool
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local Constants = require(Shared.Constants)
local EconomyMath = require(Shared.Logic.EconomyMath)
local Clock = require(Shared.Clock)

local WorldBuilder = require(script.Parent.Parent.WorldBuilder)

local PlotService = {}

local services
local world
local owners = {} -- index -> userId
local padTimer = 0
local padCooldown = {} -- userId -> reloj de la última recogida

local A = Constants.PlotAttr

local applyStyle -- definida más abajo

function PlotService.Init(allServices)
	services = allServices
	world = WorldBuilder.build()
	-- Las parcelas sin dueño se muestran con los corrales cerrados y sin decoración.
	for _, plot in ipairs(world.plots) do
		applyStyle(plot, 0, 0, false)
	end
end

function PlotService.world()
	return world
end

function PlotService.plot(index)
	return world.plots[index]
end

function PlotService.spawnCFrame(index)
	local plot = world.plots[index]
	return plot and plot.spawnCFrame or nil
end

function PlotService.slotCFrame(index, slot)
	local plot = world.plots[index]
	return plot and plot.slotCFrames[slot] or nil
end

function PlotService.ownerOf(index)
	return owners[index]
end

-- ¿Está la posición dentro del cuadrado de la parcela (con margen)?
function PlotService.isInside(index, position, margin)
	local plot = world.plots[index]
	if not plot then
		return false
	end
	local localPos = plot.cframe:PointToObjectSpace(position)
	local half = GameConfig.World.PlotSize / 2 + (margin or 0)
	return math.abs(localPos.X) <= half and math.abs(localPos.Z) <= half
end

function PlotService.setEconomy(index, income, pending, cap)
	local plot = world.plots[index]
	if not plot then
		return
	end
	local model = plot.model
	-- Solo se escribe si cambia el valor visible para no replicar de más.
	local incomeRounded = math.floor(income * 10 + 0.5) / 10
	if model:GetAttribute(A.Income) ~= incomeRounded then
		model:SetAttribute(A.Income, incomeRounded)
	end
	local pendingFloor = math.floor(pending)
	if model:GetAttribute(A.Pending) ~= pendingFloor then
		model:SetAttribute(A.Pending, pendingFloor)
	end
	if model:GetAttribute(A.PendingCap) ~= cap then
		model:SetAttribute(A.PendingCap, cap)
	end
end

function applyStyle(plot, styleLevel, slots, aura)
	local style = UpgradeConfig.PlotStyles[styleLevel] or UpgradeConfig.PlotStyles[0]
	plot.floor.Material = style.floor
	plot.floor.Color = styleLevel >= 2 and Color3.fromRGB(236, 232, 240) or Color3.fromRGB(128, 190, 110)
	for _, trim in ipairs(plot.trims) do
		trim.Material = style.trim
	end
	for slot, pad in ipairs(plot.slotPads) do
		local unlocked = slot <= slots
		pad.Transparency = unlocked and 0 or 0.7
		pad.Color = unlocked and Color3.fromRGB(236, 214, 150) or Color3.fromRGB(96, 98, 112)
	end
	-- Decoración desbloqueada por "Plot Makeover": cada nivel añade la suya (cosmética).
	for level, parts in ipairs(plot.decor) do
		local shown = styleLevel >= level
		for _, part in ipairs(parts) do
			part.Transparency = shown and (part:GetAttribute("ShownTransparency") or 0) or 1
		end
	end
	plot.model:SetAttribute(A.Style, styleLevel)
	plot.model:SetAttribute(A.Aura, aura == true)
	plot.model:SetAttribute("Slots", slots)
end

function PlotService.refresh(session)
	local plot = session.plotIndex and world.plots[session.plotIndex]
	if not plot then
		return
	end
	applyStyle(
		plot,
		EconomyMath.upgradeLevel(session.profile, "PLOT_STYLE"),
		services.CreatureService.slotCount(session),
		session.profile.cosmetics.PLOT_AURA == true
	)
end

local function assign(session)
	for index = 1, GameConfig.PlotCount do
		if owners[index] == nil then
			owners[index] = session.userId
			session.plotIndex = index
			local plot = world.plots[index]
			plot.model:SetAttribute(A.Owner, session.userId)
			plot.model:SetAttribute(A.OwnerName, session.player.DisplayName)
			return index
		end
	end
	return nil
end

local function release(session)
	local index = session.plotIndex
	if not index or owners[index] ~= session.userId then
		return
	end
	owners[index] = nil
	padCooldown[session.userId] = nil
	local plot = world.plots[index]
	plot.model:SetAttribute(A.Owner, 0)
	plot.model:SetAttribute(A.OwnerName, "")
	applyStyle(plot, 0, 0, false)
	PlotService.setEconomy(index, 0, 0, 0)
	session.plotIndex = nil
end

function PlotService.Start()
	-- La asignación debe ocurrir antes de que otros servicios reaccionen a SessionStarted,
	-- por eso PlotService se inicia el primero (ver Bootstrap).
	services.PlayerDataService.SessionStarted:Connect(function(session)
		local index = assign(session)
		if not index then
			warn("[Plot] no free plot for " .. tostring(session.userId))
			session.player:Kick("El servidor está lleno.")
			return
		end
	end)
	services.PlayerDataService.SessionEnding:Connect(release)
end

-- Comprobación periódica de zonas (recogida de ganancias y entrega de cajas).
function PlotService.Update(dt)
	padTimer += dt
	if padTimer < 0.15 then
		return
	end
	padTimer = 0
	local now = Clock.now()
	services.PlayerDataService.forEach(function(session)
		local plot = session.plotIndex and world.plots[session.plotIndex]
		if not plot then
			return
		end
		local position = services.CharacterService.positionOf(session.userId)
		if not position then
			return
		end
		local flat = Vector3.new(position.X, plot.collectPos.Y, position.Z)
		if (flat - plot.collectPos).Magnitude <= 5.5 and math.abs(position.Y - plot.collectPos.Y) < 12 then
			if now - (padCooldown[session.userId] or -math.huge) >= 0.75 and session.profile.pendingCoins >= 1 then
				padCooldown[session.userId] = now
				services.EconomyService.collect(session.userId)
			end
		end
		if (flat - plot.deliveryPos).Magnitude <= 5.5 and math.abs(position.Y - plot.deliveryPos.Y) < 12 then
			services.TheftService.tryDeliver(session.userId)
		end
	end)
end

return PlotService
