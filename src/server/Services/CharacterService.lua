-- Seguimiento de personajes: posición autoritativa en servidor, velocidad y teletransporte a la parcela.
--
-- API:
--   CharacterService.positionOf(userId) -> Vector3 | nil   (nil si no hay personaje vivo)
--   CharacterService.setSpeedMult(userId, mult)
--   CharacterService.teleportHome(userId)
--   CharacterService.Died : Signal(userId)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Signal = require(Shared.Signal)

local CharacterService = {}
CharacterService.Died = Signal.new()

local services
local chars = {} -- userId -> { character, humanoid, root, alive, speedMult }
local speedMults = {} -- userId -> mult (persiste entre respawns)

local function applySpeed(userId)
	local entry = chars[userId]
	if entry and entry.humanoid then
		entry.humanoid.WalkSpeed = GameConfig.Character.WalkSpeed * (speedMults[userId] or 1)
	end
end

function CharacterService.teleportHome(userId)
	local entry = chars[userId]
	local session = services.PlayerDataService.getSession(userId)
	if not entry or not entry.character or not session or not session.plotIndex then
		return false
	end
	local cf = services.PlotService.spawnCFrame(session.plotIndex)
	if not cf then
		return false
	end
	entry.character:PivotTo(cf)
	return true
end

local function onCharacter(player, character)
	local userId = player.UserId
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not root then
		return
	end
	local entry = { character = character, humanoid = humanoid, root = root, alive = true }
	chars[userId] = entry
	applySpeed(userId)
	humanoid.Died:Connect(function()
		if chars[userId] == entry then
			entry.alive = false
			CharacterService.Died:Fire(userId)
		end
	end)
	-- El motor coloca al personaje en el spawn DESPUÉS de CharacterAdded: se espera a que esté
	-- en Workspace y se mueve a la parcela en el siguiente paso.
	task.spawn(function()
		local waited = 0
		while character.Parent ~= workspace and waited < 5 do
			task.wait(0.05)
			waited += 0.05
		end
		task.wait(0.1)
		if chars[userId] == entry and character.Parent == workspace then
			CharacterService.teleportHome(userId)
		end
	end)
end

function CharacterService.Init(allServices)
	services = allServices
end

function CharacterService.Start()
	local function onPlayer(player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		chars[player.UserId] = nil
		speedMults[player.UserId] = nil
	end)
	-- Cuando se asigna la parcela (sesión iniciada) el personaje puede existir ya.
	services.PlayerDataService.SessionStarted:Connect(function(session)
		task.defer(function()
			CharacterService.teleportHome(session.userId)
		end)
	end)
end

function CharacterService.positionOf(userId)
	local entry = chars[userId]
	if not entry or not entry.alive then
		return nil
	end
	local root = entry.root
	if not root or not root.Parent then
		return nil
	end
	return root.CFrame.Position
end

function CharacterService.rootOf(userId)
	local entry = chars[userId]
	if entry and entry.alive and entry.root and entry.root.Parent then
		return entry.root
	end
	return nil
end

function CharacterService.setSpeedMult(userId, mult)
	speedMults[userId] = mult
	applySpeed(userId)
end

function CharacterService.speedOf(userId)
	return GameConfig.Character.WalkSpeed * (speedMults[userId] or 1)
end

return CharacterService
