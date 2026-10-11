-- Utilidades puras compartidas.
local Utilities = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }

-- 1234 -> "1.23K", 1500000 -> "1.5M"
function Utilities.formatNumber(n)
	if type(n) ~= "number" or n ~= n then
		return "0"
	end
	local negative = n < 0
	n = math.abs(n)
	local index = 1
	while n >= 1000 and index < #SUFFIXES do
		n /= 1000
		index += 1
	end
	local text
	if index == 1 then
		text = tostring(math.floor(n + 0.5))
	elseif n >= 100 then
		text = string.format("%.0f", n)
	elseif n >= 10 then
		text = string.format("%.1f", n)
	else
		text = string.format("%.2f", n)
	end
	-- Quita ceros decimales sobrantes ("1.50" -> "1.5", "2.0" -> "2").
	if string.find(text, ".", 1, true) then
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "%.$", "")
	end
	return (negative and "-" or "") .. text .. SUFFIXES[index]
end

-- 3725 -> "1h 2m", 75 -> "1:15"
function Utilities.formatTime(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	if seconds >= 3600 then
		return string.format("%dh %dm", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
	end
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

function Utilities.shallowCopy(t)
	local copy = {}
	for k, v in pairs(t) do
		copy[k] = v
	end
	return copy
end

function Utilities.deepCopy(t)
	if type(t) ~= "table" then
		return t
	end
	local copy = {}
	for k, v in pairs(t) do
		copy[k] = Utilities.deepCopy(v)
	end
	return copy
end

function Utilities.lerp(a, b, t)
	return a + (b - a) * t
end

return Utilities
