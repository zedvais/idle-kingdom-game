-- Server entry point: runs every rule of the game.
-- The game is played entirely through menus. The client sends a request on
-- the Action remote ("do this quest", "buy this holding"), the server checks
-- it and changes the player's data, then sends the new state back.
-- Never trust numbers from the client: everything is worked out here.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local StoreConfig = require(ReplicatedStorage.Shared.StoreConfig)
local BountyConfig = require(ReplicatedStorage.Shared.BountyConfig)
local FestivalConfig = require(ReplicatedStorage.Shared.FestivalConfig)
local ResearchConfig = require(ReplicatedStorage.Shared.ResearchConfig)
local ProfileConfig = require(ReplicatedStorage.Shared.ProfileConfig)
local RelicConfig = require(ReplicatedStorage.Shared.RelicConfig)
local RebirthConfig = require(ReplicatedStorage.Shared.RebirthConfig)
local Format = require(ReplicatedStorage.Shared.Format)
local Market = require(script.Parent.Market)
local Recruit = require(script.Parent.Recruit)
local Loadout = require(script.Parent.Loadout)
local PlayerData = require(script.Parent.PlayerData)
local Store = require(script.Parent.Store)

local AUTOSAVE_SECONDS = 60
local MAX_ACTIONS_PER_SECOND = 25

-- Nobody walks around in this game, so characters are never spawned.
Players.CharacterAutoLoads = false

-- Remotes the client uses: Action (client to server) and State (server to client).
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local actionRemote = Instance.new("RemoteEvent")
actionRemote.Name = "Action"
actionRemote.Parent = remotes
local stateRemote = Instance.new("RemoteEvent")
stateRemote.Name = "State"
stateRemote.Parent = remotes
remotes.Parent = ReplicatedStorage

local sessions = {} -- [Player] = { data, canSave, actionCount, regen }
local festivalTop = {} -- { { name, points } } for this week, refreshed each minute
local festivalTopWeek = -1
local boardTops = {} -- [ranking board key] = { { name, score } }, all servers
local random = Random.new()

-- Quick lookups from an id to its settings.
local function indexById(list)
	local map = {}
	for _, item in list do
		map[item.id] = item
	end
	return map
end

local skillById = indexById(GameConfig.Skills)
local questById = indexById(GameConfig.Quests)
local holdingById = indexById(GameConfig.Holdings)
local stageById = indexById(GameConfig.Stages)
local tokenItemById = indexById(GameConfig.TokenShop)

---------------------------------------------------------------------------
-- Working out a player's numbers
---------------------------------------------------------------------------

local function sendToast(player: Player, text: string)
	player:SetAttribute("ToastText", text)
	player:SetAttribute("ToastId", (player:GetAttribute("ToastId") or 0) + 1)
end

-- Puts a letter in the player's mail. rewards is a list of rewards to
-- claim (see StoreConfig), or nil for a letter that only tells something.
local function sendMail(data, title: string, text: string, rewards)
	local id = "m" .. data.mailNext
	data.mailNext += 1
	table.insert(data.mail, 1, {
		id = id,
		time = os.time(),
		title = title,
		text = text,
		rewards = rewards,
		claimed = rewards == nil,
		read = false,
	})
	-- Too many letters: throw away the oldest one with nothing to claim.
	while #data.mail > ProfileConfig.MailKept do
		local dropped = false
		for index = #data.mail, 1, -1 do
			if data.mail[index].claimed then
				table.remove(data.mail, index)
				dropped = true
				break
			end
		end
		if not dropped then
			table.remove(data.mail)
		end
	end
end

-- Adds to an all-time number shown on the Profile page.
local function countLifetime(data, stat: string, amount: number)
	data.lifetime[stat] = (data.lifetime[stat] or 0) + amount
end

-- True if the player owns this game pass ("charter", "couriers", ...).
local function hasPass(data, key: string): boolean
	return data.passes[key] == true
end

-- How many pieces of gear the armory holds.
local function maxGear(data): number
	return GameConfig.MaxGearOwned + (if hasPass(data, "armory") then StoreConfig.ArmoryExtra else 0)
end

-- Research bonus of one kind ("income", "attack", "energy", ...), added up.
local function researchTotal(data, kind: string): number
	local total = 0
	for key, level in data.research.levels do
		local tech = ResearchConfig.Techs[key]
		if tech and tech.bonus == kind then
			total += tech.amount * level
		end
	end
	return total
end

-- This week's festival bonus of one kind, or 0.
local function festivalBonus(kind: string): number
	local festival = FestivalConfig.getFestival(FestivalConfig.getWeek(os.time()))
	if festival.bonus.kind == kind then
		return festival.bonus.amount
	end
	return 0
end

-- Market price after this week's festival discount.
local function marketPrice(item): number
	return math.floor(item.price * (1 - festivalBonus("marketPrice")))
end

local function skillTotal(data, skillId: string): number
	return (data.skills[skillId] or 0) * skillById[skillId].amount
end

local function getKeepBonus(data): number
	local keep = GameConfig.KeepLevels[data.keep] or GameConfig.KeepLevels[1]
	return keep.bonus
end

-- The bonuses from every trophy the player has earned, added up.
local function getTrophyBonus(data)
	local total = { attack = 0, defense = 0, income = 0, xp = 0, questGold = 0 }
	for _, trophy in GameConfig.Trophies do
		if data.trophies[trophy.id] then
			for key in total do
				total[key] += trophy[key] or 0
			end
		end
	end
	return total
end

-- Trophy bonuses plus the realm bonuses from full gear sets.
local function getPerkBonus(data, gear)
	local total = getTrophyBonus(data)
	local perks = (gear or Loadout.compute(data)).perks
	for key in total do
		total[key] += perks[key] or 0
	end
	if hasPass(data, "charter") then
		total.income += StoreConfig.CharterIncome
		total.questGold += StoreConfig.CharterQuestGold
		total.xp += StoreConfig.CharterXp
	end
	for key in total do
		total[key] += researchTotal(data, key)
	end
	total.income += festivalBonus("income")
	total.attack += festivalBonus("attack")
	-- Rebirth Stars and the Relic Hall last forever.
	for key, amount in RebirthConfig.PerStar do
		total[key] += amount * data.rebirth.stars
	end
	local relicBonus = RelicConfig.getBonus(data.relics.points)
	total.attack += relicBonus
	total.defense += relicBonus
	return total
end

-- Every number the menus show about the player, with where attack and
-- defense come from.
local function getStats(data)
	local baseAttack = GameConfig.BaseAttack + skillTotal(data, "attack")
	local baseDefense = GameConfig.BaseDefense + skillTotal(data, "defense")

	local crewAttack, crewDefense, crewSize = 0, 0, 0
	for _, soldier in data.crew do
		if soldier then
			local soldierAttack, soldierDefense = GameConfig.getSoldierStats(soldier)
			crewAttack += soldierAttack
			crewDefense += soldierDefense
			crewSize += 1
		end
	end

	local gear = Loadout.compute(data)
	local gearAttack, gearDefense = gear.attack, gear.defense
	local crewBonus = crewSize * GameConfig.CrewSizeBonus
	local keepBonus = getKeepBonus(data)
	local trophyBonus = getTrophyBonus(data)
	local perkBonus = getPerkBonus(data, gear)

	local rawAttack = baseAttack + crewAttack + gearAttack
	local rawDefense = baseDefense + crewDefense + gearDefense
	local attack = math.floor(rawAttack * (1 + crewBonus + keepBonus + perkBonus.attack))
	local defense = math.floor(rawDefense * (1 + crewBonus + keepBonus + perkBonus.defense))

	local incomePerHour = 0
	local lotsUsed = 0
	for _, holding in GameConfig.Holdings do
		local count = data.holdings[holding.id] or 0
		lotsUsed += count
		incomePerHour += holding.income * count
	end
	incomePerHour = math.floor(incomePerHour * (1 + keepBonus + perkBonus.income))

	return {
		maxEnergy = GameConfig.BaseMaxEnergy + skillTotal(data, "energy") + researchTotal(data, "energy"),
		maxStamina = GameConfig.BaseMaxStamina + skillTotal(data, "stamina"),
		maxHealth = GameConfig.BaseMaxHealth + skillTotal(data, "health") + researchTotal(data, "health"),
		attack = attack,
		defense = defense,
		crewSize = crewSize,
		crewBonus = crewBonus,
		keepBonus = keepBonus,
		trophyBonus = trophyBonus,
		setBonus = gear.perks,
		lots = GameConfig.BaseLots + skillTotal(data, "lots") + researchTotal(data, "lots"),
		lotsUsed = lotsUsed,
		incomePerHour = incomePerHour,
		-- Where attack and defense come from, for the Keep page.
		breakdown = {
			{ "You and skills", baseAttack, baseDefense },
			{ "Warband", crewAttack, crewDefense },
			{ "Gear", gearAttack, gearDefense },
			{ "Bonuses", attack - rawAttack, defense - rawDefense },
		},
	}
end

-- Starts a new day of playtime rewards when the UTC day changes.
local function checkNewDay(data)
	local today = GameConfig.getDay()
	if data.playDay ~= today then
		data.playDay = today
		data.playSeconds = 0
		data.claimed = {}
	end
end

-- Foes come back to full health and can be beaten again each UTC day.
local function checkStageDay(data)
	local today = GameConfig.getDay()
	if data.stageDay ~= today then
		data.stageDay = today
		data.stageHealth = {}
		data.stageCleared = {}
	end
end

