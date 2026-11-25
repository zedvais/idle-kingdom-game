-- Barracks troops, expeditions and battle reports (the War Chronicle).
--
-- Troops are trained in the Barracks and sent out on expeditions. Each
-- troop type is strong against one kind of enemy, so the mix you train
-- matters. Your whole army marches on an expedition and comes back when it
-- ends, minus anyone lost in the fighting.

local ArmyConfig = {}

-- strong = the enemy kind this troop hits harder (x CounterBonus).
-- resources = what each troop costs from the Estate, on top of gold.
-- siege only works well against forts; against anything else it hits at
-- SiegeOpenField.
ArmyConfig.Troops = {
	{ key = "spear", name = "Spearmen", level = 1, cost = 200, seconds = 6, attack = 4, defense = 6, strong = "cavalry", resources = { grain = 3 }, note = "Strong against cavalry" },
	{ key = "archer", name = "Archers", level = 1, cost = 260, seconds = 8, attack = 6, defense = 3, strong = "spear", resources = { grain = 3, lumber = 2 }, note = "Strong against spearmen" },
	{ key = "cavalry", name = "Cavalry", level = 5, cost = 450, seconds = 14, attack = 9, defense = 5, strong = "archer", resources = { grain = 6 }, note = "Strong against archers" },
	{ key = "knight", name = "Knights", level = 15, cost = 1200, seconds = 30, attack = 16, defense = 14, resources = { grain = 8, iron = 4 }, note = "Tough all-rounders" },
	{ key = "siege", name = "Siege Rams", level = 25, cost = 2500, seconds = 60, attack = 30, defense = 4, strong = "fort", resources = { lumber = 40, iron = 10 }, note = "Breaks forts, weak in the open" },
}
ArmyConfig.CounterBonus = 1.5
ArmyConfig.SiegeOpenField = 0.5

-- Words for each enemy kind.
ArmyConfig.EnemyNames = {
	spear = "spearmen",
	archer = "archers",
	cavalry = "riders",
	mixed = "a mixed host",
	fort = "a fort",
}

-- How many troops you can have, at home and away: Base + PerKeep x Keep level.
ArmyConfig.BaseCap = 30
ArmyConfig.CapPerKeep = 20

-- Expeditions. power = the enemy's strength; your attack power must beat
-- it. Rewards: `goldMinutes` of holding income (with the usual floor),
-- `plunder` resources (up to your storage),
-- boss tokens, and a chance of a gear chest and of Crowns.
ArmyConfig.Expeditions = {
	{
		key = "woods",
		name = "Wolf-haunted Woods",
		level = 3,
		minutes = 10,
		enemy = "cavalry",
		power = 60,
		goldMinutes = 20,
		plunder = { lumber = 600, grain = 300 },
		tokens = 2,
		chest = "Common",
		chestChance = 0.3,
	},
	{
		key = "mill",
		name = "The Bandit Mill",
		level = 6,
		minutes = 20,
		enemy = "spear",
		power = 200,
		goldMinutes = 40,
		plunder = { grain = 1500, lumber = 1000 },
		tokens = 4,
		chest = "Uncommon",
		chestChance = 0.35,
	},
	{
		key = "crossing",
		name = "Raider Crossing",
		level = 10,
		minutes = 30,
		enemy = "archer",
		power = 600,
		goldMinutes = 60,
		plunder = { stone = 3000, iron = 600 },
		tokens = 6,
		chest = "Rare",
		chestChance = 0.35,
	},
	{
		key = "watchfort",
		name = "The Ruined Watchfort",
		level = 15,
		minutes = 60,
		enemy = "fort",
		power = 1800,
		goldMinutes = 100,
		plunder = { stone = 8000, iron = 2000 },
		tokens = 10,
		chest = "Epic",
		chestChance = 0.4,
		crowns = 5,
		crownChance = 0.25,
	},
	{
		key = "barrow",
		name = "Barrow of the Old Kings",
		level = 25,
		minutes = 90,
		enemy = "mixed",
		power = 6000,
		goldMinutes = 150,
		plunder = { iron = 8000, stone = 15000 },
		tokens = 16,
		chest = "Legendary",
		chestChance = 0.4,
		crowns = 10,
		crownChance = 0.3,
	},
	{
		key = "citadel",
		name = "The Hollow Citadel",
		level = 40,
		minutes = 120,
		enemy = "fort",
		power = 20000,
		goldMinutes = 200,
		plunder = { iron = 25000, stone = 40000, lumber = 40000 },
		tokens = 25,
		chest = "Mythic",
		chestChance = 0.35,
		crowns = 15,
		crownChance = 0.35,
	},
}

-- Battles last up to this many rounds. The enemy has power x EnemyHealth
-- health; you deal your attack power each round. Each round the enemy hits
-- back for power x EnemyHit, against your health of defense power x
-- ArmyHealth. Troops are lost in proportion to the health you lose.
ArmyConfig.Rounds = 3
ArmyConfig.EnemyHealth = 3
ArmyConfig.EnemyHit = 0.25
ArmyConfig.ArmyHealth = 3

-- Reports kept in the War Chronicle.
ArmyConfig.ChronicleKept = 20

local troopByKey = {}
for _, troop in ArmyConfig.Troops do
	troopByKey[troop.key] = troop
end
local expeditionByKey = {}
for _, expedition in ArmyConfig.Expeditions do
	expeditionByKey[expedition.key] = expedition
end

function ArmyConfig.getTroop(key: string)
	return troopByKey[key]
end

function ArmyConfig.getExpedition(key: string)
	return expeditionByKey[key]
end

function ArmyConfig.getCap(keepLevel: number): number
	return ArmyConfig.BaseCap + ArmyConfig.CapPerKeep * keepLevel
end

-- How hard one troop type hits an enemy kind.
function ArmyConfig.getMultiplier(troop, enemy: string): number
	if troop.strong == enemy then
		return ArmyConfig.CounterBonus
	end
	if troop.key == "siege" then
		return ArmyConfig.SiegeOpenField
	end
	return 1
end

-- Attack and defense power of an army ({ [troop key] = count }) against an
-- enemy kind.
function ArmyConfig.getPower(troops, enemy: string): (number, number)
	local attack, defense = 0, 0
	for key, count in troops do
		local troop = troopByKey[key]
		if troop and count > 0 then
			attack += count * troop.attack * ArmyConfig.getMultiplier(troop, enemy)
			defense += count * troop.defense
		end
	end
	return math.floor(attack), math.floor(defense)
end

function ArmyConfig.countTroops(troops): number
	local total = 0
	for _, count in troops do
		total += count
	end
	return total
end

return ArmyConfig
