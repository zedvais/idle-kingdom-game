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

local PAGE_NAMES = { "Keep", "Quests", "Holdings", "Market", "Warband", "Armory", "Foes" }
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

local function formatClock(seconds: number): string
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
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

-- Rarity colors, for names shown with rich text.
local function rarityName(item): string
	local rarity = GameConfig.getRarity(item.rarity)
	local color = rarity.color
	local hex = string.format("#%02X%02X%02X", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
	return `<font color="{hex}"><b>{item.rarity}</b></font> {item.name}`
end

-- A row whose text can show rarity colors.
local function makeItemRow(page: Instance, order: number)
	local info, button = makeRow(page, order, 52, true)
	info.RichText = true
	return { info = info, button = button }
end

-- Market: a fixed number of rows that are refilled each restock.
local marketSummary = makeRow(pages.Market, nextOrder(), 50, false)
local marketRows = {}
for index = 1, GameConfig.MarketSize do
	local row = makeItemRow(pages.Market, nextOrder())
	marketRows[index] = row
	row.button.Activated:Connect(function()
		send("Buy", tostring(index))
	end)
end

-- Warband: one row for you, one per unlocked slot, and the next locked slot.
local openRecruitWindow -- defined further down, with the recruit window

local warbandSummary, autoRollButton = makeRow(pages.Warband, nextOrder(), 56, true)
setButton(autoRollButton, "Auto Roll", true, COLOR_ACTION)
autoRollButton.Activated:Connect(function()
	openRecruitWindow(0)
end)

local function gearLine(item): string
	if not item then
		return `<font color="#7F847E">empty</font>`
	end
	return `{rarityName(item)} ({statText(item.attack, item.defense)})`
end

local function makeCrewRow(order: number)
	local row = makeFrame(pages.Warband, UDim2.new(1, -10, 0, 76), UDim2.fromOffset(0, 0), COLOR_ROW)
	row.LayoutOrder = order
	addCorner(row, 6)

	local info = makeText(row, UDim2.new(0.34, -10, 1, -8), UDim2.fromOffset(10, 4), COLOR_TEXT, 13)
	info.RichText = true
	local gearText = makeText(row, UDim2.new(0.66, -250, 1, -8), UDim2.new(0.34, 0, 0, 4), COLOR_DIM, 12)
	gearText.RichText = true

	local function button(width: number, offset: number): TextButton
		local b = makeButton(row, UDim2.fromOffset(width, 50), UDim2.new(1, offset, 0.5, 0), COLOR_DISABLED)
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.TextSize = 13
		return b
	end
	local release = button(60, -6)
	local roll = button(70, -70)
	local train = button(98, -144)

	return { frame = row, info = info, gearText = gearText, train = train, roll = roll, release = release }
end

local youRow = makeCrewRow(nextOrder())
youRow.train.Visible = false
youRow.roll.Visible = false
youRow.release.Visible = false

local crewRows = {}
for slot = 1, GameConfig.MaxSoldierSlots do
	local row = makeCrewRow(nextOrder())
	crewRows[slot] = row
	row.train.Activated:Connect(function()
		send("Train", tostring(slot))
	end)
	row.roll.Activated:Connect(function()
		openRecruitWindow(slot)
	end)
	row.release.Activated:Connect(function()
		send("Release", tostring(slot))
	end)
end

local lockedInfo, unlockButton = makeRow(pages.Warband, nextOrder(), 56, true)
unlockButton.Activated:Connect(function()
	send("Slot")
end)

-- Armory: your gear, each with a Sell button.
local armorySummary = makeRow(pages.Armory, nextOrder(), 50, false)
armorySummary.TextColor3 = COLOR_DIM
local gearRows = {}
for index = 1, GameConfig.MaxGearOwned do
	local row = makeItemRow(pages.Armory, nextOrder())
	row.uid = nil
	gearRows[index] = row
	row.button.Activated:Connect(function()
		if row.uid then
			send("Sell", row.uid)
		end
	end)
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

local lastState = nil
local refreshRecruitWindow -- defined further down, with the recruit window

local function draw(state)
	lastState = state
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
		.. `Holdings {stats.holdingsOwned} / {stats.holdingSlots}   |   Soldiers {stats.crewSize} / {#state.crew}\n`
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

	-- Market
	marketSummary.Text = `New stock in {formatClock(state.marketRestock)}\nItems roll around your level. Rarer items are stronger and cost more.`
	for index, row in marketRows do
		local item = state.market[index]
		if not item then
			row.info.Parent.Visible = false
			continue
		end
		row.info.Parent.Visible = true
		row.info.Text = `{rarityName(item)}  Lv {item.level}  ({string.lower(item.slot)})\n{statText(item.attack, item.defense)}`
		if item.sold then
			setButton(row.button, "Sold", false, COLOR_BUY)
		elseif state.level < item.level then
			setButton(row.button, `Level {item.level}`, false, COLOR_BUY)
		else
			setButton(row.button, `Buy\n{Format.short(item.price)}`, gold >= item.price, COLOR_BUY)
		end
	end

	-- Warband
	local crew = state.crew
	warbandSummary.Text = `Soldiers {stats.crewSize} / {#crew}   |   Attack {Format.short(stats.attack)}   |   Defense {Format.short(stats.defense)}\n`
		.. `Warband size bonus +{math.floor(stats.crewBonus * 100 + 0.5)}% attack and defense`

	youRow.info.Text = `<b>You</b>, leader\nAttack {GameConfig.BaseAttack + (state.skills.attack or 0)}, defense {GameConfig.BaseDefense + (state.skills.defense or 0)} before gear`
	youRow.gearText.Text = `Weapon: {gearLine(state.yourGear.Weapon)}\nArmor: {gearLine(state.yourGear.Armor)}\nMount: {gearLine(state.yourGear.Mount)}`

	for slot, row in crewRows do
		local soldier = crew[slot]
		row.frame.Visible = soldier ~= nil
		if soldier == nil then
			continue
		end
		if soldier then
			local rank = if soldier.train > 0 then ` +{soldier.train}` else ""
			row.info.Text = `{rarityName({ rarity = soldier.rarity, name = soldier.class })}{rank}\n{soldier.name}, {soldier.tier} recruit\n{statText(soldier.attack, soldier.defense)}`
			row.gearText.Text = `Weapon: {gearLine(soldier.gear.Weapon)}\nArmor: {gearLine(soldier.gear.Armor)}\nMount: {gearLine(soldier.gear.Mount)}`
			row.train.Visible = true
			if soldier.train >= GameConfig.MaxTrainRank then
				setButton(row.train, "Fully trained", false, COLOR_BUY)
			else
				setButton(row.train, `Train +{soldier.train + 1}\n{Format.short(soldier.trainCost)}`, gold >= soldier.trainCost, COLOR_BUY)
			end
			setButton(row.roll, "Reroll", true, COLOR_ACTION)
			row.release.Visible = true
			setButton(row.release, "Release", true, COLOR_DISABLED)
		else
			row.info.Text = `<b>Empty slot {slot}</b>\nRecruit someone to fill it.`
			row.gearText.Text = ""
			row.train.Visible = false
			row.release.Visible = false
			setButton(row.roll, "Recruit", true, COLOR_ACTION)
		end
	end

	local nextSlot = #crew + 1
	lockedInfo.Parent.Visible = nextSlot <= GameConfig.MaxSoldierSlots
	if nextSlot <= GameConfig.MaxSoldierSlots then
		local slotLevel = GameConfig.getSlotLevel(nextSlot)
		local slotCost = GameConfig.getSlotCost(nextSlot)
		lockedInfo.Text = `Locked slot {nextSlot}\nEach slot costs more than the last.`
		if state.level < slotLevel then
			setButton(unlockButton, `Level {slotLevel}\n{Format.short(slotCost)}`, false, COLOR_BUY)
		else
			setButton(unlockButton, `Unlock\n{Format.short(slotCost)}`, gold >= slotCost, COLOR_BUY)
		end
	end

	-- Armory
	armorySummary.Text = `Gear {#state.gear} / {GameConfig.MaxGearOwned}. Your best weapon, armor and mount are used automatically, `
		.. `one each for you and every soldier, strongest soldier first. Buy gear in the Market.`
	local gear = table.clone(state.gear)
	local slotOrder = { Weapon = 1, Armor = 2, Mount = 3 }
	table.sort(gear, function(a, b)
		if a.slot ~= b.slot then
			return (slotOrder[a.slot] or 9) < (slotOrder[b.slot] or 9)
		end
		return a.attack + a.defense > b.attack + b.defense
	end)
	for index, row in gearRows do
		local item = gear[index]
		row.uid = if item then item.uid else nil
		row.info.Parent.Visible = item ~= nil
		if item then
			local status = if state.gearInUse[item.uid] then "In use" else "Spare"
			row.info.Text = `{rarityName(item)}  Lv {item.level}  ({string.lower(item.slot)})\n{statText(item.attack, item.defense)}   |   {status}`
			setButton(row.button, `Sell\n+{Format.short(item.price * GameConfig.SellShare)}`, true, COLOR_ACTION)
		end
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

stateRemote.OnClientEvent:Connect(function(state)
	draw(state)
	refreshRecruitWindow()
end)

---------------------------------------------------------------------------
-- Recruit window: roll soldiers until one of the chosen rarity turns up
---------------------------------------------------------------------------

local recruitGui = Instance.new("ScreenGui")
recruitGui.Name = "KingdomRecruit"
recruitGui.DisplayOrder = 5
recruitGui.ResetOnSpawn = false
recruitGui.Enabled = false
recruitGui.Parent = playerGui

local shade = makeFrame(recruitGui, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Color3.new(0, 0, 0))
shade.BackgroundTransparency = 0.45

local recruitWindow = makeFrame(recruitGui, UDim2.fromOffset(540, 430), UDim2.fromScale(0.5, 0.5), Color3.fromRGB(20, 25, 22))
recruitWindow.AnchorPoint = Vector2.new(0.5, 0.5)
addCorner(recruitWindow, 10)
local windowStroke = Instance.new("UIStroke")
windowStroke.Color = COLOR_HEADER
windowStroke.Thickness = 1.5
windowStroke.Parent = recruitWindow
local windowLimit = Instance.new("UISizeConstraint")
windowLimit.MaxSize = Vector2.new(540, 430)
windowLimit.Parent = recruitWindow
local windowScale = Instance.new("UIScale")
windowScale.Parent = recruitWindow

local recruitTitle = makeText(recruitWindow, UDim2.new(1, -70, 0, 34), UDim2.fromOffset(16, 10), COLOR_HEADER, 24)
recruitTitle.Font = Enum.Font.GothamBold
recruitTitle.Text = "RECRUIT"

local closeButton = makeButton(recruitWindow, UDim2.fromOffset(36, 36), UDim2.new(1, -46, 0, 10), COLOR_ROW)
closeButton.Text = "X"
closeButton.TextSize = 18

local targetBox = makeFrame(recruitWindow, UDim2.new(1, -32, 0, 44), UDim2.fromOffset(16, 50), Color3.fromRGB(70, 35, 30))
addCorner(targetBox, 6)
local targetText = makeText(targetBox, UDim2.new(1, -16, 1, -6), UDim2.fromOffset(8, 3), COLOR_TEXT, 13)
targetText.RichText = true

local function sectionLabel(text: string, y: number)
	local label = makeText(recruitWindow, UDim2.new(1, -32, 0, 18), UDim2.fromOffset(16, y), COLOR_DIM, 12)
	label.Font = Enum.Font.GothamBold
	label.Text = text
end

-- A row of equal buttons across the window.
local function buttonRow(count: number, y: number, height: number, perRow: number?)
	local columns = perRow or count
	local buttons = {}
	for index = 1, count do
		local column = (index - 1) % columns
		local line = math.floor((index - 1) / columns)
		local b = makeButton(
			recruitWindow,
			UDim2.new(1 / columns, -8 - 32 / columns, 0, height),
			UDim2.new(column / columns, 20 - 32 * column / columns, 0, y + line * (height + 6)),
			COLOR_ROW
		)
		buttons[index] = b
	end
	return buttons
end

sectionLabel("RECRUIT TIER", 102)
local tierButtons = buttonRow(#GameConfig.RecruitTiers, 122, 46)
sectionLabel("STOP AT THIS RARITY OR BETTER", 176)
local rarityButtons = buttonRow(#GameConfig.Rarities, 196, 32, 4)
sectionLabel("SLOTS", 272)
local scopeButtons = buttonRow(3, 292, 34)

local chanceBox = makeFrame(recruitWindow, UDim2.new(1, -32, 0, 30), UDim2.fromOffset(16, 334), COLOR_ROW)
addCorner(chanceBox, 6)
local chanceText = makeText(chanceBox, UDim2.new(1, -16, 1, 0), UDim2.fromOffset(8, 0), COLOR_TEXT, 13)

local startButton = makeButton(recruitWindow, UDim2.fromOffset(260, 44), UDim2.new(0.5, 0, 1, -14), COLOR_GOLD)
startButton.AnchorPoint = Vector2.new(0.5, 1)
startButton.TextColor3 = Color3.fromRGB(35, 28, 10)
startButton.TextSize = 18
startButton.Text = "START"

local SCOPES = { "this", "empty", "below" }
local recruitSlot = 0
local chosenTier = 1
local chosenRarity = 3
local chosenScope = "this"

-- How many slots each scope would roll for, with the current choices.
local function scopeCount(state, scope: string): number
	if scope == "this" then
		return if recruitSlot > 0 then 1 else 0
	end
	local count = 0
	for _, soldier in state.crew do
		if not soldier or (scope == "below" and GameConfig.getRarityRank(soldier.rarity) < chosenRarity) then
			count += 1
		end
	end
	return count
end

function refreshRecruitWindow()
	if not recruitGui.Enabled or not lastState then
		return
	end
	local state = lastState
	local gold = state.gold

	-- Fit the window on small screens.
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(800, 600)
	windowScale.Scale = math.min(1, (viewport.X - 20) / 540, (viewport.Y - 20) / 430)

	local slotSoldier = if recruitSlot > 0 then state.crew[recruitSlot] else nil
	if recruitSlot > 0 and slotSoldier then
		local rank = if slotSoldier.train > 0 then ` +{slotSoldier.train}` else ""
		targetText.Text = `{rarityName({ rarity = slotSoldier.rarity, name = slotSoldier.class })}{rank}  {slotSoldier.name}\n<font color="#E08A7A">Slot {recruitSlot} is replaced when a roll hits. Training is lost.</font>`
	elseif recruitSlot > 0 then
		targetText.Text = `<b>Slot {recruitSlot}</b>\nThis slot is empty.`
	else
		targetText.Text = "<b>Your warband</b>\nRoll for every empty slot, or for every slot below a rarity."
	end

	for index, tier in GameConfig.RecruitTiers do
		local b = tierButtons[index]
		local unlocked = state.level >= tier.level
		local costText = if unlocked then Format.short(tier.cost) else `Level {tier.level}`
		b.Text = `{string.upper(tier.id)}\n{costText}`
		b.BackgroundColor3 = if index == chosenTier then COLOR_SELECTED else COLOR_ROW
		b.TextColor3 = if unlocked then Color3.new(1, 1, 1) else COLOR_DIM
	end

	-- Keep the chosen rarity one this tier can roll.
	local tier = GameConfig.RecruitTiers[chosenTier]
	while chosenRarity > 1 and GameConfig.getChanceAtLeast(tier, GameConfig.Rarities[chosenRarity].id) <= 0 do
		chosenRarity -= 1
	end

	for index, rarity in GameConfig.Rarities do
		local b = rarityButtons[index]
		local possible = GameConfig.getChanceAtLeast(tier, rarity.id) > 0
		b.Text = string.upper(rarity.id)
		b.TextColor3 = if possible then rarity.color else COLOR_DISABLED
		b.BackgroundColor3 = if index == chosenRarity then COLOR_SELECTED else COLOR_ROW
	end

	if recruitSlot == 0 and chosenScope == "this" then
		chosenScope = "empty"
	end
	local labels = {
		this = if recruitSlot > 0 then "THIS SLOT ONLY" else "NO SLOT PICKED",
		empty = `EMPTY SLOTS ({scopeCount(state, "empty")})`,
		below = `BELOW {string.upper(GameConfig.Rarities[chosenRarity].id)} ({scopeCount(state, "below")})`,
	}
	for index, scope in SCOPES do
		local b = scopeButtons[index]
		b.Text = labels[scope]
		b.TextSize = 12
		b.BackgroundColor3 = if scope == chosenScope then COLOR_SELECTED else COLOR_ROW
	end

	local chance = GameConfig.getChanceAtLeast(tier, GameConfig.Rarities[chosenRarity].id)
	local expected = if chance > 0 then tier.cost / chance else 0
	chanceText.Text = string.format("Chance per roll: %.2f%%   |   Average cost per hit: %s gold", chance * 100, Format.short(expected))

	local ready = state.level >= tier.level and gold >= tier.cost and scopeCount(state, chosenScope) > 0
	startButton.BackgroundColor3 = if ready then COLOR_GOLD else COLOR_DISABLED
end

function openRecruitWindow(slot: number)
	recruitSlot = slot
	chosenScope = if slot > 0 then "this" else "empty"
	recruitGui.Enabled = true
	refreshRecruitWindow()
end

for index in GameConfig.RecruitTiers do
	tierButtons[index].Activated:Connect(function()
		chosenTier = index
		refreshRecruitWindow()
	end)
end
for index, rarity in GameConfig.Rarities do
	rarityButtons[index].Activated:Connect(function()
		if GameConfig.getChanceAtLeast(GameConfig.RecruitTiers[chosenTier], rarity.id) > 0 then
			chosenRarity = index
			refreshRecruitWindow()
		end
	end)
end
for index, scope in SCOPES do
	scopeButtons[index].Activated:Connect(function()
		if scope ~= "this" or recruitSlot > 0 then
			chosenScope = scope
			refreshRecruitWindow()
		end
	end)
end

closeButton.Activated:Connect(function()
	recruitGui.Enabled = false
end)

startButton.Activated:Connect(function()
	local tier = GameConfig.RecruitTiers[chosenTier]
	local rarity = GameConfig.Rarities[chosenRarity]
	send("Roll", `{math.max(recruitSlot, 1)}:{tier.id}:{rarity.id}:{chosenScope}`)
end)

---------------------------------------------------------------------------
-- Toasts: short messages from the server
---------------------------------------------------------------------------

local toastGui = Instance.new("ScreenGui")
toastGui.Name = "KingdomToasts"
toastGui.DisplayOrder = 10
toastGui.ResetOnSpawn = false
toastGui.Parent = playerGui

local toast = makeText(toastGui, UDim2.fromOffset(520, 40), UDim2.new(0.5, 0, 1, -54), Color3.new(1, 1, 1), 15)
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
