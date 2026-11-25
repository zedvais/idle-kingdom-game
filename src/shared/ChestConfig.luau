-- Chests. Every chest waits in the Inventory until it is opened (Open 1 /
-- Open 10). A chest has its own item pool and its own rarity odds.
--
-- Two kinds:
--   * Rarity chests (id = a rarity, e.g. "Epic"): won from quests, foes, the
--     token shop and rewards. Chest pool items, that rarity or better, at
--     the Market's odds.
--   * Market chests: turn up at random in the rolling Market stock, for gold.
--   * Royal Coffers: bought in the Shop with Crowns (1, 5 or 10 at a time),
--     with Royal Coffer items, which have the best stats.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local ChestConfig = {}

-- Gold chests that can turn up in the rolling Market stock, in place of a
-- piece of gear. `weight` is how often each one appears among chest rows;
-- MarketChestChance is the chance that a Market row is a chest at all.
-- Prices are a number of Common Market items at the stock's level, so they
-- keep up as you level. odds = { { rarity, weight }, ... }.
ChestConfig.MarketChestChance = 0.12
ChestConfig.MarketChests = {
	{
		id = "sack",
		name = "Peddler's Sack",
		note = "Cheap and cheerful. Mostly plain Market gear.",
		pool = "market",
		goldItems = 2,
		weight = 60,
		odds = { { "Common", 60 }, { "Uncommon", 30 }, { "Rare", 9 }, { "Epic", 1 } },
		color = Color3.fromRGB(150, 120, 80),
	},
	{
		id = "strongbox",
		name = "Merchant's Strongbox",
		note = "Chest gear, never Common.",
		pool = "chest",
		goldItems = 14,
		weight = 30,
		odds = { { "Uncommon", 45 }, { "Rare", 38 }, { "Epic", 14 }, { "Legendary", 3 } },
		color = Color3.fromRGB(90, 140, 200),
	},
	{
		id = "warchest",
		name = "Quartermaster's War Chest",
		note = "Chest gear, Rare or better.",
		pool = "chest",
		goldItems = 45,
		weight = 10,
		odds = { { "Rare", 60 }, { "Epic", 30 }, { "Legendary", 9 }, { "Mythic", 1 } },
		color = Color3.fromRGB(170, 90, 200),
	},
}

-- Picks which gold chest a Market chest row holds.
function ChestConfig.rollMarketChest(random: Random)
	local total = 0
	for _, chest in ChestConfig.MarketChests do
		total += chest.weight
	end
	local roll = random:NextNumber(0, total)
	for _, chest in ChestConfig.MarketChests do
		roll -= chest.weight
		if roll <= 0 then
			return chest
		end
	end
	return ChestConfig.MarketChests[1]
end

local byId = {}
for _, chest in ChestConfig.MarketChests do
	chest.market = true
	byId[chest.id] = chest
end

-- Premium chests: the Royal Coffers from the Shop (Crowns). They go to
-- the Inventory too, and keep their pity counter when opened.
local StoreConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("StoreConfig"))
ChestConfig.PremiumChests = {}
for _, coffer in StoreConfig.Coffers do
	local chest = {
		id = coffer.key,
		name = coffer.name,
		note = `Royal gear, the strongest stats. {coffer.pityRarity} guaranteed within {coffer.pityEvery} opens.`,
		pool = "premium",
		odds = coffer.odds,
		color = Color3.fromRGB(230, 180, 60),
		coffer = coffer,
	}
	byId[chest.id] = chest
	table.insert(ChestConfig.PremiumChests, chest)
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

-- Every chest: rarity chests (rarest first), Royal Coffers, Market chests.
function ChestConfig.all()
	local list = {}
	for index = #GameConfig.Rarities, 1, -1 do
		local chest = byId[GameConfig.Rarities[index].id]
		if chest then
			table.insert(list, chest)
		end
	end
	for _, chest in ChestConfig.PremiumChests do
		table.insert(list, chest)
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
