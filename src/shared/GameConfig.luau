-- Shared settings that both the server and the client read.
-- Every number here is a starting value meant to be tuned by play testing.

local GameConfig = {}

GameConfig.GameName = "Idle Kingdom"

---------------------------------------------------------------------------
-- Starting values and timers
---------------------------------------------------------------------------

GameConfig.StartingGold = 300
GameConfig.BaseMaxEnergy = 20
GameConfig.BaseMaxStamina = 5
GameConfig.BaseMaxHealth = 100
GameConfig.BaseAttack = 3
GameConfig.BaseDefense = 3
GameConfig.BaseHoldingSlots = 3

-- Seconds to regain one point.
GameConfig.EnergyRegenSeconds = 12
GameConfig.StaminaRegenSeconds = 20
GameConfig.HealthRegenSeconds = 5

GameConfig.SkillPointsPerLevel = 3

-- Doing a quest this many times earns one mastery rank. Each rank adds
-- MasteryGoldBonus to that quest's gold (0.1 means +10%).
GameConfig.MasteryPerRank = 25
GameConfig.MaxMasteryRanks = 3
GameConfig.MasteryGoldBonus = 0.1

-- Holdings: each level costs more, and offline they earn at a reduced rate.
GameConfig.HoldingCostGrowth = 1.25
GameConfig.HoldingMaxLevel = 50
GameConfig.OfflineRate = 0.5
GameConfig.OfflineMaxSeconds = 8 * 60 * 60

-- Foes: seconds before a beaten foe can be fought again, and the health
-- you need before you are allowed to attack.
GameConfig.FoeCooldownSeconds = 15 * 60
GameConfig.MinHealthToFight = 20

---------------------------------------------------------------------------
-- Skills: what one skill point buys
---------------------------------------------------------------------------

GameConfig.Skills = {
	{ id = "energy", name = "Max Energy", amount = 2, cost = 1, note = "+2 max energy" },
	{ id = "stamina", name = "Max Stamina", amount = 1, cost = 1, note = "+1 max stamina" },
	{ id = "health", name = "Max Health", amount = 10, cost = 1, note = "+10 max health" },
	{ id = "attack", name = "Attack", amount = 1, cost = 1, note = "+1 attack" },
	{ id = "defense", name = "Defense", amount = 1, cost = 1, note = "+1 defense" },
	{ id = "slots", name = "Holding Slots", amount = 1, cost = 3, note = "+1 holding you can own" },
}

---------------------------------------------------------------------------
-- Quests: spend energy, earn gold and experience
---------------------------------------------------------------------------

GameConfig.Quests = {
	{ id = "patrol", region = "Oakvale", name = "Patrol the Village Road", level = 1, energy = 1, gold = 40, xp = 2 },
	{ id = "chickens", region = "Oakvale", name = "Chase Off Chicken Thieves", level = 2, energy = 2, gold = 90, xp = 4 },
	{ id = "graincart", region = "Oakvale", name = "Guard the Grain Cart", level = 3, energy = 3, gold = 150, xp = 7 },
	{ id = "cellar", region = "Oakvale", name = "Clear Rats from the Cellar", level = 4, energy = 3, gold = 190, xp = 8 },
	{ id = "taxman", region = "Oakvale", name = "Escort the Tax Collector", level = 5, energy = 4, gold = 270, xp = 11 },
	{ id = "boar", region = "Oakvale", name = "Hunt the Marsh Boar", level = 6, energy = 5, gold = 370, xp = 14 },
	{ id = "fort", region = "Greywatch", name = "Scout the Border Fort", level = 8, energy = 6, gold = 520, xp = 18 },
	{ id = "caravan", region = "Greywatch", name = "Ambush a Smuggler Caravan", level = 10, energy = 7, gold = 700, xp = 23 },
	{ id = "blockade", region = "Greywatch", name = "Break the Toll Blockade", level = 12, energy = 8, gold = 920, xp = 28 },
	{ id = "hideout", region = "Greywatch", name = "Storm the Outlaw Hideout", level = 15, energy = 10, gold = 1400, xp = 38 },
}

---------------------------------------------------------------------------
-- Holdings: buy once, upgrade, earn gold every hour
---------------------------------------------------------------------------

GameConfig.Holdings = {
	{ id = "field", name = "Wheat Field", level = 1, cost = 400, income = 360 },
	{ id = "mill", name = "Water Mill", level = 3, cost = 1800, income = 1300 },
	{ id = "tavern", name = "Roadside Tavern", level = 6, cost = 7500, income = 4800 },
	{ id = "smithy", name = "Smithy", level = 10, cost = 28000, income = 16000 },
	{ id = "quarry", name = "Stone Quarry", level = 15, cost = 100000, income = 52000 },
	{ id = "market", name = "Market Hall", level = 20, cost = 380000, income = 180000 },
}

---------------------------------------------------------------------------
-- Rarity: every soldier and piece of gear rolls one of these.
-- chance is a weight (bigger means more common), stats multiplies the
-- item's attack and defense, and price multiplies its cost.
---------------------------------------------------------------------------

GameConfig.Rarities = {
	{ id = "Common", chance = 500, stats = 1, price = 1, color = Color3.fromRGB(190, 190, 185) },
	{ id = "Uncommon", chance = 280, stats = 1.4, price = 1.6, color = Color3.fromRGB(110, 200, 110) },
	{ id = "Rare", chance = 140, stats = 2, price = 3, color = Color3.fromRGB(90, 150, 240) },
	{ id = "Epic", chance = 60, stats = 3, price = 6, color = Color3.fromRGB(180, 100, 230) },
	{ id = "Legendary", chance = 18, stats = 4.5, price = 12, color = Color3.fromRGB(245, 165, 50) },
	{ id = "Mythic", chance = 2, stats = 7, price = 30, color = Color3.fromRGB(240, 70, 90) },
}

