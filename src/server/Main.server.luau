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
local soldierById = indexById(GameConfig.Soldiers)
local gearById = indexById(GameConfig.Gear)
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

-- Attack and defense from the best gear, one piece per slot for you and
-- for each soldier.
local function getGearBonus(data): (number, number)
	local members = 1 + #data.soldiers
	local attack, defense = 0, 0

	for _, slot in GameConfig.GearSlots do
		local pieces = {}
		for _, gear in GameConfig.Gear do
			if gear.slot == slot then
				for _ = 1, math.min(data.gear[gear.id] or 0, members) do
					table.insert(pieces, gear)
				end
			end
		end
		table.sort(pieces, function(a, b)
			return a.attack + a.defense > b.attack + b.defense
		end)
		for index = 1, math.min(#pieces, members) do
			attack += pieces[index].attack
			defense += pieces[index].defense
		end
	end

	return attack, defense
end

local function getStats(data)
	local attack = GameConfig.BaseAttack + skillTotal(data, "attack")
	local defense = GameConfig.BaseDefense + skillTotal(data, "defense")

	for _, soldierId in data.soldiers do
		local soldier = soldierById[soldierId]
		if soldier then
			attack += soldier.attack
			defense += soldier.defense
		end
	end

	local gearAttack, gearDefense = getGearBonus(data)

	local incomePerHour = 0
	local holdingsOwned = 0
	for _, holding in GameConfig.Holdings do
		local level = data.holdings[holding.id] or 0
		if level > 0 then
			holdingsOwned += 1
			incomePerHour += GameConfig.getHoldingIncome(holding, level)
		end
	end

	return {
		maxEnergy = GameConfig.BaseMaxEnergy + skillTotal(data, "energy"),
		maxStamina = GameConfig.BaseMaxStamina + skillTotal(data, "stamina"),
		maxHealth = GameConfig.BaseMaxHealth + skillTotal(data, "health"),
		attack = attack + gearAttack,
		defense = defense + gearDefense,
		holdingSlots = GameConfig.BaseHoldingSlots + skillTotal(data, "slots"),
		holdingsOwned = holdingsOwned,
		incomePerHour = incomePerHour,
	}
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
		soldierSlots = data.soldierSlots,
		soldiers = data.soldiers,
		gear = data.gear,
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

---------------------------------------------------------------------------
-- Player actions
---------------------------------------------------------------------------

local actions = {}

function actions.Quest(player: Player, data, id: string)
	local quest = questById[id]
	if not quest or data.level < quest.level then
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

	if GameConfig.getMasteryRank(completions + 1) > rankBefore then
		sendToast(player, `Mastery rank up! {quest.name} now pays more gold.`)
	end
	addXp(player, data, quest.xp)
end

function actions.Holding(player: Player, data, id: string)
	local holding = holdingById[id]
	if not holding or data.level < holding.level then
		return
	end

	local level = data.holdings[id] or 0
	if level >= GameConfig.HoldingMaxLevel then
		return
	end
	if level == 0 then
		local stats = getStats(data)
		if stats.holdingsOwned >= stats.holdingSlots then
			sendToast(player, "No free holding slot. Spend skill points on Holding Slots.")
			return
		end
	end

	if spendGold(player, data, GameConfig.getHoldingCost(holding, level)) then
		data.holdings[id] = level + 1
		if level == 0 then
			sendToast(player, `You now own the {holding.name}.`)
		end
	end
end

function actions.Skill(player: Player, data, id: string)
	local skill = skillById[id]
	if not skill then
		return
	end
	if data.skillPoints < skill.cost then
		sendToast(player, "Not enough skill points. Level up to earn more.")
		return
	end

	data.skillPoints -= skill.cost
	data.skills[id] = (data.skills[id] or 0) + 1

	-- Raising a maximum also hands over the new points right away.
	if id == "energy" or id == "stamina" or id == "health" then
		data[id] += skill.amount
	end
end

function actions.Slot(player: Player, data)
	if data.soldierSlots >= GameConfig.MaxSoldierSlots then
		return
	end
	if spendGold(player, data, GameConfig.getSlotCost(data.soldierSlots)) then
		data.soldierSlots += 1
	end
end

function actions.Hire(player: Player, data, id: string)
	local soldier = soldierById[id]
	if not soldier then
		return
	end

	-- With a full warband, the new soldier replaces the weakest one.
	local replaceIndex = nil
	if #data.soldiers >= data.soldierSlots then
		local weakestPower = math.huge
		for index, soldierId in data.soldiers do
			local other = soldierById[soldierId]
			local power = if other then other.attack + other.defense else 0
			if power < weakestPower then
				weakestPower = power
				replaceIndex = index
			end
		end
		if not replaceIndex or weakestPower >= soldier.attack + soldier.defense then
			sendToast(player, "Your warband is full. Unlock another slot first.")
			return
		end
	end

	if spendGold(player, data, soldier.cost) then
		if replaceIndex then
			data.soldiers[replaceIndex] = id
			sendToast(player, `A {soldier.name} replaced your weakest soldier.`)
		else
			table.insert(data.soldiers, id)
			sendToast(player, `A {soldier.name} joined your warband.`)
		end
	end
end

function actions.Gear(player: Player, data, id: string)
	local gear = gearById[id]
	if not gear then
		return
	end
	if spendGold(player, data, gear.cost) then
		data.gear[id] = (data.gear[id] or 0) + 1
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
	if id ~= nil and type(id) ~= "string" then
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
