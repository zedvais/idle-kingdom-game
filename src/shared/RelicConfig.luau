-- Relic Hall: give up spare gear for good, in return for lasting attack and
-- defense. Rarer pieces are worth more relic points.

local RelicConfig = {}

-- Relic points for one piece of each rarity. Set pieces count double.
RelicConfig.Points = {
	Common = 1,
	Uncommon = 2,
	Rare = 4,
	Epic = 8,
	Legendary = 16,
	Mythic = 32,
	Divine = 64,
}
RelicConfig.SetMultiplier = 2

-- Each point adds this much attack and defense (0.001 = +0.1%), up to the cap.
RelicConfig.BonusPerPoint = 0.001
RelicConfig.MaxBonus = 0.5

-- Milestones give a title for the Profile page.
RelicConfig.Milestones = {
	{ points = 100, title = "Collector" },
	{ points = 250, title = "Curator" },
	{ points = 500, title = "Keeper of Relics" },
}

function RelicConfig.getPoints(item): number
	local points = RelicConfig.Points[item.rarity] or 1
	if item.set then
		points *= RelicConfig.SetMultiplier
	end
	return points
end

function RelicConfig.getBonus(points: number): number
	return math.min(RelicConfig.MaxBonus, points * RelicConfig.BonusPerPoint)
end

return RelicConfig