---------------------------------------------------------------------------
-- Market: restocks for everyone at the same moment
---------------------------------------------------------------------------

GameConfig.MarketRestockSeconds = 5 * 60
GameConfig.MarketSize = 8
GameConfig.MarketSoldierShare = 0.35 -- share of the stock that is soldiers
-- Item levels roll from the player's level plus or minus these amounts,
-- so some items are a goal to level up for.
GameConfig.MarketLevelBelow = 2
GameConfig.MarketLevelAbove = 3

-- Selling or releasing gives back this share of the price.
GameConfig.SellShare = 0.25
GameConfig.MaxGearOwned = 40

-- Stats and price grow with the item's level.
GameConfig.ItemStatGrowth = 0.15 -- +15% stats per level
GameConfig.ItemPriceGrowth = 1.18 -- x1.18 price per level

---------------------------------------------------------------------------
-- Warband: you always fight, plus one soldier per unlocked slot
---------------------------------------------------------------------------

GameConfig.MaxSoldierSlots = 10
GameConfig.SoldierSlotBaseCost = 2000
GameConfig.SoldierSlotCostGrowth = 2.5

-- Soldier classes. attack and defense are at item level 1, Common.
GameConfig.SoldierClasses = {
	{ id = "Militia", attack = 2, defense = 2, price = 400 },
	{ id = "Archer", attack = 4, defense = 1, price = 500 },
	{ id = "Knight", attack = 2, defense = 4, price = 550 },
	{ id = "Battle Mage", attack = 5, defense = 1, price = 650 },
}

---------------------------------------------------------------------------
-- Gear: one weapon, one armor and one mount for you and for each soldier.
-- The best pieces you own are used automatically.
---------------------------------------------------------------------------

GameConfig.GearSlots = { "Weapon", "Armor", "Mount" }

GameConfig.GearTypes = {
	Weapon = { attack = 2, defense = 0, price = 250, names = { "Sword", "Spear", "War Axe", "Mace", "Longbow", "Halberd" } },
	Armor = { attack = 0, defense = 2, price = 250, names = { "Jerkin", "Chainmail", "Brigandine", "Plate Harness", "Scale Mail" } },
	Mount = { attack = 1, defense = 1, price = 300, names = { "Mule", "Pony", "Warhorse", "Elk", "Griffin" } },
}

---------------------------------------------------------------------------
-- Foes: turn by turn fights that cost stamina
---------------------------------------------------------------------------

GameConfig.Foes = {
	{ id = "garrick", band = "Thornwood Bandits", name = "Garrick the Toll-Taker", level = 4, health = 60, attack = 8, defense = 2, gold = 3000, xp = 60, renown = 10 },
	{ id = "hilda", band = "Thornwood Bandits", name = "Mad Hilda", level = 8, health = 220, attack = 16, defense = 8, gold = 10000, xp = 160, renown = 20 },
	{ id = "aldous", band = "Thornwood Bandits", name = "Sir Aldous the Oathbreaker", level = 13, health = 600, attack = 28, defense = 18, gold = 32000, xp = 380, renown = 35 },
	{ id = "vex", band = "Thornwood Bandits", name = "Baron Vex", level = 18, health = 1500, attack = 46, defense = 32, gold = 100000, xp = 800, renown = 60 },
}

---------------------------------------------------------------------------
-- Formulas
---------------------------------------------------------------------------

-- Experience needed to go from `level` to the next one.
function GameConfig.getXpNeeded(level: number): number
	return math.floor(12 * level ^ 1.5 + 8)
end

function GameConfig.getMasteryRank(completions: number): number
	return math.min(GameConfig.MaxMasteryRanks, math.floor(completions / GameConfig.MasteryPerRank))
end

function GameConfig.getQuestGold(quest, completions: number): number
	local bonus = 1 + GameConfig.getMasteryRank(completions) * GameConfig.MasteryGoldBonus
	return math.floor(quest.gold * bonus)
end

-- Gold to buy a holding (level 0) or upgrade it from `level` to the next.
function GameConfig.getHoldingCost(holding, level: number): number
	return math.floor(holding.cost * GameConfig.HoldingCostGrowth ^ level)
end

-- Gold per hour for one holding at `level`.
function GameConfig.getHoldingIncome(holding, level: number): number
	return holding.income * level
end

function GameConfig.getRarity(id: string)
	for _, rarity in GameConfig.Rarities do
		if rarity.id == id then
			return rarity
		end
	end
	return GameConfig.Rarities[1]
end

-- Attack or defense for an item at `level` with the given rarity.
function GameConfig.getItemStat(base: number, level: number, rarity): number
	if base <= 0 then
		return 0
	end
	return math.max(1, math.floor(base * (1 + GameConfig.ItemStatGrowth * (level - 1)) * rarity.stats + 0.5))
end

function GameConfig.getItemPrice(base: number, level: number, rarity): number
	return math.floor(base * GameConfig.ItemPriceGrowth ^ (level - 1) * rarity.price)
end

-- Gold for the next soldier slot when you already have `slots` of them.
function GameConfig.getSlotCost(slots: number): number
	return math.floor(GameConfig.SoldierSlotBaseCost * GameConfig.SoldierSlotCostGrowth ^ slots)
end

return GameConfig
