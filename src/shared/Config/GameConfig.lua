-- Configuración general del juego. Todo valor ajustable de alto nivel vive aquí.
local GameConfig = {
	Version = "0.1.0",

	MaxPlayers = 8,
	PlotCount = 8,

	StartingCoins = 50,
	StarterSpecies = "GOBBLO",
	-- Espacio central de la primera fila: queda justo delante del punto de aparición.
	StarterSlot = 2,
	-- Comida que aparece en la propia parcela la primera vez (tutorial rápido).
	StarterPickups = { "BREAD_CRUMB", "APPLE", "CARROT" },

	-- Jugadores con menos tiempo total de juego que esto no pueden ser robados.
	NewPlayerProtectionSeconds = 180,

	Admins = {
		-- Rellenar con los UserId autorizados. Nunca se confía en el cliente.
		UserIds = {},
		AllowPlaceCreator = true,
		AllowInStudio = true,
	},

	Data = {
		StoreName = "FTB_PlayerData_v1",
		KeyPrefix = "player_",
		AutosaveInterval = 120,
		-- Un bloqueo de sesión más antiguo que esto se considera abandonado.
		SessionLockTimeout = 600,
		MaxRetries = 5,
		RetryBaseDelay = 1,
		LoadKickMessage = "No se pudieron cargar tus datos de forma segura. Vuelve a entrar en unos minutos (tu progreso NO se ha sobrescrito).",
	},

	Interaction = {
		-- Distancia base (studs) para alimentar; se suma el radio del hitbox.
		FeedBaseDistance = 10,
		PickupDistance = 14,
		PadDistance = 16,
		GiantFeedDistance = 40,
	},

	World = {
		GroundSize = 420,
		PlotRingRadius = 132,
		PlotSize = 56,
		PlazaRadius = 78,
		FoodRingInner = 16,
		FoodRingOuter = 46,
		PedestalRadius = 12,
		KioskRadius = 62,
		MaxSlotsPerPlot = 6,
	},

	-- Comida que aparece sola en la zona central.
	FoodField = {
		BaseActive = 22,
		PerPlayer = 5,
		MaxActive = 60,
		SpawnInterval = 0.9,
		Lifetime = 240,
		PickupRadius = 5,
		StarterLifetime = 900,
		FullNoticeCooldown = 5,
	},

	Character = {
		WalkSpeed = 18,
	},
}

return GameConfig
