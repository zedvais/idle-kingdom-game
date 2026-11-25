-- Scholars' Hall: research that gives permanent bonuses. One research runs
-- at a time and takes real time; it keeps going while you are away.

local ResearchConfig = {}

-- bonus kinds the server understands:
--   income, questGold, xp, attack, defense   +amount per level (0.03 = +3%)
--   energy, health                           +amount max per level
--   lots                                     +amount holding lots per level
-- needs = { tech key, level } that must be reached first.
ResearchConfig.Branches = {
	{
		name = "Husbandry",
		techs = {
			{ key = "rotation", name = "Crop Rotation", bonus = "income", amount = 0.03, maxLevel = 10, cost = 2000, minutes = 2 },
			{ key = "trade", name = "Trade Routes", bonus = "questGold", amount = 0.03, maxLevel = 10, cost = 6000, minutes = 4, needs = { "rotation", 3 } },
			{ key = "surveying", name = "Land Surveying", bonus = "lots", amount = 1, maxLevel = 5, cost = 40000, minutes = 10, needs = { "trade", 4 } },
		},
	},
	{
		name = "Warcraft",
		techs = {
			{ key = "smithing", name = "Smithing", bonus = "attack", amount = 0.03, maxLevel = 10, cost = 3000, minutes = 2 },
			{ key = "masonry", name = "Masonry", bonus = "defense", amount = 0.03, maxLevel = 10, cost = 3000, minutes = 2 },
			{ key = "tactics", name = "Battle Tactics", bonus = "attack", amount = 0.05, maxLevel = 5, cost = 60000, minutes = 15, needs = { "smithing", 5 } },
		},
	},
	{
		name = "Provisions",
		techs = {
			{ key = "rations", name = "Field Rations", bonus = "energy", amount = 2, maxLevel = 10, cost = 2500, minutes = 3 },
			{ key = "medicine", name = "Field Medicine", bonus = "health", amount = 10, maxLevel = 10, cost = 2500, minutes = 3 },
		},
	},
	{
		name = "Lore",
		techs = {
			{ key = "scholarship", name = "Scholarship", bonus = "xp", amount = 0.03, maxLevel = 10, cost = 4000, minutes = 3 },
			{ key = "cartography", name = "Cartography", bonus = "questGold", amount = 0.04, maxLevel = 5, cost = 50000, minutes = 12, needs = { "scholarship", 5 } },
		},
	},
}

ResearchConfig.CostGrowth = 2.2 -- gold cost x2.2 per level
ResearchConfig.TimeGrowth = 1.6 -- research time x1.6 per level
ResearchConfig.CrownMinutes = 5 -- finishing early costs 1 Crown per 5 minutes left

ResearchConfig.Techs = {}
for _, branch in ResearchConfig.Branches do
	for _, tech in branch.techs do
		tech.branch = branch.name
		ResearchConfig.Techs[tech.key] = tech
	end
end

-- Gold to research the next level when the tech is at `level`.
function ResearchConfig.getCost(tech, level: number): number
	return math.floor(tech.cost * ResearchConfig.CostGrowth ^ level)
end

-- Seconds to research the next level when the tech is at `level`.
function ResearchConfig.getSeconds(tech, level: number): number
	return math.floor(tech.minutes * 60 * ResearchConfig.TimeGrowth ^ level)
end

function ResearchConfig.getFinishCost(secondsLeft: number): number
	return math.max(1, math.ceil(secondsLeft / 60 / ResearchConfig.CrownMinutes))
end

-- What one tech gives at a level, as words.
function ResearchConfig.describe(tech, level: number): string
	local total = tech.amount * level
	if tech.bonus == "energy" then
		return `+{total} max energy`
	elseif tech.bonus == "health" then
		return `+{total} max health`
	elseif tech.bonus == "lots" then
		return `+{total} holding lots`
	end
	local words = {
		income = "holding income",
		questGold = "quest gold",
		xp = "quest XP",
		attack = "attack",
		defense = "defense",
	}
	return `+{math.floor(total * 100 + 0.5)}% {words[tech.bonus] or tech.bonus}`
end

return ResearchConfig
