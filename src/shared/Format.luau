-- Turns big numbers into short text, for example 15300 becomes "15.3K".

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp" }

function Format.short(value: number): string
	value = math.floor(value)
	if value < 1000 then
		return tostring(value)
	end

	local index = 1
	while value >= 1000 and index < #SUFFIXES do
		value /= 1000
		index += 1
	end

	local text
	if value >= 100 then
		text = string.format("%d", math.floor(value))
	elseif value >= 10 then
		text = string.format("%.1f", math.floor(value * 10) / 10)
	else
		text = string.format("%.2f", math.floor(value * 100) / 100)
	end
	return text .. SUFFIXES[index]
end

-- Reads amounts people type, like "2500", "1.5k", "720b" or "3M".
-- Returns nil when the text is not a number.
local MULTIPLIERS = { k = 1e3, m = 1e6, b = 1e9, t = 1e12, qa = 1e15, qi = 1e18 }

function Format.parse(text: string): number?
	local cleaned = string.lower(string.gsub(text, "[%s,]", ""))
	local number, suffix = string.match(cleaned, "^(%d*%.?%d+)(%a*)$")
	if not number then
		return nil
	end
	local value = tonumber(number)
	if not value then
		return nil
	end
	if suffix ~= "" then
		local multiplier = MULTIPLIERS[suffix]
		if not multiplier then
			return nil
		end
		value *= multiplier
	end
	return math.floor(value)
end

return Format
