-- Server entry point: runs every rule of the game.
-- The game is played entirely through menus. The client sends a request on
-- the Action remote ("do this quest", "buy this holding"), the server checks
-- it and changes the player's data, then sends the new state back.
-- Never trust numbers from the client: everything is worked out here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Format = require(ReplicatedStorage.Shared.Format)
local Market = require(script.Parent.Market)
local Recruit = require(script.Parent.Recruit)
local PlayerData = require(script.Parent.PlayerData)

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
local foeById = indexById(GameConfig.Foes)

---------------------------------------------------------------------------
-- Working out a player's numbers
---------------------------------------------------------------------------

local function sendToast(player: Player, text: string)
	player:SetAttribute("ToastText", text)
	player:SetAttribute("ToastId", (player:GetAttribute("ToastId") or 0) + 1)
end

local function skillTotal(data, skillId: string): number
	return (data.skills[skillId] or 0) * skillById[skillId].amount
end

local function itemPower(item): number
	return item.attack + item.defense
end

-- Soldiers currently in the warband, with the slot each is in.
local function filledSlots(data)
	local list = {}
	for slot, soldier in data.crew do
		if soldier then
			table.insert(list, { slot = slot, soldier = soldier })
		end
	end
	return list
end

-- Hands out gear automatically: in each gear slot, the best piece goes to
-- you, the next best to your strongest soldier, and so on.
-- Returns attack and defense from gear, the set of item ids in use, and
-- what each member wears: wearing[0] is you, wearing[slot] is a soldier.
local function assignGear(data): (number, number, { [string]: boolean }, { [number]: { [string]: any } })
	local members = { 0 }
	local filled = filledSlots(data)
	table.sort(filled, function(a, b)
		local aAttack, aDefense = GameConfig.getSoldierStats(a.soldier)
		local bAttack, bDefense = GameConfig.getSoldierStats(b.soldier)
		return aAttack + aDefense > bAttack + bDefense
	end)
	for _, entry in filled do
		table.insert(members, entry.slot)
	end

	local attack, defense = 0, 0
	local used = {}
	local wearing = {}
	for _, member in members do
		wearing[member] = {}
	end

	for _, gearSlot in GameConfig.GearSlots do
		local pieces = {}
		for _, item in data.gear do
			if item.slot == gearSlot then
				table.insert(pieces, item)
			end
		end
		table.sort(pieces, function(a, b)
			return itemPower(a) > itemPower(b)
		end)
		for index, member in members do
			local piece = pieces[index]
			if piece then
				attack += piece.attack
				defense += piece.defense
				used[piece.uid] = true
				wearing[member][gearSlot] = piece
			end
		end
	end

	return attack, defense, used, wearing
end