-- A new Royal Pass season starts everyone from tier 0 on the free track.
local function checkPassSeason(data)
	local season = StoreConfig.getSeason(os.time())
	if data.pass.season ~= season then
		data.pass = {
			season = season,
			points = 0,
			noble = false,
			energyCarry = 0,
			claimedFree = {},
			claimedNoble = {},
		}
	end
end

-- Weekly challenges start over every Monday 00:00 UTC.
local function checkWeek(data)
	local week = StoreConfig.getWeek(os.time())
	if data.weekly.week ~= week then
		data.weekly = { week = week, energy = 0, foes = 0, market = 0, play = 0, claimed = {} }
	end
end

local function addPassPoints(data, points: number)
	checkPassSeason(data)
	local cap = StoreConfig.PassTiers * StoreConfig.PointsPerTier
	data.pass.points = math.min(cap, data.pass.points + points)
end

-- Quest energy feeds the Royal Pass, the Tithe Chest and the weekly challenge.
local function onQuestEnergy(data, energy: number)
	checkWeek(data)
	data.weekly.energy += energy

	checkPassSeason(data)
	local perPoint = 1 / StoreConfig.PointsPerQuestEnergy
	data.pass.energyCarry += energy
	local points = math.floor(data.pass.energyCarry / perPoint)
	if points > 0 then
		data.pass.energyCarry -= points * perPoint
		addPassPoints(data, points)
	end

	data.titheEnergy += energy
	local crowns = math.floor(data.titheEnergy / StoreConfig.TitheEnergyPerCrown)
	if crowns > 0 then
		data.titheEnergy -= crowns * StoreConfig.TitheEnergyPerCrown
		data.tithe = math.min(StoreConfig.TitheMax, data.tithe + crowns)
	end
end

local function onFoeBeaten(data)
	checkWeek(data)
	data.weekly.foes += 1
	addPassPoints(data, StoreConfig.PointsPerFoe)
	data.tithe = math.min(StoreConfig.TitheMax, data.tithe + StoreConfig.TitheCrownsPerFoe)
end

-- Bounty counts start over each UTC day (daily) and each week (weekly).
local function checkBounty(data)
	local bounty = data.bounty
	local today = GameConfig.getDay()
	local week = StoreConfig.getWeek(os.time())
	if bounty.day ~= today then
		bounty.day = today
		bounty.daily = {}
		for _, task in BountyConfig.Daily do
			bounty.claimed[task.key] = nil
		end
	end
	if bounty.week ~= week then
		bounty.week = week
		bounty.weekly = {}
		for _, task in BountyConfig.Weekly do
			bounty.claimed[task.key] = nil
		end
	end
	if bounty.shopWeek ~= week then
		bounty.shopWeek = week
		bounty.bought = {}
	end
end

-- A new festival starts each week. The finished week's points are kept so
-- its rank reward can be paid.
local function checkFestival(data)
	local festival = data.festival
	local week = FestivalConfig.getWeek(os.time())
	if festival.week ~= week then
		if festival.points > 0 and festival.week >= 0 then
			festival.lastWeek = festival.week
			festival.lastPoints = festival.points
			festival.lastPaid = false
		end
		festival.week = week
		festival.points = 0
		festival.milestones = {}
	end
end

-- Counts one kind of action for the Bounty Board and Festival Week.
-- stat is one of BountyConfig.Stats.
local function track(data, stat: string, amount: number)
	countLifetime(data, stat, amount)
	checkBounty(data)
	data.bounty.daily[stat] = (data.bounty.daily[stat] or 0) + amount
	data.bounty.weekly[stat] = (data.bounty.weekly[stat] or 0) + amount

	checkFestival(data)
	local festival = FestivalConfig.getFestival(data.festival.week)
	local points = festival.points[stat]
	if points then
		data.festival.points += points * amount
	end
end

-- Which streak day the player would claim today, and whether they can.
local function streakToday(data): (number, boolean)
	local today = GameConfig.getDay()
	local streak = data.streak
	if streak.lastDay == today then
		return streak.count, false
	end
	if streak.lastDay == today - 1 then
		return streak.count % #BountyConfig.Streak + 1, true
	end
	return 1, true
end

-- How far the player is toward a trophy.
local function trophyProgress(data, kind: string): number
	if kind == "stage" then
		return data.highestStage
	elseif kind == "level" then
		return data.level
	elseif kind == "keep" then
		return data.keep
	elseif kind == "holdings" then
		local total = 0
		for _, count in data.holdings do
			total += count
		end
		return total
	elseif kind == "mastered" then
		local total = 0
		for _, done in data.quests do
			if GameConfig.getMasteryRank(done) >= GameConfig.MaxMasteryRanks then
				total += 1
			end
		end
		return total
	elseif kind == "crew" or kind == "divine" then
		local total = 0
		for _, soldier in data.crew do
			if soldier and (kind == "crew" or soldier.rarity == "Divine") then
				total += 1
			end
		end
		return total
	end
	return 0
end

local function checkTrophies(player: Player, data)
	for _, trophy in GameConfig.Trophies do
		if not data.trophies[trophy.id] and trophyProgress(data, trophy.kind) >= trophy.value then
			data.trophies[trophy.id] = true
			sendToast(player, `Trophy earned: {trophy.name}! Check your Inventory.`)
			sendMail(data, `Trophy: {trophy.name}`, `{trophy.note}. Its bonus is yours for good.`, nil)
		end
	end
end

-- Restocks the Market when a new window starts.
local function restockIfDue(player: Player, data)
	local window = Market.currentWindow()
	if data.market.window ~= window then
		data.market = Market.roll(player.UserId, window, data.level)
	end
end

