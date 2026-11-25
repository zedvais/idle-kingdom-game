-- Loads and saves each player's progress with Roblox DataStores.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local PlayerData = {}

-- Change this name to wipe everyone's progress (useful during testing).
local STORE_NAME = "IdleKingdom_v5"

local store = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[PlayerData] DataStore is not available:", result)
	end
end

local function keyFor(player: Player): string
	return "player_" .. player.UserId
end

local function newData()
	return {
		gold = GameConfig.StartingGold,
		level = 1,
		xp = 0,
		skillPoints = 0,
		renown = 0,
		energy = GameConfig.BaseMaxEnergy,
		stamina = GameConfig.BaseMaxStamina,
		health = GameConfig.BaseMaxHealth,
		skills = {}, -- [skillId] = times bought
		quests = {}, -- [questId] = times completed
		holdings = {}, -- [holdingId] = how many copies are built
		keep = 1, -- index into GameConfig.KeepLevels
		banked = 0,
		playDay = 0, -- which day playSeconds counts for
		playSeconds = 0,
		claimed = {}, -- [reward index as text] = true, for today
		xpBoostUntil = 0,
		-- One entry per unlocked warband slot: a soldier table, or false
		-- when the slot is empty.
		crew = { false },
		gear = {}, -- list of owned gear items; item.wornBy is who wears it
		equipReady = false, -- true once old saves got their first loadout
		autoEquipNew = true, -- new gear goes onto an empty slot
		nextItemId = 1,
		market = { window = -1, items = {} },
		tokens = 0, -- boss tokens
		highestStage = 0, -- highest foe stage ever beaten
		stageDay = 0, -- the UTC day the two tables below belong to
		stageHealth = {}, -- ["s3"] = health a stage has left today
		stageCleared = {}, -- ["s3"] = true once beaten today
		trophies = {}, -- [trophyId] = true once earned
		autoQuest = "", -- quest id that auto quests repeat
		autoQuestOn = false,
		autoBuy = {
			on = false,
			slots = { Weapon = true, Armor = true, Mount = true },
			minRarity = "Rare",
			minPrice = 0,
			maxPrice = 0, -- 0 means no limit
			whenBroke = "wait", -- "wait" for more gold or "stop" auto-buy
			bought = 0,
			spent = 0,
			recent = {}, -- newest first: { name, rarity, price }
		},
		-- Shop and Royal Pass
		crowns = 0,
		passes = {}, -- [pass key] = true for each game pass owned
		receipts = {}, -- recent Robux purchase ids, newest first
		packsBought = {}, -- [product key] = true for one-time packs
		title = "", -- shown before your name, e.g. "Founder"
		firstSeen = 0, -- os.time() of the first visit
		tithe = 0, -- Crowns waiting in the Tithe Chest
		titheEnergy = 0, -- quest energy not yet turned into a Crown
		pity = {}, -- [coffer key] = opens since its pity rarity last came up
		pass = {
			season = -1, -- which season the fields below belong to
			points = 0,
			noble = false, -- premium track bought for this season
			energyCarry = 0, -- quest energy not yet turned into a point
			claimedFree = {}, -- [tier as text] = true
			claimedNoble = {},
		},
		weekly = {
			week = -1,
			energy = 0,
			foes = 0,
			market = 0,
			play = 0,
			claimed = {}, -- [challenge key] = true
		},
		tipsSeen = {}, -- [page name] = true once its tip is dismissed
		-- Bounty Board, login streak, Festival Week and research
		seals = 0,
		bounty = {
			day = -1, -- UTC day the daily counts belong to
			week = -1, -- week the weekly counts belong to
			daily = {}, -- [stat] = count today
			weekly = {}, -- [stat] = count this week
			claimed = {}, -- [task key] = true (daily keys reset daily, weekly keys weekly)
			shopWeek = -1,
			bought = {}, -- [Seal shop key] = bought this week
		},
		streak = { count = 0, lastDay = -1 },
		festival = {
			week = -1,
			points = 0,
			milestones = {}, -- [milestone index as text] = true
			lastWeek = -1, -- the finished week waiting for its rank reward
			lastPoints = 0,
			lastPaid = true,
		},
		research = {
			levels = {}, -- [tech key] = level
			active = "", -- tech being researched, "" for none
			endsAt = 0,
		},
		lastSeen = 0,
	}
end

-- Fills in anything missing or broken so old saves keep working when the
-- game changes.
local function repair(data)
	local fresh = newData()
	if type(data) ~= "table" then
		return fresh
	end
	for key, default in fresh do
		if type(data[key]) ~= type(default) then
			data[key] = default
		end
	end
	-- Settings tables get any new fields too.
	for _, name in { "autoBuy", "pass", "weekly", "bounty", "streak", "festival", "research" } do
		for key, default in fresh[name] do
			if type(data[name][key]) ~= type(default) then
				data[name][key] = default
			end
		end
	end
	data.foes = nil -- replaced by stages
	return data
end

-- Returns the player's data and whether it is safe to save it later.
-- If loading fails we never save, so a hiccup cannot wipe real progress.
function PlayerData.load(player: Player)
	if not store then
		return newData(), false
	end

	local ok, result = pcall(function()
		return store:GetAsync(keyFor(player))
	end)
	if not ok then
		warn("[PlayerData] Could not load data for", player.Name, "-", result)
		return newData(), false
	end

	return repair(result), true
end

function PlayerData.save(player: Player, data): boolean
	if not store then
		return false
	end

	data.lastSeen = os.time()
	local ok, result = pcall(function()
		store:SetAsync(keyFor(player), data)
	end)
	if not ok then
		warn("[PlayerData] Could not save data for", player.Name, "-", result)
	end
	return ok
end

return PlayerData
