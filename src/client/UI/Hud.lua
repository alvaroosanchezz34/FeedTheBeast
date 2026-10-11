-- HUD permanente: monedas y producción, estado (protección, boosts...), botones de menú,
-- barra de comida, aviso de caja transportada, banner de evento y objetivo del tutorial.
-- Solo MUESTRA el estado que envía el servidor.
--
-- Distribución pensada para móvil y PC: monedas y menú a la izquierda (lejos del botón de salto),
-- barra de comida abajo en el centro (entre el joystick y el salto) y avisos arriba en el centro.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FoodConfig = require(Shared.Config.FoodConfig)
local EventConfig = require(Shared.Config.EventConfig)
local TheftConfig = require(Shared.Config.TheftConfig)
local Constants = require(Shared.Constants)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local EconomyMath = require(Shared.Logic.EconomyMath)
local Utilities = require(Shared.Utilities)

local Theme = require(script.Parent.Theme)
local FoodIcon = require(script.Parent.FoodIcon)

local Hud = {}

local C = Theme.Colors
local MAX_SLOTS = 8

function Hud.create(ctx)
	local State = ctx.State
	local layer = ctx.layers.hud
	local hud = {}

	---------------------------------------------------------------------------------------
	-- Monedas y producción
	---------------------------------------------------------------------------------------
	local currency = Theme.panel({ name = "Currency", size = UDim2.fromOffset(250, 66), position = UDim2.fromOffset(14, 10) }, layer)
	Theme.label({ name = "Icon", text = "💰", size = UDim2.fromOffset(56, 66), textSize = 34 }, currency)
	local coinsLabel = Theme.label({
		name = "Coins",
		text = "0",
		font = Theme.Fonts.Display,
		textSize = 30,
		color = C.Gold,
		stroke = true,
		size = UDim2.new(1, -66, 0, 36),
		position = UDim2.fromOffset(58, 5),
		alignX = Enum.TextXAlignment.Left,
	}, currency)
	local incomeLabel = Theme.label({
		name = "Income",
		text = "+0/s",
		textSize = 15,
		color = C.Green,
		size = UDim2.new(1, -66, 0, 20),
		position = UDim2.fromOffset(58, 40),
		alignX = Enum.TextXAlignment.Left,
	}, currency)

	local shownCoins, targetCoins = 0, 0
	local coinsKnown = false
	local function setCoins(value)
		targetCoins = value or 0
		-- El primer valor y los cambios pequeños se muestran al instante; un salto grande se anima.
		if not coinsKnown or math.abs(targetCoins - shownCoins) < 2 then
			coinsKnown = true
			shownCoins = targetCoins
			coinsLabel.Text = Utilities.formatNumber(shownCoins)
		end
	end

	---------------------------------------------------------------------------------------
	-- Chips de estado
	---------------------------------------------------------------------------------------
	local chips = Theme.box({ name = "Status", size = UDim2.fromOffset(250, 0), position = UDim2.fromOffset(14, 84), automatic = Enum.AutomaticSize.Y }, layer)
	Theme.list(chips, "V", 4)
	local chipLabels = {}
	local function chip(id, order, color)
		local frame, label = Theme.chip({ name = "Chip_" .. id, size = UDim2.fromOffset(250, 24), color = color, order = order, textSize = 14 }, chips)
		frame.Visible = false
		chipLabels[id] = { frame = frame, label = label }
	end
	chip("ephemeral", 1, C.Red)
	chip("protection", 2, C.Blue)
	chip("growth", 3, C.Orange)
	chip("event", 4, C.Gold)
	chip("rebirth", 5, C.Pink)
	chip("vip", 6, C.Purple)

	local function setChip(id, text)
		local entry = chipLabels[id]
		entry.frame.Visible = text ~= nil
		if text then
			entry.label.Text = text
		end
	end

	---------------------------------------------------------------------------------------
	-- Menú
	---------------------------------------------------------------------------------------
	local menu = Theme.box({ name = "Menu", size = UDim2.fromOffset(150, 0), position = UDim2.new(0, 14, 0.5, 30), anchor = Vector2.new(0, 0.5), automatic = Enum.AutomaticSize.Y }, layer)
	Theme.list(menu, "V", 8)
	local menuButtons = {}
	local function menuButton(id, icon, text, color, order)
		local button = Theme.button({
			name = "Menu_" .. id,
			icon = icon,
			text = text,
			color = color,
			size = UDim2.fromOffset(150, 58),
			textSize = 19,
			order = order,
			onClick = function()
				ctx.toggle(id)
			end,
		}, menu)
		-- Indicador "hay algo que hacer aquí".
		local badge = Theme.panel({ name = "Badge", size = UDim2.fromOffset(24, 24), position = UDim2.new(1, -4, 0, -6), anchor = Vector2.new(1, 0), color = C.Red, radius = 12, strokeThickness = 2, zindex = 3 }, button.instance)
		Theme.label({ text = "!", font = Theme.Fonts.Display, textSize = 18, zindex = 3 }, badge)
		badge.Visible = false
		menuButtons[id] = { button = button, badge = badge }
	end
	menuButton("shop", "🛒", "SHOP", C.Orange, 1)
	menuButton("beasts", "🐾", "BEASTS", C.Blue, 2)
	menuButton("upgrades", "⬆️", "UPGRADES", C.Green, 3)
	menuButton("rebirth", "🔥", "REBIRTH", C.Pink, 4)

	Theme.button({
		name = "Settings",
		text = "⚙️",
		color = C.Grey,
		size = UDim2.fromOffset(60, 60),
		position = UDim2.fromOffset(272, 13),
		textSize = 26,
		onClick = function()
			ctx.toggle("settings")
		end,
	}, layer)

	local function refreshBadges()
		local coins = State.get("coins") or 0
		local upgrades = State.get("upgrades")
		local affordable = false
		if upgrades then
			for _, cost in pairs(upgrades.costs) do
				if cost >= 0 and coins >= cost then
					affordable = true
					break
				end
			end
		end
		menuButtons.upgrades.badge.Visible = affordable

		local rebirths = State.get("rebirths") or 0
		local best = 0
		for _, creature in ipairs(State.get("creatures") or {}) do
			best = math.max(best, creature.level)
		end
		menuButtons.rebirth.badge.Visible = coins >= EconomyMath.rebirthCost(rebirths) and best >= EconomyMath.rebirthRequiredLevel(rebirths)
	end

	---------------------------------------------------------------------------------------
	-- Barra de comida
	---------------------------------------------------------------------------------------
	local hotbar = Theme.panel({
		name = "Hotbar",
		size = UDim2.fromOffset(0, 84),
		position = UDim2.new(0.5, 0, 1, -12),
		anchor = Vector2.new(0.5, 1),
		color = C.PanelDark,
		transparency = 0.15,
	}, layer)
	hotbar.AutomaticSize = Enum.AutomaticSize.X
	Theme.padding(hotbar, 10, 8)
	Theme.list(hotbar, "H", 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)

	local bag = Theme.box({ name = "Bag", size = UDim2.fromOffset(74, 68), order = 0 }, hotbar)
	Theme.label({ text = "🎒", size = UDim2.new(1, 0, 0, 38), textSize = 30 }, bag)
	local bagLabel = Theme.label({ name = "Count", text = "0/10", size = UDim2.new(1, 0, 0, 24), position = UDim2.fromOffset(0, 40), textSize = 16, font = Theme.Fonts.Display, stroke = true }, bag)

	local emptyHint = Theme.label({
		name = "Empty",
		text = "No food yet — grab some!",
		size = UDim2.fromOffset(230, 68),
		textSize = 16,
		color = C.TextDim,
		order = 1,
	}, hotbar)

	local selectedInfo = Theme.label({
		name = "SelectedInfo",
		text = "",
		size = UDim2.fromOffset(520, 24),
		position = UDim2.new(0.5, 0, 1, -100),
		anchor = Vector2.new(0.5, 1),
		textSize = 16,
		stroke = true,
	}, layer)

	local slots = {} -- foodId -> { button, count, stroke }
	local slotOrder = 10

	local function refreshSelection()
		local selected = State.selectedFood()
		for foodId, slot in pairs(slots) do
			local isSelected = foodId == selected
			slot.stroke.Color = isSelected and C.Gold or Theme.rarityColor(FoodConfig.Foods[foodId].rarity)
			slot.stroke.Thickness = isSelected and 5 or 3
		end
		if selected then
			local def = FoodConfig.Foods[selected]
			selectedInfo.Text = string.format("%s %s  ·  +%d growth", def.icon, def.name, def.growth)
			selectedInfo.TextColor3 = Theme.rarityColor(def.rarity)
		elseif next(slots) ~= nil then
			selectedInfo.Text = "AUTO: feeds the favourite or smallest snack · tap a food to choose"
			selectedInfo.TextColor3 = C.TextDim
		else
			selectedInfo.Text = ""
		end
	end

	local function makeSlot(foodId)
		local def = FoodConfig.Foods[foodId]
		local button = Instance.new("TextButton")
		button.Name = "Food_" .. foodId
		button.Size = UDim2.fromOffset(68, 68)
		button.BackgroundColor3 = C.Panel
		button.AutoButtonColor = false
		button.BorderSizePixel = 0
		button.Text = ""
		button.LayoutOrder = slotOrder + (table.find(FoodConfig.Order, foodId) or 0)
		Theme.corner(button, 12)
		local stroke = Theme.stroke(button, Theme.rarityColor(def.rarity), 3)
		FoodIcon.new({ food = foodId, size = UDim2.new(1, -6, 1, -6), position = UDim2.fromOffset(3, 1) }, button)
		local count = Theme.label({
			name = "Count",
			text = "1",
			size = UDim2.fromOffset(40, 22),
			position = UDim2.new(1, -3, 1, -2),
			anchor = Vector2.new(1, 1),
			font = Theme.Fonts.Display,
			textSize = 18,
			alignX = Enum.TextXAlignment.Right,
			stroke = true,
		}, button)
		button.Activated:Connect(function()
			if Theme.onClick then
				Theme.onClick()
			end
			-- Tocar la comida seleccionada vuelve al modo automático.
			if State.selectedFood() == foodId then
				State.selectFood(nil)
			else
				State.selectFood(foodId)
			end
		end)
		button.Parent = hotbar
		return { button = button, count = count, stroke = stroke }
	end

	local overflow = Theme.label({ name = "More", text = "", size = UDim2.fromOffset(48, 68), textSize = 18, font = Theme.Fonts.Display, color = C.TextDim, order = 999 }, hotbar)
	overflow.Visible = false

	local function refreshInventory()
		local inventory = State.get("inventory") or {}
		local capacity = State.get("capacity") or 0
		local total, shown, hidden = 0, 0, 0
		local seen = {}
		for _, foodId in ipairs(FoodConfig.Order) do
			local count = inventory[foodId] or 0
			total += count
			if count > 0 then
				if shown < MAX_SLOTS then
					shown += 1
					seen[foodId] = true
					local slot = slots[foodId]
					if not slot then
						slot = makeSlot(foodId)
						slots[foodId] = slot
					end
					slot.count.Text = tostring(count)
				else
					hidden += 1
				end
			end
		end
		for foodId, slot in pairs(slots) do
			if not seen[foodId] then
				slot.button:Destroy()
				slots[foodId] = nil
			end
		end
		overflow.Visible = hidden > 0
		overflow.Text = "+" .. hidden
		emptyHint.Visible = shown == 0
		bagLabel.Text = string.format("%d/%d", total, capacity)
		bagLabel.TextColor3 = (capacity > 0 and total >= capacity) and C.Red or C.Text
		refreshSelection()
	end

	---------------------------------------------------------------------------------------
	-- Caja transportada
	---------------------------------------------------------------------------------------
	local carry = Theme.panel({
		name = "Carry",
		size = UDim2.fromOffset(520, 56),
		position = UDim2.new(0.5, 0, 1, -132),
		anchor = Vector2.new(0.5, 1),
		color = C.Blue,
	}, layer)
	carry.Visible = false
	local carryLabel = Theme.label({
		text = "",
		size = UDim2.new(1, -130, 1, 0),
		position = UDim2.fromOffset(12, 0),
		font = Theme.Fonts.Display,
		textSize = 18,
		stroke = true,
		alignX = Enum.TextXAlignment.Left,
		scaled = true,
		maxTextSize = 18,
	}, carry)
	Theme.button({
		name = "Drop",
		text = "DROP",
		color = C.Red,
		size = UDim2.fromOffset(104, 42),
		position = UDim2.new(1, -8, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		textSize = 17,
		onClick = function()
			ctx.Input.dropCrate()
		end,
	}, carry)

	local function refreshCarry(carried)
		carry.Visible = carried ~= nil
		selectedInfo.Visible = carried == nil
		if carried then
			local tier = TheftConfig.Tiers[carried.tier]
			carryLabel.Text = string.format("📦 %s — run to your BLUE pad!", tier and string.upper(tier.name) or "CRATE")
			carry.BackgroundColor3 = tier and Theme.darken(tier.color, 0.25) or C.Blue
			local plot = ctx.World.ownPlot()
			ctx.setGuide("carry", plot and plot.deliveryPos or nil, Color3.fromRGB(110, 190, 255))
		else
			ctx.setGuide("carry", nil)
		end
	end

	---------------------------------------------------------------------------------------
	-- Banner de evento
	---------------------------------------------------------------------------------------
	local top = Theme.box({ name = "Top", size = UDim2.fromOffset(460, 0), position = UDim2.new(0.5, 0, 0, 10), anchor = Vector2.new(0.5, 0), automatic = Enum.AutomaticSize.Y }, layer)
	Theme.list(top, "V", 8, Enum.HorizontalAlignment.Center)

	local eventPanel = Theme.panel({ name = "Event", size = UDim2.fromOffset(460, 62), order = 1 }, top)
	eventPanel.Visible = false
	local eventTitle = Theme.label({ name = "Title", text = "", font = Theme.Fonts.Display, textSize = 22, stroke = true, size = UDim2.new(1, -110, 0, 30), position = UDim2.fromOffset(14, 5), alignX = Enum.TextXAlignment.Left }, eventPanel)
	local eventTimer = Theme.label({ name = "Timer", text = "", font = Theme.Fonts.Display, textSize = 22, stroke = true, size = UDim2.fromOffset(96, 30), position = UDim2.new(1, -12, 0, 5), anchor = Vector2.new(1, 0), alignX = Enum.TextXAlignment.Right }, eventPanel)
	local eventBar = Theme.progress({ size = UDim2.new(1, -28, 0, 14), position = UDim2.fromOffset(14, 40), color = C.Gold }, eventPanel)

	local eventFolder = nil
	local EA = Constants.EventAttr

	local function updateEvent()
		if not eventFolder then
			eventFolder = ReplicatedStorage:FindFirstChild(Constants.Folders.EventState)
			if not eventFolder then
				return
			end
		end
		local id = eventFolder:GetAttribute(EA.Id)
		local phase = eventFolder:GetAttribute(EA.Phase)
		local def = id and EventConfig.Events[id]
		if not def or phase == "Idle" or phase == nil then
			eventPanel.Visible = false
			setChip("event", nil)
			return
		end
		eventPanel.Visible = true
		eventPanel.BackgroundColor3 = Theme.darken(def.color, 0.55)
		local now = workspace:GetServerTimeNow()
		local startsAt = eventFolder:GetAttribute(EA.StartsAt) or now
		local endsAt = eventFolder:GetAttribute(EA.EndsAt) or now
		if phase == "Announce" then
			eventTitle.Text = def.icon .. " " .. def.name .. " incoming!"
			eventTimer.Text = Utilities.formatTime(math.max(0, math.ceil(startsAt - now)))
			eventBar.set(1 - math.clamp((startsAt - now) / EventConfig.AnnounceLead, 0, 1), def.color)
			setChip("event", nil)
		else
			eventTitle.Text = def.icon .. " " .. def.name
			eventTimer.Text = Utilities.formatTime(math.max(0, math.ceil(endsAt - now)))
			local goal = eventFolder:GetAttribute(EA.Goal) or 0
			if goal > 0 then
				local progress = eventFolder:GetAttribute(EA.Progress) or 0
				eventBar.set(progress / goal, def.color)
				eventTitle.Text = string.format("%s %s  %d%%", def.icon, def.name, math.floor(progress / goal * 100))
			else
				eventBar.set(math.clamp((endsAt - now) / math.max(1, endsAt - startsAt), 0, 1), def.color)
			end
			setChip("event", def.incomeMult and string.format("%s x%s coins", def.icon, tostring(def.incomeMult)) or nil)
		end
	end

	---------------------------------------------------------------------------------------
	-- Objetivo (tutorial)
	---------------------------------------------------------------------------------------
	local objective = Theme.panel({ name = "Objective", size = UDim2.fromOffset(460, 46), color = C.Green, order = 2 }, top)
	objective.Visible = false
	local objectiveLabel = Theme.label({ text = "", font = Theme.Fonts.Display, textSize = 19, stroke = true, scaled = true, maxTextSize = 19 }, objective)
	Theme.padding(objectiveLabel, 12, 6)

	function hud.setObjective(text, color)
		objective.Visible = text ~= nil
		if text then
			objectiveLabel.Text = "➤ " .. text
			objective.BackgroundColor3 = color or C.Green
		end
	end

	function hud.topContainer()
		return top
	end

	---------------------------------------------------------------------------------------
	-- Suscripciones
	---------------------------------------------------------------------------------------
	State.observe("coins", function(value)
		setCoins(value)
		refreshBadges()
	end)
	State.observe("income", function(value)
		incomeLabel.Text = string.format("+%s/s", Utilities.formatNumber(value or 0))
	end)
	State.observe("inventory", refreshInventory)
	State.observe("capacity", refreshInventory)
	State.observe("upgrades", refreshBadges)
	State.observe("creatures", refreshBadges)
	State.observe("rebirths", function(value)
		refreshBadges()
		local rebirths = value or 0
		setChip("rebirth", rebirths > 0 and string.format("🔥 Rebirth %d · x%s coins", rebirths, tostring(1 + rebirths * EconomyConfig.Rebirth.IncomeMultPerRebirth)) or nil)
	end)
	State.observe("passes", function(passes)
		local bonus = math.floor((EconomyConfig.VIPIncomeMult - 1) * 100 + 0.5)
		setChip("vip", passes and passes.VIP and string.format("👑 VIP · +%d%% coins", bonus) or nil)
	end)
	State.observe("ephemeral", function(value)
		setChip("ephemeral", value and "⚠️ TEST MODE: progress is NOT saved" or nil)
	end)
	State.SelectedFoodChanged:Connect(refreshSelection)
	ctx.World.CarryChanged:Connect(refreshCarry)

	-- La protección de novato llega como "segundos restantes": la cuenta atrás es local.
	local protectionLeft, growthTimer = 0, 0
	State.observe("protection", function(value)
		protectionLeft = value or 0
	end)

	function hud.update(dt)
		-- Contador de monedas animado.
		if shownCoins ~= targetCoins then
			local diff = targetCoins - shownCoins
			local step = diff * math.min(1, dt * 10)
			if math.abs(diff) < 1 then
				shownCoins = targetCoins
			else
				shownCoins += step
			end
			coinsLabel.Text = Utilities.formatNumber(math.floor(shownCoins + 0.5))
		end

		growthTimer += dt
		if growthTimer >= 0.25 then
			if protectionLeft > 0 then
				protectionLeft = math.max(0, protectionLeft - growthTimer)
				setChip("protection", protectionLeft > 0 and ("🛡️ New player shield " .. Utilities.formatTime(protectionLeft)) or nil)
			else
				setChip("protection", nil)
			end
			local growth = State.boostRemaining("Growth")
			setChip("growth", growth > 0 and ("⚡ x2 growth " .. Utilities.formatTime(growth)) or nil)
			growthTimer = 0
			updateEvent()
		end
	end

	refreshInventory()
	refreshBadges()
	return hud
end

return Hud
