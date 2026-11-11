-- Loads and saves each player's progress with Roblox DataStores.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local PlayerData = {}

-- Change this name to wipe everyone's progress (useful during testing).
local STORE_NAME = "IdleKingdom_v3"

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
		holdings = {}, -- [holdingId] = level
		soldierSlots = 1,
		soldiers = {}, -- list of soldier items in the warband
		gear = {}, -- list of owned gear items
		nextItemId = 1,
		market = { window = -1, items = {} },
		foes = {}, -- [foeId] = { health = number, readyAt = os.time() value }
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
