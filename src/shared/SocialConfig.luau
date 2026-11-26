-- Playing with other players: raids, guilds and the realm map.
--
-- Raids: attack another player's keep (they may be offline or on another
-- server). Your attack roll against their defense roll; win and you take
-- part of their gold on hand and unprotected resources. Gold in the Bank
-- is always safe, and the Hidden Cellar keeps part of the resources safe.
-- Every raid also wounds the defender. Under GameConfig.MinHealthToFight
-- (20) health they are incapacitated: they can not be raided, and they can
-- not attack anyone either, until their health recovers.
--
-- Guilds: up to MaxMembers players. Members donate gold for guild
-- experience; guild levels give every member bonuses.
--
-- Realm map: each week guilds siege the realm's territories. The guild
-- with the most siege points on a territory at the end of the week holds
-- it the next week, and its members get that territory's bonus.

local SocialConfig = {}

---------------------------------------------------------------------------
-- Raids
---------------------------------------------------------------------------

SocialConfig.RaidMinLevel = 5 -- you can raid and be raided from this level
SocialConfig.RaidLevelRange = 6 -- targets are within this many levels of you
SocialConfig.RaidStamina = 1 -- stamina per raid
SocialConfig.RaidTargets = 6 -- targets shown at once
SocialConfig.RaidRefreshSeconds = 30 -- how often you can look for new targets
SocialConfig.WinDamage = { 0.2, 0.35 } -- share of the defender's max health a won raid takes
SocialConfig.LossDamage = { 0.05, 0.1 } -- share a failed raid still takes
SocialConfig.StealGold = 0.1 -- share of gold on hand taken by a win
SocialConfig.StealResources = 0.08 -- share of unprotected resources taken
SocialConfig.WinHealthCost = 0.05 -- share of your max health a win costs
SocialConfig.LossHealthCost = 0.2 -- share of your max health a loss costs
SocialConfig.WinRenown = 3
SocialConfig.RollMin = 0.8 -- attack and defense each roll between these
SocialConfig.RollMax = 1.2
SocialConfig.AttackersKept = 10 -- recent attackers you can take revenge on
SocialConfig.ProfileSeconds = 60 -- how often your defense profile is published

-- Computer-run keeps fill the target list when few players are near your
-- level. Their defense is about their level's expected power.
SocialConfig.NpcNames = {
	"Bandit Stockade", "Lord Mortimer's Manor", "The Saltmarsh Toll", "Abbot Fenwick's Granary",
	"Raider Camp", "Sir Hugo's Tower", "The Widow's Mill", "Smugglers' Cove", "Old Barrow Fort",
	"Count Ravel's Lodge", "The Black Hen Inn", "Thornfield Hall",
}
SocialConfig.NpcGoldMinutes = 20 -- an NPC keep holds this many minutes of your income

-- Expected attack and defense at a level (same curve as the foe stages).
function SocialConfig.expectedPower(level: number): number
	return 10 + 4.5 * level ^ 1.55
end

---------------------------------------------------------------------------
-- Guilds
---------------------------------------------------------------------------

SocialConfig.GuildMinLevel = 8 -- to create a guild
SocialConfig.GuildCost = 50000 -- gold to create a guild
SocialConfig.GuildNameMin = 3
SocialConfig.GuildNameMax = 20
SocialConfig.GuildTagMin = 2
SocialConfig.GuildTagMax = 4
SocialConfig.WallKept = 30 -- messages kept on the guild wall
SocialConfig.WallMax = 120 -- characters per message
SocialConfig.WallSeconds = 10 -- between your posts
SocialConfig.DonateXpPer = 100 -- gold per guild experience point
SocialConfig.BrowseSize = 30 -- guilds shown in the list
SocialConfig.GuildRefreshSeconds = 30

-- Guild level n needs Levels[n] experience. Each level gives every member
-- these bonuses (added up to the guild's level) and more room.
SocialConfig.Levels = { 0, 2000, 8000, 25000, 70000, 180000, 450000, 1100000, 2600000, 6000000 }
SocialConfig.PerLevel = { income = 0.02, attack = 0.01, defense = 0.01 }
SocialConfig.BaseMembers = 10
SocialConfig.MembersPerLevel = 2

function SocialConfig.getLevel(xp: number): number
	local level = 1
	for index, need in SocialConfig.Levels do
		if xp >= need then
			level = index
		end
	end
	return level
end

function SocialConfig.maxMembers(level: number): number
	return SocialConfig.BaseMembers + SocialConfig.MembersPerLevel * (level - 1)
end

-- The bonus a guild level gives each member ({ income, attack, defense }).
function SocialConfig.guildBonus(level: number)
	local bonus = {}
	for key, amount in SocialConfig.PerLevel do
		bonus[key] = amount * math.max(0, level - 1)
	end
	return bonus
end

---------------------------------------------------------------------------
-- Realm map
---------------------------------------------------------------------------

SocialConfig.SiegeStamina = 1
SocialConfig.SiegeMinLevel = 8
SocialConfig.RealmRefreshSeconds = 60

-- Siege points for one siege: grows with your level and a little with power.
function SocialConfig.siegePoints(level: number, attack: number): number
	return math.floor(10 + level + math.sqrt(math.max(0, attack)) * 0.5)
end

-- Laid out in a 3 x 3 grid, row by row. bonus kinds are the same as
-- research and gear sets: income, questGold, xp, attack, defense.
SocialConfig.Territories = {
	{ id = "northmarch", name = "The Northmarch", glyph = "\u{2744}\u{FE0F}", bonus = "defense", amount = 0.05, color = Color3.fromRGB(120, 160, 200) },
	{ id = "crownwood", name = "Crownwood", glyph = "\u{1F332}", bonus = "income", amount = 0.05, color = Color3.fromRGB(70, 140, 70) },
	{ id = "stormcliff", name = "Stormcliff", glyph = "\u{26A1}", bonus = "attack", amount = 0.05, color = Color3.fromRGB(110, 100, 160) },
	{ id = "goldfields", name = "The Goldfields", glyph = "\u{1F33E}", bonus = "questGold", amount = 0.08, color = Color3.fromRGB(200, 170, 70) },
	{ id = "throne", name = "Throne of Ashvale", glyph = "\u{1F451}", bonus = "income", amount = 0.1, color = Color3.fromRGB(220, 180, 60) },
	{ id = "saltcoast", name = "The Salt Coast", glyph = "\u{1F30A}", bonus = "xp", amount = 0.06, color = Color3.fromRGB(70, 140, 190) },
	{ id = "fenlands", name = "The Fenlands", glyph = "\u{1F438}", bonus = "xp", amount = 0.05, color = Color3.fromRGB(90, 130, 90) },
	{ id = "emberpass", name = "Ember Pass", glyph = "\u{1F525}", bonus = "attack", amount = 0.06, color = Color3.fromRGB(200, 90, 50) },
	{ id = "ironhold", name = "Ironhold", glyph = "\u{26CF}\u{FE0F}", bonus = "defense", amount = 0.06, color = Color3.fromRGB(130, 130, 140) },
}

SocialConfig.BonusNames = {
	income = "income",
	questGold = "quest gold",
	xp = "experience",
	attack = "attack",
	defense = "defense",
}

-- Realm weeks start Monday 00:00 UTC (the epoch began on a Thursday).
function SocialConfig.getWeek(now: number): number
	return (now - 4 * 86400) // (7 * 86400)
end

function SocialConfig.getWeekSecondsLeft(now: number): number
	local into = (now - 4 * 86400) % (7 * 86400)
	return 7 * 86400 - into
end

return SocialConfig
