-- Server entry point: runs the whole kingdom game loop.
-- The server owns every rule (gold, costs, battles) so players cannot cheat.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Format = require(ReplicatedStorage.Shared.Format)
local PlayerData = require(script.Parent.PlayerData)
local PlotBuilder = require(script.Parent.PlotBuilder)

local AUTOSAVE_SECONDS = 60

-- Where each player's village goes. Two rows of four plots.
local PLOT_ORIGINS = {}
for row = 0, 1 do
	for column = 0, 3 do
		table.insert(PLOT_ORIGINS, Vector3.new(-180 + column * 120, 0, -125 + row * 250))
	end
end

local sessions = {} -- [Player] = { data, canSave, plot, slot, attackReadyAt }
local usedSlots = {} -- [slot index] = Player

local buildingById = {}
for _, building in GameConfig.Buildings do
	buildingById[building.id] = building
end

local unitById = {}
for _, unit in GameConfig.Units do
	unitById[unit.id] = unit
end

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local function sendToast(player: Player, text: string)
	player:SetAttribute("ToastText", text)
	player:SetAttribute("ToastId", (player:GetAttribute("ToastId") or 0) + 1)
end

local function getEntry(data, buildingId: string)
	local entry = data.buildings[buildingId]
	if not entry then
		entry = { level = 0, steward = false, stored = 0 }
		data.buildings[buildingId] = entry
	end
	return entry
end

local function getIncome(data, building): number
	local entry = getEntry(data, building.id)
	return GameConfig.getBaseIncome(building, entry.level) * GameConfig.getLandMultiplier(data.landsConquered)
end

local function getTotalIncome(data): number
	local total = 0
	for _, building in GameConfig.Buildings do
		total += getIncome(data, building)
	end
	return total
end

local function getArmyPower(data): number
	local power = 0
	for _, unit in GameConfig.Units do
		power += (data.units[unit.id] or 0) * unit.power
	end
	return power
end

local function claimSlot(player: Player): number
	for slot = 1, #PLOT_ORIGINS do
		if not usedSlots[slot] then
			usedSlots[slot] = player
			return slot
		end
	end
	-- Server is fuller than the number of plots. Share the first plot spot.
	return 1
end

---------------------------------------------------------------------------
-- Showing the current state on signs, prompts and the player's HUD
---------------------------------------------------------------------------

