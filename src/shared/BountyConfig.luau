-- The Bounty Board: daily and weekly tasks that pay Seals, a Seal shop,
-- and a 7 day login streak. Change numbers here.

local BountyConfig = {}

-- What the tasks count. The server adds to these as you play:
--   quests    quests completed (auto quests count)
--   foes      foe stages beaten
--   holdings  holdings built
--   rolls     warband recruit rolls
--   train     soldier training ranks bought
--   market    gear bought at the Market (auto-buy counts)
--   claims    daily playtime rewards claimed
BountyConfig.Stats = { "quests", "foes", "holdings", "rolls", "train", "market", "claims" }

-- Daily tasks start over at 00:00 UTC.
BountyConfig.Daily = {
	{ key = "d_quests", stat = "quests", goal = 60, seals = 3, name = "Complete 60 quests" },
	{ key = "d_foes", stat = "foes", goal = 3, seals = 3, name = "Beat 3 foe stages" },
	{ key = "d_holdings", stat = "holdings", goal = 2, seals = 2, name = "Build 2 holdings" },
	{ key = "d_rolls", stat = "rolls", goal = 10, seals = 2, name = "Make 10 recruit rolls" },
	{ key = "d_claims", stat = "claims", goal = 3, seals = 2, name = "Claim 3 playtime rewards" },
}

-- Weekly tasks start over on Monday 00:00 UTC.
BountyConfig.Weekly = {
	{ key = "w_quests", stat = "quests", goal = 1000, seals = 10, name = "Complete 1,000 quests" },
	{ key = "w_foes", stat = "foes", goal = 20, seals = 10, name = "Beat 20 foe stages" },
	{ key = "w_train", stat = "train", goal = 15, seals = 8, name = "Train soldiers 15 times" },
	{ key = "w_market", stat = "market", goal = 15, seals = 8, name = "Buy 15 pieces of gear at the Market" },
	{ key = "w_holdings", stat = "holdings", goal = 12, seals = 8, name = "Build 12 holdings" },
}

-- The Seal shop. limit = how many can be bought each week.
-- reward uses the same kinds as StoreConfig.
BountyConfig.Shop = {
	{ key = "income", name = "Steward's Ledger", cost = 3, limit = 5, reward = { kind = "gold", minutes = 30 } },
	{ key = "tokens", name = "Bounty of Tokens", cost = 6, limit = 3, reward = { kind = "tokens", amount = 10 } },
	{ key = "rare", name = "Rare Chest", cost = 5, limit = 4, reward = { kind = "chest", rarity = "Rare" } },
	{ key = "epic", name = "Epic Chest", cost = 14, limit = 2, reward = { kind = "chest", rarity = "Epic" } },
	{ key = "skill", name = "Tome of Insight", cost = 15, limit = 2, reward = { kind = "skill", amount = 1 } },
	{ key = "crowns", name = "Purse of Crowns", cost = 20, limit = 1, reward = { kind = "crowns", amount = 25 } },
}

-- Login streak: claim one reward per UTC day. Missing a whole day starts
-- the streak over at day 1. After day 7 it goes back to day 1.
BountyConfig.Streak = {
	{ kind = "gold", minutes = 60 },
	{ kind = "energy" },
	{ kind = "crowns", amount = 10 },
	{ kind = "chest", rarity = "Rare" },
	{ kind = "seals", amount = 5 },
	{ kind = "skill", amount = 1 },
	{ kind = "chest", rarity = "Epic" },
}

function BountyConfig.getShopItem(key: string)
	for _, item in BountyConfig.Shop do
		if item.key == key then
			return item
		end
	end
	return nil
end

-- Finds a task by key. Returns the task and "daily" or "weekly".
function BountyConfig.getTask(key: string)
	for _, task in BountyConfig.Daily do
		if task.key == key then
			return task, "daily"
		end
	end
	for _, task in BountyConfig.Weekly do
		if task.key == key then
			return task, "weekly"
		end
	end
	return nil, nil
end

return BountyConfig
