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

local PAGE_NAMES = { "Keep", "Quests", "Holdings", "Market", "Warband", "Inventory", "Foes", "Bank" }
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
	local button = makeButton(rail, UDim2.new(1, -12, 0, 34), UDim2.fromOffset(0, 0), COLOR_ROW)
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

-- A row with a label on the left and several buttons sharing the rest.
local function makeButtonRow(page: Instance, order: number, labelText: string, names: { string }, labelWidth: number?)
	local row = makeFrame(page, UDim2.new(1, -10, 0, 44), UDim2.fromOffset(0, 0), COLOR_ROW)
	row.LayoutOrder = order
	addCorner(row, 6)
	local width = if labelText == "" then 0 else (labelWidth or 130)
	local label = makeText(row, UDim2.new(0, width - 10, 1, 0), UDim2.fromOffset(10, 0), COLOR_TEXT, 13)
	label.Text = labelText
	local buttons = {}
	local share = 1 / #names
	for index, name in names do
		local b = makeButton(
			row,
			UDim2.new(share, -(width / #names) - 6, 1, -10),
			UDim2.new(share * (index - 1), width - (width * (index - 1) / #names) + 3, 0, 5),
			COLOR_DISABLED
		)
		b.Text = name
		b.TextSize = 13
		buttons[index] = b
	end
	return buttons, label
end

-- A dark text box for typing an amount.
local function makeAmountBox(parent: Instance, size: UDim2, position: UDim2, placeholder: string): TextBox
	local box = Instance.new("TextBox")
	box.Size = size
	box.Position = position
	box.BackgroundColor3 = Color3.fromRGB(20, 24, 22)
	box.TextColor3 = COLOR_TEXT
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = COLOR_DIM
	box.Font = Enum.Font.GothamBold
	box.TextSize = 15
	box.Text = ""
	box.ClearTextOnFocus = false
	box.Parent = parent
	addCorner(box, 6)
	return box
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

-- A region header that folds its rows away when clicked, like the
-- reference's city bars. Returns a function that registers a row under it.
local function makeRegionHeader(page: Instance, order: number, region)
	local header = makeButton(page, UDim2.new(1, -10, 0, 40), UDim2.fromOffset(0, 0), Color3.fromRGB(44, 38, 28))
	header.LayoutOrder = order
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.TextColor3 = COLOR_HEADER
	header.TextSize = 18
	local stroke = Instance.new("UIStroke")
	stroke.Color = COLOR_HEADER
	stroke.Transparency = 0.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = header
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = header

	local open = region.level == 1
	local rows = {}
	local levelText = if region.level > 1 then `  (LEVEL {region.level}+)` else ""
	local function update()
		header.Text = `{if open then "-" else "+"}   {string.upper(region.id)}{levelText}`
		for _, row in rows do
			row.Visible = open
		end
	end
	header.Activated:Connect(function()
		open = not open
		update()
	end)
	update()

	return function(row: GuiObject)
		table.insert(rows, row)
		row.Visible = open
	end
end

-- Keep: your home, your numbers, daily rewards and skills.
local keepInfo, keepButton = makeRow(pages.Keep, nextOrder(), 74, true)
keepButton.Activated:Connect(function()
	send("Keep")
end)
local keepSummary = makeRow(pages.Keep, nextOrder(), 74, false)
local breakdownText = makeRow(pages.Keep, nextOrder(), 96, false)
breakdownText.TextColor3 = COLOR_DIM

makeHeading(pages.Keep, nextOrder(), "Daily playtime rewards")
local playtimeSummary = makeRow(pages.Keep, nextOrder(), 32, false)
local rewardRows = {}
for index, reward in GameConfig.PlaytimeRewards do
	local info, button = makeRow(pages.Keep, nextOrder(), 46, true)
	rewardRows[index] = { info = info, button = button }
	button.Activated:Connect(function()
		send("Claim", tostring(index))
	end)
	info.Text = `{reward.minutes} min: {reward.label}`
end

makeHeading(pages.Keep, nextOrder(), "Skills")
local skillRows = {}
for _, skill in GameConfig.Skills do
	local info, button = makeRow(pages.Keep, nextOrder(), 50, true)
	skillRows[skill.id] = { info = info, button = button }
	button.Activated:Connect(function()
		send("Skill", skill.id)
	end)
end

-- Quests, in folding regions.
local questRows = {}
local autoQuestInfo, autoQuestButton = makeRow(pages.Quests, nextOrder(), 50, true)
autoQuestInfo.RichText = true
local autoQuestOn = false
autoQuestButton.Activated:Connect(function()
	send("AutoQuest", if autoQuestOn then "off" else "on")
end)
local questBoost = makeRow(pages.Quests, nextOrder(), 30, false)
questBoost.TextColor3 = COLOR_XP
for _, region in GameConfig.Regions do
	local addRow = makeRegionHeader(pages.Quests, nextOrder(), region)
	for _, quest in GameConfig.Quests do
		if quest.region == region.id then
			local info, button = makeRow(pages.Quests, nextOrder(), 56, true)
			info.RichText = true
			addRow(info.Parent)
			questRows[quest.id] = { info = info, button = button }
			button.Activated:Connect(function()
				send("Quest", quest.id)
			end)
		end
	end
end

-- Holdings: what you have built, then what you can build, by region.
local holdingSummary = makeRow(pages.Holdings, nextOrder(), 50, false)
makeHeading(pages.Holdings, nextOrder(), "Your lands")
local ownedEmpty = makeRow(pages.Holdings, nextOrder(), 34, false)
ownedEmpty.TextColor3 = COLOR_DIM
ownedEmpty.Text = "Nothing built yet. Build a holding below."
local ownedRows = {}
for _, holding in GameConfig.Holdings do
	local info, button = makeRow(pages.Holdings, nextOrder(), 46, true)
	ownedRows[holding.id] = { info = info, button = button }
	button.Activated:Connect(function()
		send("Demolish", holding.id)
	end)
end
makeHeading(pages.Holdings, nextOrder(), "Build")
local holdingRows = {}
for _, region in GameConfig.Regions do
	local addRow = makeRegionHeader(pages.Holdings, nextOrder(), region)
	for _, holding in GameConfig.Holdings do
		if holding.region == region.id then
			local info, button = makeRow(pages.Holdings, nextOrder(), 52, true)
			addRow(info.Parent)
			holdingRows[holding.id] = { info = info, button = button }
			button.Activated:Connect(function()
				send("Holding", holding.id)
			end)
		end
	end
end

-- Bank: move gold in and out. Gold in the bank is safe from raids.
local bankSummary = makeRow(pages.Bank, nextOrder(), 74, false)
local bankInputRow = makeFrame(pages.Bank, UDim2.new(1, -10, 0, 56), UDim2.fromOffset(0, 0), COLOR_ROW)
bankInputRow.LayoutOrder = nextOrder()
addCorner(bankInputRow, 6)
local bankInput = Instance.new("TextBox")
bankInput.Size = UDim2.new(1, -20, 1, -16)
bankInput.Position = UDim2.fromOffset(10, 8)
bankInput.BackgroundColor3 = Color3.fromRGB(20, 24, 22)
bankInput.TextColor3 = COLOR_TEXT
bankInput.PlaceholderText = "Amount, like 5000 or 2.5m"
bankInput.PlaceholderColor3 = COLOR_DIM
bankInput.Font = Enum.Font.GothamBold
bankInput.TextSize = 20
bankInput.Text = ""
bankInput.ClearTextOnFocus = false
bankInput.Parent = bankInputRow
addCorner(bankInput, 6)

local bankButtons = makeFrame(pages.Bank, UDim2.new(1, -10, 0, 96), UDim2.fromOffset(0, 0), COLOR_ROW)
bankButtons.LayoutOrder = nextOrder()
bankButtons.BackgroundTransparency = 1
local function bankButton(text: string, x: number, y: number, color: Color3, callback)
	local b = makeButton(bankButtons, UDim2.new(0.5, -5, 0, 44), UDim2.new(x, if x > 0 then 5 else 0, 0, y), color)
	b.Text = text
	b.TextSize = 16
	b.Activated:Connect(callback)
	return b
end
bankButton("Deposit", 0, 0, COLOR_GOLD, function()
	send("Deposit", bankInput.Text)
end).TextColor3 = Color3.fromRGB(35, 28, 10)
bankButton("Withdraw", 0.5, 0, COLOR_SELECTED, function()
	send("Withdraw", bankInput.Text)
end)
bankButton("Deposit all", 0, 50, COLOR_ROW, function()
	send("Deposit", "all")
end)
bankButton("Withdraw all", 0.5, 50, COLOR_ROW, function()
	send("Withdraw", "all")
end)
local bankNote = makeRow(pages.Bank, nextOrder(), 50, false)
bankNote.TextColor3 = COLOR_DIM
bankNote.Text = `Depositing costs a {math.floor(GameConfig.BankFee * 100)}% fee. You spend gold on hand, so withdraw before buying. `
	.. "Once raids arrive, only gold on hand can be stolen."

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

makeHeading(pages.Market, nextOrder(), "Auto-buy")
local autoBuyInfo, autoBuyButton = makeRow(pages.Market, nextOrder(), 56, true)
autoBuyInfo.RichText = true
local autoBuyRunning = false
autoBuyButton.Activated:Connect(function()
	send("AutoBuy", if autoBuyRunning then "off" else "on")
end)

local slotButtons = makeButtonRow(pages.Market, nextOrder(), "Buy these", GameConfig.GearSlots)
for index, slot in GameConfig.GearSlots do
	slotButtons[index].Activated:Connect(function()
		send("AutoBuy", "slot:" .. slot)
	end)
end

local rarityChoices = {}
for _, rarity in GameConfig.Rarities do
	if rarity.chance > 0 then
		table.insert(rarityChoices, rarity.id)
	end
end
local rarityButtons = makeButtonRow(pages.Market, nextOrder(), "Lowest rarity", rarityChoices)
for index, rarityId in rarityChoices do
	rarityButtons[index].Activated:Connect(function()
		send("AutoBuy", "rarity:" .. rarityId)
	end)
end

local priceRow = makeFrame(pages.Market, UDim2.new(1, -10, 0, 44), UDim2.fromOffset(0, 0), COLOR_ROW)
priceRow.LayoutOrder = nextOrder()
addCorner(priceRow, 6)
makeText(priceRow, UDim2.new(0, 120, 1, 0), UDim2.fromOffset(10, 0), COLOR_TEXT, 13).Text = "Price range"
local minBox = makeAmountBox(priceRow, UDim2.new(0.5, -(65 + BUTTON_WIDTH / 2 + 12), 1, -10), UDim2.new(0, 130, 0, 5), "Min: none")
local maxBox = makeAmountBox(priceRow, UDim2.new(0.5, -(65 + BUTTON_WIDTH / 2 + 12), 1, -10), UDim2.new(0.5, 65 - BUTTON_WIDTH / 2 + 2, 0, 5), "Max: none")
local priceButton = makeButton(priceRow, UDim2.new(0, BUTTON_WIDTH, 1, -10), UDim2.new(1, -6, 0, 5), COLOR_BUY)
priceButton.AnchorPoint = Vector2.new(1, 0)
priceButton.Text = "Save prices"
priceButton.Activated:Connect(function()
	send("AutoBuy", "min:" .. string.sub(minBox.Text, 1, 40))
	send("AutoBuy", "max:" .. string.sub(maxBox.Text, 1, 40))
end)

local brokeButtons = makeButtonRow(pages.Market, nextOrder(), "Out of gold", { "Wait for more", "Stop auto-buy" })
brokeButtons[1].Activated:Connect(function()
	send("AutoBuy", "broke:wait")
end)
brokeButtons[2].Activated:Connect(function()
	send("AutoBuy", "broke:stop")
end)

local recentBuys = makeRow(pages.Market, nextOrder(), 110, false)
recentBuys.RichText = true
recentBuys.TextYAlignment = Enum.TextYAlignment.Top

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

-- Inventory: tabs for gear by slot and for trophies, and a rarity filter.
local INVENTORY_TABS = { "All", "Weapon", "Armor", "Mount", "Trophies" }
local inventoryTab = "All"
local inventoryRarity = 0 -- 0 shows every rarity, otherwise the lowest rank shown
local redraw -- draws the last state again; defined after draw()
local tabButtons = makeButtonRow(pages.Inventory, nextOrder(), "", INVENTORY_TABS)
local filterInfo, filterButton = makeRow(pages.Inventory, nextOrder(), 44, true)
filterInfo.TextColor3 = COLOR_DIM
filterButton.Activated:Connect(function()
	inventoryRarity = (inventoryRarity + 1) % (#GameConfig.Rarities + 1)
	redraw()
end)
for index, tab in INVENTORY_TABS do
	tabButtons[index].Activated:Connect(function()
		inventoryTab = tab
		redraw()
	end)
end
local armorySummary = makeRow(pages.Inventory, nextOrder(), 50, false)
armorySummary.TextColor3 = COLOR_DIM

local trophyRows = {}
for _, trophy in GameConfig.Trophies do
	local info, button = makeRow(pages.Inventory, nextOrder(), 52, true)
	info.RichText = true
	button.AutoButtonColor = false
	trophyRows[trophy.id] = { info = info, button = button }
end
local gearRows = {}
for index = 1, GameConfig.MaxGearOwned do
	local row = makeItemRow(pages.Inventory, nextOrder())
	row.uid = nil
	gearRows[index] = row
	row.button.Activated:Connect(function()
		if row.uid then
			send("Sell", row.uid)
		end
	end)
end

-- Foes: a fight panel for the chosen stage, then every stage by house,
-- then the token shop.
local foeSummary = makeRow(pages.Foes, nextOrder(), 50, false)
foeSummary.RichText = true

local fightInfo, fightButton = makeRow(pages.Foes, nextOrder(), 132, true)
fightInfo.RichText = true
fightInfo.Size = UDim2.new(1, -(BUTTON_WIDTH + 26), 0, 74)
local fightPanel = fightInfo.Parent
fightPanel.BackgroundColor3 = Color3.fromRGB(58, 44, 40)
local yourFightBar = makeBar(fightPanel, UDim2.new(0.5, -(BUTTON_WIDTH / 2 + 22), 0, 18), UDim2.new(0, 10, 1, -48), COLOR_HEALTH)
local foeFightBar = makeBar(fightPanel, UDim2.new(0.5, -(BUTTON_WIDTH / 2 + 22), 0, 18), UDim2.new(0.5, -(BUTTON_WIDTH / 2 - 6), 1, -48), COLOR_ACTION)

local selectedStage = nil -- stage id the fight panel shows
fightButton.Activated:Connect(function()
	if selectedStage then
		send("Fight", selectedStage)
	end
end)

local stageRows = {}
local lastHouse = nil
for _, stage in GameConfig.Stages do
	if stage.houseName ~= lastHouse then
		lastHouse = stage.houseName
		makeHeading(pages.Foes, nextOrder(), stage.houseName)
	end
	local info, button = makeRow(pages.Foes, nextOrder(), 56, true)
	info.RichText = true
	stageRows[stage.id] = { info = info, button = button }
	button.Activated:Connect(function()
		selectedStage = stage.id
		pages.Foes.CanvasPosition = Vector2.new(0, 0)
	end)
end

makeHeading(pages.Foes, nextOrder(), "Token shop")
local tokenRows = {}
for _, item in GameConfig.TokenShop do
	local info, button = makeRow(pages.Foes, nextOrder(), 46, true)
	info.Text = `<b>{item.name}</b>\n{item.note}`
	info.RichText = true
	tokenRows[item.id] = button
	button.Activated:Connect(function()
		send("TokenBuy", item.id)
	end)
end

showPage("Quests")

---------------------------------------------------------------------------
-- Drawing the state the server sends
---------------------------------------------------------------------------

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
	incomeLabel.Text = `+{Format.short(stats.incomePerHour)}/hr   |   Banked {Format.short(state.banked)}`
	setBar(energyBar, state.energy, stats.maxEnergy, `Energy {state.energy} / {stats.maxEnergy}`)
	setBar(staminaBar, state.stamina, stats.maxStamina, `Stamina {state.stamina} / {stats.maxStamina}`)
	setBar(healthBar, state.health, stats.maxHealth, `Health {state.health} / {stats.maxHealth}`)

	-- A dot on the Keep button when there are points to spend.
	railButtons.Keep.Text = if state.skillPoints > 0 then `Keep ({state.skillPoints})` else "Keep"

	-- Keep
	local keep = GameConfig.KeepLevels[state.keep]
	local nextKeep = GameConfig.KeepLevels[state.keep + 1]
	local keepText = `<b>{string.upper(keep.name)}</b>   Keep level {state.keep} of {#GameConfig.KeepLevels}\n`
		.. `Income, attack and defense +{math.floor(keep.bonus * 100)}%`
	if nextKeep then
		keepText ..= `\nNext: {nextKeep.name}, +{math.floor(nextKeep.bonus * 100)}%`
		if state.level < nextKeep.level then
			setButton(keepButton, `Level {nextKeep.level}\n{Format.short(nextKeep.cost)}`, false, COLOR_BUY)
		else
			setButton(keepButton, `Upgrade\n{Format.short(nextKeep.cost)}`, gold >= nextKeep.cost, COLOR_BUY)
		end
	else
		setButton(keepButton, "Max level", false, COLOR_BUY)
	end
	keepInfo.RichText = true
	keepInfo.Text = keepText

	keepSummary.Text = `Attack {Format.short(stats.attack)}   |   Defense {Format.short(stats.defense)}   |   Renown {Format.short(state.renown)}\n`
		.. `Income {Format.short(stats.incomePerHour)}/hr   |   Lots {stats.lotsUsed} / {stats.lots}   |   Soldiers {stats.crewSize} / {#state.crew}\n`
		.. `Skill points to spend: {state.skillPoints}`
	local lines = { "Where your attack and defense come from:" }
	for _, part in stats.breakdown do
		table.insert(lines, `{part[1]}: {Format.short(part[2])} attack, {Format.short(part[3])} defense`)
	end
	breakdownText.Text = table.concat(lines, "\n")

	local played = state.playSeconds
	playtimeSummary.Text = `Played today: {math.floor(played / 3600)}h {math.floor(played / 60) % 60}m. Rewards reset at 00:00 UTC.`
	for index, reward in GameConfig.PlaytimeRewards do
		local row = rewardRows[index]
		local key = tostring(index)
		if state.claimed[key] then
			setButton(row.button, "Claimed", false, COLOR_BUY)
		elseif played >= reward.minutes * 60 then
			setButton(row.button, "Claim", true, COLOR_GOLD)
		else
			setButton(row.button, `In {formatClock(reward.minutes * 60 - played)}`, false, COLOR_BUY)
		end
	end

	for _, skill in GameConfig.Skills do
		local row = skillRows[skill.id]
		local bought = state.skills[skill.id] or 0
		local cost = GameConfig.getSkillCost(skill, bought)
		row.info.Text = `{skill.name}  (bought {bought})\n{skill.note}`
		local pointWord = if cost == 1 then "point" else "points"
		setButton(row.button, `Add\n{cost} {pointWord}`, state.skillPoints >= cost, COLOR_BUY)
	end

	-- Quests
	autoQuestOn = state.autoQuestOn
	local autoTarget = nil
	for _, quest in GameConfig.Quests do
		if quest.id == state.autoQuest then
			autoTarget = quest
		end
	end
	if autoTarget then
		autoQuestInfo.Text = `<b>Auto quests: {if autoQuestOn then "ON" else "OFF"}</b>\n`
			.. `Repeats <b>{autoTarget.name}</b> whenever you have {autoTarget.energy} energy. Do another quest to switch.`
	else
		autoQuestInfo.Text = "<b>Auto quests: OFF</b>\nDo a quest once, then turn this on to keep repeating it while you play."
	end
	setButton(autoQuestButton, if autoQuestOn then "Turn off" else "Turn on", autoTarget ~= nil, if autoQuestOn then COLOR_DISABLED else COLOR_ACTION)
	questBoost.Text = if state.xpBoostLeft > 0 then `Double XP active: {formatClock(state.xpBoostLeft)} left` else ""
	questBoost.Parent.Visible = state.xpBoostLeft > 0
	local medalColors = { "#C8844E", "#C9D2DE", "#F0C85A" }
	for _, quest in GameConfig.Quests do
		local row = questRows[quest.id]
		local done = state.quests[quest.id] or 0
		local rank = GameConfig.getMasteryRank(done)
		local medals = {}
		for index, medal in GameConfig.MasteryMedals do
			local color = if index <= rank then medalColors[index] else "#5A5F5A"
			table.insert(medals, `<font color="{color}">{medal}</font>`)
		end
		local progress = if rank >= GameConfig.MaxMasteryRanks
			then "Mastered"
			else `{done % GameConfig.MasteryPerRank}/{GameConfig.MasteryPerRank}`
		row.info.Text = `<b>{quest.name}</b>\n{quest.energy} energy   {Format.short(GameConfig.getQuestGold(quest, done))} gold   {quest.xp} XP   `
			.. `{string.format("%.1f", quest.drop * 100)}% gear drop\n{table.concat(medals, "  ")}   {progress}`
		if state.level < quest.level then
			setButton(row.button, `Level {quest.level}`, false, COLOR_ACTION)
		else
			setButton(row.button, "Do Quest", state.energy >= quest.energy, COLOR_ACTION)
		end
	end

	-- Holdings
	local lotsFull = stats.lotsUsed >= stats.lots
	holdingSummary.Text = `Income {Format.short(stats.incomePerHour)} gold/hr   |   Lots {stats.lotsUsed} / {stats.lots}{if lotsFull then " (full)" else ""}\n`
		.. `Holdings earn {math.floor(GameConfig.OfflineRate * 100)}% while you are away. More lots come from skill points in the Keep.`
	local anyOwned = false
	for _, holding in GameConfig.Holdings do
		local count = state.holdings[holding.id] or 0
		local ownedRow = ownedRows[holding.id]
		ownedRow.info.Parent.Visible = count > 0
		if count > 0 then
			anyOwned = true
			local income = math.floor(holding.income * count * (1 + stats.keepBonus))
			ownedRow.info.Text = `{holding.name}  x{count}\n{Format.short(income)} gold/hr`
			local refund = math.floor(GameConfig.getHoldingCost(holding, count - 1) * GameConfig.DemolishRefund)
			setButton(ownedRow.button, `Demolish 1\n+{Format.short(refund)}`, true, COLOR_DISABLED)
		end

		local row = holdingRows[holding.id]
		local cost = GameConfig.getHoldingCost(holding, count)
		row.info.Text = `{holding.name}  (you have {count})\n+{Format.short(holding.income)} gold/hr per lot`
		if state.level < holding.level then
			setButton(row.button, `Level {holding.level}`, false, COLOR_BUY)
		elseif lotsFull then
			setButton(row.button, `Lots full\n{Format.short(cost)}`, false, COLOR_BUY)
		else
			setButton(row.button, `Build\n{Format.short(cost)}`, gold >= cost, COLOR_BUY)
		end
	end
	ownedEmpty.Parent.Visible = not anyOwned

	-- Bank
	bankSummary.Text = `On hand: {Format.short(gold)} gold\nBanked: {Format.short(state.banked)} gold\n`
		.. `Deposit fee {math.floor(GameConfig.BankFee * 100)}%`

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

	-- Auto-buy
	local rule = state.autoBuy
	autoBuyRunning = rule.on
	autoBuyInfo.Text = `<b>{if rule.on then "RUNNING" else "STOPPED"}</b>   Bought {rule.bought}, spent {Format.short(rule.spent)} gold\n`
		.. "Buys matching Market items as they appear, while you are in the game."
	setButton(autoBuyButton, if rule.on then "Stop" else "Start", true, if rule.on then COLOR_ACTION else COLOR_BUY)
	for index, slot in GameConfig.GearSlots do
		setButton(slotButtons[index], slot, rule.slots[slot] == true, COLOR_SELECTED)
	end
	for index, rarityId in rarityChoices do
		setButton(rarityButtons[index], rarityId, rarityId == rule.minRarity, COLOR_SELECTED)
	end
	minBox.PlaceholderText = if rule.minPrice > 0 then `Min: {Format.short(rule.minPrice)}` else "Min: none"
	maxBox.PlaceholderText = if rule.maxPrice > 0 then `Max: {Format.short(rule.maxPrice)}` else "Max: none"
	setButton(brokeButtons[1], "Wait for more", rule.whenBroke == "wait", COLOR_SELECTED)
	setButton(brokeButtons[2], "Stop auto-buy", rule.whenBroke == "stop", COLOR_SELECTED)
	local recentLines = { "<b>Recent buys</b>" }
	for _, buy in rule.recent do
		table.insert(recentLines, `{rarityName(buy)}   {Format.short(buy.price)} gold`)
	end
	if #rule.recent == 0 then
		table.insert(recentLines, "Nothing yet.")
	end
	recentBuys.Text = table.concat(recentLines, "\n")

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

	-- Inventory
	for index, tab in INVENTORY_TABS do
		setButton(tabButtons[index], if tab == "Trophies" then tab else (if tab == "All" then "All gear" else tab .. "s"), tab == inventoryTab, COLOR_SELECTED)
	end
	local showTrophies = inventoryTab == "Trophies"
	filterInfo.Parent.Visible = not showTrophies
	local filterRarity = GameConfig.Rarities[inventoryRarity]
	filterInfo.Text = if filterRarity then `Showing {filterRarity.id} and rarer` else "Showing every rarity"
	setButton(filterButton, "Change rarity", true, COLOR_SELECTED)

	local earnedCount = 0
	for _, trophy in GameConfig.Trophies do
		local row = trophyRows[trophy.id]
		local earned = state.trophies[trophy.id] == true
		if earned then
			earnedCount += 1
		end
		row.info.Parent.Visible = showTrophies
		local bonuses = {}
		for _, pair in GameConfig.TrophyBonusNames do
			local amount = trophy[pair[1]]
			if amount then
				table.insert(bonuses, `+{math.floor(amount * 100 + 0.5)}% {pair[2]}`)
			end
		end
		local progress = state.trophyProgress[trophy.id] or 0
		row.info.Text = `<b>{trophy.name}</b>   <font color="#9FD49A">{table.concat(bonuses, ", ")}</font>\n`
			.. (if earned then trophy.note else `{trophy.note}   ({progress} / {trophy.value})`)
		setButton(row.button, if earned then "Earned" else "Locked", earned, COLOR_GOLD)
		row.button.TextColor3 = if earned then Color3.fromRGB(35, 28, 10) else Color3.new(1, 1, 1)
	end

	if showTrophies then
		local bonus = stats.trophyBonus
		armorySummary.Text = `Trophies {earnedCount} / {#GameConfig.Trophies}. Their bonuses never go away.   Now: `
			.. `+{math.floor(bonus.attack * 100 + 0.5)}% attack, +{math.floor(bonus.defense * 100 + 0.5)}% defense, `
			.. `+{math.floor(bonus.income * 100 + 0.5)}% income, +{math.floor(bonus.xp * 100 + 0.5)}% quest XP, +{math.floor(bonus.questGold * 100 + 0.5)}% quest gold`
	else
		armorySummary.Text = `Gear {#state.gear} / {GameConfig.MaxGearOwned}. Your best weapon, armor and mount are used automatically, `
			.. `one each for you and every soldier, strongest soldier first. Buy gear in the Market.`
	end
	local gear = {}
	for _, item in state.gear do
		local slotMatches = inventoryTab == "All" or item.slot == inventoryTab
		if not showTrophies and slotMatches and GameConfig.getRarityRank(item.rarity) >= math.max(1, inventoryRarity) then
			table.insert(gear, item)
		end
	end
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
	local function stageOpen(stage)
		return state.level >= stage.level and stage.index <= state.highestStage + 1
	end
	-- Keep the panel on the chosen stage; otherwise show the first one
	-- still to beat today.
	local chosen = selectedStage and GameConfig.Stages[tonumber(string.sub(selectedStage, 2)) or 0]
	if not chosen or state.stageCleared[chosen.id] or not stageOpen(chosen) then
		chosen = nil
		for _, stage in GameConfig.Stages do
			if stageOpen(stage) and not state.stageCleared[stage.id] then
				chosen = stage
				break
			end
		end
		selectedStage = chosen and chosen.id
	end

	foeSummary.Text = `<b>{state.tokens} boss tokens</b>   |   Highest stage {state.highestStage}   |   Foes return in {formatClock(state.stageReset)}\n`
		.. "Beat each stage once a day. Each win opens the next stage. Spend tokens in the token shop below."
	local hitLow = math.max(1, math.floor(GameConfig.getHit(stats.attack, chosen and chosen.defense or 0) * GameConfig.HitRollMin))
	local hitHigh = math.max(1, math.floor(GameConfig.getHit(stats.attack, chosen and chosen.defense or 0) * GameConfig.HitRollMax))
	setBar(yourFightBar, state.health, stats.maxHealth, `You: {state.health} / {stats.maxHealth}`)
	if chosen then
		local foeHealth = state.stageHealth[chosen.id] or chosen.health
		local chest = if chosen.chest then `, {chosen.chest} chest` else ""
		fightInfo.Text = `<b>STAGE {chosen.index}: {chosen.name}</b>  ({chosen.title})\n`
			.. `You hit {Format.short(hitLow)} to {Format.short(hitHigh)}   vs   defense {Format.short(chosen.defense)}, attack {Format.short(chosen.attack)}\n`
			.. `Reward: {Format.short(chosen.gold)} gold, {chosen.xp} XP, {chosen.tokens} tokens{chest}`
		setBar(foeFightBar, foeHealth, chosen.health, `Foe: {Format.short(foeHealth)} / {Format.short(chosen.health)}`)
		local ready = state.stamina >= 1 and state.health >= GameConfig.MinHealthToFight
		local label = if state.stamina < 1 then "No stamina" elseif not ready then "Too wounded" else "Attack\n1 stamina"
		setButton(fightButton, label, ready, COLOR_ACTION)
	else
		local nextStage = GameConfig.Stages[state.highestStage + 1]
		fightInfo.Text = if nextStage and state.level < nextStage.level
			then `<b>All open stages are beaten for today.</b>\nThe next stage opens at level {nextStage.level}.`
			else "<b>All open stages are beaten for today.</b>\nFoes return at 00:00 UTC."
		setBar(foeFightBar, 0, 1, "")
		setButton(fightButton, "Done", false, COLOR_ACTION)
	end

	for _, stage in GameConfig.Stages do
		local row = stageRows[stage.id]
		local chest = if stage.chest then `   {stage.chest} chest` else ""
		row.info.Text = `<b>Stage {stage.index}: {stage.name}</b>   Level {stage.level}\n`
			.. `{Format.short(stage.health)} health, {Format.short(stage.defense)} defense   |   {stage.tokens} tokens{chest}`
		if state.stageCleared[stage.id] then
			setButton(row.button, "Done today", false, COLOR_BUY)
		elseif state.level < stage.level then
			setButton(row.button, `Level {stage.level}`, false, COLOR_ACTION)
		elseif not stageOpen(stage) then
			setButton(row.button, "Locked", false, COLOR_ACTION)
		elseif stage.id == selectedStage then
			setButton(row.button, "Selected", true, COLOR_SELECTED)
		else
			setButton(row.button, "Fight", true, COLOR_ACTION)
		end
	end

	for _, item in GameConfig.TokenShop do
		setButton(tokenRows[item.id], `Buy\n{item.cost} tokens`, state.tokens >= item.cost, COLOR_BUY)
	end
end

redraw = function()
	if lastState then
		draw(lastState)
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
