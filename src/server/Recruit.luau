-- Rolls new soldiers for the warband.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local Recruit = {}

local random = Random.new()

local function rollRarity(tier)
	local total = 0
	for _, weight in tier.chances do
		total += weight
	end
	local roll = random:NextNumber(0, total)
	for index, weight in tier.chances do
		if weight > 0 then
			roll -= weight
			if roll <= 0 then
				return GameConfig.Rarities[index].id
			end
		end
	end
	-- Rounding left us past the end: take the most common rarity this tier has.
	for index, weight in tier.chances do
		if weight > 0 then
			return GameConfig.Rarities[index].id
		end
	end
	return GameConfig.Rarities[1].id
end

function Recruit.roll(tier, uid: string)
	local class = GameConfig.SoldierClasses[random:NextInteger(1, #GameConfig.SoldierClasses)]
	local first = GameConfig.FirstNames[random:NextInteger(1, #GameConfig.FirstNames)]
	local epithet = GameConfig.Epithets[random:NextInteger(1, #GameConfig.Epithets)]
	return {
		uid = uid,
		name = `{first} {epithet}`,
		class = class.id,
		rarity = rollRarity(tier),
		tier = tier.id,
		train = 0,
	}
end

return Recruit
