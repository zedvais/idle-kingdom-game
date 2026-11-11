-- Server entry point: runs the whole kingdom game loop.
-- The server owns every rule (gold, costs, battles) so players cannot cheat.
-- Players have no character. They watch their village from a fixed camera and
-- play by tapping buttons, which arrive here through the Action remote.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Format = require(ReplicatedStorage.Shared.Format)
local PlayerData = require(script.Parent.PlayerData)
local PlotBuilder = require(script.Parent.PlotBuilder)

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

-- Where each player's village goes. Two rows of four plots.
local PLOT_ORIGINS = {}
for row = 0, 1 do
	for column = 0, 3 do
		table.insert(PLOT_ORIGINS, Vector3.new(-180 + column * 120, 0, -125 + row * 250))
	end
end

local sessions = {} -- [Player] = { data, canSave, plot, slot, attackReadyAt, actionCount }
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
-- Showing the current state: signs in the village and the player's menus
---------------------------------------------------------------------------

local function refresh(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	local data = session.data
	local plot = session.plot

	-- Everything the client needs to draw its menus, already worked out.
	local state = {
		gold = data.gold,
		goldPerSecond = getTotalIncome(data),
		armyPower = getArmyPower(data),
		landsConquered = data.landsConquered,
		attackWait = math.max(0, math.ceil(session.attackReadyAt - os.clock())),
		plotOrigin = plot.origin,
		buildings = {},
		units = {},
	}

	for _, building in GameConfig.Buildings do
		local view = plot.buildings[building.id]
		local entry = getEntry(data, building.id)
		local locked = data.landsConquered < building.requiresLands
		local income = getIncome(data, building)

		state.buildings[building.id] = {
			level = entry.level,
			steward = entry.steward,
			stored = entry.stored,
			capacity = income * GameConfig.StorageSeconds,
			income = income,
			upgradeCost = GameConfig.getUpgradeCost(building, entry.level),
			stewardCost = GameConfig.getStewardCost(building),
			locked = locked,
		}

		if locked then
			view.label.Text = `{building.name} (locked)`
			view.block.Transparency = 0.8
		elseif entry.level == 0 then
			view.label.Text = building.name
			view.block.Transparency = 0.6
		else
			view.label.Text = `{building.name}  Lv {entry.level}`
			view.block.Transparency = 0
		end
	end

	for _, unit in GameConfig.Units do
		local count = data.units[unit.id] or 0
		state.units[unit.id] = count
		plot.units[unit.id].label.Text = `{unit.name} x{Format.short(count)}`
	end

	local nextLand = GameConfig.Lands[data.landsConquered + 1]
	plot.war.label.Text = if nextLand then `Next: {nextLand.name}` else "All conquered!"

	stateRemote:FireClient(player, state)

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

-- The client asks for something. Never trust what it sends: check everything.
actionRemote.OnServerEvent:Connect(function(player: Player, action, id, amount)
	local session = sessions[player]
	if not session or type(action) ~= "string" then
		return
	end

	-- Ignore floods of requests (auto-clickers or exploits).
	session.actionCount += 1
	if session.actionCount > MAX_ACTIONS_PER_SECOND then
		return
	end

	if action == "Attack" then
		attack(player)
		return
	end

	if type(id) ~= "string" then
		return
	end

	local building = buildingById[id]
	local unit = unitById[id]
	if action == "Collect" and building then
		collect(player, building.id)
	elseif action == "Upgrade" and building then
		upgrade(player, building)
	elseif action == "Steward" and building then
		hireSteward(player, building)
	elseif action == "Recruit" and unit then
		recruit(player, unit, if amount == 10 then 10 else 1)
	end
end)

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
		actionCount = 0,
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
			session.actionCount = 0
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