local function refresh(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	local data = session.data
	local plot = session.plot

	for _, building in GameConfig.Buildings do
		local view = plot.buildings[building.id]
		local entry = getEntry(data, building.id)
		local locked = data.landsConquered < building.requiresLands

		if locked then
			local land = GameConfig.Lands[building.requiresLands]
			view.label.Text = `{building.name}\nConquer {land.name} to unlock`
			view.block.Transparency = 0.8
			view.upgradePrompt.Enabled = false
			view.stewardPrompt.Enabled = false
		else
			local cost = GameConfig.getUpgradeCost(building, entry.level)
			view.upgradePrompt.Enabled = true
			view.upgradePrompt.ObjectText = building.name
			local verb = if entry.level == 0 then "Build" else "Upgrade"
			view.upgradePrompt.ActionText = `{verb} ({Format.short(cost)} gold)`

			if entry.level == 0 then
				view.label.Text = `{building.name}\nNot built`
				view.block.Transparency = 0.6
				view.stewardPrompt.Enabled = false
			else
				local income = getIncome(data, building)
				local status
				if entry.steward then
					status = "Steward collecting"
				else
					local capacity = income * GameConfig.StorageSeconds
					status = `Stored {Format.short(entry.stored)} / {Format.short(capacity)}`
				end
				view.label.Text = `{building.name}  Lv {entry.level}\n{Format.short(income)} gold/s\n{status}`
				view.block.Transparency = 0

				view.stewardPrompt.Enabled = not entry.steward
				view.stewardPrompt.ObjectText = building.name
				view.stewardPrompt.ActionText = `Hire steward ({Format.short(GameConfig.getStewardCost(building))} gold)`
			end
		end
	end

	for _, unit in GameConfig.Units do
		local view = plot.units[unit.id]
		local count = data.units[unit.id] or 0
		view.label.Text = `{unit.name} x{Format.short(count)}\n+{Format.short(unit.power)} power each`
		view.recruitPrompt.Enabled = true
		view.recruitPrompt.ObjectText = unit.name
		view.recruitPrompt.ActionText = `Recruit 1 ({Format.short(unit.cost)} gold)`
		view.recruitTenPrompt.Enabled = true
		view.recruitTenPrompt.ObjectText = unit.name
		view.recruitTenPrompt.ActionText = `Recruit 10 ({Format.short(unit.cost * 10)} gold)`
	end

	local power = getArmyPower(data)
	local nextLand = GameConfig.Lands[data.landsConquered + 1]
	if nextLand then
		local waitLeft = math.ceil(session.attackReadyAt - os.clock())
		local status = if waitLeft > 0 then `Army resting: {waitLeft}s` else `Your power: {Format.short(power)}`
		plot.war.label.Text = `Next: {nextLand.name}\nPower needed: {Format.short(nextLand.power)}\n{status}`
		plot.war.attackPrompt.Enabled = waitLeft <= 0
		plot.war.attackPrompt.ObjectText = nextLand.name
		plot.war.attackPrompt.ActionText = "Attack"
	else
		plot.war.label.Text = "Every land is conquered!\nA new reign is coming soon"
		plot.war.attackPrompt.Enabled = false
	end

	player:SetAttribute("Gold", data.gold)
	player:SetAttribute("GoldPerSecond", getTotalIncome(data))
	player:SetAttribute("ArmyPower", power)
	player:SetAttribute("LandsConquered", data.landsConquered)

	local leaderstats = player:FindFirstChild("leaderstats")
	local goldStat = leaderstats and leaderstats:FindFirstChild("Gold")
	if goldStat then
		goldStat.Value = Format.short(data.gold)
	end
end

---------------------------------------------------------------------------
-- Player actions
---------------------------------------------------------------------------

local function collect(player: Player, buildingId: string)
	local session = sessions[player]
	if not session then
		return
	end
	local entry = getEntry(session.data, buildingId)
	if entry.stored > 0 then
		session.data.gold += entry.stored
		entry.stored = 0
		refresh(player)
	end
end

local function upgrade(player: Player, building)
	local session = sessions[player]
	if not session then
		return
	end
	local data = session.data
	if data.landsConquered < building.requiresLands then
		return
	end

	collect(player, building.id)

	local entry = getEntry(data, building.id)
	local cost = GameConfig.getUpgradeCost(building, entry.level)
	if data.gold < cost then
		sendToast(player, `Not enough gold. You need {Format.short(cost)}.`)
		return
	end

	data.gold -= cost
	entry.level += 1
	if entry.level == 1 then
		sendToast(player, `{building.name} built!`)
	elseif table.find(GameConfig.MilestoneLevels, entry.level) then
		sendToast(player, `{building.name} reached level {entry.level}. Its income doubled!`)
	end
	refresh(player)
end

local function hireSteward(player: Player, building)
	local session = sessions[player]
	if not session then
		return
	end
	local data = session.data
	local entry = getEntry(data, building.id)
	if entry.level == 0 or entry.steward then
		return
	end

	collect(player, building.id)

	local cost = GameConfig.getStewardCost(building)
	if data.gold < cost then
		sendToast(player, `Not enough gold. You need {Format.short(cost)}.`)
		return
	end

	data.gold -= cost
	entry.steward = true
	sendToast(player, `A steward now runs the {building.name}.`)
	refresh(player)
end

local function recruit(player: Player, unit, amount: number)
	local session = sessions[player]
	if not session then
		return
	end
	local data = session.data
	local cost = unit.cost * amount
	if data.gold < cost then
		sendToast(player, `Not enough gold. You need {Format.short(cost)}.`)
		return
	end

	data.gold -= cost
	data.units[unit.id] = (data.units[unit.id] or 0) + amount
	refresh(player)
end

local function attack(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	local data = session.data
	local land = GameConfig.Lands[data.landsConquered + 1]
	if not land or os.clock() < session.attackReadyAt then
		return
	end

	local power = getArmyPower(data)
	if power >= land.power then
		data.landsConquered += 1
		sendToast(player, `Victory! {land.name} is yours. Gold income +{math.floor(land.bonus * 100)}%.`)
	else
		session.attackReadyAt = os.clock() + GameConfig.AttackCooldownSeconds
		sendToast(player, `Defeat at {land.name}. You need {Format.short(land.power)} power and have {Format.short(power)}.`)
	end
	refresh(player)
end

---------------------------------------------------------------------------
-- Joining and leaving
---------------------------------------------------------------------------

local function connectPlot(player: Player, plot)
	local function ifOwner(callback)
		return function(whoTriggered: Player)
			if whoTriggered == player then
				callback()
			else
				sendToast(whoTriggered, `This is {player.DisplayName}'s kingdom.`)
			end
		end
	end

	for _, building in GameConfig.Buildings do
		local view = plot.buildings[building.id]
		view.upgradePrompt.Triggered:Connect(ifOwner(function()
			upgrade(player, building)
		end))
		view.stewardPrompt.Triggered:Connect(ifOwner(function()
			hireSteward(player, building)
		end))
		-- Walking onto the stone pad collects the stored gold.
		view.pad.Touched:Connect(function(hit)
			local character = hit.Parent
			if character and Players:GetPlayerFromCharacter(character) == player then
				collect(player, building.id)
			end
		end)
	end

	for _, unit in GameConfig.Units do
		local view = plot.units[unit.id]
		view.recruitPrompt.Triggered:Connect(ifOwner(function()
			recruit(player, unit, 1)
		end))
		view.recruitTenPrompt.Triggered:Connect(ifOwner(function()
			recruit(player, unit, 10)
		end))
	end

	plot.war.attackPrompt.Triggered:Connect(ifOwner(function()
		attack(player)
	end))
end

-- Gold earned by stewarded buildings while the player was away.
local function grantOfflineGold(player: Player, data)
	if data.lastSeen <= 0 then
		return
	end
	local seconds = math.clamp(os.time() - data.lastSeen, 0, GameConfig.OfflineMaxSeconds)
	local perSecond = 0
	for _, building in GameConfig.Buildings do
		if getEntry(data, building.id).steward then
			perSecond += getIncome(data, building)
		end
	end
	local earned = math.floor(perSecond * GameConfig.OfflineRate * seconds)
	if earned > 0 then
		data.gold += earned
		player:SetAttribute("OfflineGold", earned)
	end
end

local function moveToPlot(player: Player, character: Model)
	local session = sessions[player]
	if not session then
		return
	end
	task.wait(0.2) -- let the character finish spawning first
	if character.Parent then
		character:PivotTo(session.plot.spawnCFrame)
	end
end

local function onPlayerAdded(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local goldStat = Instance.new("StringValue")
	goldStat.Name = "Gold"
	goldStat.Value = "0"
	goldStat.Parent = leaderstats
	leaderstats.Parent = player

	local data, canSave = PlayerData.load(player)
	if not player.Parent then
		return -- left while loading
	end
	if not canSave and not RunService:IsStudio() then
		sendToast(player, "Could not load your save. Progress in this visit will not be kept.")
	end

	grantOfflineGold(player, data)

	local slot = claimSlot(player)
	local plot = PlotBuilder.build(PLOT_ORIGINS[slot], player.DisplayName)

	sessions[player] = {
		data = data,
		canSave = canSave,
		plot = plot,
		slot = slot,
		attackReadyAt = 0,
	}

	connectPlot(player, plot)
	refresh(player)

	player.CharacterAdded:Connect(function(character)
		moveToPlot(player, character)
	end)
	if player.Character then
		moveToPlot(player, player.Character)
	end
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
	session.plot.model:Destroy()
	if usedSlots[session.slot] == player then
		usedSlots[session.slot] = nil
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
-- The idle loop: once a second, every building earns gold
---------------------------------------------------------------------------

task.spawn(function()
	while true do
		task.wait(1)
		for player, session in sessions do
			local data = session.data
			for _, building in GameConfig.Buildings do
				local entry = getEntry(data, building.id)
				if entry.level > 0 then
					local income = getIncome(data, building)
					if entry.steward then
						data.gold += income + entry.stored
						entry.stored = 0
					else
						entry.stored = math.min(entry.stored + income, income * GameConfig.StorageSeconds)
					end
				end
			end
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
