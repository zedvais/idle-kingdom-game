-- Rolls the Market's gear stock. Everyone's Market restocks at the same moment,
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

-- Picks a rarity by Market odds, never below `minRank` (1 = Common).
local function rollRarity(random: Random, minRank: number)
	local total = 0
	for index, rarity in GameConfig.Rarities do
		if index >= minRank then
			total += rarity.chance
		end
	end
	local roll = random:NextNumber(0, total)
	for index, rarity in GameConfig.Rarities do
		if index >= minRank and rarity.chance > 0 then
			roll -= rarity.chance
			if roll <= 0 then
				return rarity
			end
		end
	end
	return GameConfig.Rarities[minRank]
end

local function rollLevel(random: Random, playerLevel: number): number
	local low = math.max(1, playerLevel - GameConfig.MarketLevelBelow)
	local high = playerLevel + GameConfig.MarketLevelAbove
	return random:NextInteger(low, high)
end

-- One piece of gear rolled around `playerLevel`. Also used for quest drops
-- and chests, which pass a minimum rarity.
-- `pool` picks the item list: "market" (default), "chest" or "premium".
function Market.rollGear(random: Random, playerLevel: number, minRank: number?, pool: string?)
	local slot = GameConfig.GearSlots[random:NextInteger(1, #GameConfig.GearSlots)]
	local gearType = GameConfig.GearTypes[slot]
	local names = GameConfig.GearPools[pool or "market"].items[slot].names
	local rarity = rollRarity(random, minRank or 1)
	-- The level only sets the price (Market prices follow the player's
	-- level); stats are fixed by name and rarity.
	local level = rollLevel(random, playerLevel)
	local name = names[random:NextInteger(1, #names)]
	local attack, defense = GameConfig.getGearStats(slot, name, rarity)
	return {
		kind = "Gear",
		slot = slot,
		name = name,
		rarity = rarity.id,
		level = level,
		attack = attack,
		defense = defense,
		price = GameConfig.getItemPrice(gearType.price, level, rarity),
	}
end

-- One piece of gear of exactly this rarity from a pool (Royal Coffers use
-- the premium pool; chests pass their own).
function Market.rollGearOfRarity(random: Random, playerLevel: number, rarityId: string, pool: string?)
	local item = Market.rollGear(random, playerLevel, 1, pool or "premium")
	local rarity = GameConfig.getRarity(rarityId)
	local gearType = GameConfig.GearTypes[item.slot]
	item.rarity = rarity.id
	item.attack, item.defense = GameConfig.getGearStats(item.slot, item.name, rarity)
	item.price = GameConfig.getItemPrice(gearType.price, item.level, rarity)
	return item
end

-- One piece of a gear set (foe drops). The slot is random; the name comes
-- from the set.
function Market.rollSetPiece(random: Random, playerLevel: number, set, minRank: number)
	local item = Market.rollGear(random, playerLevel, minRank)
	item.name = set.pieces[item.slot]
	item.set = set.id
	item.attack, item.defense = GameConfig.getGearStats(item.slot, item.name, item.rarity)
	return item
end

-- A fresh stock for one player. Seeded by player and window, so the same
-- player at the same level sees the same stock if they rejoin.
function Market.roll(userId: number, window: number, playerLevel: number)
	local random = Random.new(userId * 7919 + window * 104729 + playerLevel)
	local items = {}
	for _ = 1, GameConfig.MarketSize do
		local item = Market.rollGear(random, playerLevel)
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
