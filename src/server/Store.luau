-- Talks to Roblox for Robux purchases: shows the buy prompts, checks which
-- game passes a player owns, and hands out developer products exactly once
-- per purchase (Roblox may send the same receipt more than once).
--
-- Main.server.luau gives this module three functions through Store.init:
--   getSession(player)          -> the player's session, or nil if not loaded
--   grantProduct(player, data, product)  hands out a developer product
--   grantPass(player, data, pass)        turns a game pass on
-- and Store calls them at the right time.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local StoreConfig = require(ReplicatedStorage.Shared.StoreConfig)
local PlayerData = require(script.Parent.PlayerData)

local Store = {}

-- How many past purchase ids each save remembers, to ignore repeats.
local RECEIPTS_KEPT = 50

local hooks = nil

local productById = {}
for _, product in StoreConfig.Products do
	if product.id ~= 0 then
		productById[product.id] = product
	end
end
local passById = {}
for _, pass in StoreConfig.Passes do
	if pass.id ~= 0 then
		passById[pass.id] = pass
	end
end

-- Called when Roblox has taken the Robux for a developer product.
local function processReceipt(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local session = player and hooks.getSession(player)
	if not session then
		-- Not loaded yet (or gone). Roblox will try again later.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = session.data

	if table.find(data.receipts, info.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local product = productById[info.ProductId]
	if not product then
		warn("[Store] Unknown developer product id", info.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local ok, err = pcall(hooks.grantProduct, player, data, product)
	if not ok then
		warn("[Store] Could not grant", product.key, "-", err)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	table.insert(data.receipts, 1, info.PurchaseId)
	while #data.receipts > RECEIPTS_KEPT do
		table.remove(data.receipts)
	end

	-- Save straight away so a crash cannot lose what was paid for. If the
	-- save fails, Roblox asks again on the next visit, and that visit loads
	-- the old save without the reward, so it is not given twice.
	if session.canSave and not PlayerData.save(player, data) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	hooks.refresh(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Turns on every pass the player owns on Roblox. Runs when they join.
function Store.checkPasses(player: Player, data)
	for _, pass in StoreConfig.Passes do
		if pass.id ~= 0 and not data.passes[pass.key] then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.id)
			end)
			if ok and owns then
				data.passes[pass.key] = true
			end
		end
	end
end

-- Shows the Roblox buy prompt for a pass or product.
-- kind is "pass" or "product". Returns a message for the player if the
-- prompt could not be shown, or nil.
function Store.prompt(player: Player, data, kind: string, entry): string?
	if entry.id == 0 then
		if RunService:IsStudio() then
			-- Test mode: pretend it was bought so the reward can be tried.
			if kind == "pass" then
				hooks.grantPass(player, data, entry)
			else
				hooks.grantProduct(player, data, entry)
			end
			return `[Studio test] {entry.name} given for free. Real players pay {entry.price} Robux.`
		end
		return `{entry.name} is not on sale yet.`
	end
	local ok, err = pcall(function()
		if kind == "pass" then
			MarketplaceService:PromptGamePassPurchase(player, entry.id)
		else
			MarketplaceService:PromptProductPurchase(player, entry.id)
		end
	end)
	if not ok then
		warn("[Store] Could not show the prompt for", entry.key, "-", err)
		return "The Roblox shop did not open. Try again in a moment."
	end
	return nil
end

function Store.init(options)
	hooks = options
	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		local pass = passById[passId]
		local session = hooks.getSession(player)
		if purchased and pass and session then
			hooks.grantPass(player, session.data, pass)
			hooks.refresh(player)
		end
	end)
end

return Store
