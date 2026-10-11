-- Ventana de tareas diarias: progreso, recompensa, botón de reclamar, premio extra y cuenta atrás.
-- Solo muestra lo que envía el servidor (clave de estado "quests"); reclamar es una petición que
-- el servidor valida (una tarea no se puede cobrar dos veces).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Utilities = require(Shared.Utilities)
local Clock = require(Shared.Clock)

local Theme = require(script.Parent.Theme)

local TasksWindow = {}

local C = Theme.Colors

-- ¿Hay algo que reclamar? (lo usa también el HUD para el indicador del botón).
function TasksWindow.hasClaimable(view)
	if type(view) ~= "table" then
		return false
	end
	for _, quest in ipairs(view.list or {}) do
		if quest.done and not quest.claimed then
			return true
		end
	end
	return view.bonus ~= nil and view.bonus.ready == true
end

function TasksWindow.register(manager, ctx)
	local State = ctx.State

	manager.register("tasks", {
		title = "DAILY TASKS",
		icon = "📋",
		color = C.Purple or C.Blue,
		watch = { "quests" },
		render = function(content)
			local view = State.get("quests")
			if type(view) ~= "table" or #(view.list or {}) == 0 then
				Theme.label({ name = "Empty", text = "Tasks are loading…", textSize = 18, color = C.TextDim }, content)
				return nil
			end

			local timerLabel = Theme.label({
				name = "Timer",
				text = "",
				textSize = 15,
				color = C.TextDim,
				size = UDim2.new(1, 0, 0, 22),
				alignX = Enum.TextXAlignment.Right,
			}, content)
			Theme.label({
				name = "Hint",
				text = "Finish all three for the daily bonus.",
				textSize = 15,
				color = C.TextDim,
				size = UDim2.new(1, 0, 0, 22),
				alignX = Enum.TextXAlignment.Left,
			}, content)

			local scroll = Theme.scroll({ size = UDim2.new(1, 0, 1, -28), position = UDim2.fromOffset(0, 28) }, content)
			Theme.padding(scroll, 4, 6, 12, 6)
			Theme.list(scroll, "V", 8)

			for order, quest in ipairs(view.list) do
				local stateColor = quest.claimed and C.Grey or (quest.done and C.Gold or C.PanelLight)
				local row = Theme.panel({ name = "Task_" .. quest.index, size = UDim2.new(1, -4, 0, 96), color = C.PanelDark, strokeColor = stateColor, order = order }, scroll)
				Theme.label({ name = "Icon", text = quest.icon or "📋", textSize = 36, size = UDim2.fromOffset(56, 56), position = UDim2.fromOffset(10, 10) }, row)
				Theme.label({ name = "Name", text = quest.name, font = Theme.Fonts.Display, textSize = 20, stroke = true, size = UDim2.new(1, -230, 0, 26), position = UDim2.fromOffset(74, 8), alignX = Enum.TextXAlignment.Left, scaled = true, maxTextSize = 20 }, row)
				Theme.label({ name = "Desc", text = quest.desc, textSize = 14, color = C.TextDim, size = UDim2.new(1, -230, 0, 20), position = UDim2.fromOffset(74, 34), alignX = Enum.TextXAlignment.Left, scaled = true, maxTextSize = 14 }, row)
				local bar = Theme.progress({ name = "Bar", size = UDim2.new(1, -230, 0, 18), position = UDim2.fromOffset(74, 62), color = quest.done and C.Gold or C.Green, radius = 8 }, row)
				bar.set(quest.goal > 0 and quest.progress / quest.goal or 0)
				Theme.label({ name = "Count", text = string.format("%d / %d", quest.progress, quest.goal), textSize = 13, stroke = true, size = UDim2.fromScale(1, 1), zindex = 3 }, bar.instance)
				Theme.label({ name = "Reward", text = "🎁 " .. quest.reward, textSize = 13, color = C.Gold, size = UDim2.fromOffset(140, 30), position = UDim2.new(1, -10, 0, 6), anchor = Vector2.new(1, 0), alignX = Enum.TextXAlignment.Right, wrapped = true }, row)
				local button = Theme.button({
					name = "Claim",
					text = quest.claimed and "DONE ✓" or (quest.done and "CLAIM" or "IN PROGRESS"),
					color = quest.claimed and C.Grey or (quest.done and C.Green or C.PanelLight),
					size = UDim2.fromOffset(140, 44),
					position = UDim2.new(1, -10, 1, -8),
					anchor = Vector2.new(1, 1),
					textSize = 16,
					onClick = function()
						State.send("ClaimQuest", quest.index)
					end,
				}, row)
				button.setEnabled(quest.done and not quest.claimed)
			end

			local bonus = view.bonus or {}
			local bonusRow = Theme.panel({ name = "Bonus", size = UDim2.new(1, -4, 0, 74), color = Theme.darken(C.Gold, 0.6), strokeColor = C.Gold, order = 99 }, scroll)
			Theme.label({ text = "🎁", textSize = 34, size = UDim2.fromOffset(56, 56), position = UDim2.fromOffset(10, 9) }, bonusRow)
			Theme.label({ text = "Daily bonus", font = Theme.Fonts.Display, textSize = 20, stroke = true, size = UDim2.new(1, -230, 0, 26), position = UDim2.fromOffset(74, 10), alignX = Enum.TextXAlignment.Left }, bonusRow)
			Theme.label({ name = "Reward", text = tostring(bonus.reward or ""), textSize = 14, color = C.Gold, size = UDim2.new(1, -230, 0, 22), position = UDim2.fromOffset(74, 38), alignX = Enum.TextXAlignment.Left, scaled = true, maxTextSize = 14 }, bonusRow)
			local bonusButton = Theme.button({
				name = "ClaimBonus",
				text = bonus.claimed and "DONE ✓" or (bonus.ready and "CLAIM" or "LOCKED"),
				color = bonus.claimed and C.Grey or (bonus.ready and C.Green or C.PanelLight),
				size = UDim2.fromOffset(140, 48),
				position = UDim2.new(1, -10, 0.5, 0),
				anchor = Vector2.new(1, 0.5),
				textSize = 16,
				onClick = function()
					State.send("ClaimQuestBonus")
				end,
			}, bonusRow)
			bonusButton.setEnabled(bonus.ready == true)

			local shown = nil
			local function tick()
				local left = math.max(0, math.floor((view.resetAt or 0) - Clock.unix()))
				if left ~= shown then
					shown = left
					timerLabel.Text = "New tasks in " .. Utilities.formatTime(left)
				end
			end
			tick()
			-- Sin `update`: al cambiar "quests" la ventana se reconstruye conservando el scroll.
			return { tick = tick }
		end,
	})
end

return TasksWindow
