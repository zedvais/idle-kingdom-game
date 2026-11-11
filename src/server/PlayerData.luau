-- Loads and saves each player's kingdom with Roblox DataStores.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local PlayerData = {}

-- Change this name to wipe everyone's progress (useful during testing).
local STORE_NAME = "IdleKingdom_v1"

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
		buildings = {}, -- [buildingId] = { level, steward, stored }
		units = {}, -- [unitId] = count
		landsConquered = 0,
		lastSeen = 0,
	}
end

-- Fills in anything missing so old saves keep working when the game changes.
local function repair(data)
	local fresh = newData()
	if type(data) ~= "table" then
		return fresh
	end
	if type(data.gold) ~= "number" then
		data.gold = fresh.gold
	end
	if type(data.buildings) ~= "table" then
		data.buildings = {}
	end
	if type(data.units) ~= "table" then
		data.units = {}
	end
	if type(data.landsConquered) ~= "number" then
		data.landsConquered = 0
	end
	if type(data.lastSeen) ~= "number" then
		data.lastSeen = 0
	end
	for _, entry in data.buildings do
		if type(entry.level) ~= "number" then
			entry.level = 0
		end
		if type(entry.stored) ~= "number" then
			entry.stored = 0
		end
		entry.steward = entry.steward == true
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
