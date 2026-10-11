-- Monetización. NINGÚN ID es real todavía: `id = 0` es un placeholder explícito.
-- Hay que crear cada producto en el Creator Dashboard y pegar aquí su ID (ver docs/MONETIZACION.md).
-- Un producto con id 0 se ignora por completo (no se muestra como comprable ni se concede).
-- Los precios en Robux se fijan en el Dashboard; `suggestedRobux` es solo una hipótesis a probar.
local MonetizationConfig = {}

MonetizationConfig.PLACEHOLDER_ID = 0

MonetizationConfig.GamePasses = {
	VIP = { key = "VIP", id = 0, name = "VIP", icon = "👑", suggestedRobux = 199, desc = "+20% coins, VIP chat tag and nameplate crown." },
	AUTO_FEED = { key = "AUTO_FEED", id = 0, name = "Auto-Feed", icon = "🤖", suggestedRobux = 99, desc = "Your creatures eat from your backpack automatically." },
	EXTRA_SLOT = { key = "EXTRA_SLOT", id = 0, name = "Bonus Pen", icon = "🏠", suggestedRobux = 99, desc = "+1 creature slot (beyond coin upgrades)." },
}

MonetizationConfig.Products = {
	GROWTH_BOOST = { key = "GROWTH_BOOST", id = 0, name = "Growth Boost (15 min)", icon = "⚡", suggestedRobux = 49, desc = "x2 growth from food for 15 minutes.", grant = { type = "Boost", boost = "Growth", seconds = 900 } },
	-- Cosmético: garantiza una apariencia de parcela premium. No da ventaja económica.
	PLOT_AURA = { key = "PLOT_AURA", id = 0, name = "Plot Aura Pack", icon = "🌈", suggestedRobux = 149, desc = "Cosmetic glowing border for your plot.", grant = { type = "Cosmetic", cosmetic = "PLOT_AURA" } },
}

MonetizationConfig.AutoFeed = {
	Interval = 3, -- segundos entre alimentaciones automáticas por jugador
}

-- Número de recibos recordados por perfil para idempotencia.
MonetizationConfig.ReceiptHistory = 100
MonetizationConfig.MaxBoostSeconds = 24 * 3600

function MonetizationConfig.isConfigured(def)
	return type(def) == "table" and type(def.id) == "number" and def.id > 0
end

function MonetizationConfig.productById(id)
	for _, def in pairs(MonetizationConfig.Products) do
		if def.id == id and def.id > 0 then
			return def
		end
	end
	return nil
end

return MonetizationConfig
