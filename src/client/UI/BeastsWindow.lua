-- Ventana de criaturas: "MY BEASTS" (colocar, guardar, vender) y "COLLECTION" (especies x
-- mutaciones descubiertas). Los retratos son las criaturas reales en un ViewportFrame.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CreatureConfig = require(Shared.Config.CreatureConfig)
local MutationConfig = require(Shared.Config.MutationConfig)
local Utilities = require(Shared.Utilities)

local Theme = require(script.Parent.Theme)
local CreatureIcon = require(script.Parent.CreatureIcon)

local BeastsWindow = {}

local C = Theme.Colors
local SELL_CONFIRM_SECONDS = 3

function BeastsWindow.register(manager, ctx)
	local State = ctx.State

	---------------------------------------------------------------------------------------
	-- Mis criaturas
	---------------------------------------------------------------------------------------
	local function renderMine(content)
		local summary = Theme.label({
			name = "Summary",
			text = "",
			textSize = 15,
			color = C.TextDim,
			size = UDim2.new(1, 0, 0, 22),
			alignX = Enum.TextXAlignment.Left,
		}, content)
		local scroll = Theme.scroll({ size = UDim2.new(1, 0, 1, -28), position = UDim2.fromOffset(0, 28) }, content)
		Theme.padding(scroll, 6, 6, 14, 6)
		Theme.list(scroll, "V", 8)

		local rows = {} -- id -> fila
		local signature = ""

		local function firstFreeSlot(creatures, slots)
			local used = {}
			for _, creature in ipairs(creatures) do
				if creature.slot > 0 then
					used[creature.slot] = true
				end
			end
			for slot = 1, slots do
				if not used[slot] then
					return slot
				end
			end
			return nil
		end

		local function buildRow(creature, order)
			local species = CreatureConfig.Species[creature.species]
			local mutation = MutationConfig.Mutations[creature.mutation] or MutationConfig.Mutations.NORMAL
			local rarityColor = Theme.rarityColor(species.rarity)
			local frame = Theme.panel({ name = creature.id, size = UDim2.new(1, -4, 0, 100), color = C.PanelDark, strokeColor = creature.slot > 0 and rarityColor or C.Ink, order = order }, scroll)

			local portrait = Theme.panel({ name = "Portrait", size = UDim2.fromOffset(84, 84), position = UDim2.fromOffset(8, 8), color = Theme.darken(rarityColor, 0.6), strokeThickness = 2 }, frame)
			CreatureIcon.new({ species = creature.species, mutation = creature.mutation }, portrait)

			Theme.label({ text = species.name, font = Theme.Fonts.Display, textSize = 22, color = rarityColor, stroke = true, size = UDim2.fromOffset(200, 26), position = UDim2.fromOffset(104, 8), alignX = Enum.TextXAlignment.Left }, frame)
			if mutation.id ~= "NORMAL" then
				Theme.chip({ text = string.upper(mutation.name), color = Theme.darken(mutation.color, 0.3), size = UDim2.fromOffset(92, 22), position = UDim2.fromOffset(104, 36) }, frame)
			end
			Theme.chip({
				text = creature.slot > 0 and ("PEN " .. creature.slot) or "STORED",
				color = creature.slot > 0 and Theme.darken(C.Green, 0.3) or C.PanelLight,
				size = UDim2.fromOffset(82, 22),
				position = UDim2.fromOffset(mutation.id ~= "NORMAL" and 202 or 104, 36),
			}, frame)

			local row = { frame = frame, creature = creature, sellArmedUntil = 0 }
			row.info = Theme.label({ name = "Info", text = "", textSize = 14, color = C.Text, size = UDim2.new(1, -420, 0, 18), position = UDim2.fromOffset(104, 62), alignX = Enum.TextXAlignment.Left }, frame)
			row.bar = Theme.progress({ size = UDim2.new(1, -420, 0, 10), position = UDim2.fromOffset(104, 84), color = C.Green }, frame)

			row.move = Theme.button({
				name = "Move",
				text = creature.slot > 0 and "STORE" or "PLACE",
				color = creature.slot > 0 and C.Grey or C.Blue,
				size = UDim2.fromOffset(130, 50),
				position = UDim2.new(1, -160, 0.5, 0),
				anchor = Vector2.new(1, 0.5),
				textSize = 18,
				onClick = function()
					local current = row.creature
					if current.slot > 0 then
						State.send("StoreCreature", current.id)
						return
					end
					local slot = firstFreeSlot(State.get("creatures") or {}, State.get("slots") or 0)
					if slot then
						State.send("PlaceCreature", current.id, slot)
					else
						ctx.toast("All pens are busy. Store a beast or buy an Extra Pen.", "error", "🏠")
					end
				end,
			}, frame)

			row.sell = Theme.button({
				name = "Sell",
				text = "",
				color = C.Red,
				size = UDim2.fromOffset(140, 50),
				position = UDim2.new(1, -10, 0.5, 0),
				anchor = Vector2.new(1, 0.5),
				textSize = 16,
				scaled = true,
				onClick = function()
					-- Vender es irreversible: hace falta pulsar dos veces.
					if ctx.clock() < row.sellArmedUntil then
						row.sellArmedUntil = 0
						State.send("SellCreature", row.creature.id)
					else
						row.sellArmedUntil = ctx.clock() + SELL_CONFIRM_SECONDS
						row.sell.setText("SURE? TAP AGAIN")
					end
				end,
			}, frame)
			return row
		end

		local function refreshRow(row, creature, total)
			row.creature = creature
			row.info.Text = string.format("Lv %d%s  ·  +%s/s", creature.level, creature.maxed and " (MAX)" or "", Utilities.formatNumber(creature.income))
			row.bar.set(creature.maxed and 1 or creature.progress, creature.maxed and C.Gold or C.Green)
			if ctx.clock() >= row.sellArmedUntil then
				row.sell.setText("SELL  💰 " .. Utilities.formatNumber(creature.sellValue))
			end
			row.sell.setEnabled(total > 1)
		end

		local function update()
			local creatures = State.get("creatures") or {}
			local slots = State.get("slots") or 0
			local placed = 0
			local parts = {}
			for _, creature in ipairs(creatures) do
				if creature.slot > 0 then
					placed += 1
				end
				table.insert(parts, creature.id .. ":" .. creature.mutation .. ":" .. creature.slot)
			end
			summary.Text = string.format("Pens %d/%d  ·  Beasts %d/%d  ·  only beasts in a pen make coins", placed, slots, #creatures, CreatureConfig.MaxOwned)

			-- Los retratos solo se reconstruyen cuando cambia QUÉ criaturas hay o dónde están;
			-- los cambios de nivel se refrescan en el sitio.
			local newSignature = table.concat(parts, "|")
			if newSignature ~= signature then
				signature = newSignature
				for _, row in pairs(rows) do
					row.frame:Destroy()
				end
				rows = {}
				for index, creature in ipairs(creatures) do
					rows[creature.id] = buildRow(creature, index)
				end
			end
			for _, creature in ipairs(creatures) do
				local row = rows[creature.id]
				if row then
					refreshRow(row, creature, #creatures)
				end
			end
		end
		update()
		return { update = update }
	end

	---------------------------------------------------------------------------------------
	-- Colección
	---------------------------------------------------------------------------------------
	local function renderCollection(content)
		local collection = State.get("collection") or {}
		local total, found = 0, 0
		for _, speciesId in ipairs(CreatureConfig.Order) do
			for _, mutationId in ipairs(MutationConfig.Order) do
				total += 1
				if collection[speciesId .. ":" .. mutationId] then
					found += 1
				end
			end
		end
		Theme.label({
			name = "Summary",
			text = string.format("Discovered %d/%d  ·  mutations appear when hatching or feeding", found, total),
			textSize = 15,
			color = C.TextDim,
			size = UDim2.new(1, 0, 0, 22),
			alignX = Enum.TextXAlignment.Left,
		}, content)
		local scroll = Theme.scroll({ size = UDim2.new(1, 0, 1, -28), position = UDim2.fromOffset(0, 28) }, content)
		Theme.padding(scroll, 6, 6, 14, 6)
		Theme.grid(scroll, UDim2.fromOffset(134, 158), 10)

		local order = 0
		for _, speciesId in ipairs(CreatureConfig.Order) do
			local species = CreatureConfig.Species[speciesId]
			for _, mutationId in ipairs(MutationConfig.Order) do
				order += 1
				local mutation = MutationConfig.Mutations[mutationId]
				local discovered = collection[speciesId .. ":" .. mutationId] == true
				local rarityColor = Theme.rarityColor(species.rarity)
				local borderColor = discovered and (mutationId ~= "NORMAL" and mutation.color or rarityColor) or C.Line
				local cell = Theme.panel({ name = speciesId .. "_" .. mutationId, color = C.PanelDark, strokeColor = borderColor, order = order }, scroll)
				local portrait = Theme.box({ name = "Portrait", size = UDim2.new(1, -12, 0, 104), position = UDim2.fromOffset(6, 6) }, cell)
				CreatureIcon.new({ species = speciesId, mutation = mutationId, silhouette = not discovered }, portrait)
				Theme.label({
					text = discovered and species.name or "???",
					font = Theme.Fonts.Display,
					textSize = 16,
					color = discovered and rarityColor or C.TextDim,
					stroke = true,
					size = UDim2.new(1, -6, 0, 20),
					position = UDim2.fromOffset(3, 112),
					scaled = true,
					maxTextSize = 16,
				}, cell)
				Theme.label({
					text = mutationId == "NORMAL" and species.rarity or mutation.name,
					textSize = 12,
					color = (discovered and mutationId ~= "NORMAL") and mutation.color or C.TextDim,
					size = UDim2.new(1, -6, 0, 16),
					position = UDim2.fromOffset(3, 134),
				}, cell)
			end
		end
		return nil -- sin update: al cambiar la colección se reconstruye
	end

	manager.register("beasts", {
		title = "BEASTS",
		icon = "🐾",
		color = C.Blue,
		tabs = { { id = "mine", label = "🐾 MY BEASTS" }, { id = "collection", label = "📖 COLLECTION" } },
		watch = { "creatures", "slots", "collection" },
		render = function(content, tab)
			if tab == "collection" then
				return renderCollection(content)
			end
			return renderMine(content)
		end,
	})
end

return BeastsWindow
