-- Tipos de referencia (documentación viva del esquema de datos).
export type Creature = {
	id: string,
	species: string,
	mutation: string,
	growth: number,
	slot: number, -- 0 = guardada
	born: number,
}

export type Profile = {
	version: number,
	createdAt: number,
	lastSave: number,
	coins: number,
	pendingCoins: number,
	pendingOffline: number,
	inventory: { [string]: number },
	creatures: { [string]: Creature },
	nextCreatureId: number,
	collection: { [string]: boolean },
	upgrades: { [string]: number },
	rebirths: number,
	boosts: { [string]: number },
	cosmetics: { [string]: boolean },
	stats: { [string]: number },
	flags: { [string]: boolean },
	settings: { vfxQuality: string, sfxVolume: number, musicVolume: number },
	receipts: { string },
}

return {}
