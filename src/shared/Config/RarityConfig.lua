-- Seis niveles de rareza. El orden importa (de menor a mayor).
local RarityConfig = {}

RarityConfig.Order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Secret" }

RarityConfig.Rarities = {
	Common = { name = "Common", color = Color3.fromRGB(190, 196, 204), valueMult = 1, glow = 0 },
	Uncommon = { name = "Uncommon", color = Color3.fromRGB(96, 214, 110), valueMult = 2.5, glow = 0 },
	Rare = { name = "Rare", color = Color3.fromRGB(72, 150, 255), valueMult = 7, glow = 1 },
	Epic = { name = "Epic", color = Color3.fromRGB(184, 92, 255), valueMult = 20, glow = 1 },
	Legendary = { name = "Legendary", color = Color3.fromRGB(255, 176, 46), valueMult = 60, glow = 2 },
	Secret = { name = "Secret", color = Color3.fromRGB(255, 70, 140), valueMult = 250, glow = 3 },
}

RarityConfig.Index = {}
for i, id in ipairs(RarityConfig.Order) do
	RarityConfig.Index[id] = i
end

function RarityConfig.get(id)
	return RarityConfig.Rarities[id]
end

return RarityConfig
