-- DataStore calls for things shared between players (raids, guilds, the
-- realm map), with a stand-in kept in server memory when DataStores can
-- not be reached (an unpublished place in Studio). With the stand-in,
-- everything works for the players in that one server, so the pages can
-- be tried out in Studio.

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local SharedStore = {}

local useMemory = false
local memory = {} -- [store name] = { [key] = value }
local orderedMemory = {} -- [store name] = { [key] = number }

-- In Studio, the first DataStore error switches to the stand-in for good.
local function failed(err)
	if RunService:IsStudio() and not useMemory then
		useMemory = true
		warn("[SharedStore] DataStores are not available in this Studio session, using server memory instead:", err)
	end
end

if game.PlaceId == 0 then
	useMemory = true
end

function SharedStore.isMemory(): boolean
	return useMemory
end

local stores = {}
local function storeFor(name: string)
	if stores[name] == nil then
		local ok, store = pcall(function()
			return DataStoreService:GetDataStore(name)
		end)
		stores[name] = if ok then store else false
		if not ok then
			failed(store)
		end
	end
	return stores[name] or nil
end

local function memoryFor(name: string)
	memory[name] = memory[name] or {}
	return memory[name]
end

-- Reads a value. Returns (value, ok).
function SharedStore.get(name: string, key: string): (any, boolean)
	if not useMemory then
		local store = storeFor(name)
		if store then
			local ok, value = pcall(function()
				return store:GetAsync(key)
			end)
			if ok then
				return value, true
			end
			failed(value)
			if not useMemory then
				return nil, false
			end
		elseif not useMemory then
			return nil, false
		end
	end
	local value = memoryFor(name)[key]
	return if type(value) == "table" then table.clone(value) else value, true
end

-- Changes a value with transform(old) -> new (return nil to change
-- nothing). Returns (new value, ok). transform may run more than once.
function SharedStore.update(name: string, key: string, transform: (any) -> any): (any, boolean)
	if not useMemory then
		local store = storeFor(name)
		if store then
			local ok, value = pcall(function()
				return store:UpdateAsync(key, transform)
			end)
			if ok then
				return value, true
			end
			failed(value)
			if not useMemory then
				return nil, false
			end
		elseif not useMemory then
			return nil, false
		end
	end
	local list = memoryFor(name)
	local old = list[key]
	-- deep copy so a transform that edits in place and then bails out
	-- leaves the stored value alone
	local copy = if type(old) == "table" then SharedStore.deepCopy(old) else old
	local new = transform(copy)
	if new ~= nil then
		list[key] = new
		return new, true
	end
	return old, true
end

function SharedStore.set(name: string, key: string, value: any): boolean
	if not useMemory then
		local store = storeFor(name)
		if store then
			local ok, err = pcall(function()
				store:SetAsync(key, value)
			end)
			if ok then
				return true
			end
			failed(err)
			if not useMemory then
				return false
			end
		elseif not useMemory then
			return false
		end
	end
	memoryFor(name)[key] = value
	return true
end

function SharedStore.remove(name: string, key: string)
	if not useMemory then
		local store = storeFor(name)
		if store then
			local ok, err = pcall(function()
				store:RemoveAsync(key)
			end)
			if ok then
				return
			end
			failed(err)
			if not useMemory then
				return
			end
		end
	end
	memoryFor(name)[key] = nil
end

function SharedStore.deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, inner in value do
		copy[key] = SharedStore.deepCopy(inner)
	end
	return copy
end

---------------------------------------------------------------------------
-- Ordered stores (whole numbers by key, for searching by level)
---------------------------------------------------------------------------

local ordered = {}
local function orderedFor(name: string)
	if ordered[name] == nil then
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore(name)
		end)
		ordered[name] = if ok then store else false
		if not ok then
			failed(store)
		end
	end
	return ordered[name] or nil
end

function SharedStore.setOrdered(name: string, key: string, value: number)
	value = math.floor(value)
	if not useMemory then
		local store = orderedFor(name)
		if store then
			local ok, err = pcall(function()
				store:SetAsync(key, value)
			end)
			if ok then
				return
			end
			failed(err)
			if not useMemory then
				return
			end
		end
	end
	orderedMemory[name] = orderedMemory[name] or {}
	orderedMemory[name][key] = value
end

-- Up to `count` entries with min <= value <= max, highest first:
-- { { key, value } }.
function SharedStore.range(name: string, count: number, min: number, max: number): { { any } }
	local list = {}
	if not useMemory then
		local store = orderedFor(name)
		if store then
			local ok, pages = pcall(function()
				return store:GetSortedAsync(false, count, min, max)
			end)
			if ok then
				for _, entry in pages:GetCurrentPage() do
					table.insert(list, { entry.key, entry.value })
				end
				return list
			end
			failed(pages)
			if not useMemory then
				return list
			end
		end
	end
	for key, value in orderedMemory[name] or {} do
		if value >= min and value <= max then
			table.insert(list, { key, value })
		end
	end
	table.sort(list, function(a, b)
		return a[2] > b[2]
	end)
	while #list > count do
		table.remove(list)
	end
	return list
end

return SharedStore