local function getKeepBonus(data): number
	local keep = GameConfig.KeepLevels[data.keep] or GameConfig.KeepLevels[1]
	return keep.bonus
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

	local gearAttack, gearDefense = assignGear(data)
	local crewBonus = crewSize * GameConfig.CrewSizeBonus
	local keepBonus = getKeepBonus(data)

	local rawAttack = baseAttack + crewAttack + gearAttack
	local rawDefense = baseDefense + crewDefense + gearDefense
	local attack = math.floor(rawAttack * (1 + crewBonus + keepBonus))
	local defense = math.floor(rawDefense * (1 + crewBonus + keepBonus))

	local incomePerHour = 0
	local lotsUsed = 0
	for _, holding in GameConfig.Holdings do
		local count = data.holdings[holding.id] or 0
		lotsUsed += count
		incomePerHour += holding.income * count
	end
	incomePerHour = math.floor(incomePerHour * (1 + keepBonus))

	return {
		maxEnergy = GameConfig.BaseMaxEnergy + skillTotal(data, "energy"),
		maxStamina = GameConfig.BaseMaxStamina + skillTotal(data, "stamina"),
		maxHealth = GameConfig.BaseMaxHealth + skillTotal(data, "health"),
		attack = attack,
		defense = defense,
		crewSize = crewSize,
		crewBonus = crewBonus,
		keepBonus = keepBonus,
		lots = GameConfig.BaseLots + skillTotal(data, "lots"),
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

-- Sends the player everything their menus need to draw.
local function refresh(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	local data = session.data
	local stats = getStats(data)
	local now = os.time()

	-- Restock the Market when a new window starts.
	local window = Market.currentWindow()
	if data.market.window ~= window then
		data.market = Market.roll(player.UserId, window, data.level)
	end
	local _, _, gearInUse, wearing = assignGear(data)

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

	local foes = {}
	for _, foe in GameConfig.Foes do
		local record = data.foes[foe.id]
		foes[foe.id] = {
			health = if record then record.health else foe.health,
			wait = if record then math.max(0, record.readyAt - now) else 0,
		}
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
		market = data.market.items,
		marketRestock = Market.secondsUntilRestock(),
		foes = foes,
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

-- Gives the player a rolled piece of gear (quest drops and chests).
local function giveGear(player: Player, data, minRank: number?, source: string)
	if #data.gear >= GameConfig.MaxGearOwned then
		sendToast(player, `{source}, but your armory is full. Sell some gear to make room.`)
		return
	end
	local item = Market.rollGear(random, data.level, minRank)
	item.uid = "i" .. data.nextItemId
	data.nextItemId += 1
	table.insert(data.gear, item)
	sendToast(player, `{source}: {item.rarity} {item.name}!`)
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

	data.energy -= quest.energy
	data.gold += GameConfig.getQuestGold(quest, completions)
	data.quests[id] = completions + 1

	local rankAfter = GameConfig.getMasteryRank(completions + 1)
	if rankAfter > rankBefore then
		sendToast(player, `{GameConfig.MasteryMedals[rankAfter]} mastery! {quest.name} now pays more gold.`)
	end
	if random:NextNumber() < quest.drop then
		giveGear(player, data, nil, "You found gear")
	end
	addXp(player, data, quest.xp)
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
	local fee = math.ceil(amount * GameConfig.BankFee)
	data.gold -= amount
	data.banked += amount - fee
	sendToast(player, `Deposited {Format.short(amount - fee)} gold after a {Format.short(fee)} fee.`)
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
	if data.gold < tier.cost then
		sendToast(player, `Not enough gold. One {tier.id} roll costs {Format.short(tier.cost)}.`)
		return
	end

	local rolls, filled, best = 0, 0, nil
	for _, slot in targets do
		while rolls < GameConfig.MaxRollsPerRequest and data.gold >= tier.cost do
			data.gold -= tier.cost
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

	local spent = Format.short(rolls * tier.cost)
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
	end
end

-- Dismisses the soldier in a slot. The slot stays unlocked and empty.
function actions.Release(player: Player, data, id: string)
	local slot = tonumber(id)
	local soldier = slot and data.crew[slot]
	if soldier then
		data.crew[slot] = false
		sendToast(player, `{soldier.name} left the warband.`)
	end
end

-- Buys item number `id` ("1" to "8") from the Market.
function actions.Buy(player: Player, data, id: string)
	local index = tonumber(id)
	local item = index and data.market.items[index]
	if not item or item.sold then
		return
	end
	if data.level < item.level then
		sendToast(player, `You need level {item.level} to buy this.`)
		return
	end
	if #data.gear >= GameConfig.MaxGearOwned then
		sendToast(player, "Your armory is full. Sell some gear first.")
		return
	end
	if not spendGold(player, data, item.price) then
		return
	end

	item.sold = true
	local owned = table.clone(item)
	owned.sold = nil
	owned.uid = "i" .. data.nextItemId
	data.nextItemId += 1

	table.insert(data.gear, owned)
	sendToast(player, `You bought a {owned.rarity} {owned.name}.`)
end

-- Sells a piece of gear for part of its price.
function actions.Sell(player: Player, data, id: string)
	for index, item in data.gear do
		if item.uid == id then
			table.remove(data.gear, index)
			local refund = math.floor(item.price * GameConfig.SellShare)
			data.gold += refund
			sendToast(player, `Sold {item.rarity} {item.name} for {Format.short(refund)} gold.`)
			return
		end
	end
end

function actions.Fight(player: Player, data, id: string)
	local foe = foeById[id]
	if not foe or data.level < foe.level then
		return
	end

	local now = os.time()
	local record = data.foes[id]
	if not record then
		record = { health = foe.health, readyAt = 0 }
		data.foes[id] = record
	end

	if record.readyAt > now then
		sendToast(player, `{foe.name} is in hiding. Come back later.`)
		return
	end
	if data.stamina < 1 then
		sendToast(player, "Not enough stamina. It refills over time.")
		return
	end
	if data.health < GameConfig.MinHealthToFight then
		sendToast(player, `You are too wounded. Rest until you have {GameConfig.MinHealthToFight} health.`)
		return
	end

	local stats = getStats(data)
	data.stamina -= 1

	local damage = math.max(1, math.floor((stats.attack - foe.defense * 0.5) * random:NextNumber(0.85, 1.15)))
	record.health -= damage

	if record.health <= 0 then
		record.health = foe.health
		record.readyAt = now + GameConfig.FoeCooldownSeconds
		data.gold += foe.gold
		data.renown += foe.renown
		sendToast(player, `{foe.name} is defeated! +{Format.short(foe.gold)} gold, +{foe.xp} XP, +{foe.renown} renown.`)
		addXp(player, data, foe.xp)
		return
	end

	local hurt = math.max(1, math.floor((foe.attack - stats.defense * 0.5) * random:NextNumber(0.85, 1.15)))
	data.health = math.max(0, data.health - hurt)
	sendToast(player, `You hit for {damage}. {foe.name} hits back for {hurt}.`)
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

	data.energy = math.max(data.energy, math.min(stats.maxEnergy, data.energy + math.floor(seconds / GameConfig.EnergyRegenSeconds)))
	data.stamina = math.max(data.stamina, math.min(stats.maxStamina, data.stamina + math.floor(seconds / GameConfig.StaminaRegenSeconds)))
	data.health = math.max(data.health, math.min(stats.maxHealth, data.health + math.floor(seconds / GameConfig.HealthRegenSeconds)))

	local paidSeconds = math.min(seconds, GameConfig.OfflineMaxSeconds)
	local earned = math.floor(stats.incomePerHour / 3600 * paidSeconds * GameConfig.OfflineRate)
	if earned > 0 then
		data.gold += earned
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

	applyTimeAway(player, data)

	sessions[player] = {
		data = data,
		canSave = canSave,
		actionCount = 0,
		regen = { energy = 0, stamina = 0, health = 0 },
	}
	refresh(player)
end

local function onPlayerRemoving(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	sessions[player] = nil
	if session.canSave then
		PlayerData.save(player, session.data)
	end
end

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
local function regenerate(session, key: string, seconds: number, maximum: number)
	local data = session.data
	if data[key] >= maximum then
		session.regen[key] = 0
		return
	end
	session.regen[key] += 1
	if session.regen[key] >= seconds then
		session.regen[key] = 0
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
			data.gold += stats.incomePerHour / 3600
			regenerate(session, "energy", GameConfig.EnergyRegenSeconds, stats.maxEnergy)
			regenerate(session, "stamina", GameConfig.StaminaRegenSeconds, stats.maxStamina)
			regenerate(session, "health", GameConfig.HealthRegenSeconds, stats.maxHealth)

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
			end
		end
	end
end)

print(`[{GameConfig.GameName}] server started`)
