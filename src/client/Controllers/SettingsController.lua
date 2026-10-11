-- Ajustes del jugador: calidad de efectos y volumen. La calidad "Auto" se decide en el cliente
-- según el dispositivo; la preferencia elegida se guarda en el perfil a través del servidor.
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local VFXConfig = require(Shared.Config.VFXConfig)
local Signal = require(Shared.Signal)

local SettingsController = {}

SettingsController.QualityChanged = Signal.new()
SettingsController.VolumeChanged = Signal.new()

local StateController
local settings = { vfxQuality = "Auto", sfxVolume = 1, musicVolume = 1 }
local resolved = VFXConfig.DefaultQuality

local function detectQuality()
	local saved = 5
	pcall(function()
		local level = UserSettings():GetService("UserGameSettings").SavedQualityLevel
		if level ~= Enum.SavedQualitySetting.Automatic then
			saved = level.Value
		end
	end)
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	if saved <= 3 then
		return "Low"
	elseif touchOnly or saved <= 6 then
		return "Medium"
	end
	return "High"
end

local function resolve()
	local wanted = settings.vfxQuality
	local quality = VFXConfig.Quality[wanted] and wanted or detectQuality()
	if quality ~= resolved then
		resolved = quality
		SettingsController.QualityChanged:Fire(quality)
	end
end

-- Calidad efectiva: "Low" | "Medium" | "High".
function SettingsController.quality()
	return resolved
end

function SettingsController.qualityConfig()
	return VFXConfig.Quality[resolved]
end

function SettingsController.get(key)
	return settings[key]
end

function SettingsController.set(key, value)
	if settings[key] == value then
		return
	end
	settings[key] = value
	StateController.send("SetSetting", key, value)
	if key == "vfxQuality" then
		resolve()
	else
		SettingsController.VolumeChanged:Fire()
	end
end

function SettingsController.Init(controllers)
	StateController = controllers.StateController
	resolved = detectQuality()
end

function SettingsController.Start()
	StateController.observe("settings", function(value)
		if type(value) ~= "table" then
			return
		end
		for key, v in pairs(value) do
			settings[key] = v
		end
		resolve()
		SettingsController.VolumeChanged:Fire()
	end)
end

return SettingsController
