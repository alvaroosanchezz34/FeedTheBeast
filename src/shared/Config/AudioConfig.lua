-- Puntos de integración de audio. NO hay IDs inventados: `id = ""` significa "pendiente de asignar".
-- AudioController ignora los sonidos sin ID. Asigna assets propios o con licencia verificada
-- (ver docs/ASSETS_PENDIENTES.md). `maxPerSecond` limita el spam cuando hay 8 jugadores.
local AudioConfig = {
	MasterVolume = 0.8,
	MaxDistance = 90,
	MaxSimultaneous = 10,

	Sounds = {
		PickupFood = { id = "", volume = 0.5, pitch = { 0.95, 1.15 }, maxPerSecond = 6 },
		Eat = { id = "", volume = 0.6, pitch = { 0.9, 1.2 }, maxPerSecond = 5, spatial = true },
		Grow = { id = "", volume = 0.6, pitch = { 0.95, 1.1 }, maxPerSecond = 3, spatial = true },
		Purchase = { id = "", volume = 0.6, maxPerSecond = 3 },
		Coins = { id = "", volume = 0.5, pitch = { 0.95, 1.1 }, maxPerSecond = 4 },
		Error = { id = "", volume = 0.4, maxPerSecond = 3 },
		Click = { id = "", volume = 0.35, maxPerSecond = 10 },
		Hatch = { id = "", volume = 0.7, maxPerSecond = 2 },
		MutationGolden = { id = "", volume = 0.8, maxPerSecond = 1, spatial = true },
		MutationElectric = { id = "", volume = 0.7, maxPerSecond = 1, spatial = true },
		MutationCosmic = { id = "", volume = 0.8, maxPerSecond = 1, spatial = true },
		RareFind = { id = "", volume = 0.8, maxPerSecond = 1 },
		SecretReveal = { id = "", volume = 0.9, maxPerSecond = 1 },
		Steal = { id = "", volume = 0.7, maxPerSecond = 2, spatial = true },
		StolenAlert = { id = "", volume = 0.8, maxPerSecond = 1 },
		Recover = { id = "", volume = 0.7, maxPerSecond = 2 },
		Deliver = { id = "", volume = 0.7, maxPerSecond = 2 },
		EventStart = { id = "", volume = 0.8, maxPerSecond = 1 },
		EventEnd = { id = "", volume = 0.6, maxPerSecond = 1 },
		Rebirth = { id = "", volume = 0.9, maxPerSecond = 1 },
		ElectricZap = { id = "", volume = 0.15, pitch = { 0.9, 1.3 }, maxPerSecond = 1, spatial = true },
	},

	Music = {
		Main = { id = "", volume = 0.25 },
		Event = { id = "", volume = 0.3 },
	},
}

return AudioConfig
