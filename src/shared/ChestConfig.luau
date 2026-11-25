-- Chests. Every chest waits in the Inventory until it is opened (Open 1 /
-- Open 10). A chest has its own item pool and its own rarity odds.
--
-- Two kinds:
--   * Rarity chests (id = a rarity, e.g. "Epic"): won from quests, foes, the
--     token shop and rewards. Chest pool items, that rarity or better, at
--     the Market's odds.
--   * Market chests: bought in the Market, with gold (cheap, plain items) or
--     with Crowns (Royal Coffer items, which have the best stats).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local ChestConfig = {}

-- Sold in the Market, in this order. `gold` prices are a number of Common
-- Market items at the player's level (so they keep up as you level);
-- `crowns` prices are flat. odds = { { rarity, weight }, ... }.
ChestConfig.MarketChests = {
	{
		id = "sack",
		name = "Peddler's Sack",
		note = "Cheap and cheerful. Mostly plain Market gear.",
		pool = "market",
		goldItems = 2,
		odds = { { "Common", 60 }, { "Uncommon", 30 }, { "Rare", 9 }, { "Epic", 1 } },
		color = Color3.fromRGB(150, 120, 80),
	},
	{
		id = "strongbox",
		name = "Merchant's Strongbox",
		note = "Chest gear, never Common.",
		pool = "chest",
		goldItems = 14,
		odds = { { "Uncommon", 45 }, { "Rare", 38 }, { "Epic", 14 }, { "Legendary", 3 } },
		color = Color3.fromRGB(90, 140, 200),
	},
	{
		id = "crowncask",
		name = "Crown Cask",
		note = "Royal gear with the strongest stats. Rare or better.",
		pool = "premium",
		crowns = 40,
		odds = { { "Rare", 58 }, { "Epic", 32 }, { "Legendary", 9 }, { "Mythic", 1 } },
		color = Color3.fromRGB(230, 180, 60),
	},
	{
		id = "dragonhoard",
		name = "Dragon Hoard",
		note = "Royal gear, Epic or better, with a real shot at Mythic.",
		pool = "premium",
		crowns = 160,
		odds = { { "Epic", 62 }, { "Legendary", 31 }, { "Mythic", 7 } },
		color = Color3.fromRGB(220, 70, 60),
	},
}

local byId = {}
for _, chest in ChestConfig.MarketChests do
	chest.market = true
	byId[chest.id] = chest
end

-- Rarity chests, built from the rarities (Divine is recruits only).
for index, rarity in GameConfig.Rarities do
	if rarity.chance > 0 then
		local odds = {}
		for other = index, #GameConfig.Rarities do
			local r = GameConfig.Rarities[other]
			if r.chance > 0 then
				table.insert(odds, { r.id, r.chance })
			end
		end
		byId[rarity.id] = {
			id = rarity.id,
			name = `{rarity.id} Chest`,
			note = `Chest gear, {rarity.id} or better.`,
			pool = "chest",
			odds = odds,
			color = rarity.color,
			rarity = rarity.id,
		}
	end
end

function ChestConfig.get(id: string)
	return byId[id]
end

-- Every chest, rarest rarity chests first, then the Market chests.
function ChestConfig.all()
	local list = {}
	for index = #GameConfig.Rarities, 1, -1 do
		local chest = byId[GameConfig.Rarities[index].id]
		if chest then
			table.insert(list, chest)
		end
	end
	for _, chest in ChestConfig.MarketChests do
		table.insert(list, chest)
	end
	return list
end

-- The rarity a chest shows (its lowest possible rarity), for colors and art.
function ChestConfig.rarityOf(chest): string
	return chest.rarity or chest.odds[1][1]
end

-- Gold price of a gold chest at a player level.
function ChestConfig.goldPrice(chest, level: number): number
	local common = GameConfig.getItemPrice(GameConfig.GearTypes.Weapon.price, level, GameConfig.Rarities[1])
	return math.floor(common * (chest.goldItems or 0))
end

-- Picks a rarity by the chest's odds.
function ChestConfig.rollRarity(chest, random: Random): string
	local total = 0
	for _, pair in chest.odds do
		total += pair[2]
	end
	local roll = random:NextNumber(0, total)
	for _, pair in chest.odds do
		roll -= pair[2]
		if roll <= 0 then
			return pair[1]
		end
	end
	return chest.odds[#chest.odds][1]
end

-- Everything the chest can give with the chance of each, best odds first,
-- and the chance of each rarity.
function ChestConfig.dropTable(chest)
	local total = 0
	for _, pair in chest.odds do
		total += pair[2]
	end
	local rows, byRarity = {}, {}
	local pool = GameConfig.GearPools[chest.pool]
	if total <= 0 or not pool then
		return rows, byRarity
	end
	for _, pair in chest.odds do
		local rarity = GameConfig.getRarity(pair[1])
		local rarityChance = pair[2] / total
		table.insert(byRarity, { rarity = rarity, chance = rarityChance })
		for _, slot in GameConfig.GearSlots do
			local names = pool.items[slot].names
			for _, name in names do
				table.insert(rows, {
					slot = slot,
					name = name,
					rarity = rarity.id,
					chance = rarityChance / #GameConfig.GearSlots / #names,
				})
			end
		end
	end
	table.sort(rows, function(a, b)
		if a.chance ~= b.chance then
			return a.chance > b.chance
		end
		return a.name < b.name
	end)
	return rows, byRarity
end

return ChestConfig
