-- Mutaciones. La parte económica (incomeMult, valueMult) la usa solo el servidor.
-- La parte visual (`visual`) la consumen MutationVisuals y AuraController en el cliente.
-- Añadir una mutación = añadir una entrada aquí + (opcional) un aura en VFXConfig.
local MutationConfig = {}

MutationConfig.Order = { "NORMAL", "GOLDEN", "ELECTRIC", "COSMIC" }

MutationConfig.Mutations = {
	NORMAL = {
		id = "NORMAL",
		name = "Normal",
		tier = 0,
		incomeMult = 1,
		valueMult = 1,
		hatchWeight = 0, -- el resto de probabilidad
		feedWeight = 0,
		color = Color3.fromRGB(255, 255, 255),
		aura = nil,
		visual = nil,
	},
	GOLDEN = {
		id = "GOLDEN",
		name = "Golden",
		tier = 1,
		incomeMult = 2,
		valueMult = 3,
		hatchWeight = 0.06,
		feedWeight = 70,
		color = Color3.fromRGB(255, 200, 50),
		aura = "GOLDEN",
		visual = {
			-- role -> override. Roles: Body, Belly, Accent, Detail. (Eye/Mouth/Teeth no se tocan.)
			Body = { color = Color3.fromRGB(255, 196, 40), material = Enum.Material.Metal, reflectance = 0.35 },
			Belly = { color = Color3.fromRGB(255, 232, 140), material = Enum.Material.Metal, reflectance = 0.25 },
			Accent = { color = Color3.fromRGB(214, 140, 20), material = Enum.Material.Metal, reflectance = 0.3 },
			Detail = { color = Color3.fromRGB(255, 244, 200), material = Enum.Material.Neon },
		},
		transformEffect = "MutationGolden",
		feedEffect = "FeedGolden",
		growEffect = "GrowGolden",
		sound = "MutationGolden",
		animSpeed = 1,
	},
	ELECTRIC = {
		id = "ELECTRIC",
		name = "Electric",
		tier = 2,
		incomeMult = 3.5,
		valueMult = 6,
		hatchWeight = 0.025,
		feedWeight = 24,
		color = Color3.fromRGB(70, 220, 255),
		aura = "ELECTRIC",
		visual = {
			Body = { color = Color3.fromRGB(40, 70, 190), material = Enum.Material.Glass, reflectance = 0.1 },
			Belly = { color = Color3.fromRGB(90, 230, 255), material = Enum.Material.Neon },
			Accent = { color = Color3.fromRGB(160, 90, 255), material = Enum.Material.Neon },
			Detail = { color = Color3.fromRGB(220, 250, 255), material = Enum.Material.Neon },
		},
		transformEffect = "MutationElectric",
		feedEffect = "FeedElectric",
		growEffect = "GrowElectric",
		sound = "MutationElectric",
		animSpeed = 1.5,
	},
	COSMIC = {
		id = "COSMIC",
		name = "Cosmic",
		tier = 3,
		incomeMult = 6,
		valueMult = 12,
		hatchWeight = 0.006,
		feedWeight = 6,
		color = Color3.fromRGB(190, 110, 255),
		aura = "COSMIC",
		visual = {
			Body = { color = Color3.fromRGB(28, 16, 64), material = Enum.Material.Glass, reflectance = 0.15 },
			Belly = { color = Color3.fromRGB(120, 60, 220), material = Enum.Material.Neon },
			Accent = { color = Color3.fromRGB(255, 110, 220), material = Enum.Material.Neon },
			Detail = { color = Color3.fromRGB(140, 240, 255), material = Enum.Material.Neon },
		},
		transformEffect = "MutationCosmic",
		feedEffect = "FeedCosmic",
		growEffect = "GrowCosmic",
		sound = "MutationCosmic",
		animSpeed = 0.75,
	},
}

function MutationConfig.get(id)
	return MutationConfig.Mutations[id]
end

function MutationConfig.isValid(id)
	return MutationConfig.Mutations[id] ~= nil
end

return MutationConfig
