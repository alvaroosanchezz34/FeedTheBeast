-- Definición única de todos los remotos. El servidor los crea (ValidationService) y aplica a
-- cada uno validación de argumentos y rate limiting. Los remotos transportan INTENCIONES del
-- jugador; ningún remoto concede resultados por sí mismo.
local Constants = require(script.Parent.Constants)

local RemoteDefinitions = {
	FolderName = Constants.Folders.Remotes,

	-- Cliente -> servidor. rate = peticiones/segundo sostenidas, burst = ráfaga máxima.
	ServerEvents = {
		ClientReady = { args = {}, rate = 0.5, burst = 2 },
		Feed = { args = { { type = "id" }, { type = "id" } }, rate = 4, burst = 6 },
		GiantFeed = { args = { { type = "id" } }, rate = 4, burst = 6 },
		BuyFood = { args = { { type = "id" }, { type = "int", min = 1, max = 50 } }, rate = 5, burst = 8 },
		BuyEgg = { args = { { type = "id" } }, rate = 2, burst = 3 },
		BuyUpgrade = { args = { { type = "id" } }, rate = 4, burst = 6 },
		PlaceCreature = { args = { { type = "id" }, { type = "int", min = 1, max = 6 } }, rate = 3, burst = 5 },
		StoreCreature = { args = { { type = "id" } }, rate = 3, burst = 5 },
		SellCreature = { args = { { type = "id" } }, rate = 2, burst = 3 },
		ConfirmRebirth = { args = { { type = "string", maxLen = 64 } }, rate = 0.5, burst = 2 },
		ClaimOffline = { args = {}, rate = 1, burst = 2 },
		SetSetting = { args = { { type = "enum", values = Constants.SettingKeys }, { type = "setting" } }, rate = 4, burst = 8 },
		DropCrate = { args = {}, rate = 1, burst = 2 },
		Admin = {
			args = { { type = "id" }, { type = "string", maxLen = 60, optional = true }, { type = "string", maxLen = 60, optional = true } },
			rate = 2,
			burst = 4,
		},
	},

	-- Cliente -> servidor con respuesta.
	ServerFunctions = {
		GetRebirthInfo = { args = {}, rate = 1, burst = 3 },
	},

	-- Servidor -> cliente.
	ClientEvents = {
		"State", -- (patch: tabla) fusiona campos del estado visible del jugador
		"Notify", -- ({ text, kind, icon })
		"Effect", -- (effectId, { model?, position?, radius?, ... })
		"CreatureEvent", -- (model, kind, data) : "Fed" | "Grew" | "Mutated" | "Spawned"
	},
}

return RemoteDefinitions
