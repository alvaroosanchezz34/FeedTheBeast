-- Tutorial sin ventanas: un único objetivo visible arriba y una línea-guía en el mundo.
-- Se deduce del progreso real que envía el servidor (estadísticas y flags), así que no hay
-- estado propio que guardar y un jugador veterano nunca lo ve.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CreatureConfig = require(Shared.Config.CreatureConfig)

local Theme = require(script.Parent.Theme)

local Tutorial = {}

local C = Theme.Colors
local PLAZA = Vector3.new(0, 1, 0)
local FOOD_GOAL = 6 -- comidas recogidas para dar por aprendido "la plaza tiene comida"

function Tutorial.create(ctx, hud)
	local State = ctx.State
	local tutorial = { step = nil }
	local timer = 0

	local function ownCreature()
		local best = nil
		for _, entry in pairs(ctx.Creatures.entries()) do
			if entry.isOwn and not entry.isGiant then
				if not best or entry.creatureId < best.creatureId then
					best = entry
				end
			end
		end
		return best
	end

	local function evaluate()
		local stats = State.get("stats")
		local flags = State.get("flags")
		if not stats or not flags then
			return nil
		end
		local inventory = State.get("inventory") or {}
		local hasFood = next(inventory) ~= nil
		local creature = ownCreature()
		local creaturePos = creature and creature.visual.root.CFrame.Position or nil
		local name = creature and CreatureConfig.Species[creature.speciesId].name or "your beast"

		if (stats.foodsFed or 0) == 0 then
			if not hasFood then
				return "grab", "Walk forward and grab the food!", C.Orange, creaturePos
			end
			return "feed", string.format("Go to %s and FEED it! (E or tap)", name), C.Green, creaturePos
		end
		if not flags.firstCollect then
			local plot = ctx.World.ownPlot()
			return "collect", "It makes coins! Step on your GOLD pad to collect.", Theme.darken(C.Gold, 0.15), plot and plot.collectPos or nil
		end
		local upgrades = State.get("upgrades")
		local spent = (stats.eggsHatched or 0) > 0
		if upgrades then
			for _, level in pairs(upgrades.levels) do
				if level > 0 then
					spent = true
				end
			end
		end
		if not spent and (stats.foodsCollected or 0) < FOOD_GOAL then
			return "plaza", "More food in the PLAZA! Feed, grow, then visit the SHOP.", C.Blue, PLAZA
		end
		return nil
	end

	function tutorial.refresh()
		local step, text, color, target = evaluate()
		if step ~= tutorial.step then
			tutorial.step = step
			hud.setObjective(text, color)
			if step then
				ctx.Audio.play("Click")
			end
		end
		-- El destino puede cambiar (la criatura aparece un instante después del estado).
		ctx.setGuide("tutorial", step and target or nil, color)
	end

	for _, key in ipairs({ "stats", "flags", "inventory", "upgrades", "creatures" }) do
		State.observe(key, function()
			tutorial.refresh()
		end)
	end

	function tutorial.update(dt)
		timer += dt
		if timer >= 1 then
			timer = 0
			tutorial.refresh()
		end
	end

	return tutorial
end

return Tutorial
