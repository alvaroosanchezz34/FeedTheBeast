-- Clasificación del servidor mediante `leaderstats` (lista de jugadores nativa de Roblox).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyMath = require(Shared.Logic.EconomyMath)

local LeaderboardService = {}

local services
local timer = 0

local function ensure(session)
	local player = session.player
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		for _, name in ipairs({ "Coins", "Rebirths", "Best Lv" }) do
			local value = Instance.new("IntValue")
			value.Name = name
			value.Parent = stats
		end
		stats.Parent = player
	end
	return stats
end

local function refresh(session)
	if not session.player or not session.player.Parent then
		return
	end
	local stats = ensure(session)
	local profile = session.profile
	local maxLevel = EconomyMath.maxLevel(profile.rebirths)
	local best = 0
	for _, creature in pairs(profile.creatures) do
		best = math.max(best, (EconomyMath.levelFromGrowth(creature.species, creature.growth, maxLevel)))
	end
	local function set(name, value)
		local object = stats:FindFirstChild(name)
		if object and object.Value ~= value then
			object.Value = value
		end
	end
	set("Coins", math.floor(profile.coins))
	set("Rebirths", profile.rebirths)
	set("Best Lv", best)
end

function LeaderboardService.Init(allServices)
	services = allServices
end

function LeaderboardService.Start()
	services.PlayerDataService.SessionStarted:Connect(refresh)
end

function LeaderboardService.Update(dt)
	timer += dt
	if timer < 2 then
		return
	end
	timer = 0
	services.PlayerDataService.forEach(refresh)
end

return LeaderboardService
