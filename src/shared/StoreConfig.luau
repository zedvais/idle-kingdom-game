-- Everything sold for Robux or Crowns, and the Royal Pass.
-- Change prices and rewards here; the server and the menus both read it.
--
-- SETTING UP ROBUX ITEMS (after the game is published)
-- Every Robux item below has an `id` that is 0 for now. Roblox only gives
-- out ids once the game is published:
--   1. Open the game on create.roblox.com > Monetization.
--   2. Passes: make one pass per entry in StoreConfig.Passes, with the same
--      name and price. Copy its id into that entry's `id`.
--   3. Developer Products: make one product per entry in
--      StoreConfig.Products (Crown pouches, packs, Tithe Chest, Royal Pass
--      premium). Copy each id into the entry's `id`.
--   4. Rebuild the place file and publish again.
-- While an id is 0, pressing its button in Roblox Studio pretends the
-- purchase went through (nothing is charged), so every reward can be tested.
-- In a live server an id of 0 just says the item is not on sale yet.

local Format = require(script.Parent.Format)

local StoreConfig = {}

-- Crowns are the premium currency. Players buy them with Robux and spend
-- them in the Crown shop, on Royal Coffers, and on Royal Pass tiers.
StoreConfig.CurrencyName = "Crowns"

---------------------------------------------------------------------------
-- Rewards
---------------------------------------------------------------------------
-- One reward is a table with a kind:
--   crowns  amount = Crowns
--   gold    minutes = that many minutes of holding income (at least
--           GoldFloorPerLevel x level, so new players still get something)
--   chest   rarity = one piece of gear of at least that rarity
--   xpBoost minutes = double experience
--   skill   amount = skill points
--   tokens  amount = boss tokens
--   energy / stamina / health = a full refill
--   title   text = a title shown before your name

StoreConfig.GoldFloorPerLevel = 500

---------------------------------------------------------------------------
-- Game passes: bought once, kept forever
---------------------------------------------------------------------------

StoreConfig.Passes = {
	{
		key = "charter",
		id = 0,
		name = "Royal Charter",
		price = 399,
		note = "+25% holding income, +25% quest gold, +10% quest XP, and a gold name",
	},
	{
		key = "couriers",
		id = 0,
		name = "Swift Couriers",
		price = 249,
		note = "Energy, stamina and health refill twice as fast",
	},
	{
		key = "nightwatch",
		id = 0,
		name = "Night Watch",
		price = 199,
		note = "Holdings pay in full while you are away, for up to 24 hours (normally half, up to 8)",
	},
	{
		key = "treasury",
		id = 0,
		name = "Royal Treasury",
		price = 99,
		note = "No fee when you deposit gold in the Bank",
	},
	{
		key = "armory",
		id = 0,
		name = "Armory Wing",
		price = 149,
		note = "Your armory holds 80 pieces of gear instead of 40",
	},
	{
		key = "autoquest",
		id = 0,
		name = "Quest Herald",
		price = 249,
		note = "Auto quests: repeats your last quest whenever you have the energy",
	},
	{
		key = "autoroll",
		id = 0,
		name = "Recruiting Sergeant",
		price = 199,
		note = "Auto roll: keeps rolling recruits, slot after slot, until the rarity you pick turns up",
	},
	{
		key = "autobuy",
		id = 0,
		name = "Market Steward",
		price = 149,
		note = "Market auto-buy: buys gear that matches your rules every restock",
	},
}

-- What the passes do, used by the server.
StoreConfig.CharterIncome = 0.25
StoreConfig.CharterQuestGold = 0.25
StoreConfig.CharterXp = 0.1
StoreConfig.CouriersSpeed = 2
StoreConfig.NightWatchRate = 1
StoreConfig.NightWatchHours = 24
StoreConfig.ArmoryExtra = 40

---------------------------------------------------------------------------
-- Developer products: can be bought again and again (packs only once)
---------------------------------------------------------------------------
-- group says where the menu shows it:
--   crowns  a pouch of Crowns
--   pack    a one-time offer. once = true; hours = only for that many
--           hours after the player's first visit; level = from that level
--   tithe   breaks the Tithe Chest
--   pass    unlocks the premium track of the current Royal Pass season

