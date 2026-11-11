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
GameConfig.BaseLots = 4

-- Seconds to regain one point.
GameConfig.EnergyRegenSeconds = 12
GameConfig.StaminaRegenSeconds = 20
GameConfig.HealthRegenSeconds = 5

GameConfig.SkillPointsPerLevel = 3

-- Doing a quest this many times earns one mastery medal. Each medal adds
-- MasteryGoldBonus to that quest's gold (0.1 means +10%).
GameConfig.MasteryPerRank = 25
GameConfig.MasteryMedals = { "Bronze", "Silver", "Gold" }
GameConfig.MaxMasteryRanks = #GameConfig.MasteryMedals
GameConfig.MasteryGoldBonus = 0.1

-- Holdings: each copy you build costs more than the last. Offline they
-- earn at a reduced rate. Demolishing gives back part of the last price.
GameConfig.HoldingCostGrowth = 1.12
GameConfig.DemolishRefund = 0.5
GameConfig.OfflineRate = 0.5
GameConfig.OfflineMaxSeconds = 8 * 60 * 60

-- Bank: gold in the bank is safe from raids. Depositing costs a fee.
GameConfig.BankFee = 0.1

-- Foes: seconds before a beaten foe can be fought again, and the health
-- you need before you are allowed to attack.
GameConfig.FoeCooldownSeconds = 15 * 60
GameConfig.MinHealthToFight = 20

---------------------------------------------------------------------------
-- Skills: what one skill point buys
---------------------------------------------------------------------------

-- cost is skill points for the first purchase. With growth, each later
-- purchase of the same skill costs that many times more.
GameConfig.Skills = {
	{ id = "energy", name = "Max Energy", amount = 2, cost = 1, note = "+2 max energy" },
	{ id = "stamina", name = "Max Stamina", amount = 1, cost = 1, note = "+1 max stamina" },
	{ id = "health", name = "Max Health", amount = 10, cost = 1, note = "+10 max health" },
	{ id = "attack", name = "Attack", amount = 1, cost = 1, note = "+1 attack" },
	{ id = "defense", name = "Defense", amount = 1, cost = 1, note = "+1 defense" },
	{ id = "lots", name = "Holding Lots", amount = 1, cost = 2, growth = 1.5, note = "+1 lot to build a holding on" },
}

function GameConfig.getSkillCost(skill, bought: number): number
	return math.floor(skill.cost * (skill.growth or 1) ^ bought + 0.5)
end

---------------------------------------------------------------------------
-- Regions: quests and holdings are grouped by region, each opening at a level
---------------------------------------------------------------------------

GameConfig.Regions = {
	{ id = "Oakvale", level = 1 },
	{ id = "Greywatch", level = 8 },
	{ id = "Emberreach", level = 18 },
}

---------------------------------------------------------------------------
-- Quests: spend energy, earn gold and experience
---------------------------------------------------------------------------

-- drop is the chance (0 to 1) of finding a piece of gear.
GameConfig.Quests = {
	{ id = "patrol", region = "Oakvale", name = "Patrol the Village Road", level = 1, energy = 1, gold = 40, xp = 2, drop = 0.025 },
	{ id = "chickens", region = "Oakvale", name = "Chase Off Chicken Thieves", level = 2, energy = 2, gold = 90, xp = 4, drop = 0.025 },
	{ id = "graincart", region = "Oakvale", name = "Guard the Grain Cart", level = 3, energy = 3, gold = 150, xp = 7, drop = 0.03 },
	{ id = "cellar", region = "Oakvale", name = "Clear Rats from the Cellar", level = 4, energy = 3, gold = 190, xp = 8, drop = 0.03 },
	{ id = "taxman", region = "Oakvale", name = "Escort the Tax Collector", level = 5, energy = 4, gold = 270, xp = 11, drop = 0.035 },
	{ id = "boar", region = "Oakvale", name = "Hunt the Marsh Boar", level = 6, energy = 5, gold = 370, xp = 14, drop = 0.04 },
	{ id = "fort", region = "Greywatch", name = "Scout the Border Fort", level = 8, energy = 6, gold = 520, xp = 18, drop = 0.04 },
	{ id = "caravan", region = "Greywatch", name = "Ambush a Smuggler Caravan", level = 10, energy = 7, gold = 700, xp = 23, drop = 0.045 },
	{ id = "blockade", region = "Greywatch", name = "Break the Toll Blockade", level = 12, energy = 8, gold = 920, xp = 28, drop = 0.045 },
	{ id = "hideout", region = "Greywatch", name = "Storm the Outlaw Hideout", level = 15, energy = 10, gold = 1400, xp = 38, drop = 0.05 },
	{ id = "ferry", region = "Emberreach", name = "Seize the Ember Ferry", level = 18, energy = 11, gold = 2100, xp = 46, drop = 0.05 },
	{ id = "forge", region = "Emberreach", name = "Relight the Old Forge", level = 21, energy = 12, gold = 2900, xp = 55, drop = 0.055 },
	{ id = "ashwolves", region = "Emberreach", name = "Drive Out the Ash Wolves", level = 24, energy = 14, gold = 4000, xp = 66, drop = 0.06 },
	{ id = "cinderkeep", region = "Emberreach", name = "Lift the Siege of Cinderkeep", level = 28, energy = 16, gold = 5600, xp = 80, drop = 0.065 },
}

