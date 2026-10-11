-- Avisos temporales: notificaciones breves, anuncios globales, tarjeta de eclosión y ganancias
-- offline. Se limita cuántos hay a la vez y todos se retiran solos.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CreatureConfig = require(Shared.Config.CreatureConfig)
local MutationConfig = require(Shared.Config.MutationConfig)
local Utilities = require(Shared.Utilities)

local Theme = require(script.Parent.Theme)
local CreatureIcon = require(script.Parent.CreatureIcon)

local Toasts = {}

local C = Theme.Colors
local MAX_TOASTS = 4
local TOAST_TIME = 3.4

local KIND_COLOR = {
	info = C.PanelLight,
	success = C.Green,
	error = C.Red,
	reward = C.Gold,
	alert = C.Pink,
}

local KIND_SOUND = {
	error = "Error",
	reward = "Coins",
	alert = "StolenAlert",
}

function Toasts.create(ctx)
	local State = ctx.State
	local toasts = {}
	local active = {} -- { frame, expires }
	local clock = 0

	local stack = Theme.box({
		name = "Toasts",
		size = UDim2.fromOffset(440, 0),
		position = UDim2.new(0.5, 0, 0, 132),
		anchor = Vector2.new(0.5, 0),
		automatic = Enum.AutomaticSize.Y,
	}, ctx.layers.overlay)
	Theme.list(stack, "V", 6, Enum.HorizontalAlignment.Center)

	local order = 0

	local function remove(index)
		local entry = table.remove(active, index)
		if entry then
			entry.frame:Destroy()
		end
	end

	function toasts.toast(text, kind, icon)
		if type(text) ~= "string" or text == "" then
			return
		end
		-- El mismo aviso repetido solo renueva su tiempo.
		for _, entry in ipairs(active) do
			if entry.text == text then
				entry.expires = clock + TOAST_TIME
				return
			end
		end
		while #active >= MAX_TOASTS do
			remove(1)
		end
		order += 1
		local color = KIND_COLOR[kind] or KIND_COLOR.info
		local frame = Theme.panel({ name = "Toast", size = UDim2.fromOffset(440, 44), color = Theme.darken(color, 0.35), strokeColor = color, order = order }, stack)
		local label = Theme.label({
			text = (icon and (icon .. "  ") or "") .. text,
			textSize = 17,
			scaled = true,
			maxTextSize = 17,
			stroke = true,
		}, frame)
		Theme.padding(label, 12, 6)
		table.insert(active, { frame = frame, text = text, expires = clock + TOAST_TIME })
		if KIND_SOUND[kind] then
			ctx.Audio.play(KIND_SOUND[kind])
		end
	end

	---------------------------------------------------------------------------------------
	-- Anuncio global (una línea grande; el siguiente sustituye al anterior)
	---------------------------------------------------------------------------------------
	local announce = Theme.label({
		name = "Announce",
		text = "",
		font = Theme.Fonts.Display,
		textSize = 30,
		stroke = true,
		scaled = true,
		maxTextSize = 30,
		size = UDim2.new(0.7, 0, 0, 44),
		position = UDim2.new(0.5, 0, 0.24, 0),
		anchor = Vector2.new(0.5, 0.5),
	}, ctx.layers.overlay)
	announce.Visible = false
	local announceUntil = 0

	function toasts.announce(text, color, duration)
		announce.Text = text
		announce.TextColor3 = color or C.Text
		announce.TextTransparency = 0
		announce.Visible = true
		announceUntil = clock + (duration or 4)
	end

	---------------------------------------------------------------------------------------
	-- Tarjeta de eclosión
	---------------------------------------------------------------------------------------
	local card = nil
	local cardUntil = 0

	local function closeCard()
		if card then
			card:Destroy()
			card = nil
		end
	end

	function toasts.hatch(data)
		local species = CreatureConfig.Species[data.species]
		local mutation = MutationConfig.Mutations[data.mutation] or MutationConfig.Mutations.NORMAL
		if not species then
			return
		end
		closeCard()
		local rarityColor = Theme.rarityColor(species.rarity)
		local button = Instance.new("TextButton")
		button.Name = "HatchCard"
		button.Size = UDim2.fromOffset(330, 400)
		button.Position = UDim2.fromScale(0.5, 0.5)
		button.AnchorPoint = Vector2.new(0.5, 0.5)
		button.BackgroundColor3 = C.Panel
		button.AutoButtonColor = false
		button.BorderSizePixel = 0
		button.Text = ""
		button.ZIndex = 20
		Theme.corner(button, 18)
		Theme.stroke(button, rarityColor, 5)
		button.Parent = ctx.layers.overlay
		card = button

		Theme.label({ text = data.isNew and "NEW BEAST!" or "HATCHED!", font = Theme.Fonts.Display, textSize = 26, color = data.isNew and C.Gold or C.Text, stroke = true, size = UDim2.new(1, 0, 0, 40), position = UDim2.fromOffset(0, 10), zindex = 21 }, button)
		local portrait = Theme.panel({ name = "Portrait", size = UDim2.fromOffset(230, 200), position = UDim2.new(0.5, 0, 0, 56), anchor = Vector2.new(0.5, 0), color = Theme.darken(rarityColor, 0.6), strokeThickness = 2, zindex = 21 }, button)
		local icon = CreatureIcon.new({ species = data.species, mutation = mutation.id }, portrait)
		if icon then
			icon.ZIndex = 22
		end
		Theme.label({ text = species.name, font = Theme.Fonts.Display, textSize = 32, color = rarityColor, stroke = true, size = UDim2.new(1, 0, 0, 40), position = UDim2.fromOffset(0, 262), zindex = 21 }, button)
		local subtitle = string.upper(species.rarity)
		if mutation.id ~= "NORMAL" then
			subtitle = string.upper(mutation.name) .. " · " .. subtitle
		end
		Theme.label({ text = subtitle, font = Theme.Fonts.Display, textSize = 18, color = mutation.id ~= "NORMAL" and mutation.color or C.TextDim, stroke = true, size = UDim2.new(1, 0, 0, 24), position = UDim2.fromOffset(0, 302), zindex = 21 }, button)
		Theme.label({ text = "“" .. species.tagline .. "”", textSize = 15, color = C.TextDim, size = UDim2.new(1, -24, 0, 22), position = UDim2.fromOffset(12, 330), zindex = 21, scaled = true, maxTextSize = 15 }, button)
		Theme.label({
			text = data.stored and "Your pens are full: it is waiting in BEASTS." or "Tap to continue",
			textSize = 14,
			color = data.stored and C.Orange or C.TextDim,
			size = UDim2.new(1, -24, 0, 22),
			position = UDim2.fromOffset(12, 364),
			zindex = 21,
		}, button)

		button.Activated:Connect(closeCard)
		-- Aparece con un pequeño rebote.
		local scale = Instance.new("UIScale")
		scale.Scale = 0.6
		scale.Parent = button
		Theme.tween(scale, 0.28, { Scale = 1 }, Enum.EasingStyle.Back)
		cardUntil = clock + 4.5
	end

	---------------------------------------------------------------------------------------
	-- Ganancias offline
	---------------------------------------------------------------------------------------
	local offline = nil
	local offlineAmount = nil

	local function refreshOffline(amount)
		amount = amount or 0
		if amount <= 0 then
			if offline then
				offline:Destroy()
				offline = nil
				offlineAmount = nil
			end
			return
		end
		if offline and offlineAmount then
			offlineAmount.Text = "+" .. Utilities.formatNumber(amount) .. " coins"
			return
		end
		offline = Theme.panel({ name = "Offline", size = UDim2.fromOffset(360, 190), position = UDim2.fromScale(0.5, 0.42), anchor = Vector2.new(0.5, 0.5), strokeColor = C.Gold, zindex = 15 }, ctx.layers.overlay)
		Theme.label({ text = "💤 While you were away…", font = Theme.Fonts.Display, textSize = 22, stroke = true, size = UDim2.new(1, 0, 0, 36), position = UDim2.fromOffset(0, 12), zindex = 16 }, offline)
		offlineAmount = Theme.label({ name = "Amount", text = "+" .. Utilities.formatNumber(amount) .. " coins", font = Theme.Fonts.Display, textSize = 34, color = C.Gold, stroke = true, size = UDim2.new(1, 0, 0, 44), position = UDim2.fromOffset(0, 52), zindex = 16 }, offline)
		Theme.label({ text = "Your beasts kept working at half speed.", textSize = 14, color = C.TextDim, size = UDim2.new(1, 0, 0, 20), position = UDim2.fromOffset(0, 98), zindex = 16 }, offline)
		Theme.button({
			name = "Claim",
			text = "CLAIM",
			color = C.Green,
			size = UDim2.fromOffset(200, 54),
			position = UDim2.new(0.5, 0, 1, -12),
			anchor = Vector2.new(0.5, 1),
			zindex = 16,
			onClick = function()
				State.send("ClaimOffline")
			end,
		}, offline)
	end

	State.observe("pendingOffline", refreshOffline)

	---------------------------------------------------------------------------------------
	-- Entrada desde el servidor
	---------------------------------------------------------------------------------------
	State.Notified:Connect(function(data)
		local kind = data.kind
		if kind == "hatch" then
			toasts.hatch(data)
		elseif kind == "announce" then
			toasts.announce(tostring(data.text or ""), data.color, 4)
		elseif kind == "event" then
			toasts.announce(tostring(data.text or ""), data.color, 6)
		else
			toasts.toast(data.text, kind, data.icon)
		end
	end)

	function toasts.update(dt)
		clock += dt
		for index = #active, 1, -1 do
			if clock >= active[index].expires then
				remove(index)
			end
		end
		if announce.Visible then
			local left = announceUntil - clock
			if left <= 0 then
				announce.Visible = false
			elseif left < 0.6 then
				announce.TextTransparency = 1 - left / 0.6
			end
		end
		if card and clock >= cardUntil then
			closeCard()
		end
	end

	function toasts.count()
		return #active
	end

	return toasts
end

return Toasts
