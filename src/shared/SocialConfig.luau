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
-- Realm map: 30 territories in 5 tiers that guilds claim, attack, siege,
-- garrison and fortify (details in the Realm map section below).

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
-- Thirty territories in five tiers. Every tier is its own land with its
-- own look and buildings; the bonus kinds are the same everywhere, higher
-- tiers just give bigger percentages.
--
-- A territory nobody holds is CLAIMED (gold, no fighting). A territory
-- another guild holds is fought for: ATTACK (stamina) and SIEGE (energy)
-- wear down its strength, which regains 10% an hour. At 0 strength the
-- guild that did the most damage in that blow takes it over at half
-- strength; the old garrison goes home and the fortifications are lost.
--
-- Holders station soldiers from their warband as a garrison (more
-- defense), donate gold and energy to four fortifications, and every two
-- hours each member gets a stipend. Any player can live in one territory
-- as a resident and gets a share of its bonus while a guild holds it.

SocialConfig.RealmRefreshSeconds = 120 -- full re-read of every territory
SocialConfig.RealmViewSeconds = 10 -- re-read of the territory you have open
SocialConfig.RealmFlushSeconds = 8 -- attacks are sent in batches this often

SocialConfig.AttackStamina = 1
SocialConfig.AttackPower = 3 -- damage = attack x this (x roll)
SocialConfig.SiegeEnergy = 10
SocialConfig.SiegePower = 25 -- a siege hits much harder, for energy
SocialConfig.RegenPerHour = 0.1 -- share of max strength regained an hour
SocialConfig.CaptureStrength = 0.5 -- a captured territory starts at half
SocialConfig.HeldBase = 2 -- a guild holds up to this + its level territories
SocialConfig.StipendSeconds = 7200 -- every two hours
SocialConfig.ResidentShare = 0.25 -- residents get this share of the bonus
SocialConfig.ResidentsMax = 50
SocialConfig.HistoryKept = 8
SocialConfig.ResidentNamesKept = 12

-- The four fortifications. Effects are the same on every tier; the names
-- change with the tier's theme (Tiers[n].forts).
SocialConfig.Forts = {
	{ key = "walls", about = "Max strength", per = 0.2, text = "+20% max strength a level" },
	{ key = "guard", about = "Garrison defense", per = 0.2, text = "+20% garrison defense a level" },
	{ key = "heal", about = "Strength regained", per = 0.02, text = "+2% strength an hour a level" },
	{ key = "homes", about = "Residents' share", per = 0.01, text = "+1% residents' share a level" },
}
SocialConfig.FortMax = 5

-- Each soldier in a garrison adds this x their rarity rank (Common 1 ...
-- Divine 7) to the territory's defense. Damage is divided by 1 + defense.
SocialConfig.GarrisonPerRank = 0.003

-- Base bonus amounts, multiplied by the tier's scale.
SocialConfig.BonusBase = { income = 0.03, attack = 0.02, defense = 0.02, xp = 0.03, questGold = 0.04 }

SocialConfig.Tiers = {
	{
		tier = 1, name = "The Hamlets", level = 8, scale = 1, strength = 100000, claim = 100000,
		stipendMinutes = 10, garrison = 20, fortGold = 40000, fortEnergy = 30, points = 1,
		glyph = "\u{1F3E1}", land = Color3.fromRGB(96, 150, 70), sky = Color3.fromRGB(150, 200, 230),
		about = "Farm villages, mills and orchards.",
		forts = { "Wooden Palisade", "Lookout Post", "Herb Hut", "Thatched Cottages" },
	},
	{
		tier = 2, name = "Greywatch Marches", level = 15, scale = 1.8, strength = 500000, claim = 1000000,
		stipendMinutes = 15, garrison = 25, fortGold = 400000, fortEnergy = 45, points = 2,
		glyph = "\u{1F3F0}", land = Color3.fromRGB(110, 116, 120), sky = Color3.fromRGB(120, 140, 160),
		about = "Stone towers on the grey border hills.",
		forts = { "Stone Curtain Wall", "Watchtowers", "Chapel Hospice", "Garrison Row" },
	},
	{
		tier = 3, name = "The Ember Wilds", level = 22, scale = 2.8, strength = 2000000, claim = 8000000,
		stipendMinutes = 20, garrison = 30, fortGold = 3000000, fortEnergy = 60, points = 4,
		glyph = "\u{1F30B}", land = Color3.fromRGB(150, 70, 40), sky = Color3.fromRGB(200, 110, 60),
		about = "Forges and smelters on the burning slopes.",
		forts = { "Obsidian Ramparts", "Brazier Towers", "Hot Spring Baths", "Smith Lodges" },
	},
	{
		tier = 4, name = "Iron Baronies", level = 30, scale = 4, strength = 6000000, claim = 50000000,
		stipendMinutes = 30, garrison = 35, fortGold = 20000000, fortEnergy = 80, points = 7,
		glyph = "\u{26CF}\u{FE0F}", land = Color3.fromRGB(70, 76, 96), sky = Color3.fromRGB(90, 96, 120),
		about = "Mine fortresses of the iron barons.",
		forts = { "Iron Gatehouse", "Crossbow Bastions", "Barber Surgeons", "Miners' Halls" },
	},
	{
		tier = 5, name = "The Crownlands", level = 40, scale = 6, strength = 20000000, claim = 300000000,
		stipendMinutes = 45, garrison = 40, fortGold = 120000000, fortEnergy = 100, points = 10,
		glyph = "\u{1F451}", land = Color3.fromRGB(170, 140, 60), sky = Color3.fromRGB(240, 210, 130),
		about = "Palaces and courts around the throne.",
		forts = { "Royal Ramparts", "Kingsguard Barracks", "Royal Infirmary", "Noble Townhouses" },
	},
}

