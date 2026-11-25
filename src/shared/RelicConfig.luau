-- Relic Hall (your collection): put gear on display for lasting flat
-- attack and defense. Copies of the same item (same name and rarity) count
-- together. The more copies of one item you hold, the higher its tier, and
-- each tier multiplies that item's bonus. Items can be taken back out.

local RelicConfig = {}

-- Flat attack and defense one item gives at tier 1, by rarity.
RelicConfig.RarityStat = {
	Common = 1,
	Uncommon = 2,
	Rare = 4,
	Epic = 8,
	Legendary = 16,
	Mythic = 32,
	Divine = 64,
}

-- Copies needed for each tier, and the bonus multiplier at that tier.
-- Example: 100 Epic Swords = tier 3 = 8 x 10 = +80 attack and +80 defense.
RelicConfig.Tiers = {
	{ copies = 1, multiplier = 1 },
	{ copies = 10, multiplier = 3 },
	{ copies = 100, multiplier = 10 },
	{ copies = 1000, multiplier = 25 },
	{ copies = 2500, multiplier = 50 },
	{ copies = 10000, multiplier = 120 },
}

-- Titles for the total number of pieces in the hall.
RelicConfig.Milestones = {
	{ pieces = 100, title = "Collector" },
	{ pieces = 1000, title = "Curator" },
	{ pieces = 10000, title = "Keeper of Relics" },
}

-- The collection key for an item: copies share a key.
function RelicConfig.getKey(item): string
	return `{item.name}|{item.rarity}`
end

-- Tier reached (0 when none) for this many copies.
function RelicConfig.getTier(copies: number): number
	local tier = 0
	for index, entry in RelicConfig.Tiers do
		if copies >= entry.copies then
			tier = index
		end
	end
	return tier
end

-- Flat attack and defense (the same number) one collected item gives.
function RelicConfig.getItemBonus(rarity: string, copies: number): number
	local tier = RelicConfig.getTier(copies)
	if tier == 0 then
		return 0
	end
	return (RelicConfig.RarityStat[rarity] or 1) * RelicConfig.Tiers[tier].multiplier
end

-- Total flat bonus of a whole collection ({ [key] = { rarity, count } }).
function RelicConfig.getTotalBonus(items): number
	local total = 0
	for _, entry in items do
		total += RelicConfig.getItemBonus(entry.rarity, entry.count)
	end
	return total
end

return RelicConfig