---------------------------------------------------------------------------
-- Holdings: each one built takes a lot and earns gold every hour. You can
-- build the same holding many times.
---------------------------------------------------------------------------

GameConfig.Holdings = {
	{ id = "field", region = "Oakvale", name = "Wheat Field", level = 1, cost = 400, income = 360 },
	{ id = "mill", region = "Oakvale", name = "Water Mill", level = 3, cost = 1800, income = 1300 },
	{ id = "tavern", region = "Oakvale", name = "Roadside Tavern", level = 5, cost = 7500, income = 4800 },
	{ id = "smithy", region = "Greywatch", name = "Smithy", level = 8, cost = 28000, income = 16000 },
	{ id = "quarry", region = "Greywatch", name = "Stone Quarry", level = 11, cost = 100000, income = 52000 },
	{ id = "tollbridge", region = "Greywatch", name = "Toll Bridge", level = 14, cost = 380000, income = 180000 },
	{ id = "markethall", region = "Emberreach", name = "Market Hall", level = 18, cost = 1400000, income = 600000 },
	{ id = "glassworks", region = "Emberreach", name = "Glassworks", level = 22, cost = 5000000, income = 2000000 },
	{ id = "mint", region = "Emberreach", name = "Royal Mint", level = 26, cost = 18000000, income = 6500000 },
}

---------------------------------------------------------------------------
-- Keep: your home. Each upgrade adds to income, attack and defense.
---------------------------------------------------------------------------

GameConfig.KeepLevels = {
	{ name = "Timber Hall", level = 1, cost = 0, bonus = 0 },
	{ name = "Palisade Fort", level = 3, cost = 5000, bonus = 0.05 },
	{ name = "Stone Tower", level = 6, cost = 40000, bonus = 0.1 },
	{ name = "Motte Castle", level = 10, cost = 250000, bonus = 0.16 },
	{ name = "Curtain-Wall Keep", level = 14, cost = 1500000, bonus = 0.23 },
	{ name = "Fortress of the Vale", level = 18, cost = 8000000, bonus = 0.31 },
	{ name = "Highcrown Citadel", level = 23, cost = 45000000, bonus = 0.4 },
	{ name = "Sunspire Palace", level = 28, cost = 250000000, bonus = 0.5 },
}

---------------------------------------------------------------------------
-- Daily playtime rewards: claimable after this many minutes played today
-- (days roll over at 00:00 UTC).
--   gold    = that many minutes of holding income (at least 500 x level)
--   energy / stamina = a full refill
--   chest   = a piece of gear of at least that rarity
--   xpBoost = double experience for that many minutes
---------------------------------------------------------------------------

GameConfig.PlaytimeRewards = {
	{ minutes = 5, kind = "gold", amount = 60, label = "Purse of Gold" },
	{ minutes = 15, kind = "energy", label = "Energy Refill" },
	{ minutes = 30, kind = "stamina", label = "Stamina Refill" },
	{ minutes = 60, kind = "chest", rarity = "Rare", label = "Rare Chest" },
	{ minutes = 90, kind = "xpBoost", amount = 30, label = "Double XP" },
	{ minutes = 120, kind = "chest", rarity = "Epic", label = "Epic Chest" },
	{ minutes = 180, kind = "gold", amount = 180, label = "Royal Purse" },
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
	-- Divine never appears in the Market. Only Royal recruits can roll it.
	{ id = "Divine", chance = 0, stats = 11, price = 80, color = Color3.fromRGB(255, 240, 150) },
}

---------------------------------------------------------------------------
-- Market: restocks for everyone at the same moment
---------------------------------------------------------------------------

GameConfig.MarketRestockSeconds = 5 * 60
GameConfig.MarketSize = 8
-- Item levels roll from the player's level plus or minus these amounts,
-- so some items are a goal to level up for.
GameConfig.MarketLevelBelow = 2
GameConfig.MarketLevelAbove = 3

-- Selling gear gives back this share of the price.
GameConfig.SellShare = 0.25
GameConfig.MaxGearOwned = 40

-- Stats and price grow with the item's level.
GameConfig.ItemStatGrowth = 0.15 -- +15% stats per level
GameConfig.ItemPriceGrowth = 1.18 -- x1.18 price per level

---------------------------------------------------------------------------
-- Warband: you always fight, plus one soldier per unlocked slot.
-- Soldiers are recruited by rolling. A roll costs gold, and the recruit
-- tier decides the odds of each rarity and how strong the soldier is.
---------------------------------------------------------------------------

