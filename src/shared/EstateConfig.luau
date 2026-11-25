-- Estate: resources, timed building upgrades, defenses and extra castles.
--
-- Four resources (lumber, stone, iron, grain) come from buildings in each
-- castle and pile up to a storage cap. Every castle has the same set of
-- buildings and its own builder, who works on one upgrade at a time. Upgrades
-- cost gold and resources and take time; Crowns finish them early.
-- Resources pay for building upgrades, Keep upgrades and troops.

local EstateConfig = {}

EstateConfig.Resources = {
	{ key = "lumber", name = "Lumber", color = "#C9A26B" },
	{ key = "stone", name = "Stone", color = "#B8B8B0" },
	{ key = "iron", name = "Iron", color = "#8FA7C4" },
	{ key = "grain", name = "Grain", color = "#E3C86A" },
}

-- What a new player starts with, and the storage everyone has before any
-- Storehouse or Granary.
EstateConfig.StartingStock = { lumber = 400, stone = 300, iron = 0, grain = 300 }
EstateConfig.BaseCap = 2000

-- Castles. The first is yours from the start; the others are bought once.
EstateConfig.Castles = {
	{ key = "home", name = "Oakvale Hall", level = 1 },
	{
		key = "greywatch",
		name = "Greywatch Outpost",
		level = 12,
		cost = { gold = 2000000, lumber = 15000, stone = 15000, iron = 4000 },
	},
	{
		key = "ember",
		name = "Emberreach Citadel",
		level = 25,
		cost = { gold = 150000000, lumber = 250000, stone = 250000, iron = 80000, grain = 40000 },
	},
}

-- Buildings in every castle.
--   kind "produce": makes `resource`, rate per hour at level L = rate x L x RateGrowth^(L-1)
--   kind "storage": raises the cap of `stores` by cap x (CapGrowth^L - 1)
--   kind "cellar":  keeps `percent` per level of your stock safe from raids (up to MaxCellar)
--   kind "defense": +`percent` defense per level (walls and towers also guard against raids)
-- cost is for going from level 0 to 1; each level after costs CostGrowth times more.
-- seconds is the build time to level 1; each level after takes TimeGrowth times longer.
EstateConfig.Buildings = {
	{ key = "lumbercamp", name = "Lumber Camp", kind = "produce", resource = "lumber", rate = 60, level = 1,
		cost = { gold = 400, lumber = 60, stone = 40 }, seconds = 20, note = "Cuts lumber every hour." },
	{ key = "quarry", name = "Quarry", kind = "produce", resource = "stone", rate = 50, level = 1,
		cost = { gold = 400, lumber = 80, stone = 20 }, seconds = 20, note = "Breaks stone every hour." },
	{ key = "farm", name = "Farm", kind = "produce", resource = "grain", rate = 60, level = 2,
		cost = { gold = 600, lumber = 100, stone = 60 }, seconds = 30, note = "Grows grain to feed troops." },
	{ key = "mine", name = "Iron Mine", kind = "produce", resource = "iron", rate = 25, level = 5,
		cost = { gold = 3000, lumber = 300, stone = 300 }, seconds = 60, note = "Digs iron for knights, rams and the Keep." },
	{ key = "storehouse", name = "Storehouse", kind = "storage", stores = { "lumber", "stone", "iron" }, cap = 3000, level = 1,
		cost = { gold = 800, lumber = 150, stone = 150 }, seconds = 40, note = "Holds more lumber, stone and iron." },
	{ key = "granary", name = "Granary", kind = "storage", stores = { "grain" }, cap = 3000, level = 2,
		cost = { gold = 800, lumber = 200, stone = 100 }, seconds = 40, note = "Holds more grain." },
	{ key = "cellar", name = "Hidden Cellar", kind = "cellar", percent = 0.03, level = 6,
		cost = { gold = 20000, lumber = 1500, stone = 2500 }, seconds = 120, note = "Hides part of your stock from raiders." },
	{ key = "walls", name = "Walls", kind = "defense", percent = 0.015, level = 4,
		cost = { gold = 8000, lumber = 500, stone = 1500 }, seconds = 90, note = "Stone walls: more defense, and they hold off raids." },
	{ key = "towers", name = "Archer Towers", kind = "defense", percent = 0.01, level = 8,
		cost = { gold = 30000, lumber = 2500, stone = 1500, iron = 400 }, seconds = 150, note = "Archers on the walls: more defense against every foe." },
}