-- Sends the player everything their menus need to draw.
local function refresh(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	local data = session.data
	local stats = getStats(data)
	local now = os.time()

	restockIfDue(player, data)
	local gearState = Loadout.compute(data)
	local wearing = gearState.wearing
	local gearInUse = {}
	for _, item in data.gear do
		if item.wornBy ~= nil then
			gearInUse[item.uid] = true
		end
	end

	-- The warband as the client draws it: each slot with its soldier's
	-- stats and gear worked out.
	local crew = {}
	for slot, soldier in data.crew do
		if soldier then
			local soldierAttack, soldierDefense = GameConfig.getSoldierStats(soldier)
			local entry = table.clone(soldier)
			entry.attack = soldierAttack
			entry.defense = soldierDefense
			entry.trainCost = GameConfig.getTrainCost(soldier)
			entry.gear = wearing[slot] or {}
			crew[slot] = entry
		else
			crew[slot] = false
		end
	end

	checkStageDay(data)
	checkPassSeason(data)
	checkWeek(data)
	checkBounty(data)
	checkFestival(data)
	local streakDay, streakReady = streakToday(data)
	checkTrophies(player, data)
	local trophyProgressList = {}
	for _, trophy in GameConfig.Trophies do
		trophyProgressList[trophy.id] = math.min(trophy.value, trophyProgress(data, trophy.kind))
	end

	stateRemote:FireClient(player, {
		gold = data.gold,
		level = data.level,
		xp = data.xp,
		xpNeeded = GameConfig.getXpNeeded(data.level),
		skillPoints = data.skillPoints,
		renown = data.renown,
		energy = data.energy,
		stamina = data.stamina,
		health = data.health,
		stats = stats,
		skills = data.skills,
		quests = data.quests,
		holdings = data.holdings,
		keep = data.keep,
		banked = data.banked,
		playSeconds = data.playSeconds,
		claimed = data.claimed,
		xpBoostLeft = math.max(0, data.xpBoostUntil - now),
		crew = crew,
		yourGear = wearing[0] or {},
		gear = data.gear,
		gearInUse = gearInUse,
		gearSets = gearState.sets,
		fullSets = gearState.fullSets,
		autoEquipNew = data.autoEquipNew,
		market = data.market.items,
		marketRestock = Market.secondsUntilRestock(),
		marketWindow = data.market.window,
		tokens = data.tokens,
		highestStage = data.highestStage,
		stageHealth = data.stageHealth,
		stageCleared = data.stageCleared,
		stageReset = GameConfig.getSecondsToReset(),
		trophies = data.trophies,
		trophyProgress = trophyProgressList,
		autoQuest = data.autoQuest,
		autoQuestOn = data.autoQuestOn,
		autoBuy = data.autoBuy,
		maxGear = maxGear(data),
		crowns = data.crowns,
		passes = data.passes,
		packsBought = data.packsBought,
		secondsSinceFirstVisit = now - data.firstSeen,
		title = data.title,
		tithe = data.tithe,
		pity = data.pity,
		pass = data.pass,
		passSecondsLeft = StoreConfig.getSeasonSecondsLeft(now),
		weekly = data.weekly,
		weekSecondsLeft = StoreConfig.getWeekSecondsLeft(now),
		tipsSeen = data.tipsSeen,
		seals = data.seals,
		bounty = data.bounty,
		streakDay = streakDay,
		streakReady = streakReady,
		festival = data.festival,
		festivalTop = if festivalTopWeek == data.festival.week then festivalTop else {},
		research = data.research,
		researchLeft = math.max(0, data.research.endsAt - now),
		firstSeen = data.firstSeen,
		lifetime = data.lifetime,
		titles = data.titles,
		firstClears = data.firstClears,
		mail = data.mail,
		relics = data.relics,
		relicBonus = RelicConfig.getBonus(data.relics.points),
		rebirth = data.rebirth,
		rebirthStars = RebirthConfig.getStars(data.level),
		rankings = boardTops,
	})

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local levelStat = leaderstats:FindFirstChild("Level")
		local renownStat = leaderstats:FindFirstChild("Renown")
		if levelStat then
			levelStat.Value = data.level
		end
		if renownStat then
			renownStat.Value = data.renown
		end
	end
end

local function addXp(player: Player, data, amount: number)
	if data.xpBoostUntil > os.time() then
		amount *= 2
	end
	data.xp += amount
	local leveled = false
	while data.xp >= GameConfig.getXpNeeded(data.level) do
		data.xp -= GameConfig.getXpNeeded(data.level)
		data.level += 1
		data.skillPoints += GameConfig.SkillPointsPerLevel
		leveled = true
	end
	if leveled then
		-- A level up refills everything.
		local stats = getStats(data)
		data.energy = math.max(data.energy, stats.maxEnergy)
		data.stamina = math.max(data.stamina, stats.maxStamina)
		data.health = math.max(data.health, stats.maxHealth)
		sendToast(player, `Level {data.level}! You gained {GameConfig.SkillPointsPerLevel} skill points and a full refill.`)
	end
end

local function spendGold(player: Player, data, cost: number): boolean
	if data.gold < cost then
		sendToast(player, `Not enough gold. You need {Format.short(cost)}.`)
		return false
	end
	data.gold -= cost
	return true
end

-- Who a member is, for messages.
local function memberName(data, member: number?): string
	if member == 0 then
		return "you"
	end
	local soldier = member and data.crew[member]
	return if soldier then soldier.name else "nobody"
end

-- Adds a new item to the armory. If "New gear fills empty slots" is on, it
-- goes straight onto the first person with that slot empty.
-- Returns a short note about who wears it, for the toast.
local function addGear(data, item): string
	item.uid = "i" .. data.nextItemId
	data.nextItemId += 1
	table.insert(data.gear, item)
	if data.autoEquipNew then
		local member = Loadout.fillEmpty(data, item)
		if member ~= nil then
			return if member == 0 then " You put it on." else ` {memberName(data, member)} put it on.`
		end
	end
	return ""
end

-- Gives the player a rolled piece of gear (quest drops and chests).
-- Pass `set` for a piece of a gear set. `paid` lets bought rewards go past
-- the armory limit, so nothing paid for is ever lost.
local function giveGear(player: Player, data, minRank: number?, source: string, set: any?, paid: boolean?)
	if not paid and #data.gear >= maxGear(data) then
		sendToast(player, `{source}, but your armory is full. Sell some gear to make room.`)
		return
	end
	local item = if set
		then Market.rollSetPiece(random, data.level, set, minRank or 1)
		else Market.rollGear(random, data.level, minRank)
	local note = addGear(data, item)
	sendToast(player, `{source}: {item.rarity} {item.name}!{note}`)
end

---------------------------------------------------------------------------
-- Player actions
---------------------------------------------------------------------------

local actions = {}

function actions.Quest(player: Player, data, id: string)
	local quest = questById[id]
	if not quest or data.level < quest.level or data.level < GameConfig.getRegion(quest.region).level then
		return
	end
	if data.energy < quest.energy then
		sendToast(player, "Not enough energy. It refills over time.")
		return
	end

	local completions = data.quests[id] or 0
	local rankBefore = GameConfig.getMasteryRank(completions)

	local trophyBonus = getPerkBonus(data)
	data.energy -= quest.energy
	onQuestEnergy(data, quest.energy)
	local questGold = math.floor(GameConfig.getQuestGold(quest, completions) * (1 + trophyBonus.questGold))
	data.gold += questGold
	countLifetime(data, "goldEarned", questGold)
	data.quests[id] = completions + 1
	track(data, "quests", 1)
	data.autoQuest = id

	local rankAfter = GameConfig.getMasteryRank(completions + 1)
	if rankAfter > rankBefore then
		sendToast(player, `{GameConfig.MasteryMedals[rankAfter]} mastery! {quest.name} now pays more gold.`)
	end
	if random:NextNumber() < quest.drop then
		giveGear(player, data, nil, "You found gear")
	end
	addXp(player, data, math.floor(quest.xp * (1 + trophyBonus.xp)))
end

-- Builds one more copy of a holding on a free lot.
function actions.Holding(player: Player, data, id: string)
	local holding = holdingById[id]
	if not holding or data.level < holding.level then
		return
	end
	local stats = getStats(data)
	if stats.lotsUsed >= stats.lots then
		sendToast(player, "Every lot is built on. Demolish one, or buy Holding Lots in the Keep.")
		return
	end
	local count = data.holdings[id] or 0
	if spendGold(player, data, GameConfig.getHoldingCost(holding, count)) then
		data.holdings[id] = count + 1
		track(data, "holdings", 1)
	end
end

-- Pulls down one copy of a holding to free its lot.
function actions.Demolish(player: Player, data, id: string)
	local holding = holdingById[id]
	local count = holding and data.holdings[id] or 0
	if not holding or count <= 0 then
		return
	end
	local refund = math.floor(GameConfig.getHoldingCost(holding, count - 1) * GameConfig.DemolishRefund)
	data.holdings[id] = count - 1
	data.gold += refund
	sendToast(player, `Demolished a {holding.name} for {Format.short(refund)} gold. One lot is free.`)
end

-- Upgrades the Keep to its next level.
function actions.Keep(player: Player, data)
	local nextKeep = GameConfig.KeepLevels[data.keep + 1]
	if not nextKeep then
		return
	end
	if data.level < nextKeep.level then
		sendToast(player, `You need level {nextKeep.level} for the {nextKeep.name}.`)
		return
	end
	if spendGold(player, data, nextKeep.cost) then
		data.keep += 1
		sendToast(player, `Your home is now the {nextKeep.name}! +{math.floor(nextKeep.bonus * 100)}% income, attack and defense.`)
	end
end

-- Claims a daily playtime reward. id is its number in the list, as text.
function actions.Claim(player: Player, data, id: string)
	checkNewDay(data)
	local index = tonumber(id)
	local reward = index and GameConfig.PlaytimeRewards[index]
	if not reward or data.claimed[id] or data.playSeconds < reward.minutes * 60 then
		return
	end
	data.claimed[id] = true
	addPassPoints(data, StoreConfig.PointsPerPlaytimeReward)
	track(data, "claims", 1)

	local stats = getStats(data)
	if reward.kind == "gold" then
		local amount = math.max(math.floor(stats.incomePerHour / 60 * reward.amount), 500 * data.level)
		data.gold += amount
		sendToast(player, `{reward.label}: +{Format.short(amount)} gold.`)
	elseif reward.kind == "energy" then
		data.energy = math.max(data.energy, stats.maxEnergy)
		sendToast(player, "Energy refilled.")
	elseif reward.kind == "stamina" then
		data.stamina = math.max(data.stamina, stats.maxStamina)
		sendToast(player, "Stamina refilled.")
	elseif reward.kind == "chest" then
		giveGear(player, data, GameConfig.getRarityRank(reward.rarity), `{reward.label} opened`)
	elseif reward.kind == "xpBoost" then
		data.xpBoostUntil = math.max(data.xpBoostUntil, os.time()) + reward.amount * 60
		sendToast(player, `Double experience for {reward.amount} minutes!`)
	end
end

-- Bank. id is the amount as text ("all" for everything).
function actions.Deposit(player: Player, data, id: string)
	local amount = if id == "all" then math.floor(data.gold) else Format.parse(id)
	if not amount or amount <= 0 then
		sendToast(player, "Type an amount, like 5000 or 2.5m.")
		return
	end
	amount = math.min(amount, math.floor(data.gold))
	if amount <= 0 then
		return
	end
	local fee = if hasPass(data, "treasury") then 0 else math.ceil(amount * GameConfig.BankFee)
	data.gold -= amount
	data.banked += amount - fee
	if fee > 0 then
		sendToast(player, `Deposited {Format.short(amount - fee)} gold after a {Format.short(fee)} fee.`)
	else
		sendToast(player, `Deposited {Format.short(amount)} gold. The Royal Treasury takes no fee.`)
	end
end

function actions.Withdraw(player: Player, data, id: string)
	local amount = if id == "all" then math.floor(data.banked) else Format.parse(id)
	if not amount or amount <= 0 then
		sendToast(player, "Type an amount, like 5000 or 2.5m.")
		return
	end
	amount = math.min(amount, math.floor(data.banked))
	if amount <= 0 then
		return
	end
	data.banked -= amount
	data.gold += amount
	sendToast(player, `Withdrew {Format.short(amount)} gold.`)
end

function actions.Skill(player: Player, data, id: string)
	local skill = skillById[id]
	if not skill then
		return
	end
	local cost = GameConfig.getSkillCost(skill, data.skills[id] or 0)
	if data.skillPoints < cost then
		sendToast(player, "Not enough skill points. Level up to earn more.")
		return
	end

	data.skillPoints -= cost
	data.skills[id] = (data.skills[id] or 0) + 1

	-- Raising a maximum also hands over the new points right away.
	if id == "energy" or id == "stamina" or id == "health" then
		data[id] += skill.amount
	end
end

function actions.Slot(player: Player, data)
	local nextSlot = #data.crew + 1
	if nextSlot > GameConfig.MaxSoldierSlots then
		return
	end
	local level = GameConfig.getSlotLevel(nextSlot)
	if data.level < level then
		sendToast(player, `You need level {level} to unlock this slot.`)
		return
	end
	if spendGold(player, data, GameConfig.getSlotCost(nextSlot)) then
		table.insert(data.crew, false)
		sendToast(player, "A new warband slot is open. Recruit someone to fill it.")
	end
end

-- Recruits soldiers by rolling. id is "slot:tier:rarity:scope", for example
-- "3:Royal:Epic:this". Rolls keep going until a soldier of that rarity or
-- better turns up, gold runs out, or the roll limit is reached. Only the
-- soldier that hits the target is kept; it replaces whoever was in the slot.
--   scope "this"  = just that slot
--   scope "empty" = every empty slot
--   scope "below" = every slot that is empty or below that rarity
function actions.Roll(player: Player, data, id: string)
	local slotText, tierId, rarityId, scope = string.match(id, "^(%d+):(%a+):(%a+):(%a+)$")
	local tier = tierId and GameConfig.getRecruitTier(tierId)
	if not tier then
		return
	end
	if data.level < tier.level then
		sendToast(player, `You need level {tier.level} for {tier.id} recruits.`)
		return
	end
	local targetRank = GameConfig.getRarityRank(rarityId)
	if GameConfig.Rarities[targetRank].id ~= rarityId or GameConfig.getChanceAtLeast(tier, rarityId) <= 0 then
		sendToast(player, `{tier.id} recruits can never be {rarityId}.`)
		return
	end

	local targets = {}
	if scope == "this" then
		local slot = tonumber(slotText)
		if slot and data.crew[slot] ~= nil then
			table.insert(targets, slot)
		end
	else
		for slot, soldier in data.crew do
			if not soldier or (scope == "below" and GameConfig.getRarityRank(soldier.rarity) < targetRank) then
				table.insert(targets, slot)
			end
		end
	end
	if #targets == 0 then
		sendToast(player, "No slots match. Pick another option.")
		return
	end
	-- The Muster Fair festival makes rolls cheaper.
	local rollCost = math.floor(tier.cost * (1 - festivalBonus("rollCost")))
	if data.gold < rollCost then
		sendToast(player, `Not enough gold. One {tier.id} roll costs {Format.short(rollCost)}.`)
		return
	end

	-- Without the Recruiting Sergeant pass, each press is one roll for one
	-- slot. It is kept if the slot is empty or it reaches the chosen rarity.
	if not hasPass(data, "autoroll") then
		local slot = targets[1]
		data.gold -= rollCost
		local soldier = Recruit.roll(tier, "s" .. data.nextItemId)
		data.nextItemId += 1
		track(data, "rolls", 1)
		if not data.crew[slot] or GameConfig.getRarityRank(soldier.rarity) >= targetRank then
			data.crew[slot] = soldier
			sendToast(player, `{soldier.rarity} {soldier.class} {soldier.name} joined slot {slot}.`)
		else
			sendToast(player, `Rolled a {soldier.rarity} {soldier.class}, below {rarityId}, so slot {slot} kept its soldier. The Recruiting Sergeant pass keeps rolling for you.`)
		end
		return
	end

	local rolls, filled, best = 0, 0, nil
	for _, slot in targets do
		while rolls < GameConfig.MaxRollsPerRequest and data.gold >= rollCost do
			data.gold -= rollCost
			rolls += 1
			local soldier = Recruit.roll(tier, "s" .. data.nextItemId)
			data.nextItemId += 1
			if GameConfig.getRarityRank(soldier.rarity) >= targetRank then
				data.crew[slot] = soldier
				filled += 1
				if not best or GameConfig.getRarityRank(soldier.rarity) > GameConfig.getRarityRank(best.rarity) then
					best = soldier
				end
				break
			end
		end
	end

	if rolls > 0 then
		track(data, "rolls", rolls)
	end
	local spent = Format.short(rolls * rollCost)
	if filled == 0 then
		sendToast(player, `{rolls} rolls ({spent} gold) and no {rarityId} or better. Try again.`)
	elseif filled == 1 and best then
		sendToast(player, `{best.rarity} {best.class} {best.name} joined after {rolls} rolls ({spent} gold).`)
	elseif best then
		sendToast(player, `Filled {filled} of {#targets} slots in {rolls} rolls ({spent} gold). Best: {best.rarity} {best.name}.`)
	end
end

function actions.Train(player: Player, data, id: string)
	local slot = tonumber(id)
	local soldier = slot and data.crew[slot]
	if not soldier then
		return
	end
	if soldier.train >= GameConfig.MaxTrainRank then
		sendToast(player, `{soldier.name} is fully trained.`)
		return
	end
	if spendGold(player, data, GameConfig.getTrainCost(soldier)) then
		soldier.train += 1
		track(data, "train", 1)
	end
end

-- Dismisses the soldier in a slot. The slot stays unlocked and empty.
function actions.Release(player: Player, data, id: string)
	local slot = tonumber(id)
	local soldier = slot and data.crew[slot]
	if soldier then
		Loadout.clearMember(data, slot)
		data.crew[slot] = false
		sendToast(player, `{soldier.name} left the warband. Their gear is back in your armory.`)
	end
end

-- Buys a Market item. `auto` is true when auto-buy does it, which keeps
-- its messages short.
local function buyItem(player: Player, data, item, auto: boolean): boolean
	if data.level < item.level then
		if not auto then
			sendToast(player, `You need level {item.level} to buy this.`)
		end
		return false
	end
	if #data.gear >= maxGear(data) then
		sendToast(player, "Your armory is full. Sell some gear first.")
		return false
	end
	local price = marketPrice(item)
	if data.gold < price then
		if not auto then
			sendToast(player, `Not enough gold. You need {Format.short(price)}.`)
		end
		return false
	end
	data.gold -= price

	item.sold = true
	local owned = table.clone(item)
	owned.sold = nil
	local note = addGear(data, owned)
	checkWeek(data)
	data.weekly.market += 1
	track(data, "market", 1)
	sendToast(player, `{if auto then "Auto-buy got" else "You bought"} a {owned.rarity} {owned.name}.{note}`)
	return true
end

-- Buys one Market offer. id is "<window>:<row>", for example "5902211:4":
-- the restock window the player was looking at, then the row they clicked.
-- If the stock has restocked since then, the row now holds a different item
-- at a different price, so the request is turned down before any gold is
-- taken, and the refresh that follows shows the player the new stock.
function actions.Buy(player: Player, data, id: string)
	local windowText, rowText = string.match(id, "^(%d+):(%d+)$")
	local window = tonumber(windowText)
	local index = tonumber(rowText)
	if not window or not index then
		return
	end
	restockIfDue(player, data)
	if window ~= data.market.window then
		sendToast(player, "The Market just restocked, so nothing was bought. Check the new stock.")
		return
	end
	local item = data.market.items[index]
	if item and not item.sold then
		buyItem(player, data, item, false)
	end
end

-- Sells a piece of gear for part of its price.
function actions.Sell(player: Player, data, id: string)
	for index, item in data.gear do
		if item.uid == id then
			if item.wornBy ~= nil then
				sendToast(player, `Take the {item.name} off {memberName(data, item.wornBy)} before selling it.`)
				return
			end
			table.remove(data.gear, index)
			local refund = math.floor(item.price * GameConfig.SellShare)
			data.gold += refund
			sendToast(player, `Sold {item.rarity} {item.name} for {Format.short(refund)} gold.`)
			return
		end
	end
end

-- One attack on a foe stage. Returns "cleared", "down" or "hit" with the
-- damage dealt and taken, or nil if the attack could not be made. A toast
-- says why, unless `quiet` is set (later attacks of Attack x5).
local function attackStage(player: Player, data, stage, quiet: boolean): (string?, number, number)
	local id = stage.id
	local function refuse(text: string)
		if not quiet then
			sendToast(player, text)
		end
		return nil, 0, 0
	end
	checkStageDay(data)
	if stage.index > data.highestStage + 1 then
		return refuse("Beat the stage before this one first.")
	end
	if data.stageCleared[id] then
		return refuse(`{stage.name} is already beaten today. Foes return at 00:00 UTC.`)
	end
	if data.stamina < 1 then
		return refuse("Not enough stamina. It refills over time.")
	end
	if data.health < GameConfig.MinHealthToFight then
		return refuse(`You are too wounded. Rest until you have {GameConfig.MinHealthToFight} health.`)
	end

	local stats = getStats(data)
	data.stamina -= 1
	countLifetime(data, "attacks", 1)

	local roll = random:NextNumber(GameConfig.HitRollMin, GameConfig.HitRollMax)
	local damage = math.max(1, math.floor(GameConfig.getHit(stats.attack, stage.defense) * roll))
	local health = (data.stageHealth[id] or stage.health) - damage

	if health <= 0 then
		data.stageHealth[id] = nil
		data.stageCleared[id] = true
		data.highestStage = math.max(data.highestStage, stage.index)
		data.gold += stage.gold
		countLifetime(data, "goldEarned", stage.gold)
		data.tokens += stage.tokens
		data.renown += stage.renown
		onFoeBeaten(data)
		track(data, "foes", 1)
		local first = ""
		if not data.firstClears[id] then
			data.firstClears[id] = true
			data.crowns += stage.firstCrowns
			data.tokens += stage.firstTokens
			first = ` First clear bonus: +{stage.firstCrowns} Crowns, +{stage.firstTokens} tokens!`
		end
		sendToast(
			player,
			`Stage {stage.index} cleared! {stage.name} is beaten. +{Format.short(stage.gold)} gold, +{stage.xp} XP, +{stage.tokens} boss tokens.{first}`
		)
		addXp(player, data, stage.xp)
		if stage.chest then
			giveGear(player, data, GameConfig.getRarityRank(stage.chest), `{stage.chest} chest from {stage.name}`)
		end
		local set = GameConfig.getHouseSet(stage.house)
		if set and random:NextNumber() < GameConfig.SetDropChance then
			-- Each house's set starts one rarity below its chest.
			local house = nil
			for _, candidate in GameConfig.Houses do
				if candidate.id == stage.house then
					house = candidate
				end
			end
			local minRank = math.max(1, GameConfig.getRarityRank(house and house.chest or "Common") - 1)
			giveGear(player, data, minRank, `{set.name} set piece from {stage.name}`, set)
		end
		return "cleared", damage, 0
	end
	data.stageHealth[id] = health

	roll = random:NextNumber(GameConfig.HitRollMin, GameConfig.HitRollMax)
	local hurt = math.max(1, math.floor(GameConfig.getHit(stage.attack, stats.defense) * roll))
	data.health = math.max(0, data.health - hurt)
	if data.health <= 0 then
		-- Losing sends the foe back to full health.
		data.stageHealth[id] = nil
		countLifetime(data, "knockdowns", 1)
		sendToast(player, `{stage.name} knocked you down and recovered. Rest, grow stronger and try again.`)
		return "down", damage, hurt
	end
	if not quiet then
		sendToast(player, `You hit for {Format.short(damage)}. {stage.name} hits back for {Format.short(hurt)}.`)
	end
	return "hit", damage, hurt
end

-- One attack on a foe stage. id is the stage id ("s1").
function actions.Fight(player: Player, data, id: string)
	local stage = stageById[id]
	if stage and data.level >= stage.level then
		attackStage(player, data, stage, false)
	end
end

-- Several attacks in a row (Attack x5). Stops early when the foe falls, you
-- are knocked down, or you run out of stamina or health.
function actions.FightMany(player: Player, data, id: string)
	local stage = stageById[id]
	if not stage or data.level < stage.level then
		return
	end
	local attacks, dealt, taken = 0, 0, 0
	for _ = 1, GameConfig.MultiAttack do
		local result, damage, hurt = attackStage(player, data, stage, true)
		if not result then
			if attacks == 0 then
				attackStage(player, data, stage, false) -- shows why it could not start
			end
			break
		end
		attacks += 1
		dealt += damage
		taken += hurt
		if result ~= "hit" then
			return -- the clear or the knockdown already has its own message
		end
	end
	if attacks > 0 then
		sendToast(player, `{attacks} attacks on {stage.name}: you dealt {Format.short(dealt)} and took {Format.short(taken)}.`)
	end
end

-- Spends boss tokens in the token shop.
function actions.TokenBuy(player: Player, data, id: string)
	local item = tokenItemById[id]
	if not item then
		return
	end
	if data.tokens < item.cost then
		sendToast(player, `Not enough boss tokens. You need {item.cost}.`)
		return
	end
	if item.kind == "chest" and #data.gear >= maxGear(data) then
		sendToast(player, "Your armory is full. Sell some gear first.")
		return
	end
	data.tokens -= item.cost

	local stats = getStats(data)
	if item.kind == "health" then
		data.health = math.max(data.health, stats.maxHealth)
		sendToast(player, "Health refilled.")
	elseif item.kind == "energy" then
		data.energy = math.max(data.energy, stats.maxEnergy)
		sendToast(player, "Energy refilled.")
	elseif item.kind == "stamina" then
		data.stamina = math.max(data.stamina, stats.maxStamina)
		sendToast(player, "Stamina refilled.")
	elseif item.kind == "xpBoost" then
		data.xpBoostUntil = math.max(data.xpBoostUntil, os.time()) + item.amount * 60
		sendToast(player, `Double experience for {item.amount} more minutes!`)
	elseif item.kind == "skill" then
		data.skillPoints += 1
		sendToast(player, "+1 skill point. Spend it in the Keep.")
	elseif item.kind == "chest" then
		giveGear(player, data, GameConfig.getRarityRank(item.rarity), `{item.name} opened`)
	end
end

-- Puts a piece of gear on someone. id is "<item uid>:<member>", where
-- member 0 is you and 1 and up is a warband slot, for example "i42:0".
function actions.Equip(player: Player, data, id: string)
	local uid, memberText = string.match(id, "^(i%d+):(%d+)$")
	local member = tonumber(memberText)
	if not uid or not member then
		return
	end
	local item = Loadout.findItem(data, uid)
	local before = item and item.wornBy
	local ok, result = Loadout.equip(data, uid, member)
	if not ok then
		sendToast(player, result)
		return
	end
	local who = if member == 0 then "You now wear" else `{memberName(data, member)} now wears`
	local extra = ""
	if before ~= nil and before ~= member then
		extra = ` (taken from {memberName(data, before)})`
	elseif result then
		extra = `. The {result.name} is spare now`
	end
	sendToast(player, `{who} the {item.rarity} {item.name}{extra}.`)
end

-- Takes a piece of gear off. id is the item uid.
function actions.Unequip(player: Player, data, id: string)
	local item = Loadout.findItem(data, id)
	if item and Loadout.unequip(data, id) then
		sendToast(player, `The {item.name} is spare now.`)
	end
end

-- Equip best: hands out every piece by strength. Sets are not considered.
function actions.EquipBest(player: Player, data)
	Loadout.autoEquip(data)
	sendToast(player, "Everyone now wears the strongest gear you own. Set bonuses were not considered.")
end

-- Turns "new gear fills empty slots" on or off.
function actions.EquipNew(player: Player, data, id: string)
	data.autoEquipNew = id == "on"
end

-- Auto quests: "on" or "off". They repeat the last quest you did.
function actions.AutoQuest(player: Player, data, id: string)
	if id == "on" then
		if not hasPass(data, "autoquest") then
			sendToast(player, "Auto quests come with the Quest Herald game pass. Find it in the Shop.")
			return
		end
		if not questById[data.autoQuest] then
			sendToast(player, "Do a quest once first. Auto quests repeat the last quest you did.")
			return
		end
		data.autoQuestOn = true
	elseif id == "off" then
		data.autoQuestOn = false
	end
end

-- Market auto-buy settings. id is one command:
-- on, off, slot:Weapon, rarity:Epic, min:5k, max:2m, broke:wait, broke:stop
function actions.AutoBuy(player: Player, data, id: string)
	local rule = data.autoBuy
	local command, value = string.match(id, "^(%a+):?(.*)$")
	if command == "on" then
		if not hasPass(data, "autobuy") then
			sendToast(player, "Auto-buy comes with the Market Steward game pass. Find it in the Shop.")
			return
		end
		rule.on = true
		sendToast(player, "Auto-buy is running. It buys while you are in the game.")
	elseif command == "off" then
		rule.on = false
	elseif command == "slot" and GameConfig.GearTypes[value] then
		rule.slots[value] = not rule.slots[value]
	elseif command == "rarity" and GameConfig.getRarity(value).id == value then
		rule.minRarity = value
	elseif command == "min" or command == "max" then
		local amount = if value == "" or value == "0" then 0 else Format.parse(value)
		if not amount then
			sendToast(player, "Type a price, like 5000 or 2.5m. Leave it empty for no limit.")
			return
		end
		if command == "min" then
			rule.minPrice = amount
		else
			rule.maxPrice = amount
		end
	elseif command == "broke" and (value == "wait" or value == "stop") then
		rule.whenBroke = value
	end
end

---------------------------------------------------------------------------
-- Shop and Royal Pass
---------------------------------------------------------------------------

-- Hands out one reward (see StoreConfig) and returns words for it.
local function grantReward(player: Player, data, reward, source: string): string
	local kind = reward.kind
	local stats = getStats(data)
	if kind == "crowns" then
		data.crowns += reward.amount
	elseif kind == "gold" then
		-- A fixed `amount`, or `minutes` of holding income (at least a floor).
		local amount = reward.amount
			or math.max(math.floor(stats.incomePerHour / 60 * reward.minutes), StoreConfig.GoldFloorPerLevel * data.level)
		data.gold += amount
		return `{Format.short(amount)} gold`
	elseif kind == "chest" then
		giveGear(player, data, GameConfig.getRarityRank(reward.rarity), `{source}: {reward.rarity} chest`, nil, true)
	elseif kind == "xpBoost" then
		data.xpBoostUntil = math.max(data.xpBoostUntil, os.time()) + reward.minutes * 60
	elseif kind == "skill" then
		data.skillPoints += reward.amount
	elseif kind == "tokens" then
		data.tokens += reward.amount
	elseif kind == "energy" then
		data.energy = math.max(data.energy, stats.maxEnergy)
	elseif kind == "stamina" then
		data.stamina = math.max(data.stamina, stats.maxStamina)
	elseif kind == "health" then
		data.health = math.max(data.health, stats.maxHealth)
	elseif kind == "title" then
		data.title = reward.text
		data.titles[reward.text] = true
	elseif kind == "seals" then
		data.seals += reward.amount
	end
	return StoreConfig.describe(reward)
end

local function grantRewards(player: Player, data, rewards, source: string): string
	local parts = {}
	for _, reward in rewards do
		table.insert(parts, grantReward(player, data, reward, source))
	end
	return table.concat(parts, ", ")
end

---------------------------------------------------------------------------
-- Profile, promo codes, mail, Relic Hall and rebirth
---------------------------------------------------------------------------

-- Picks a title to show before your name. id is the title, or "" for none.
function actions.Title(player: Player, data, id: string)
	if id == "" then
		data.title = ""
	elseif data.titles[id] then
		data.title = id
		sendToast(player, `You are now known as {id} {player.DisplayName}.`)
	end
end

-- Redeems a promo code. id is what the player typed.
function actions.Code(player: Player, data, id: string)
	local entry = ProfileConfig.getCode(id)
	if not entry then
		sendToast(player, "That code does not work. Check the spelling.")
		return
	end
	local key = string.upper(entry.code)
	-- Admin codes only work in Studio and for the game's owner.
	if entry.adminOnly and not RunService:IsStudio() and player.UserId ~= game.CreatorId then
		sendToast(player, "That code does not work. Check the spelling.")
		return
	end
	if data.codes[key] and not entry.repeatable then
		sendToast(player, "You already used that code.")
		return
	end
	if entry.ends > 0 and os.time() > entry.ends then
		sendToast(player, "That code has ended.")
		return
	end
	data.codes[key] = true
	countLifetime(data, "codes", 1)
	local got = grantRewards(player, data, entry.rewards, `Code {key}`)
	sendToast(player, `Code redeemed: {got}.`)
end

-- Claims what is attached to a letter. id is the letter id, or "all".
function actions.MailClaim(player: Player, data, id: string)
	local got = {}
	for _, letter in data.mail do
		if (id == "all" or letter.id == id) and not letter.claimed and letter.rewards then
			letter.claimed = true
			letter.read = true
			table.insert(got, grantRewards(player, data, letter.rewards, letter.title))
		end
	end
	if #got > 0 then
		sendToast(player, `From your mail: {table.concat(got, ", ")}.`)
	end
end

-- Marks a letter as read. id is the letter id, or "all".
function actions.MailRead(player: Player, data, id: string)
	for _, letter in data.mail do
		if id == "all" or letter.id == id then
			letter.read = true
		end
	end
end

-- Throws away a letter with nothing left to claim. id is the letter id, or
-- "read" for every read letter with nothing left to claim.
function actions.MailDelete(player: Player, data, id: string)
	for index = #data.mail, 1, -1 do
		local letter = data.mail[index]
		if letter.claimed and (letter.id == id or (id == "read" and letter.read)) then
			table.remove(data.mail, index)
		end
	end
end

local function addRelicPoints(data, points: number)
	local before = data.relics.points
	data.relics.points += points
	for _, milestone in RelicConfig.Milestones do
		if before < milestone.points and data.relics.points >= milestone.points then
			data.titles[milestone.title] = true
			sendMail(data, "The Relic Hall honours you", `You have earned the title "{milestone.title}". Pick it on your Profile page.`, nil)
		end
	end
end

-- Gives one spare piece of gear to the Relic Hall for good. id is its uid.
function actions.Relic(player: Player, data, id: string)
	for index, item in data.gear do
		if item.uid == id then
			if item.wornBy ~= nil then
				sendToast(player, `Take the {item.name} off {memberName(data, item.wornBy)} first.`)
				return
			end
			table.remove(data.gear, index)
			local points = RelicConfig.getPoints(item)
			data.relics.count += 1
			addRelicPoints(data, points)
			sendToast(player, `The {item.rarity} {item.name} now rests in the Relic Hall: +{points} relic points.`)
			return
		end
	end
end

-- Gives every spare piece of one rarity. Set pieces are never given in
-- bulk. id is the rarity, e.g. "Common".
function actions.RelicBulk(player: Player, data, id: string)
	if GameConfig.getRarity(id).id ~= id then
		return
	end
	local count, points = 0, 0
	for index = #data.gear, 1, -1 do
		local item = data.gear[index]
		if item.rarity == id and item.wornBy == nil and not item.set then
			table.remove(data.gear, index)
			count += 1
			points += RelicConfig.getPoints(item)
		end
	end
	if count == 0 then
		sendToast(player, `You have no spare {id} gear to give. Worn pieces and set pieces are kept.`)
		return
	end
	data.relics.count += count
	addRelicPoints(data, points)
	sendToast(player, `{count} {id} pieces now rest in the Relic Hall: +{points} relic points.`)
end

-- Starts a new life for Stars. id must be "confirm".
function actions.Rebirth(player: Player, data, id: string)
	if id ~= "confirm" then
		return
	end
	local stars = RebirthConfig.getStars(data.level)
	if stars <= 0 then
		sendToast(player, `Rebirth opens at level {RebirthConfig.MinLevel}.`)
		return
	end
	local fromLevel = data.level
	data.rebirth.count += 1
	data.rebirth.stars += stars
	local title = RebirthConfig.getTitle(data.rebirth.count)
	data.titles[title] = true

	-- A new life: see RebirthConfig for what is kept.
	data.level = 1
	data.xp = 0
	data.skillPoints = 0
	data.skills = {}
	data.quests = {}
	data.holdings = {}
	data.keep = 1
	data.banked = 0
	data.gold = GameConfig.StartingGold + RebirthConfig.StartGoldPerStar * data.rebirth.stars
	data.autoQuest = ""
	data.autoQuestOn = false
	data.highestStage = 0
	data.stageHealth = {}
	data.stageCleared = {}
	local stats = getStats(data)
	data.energy = stats.maxEnergy
	data.stamina = stats.maxStamina
	data.health = stats.maxHealth

	sendMail(
		data,
		`Reborn at level {fromLevel}`,
		`You gave up a life at level {fromLevel} for {stars} Stars. You now hold {data.rebirth.stars} Stars and the title "{title}".`,
		nil
	)
	sendToast(player, `You are reborn! +{stars} Stars ({data.rebirth.stars} in all). Your warband, gear and research came with you.`)
end

-- Called by Store once Roblox has taken the Robux (or in a Studio test).
local function grantProduct(player: Player, data, product)
	if product.group == "crowns" then
		data.crowns += product.crowns
		sendToast(player, `+{product.crowns} Crowns. Thank you for supporting the realm!`)
	elseif product.group == "pack" then
		data.packsBought[product.key] = true
		local got = grantRewards(player, data, product.rewards, product.name)
		sendToast(player, `{product.name} opened: {got}.`)
	elseif product.group == "tithe" then
		local amount = data.tithe
		data.crowns += amount
		data.tithe = 0
		sendToast(player, `You broke the Tithe Chest: +{amount} Crowns. It starts filling again.`)
	elseif product.group == "pass" then
		checkPassSeason(data)
		data.pass.noble = true
		sendToast(player, "The Noble track is yours for this season. Claim its rewards on the Royal Pass page.")
	end
end

local function grantPass(player: Player, data, pass)
	data.passes[pass.key] = true
	sendToast(player, `{pass.name} is yours forever: {pass.note}.`)
end

-- Opens a Robux purchase. id is "pass:<key>" or "product:<key>".
function actions.Robux(player: Player, data, id: string)
	local kind, key = string.match(id, "^(%a+):(%w+)$")
	local entry = nil
	if kind == "pass" then
		entry = StoreConfig.getPass(key)
		if entry and hasPass(data, key) then
			sendToast(player, `You already own {entry.name}.`)
			return
		end
	elseif kind == "product" then
		entry = StoreConfig.getProduct(key)
		if not entry then
			return
		end
		if entry.group == "pack" then
			if data.packsBought[key] then
				sendToast(player, `You already bought the {entry.name}.`)
				return
			end
			if entry.level and data.level < entry.level then
				sendToast(player, `The {entry.name} opens at level {entry.level}.`)
				return
			end
			if entry.hours and os.time() > data.firstSeen + entry.hours * 3600 then
				sendToast(player, `The {entry.name} is no longer offered.`)
				return
			end
		elseif entry.group == "tithe" and data.tithe < StoreConfig.TitheMinToBreak then
			sendToast(player, `The Tithe Chest needs {StoreConfig.TitheMinToBreak} Crowns before it can be broken.`)
			return
		elseif entry.group == "pass" then
			checkPassSeason(data)
			if data.pass.noble then
				sendToast(player, "You already have the Noble track this season.")
				return
			end
		end
	end
	if not entry then
		return
	end
	local message = Store.prompt(player, data, kind, entry)
	if message then
		sendToast(player, message)
	end
end

local function spendCrowns(player: Player, data, cost: number): boolean
	if data.crowns < cost then
		sendToast(player, `Not enough Crowns. You need {cost}. Get more at the top of the Shop.`)
		return false
	end
	data.crowns -= cost
	return true
end

-- Buys something in the Crown shop. id is its key.
function actions.CrownBuy(player: Player, data, id: string)
	local item = StoreConfig.getCrownItem(id)
	if item and spendCrowns(player, data, item.cost) then
		local got = grantReward(player, data, item.reward, item.name)
		sendToast(player, `{item.name}: {got}.`)
	end
end

-- Opens a Royal Coffer. id is its key.
function actions.Coffer(player: Player, data, id: string)
	local coffer = StoreConfig.getCoffer(id)
	if not coffer then
		return
	end
	if #data.gear >= maxGear(data) then
		sendToast(player, "Your armory is full. Sell some gear first.")
		return
	end
	if not spendCrowns(player, data, coffer.cost) then
		return
	end

	local pityRank = GameConfig.getRarityRank(coffer.pityRarity)
	local opens = (data.pity[id] or 0) + 1
	local rarityId
	if opens >= coffer.pityEvery then
		rarityId = coffer.pityRarity
	else
		local roll = random:NextNumber(0, 100)
		rarityId = coffer.odds[#coffer.odds][1]
		for _, pair in coffer.odds do
			roll -= pair[2]
			if roll <= 0 then
				rarityId = pair[1]
				break
			end
		end
	end
	data.pity[id] = if GameConfig.getRarityRank(rarityId) >= pityRank then 0 else opens

	local item = Market.rollGearOfRarity(random, data.level, rarityId)
	local note = addGear(data, item)
	sendToast(player, `{coffer.name}: {item.rarity} {item.name}!{note}`)
end

-- Claims Royal Pass rewards. id is a tier number, or "all".
function actions.PassClaim(player: Player, data, id: string)
	checkPassSeason(data)
	local pass = data.pass
	local reached = StoreConfig.getTier(pass.points)
	local first, last = 1, reached
	if id ~= "all" then
		local tier = tonumber(id)
		if not tier or tier < 1 or tier > reached then
			return
		end
		first, last = tier, tier
	end

	local got = {}
	for tier = first, last do
		local key = tostring(tier)
		local rewards = StoreConfig.PassRewards[tier]
		if not pass.claimedFree[key] then
			if rewards.free.kind == "chest" and #data.gear >= maxGear(data) then
				sendToast(player, "Your armory is full. Sell some gear, then claim again.")
				break
			end
			pass.claimedFree[key] = true
			table.insert(got, grantReward(player, data, rewards.free, `Royal Pass tier {tier}`))
		end
		if pass.noble and not pass.claimedNoble[key] then
			if rewards.noble.kind == "chest" and #data.gear >= maxGear(data) then
				sendToast(player, "Your armory is full. Sell some gear, then claim again.")
				break
			end
			pass.claimedNoble[key] = true
			table.insert(got, grantReward(player, data, rewards.noble, `Royal Pass tier {tier}`))
		end
	end
	if #got > 0 then
		sendToast(player, `Royal Pass: {table.concat(got, ", ")}.`)
	end
end

-- Buys one Royal Pass tier with Crowns.
function actions.PassSkip(player: Player, data)
	checkPassSeason(data)
	if StoreConfig.getTier(data.pass.points) >= StoreConfig.PassTiers then
		sendToast(player, "You have reached the last tier.")
		return
	end
	if spendCrowns(player, data, StoreConfig.TierSkipCost) then
		-- Jump to the start of the next tier.
		local nextTier = StoreConfig.getTier(data.pass.points) + 1
		data.pass.points = nextTier * StoreConfig.PointsPerTier
		sendToast(player, `Royal Pass tier {nextTier} reached. Claim its rewards below.`)
	end
end

-- Claims a finished weekly challenge. id is its key.
function actions.WeeklyClaim(player: Player, data, id: string)
	checkWeek(data)
	for _, challenge in StoreConfig.WeeklyChallenges do
		if challenge.key == id then
			if data.weekly.claimed[id] or data.weekly[challenge.stat] < challenge.goal then
				return
			end
			data.weekly.claimed[id] = true
			addPassPoints(data, challenge.points)
			sendToast(player, `Challenge done: +{challenge.points} Royal Pass points.`)
			return
		end
	end
end

---------------------------------------------------------------------------
-- Bounty Board, login streak, Festival Week and research
---------------------------------------------------------------------------

-- Claims a finished bounty task. id is its key.
function actions.BountyClaim(player: Player, data, id: string)
	checkBounty(data)
	local task, period = BountyConfig.getTask(id)
	if not task or data.bounty.claimed[id] then
		return
	end
	local counts = if period == "daily" then data.bounty.daily else data.bounty.weekly
	if (counts[task.stat] or 0) < task.goal then
		return
	end
	data.bounty.claimed[id] = true
	data.seals += task.seals
	sendToast(player, `Bounty done: +{task.seals} Seals.`)
end

-- Buys from the Seal shop. id is the item key.
function actions.SealBuy(player: Player, data, id: string)
	checkBounty(data)
	local item = BountyConfig.getShopItem(id)
	if not item then
		return
	end
	local bought = data.bounty.bought[id] or 0
	if bought >= item.limit then
		sendToast(player, `{item.name} is sold out until Monday.`)
		return
	end
	if data.seals < item.cost then
		sendToast(player, `Not enough Seals. You need {item.cost}. Finish bounties to earn more.`)
		return
	end
	if item.reward.kind == "chest" and #data.gear >= maxGear(data) then
		sendToast(player, "Your armory is full. Sell some gear first.")
		return
	end
	data.seals -= item.cost
	data.bounty.bought[id] = bought + 1
	local got = grantReward(player, data, item.reward, item.name)
	sendToast(player, `{item.name}: {got}.`)
end

function actions.StreakClaim(player: Player, data)
	local day, canClaim = streakToday(data)
	if not canClaim then
		return
	end
	local reward = BountyConfig.Streak[day]
	if reward.kind == "chest" and #data.gear >= maxGear(data) then
		sendToast(player, "Your armory is full. Sell some gear, then claim your streak reward.")
		return
	end
	data.streak.count = day
	data.streak.lastDay = GameConfig.getDay()
	local got = grantReward(player, data, reward, `Day {day} reward`)
	sendToast(player, `Login streak day {day}: {got}. Come back tomorrow for day {day % #BountyConfig.Streak + 1}.`)
end

-- Claims a festival milestone. id is its number in the list, as text.
function actions.FestivalMilestone(player: Player, data, id: string)
	checkFestival(data)
	local index = tonumber(id)
	local milestone = index and FestivalConfig.Milestones[index]
	if not milestone or data.festival.milestones[id] or data.festival.points < milestone.points then
		return
	end
	if milestone.reward.kind == "chest" and #data.gear >= maxGear(data) then
		sendToast(player, "Your armory is full. Sell some gear first.")
		return
	end
	data.festival.milestones[id] = true
	local got = grantReward(player, data, milestone.reward, "Festival milestone")
	sendToast(player, `Festival milestone: {got}.`)
end

-- Starts researching the next level of a tech. id is its key.
function actions.Research(player: Player, data, id: string)
	local tech = ResearchConfig.Techs[id]
	if not tech then
		return
	end
	local research = data.research
	if research.active ~= "" then
		sendToast(player, "The scholars are busy. Wait for the current research, or finish it with Crowns.")
		return
	end
	local level = research.levels[id] or 0
	if level >= tech.maxLevel then
		return
	end
	if tech.needs and (research.levels[tech.needs[1]] or 0) < tech.needs[2] then
		local need = ResearchConfig.Techs[tech.needs[1]]
		sendToast(player, `Research {need and need.name or tech.needs[1]} to level {tech.needs[2]} first.`)
		return
	end
	if spendGold(player, data, ResearchConfig.getCost(tech, level)) then
		research.active = id
		research.endsAt = os.time() + ResearchConfig.getSeconds(tech, level)
		sendToast(player, `The scholars began {tech.name} level {level + 1}.`)
	end
end

-- Finishes research when its time is up. Runs every second and on join.
local function checkResearch(player: Player, data)
	local research = data.research
	if research.active == "" or os.time() < research.endsAt then
		return
	end
	local tech = ResearchConfig.Techs[research.active]
	research.active = ""
	research.endsAt = 0
	if tech then
		local level = (research.levels[tech.key] or 0) + 1
		research.levels[tech.key] = level
		sendToast(player, `Research done: {tech.name} level {level} ({ResearchConfig.describe(tech, level)} in total).`)
	end
end

-- Finishes the current research now for Crowns.
function actions.ResearchFinish(player: Player, data)
	local research = data.research
	if research.active == "" then
		return
	end
	local cost = ResearchConfig.getFinishCost(math.max(0, research.endsAt - os.time()))
	if spendCrowns(player, data, cost) then
		research.endsAt = os.time()
		checkResearch(player, data)
	end
end

---------------------------------------------------------------------------
-- Festival leaderboard, shared by every server through an OrderedDataStore
---------------------------------------------------------------------------

local nameCache = {}

local function festivalStore(week: number)
	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore("Festival_" .. week)
	end)
	return if ok then store else nil
end

local function nameFor(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	nameCache[userId] = if ok then name else "Someone"
	return nameCache[userId]
end

-- Writes a player's festival points for this week.
local function saveFestivalScore(player: Player, data)
	if data.festival.points <= 0 then
		return
	end
	local store = festivalStore(data.festival.week)
	if store then
		pcall(function()
			store:SetAsync(tostring(player.UserId), math.floor(data.festival.points))
		end)
	end
end

local function refreshFestivalTop()
	local week = FestivalConfig.getWeek(os.time())
	local store = festivalStore(week)
	if not store then
		return
	end
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, FestivalConfig.LeaderboardSize)
	end)
	if not ok then
		return
	end
	local list = {}
	for _, entry in pages:GetCurrentPage() do
		table.insert(list, { nameFor(tonumber(entry.key) or 0), entry.value })
	end
	festivalTop = list
	festivalTopWeek = week