GameConfig.MaxSoldierSlots = 20

-- Slot n (counting from 1) needs this level and gold to unlock.
-- Slot 1 is open from the start.
function GameConfig.getSlotLevel(slot: number): number
	return if slot <= 1 then 1 else (slot - 1) * 3
end

function GameConfig.getSlotCost(slot: number): number
	return if slot <= 1 then 0 else math.floor(1500 * 2.2 ^ (slot - 2))
end

-- Each soldier in the warband adds this much to your total attack and defense.
GameConfig.CrewSizeBonus = 0.02

-- chances are weights for each rarity, in the same order as GameConfig.Rarities.
GameConfig.RecruitTiers = {
	{ id = "Village", level = 1, cost = 500, power = 1, chances = { 600, 280, 90, 25, 4.5, 0.5, 0 } },
	{ id = "Mercenary", level = 10, cost = 50000, power = 7, chances = { 250, 350, 250, 110, 35, 5, 0 } },
	{ id = "Royal", level = 25, cost = 5000000, power = 45, chances = { 0, 150, 350, 300, 150, 48, 2 } },
}

-- Most rolls one auto-roll request may make, to keep the server fast.
GameConfig.MaxRollsPerRequest = 1000

-- Training adds this much to a soldier's stats per rank, and costs this
-- share of their recruit tier's roll cost, growing each rank.
GameConfig.TrainStatBonus = 0.08
GameConfig.TrainCostShare = 0.5
GameConfig.TrainCostGrowth = 1.6
GameConfig.MaxTrainRank = 20

-- Soldier classes. attack and defense are for a Common Village soldier.
GameConfig.SoldierClasses = {
	{ id = "Militia", attack = 3, defense = 3 },
	{ id = "Archer", attack = 5, defense = 1 },
	{ id = "Knight", attack = 2, defense = 5 },
	{ id = "Battle Mage", attack = 6, defense = 1 },
	{ id = "Ranger", attack = 4, defense = 3 },
}

GameConfig.FirstNames = {
	"Aldric", "Bertram", "Cedric", "Edwin", "Godfrey", "Hamlin", "Osric", "Roland", "Tobias", "Wystan",
	"Ada", "Brienne", "Elswyth", "Gwen", "Isolde", "Maud", "Rowena", "Sabine", "Thea", "Wren",
}
GameConfig.Epithets = {
	"the Bold", "Ironhand", "the Quiet", "Stormborn", "the Fox", "Oakheart", "the Grim", "Swiftbow",
	"the Unbroken", "Ashcloak", "Two-Blades", "the Wise", "Ravensong", "the Wall", "Brightshield",
}

function GameConfig.getRecruitTier(id: string)
	for _, tier in GameConfig.RecruitTiers do
		if tier.id == id then
			return tier
		end
	end
	return nil
end

function GameConfig.getRarityRank(id: string): number
	for index, rarity in GameConfig.Rarities do
		if rarity.id == id then
			return index
		end
	end
	return 1
end

-- Chance (0 to 1) that one roll in `tier` lands on `rarityId` or better.
function GameConfig.getChanceAtLeast(tier, rarityId: string): number
	local rank = GameConfig.getRarityRank(rarityId)
	local total, hit = 0, 0
	for index, weight in tier.chances do
		total += weight
		if index >= rank then
			hit += weight
		end
	end
	return if total > 0 then hit / total else 0
end

-- A soldier's own attack and defense, before gear and the crew size bonus.
function GameConfig.getSoldierStats(soldier): (number, number)
	local class = GameConfig.SoldierClasses[1]
	for _, candidate in GameConfig.SoldierClasses do
		if candidate.id == soldier.class then
			class = candidate
		end
	end
	local tier = GameConfig.getRecruitTier(soldier.tier) or GameConfig.RecruitTiers[1]
	local rarity = GameConfig.getRarity(soldier.rarity)
	local scale = rarity.stats * tier.power * (1 + GameConfig.TrainStatBonus * soldier.train)
	return math.floor(class.attack * scale + 0.5), math.floor(class.defense * scale + 0.5)
end

function GameConfig.getTrainCost(soldier): number
	local tier = GameConfig.getRecruitTier(soldier.tier) or GameConfig.RecruitTiers[1]
	return math.floor(tier.cost * GameConfig.TrainCostShare * GameConfig.TrainCostGrowth ^ soldier.train)
end

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

-- Gold to build one more copy of a holding when you already own `count`.
function GameConfig.getHoldingCost(holding, count: number): number
	return math.floor(holding.cost * GameConfig.HoldingCostGrowth ^ count)
end

function GameConfig.getRegion(id: string)
	for _, region in GameConfig.Regions do
		if region.id == id then
			return region
		end
	end
	return GameConfig.Regions[1]
end

-- Today's number, counting days since 1970 in UTC.
function GameConfig.getDay(): number
	return math.floor(os.time() / 86400)
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


return GameConfig