StoreConfig.Products = {
	{ key = "crowns1", id = 0, group = "crowns", name = "Pouch of Crowns", price = 49, crowns = 80 },
	{ key = "crowns2", id = 0, group = "crowns", name = "Sack of Crowns", price = 249, crowns = 450, tag = "+12% bonus" },
	{ key = "crowns3", id = 0, group = "crowns", name = "Chest of Crowns", price = 499, crowns = 1000, tag = "+25% bonus" },
	{ key = "crowns4", id = 0, group = "crowns", name = "Vault of Crowns", price = 999, crowns = 2200, tag = "Best value" },
	{
		key = "squire",
		id = 0,
		group = "pack",
		name = "Squire's Bundle",
		price = 49,
		once = true,
		hours = 72,
		note = "Only for your first 3 days",
		rewards = {
			{ kind = "crowns", amount = 150 },
			{ kind = "chest", rarity = "Epic" },
			{ kind = "xpBoost", minutes = 120 },
		},
	},
	{
		key = "founder",
		id = 0,
		group = "pack",
		name = "Founder's Hoard",
		price = 299,
		once = true,
		note = "One per player, while the realm is young",
		rewards = {
			{ kind = "crowns", amount = 600 },
			{ kind = "chest", rarity = "Legendary" },
			{ kind = "skill", amount = 3 },
			{ kind = "title", text = "Founder" },
		},
	},
	{
		key = "lord",
		id = 0,
		group = "pack",
		name = "Lord's Treasury",
		price = 799,
		once = true,
		level = 20,
		note = "One per player, from level 20",
		rewards = {
			{ kind = "crowns", amount = 1500 },
			{ kind = "chest", rarity = "Mythic" },
			{ kind = "chest", rarity = "Legendary" },
			{ kind = "skill", amount = 5 },
		},
	},
	{ key = "tithe", id = 0, group = "tithe", name = "Break the Tithe Chest", price = 99 },
	{ key = "passPremium", id = 0, group = "pass", name = "Royal Pass: Noble track", price = 399 },
}

---------------------------------------------------------------------------
-- Tithe Chest: fills with Crowns as you play, break it for Robux
---------------------------------------------------------------------------

StoreConfig.TitheEnergyPerCrown = 40 -- quest energy spent for 1 Crown
StoreConfig.TitheCrownsPerFoe = 2 -- Crowns added for each foe stage beaten
StoreConfig.TitheMax = 250
StoreConfig.TitheMinToBreak = 60

---------------------------------------------------------------------------
-- Crown shop: spend Crowns
---------------------------------------------------------------------------

StoreConfig.CrownShop = {
	{ key = "health", name = "Healer's Visit", note = "Refill your health", cost = 5, reward = { kind = "health" } },
	{ key = "energy", name = "Royal Feast", note = "Refill your energy", cost = 10, reward = { kind = "energy" } },
	{ key = "stamina", name = "Battle Standard", note = "Refill your stamina", cost = 15, reward = { kind = "stamina" } },
	{
		key = "gold",
		name = "Tax Collection",
		note = "2 hours of holding income right now",
		cost = 25,
		reward = { kind = "gold", minutes = 120 },
	},
	{
		key = "xp",
		name = "Sage's Blessing",
		note = "Double experience for 60 minutes",
		cost = 40,
		reward = { kind = "xpBoost", minutes = 60 },
	},
	{ key = "skill", name = "Royal Tutor", note = "+1 skill point", cost = 80, reward = { kind = "skill", amount = 1 } },
}

---------------------------------------------------------------------------
-- Royal Coffers: random gear for Crowns. The odds are shown in the menu.
---------------------------------------------------------------------------
-- odds are percentages and must add up to 100.
-- pity: every `pityEvery` opens without a `pityRarity` (or better) piece,
-- the next one is guaranteed to be that rarity.

StoreConfig.Coffers = {
	{
		key = "coffer",
		name = "Royal Coffer",
		cost = 60,
		odds = { { "Rare", 62 }, { "Epic", 30 }, { "Legendary", 7 }, { "Mythic", 1 } },
		pityEvery = 20,
		pityRarity = "Legendary",
	},
	{
		key = "elite",
		name = "King's Coffer",
		cost = 180,
		odds = { { "Epic", 60 }, { "Legendary", 33 }, { "Mythic", 7 } },
		pityEvery = 25,
		pityRarity = "Mythic",
	},
}

---------------------------------------------------------------------------
-- Royal Pass: 50 tiers per 28 day season
---------------------------------------------------------------------------

-- Seasons and weeks count from Monday 23 November 2026, 00:00 UTC.
StoreConfig.SeasonStart = 1795392000
StoreConfig.SeasonDays = 28
StoreConfig.PassTiers = 50
StoreConfig.PointsPerTier = 200
StoreConfig.TierSkipCost = 120 -- Crowns to buy one tier

-- Where pass points come from.
StoreConfig.PointsPerQuestEnergy = 1 / 5 -- 1 point per 5 energy spent on quests
StoreConfig.PointsPerFoe = 15 -- each foe stage beaten
StoreConfig.PointsPerPlaytimeReward = 10 -- each daily playtime reward claimed

-- Weekly challenges. stat is what is counted this week.
StoreConfig.WeeklyChallenges = {
	{ key = "energy", stat = "energy", goal = 3000, points = 300, name = "Spend 3,000 energy on quests" },
	{ key = "foes", stat = "foes", goal = 25, points = 300, name = "Beat 25 foe stages" },
	{ key = "market", stat = "market", goal = 10, points = 300, name = "Buy 10 pieces of gear at the Market" },
	{ key = "play", stat = "play", goal = 3 * 60 * 60, points = 300, name = "Play for 3 hours" },
}