end

-- Pays last week's rank reward once. Finds the rank in the top 100.
local function payFestivalRank(player: Player, data)
	local festival = data.festival
	if festival.lastPaid or festival.lastPoints <= 0 then
		return
	end
	local store = festivalStore(festival.lastWeek)
	if not store then
		return
	end
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, 100)
	end)
	if not ok then
		return -- try again on the next visit
	end
	local rank = nil
	for index, entry in pages:GetCurrentPage() do
		if entry.key == tostring(player.UserId) then
			rank = index
			break
		end
	end
	if not player.Parent or festival.lastPaid then
		return
	end
	festival.lastPaid = true
	if not rank and festival.lastPoints < FestivalConfig.MinPointsForReward then
		return
	end
	local entry = FestivalConfig.getRankReward(rank or math.huge)
	local name = FestivalConfig.getFestival(festival.lastWeek).name
	local place = if rank then `#{rank}` else entry.label
	sendMail(data, `{name}: you placed {place}`, `Thank you for taking part in last week's {name}. Your reward is attached.`, entry.rewards)
	sendToast(player, `Last week's {name}: you placed {place}. Your reward is waiting in your Mail.`)
end

---------------------------------------------------------------------------
-- Rankings: all-time boards shared by every server
---------------------------------------------------------------------------

