--!nocheck
-- Exporta a JSON la geometría de las criaturas (todas las especies x mutaciones) y del mapa,
-- usando el código real del juego, para dibujar una previsualización APROXIMADA fuera de Roblox.
--   lune run tools/preview/export        (desde la raíz del repo)  ->  build/preview/*.json
-- Después:  python3 tools/preview/render.py
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Harness = require("../../tests/lib/Harness")

local function partData(part, extra)
	local shape = "Block"
	if part.ClassName == "WedgePart" then
		shape = "Wedge"
	elseif part.ClassName == "Part" then
		shape = part.Shape.Name
	elseif part.ClassName == "SpawnLocation" then
		shape = "Block"
	end
	local mesh = part:FindFirstChildOfClass("SpecialMesh")
	if mesh and mesh.MeshType.Name == "Sphere" then
		shape = "Ellipsoid"
	end
	local data = {
		name = part.Name,
		shape = shape,
		size = { part.Size.X, part.Size.Y, part.Size.Z },
		cf = { part.CFrame:GetComponents() },
		color = { part.Color.R, part.Color.G, part.Color.B },
		material = part.Material.Name,
		transparency = part.Transparency,
	}
	if extra then
		for key, value in pairs(extra) do
			data[key] = value
		end
	end
	return data
end

return function()
	local h = Harness.new({})
	local s = h:bootServer()
	local Shared = "ReplicatedStorage.Shared."
	local Builder = h:require(Shared .. "Creatures.CreatureBuilder")
	local MutationVisuals = h:require(Shared .. "Creatures.MutationVisuals")
	local CreatureConfig = h:require(Shared .. "Config.CreatureConfig")
	local MutationConfig = h:require(Shared .. "Config.MutationConfig")

	if not fs.isDir("build/preview") then
		fs.writeDir("build/preview")
	end

	-- Resuelve las soldaduras como lo haría el motor.
	local function solve(visual)
		for _, record in ipairs(visual.records) do
			local weld = record.weld
			weld.Part1.CFrame = weld.Part0.CFrame * weld.C0 * weld.C1:Inverse()
		end
	end

	local creatures = {}
	for _, speciesId in ipairs(CreatureConfig.Order) do
		for _, mutationId in ipairs(MutationConfig.Order) do
			for _, pose in ipairs({ "idle", "eat", "stage2", "stage3" }) do
				if pose == "idle" or mutationId == "NORMAL" then
					local visual = Builder.build(speciesId)
					MutationVisuals.apply(visual, mutationId)
					if pose == "stage2" or pose == "stage3" then
						visual:setStage(pose == "stage2" and 2 or 3)
					end
					visual.species.idle(visual, 0.9)
					if pose == "eat" then
						visual.species.eat(visual, 0.17)
					end
					visual:applyPoses()
					solve(visual)
					local parts = {}
					for _, record in ipairs(visual.records) do
						if record.part.Transparency < 1 then
							table.insert(parts, partData(record.part, { role = record.role }))
						end
					end
					table.insert(creatures, {
						species = speciesId,
						name = CreatureConfig.Species[speciesId].name,
						rarity = CreatureConfig.Species[speciesId].rarity,
						mutation = mutationId,
						pose = pose,
						height = visual.height,
						radius = visual.radius,
						parts = parts,
					})
					visual:destroy()
				end
			end
		end
	end
	fs.writeFile("build/preview/creatures.json", serde.encode("json", creatures))

	-- Comida: los 20 modelos.
	local FoodModels = h:require(Shared .. "Food.FoodModels")
	local FoodConfig = h:require(Shared .. "Config.FoodConfig")
	local foods = {}
	for _, foodId in ipairs(FoodConfig.Order) do
		local visual = FoodModels.build(foodId)
		if visual then
			solve(visual)
			local parts = {}
			for _, record in ipairs(visual.records) do
				if record.part.Transparency < 1 then
					table.insert(parts, partData(record.part))
				end
			end
			table.insert(foods, { id = foodId, name = FoodConfig.Foods[foodId].name, rarity = FoodConfig.Foods[foodId].rarity, height = visual.height, radius = visual.radius, parts = parts })
			visual:destroy()
		end
	end
	fs.writeFile("build/preview/foods.json", serde.encode("json", foods))

	-- Mapa: todas las piezas visibles que construye el servidor, con un jugador por parcela.
	for i = 1, 3 do
		h:joinPlayer(i, "P" .. i)
	end
	local world = {}
	-- Sin física, las piezas soldadas (p. ej. la hamburguesa del puesto) hay que colocarlas a mano.
	for _ = 1, 4 do -- varias pasadas: el orden de los descendientes no garantiza padres antes que hijos
		for _, d in ipairs(h.game:GetService("Workspace"):GetDescendants()) do
			if d.ClassName == "Weld" and d.Part0 and d.Part1 then
				d.Part1.CFrame = d.Part0.CFrame * d.C0 * d.C1:Inverse()
			end
		end
	end
	for _, d in ipairs(h.game:GetService("Workspace"):GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 and d.Name ~= "HumanoidRootPart" then
			table.insert(world, partData(d))
		end
	end
	fs.writeFile("build/preview/world.json", serde.encode("json", world))
	print(string.format("exported %d creature views and %d world parts to build/preview/", #creatures, #world))
end