-- The rewards on each tier. Free is for everyone; Noble needs the premium
-- track. Most tiers follow a five step cycle; tiers 10, 20, 30, 40 and 50
-- have bigger rewards.
local FREE_CYCLE = {
	{ kind = "gold", minutes = 30 },
	{ kind = "crowns", amount = 10 },
	{ kind = "xpBoost", minutes = 20 },
	{ kind = "tokens", amount = 5 },
	{ kind = "chest", rarity = "Rare" },
}
local NOBLE_CYCLE = {
	{ kind = "crowns", amount = 25 },
	{ kind = "chest", rarity = "Epic" },
	{ kind = "skill", amount = 1 },
	{ kind = "gold", minutes = 60 },
	{ kind = "crowns", amount = 40 },
}
local MILESTONES = {
	[10] = { free = { kind = "chest", rarity = "Epic" }, noble = { kind = "chest", rarity = "Legendary" } },
	[20] = { free = { kind = "crowns", amount = 30 }, noble = { kind = "skill", amount = 3 } },
	[30] = { free = { kind = "chest", rarity = "Epic" }, noble = { kind = "chest", rarity = "Legendary" } },
	[40] = { free = { kind = "skill", amount = 2 }, noble = { kind = "crowns", amount = 150 } },
	[50] = { free = { kind = "chest", rarity = "Legendary" }, noble = { kind = "chest", rarity = "Mythic" } },
}

StoreConfig.PassRewards = {}
for tier = 1, StoreConfig.PassTiers do
	local milestone = MILESTONES[tier]
	local step = (tier - 1) % 5 + 1
	StoreConfig.PassRewards[tier] = {
		free = if milestone then milestone.free else FREE_CYCLE[step],
		noble = if milestone then milestone.noble else NOBLE_CYCLE[step],
	}
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local SECONDS_PER_DAY = 86400

-- Which season we are in (0 is the first).
function StoreConfig.getSeason(now: number): number
	return math.floor((now - StoreConfig.SeasonStart) / (StoreConfig.SeasonDays * SECONDS_PER_DAY))
end

function StoreConfig.getSeasonSecondsLeft(now: number): number
	local season = StoreConfig.getSeason(now)
	local ends = StoreConfig.SeasonStart + (season + 1) * StoreConfig.SeasonDays * SECONDS_PER_DAY
	return ends - now
end

-- Which week we are in, for weekly challenges (weeks start Monday 00:00 UTC).
function StoreConfig.getWeek(now: number): number
	return math.floor((now - StoreConfig.SeasonStart) / (7 * SECONDS_PER_DAY))
end

function StoreConfig.getWeekSecondsLeft(now: number): number
	local week = StoreConfig.getWeek(now)
	return StoreConfig.SeasonStart + (week + 1) * 7 * SECONDS_PER_DAY - now
end

-- Tier reached with this many points (0 to PassTiers).
function StoreConfig.getTier(points: number): number
	return math.min(StoreConfig.PassTiers, math.floor(points / StoreConfig.PointsPerTier))
end

local function findBy(list, key: string)
	for _, entry in list do
		if entry.key == key then
			return entry
		end
	end
	return nil
end

function StoreConfig.getPass(key: string)
	return findBy(StoreConfig.Passes, key)
end

function StoreConfig.getProduct(key: string)
	return findBy(StoreConfig.Products, key)
end

function StoreConfig.getCrownItem(key: string)
	return findBy(StoreConfig.CrownShop, key)
end

function StoreConfig.getCoffer(key: string)
	return findBy(StoreConfig.Coffers, key)
end

-- Short words for a reward, for the menus and messages.
function StoreConfig.describe(reward): string
	local kind = reward.kind
	if kind == "crowns" then
		return `{reward.amount} Crowns`
	elseif kind == "gold" and reward.amount then
		return `{Format.short(reward.amount)} gold`
	elseif kind == "gold" then
		local hours = reward.minutes / 60
		return if reward.minutes % 60 == 0 then `{hours}h of income` else `{reward.minutes}m of income`
	elseif kind == "chest" then
		return `{reward.rarity} chest`
	elseif kind == "xpBoost" then
		return `{reward.minutes}m double XP`
	elseif kind == "skill" then
		return if reward.amount == 1 then "1 skill point" else `{reward.amount} skill points`
	elseif kind == "tokens" then
		return `{reward.amount} boss tokens`
	elseif kind == "energy" or kind == "stamina" or kind == "health" then
		return `{kind} refill`
	elseif kind == "title" then
		return `"{reward.text}" title`
	elseif kind == "seals" then
		return `{reward.amount} Seals`
	end
	return "a reward"
end

function StoreConfig.describeList(rewards): string
	local parts = {}
	for _, reward in rewards do
		table.insert(parts, StoreConfig.describe(reward))
	end
	return table.concat(parts, ", ")
end

return StoreConfig