local function boardStore(key: string)
	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore("Rank_" .. key)
	end)
	return if ok then store else nil
end

local function boardScore(data, key: string, stats): number
	if key == "power" then
		return stats.attack + stats.defense
	elseif key == "level" then
		return data.level
	elseif key == "renown" then
		return data.renown
	elseif key == "rebirths" then
		return data.rebirth.count
	end
	return 0
end

-- Writes a player's scores, skipping any that did not change.
local function saveBoardScores(player: Player, session)
	local data = session.data
	local stats = getStats(data)
	for _, board in ProfileConfig.Boards do
		local score = math.floor(boardScore(data, board.key, stats))
		local store = score > 0 and session.boardSent[board.key] ~= score and boardStore(board.key)
		if store then
			local ok = pcall(function()
				store:SetAsync(tostring(player.UserId), score)
			end)
			if ok then
				session.boardSent[board.key] = score
			end
		end
	end
end

local function refreshBoards()
	for _, board in ProfileConfig.Boards do
		local store = boardStore(board.key)
		if store then
			local ok, pages = pcall(function()
				return store:GetSortedAsync(false, ProfileConfig.BoardSize)
			end)
			if ok then
				local list = {}
				for _, entry in pages:GetCurrentPage() do
					table.insert(list, { nameFor(tonumber(entry.key) or 0), entry.value })
				end
				boardTops[board.key] = list
			end
		end
	end
