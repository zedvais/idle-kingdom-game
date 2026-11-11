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

-- Warband: you always fight, plus one soldier per unlocked slot.
GameConfig.MaxSoldierSlots = 10
GameConfig.SoldierSlotBaseCost = 2000
GameConfig.SoldierSlotCostGrowth = 2.5

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
-- Warband: soldiers you can hire into your slots
---------------------------------------------------------------------------

GameConfig.Soldiers = {
	{ id = "militia", name = "Militia", cost = 500, attack = 2, defense = 2 },
	{ id = "archer", name = "Archer", cost = 4000, attack = 6, defense = 3 },
	{ id = "knight", name = "Knight", cost = 30000, attack = 12, defense = 14 },
	{ id = "mage", name = "Battle Mage", cost = 200000, attack = 30, defense = 15 },
}

---------------------------------------------------------------------------
-- Armory: gear. You and each soldier use one weapon, one armor and one
-- mount, and the best pieces you own are used automatically.
---------------------------------------------------------------------------

GameConfig.Gear = {
	{ id = "rustysword", slot = "Weapon", name = "Rusty Sword", cost = 300, attack = 1, defense = 0 },
	{ id = "ironspear", slot = "Weapon", name = "Iron Spear", cost = 2500, attack = 3, defense = 0 },
	{ id = "longsword", slot = "Weapon", name = "Steel Longsword", cost = 15000, attack = 7, defense = 0 },
	{ id = "greataxe", slot = "Weapon", name = "Runed Greataxe", cost = 120000, attack = 16, defense = 0 },
	{ id = "jerkin", slot = "Armor", name = "Padded Jerkin", cost = 300, attack = 0, defense = 1 },
	{ id = "chainmail", slot = "Armor", name = "Chainmail", cost = 2500, attack = 0, defense = 3 },
	{ id = "plate", slot = "Armor", name = "Plate Harness", cost = 15000, attack = 0, defense = 7 },
	{ id = "wyrmscale", slot = "Armor", name = "Wyrmscale Mail", cost = 120000, attack = 0, defense = 16 },
	{ id = "mule", slot = "Mount", name = "Pack Mule", cost = 1000, attack = 1, defense = 1 },
	{ id = "warhorse", slot = "Mount", name = "Warhorse", cost = 12000, attack = 4, defense = 4 },
	{ id = "griffin", slot = "Mount", name = "Griffin", cost = 150000, attack = 11, defense = 11 },
}

GameConfig.GearSlots = { "Weapon", "Armor", "Mount" }

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

-- Gold for the next soldier slot when you already have `slots` of them.
function GameConfig.getSlotCost(slots: number): number
	return math.floor(GameConfig.SoldierSlotBaseCost * GameConfig.SoldierSlotCostGrowth ^ slots)
end

return GameConfig
