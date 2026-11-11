-- Rolls the Market's stock. Everyone's Market restocks at the same moment,
-- every GameConfig.MarketRestockSeconds, but each player gets their own
-- items, rolled around their level.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local Market = {}

-- Which restock window we are in right now. Changes every 5 minutes.
function Market.currentWindow(): number
	return math.floor(os.time() / GameConfig.MarketRestockSeconds)
end

function Market.secondsUntilRestock(): number
	return (Market.currentWindow() + 1) * GameConfig.MarketRestockSeconds - os.time()
end

local function rollRarity(random: Random)
	local total = 0
	for _, rarity in GameConfig.Rarities do
		total += rarity.chance
	end
	local roll = random:NextNumber(0, total)
	for _, rarity in GameConfig.Rarities do
		roll -= rarity.chance
		if roll <= 0 then
			return rarity
		end
	end
	return GameConfig.Rarities[1]
end

local function rollLevel(random: Random, playerLevel: number): number
	local low = math.max(1, playerLevel - GameConfig.MarketLevelBelow)
	local high = playerLevel + GameConfig.MarketLevelAbove
	return random:NextInteger(low, high)
end

local function rollSoldier(random: Random, playerLevel: number)
	local class = GameConfig.SoldierClasses[random:NextInteger(1, #GameConfig.SoldierClasses)]
	local rarity = rollRarity(random)
	local level = rollLevel(random, playerLevel)
	return {
		kind = "Soldier",
		slot = "Soldier",
		name = class.id,
		rarity = rarity.id,
		level = level,
		attack = GameConfig.getItemStat(class.attack, level, rarity),
		defense = GameConfig.getItemStat(class.defense, level, rarity),
		price = GameConfig.getItemPrice(class.price, level, rarity),
	}
end

local function rollGear(random: Random, playerLevel: number)
	local slot = GameConfig.GearSlots[random:NextInteger(1, #GameConfig.GearSlots)]
	local gearType = GameConfig.GearTypes[slot]
	local rarity = rollRarity(random)
	local level = rollLevel(random, playerLevel)
	return {
		kind = "Gear",
		slot = slot,
		name = gearType.names[random:NextInteger(1, #gearType.names)],
		rarity = rarity.id,
		level = level,
		attack = GameConfig.getItemStat(gearType.attack, level, rarity),
		defense = GameConfig.getItemStat(gearType.defense, level, rarity),
		price = GameConfig.getItemPrice(gearType.price, level, rarity),
	}
end

-- A fresh stock for one player. Seeded by player and window, so the same
-- player at the same level sees the same stock if they rejoin.
function Market.roll(userId: number, window: number, playerLevel: number)
	local random = Random.new(userId * 7919 + window * 104729 + playerLevel)
	local items = {}
	for _ = 1, GameConfig.MarketSize do
		local item
		if random:NextNumber() < GameConfig.MarketSoldierShare then
			item = rollSoldier(random, playerLevel)
		else
			item = rollGear(random, playerLevel)
		end
		item.sold = false
		table.insert(items, item)
	end

	-- Rarest first, then by level, so the best finds are at the top.
	local rank = {}
	for index, rarity in GameConfig.Rarities do
		rank[rarity.id] = index
	end
	table.sort(items, function(a, b)
		if rank[a.rarity] ~= rank[b.rarity] then
			return rank[a.rarity] > rank[b.rarity]
		end
		return a.level > b.level
	end)

	return { window = window, items = items }
end

return Market
