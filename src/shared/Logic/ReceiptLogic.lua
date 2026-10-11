-- Lógica pura e idempotente de concesión de Developer Products.
local MonetizationConfig = require(script.Parent.Parent.Config.MonetizationConfig)

local ReceiptLogic = {}

ReceiptLogic.Status = {
	Granted = "Granted",
	AlreadyGranted = "AlreadyGranted",
	UnknownProduct = "UnknownProduct",
	Invalid = "Invalid",
}

function ReceiptLogic.hasReceipt(profile, purchaseId)
	for _, id in ipairs(profile.receipts) do
		if id == purchaseId then
			return true
		end
	end
	return false
end

-- Aplica un `grant` del MonetizationConfig a un perfil.
function ReceiptLogic.applyGrant(profile, grant, now)
	if type(grant) ~= "table" then
		return false
	end
	if grant.type == "Boost" then
		local current = profile.boosts[grant.boost]
		local base = (type(current) == "number" and current > now) and current or now
		local expires = math.min(base + grant.seconds, now + MonetizationConfig.MaxBoostSeconds)
		profile.boosts[grant.boost] = expires
		return true
	elseif grant.type == "Cosmetic" then
		profile.cosmetics[grant.cosmetic] = true
		return true
	end
	return false
end

-- receipt = { PurchaseId = string, ProductId = number, PlayerId = number }
-- Devuelve un Status. Solo modifica el perfil cuando devuelve Granted.
function ReceiptLogic.process(profile, receipt, now)
	if type(receipt) ~= "table" or type(receipt.PurchaseId) ~= "string" or type(receipt.ProductId) ~= "number" then
		return ReceiptLogic.Status.Invalid
	end
	if ReceiptLogic.hasReceipt(profile, receipt.PurchaseId) then
		return ReceiptLogic.Status.AlreadyGranted
	end
	local def = MonetizationConfig.productById(receipt.ProductId)
	if not def then
		return ReceiptLogic.Status.UnknownProduct
	end
	if not ReceiptLogic.applyGrant(profile, def.grant, now) then
		return ReceiptLogic.Status.Invalid
	end
	table.insert(profile.receipts, receipt.PurchaseId)
	while #profile.receipts > MonetizationConfig.ReceiptHistory do
		table.remove(profile.receipts, 1)
	end
	return ReceiptLogic.Status.Granted
end

function ReceiptLogic.boostActive(profile, boostId, now)
	local expires = profile.boosts[boostId]
	return type(expires) == "number" and expires > now
end

return ReceiptLogic
