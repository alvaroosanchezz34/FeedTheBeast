-- Ventanas de tienda (comida, huevos, premium) y de mejoras. Los precios que se muestran salen
-- de la misma configuración que usa el servidor, pero comprar es solo una petición: el servidor
-- vuelve a comprobar saldo, bloqueo y capacidad.
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FoodConfig = require(Shared.Config.FoodConfig)
local EggConfig = require(Shared.Config.EggConfig)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local CreatureConfig = require(Shared.Config.CreatureConfig)
local RarityConfig = require(Shared.Config.RarityConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local Utilities = require(Shared.Utilities)

local Theme = require(script.Parent.Theme)

local ShopWindow = {}

local C = Theme.Colors

local function coinText(amount)
	return "💰 " .. Utilities.formatNumber(amount)
end

function ShopWindow.register(manager, ctx)
	local State = ctx.State

	local function upgradeLevel(id)
		local upgrades = State.get("upgrades")
		return upgrades and upgrades.levels[id] or 0
	end

	---------------------------------------------------------------------------------------
	-- Comida
	---------------------------------------------------------------------------------------
	local function renderFood(content)
		local scroll = Theme.scroll({}, content)
		Theme.padding(scroll, 6, 6, 14, 6)
		Theme.grid(scroll, UDim2.fromOffset(172, 176), 10)
		local cards = {}

		for index, foodId in ipairs(FoodConfig.Order) do
			local def = FoodConfig.Foods[foodId]
			local rarityColor = Theme.rarityColor(def.rarity)
			local card = Theme.panel({ name = foodId, color = C.PanelDark, strokeColor = rarityColor, order = index }, scroll)
			Theme.label({ text = def.icon, size = UDim2.new(1, 0, 0, 52), position = UDim2.fromOffset(0, 4), textSize = 40 }, card)
			Theme.label({ text = def.name, font = Theme.Fonts.Display, textSize = 16, color = rarityColor, stroke = true, size = UDim2.new(1, -10, 0, 20), position = UDim2.fromOffset(5, 56), scaled = true, maxTextSize = 16 }, card)
			local detail = string.format("+%d growth", def.growth)
			if #def.favoriteOf > 0 then
				local species = CreatureConfig.Species[def.favoriteOf[1]]
				detail ..= "  ·  ❤ " .. (species and species.name or "")
			end
			Theme.label({ text = detail, textSize = 12, color = C.TextDim, size = UDim2.new(1, -8, 0, 16), position = UDim2.fromOffset(4, 78), scaled = true, maxTextSize = 12 }, card)

			local entry = { def = def }
			if def.price > 0 then
				entry.buy = Theme.button({
					name = "Buy",
					text = coinText(def.price),
					color = C.Green,
					size = UDim2.new(0.58, -8, 0, 48),
					position = UDim2.new(0, 6, 1, -8),
					anchor = Vector2.new(0, 1),
					textSize = 16,
					scaled = true,
					onClick = function()
						State.send("BuyFood", foodId, 1)
					end,
				}, card)
				entry.buyFive = Theme.button({
					name = "BuyFive",
					text = "x5",
					color = C.Blue,
					size = UDim2.new(0.42, -8, 0, 48),
					position = UDim2.new(1, -6, 1, -8),
					anchor = Vector2.new(1, 1),
					textSize = 16,
					onClick = function()
						State.send("BuyFood", foodId, 5)
					end,
				}, card)
				entry.lock = Theme.label({ name = "Lock", text = "", font = Theme.Fonts.Display, textSize = 14, color = C.Orange, stroke = true, size = UDim2.new(1, -8, 0, 44), position = UDim2.new(0, 4, 1, -10), anchor = Vector2.new(0, 1), wrapped = true }, card)
			else
				local source = "Event reward"
				if table.find(def.events, "GOLDEN_FEAST") then
					source = "✨ Golden Feast event"
				elseif table.find(def.events, "GIANT_BEAST") then
					source = "👹 Giant Beast reward"
				end
				Theme.label({ text = source, font = Theme.Fonts.Display, textSize = 14, color = C.Gold, stroke = true, size = UDim2.new(1, -8, 0, 44), position = UDim2.new(0, 4, 1, -10), anchor = Vector2.new(0, 1), wrapped = true }, card)
			end
			table.insert(cards, entry)
		end

		local function update()
			local coins = State.get("coins") or 0
			local market = upgradeLevel("MARKET")
			for _, entry in ipairs(cards) do
				if entry.buy then
					local locked = market < entry.def.marketLevel
					entry.buy.instance.Visible = not locked
					entry.buyFive.instance.Visible = not locked
					entry.lock.Visible = locked
					entry.lock.Text = locked and string.format("🔒 Market License Lv %d", entry.def.marketLevel) or ""
					entry.buy.setEnabled(coins >= entry.def.price)
					entry.buyFive.setEnabled(coins >= entry.def.price * 5)
				end
			end
		end
		update()
		return { update = update }
	end

	---------------------------------------------------------------------------------------
	-- Huevos
	---------------------------------------------------------------------------------------
	local function renderEggs(content)
		local scroll = Theme.scroll({}, content)
		Theme.padding(scroll, 6, 6, 14, 6)
		Theme.grid(scroll, UDim2.fromOffset(236, 360), 12)
		local cards = {}

		for index, eggId in ipairs(EggConfig.Order) do
			local egg = EggConfig.Eggs[eggId]
			local card = Theme.panel({ name = eggId, color = C.PanelDark, order = index }, scroll)
			Theme.label({ text = egg.icon, size = UDim2.new(1, 0, 0, 70), position = UDim2.fromOffset(0, 6), textSize = 54 }, card)
			Theme.label({ text = egg.name, font = Theme.Fonts.Display, textSize = 22, stroke = true, size = UDim2.new(1, 0, 0, 28), position = UDim2.fromOffset(0, 78) }, card)

			-- Probabilidades visibles: se calculan de la misma tabla de pesos que usa el servidor.
			local total = 0
			for _, weight in pairs(egg.weights) do
				total += weight
			end
			local odds = Theme.box({ name = "Odds", size = UDim2.new(1, -24, 0, 130), position = UDim2.fromOffset(12, 112) }, card)
			Theme.list(odds, "V", 2)
			local row = 0
			for _, rarityId in ipairs(RarityConfig.Order) do
				local weight = egg.weights[rarityId]
				if weight then
					row += 1
					local line = Theme.box({ size = UDim2.new(1, 0, 0, 20), order = row }, odds)
					Theme.label({ text = rarityId, textSize = 15, color = Theme.rarityColor(rarityId), alignX = Enum.TextXAlignment.Left, font = Theme.Fonts.Display, stroke = true }, line)
					local percent = weight / total * 100
					Theme.label({ text = string.format(percent < 1 and "%.1f%%" or "%.0f%%", percent), textSize = 15, alignX = Enum.TextXAlignment.Right }, line)
				end
			end
			Theme.label({
				text = string.format("🧬 x%s mutation luck", tostring(egg.mutationLuck)),
				textSize = 13,
				color = C.TextDim,
				size = UDim2.new(1, 0, 0, 18),
				position = UDim2.fromOffset(0, 250),
			}, card)

			local entry = { egg = egg }
			entry.buy = Theme.button({
				name = "Buy",
				text = coinText(egg.price),
				color = C.Green,
				size = UDim2.new(1, -24, 0, 56),
				position = UDim2.new(0.5, 0, 1, -12),
				anchor = Vector2.new(0.5, 1),
				textSize = 20,
				onClick = function()
					State.send("BuyEgg", eggId)
				end,
			}, card)
			entry.lock = Theme.label({ name = "Lock", text = "", font = Theme.Fonts.Display, textSize = 16, color = C.Orange, stroke = true, size = UDim2.new(1, -16, 0, 56), position = UDim2.new(0.5, 0, 1, -12), anchor = Vector2.new(0.5, 1), wrapped = true }, card)
			table.insert(cards, entry)
		end

		local function update()
			local coins = State.get("coins") or 0
			local hatchery = upgradeLevel("HATCHERY")
			local owned = #(State.get("creatures") or {})
			for _, entry in ipairs(cards) do
				local locked = hatchery < entry.egg.hatcheryLevel
				local full = owned >= CreatureConfig.MaxOwned
				entry.buy.instance.Visible = not locked and not full
				entry.lock.Visible = locked or full
				entry.lock.Text = locked and string.format("🔒 Hatchery Lv %d", entry.egg.hatcheryLevel) or (full and "📦 Beast storage full" or "")
				entry.buy.setEnabled(coins >= entry.egg.price)
			end
		end
		update()
		return { update = update }
	end

	---------------------------------------------------------------------------------------
	-- Premium (Robux). Un producto sin ID configurado no se puede comprar: se muestra "SOON".
	---------------------------------------------------------------------------------------
	local function renderPremium(content)
		local scroll = Theme.scroll({}, content)
		Theme.padding(scroll, 6, 6, 14, 6)
		Theme.list(scroll, "V", 8)
		local rows = {}

		local function row(def, kind, order)
			local frame = Theme.panel({ name = def.key, size = UDim2.new(1, -4, 0, 78), color = C.PanelDark, order = order }, scroll)
			Theme.label({ text = def.icon, size = UDim2.fromOffset(70, 78), textSize = 38 }, frame)
			Theme.label({ text = def.name, font = Theme.Fonts.Display, textSize = 20, stroke = true, size = UDim2.new(1, -250, 0, 28), position = UDim2.fromOffset(72, 10), alignX = Enum.TextXAlignment.Left }, frame)
			Theme.label({ text = def.desc, textSize = 14, color = C.TextDim, size = UDim2.new(1, -250, 0, 32), position = UDim2.fromOffset(72, 38), alignX = Enum.TextXAlignment.Left, wrapped = true, alignY = Enum.TextYAlignment.Top }, frame)
			local configured = MonetizationConfig.isConfigured(def)
			local button = Theme.button({
				name = "Buy",
				text = configured and "GET" or "SOON",
				color = C.Purple,
				size = UDim2.fromOffset(150, 54),
				position = UDim2.new(1, -12, 0.5, 0),
				anchor = Vector2.new(1, 0.5),
				onClick = function()
					local player = Players.LocalPlayer
					if not configured or not player then
						return
					end
					-- La compra la gestiona Roblox; la recompensa solo la concede el servidor
					-- cuando Roblox la confirma.
					pcall(function()
						if kind == "pass" then
							MarketplaceService:PromptGamePassPurchase(player, def.id)
						else
							MarketplaceService:PromptProductPurchase(player, def.id)
						end
					end)
				end,
			}, frame)
			button.setEnabled(configured)
			table.insert(rows, { def = def, kind = kind, button = button, configured = configured })
		end

		local order = 0
		for _, key in ipairs({ "VIP", "AUTO_FEED", "EXTRA_SLOT" }) do
			if MonetizationConfig.GamePasses[key] then
				order += 1
				row(MonetizationConfig.GamePasses[key], "pass", order)
			end
		end
		for _, key in ipairs({ "GROWTH_BOOST", "PLOT_AURA" }) do
			if MonetizationConfig.Products[key] then
				order += 1
				row(MonetizationConfig.Products[key], "product", order)
			end
		end

		local function update()
			local passes = State.get("passes") or {}
			local cosmetics = State.get("cosmetics") or {}
			for _, entry in ipairs(rows) do
				local owned = (entry.kind == "pass" and passes[entry.def.key] == true)
					or (entry.def.grant and entry.def.grant.type == "Cosmetic" and cosmetics[entry.def.grant.cosmetic] == true)
				if owned then
					entry.button.setText("OWNED")
					entry.button.setEnabled(false)
				elseif entry.configured then
					entry.button.setText("GET")
					entry.button.setEnabled(true)
				end
			end
		end
		update()
		return { update = update }
	end

	manager.register("shop", {
		title = "SHOP",
		icon = "🛒",
		color = C.Orange,
		tabs = { { id = "food", label = "🍎 FOOD" }, { id = "eggs", label = "🥚 EGGS" }, { id = "premium", label = "👑 PREMIUM" } },
		watch = { "coins", "upgrades", "creatures", "passes", "cosmetics" },
		render = function(content, tab)
			if tab == "eggs" then
				return renderEggs(content)
			elseif tab == "premium" then
				return renderPremium(content)
			end
			return renderFood(content)
		end,
	})

	---------------------------------------------------------------------------------------
	-- Mejoras
	---------------------------------------------------------------------------------------
	manager.register("upgrades", {
		title = "UPGRADES",
		icon = "⬆️",
		color = C.Green,
		watch = { "coins", "upgrades" },
		render = function(content)
			local scroll = Theme.scroll({}, content)
			Theme.padding(scroll, 6, 6, 14, 6)
			Theme.list(scroll, "V", 8)
			local rows = {}
			for index, upgradeId in ipairs(UpgradeConfig.Order) do
				local def = UpgradeConfig.Upgrades[upgradeId]
				local frame = Theme.panel({ name = upgradeId, size = UDim2.new(1, -4, 0, 78), color = C.PanelDark, order = index }, scroll)
				Theme.label({ text = def.icon, size = UDim2.fromOffset(70, 78), textSize = 38 }, frame)
				Theme.label({ text = def.name, font = Theme.Fonts.Display, textSize = 20, stroke = true, size = UDim2.new(1, -260, 0, 26), position = UDim2.fromOffset(72, 8), alignX = Enum.TextXAlignment.Left }, frame)
				Theme.label({ text = def.desc, textSize = 14, color = C.TextDim, size = UDim2.new(1, -260, 0, 18), position = UDim2.fromOffset(72, 34), alignX = Enum.TextXAlignment.Left, truncate = true }, frame)
				local bar = Theme.progress({ size = UDim2.new(1, -330, 0, 12), position = UDim2.fromOffset(72, 58), color = C.Green }, frame)
				local level = Theme.label({ name = "Level", text = "", textSize = 13, color = C.TextDim, size = UDim2.fromOffset(66, 16), position = UDim2.new(1, -252, 0, 56), alignX = Enum.TextXAlignment.Left }, frame)
				local button = Theme.button({
					name = "Buy",
					text = "",
					color = C.Green,
					size = UDim2.fromOffset(170, 54),
					position = UDim2.new(1, -12, 0.5, 0),
					anchor = Vector2.new(1, 0.5),
					textSize = 18,
					scaled = true,
					onClick = function()
						State.send("BuyUpgrade", upgradeId)
					end,
				}, frame)
				table.insert(rows, { id = upgradeId, def = def, bar = bar, level = level, button = button })
			end

			local function update()
				local coins = State.get("coins") or 0
				local upgrades = State.get("upgrades") or { levels = {}, costs = {} }
				for _, entry in ipairs(rows) do
					local current = upgrades.levels[entry.id] or 0
					local cost = upgrades.costs[entry.id] or -1
					entry.bar.set(current / entry.def.maxLevel)
					entry.level.Text = string.format("Lv %d/%d", current, entry.def.maxLevel)
					if cost < 0 then
						entry.button.setText("MAX")
						entry.button.setEnabled(false)
					else
						entry.button.setText(coinText(cost))
						entry.button.setEnabled(coins >= cost)
					end
				end
			end
			update()
			return { update = update }
		end,
	})
end

return ShopWindow