end

-- Hides a page's tip for good. id is the page name.
function actions.Tip(player: Player, data, id: string)
	-- The client names the page, so keep the list small and the names short.
	local count = 0
	for _ in data.tipsSeen do
		count += 1
	end
	if #id > 0 and #id <= 20 and count < 30 then
		data.tipsSeen[id] = true
	end
end

local function runAutoQuests(player: Player, data)
	local quest = questById[data.autoQuest]
	if not data.autoQuestOn or not quest or not hasPass(data, "autoquest") then
		return
	end
	for _ = 1, GameConfig.AutoQuestsPerSecond do
		if data.energy < quest.energy then
			return
		end
		actions.Quest(player, data, quest.id)
	end
end

local function runAutoBuy(player: Player, data)
	local rule = data.autoBuy
	if not rule.on or not hasPass(data, "autobuy") then
		return
	end
	restockIfDue(player, data)
	local minRank = GameConfig.getRarityRank(rule.minRarity)
	for _, item in data.market.items do
		local wanted = not item.sold
			and rule.slots[item.slot]
			and GameConfig.getRarityRank(item.rarity) >= minRank
			and marketPrice(item) >= rule.minPrice
			and (rule.maxPrice <= 0 or marketPrice(item) <= rule.maxPrice)
			and data.level >= item.level
		if not wanted then
			continue
		end
		if #data.gear >= maxGear(data) then
			rule.on = false
			sendToast(player, "Auto-buy stopped: your armory is full.")
			return
		end
		if data.gold < marketPrice(item) then
			if rule.whenBroke == "stop" then
				rule.on = false
				sendToast(player, "Auto-buy stopped: not enough gold.")
				return
			end
			continue
		end
		if buyItem(player, data, item, true) then
			rule.bought += 1
			rule.spent += marketPrice(item)
			table.insert(rule.recent, 1, { name = item.name, rarity = item.rarity, price = marketPrice(item) })
			while #rule.recent > GameConfig.AutoBuyRecent do
				table.remove(rule.recent)
			end
		end
	end
