-- Audio. Todos los sonidos se definen en AudioConfig; los que no tienen ID asignado se ignoran
-- (no hay IDs inventados). Limita la frecuencia por sonido y el número de sonidos simultáneos
-- para que 8 jugadores no se conviertan en ruido constante.
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AudioConfig = require(Shared.Config.AudioConfig)

local AudioController = {}

local SettingsController
local EffectCleanup
local history = {} -- nombre -> lista de relojes de reproducciones recientes
local active = 0
local music = nil
local rng = Random.new()

local function allowed(name, def)
	local now = os.clock()
	local list = history[name]
	if not list then
		list = {}
		history[name] = list
	end
	while #list > 0 and now - list[1] > 1 do
		table.remove(list, 1)
	end
	if #list >= (def.maxPerSecond or 4) then
		return false
	end
	table.insert(list, now)
	return true
end

-- Reproduce un sonido de AudioConfig.Sounds. `position` atenúa el volumen con la distancia.
function AudioController.play(name, position)
	local def = AudioConfig.Sounds[name]
	if not def or def.id == "" then
		return false
	end
	local volume = def.volume * AudioConfig.MasterVolume * (SettingsController.get("sfxVolume") or 1)
	if volume <= 0 then
		return false
	end
	if def.spatial and position then
		local camera = workspace.CurrentCamera
		if camera then
			local distance = (camera.CFrame.Position - position).Magnitude
			volume *= math.clamp(1 - distance / AudioConfig.MaxDistance, 0, 1)
			if volume <= 0.01 then
				return false
			end
		end
	end
	if active >= AudioConfig.MaxSimultaneous or not allowed(name, def) then
		return false
	end
	local sound = Instance.new("Sound")
	sound.Name = "FTB_" .. name
	sound.SoundId = def.id
	sound.Volume = volume
	if def.pitch then
		sound.PlaybackSpeed = rng:NextNumber(def.pitch[1], def.pitch[2])
	end
	sound.Parent = SoundService
	active += 1
	sound:Play()
	-- El hueco de "simultáneo" se libera pronto; la instancia se destruye cuando ya ha sonado.
	EffectCleanup.after(2.5, function()
		active = math.max(0, active - 1)
	end)
	EffectCleanup.track(sound, 10)
	return true
end

local function refreshMusic()
	local def = AudioConfig.Music.Main
	if not def or def.id == "" then
		return
	end
	if not music then
		music = Instance.new("Sound")
		music.Name = "FTB_Music"
		music.SoundId = def.id
		music.Looped = true
		music.Parent = SoundService
		music:Play()
	end
	music.Volume = def.volume * AudioConfig.MasterVolume * (SettingsController.get("musicVolume") or 1)
end

function AudioController.Init(controllers)
	SettingsController = controllers.SettingsController
	EffectCleanup = controllers.EffectCleanup
end

function AudioController.Start()
	refreshMusic()
	SettingsController.VolumeChanged:Connect(refreshMusic)
end

return AudioController
