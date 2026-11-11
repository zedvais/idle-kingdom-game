-- Shared settings that both the server and the client read.
-- Every number here comes from the game design doc and is meant to be tuned.

local GameConfig = {}

GameConfig.GameName = "Idle Kingdom"

-- Gold a brand new player starts with. Enough to build the Farm.
GameConfig.StartingGold = 15

-- Each building level costs this much more than the one before it.
GameConfig.UpgradeCostGrowth = 1.15

-- Income doubles each time a building reaches one of these levels.
GameConfig.MilestoneLevels = { 25, 50, 100 }

-- A steward costs this many times the building's build cost.
GameConfig.StewardCostMultiplier = 10

-- Without a steward a building holds this many seconds of gold, then stops.
GameConfig.StorageSeconds = 60

-- While the player is away, stewarded buildings earn at this share of their
-- normal rate, for at most this many seconds.
GameConfig.OfflineRate = 0.5
GameConfig.OfflineMaxSeconds = 2 * 60 * 60

-- Seconds a player waits before attacking again after a lost battle.
GameConfig.AttackCooldownSeconds = 30

-- requiresLands = how many lands must be conquered before it can be built.
GameConfig.Buildings = {
	{ id = "Farm", name = "Farm", cost = 15, income = 1, requiresLands = 0, color = Color3.fromRGB(214, 181, 92) },
	{ id = "LumberMill", name = "Lumber Mill", cost = 150, income = 8, requiresLands = 0, color = Color3.fromRGB(133, 94, 56) },
	{ id = "Blacksmith", name = "Blacksmith", cost = 1500, income = 60, requiresLands = 0, color = Color3.fromRGB(90, 90, 100) },
	{ id = "Tavern", name = "Tavern", cost = 15000, income = 450, requiresLands = 1, color = Color3.fromRGB(170, 85, 60) },
	{ id = "Mine", name = "Mine", cost = 200000, income = 4000, requiresLands = 2, color = Color3.fromRGB(70, 110, 140) },
	{ id = "Market", name = "Market", cost = 3000000, income = 40000, requiresLands = 3, color = Color3.fromRGB(150, 70, 150) },
}

GameConfig.Units = {
	{ id = "Militia", name = "Militia", cost = 100, power = 5, color = Color3.fromRGB(160, 140, 110) },
	{ id = "Archer", name = "Archer", cost = 1000, power = 40, color = Color3.fromRGB(80, 140, 80) },
	{ id = "Knight", name = "Knight", cost = 10000, power = 300, color = Color3.fromRGB(170, 170, 185) },
	{ id = "Mage", name = "Mage", cost = 100000, power = 2500, color = Color3.fromRGB(95, 80, 190) },
}

-- Lands are conquered in this order. bonus 0.25 means +25% gold forever.
GameConfig.Lands = {
	{ name = "Bandit Camp", power = 50, bonus = 0.25 },
	{ name = "Wolfwood", power = 500, bonus = 0.25 },
	{ name = "Rival Keep", power = 5000, bonus = 0.25 },
	{ name = "Frozen Pass", power = 50000, bonus = 0.5 },
	{ name = "Dragon's Roost", power = 500000, bonus = 1 },
}

-- Gold needed to go from `level` to `level + 1`. Level 0 means not built yet.
function GameConfig.getUpgradeCost(building, level: number): number
	return math.floor(building.cost * GameConfig.UpgradeCostGrowth ^ level)
end

function GameConfig.getStewardCost(building): number
	return building.cost * GameConfig.StewardCostMultiplier
end

-- Gold per second for one building, before the land bonus.
function GameConfig.getBaseIncome(building, level: number): number
	local income = building.income * level
	for _, milestone in GameConfig.MilestoneLevels do
		if level >= milestone then
			income *= 2
		end
	end
	return income
end

-- Gold multiplier from conquered lands. 1 means no bonus.
function GameConfig.getLandMultiplier(landsConquered: number): number
	local multiplier = 1
	for index, land in GameConfig.Lands do
		if index <= landsConquered then
			multiplier += land.bonus
		end
	end
	return multiplier
end

return GameConfig