end

actionRemote.OnServerEvent:Connect(function(player: Player, action, id)
	local session = sessions[player]
	if not session or type(action) ~= "string" then
		return
	end
	if id ~= nil and (type(id) ~= "string" or #id > 64) then
		return
	end

	-- Ignore floods of requests (auto-clickers or exploits).
	session.actionCount += 1
	if session.actionCount > MAX_ACTIONS_PER_SECOND then
		return
	end

	local handler = actions[action]
	if handler then
		handler(player, session.data, id or "")
		refresh(player)
	end
end)

---------------------------------------------------------------------------
-- Joining and leaving
---------------------------------------------------------------------------

-- What the player earned and regained while they were away.
local function applyTimeAway(player: Player, data)
	if data.lastSeen <= 0 then
		return
	end
	local seconds = math.max(0, os.time() - data.lastSeen)
	local stats = getStats(data)

	local speed = if hasPass(data, "couriers") then StoreConfig.CouriersSpeed else 1
	local regenSeconds = seconds * speed
	data.energy = math.max(data.energy, math.min(stats.maxEnergy, data.energy + math.floor(regenSeconds / GameConfig.EnergyRegenSeconds)))
	data.stamina = math.max(data.stamina, math.min(stats.maxStamina, data.stamina + math.floor(regenSeconds / GameConfig.StaminaRegenSeconds)))
	data.health = math.max(data.health, math.min(stats.maxHealth, data.health + math.floor(regenSeconds / GameConfig.HealthRegenSeconds)))

	local nightWatch = hasPass(data, "nightwatch")
	local maxSeconds = if nightWatch then StoreConfig.NightWatchHours * 3600 else GameConfig.OfflineMaxSeconds
	local rate = if nightWatch then StoreConfig.NightWatchRate else GameConfig.OfflineRate
	local paidSeconds = math.min(seconds, maxSeconds)
	local earned = math.floor(stats.incomePerHour / 3600 * paidSeconds * rate)
	if earned > 0 then
		data.gold += earned
		countLifetime(data, "goldEarned", earned)
		player:SetAttribute("OfflineGold", earned)
	end
end

local function onPlayerAdded(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local levelStat = Instance.new("IntValue")
	levelStat.Name = "Level"
	levelStat.Value = 1
	levelStat.Parent = leaderstats
	local renownStat = Instance.new("IntValue")
	renownStat.Name = "Renown"
	renownStat.Parent = leaderstats
	leaderstats.Parent = player

	local data, canSave = PlayerData.load(player)
	if not player.Parent then
		return -- left while loading
	end
	if not canSave and not RunService:IsStudio() then
		sendToast(player, "Could not load your save. Progress in this visit will not be kept.")
	end

	-- Saves from before manual equipping: dress everyone in their best gear
	-- once, so nobody's stats drop.
	if not data.equipReady then
		Loadout.autoEquip(data)
		data.equipReady = true
	end
	Loadout.tidy(data)

	if data.firstSeen <= 0 then
		data.firstSeen = os.time()
	end
	Store.checkPasses(player, data)
	if not player.Parent then
		return -- left while passes were checked
	end

	applyTimeAway(player, data)
	checkResearch(player, data)

	-- Saves from before titles, first clears and mail.
	if data.title ~= "" then
		data.titles[data.title] = true
	end
	if next(data.firstClears) == nil then
		for _, stage in GameConfig.Stages do
			if stage.index <= data.highestStage then
				data.firstClears[stage.id] = true
			end
		end
	end
	for _, news in ProfileConfig.News do
		if not data.newsSeen[news.id] then
			data.newsSeen[news.id] = true
			sendMail(data, news.title, news.text, news.rewards)
		end
	end

	sessions[player] = {
		data = data,
		canSave = canSave,
		actionCount = 0,
		regen = { energy = 0, stamina = 0, health = 0 },
		boardSent = {}, -- [board key] = last score written
	}
	refresh(player)

	-- Last week's festival rank reward, if it has not been paid yet.
	checkFestival(data)
	task.spawn(function()
		payFestivalRank(player, data)
		if sessions[player] then
			refresh(player)
		end
	end)
end

local function onPlayerRemoving(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	sessions[player] = nil
	if session.canSave then
		PlayerData.save(player, session.data)
		saveFestivalScore(player, session.data)
		saveBoardScores(player, session)
	end
end

Store.init({
	getSession = function(player: Player)
		return sessions[player]
	end,
	grantProduct = grantProduct,
	grantPass = grantPass,
	refresh = refresh,
})

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

-- Save everyone when the server shuts down.
game:BindToClose(function()
	for player, session in sessions do
		if session.canSave then
			task.spawn(PlayerData.save, player, session.data)
		end
	end
	task.wait(2)
end)

---------------------------------------------------------------------------
-- The idle loop: once a second, holdings pay out and bars refill
---------------------------------------------------------------------------

-- Adds one point to a bar every `seconds` ticks, up to its maximum.
-- Swift Couriers counts two ticks a second, so bars refill twice as fast.
local function regenerate(session, key: string, seconds: number, maximum: number)
	local data = session.data
	if data[key] >= maximum then
		session.regen[key] = 0
		return
	end
	session.regen[key] += if hasPass(data, "couriers") then StoreConfig.CouriersSpeed else 1
	if session.regen[key] >= seconds then
		session.regen[key] -= seconds
		data[key] += 1
	end
end

task.spawn(function()
	while true do
		task.wait(1)
		for player, session in sessions do
			session.actionCount = 0
			local data = session.data
			local stats = getStats(data)

			checkNewDay(data)
			data.playSeconds += 1
			checkWeek(data)
			data.weekly.play += 1
			data.gold += stats.incomePerHour / 3600
			countLifetime(data, "goldEarned", stats.incomePerHour / 3600)
			countLifetime(data, "playSeconds", 1)
			regenerate(session, "energy", GameConfig.EnergyRegenSeconds, stats.maxEnergy)
			regenerate(session, "stamina", GameConfig.StaminaRegenSeconds, stats.maxStamina)
			regenerate(session, "health", GameConfig.HealthRegenSeconds, stats.maxHealth)
			runAutoQuests(player, data)
			runAutoBuy(player, data)
			checkResearch(player, data)

			refresh(player)
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_SECONDS)
		for player, session in sessions do
			if session.canSave then
				task.spawn(PlayerData.save, player, session.data)
				task.spawn(saveFestivalScore, player, session.data)
			end
		end
		refreshFestivalTop()
	end
end)

task.spawn(refreshFestivalTop)

-- Ranking boards: write scores and read the top of each board.
task.spawn(function()
	refreshBoards()
	while true do
		task.wait(ProfileConfig.BoardSeconds)
		for player, session in sessions do
			if session.canSave then
				task.spawn(saveBoardScores, player, session)
			end
		end
		refreshBoards()
	end
end)

print(`[{GameConfig.GameName}] server started`)
