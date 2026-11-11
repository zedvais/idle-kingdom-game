-- Client entry point. The whole game is menus: a status bar on top, a list
-- of sections on the left, and the open section in the middle.
-- The server sends a "state" table about once a second and after every
-- action. This script only draws that state and asks the server to do things.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Format = require(Shared:WaitForChild("Format"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local actionRemote = remotes:WaitForChild("Action")
local stateRemote = remotes:WaitForChild("State")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local COLOR_BACKGROUND = Color3.fromRGB(24, 30, 27)
local COLOR_PANEL = Color3.fromRGB(36, 45, 40)
local COLOR_ROW = Color3.fromRGB(50, 61, 54)
local COLOR_HEADER = Color3.fromRGB(205, 178, 120)
local COLOR_TEXT = Color3.fromRGB(236, 232, 220)
local COLOR_DIM = Color3.fromRGB(170, 175, 165)
local COLOR_GOLD = Color3.fromRGB(240, 200, 90)
local COLOR_ACTION = Color3.fromRGB(150, 60, 50)
local COLOR_BUY = Color3.fromRGB(60, 120, 80)
local COLOR_SELECTED = Color3.fromRGB(110, 85, 45)
local COLOR_DISABLED = Color3.fromRGB(80, 84, 80)
local COLOR_ENERGY = Color3.fromRGB(215, 170, 60)
local COLOR_STAMINA = Color3.fromRGB(70, 130, 190)
local COLOR_HEALTH = Color3.fromRGB(180, 65, 65)
local COLOR_XP = Color3.fromRGB(130, 100, 190)

local TOP_HEIGHT = 70
local RAIL_WIDTH = 116

-- A plain backdrop that covers the whole screen, including the top strip.
local backdropGui = Instance.new("ScreenGui")
backdropGui.Name = "KingdomBackdrop"
backdropGui.IgnoreGuiInset = true
backdropGui.DisplayOrder = -1
backdropGui.ResetOnSpawn = false
backdropGui.Parent = playerGui

local backdrop = Instance.new("Frame")
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = COLOR_BACKGROUND
backdrop.BorderSizePixel = 0
backdrop.Parent = backdropGui

local gui = Instance.new("ScreenGui")
gui.Name = "KingdomMenus"
gui.ResetOnSpawn = false
gui.Parent = playerGui

---------------------------------------------------------------------------
-- Small UI helpers
---------------------------------------------------------------------------

local function addCorner(instance: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local function makeFrame(parent: Instance, size: UDim2, position: UDim2, color: Color3): Frame
	local frame = Instance.new("Frame")
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

local function makeText(parent: Instance, size: UDim2, position: UDim2, color: Color3, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = size
	label.Position = position
	label.BackgroundTransparency = 1
	label.TextColor3 = color
	label.Font = Enum.Font.GothamMedium
	label.TextSize = textSize
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = ""
	label.Parent = parent
	return label
end

local function makeButton(parent: Instance, size: UDim2, position: UDim2, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.Size = size
	button.Position = position
	button.BackgroundColor3 = color
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 14
	button.TextWrapped = true
	button.Text = ""
	button.Parent = parent
	addCorner(button, 6)
	return button
end

-- Shows a button as usable (its own color) or greyed out.
local function setButton(button: TextButton, text: string, usable: boolean, color: Color3)
	button.Text = text
	button.BackgroundColor3 = if usable then color else COLOR_DISABLED
end

-- A bar that fills from left to right, with text on top.
local function makeBar(parent: Instance, size: UDim2, position: UDim2, color: Color3)
	local back = makeFrame(parent, size, position, Color3.fromRGB(20, 24, 22))
	addCorner(back, 4)
	local fill = makeFrame(back, UDim2.fromScale(0, 1), UDim2.fromScale(0, 0), color)
	addCorner(fill, 4)
	local label = makeText(back, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Color3.new(1, 1, 1), 12)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Font = Enum.Font.GothamBold
	return { fill = fill, label = label }
end

local function setBar(bar, value: number, maximum: number, text: string)
	local share = if maximum > 0 then math.clamp(value / maximum, 0, 1) else 0
	bar.fill.Size = UDim2.fromScale(share, 1)
	bar.label.Text = text
end

---------------------------------------------------------------------------
-- Top status bar
---------------------------------------------------------------------------

local topBar = makeFrame(gui, UDim2.new(1, -12, 0, TOP_HEIGHT), UDim2.fromOffset(6, 4), COLOR_PANEL)
addCorner(topBar, 8)

local nameLabel = makeText(topBar, UDim2.new(0.32, -12, 0, 26), UDim2.fromOffset(10, 6), COLOR_HEADER, 17)
nameLabel.Font = Enum.Font.GothamBold
nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
nameLabel.TextWrapped = false
local xpBar = makeBar(topBar, UDim2.new(0.32, -12, 0, 18), UDim2.fromOffset(10, 40), COLOR_XP)

local goldLabel = makeText(topBar, UDim2.new(0.34, 0, 0, 30), UDim2.new(0.33, 0, 0, 6), COLOR_GOLD, 22)
goldLabel.Font = Enum.Font.GothamBold
goldLabel.TextXAlignment = Enum.TextXAlignment.Center
local incomeLabel = makeText(topBar, UDim2.new(0.34, 0, 0, 20), UDim2.new(0.33, 0, 0, 40), COLOR_DIM, 13)
incomeLabel.TextXAlignment = Enum.TextXAlignment.Center

local energyBar = makeBar(topBar, UDim2.new(0.32, -12, 0, 18), UDim2.new(0.68, 2, 0, 5), COLOR_ENERGY)
local staminaBar = makeBar(topBar, UDim2.new(0.32, -12, 0, 18), UDim2.new(0.68, 2, 0, 26), COLOR_STAMINA)
local healthBar = makeBar(topBar, UDim2.new(0.32, -12, 0, 18), UDim2.new(0.68, 2, 0, 47), COLOR_HEALTH)

---------------------------------------------------------------------------
-- Left rail and pages
---------------------------------------------------------------------------

local rail = makeFrame(gui, UDim2.new(0, RAIL_WIDTH, 1, -(TOP_HEIGHT + 16)), UDim2.fromOffset(6, TOP_HEIGHT + 10), COLOR_PANEL)
addCorner(rail, 8)

local railLayout = Instance.new("UIListLayout")
railLayout.Padding = UDim.new(0, 4)
railLayout.SortOrder = Enum.SortOrder.LayoutOrder
railLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
railLayout.Parent = rail

local railPadding = Instance.new("UIPadding")
railPadding.PaddingTop = UDim.new(0, 6)
railPadding.Parent = rail

local main = makeFrame(gui, UDim2.new(1, -(RAIL_WIDTH + 18), 1, -(TOP_HEIGHT + 16)), UDim2.fromOffset(RAIL_WIDTH + 12, TOP_HEIGHT + 10), COLOR_PANEL)
addCorner(main, 8)

local pageTitle = makeText(main, UDim2.new(1, -24, 0, 30), UDim2.fromOffset(12, 4), COLOR_HEADER, 20)
pageTitle.Font = Enum.Font.GothamBold

local PAGE_NAMES = { "Keep", "Quests", "Holdings", "Warband", "Armory", "Foes" }
local railButtons = {}
local pages = {}

local function showPage(name: string)
	pageTitle.Text = string.upper(name)
	for _, pageName in PAGE_NAMES do
		pages[pageName].Visible = pageName == name
		railButtons[pageName].BackgroundColor3 = if pageName == name then COLOR_SELECTED else COLOR_ROW
	end
end

for index, name in PAGE_NAMES do
	local button = makeButton(rail, UDim2.new(1, -12, 0, 36), UDim2.fromOffset(0, 0), COLOR_ROW)
	button.LayoutOrder = index
	button.Text = name
	railButtons[name] = button

	local page = Instance.new("ScrollingFrame")
	page.Position = UDim2.fromOffset(8, 38)
	page.Size = UDim2.new(1, -16, 1, -44)
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.ScrollBarThickness = 6
	page.CanvasSize = UDim2.new(0, 0, 0, 0)
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.Visible = false
	page.Parent = main
	pages[name] = page

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 5)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = page

	button.Activated:Connect(function()
		showPage(name)
	end)
end

-- One line in a page: text on the left and up to one button on the right.
local BUTTON_WIDTH = 112

local function makeRow(page: Instance, order: number, height: number, hasButton: boolean)
	local row = makeFrame(page, UDim2.new(1, -10, 0, height), UDim2.fromOffset(0, 0), COLOR_ROW)
	row.LayoutOrder = order
	addCorner(row, 6)

	local textWidthOffset = if hasButton then -(BUTTON_WIDTH + 26) else -20
	local info = makeText(row, UDim2.new(1, textWidthOffset, 1, -8), UDim2.fromOffset(10, 4), COLOR_TEXT, 14)

	local button = nil
	if hasButton then
		button = makeButton(row, UDim2.fromOffset(BUTTON_WIDTH, math.min(42, height - 10)), UDim2.new(1, -6, 0.5, 0), COLOR_DISABLED)
		button.AnchorPoint = Vector2.new(1, 0.5)
	end
	return info, button
end

-- A small heading between groups of rows.
local function makeHeading(page: Instance, order: number, text: string)
	local label = makeText(page, UDim2.new(1, -10, 0, 22), UDim2.fromOffset(0, 0), COLOR_HEADER, 14)
	label.LayoutOrder = order
	label.Font = Enum.Font.GothamBold
	label.Text = string.upper(text)
end

local function send(action: string, id: string?)
	actionRemote:FireServer(action, id)
end

---------------------------------------------------------------------------
-- Building every page once. The text is filled in later by draw().
---------------------------------------------------------------------------

local order = 0
local function nextOrder(): number
	order += 1
	return order
end

-- Keep: your numbers and where skill points are spent.
local keepSummary = makeRow(pages.Keep, nextOrder(), 92, false)
makeHeading(pages.Keep, nextOrder(), "Skills")
local skillRows = {}
for _, skill in GameConfig.Skills do
	local info, button = makeRow(pages.Keep, nextOrder(), 50, true)
	skillRows[skill.id] = { info = info, button = button }
	button.Activated:Connect(function()
		send("Skill", skill.id)
	end)
end

-- Quests, grouped by region.
local questRows = {}
local lastRegion = nil
for _, quest in GameConfig.Quests do
	if quest.region ~= lastRegion then
		lastRegion = quest.region
		makeHeading(pages.Quests, nextOrder(), quest.region)
	end
	local info, button = makeRow(pages.Quests, nextOrder(), 52, true)
	questRows[quest.id] = { info = info, button = button }
	button.Activated:Connect(function()
		send("Quest", quest.id)
	end)
end

-- Holdings.
local holdingSummary = makeRow(pages.Holdings, nextOrder(), 50, false)
local holdingRows = {}
for _, holding in GameConfig.Holdings do
	local info, button = makeRow(pages.Holdings, nextOrder(), 52, true)
	holdingRows[holding.id] = { info = info, button = button }
	button.Activated:Connect(function()
		send("Holding", holding.id)
	end)
end

-- Warband.
local warbandSummary, slotButton = makeRow(pages.Warband, nextOrder(), 74, true)
slotButton.Activated:Connect(function()
	send("Slot")
end)
makeHeading(pages.Warband, nextOrder(), "Hire soldiers")
local soldierRows = {}
for _, soldier in GameConfig.Soldiers do
	local info, button = makeRow(pages.Warband, nextOrder(), 52, true)
	soldierRows[soldier.id] = { info = info, button = button }
	button.Activated:Connect(function()
		send("Hire", soldier.id)
	end)
end

-- Armory, grouped by gear slot.
local armoryNote = makeRow(pages.Armory, nextOrder(), 50, false)
armoryNote.Text = "Your best gear is used automatically: one weapon, one armor and one mount for you and for each soldier."
armoryNote.TextColor3 = COLOR_DIM
local gearRows = {}
for _, slot in GameConfig.GearSlots do
	makeHeading(pages.Armory, nextOrder(), slot .. "s")
	for _, gear in GameConfig.Gear do
		if gear.slot == slot then
			local info, button = makeRow(pages.Armory, nextOrder(), 52, true)
			gearRows[gear.id] = { info = info, button = button }
			button.Activated:Connect(function()
				send("Gear", gear.id)
			end)
		end
	end
end

-- Foes, grouped by band.
local foeRows = {}
local lastBand = nil
for _, foe in GameConfig.Foes do
	if foe.band ~= lastBand then
		lastBand = foe.band
		makeHeading(pages.Foes, nextOrder(), foe.band)
	end
	local info, button = makeRow(pages.Foes, nextOrder(), 66, true)
	local healthBarForFoe = makeBar(info.Parent, UDim2.new(1, -(BUTTON_WIDTH + 36), 0, 12), UDim2.new(0, 10, 1, -17), COLOR_HEALTH)
	info.Size = UDim2.new(1, -(BUTTON_WIDTH + 26), 1, -24)
	foeRows[foe.id] = { info = info, button = button, bar = healthBarForFoe }
	button.Activated:Connect(function()
		send("Fight", foe.id)
	end)
end

showPage("Quests")

---------------------------------------------------------------------------
-- Drawing the state the server sends
---------------------------------------------------------------------------

local function formatWait(seconds: number): string
	if seconds >= 60 then
		return `{math.ceil(seconds / 60)}m`
	end
	return `{seconds}s`
end

local function statText(attack: number, defense: number): string
	local parts = {}
	if attack > 0 then
		table.insert(parts, `+{attack} attack`)
	end
	if defense > 0 then
		table.insert(parts, `+{defense} defense`)
	end
	return table.concat(parts, ", ")
end

local function draw(state)
	local stats = state.stats
	local gold = state.gold

	-- Top bar
	nameLabel.Text = `Lv {state.level}  {player.DisplayName}`
	setBar(xpBar, state.xp, state.xpNeeded, `XP {state.xp} / {state.xpNeeded}`)
	goldLabel.Text = `{Format.short(gold)} gold`
	incomeLabel.Text = `+{Format.short(stats.incomePerHour)} per hour`
	setBar(energyBar, state.energy, stats.maxEnergy, `Energy {state.energy} / {stats.maxEnergy}`)
	setBar(staminaBar, state.stamina, stats.maxStamina, `Stamina {state.stamina} / {stats.maxStamina}`)
	setBar(healthBar, state.health, stats.maxHealth, `Health {state.health} / {stats.maxHealth}`)

	-- A dot on the Keep button when there are points to spend.
	railButtons.Keep.Text = if state.skillPoints > 0 then `Keep ({state.skillPoints})` else "Keep"

	-- Keep
	keepSummary.Text = `Attack {stats.attack}   |   Defense {stats.defense}   |   Renown {Format.short(state.renown)}\n`
		.. `Holdings {stats.holdingsOwned} / {stats.holdingSlots}   |   Warband {#state.soldiers + 1} fighters\n`
		.. `Skill points to spend: {state.skillPoints}`
	for _, skill in GameConfig.Skills do
		local row = skillRows[skill.id]
		local bought = state.skills[skill.id] or 0
		row.info.Text = `{skill.name}  (bought {bought})\n{skill.note}`
		local pointWord = if skill.cost == 1 then "point" else "points"
		setButton(row.button, `Add\n{skill.cost} {pointWord}`, state.skillPoints >= skill.cost, COLOR_BUY)
	end

	-- Quests
	for _, quest in GameConfig.Quests do
		local row = questRows[quest.id]
		local done = state.quests[quest.id] or 0
		local rank = GameConfig.getMasteryRank(done)
		local mastery
		if rank >= GameConfig.MaxMasteryRanks then
			mastery = "Mastered"
		else
			mastery = `Mastery {done % GameConfig.MasteryPerRank}/{GameConfig.MasteryPerRank}, rank {rank}`
		end
		row.info.Text = `{quest.name}\n{quest.energy} energy  >  {Format.short(GameConfig.getQuestGold(quest, done))} gold, {quest.xp} XP   |   {mastery}`
		if state.level < quest.level then
			setButton(row.button, `Level {quest.level}`, false, COLOR_ACTION)
		else
			setButton(row.button, "Do Quest", state.energy >= quest.energy, COLOR_ACTION)
		end
	end

	-- Holdings
	holdingSummary.Text = `Income: {Format.short(stats.incomePerHour)} gold per hour   |   Owned {stats.holdingsOwned} / {stats.holdingSlots}\n`
		.. `Holdings earn {math.floor(GameConfig.OfflineRate * 100)}% while you are away.`
	for _, holding in GameConfig.Holdings do
		local row = holdingRows[holding.id]
		local level = state.holdings[holding.id] or 0
		local cost = GameConfig.getHoldingCost(holding, level)
		if level == 0 then
			row.info.Text = `{holding.name}\nEarns {Format.short(holding.income)} gold per hour`
			if state.level < holding.level then
				setButton(row.button, `Level {holding.level}`, false, COLOR_BUY)
			else
				local hasSlot = stats.holdingsOwned < stats.holdingSlots
				setButton(row.button, if hasSlot then `Buy\n{Format.short(cost)}` else "No slot", hasSlot and gold >= cost, COLOR_BUY)
			end
		else
			row.info.Text = `{holding.name}  Lv {level}\nEarns {Format.short(GameConfig.getHoldingIncome(holding, level))} gold per hour`
			if level >= GameConfig.HoldingMaxLevel then
				setButton(row.button, "Max level", false, COLOR_BUY)
			else
				setButton(row.button, `Upgrade\n{Format.short(cost)}`, gold >= cost, COLOR_BUY)
			end
		end
	end

	-- Warband
	local counts = {}
	for _, soldierId in state.soldiers do
		counts[soldierId] = (counts[soldierId] or 0) + 1
	end
	local roster = {}
	for _, soldier in GameConfig.Soldiers do
		if counts[soldier.id] then
			table.insert(roster, `{counts[soldier.id]} {soldier.name}`)
		end
	end
	local rosterText = if #roster > 0 then table.concat(roster, ", ") else "nobody yet"
	warbandSummary.Text = `You lead the warband.  Soldier slots: {#state.soldiers} / {state.soldierSlots}\n`
		.. `Soldiers: {rosterText}\nTotal attack {stats.attack}, defense {stats.defense}`
	if state.soldierSlots >= GameConfig.MaxSoldierSlots then
		setButton(slotButton, "Max slots", false, COLOR_BUY)
	else
		local slotCost = GameConfig.getSlotCost(state.soldierSlots)
		setButton(slotButton, `New slot\n{Format.short(slotCost)}`, gold >= slotCost, COLOR_BUY)
	end
	for _, soldier in GameConfig.Soldiers do
		local row = soldierRows[soldier.id]
		row.info.Text = `{soldier.name}  (you have {counts[soldier.id] or 0})\n{statText(soldier.attack, soldier.defense)}`
		setButton(row.button, `Hire\n{Format.short(soldier.cost)}`, gold >= soldier.cost, COLOR_BUY)
	end

	-- Armory
	for _, gear in GameConfig.Gear do
		local row = gearRows[gear.id]
		row.info.Text = `{gear.name}  (you have {state.gear[gear.id] or 0})\n{statText(gear.attack, gear.defense)}`
		setButton(row.button, `Buy\n{Format.short(gear.cost)}`, gold >= gear.cost, COLOR_BUY)
	end

	-- Foes
	for _, foe in GameConfig.Foes do
		local row = foeRows[foe.id]
		local record = state.foes[foe.id]
		local health = if record then record.health else foe.health
		local wait = if record then record.wait else 0
		row.info.Text = `{foe.name}\nAttack {foe.attack}, defense {foe.defense}   |   Reward {Format.short(foe.gold)} gold, {foe.xp} XP`
		setBar(row.bar, health, foe.health, `{health} / {foe.health}`)
		if state.level < foe.level then
			setButton(row.button, `Level {foe.level}`, false, COLOR_ACTION)
		elseif wait > 0 then
			setButton(row.button, `Back in\n{formatWait(wait)}`, false, COLOR_ACTION)
		else
			local ready = state.stamina >= 1 and state.health >= GameConfig.MinHealthToFight
			setButton(row.button, "Attack\n1 stamina", ready, COLOR_ACTION)
		end
	end
end

stateRemote.OnClientEvent:Connect(draw)

---------------------------------------------------------------------------
-- Toasts: short messages from the server
---------------------------------------------------------------------------

local toast = makeText(gui, UDim2.fromOffset(480, 40), UDim2.new(0.5, 0, 1, -54), Color3.new(1, 1, 1), 15)
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.TextXAlignment = Enum.TextXAlignment.Center
toast.BackgroundTransparency = 0.05
toast.BackgroundColor3 = Color3.fromRGB(15, 18, 16)
toast.ZIndex = 5
toast.Visible = false
addCorner(toast, 8)

local toastCount = 0
local function showToast()
	local text = player:GetAttribute("ToastText")
	if typeof(text) ~= "string" or text == "" then
		return
	end
	toastCount += 1
	local thisToast = toastCount
	toast.Text = text
	toast.Visible = true
	task.delay(3.5, function()
		if toastCount == thisToast then
			toast.Visible = false
		end
	end)
end

player:GetAttributeChangedSignal("ToastId"):Connect(showToast)
showToast()

---------------------------------------------------------------------------
-- Welcome back window: gold earned while away
---------------------------------------------------------------------------

local function showWelcomeBack(amount: number)
	local window = makeFrame(gui, UDim2.fromOffset(380, 190), UDim2.fromScale(0.5, 0.5), Color3.fromRGB(15, 18, 16))
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.ZIndex = 10
	addCorner(window, 12)

	local title = makeText(window, UDim2.new(1, -30, 0, 34), UDim2.fromOffset(15, 14), COLOR_HEADER, 20)
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.Text = "Welcome back, my liege!"
	title.ZIndex = 11

	local body = makeText(window, UDim2.new(1, -30, 0, 56), UDim2.fromOffset(15, 54), COLOR_GOLD, 16)
	body.TextXAlignment = Enum.TextXAlignment.Center
	body.Text = `Your holdings earned {Format.short(amount)} gold while you were away.`
	body.ZIndex = 11

	local button = makeButton(window, UDim2.fromOffset(160, 42), UDim2.new(0.5, 0, 1, -14), COLOR_BUY)
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Text = "Splendid"
	button.TextSize = 16
	button.ZIndex = 11
	button.Activated:Connect(function()
		window:Destroy()
	end)
end

local shownWelcome = false
local function checkWelcomeBack()
	local amount = player:GetAttribute("OfflineGold")
	if not shownWelcome and typeof(amount) == "number" and amount > 0 then
		shownWelcome = true
		showWelcomeBack(amount)
	end
end

player:GetAttributeChangedSignal("OfflineGold"):Connect(checkWelcomeBack)
checkWelcomeBack()

print(`[{GameConfig.GameName}] client started`)