EstateConfig.MaxLevel = 30
EstateConfig.RateGrowth = 1.1
EstateConfig.CapGrowth = 1.45
EstateConfig.CostGrowth = 1.55
EstateConfig.TimeGrowth = 1.4
EstateConfig.MaxBuildSeconds = 24 * 60 * 60
EstateConfig.MaxCellar = 0.5

local buildingByKey = {}
for _, building in EstateConfig.Buildings do
	buildingByKey[building.key] = building
end
local castleByKey = {}
for _, castle in EstateConfig.Castles do
	castleByKey[castle.key] = castle
end

function EstateConfig.getBuilding(key: string)
	return buildingByKey[key]
end

function EstateConfig.getCastle(key: string)
	return castleByKey[key]
end

-- Cost of the upgrade from `level` to `level + 1`: { gold, lumber, ... }.
function EstateConfig.getCost(building, level: number)
	local cost = {}
	for key, amount in building.cost do
		cost[key] = math.floor(amount * EstateConfig.CostGrowth ^ level)
	end
	return cost
end

function EstateConfig.getSeconds(building, level: number): number
	return math.min(EstateConfig.MaxBuildSeconds, math.floor(building.seconds * EstateConfig.TimeGrowth ^ level))
end

-- Resources per hour from one producing building at a level.
function EstateConfig.getRate(building, level: number): number
	if level <= 0 then
		return 0
	end
	return math.floor(building.rate * level * EstateConfig.RateGrowth ^ (level - 1))
end

-- Extra storage from one storage building at a level.
function EstateConfig.getCapBonus(building, level: number): number
	return math.floor(building.cap * (EstateConfig.CapGrowth ^ level - 1))
end

-- Everything the estate adds up to, from { [castle key] = { levels = { [building key] = level } } }:
-- rates[resource] per hour, caps[resource], cellar share, defense share.
function EstateConfig.summarize(castles)
	local rates, caps = {}, {}
	for _, resource in EstateConfig.Resources do
		rates[resource.key] = 0
		caps[resource.key] = EstateConfig.BaseCap
	end
	local cellar, defense = 0, 0
	for _, castle in castles do
		for key, level in castle.levels do
			local building = buildingByKey[key]
			if building and level > 0 then
				if building.kind == "produce" then
					rates[building.resource] += EstateConfig.getRate(building, level)
				elseif building.kind == "storage" then
					for _, stored in building.stores do
						caps[stored] += EstateConfig.getCapBonus(building, level)
					end
				elseif building.kind == "cellar" then
					cellar += building.percent * level
				elseif building.kind == "defense" then
					defense += building.percent * level
				end
			end
		end
	end
	return { rates = rates, caps = caps, cellar = math.min(EstateConfig.MaxCellar, cellar), defense = defense }
end

-- Words for a cost table, e.g. "1.2k gold, 300 lumber".
function EstateConfig.describeCost(cost, short): string
	local parts = {}
	if cost.gold and cost.gold > 0 then
		table.insert(parts, `{short(cost.gold)} gold`)
	end
	for _, resource in EstateConfig.Resources do
		local amount = cost[resource.key]
		if amount and amount > 0 then
			table.insert(parts, `{short(amount)} {string.lower(resource.name)}`)
		end
	end
	return if #parts > 0 then table.concat(parts, ", ") else "free"
end

-- True when `stock` (and `gold`) cover every part of `cost`.
function EstateConfig.canPay(cost, gold: number, stock): boolean
	if (cost.gold or 0) > gold then
		return false
	end
	for _, resource in EstateConfig.Resources do
		if (cost[resource.key] or 0) > (stock[resource.key] or 0) then
			return false
		end
	end
	return true
end

return EstateConfig
