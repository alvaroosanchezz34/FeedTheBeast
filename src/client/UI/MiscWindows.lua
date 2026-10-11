-- Ventanas de renacimiento y de ajustes (con panel de desarrollo para administradores).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FoodConfig = require(Shared.Config.FoodConfig)
local EventConfig = require(Shared.Config.EventConfig)
local MutationConfig = require(Shared.Config.MutationConfig)
local CreatureConfig = require(Shared.Config.CreatureConfig)
local TheftConfig = require(Shared.Config.TheftConfig)
local Utilities = require(Shared.Utilities)

local Theme = require(script.Parent.Theme)

local MiscWindows = {}

local C = Theme.Colors
local CONFIRM_DELAY = 1.5 -- segundos antes de que el botón definitivo se active

function MiscWindows.register(manager, ctx)
	local State = ctx.State

	---------------------------------------------------------------------------------------
	-- Renacimiento: dos pantallas. La primera explica requisitos y consecuencias; la segunda
	-- pide confirmación y su botón tarda en activarse. El servidor exige además un código de un
	-- solo uso que solo se obtiene al abrir esta ventana.
	---------------------------------------------------------------------------------------
	local function bulletList(parent, title, items, color, position, size)
		local box = Theme.panel({ name = title, size = size, position = position, color = C.PanelDark, strokeColor = color }, parent)
		Theme.label({ text = title, font = Theme.Fonts.Display, textSize = 18, color = color, stroke = true, size = UDim2.new(1, 0, 0, 28), position = UDim2.fromOffset(0, 6) }, box)
		local list = Theme.box({ size = UDim2.new(1, -20, 1, -44), position = UDim2.fromOffset(10, 38) }, box)
		Theme.list(list, "V", 4)
		for index, item in ipairs(items) do
			Theme.label({ text = "•  " .. tostring(item), textSize = 14, size = UDim2.new(1, 0, 0, 34), alignX = Enum.TextXAlignment.Left, alignY = Enum.TextYAlignment.Top, wrapped = true, order = index }, list)
		end
		return box
	end

	manager.register("rebirth", {
		title = "REBIRTH",
		icon = "🔥",
		color = C.Pink,
		render = function(content)
			local alive = true
			local status = Theme.label({ name = "Status", text = "Loading…", textSize = 18, color = C.TextDim }, content)
			local confirmButton = nil
			local confirmAt = nil

			local function showConfirm(info)
				for _, child in ipairs(content:GetChildren()) do
					child:Destroy()
				end
				Theme.label({ text = "Are you sure?", font = Theme.Fonts.Display, textSize = 30, stroke = true, size = UDim2.new(1, 0, 0, 44) }, content)
				Theme.label({
					text = string.format("You will spend %s coins and reset everything listed below. This cannot be undone.", Utilities.formatNumber(info.cost)),
					textSize = 16,
					color = C.TextDim,
					size = UDim2.new(1, -40, 0, 40),
					position = UDim2.fromOffset(20, 46),
					wrapped = true,
				}, content)
				bulletList(content, "YOU LOSE", info.resets, C.Red, UDim2.fromOffset(0, 96), UDim2.new(1, 0, 1, -180))
				Theme.button({
					name = "Cancel",
					text = "CANCEL",
					color = C.Grey,
					size = UDim2.new(0.5, -8, 0, 64),
					position = UDim2.new(0, 0, 1, 0),
					anchor = Vector2.new(0, 1),
					onClick = function()
						manager.open("rebirth")
					end,
				}, content)
				confirmButton = Theme.button({
					name = "Confirm",
					text = "WAIT…",
					color = C.Pink,
					size = UDim2.new(0.5, -8, 0, 64),
					position = UDim2.new(1, 0, 1, 0),
					anchor = Vector2.new(1, 1),
					onClick = function()
						State.send("ConfirmRebirth", info.nonce)
						manager.close()
					end,
				}, content)
				confirmButton.setEnabled(false)
				confirmAt = ctx.clock() + CONFIRM_DELAY
			end

			local function showInfo(info)
				status:Destroy()
				local headline
				if info.maxed then
					headline = "You reached the maximum rebirth. Legend."
				else
					headline = string.format("Rebirth %d → %d", info.rebirths, info.rebirths + 1)
				end
				Theme.label({ text = headline, font = Theme.Fonts.Display, textSize = 28, stroke = true, size = UDim2.new(1, 0, 0, 38) }, content)
				Theme.label({
					text = string.format("Coins x%s → x%s forever   ·   Max level %d → %d", tostring(info.currentMult), tostring(info.nextMult), info.currentMaxLevel, info.nextMaxLevel),
					textSize = 17,
					color = C.Gold,
					size = UDim2.new(1, 0, 0, 24),
					position = UDim2.fromOffset(0, 40),
				}, content)

				local requirements = Theme.box({ name = "Requirements", size = UDim2.new(1, 0, 0, 56), position = UDim2.fromOffset(0, 72) }, content)
				Theme.list(requirements, "H", 10, Enum.HorizontalAlignment.Center)
				local function requirement(text, met, order)
					local frame = Theme.panel({ size = UDim2.new(0.5, -6, 1, 0), color = Theme.darken(met and C.Green or C.Red, 0.45), strokeColor = met and C.Green or C.Red, order = order }, requirements)
					local label = Theme.label({ text = (met and "✅  " or "❌  ") .. text, textSize = 16, scaled = true, maxTextSize = 16 }, frame)
					Theme.padding(label, 8, 4)
				end
				requirement(string.format("%s / %s coins", Utilities.formatNumber(info.coins), Utilities.formatNumber(info.cost)), info.coins >= info.cost, 1)
				requirement(string.format("A beast at level %d (best: %d)", info.requiredLevel, info.highestLevel), info.highestLevel >= info.requiredLevel, 2)

				bulletList(content, "RESETS", info.resets, C.Red, UDim2.fromOffset(0, 138), UDim2.new(0.5, -6, 1, -218))
				bulletList(content, "YOU KEEP", info.keeps, C.Green, UDim2.new(0.5, 6, 0, 138), UDim2.new(0.5, -6, 1, -218))

				local button = Theme.button({
					name = "Rebirth",
					text = info.canRebirth and "REBIRTH…" or "NOT READY YET",
					icon = "🔥",
					color = C.Pink,
					size = UDim2.new(1, 0, 0, 64),
					position = UDim2.new(0, 0, 1, 0),
					anchor = Vector2.new(0, 1),
					onClick = function()
						showConfirm(info)
					end,
				}, content)
				button.setEnabled(info.canRebirth == true and type(info.nonce) == "string")
			end

			task.spawn(function()
				local ok, info = pcall(function()
					return State.remote("GetRebirthInfo"):InvokeServer()
				end)
				if not alive then
					return
				end
				if ok and type(info) == "table" then
					showInfo(info)
				else
					status.Text = "Could not load rebirth info. Close and try again."
				end
			end)

			return {
				destroy = function()
					alive = false
				end,
				tick = function()
					if confirmButton and confirmAt and ctx.clock() >= confirmAt then
						confirmAt = nil
						confirmButton.setText("YES, REBIRTH")
						confirmButton.setEnabled(true)
					end
				end,
				-- Sin `update`: esta ventana no vigila el estado (el código de confirmación caduca).
			}
		end,
	})

	---------------------------------------------------------------------------------------
	-- Ajustes
	---------------------------------------------------------------------------------------
	local function renderSettings(content)
		local Settings = ctx.Settings
		local scroll = Theme.scroll({}, content)
		Theme.padding(scroll, 6, 6, 14, 6)
		Theme.list(scroll, "V", 10)

		local function section(titleText, height, order)
			local frame = Theme.panel({ name = titleText, size = UDim2.new(1, -4, 0, height), color = C.PanelDark, order = order }, scroll)
			Theme.label({ text = titleText, font = Theme.Fonts.Display, textSize = 19, stroke = true, size = UDim2.new(1, -24, 0, 30), position = UDim2.fromOffset(14, 8), alignX = Enum.TextXAlignment.Left }, frame)
			return frame
		end

		-- Calidad de efectos
		local quality = section("✨ Effects quality", 132, 1)
		Theme.label({
			text = "Lower it if the game stutters: fewer particles, lights and orbiting bits.",
			textSize = 13,
			color = C.TextDim,
			size = UDim2.new(1, -28, 0, 18),
			position = UDim2.fromOffset(14, 36),
			alignX = Enum.TextXAlignment.Left,
		}, quality)
		local qualityRow = Theme.box({ size = UDim2.new(1, -28, 0, 58), position = UDim2.fromOffset(14, 62) }, quality)
		Theme.list(qualityRow, "H", 8)
		local qualityButtons = {}
		for index, option in ipairs({ "Auto", "Low", "Medium", "High" }) do
			qualityButtons[option] = Theme.button({
				name = option,
				text = string.upper(option),
				color = C.PanelLight,
				size = UDim2.new(0.25, -6, 1, 0),
				textSize = 17,
				order = index,
				onClick = function()
					Settings.set("vfxQuality", option)
					manager.invalidate()
				end,
			}, qualityRow)
		end
		local qualityNote = Theme.label({ name = "Now", text = "", textSize = 12, color = C.TextDim, size = UDim2.fromOffset(240, 18), position = UDim2.new(1, -14, 0, 14), anchor = Vector2.new(1, 0), alignX = Enum.TextXAlignment.Right }, quality)

		-- Volumen
		local sliders = {}
		local function volume(titleText, key, order)
			local frame = section(titleText, 96, order)
			local bar = Theme.progress({ size = UDim2.new(1, -188, 0, 22), position = UDim2.new(0, 84, 0, 56), color = C.Blue, radius = 10 }, frame)
			local function step(delta)
				local value = math.clamp(math.floor(((Settings.get(key) or 1) + delta) * 10 + 0.5) / 10, 0, 1)
				Settings.set(key, value)
				manager.invalidate()
			end
			Theme.button({ name = "Less", text = "–", color = C.PanelLight, size = UDim2.fromOffset(60, 50), position = UDim2.fromOffset(14, 40), onClick = function()
				step(-0.1)
			end }, frame)
			Theme.button({ name = "More", text = "+", color = C.PanelLight, size = UDim2.fromOffset(60, 50), position = UDim2.new(1, -14, 0, 40), anchor = Vector2.new(1, 0), onClick = function()
				step(0.1)
			end }, frame)
			sliders[key] = bar
		end
		volume("🔊 Sound effects", "sfxVolume", 2)
		volume("🎵 Music", "musicVolume", 3)

		local help = section("🎮 Controls", 118, 4)
		Theme.label({
			text = "E / tap the prompt: feed (hold to keep feeding)\nG or the DROP button: drop the crate you carry\nWalk over food, crates and your pads to use them",
			textSize = 14,
			color = C.TextDim,
			size = UDim2.new(1, -28, 0, 70),
			position = UDim2.fromOffset(14, 40),
			alignX = Enum.TextXAlignment.Left,
			alignY = Enum.TextYAlignment.Top,
			wrapped = true,
		}, help)

		local function update()
			local selected = Settings.get("vfxQuality") or "Auto"
			for option, button in pairs(qualityButtons) do
				button.setColor(option == selected and C.Green or C.PanelLight)
			end
			qualityNote.Text = "Currently: " .. Settings.quality()
			for key, bar in pairs(sliders) do
				bar.set(Settings.get(key) or 1)
			end
		end
		update()
		return { update = update }
	end

	---------------------------------------------------------------------------------------
	-- Panel de desarrollo. Solo se MUESTRA a administradores, pero eso no es la protección:
	-- el servidor comprueba los permisos en cada comando.
	---------------------------------------------------------------------------------------
	local function renderDev(content)
		local scroll = Theme.scroll({}, content)
		Theme.padding(scroll, 6, 6, 14, 6)
		Theme.list(scroll, "V", 10)
		local order = 0

		local function group(titleText, commands)
			order += 1
			local rowsNeeded = math.ceil(#commands / 4)
			local frame = Theme.panel({ name = titleText, size = UDim2.new(1, -4, 0, 44 + rowsNeeded * 56), color = C.PanelDark, order = order }, scroll)
			Theme.label({ text = titleText, font = Theme.Fonts.Display, textSize = 17, stroke = true, size = UDim2.new(1, -24, 0, 28), position = UDim2.fromOffset(14, 6), alignX = Enum.TextXAlignment.Left }, frame)
			local grid = Theme.box({ size = UDim2.new(1, -20, 1, -44), position = UDim2.fromOffset(10, 38) }, frame)
			local layout = Theme.grid(grid, UDim2.new(0.25, -8, 0, 48), 8)
			layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
			for index, command in ipairs(commands) do
				Theme.button({
					name = command[1],
					text = command[1],
					color = C.PanelLight,
					textSize = 14,
					scaled = true,
					order = index,
					onClick = function()
						State.send("Admin", command[2], command[3], command[4])
					end,
				}, grid)
			end
		end

		group("Economy", {
			{ "+1K coins", "coins", "1000" },
			{ "+100K coins", "coins", "100000" },
			{ "+10M coins", "coins", "10000000" },
			{ "Grow all +200", "grow", "all", "200" },
			{ "Inspect", "inspect" },
			{ "Save now", "save" },
		})
		local foods = {}
		for _, foodId in ipairs({ "APPLE", "PIZZA", "DINO_STEAK", "ROYAL_LOBSTER", "GOLDEN_APPLE", "STARFRUIT", "VOID_TRUFFLE" }) do
			if FoodConfig.Foods[foodId] then
				table.insert(foods, { FoodConfig.Foods[foodId].icon .. " x5", "food", foodId, "5" })
			end
		end
		group("Food", foods)
		local eggs = {}
		for _, speciesId in ipairs(CreatureConfig.Order) do
			table.insert(eggs, { CreatureConfig.Species[speciesId].name, "egg", speciesId, "NORMAL" })
		end
		group("Spawn beast", eggs)
		local mutations = {}
		for _, mutationId in ipairs(MutationConfig.Order) do
			table.insert(mutations, { "All → " .. MutationConfig.Mutations[mutationId].name, "mutate", "all", mutationId })
		end
		table.insert(mutations, { "Clear effects", "clearfx" })
		group("Mutations and auras", mutations)
		local events = {}
		for _, eventId in ipairs(EventConfig.Order) do
			table.insert(events, { EventConfig.Events[eventId].name, "event", eventId })
		end
		table.insert(events, { "Stop event", "stopevent" })
		group("Events", events)
		local crates = {}
		for _, tierId in ipairs(TheftConfig.TierOrder) do
			table.insert(crates, { TheftConfig.Tiers[tierId].name, "crate", tierId })
		end
		group("Crates", crates)
		group("Passes (this session only)", {
			{ "Toggle VIP", "pass", "VIP" },
			{ "Toggle Auto-Feed", "pass", "AUTO_FEED" },
			{ "Toggle Bonus Pen", "pass", "EXTRA_SLOT" },
		})
		return nil
	end

	local function settingsTabs()
		local tabs = { { id = "settings", label = "⚙️ SETTINGS" } }
		if State.get("isAdmin") then
			table.insert(tabs, { id = "dev", label = "🛠️ DEV" })
		end
		return tabs
	end

	local definition = {
		title = "SETTINGS",
		icon = "⚙️",
		color = C.Grey,
		tabs = settingsTabs(),
		watch = { "settings" },
		render = function(content, tab)
			if tab == "dev" and State.get("isAdmin") then
				return renderDev(content)
			end
			return renderSettings(content)
		end,
	}
	manager.register("settings", definition)
	State.observe("isAdmin", function()
		definition.tabs = settingsTabs()
	end)
	-- La calidad "Auto" puede resolverse a otro nivel sin que cambie el ajuste guardado.
	ctx.Settings.QualityChanged:Connect(function()
		if manager.current() == "settings" then
			manager.invalidate()
		end
	end)
end

return MiscWindows