-- Six territories a tier. x, y = where the territory sits on its tier's
-- map (0 to 1).
local LAYOUT = { { 0.04, 0.08 }, { 0.36, 0.03 }, { 0.68, 0.1 }, { 0.08, 0.54 }, { 0.4, 0.5 }, { 0.71, 0.56 } }
local KINDS = { "income", "attack", "defense", "xp", "questGold", "income" }
local NAMES = {
	{ "Millbrook", "Hollow Green", "Applecross", "Fernhill", "Little Dunmore", "Brackenford" },
	{ "Greywatch Gate", "Cairn Hill", "Stonemere", "Wolfscar", "Ravenmoor", "Highcrag" },
	{ "Cinder Vale", "Ashfall", "Emberforge", "Brimstone Gulch", "Smokehollow", "Redspire" },
	{ "Ironhold", "Anvil Reach", "Blackmine", "Steelwater", "Hammerdeep", "Forgeholm" },
	{ "Throne of Ashvale", "Kingsreach", "Gilded Court", "Sunspire", "Regent's Rest", "Crownhaven" },
}

SocialConfig.Territories = {}
SocialConfig.TerritoryById = {}
for tierIndex, names in NAMES do
	local tier = SocialConfig.Tiers[tierIndex]
	for index, name in names do
		local kind = KINDS[index]
		local id = string.lower(string.gsub(name, "[^%a]", ""))
		local territory = {
			id = id,
			name = name,
			tier = tierIndex,
			slot = index,
			x = LAYOUT[index][1],
			y = LAYOUT[index][2],
			bonus = kind,
			amount = math.floor(SocialConfig.BonusBase[kind] * tier.scale * 1000 + 0.5) / 1000,
		}
		table.insert(SocialConfig.Territories, territory)
		SocialConfig.TerritoryById[id] = territory
	end
end

SocialConfig.BonusNames = {
	income = "income",
	questGold = "quest gold",
	xp = "experience",
	attack = "attack",
	defense = "defense",
}

function SocialConfig.maxHeld(guildLevel: number): number
	return SocialConfig.HeldBase + guildLevel
end

-- Max strength of a territory with its walls at `walls`.
function SocialConfig.maxStrength(tier: number, walls: number): number
	return math.floor(SocialConfig.Tiers[tier].strength * (1 + SocialConfig.Forts[1].per * walls))
end

-- Share of max strength regained an hour.
function SocialConfig.regenRate(heal: number): number
	return SocialConfig.RegenPerHour + SocialConfig.Forts[3].per * heal
end

function SocialConfig.residentShare(homes: number): number
	return SocialConfig.ResidentShare + SocialConfig.Forts[4].per * homes
end

-- Gold and energy for the next level of a fortification.
function SocialConfig.fortCost(tier: number, level: number): (number, number)
	local info = SocialConfig.Tiers[tier]
	return info.fortGold * (level + 1), info.fortEnergy * (level + 1)
end

-- The garrison's defense bonus from the sum of its soldiers' rarity ranks.
function SocialConfig.garrisonDefense(rankSum: number, guard: number): number
	return rankSum * SocialConfig.GarrisonPerRank * (1 + SocialConfig.Forts[2].per * guard)
end

-- The two-hour stipend period number.
function SocialConfig.stipendPeriod(now: number): number
	return now // SocialConfig.StipendSeconds
end

return SocialConfig
