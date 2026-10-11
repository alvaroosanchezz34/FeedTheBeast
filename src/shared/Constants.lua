-- Nombres compartidos entre servidor y cliente (tags, atributos, carpetas).
local Constants = {
	Tags = {
		Creature = "FTB_Creature",
		Pickup = "FTB_Pickup",
		Crate = "FTB_Crate",
		Plot = "FTB_Plot",
		Kiosk = "FTB_Kiosk",
	},

	Folders = {
		World = "FTB_World",
		Plots = "Plots",
		Creatures = "FTB_Creatures",
		Pickups = "FTB_Pickups",
		Crates = "FTB_Crates",
		Remotes = "FTB_Remotes",
		EventState = "FTB_EventState",
		ClientFX = "FTB_ClientFX",
	},

	-- Atributos de un modelo de criatura (los escribe SOLO el servidor).
	CreatureAttr = {
		Id = "CreatureId",
		Species = "Species",
		Mutation = "Mutation",
		Rarity = "Rarity",
		Scale = "Scale",
		Level = "Level",
		Owner = "OwnerUserId",
		Giant = "IsGiant",
		EatingUntil = "EatingUntil",
		Pivot = "Pivot", -- CFrame del punto de apoyo (no depende de que las piezas hayan llegado al cliente)
	},

	PlotAttr = {
		Index = "PlotIndex",
		Owner = "OwnerUserId",
		OwnerName = "OwnerName",
		Style = "Style",
		Income = "Income",
		Pending = "Pending",
		PendingCap = "PendingCap",
		Aura = "PlotAura",
	},

	EventAttr = {
		Id = "EventId", -- "" si no hay evento
		Phase = "Phase", -- "Idle" | "Announce" | "Active"
		StartsAt = "StartsAt", -- tiempo de servidor (workspace:GetServerTimeNow)
		EndsAt = "EndsAt",
		Progress = "Progress",
		Goal = "Goal",
	},

	CrateAttr = {
		Id = "CrateId",
		Tier = "Tier",
		State = "State",
		Carrier = "CarrierUserId",
	},

	PickupAttr = {
		Id = "PickupId",
		Food = "FoodId",
		Golden = "Golden",
		DropFrom = "DropFrom", -- altura desde la que cae (0 = aparece en el sitio)
		Owner = "Owner", -- userId del único jugador que puede recogerla (0 = cualquiera)
	},

	SettingKeys = { "vfxQuality", "sfxVolume", "musicVolume" },
}

return Constants
