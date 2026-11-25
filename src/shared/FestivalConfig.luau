-- Festival Week: a new festival every week (Monday 00:00 UTC). Each one
-- gives everyone a bonus, earns points from normal play, pays milestone
-- rewards, and ranks players on a leaderboard shared by every server.

local StoreConfig = require(script.Parent.StoreConfig)

local FestivalConfig = {}

-- bonus kinds the server understands:
--   income       holding income +amount
--   attack       attack +amount
--   rollCost     warband recruit rolls cost -amount
--   marketPrice  Market gear costs -amount
-- points: how many festival points each tracked action is worth (the
-- action names are the same as BountyConfig.Stats).
FestivalConfig.Festivals = {
	{
		key = "harvest",
		name = "Harvest Festival",
		bonusText = "+20% holding income",
		bonus = { kind = "income", amount = 0.2 },
		points = { holdings = 15, quests = 1, claims = 10 },
	},
	{
		key = "tournament",
		name = "Grand Tournament",
		bonusText = "+15% attack",
		bonus = { kind = "attack", amount = 0.15 },
		points = { foes = 25, train = 10, quests = 1 },
	},
	{
		key = "muster",
		name = "Muster Fair",
		bonusText = "Recruit rolls cost 20% less",
		bonus = { kind = "rollCost", amount = 0.2 },
		points = { rolls = 2, train = 8, quests = 1 },
	},
	{
		key = "merchants",
		name = "Merchants' Fair",
		bonusText = "Market gear costs 15% less",
		bonus = { kind = "marketPrice", amount = 0.15 },
		points = { market = 12, holdings = 8, quests = 1 },
	},
}

-- Rewards for reaching these points this week (claimed on the Festival page).
FestivalConfig.Milestones = {
	{ points = 250, reward = { kind = "gold", minutes = 120 } },
	{ points = 750, reward = { kind = "chest", rarity = "Epic" } },
	{ points = 1500, reward = { kind = "crowns", amount = 20 } },
	{ points = 3000, reward = { kind = "chest", rarity = "Legendary" } },
}

-- Paid the week after, by final rank. Players outside the top 100 with at
-- least MinPointsForReward get the last entry.
FestivalConfig.RankRewards = {
	{ best = 1, worst = 1, label = "1st", rewards = { { kind = "chest", rarity = "Mythic" }, { kind = "crowns", amount = 100 } } },
	{ best = 2, worst = 3, label = "2nd-3rd", rewards = { { kind = "chest", rarity = "Legendary" }, { kind = "crowns", amount = 50 } } },
	{ best = 4, worst = 10, label = "4th-10th", rewards = { { kind = "chest", rarity = "Epic" }, { kind = "crowns", amount = 25 } } },
	{ best = 11, worst = 100, label = "11th-100th", rewards = { { kind = "chest", rarity = "Rare" }, { kind = "crowns", amount = 10 } } },
	{ best = 101, worst = math.huge, label = "Everyone else", rewards = { { kind = "crowns", amount = 5 } } },
}
FestivalConfig.MinPointsForReward = 250
FestivalConfig.LeaderboardSize = 10 -- rows shown on the page

-- This week's festival.
function FestivalConfig.getWeek(now: number): number
	return StoreConfig.getWeek(now)
end

function FestivalConfig.getFestival(week: number)
	local count = #FestivalConfig.Festivals
	return FestivalConfig.Festivals[(week % count) + 1]
end

function FestivalConfig.getRankReward(rank: number?)
	for _, entry in FestivalConfig.RankRewards do
		if rank and rank >= entry.best and rank <= entry.worst then
			return entry
		end
	end
	return FestivalConfig.RankRewards[#FestivalConfig.RankRewards]
end

return FestivalConfig
