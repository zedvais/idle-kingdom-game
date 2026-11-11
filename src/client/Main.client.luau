-- Client entry point. There is no character to control: the camera sits above
-- the player's village and the whole game is played by tapping buttons.
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

local COLOR_PANEL = Color3.fromRGB(25, 22, 30)
local COLOR_ROW = Color3.fromRGB(45, 41, 54)
local COLOR_GOLD = Color3.fromRGB(255, 214, 90)
local COLOR_TEXT = Color3.fromRGB(235, 235, 240)
local COLOR_GREEN = Color3.fromRGB(70, 150, 85)
local COLOR_BLUE = Color3.fromRGB(65, 115, 190)
local COLOR_RED = Color3.fromRGB(180, 60, 60)
local COLOR_DISABLED = Color3.fromRGB(85, 85, 95)

local gui = Instance.new("ScreenGui")
gui.Name = "KingdomHud"
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

local function makeText(parent: Instance, size: UDim2, position: UDim2, color: Color3, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = size
	label.Position = position
	label.BackgroundTransparency = 1
	label.TextColor3 = color
	label.Font = Enum.Font.GothamBold
	label.TextSize = textSize
	label.TextWrapped = true
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
	button.AutoButtonColor = true
	button.Text = ""
	button.Parent = parent
	addCorner(button, 8)
	return button
end

-- Shows a button as usable (its own color) or greyed out.
local function setButton(button: TextButton, text: string, usable: boolean, color: Color3)
	button.Text = text
	button.BackgroundColor3 = if usable then color else COLOR_DISABLED
end

---------------------------------------------------------------------------
-- Top bar: gold, income and army power
---------------------------------------------------------------------------

local bar = Instance.new("Frame")
bar.AnchorPoint = Vector2.new(0.5, 0)
bar.Position = UDim2.new(0.5, 0, 0, 8)
bar.Size = UDim2.fromOffset(360, 70)
bar.BackgroundColor3 = COLOR_PANEL
bar.BackgroundTransparency = 0.15
bar.Parent = gui
addCorner(bar, 12)

local goldLabel = makeText(bar, UDim2.new(1, -20, 0, 34), UDim2.fromOffset(10, 6), COLOR_GOLD, 28)
local detailLabel = makeText(bar, UDim2.new(1, -20, 0, 20), UDim2.fromOffset(10, 42), COLOR_TEXT, 15)

---------------------------------------------------------------------------
-- Bottom panel with three tabs: Village, Army, Conquest
---------------------------------------------------------------------------

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.new(0.5, 0, 1, -8)
panel.Size = UDim2.new(1, -16, 0.46, 0)
panel.BackgroundColor3 = COLOR_PANEL
panel.BackgroundTransparency = 0.1
panel.Parent = gui
addCorner(panel, 12)

local panelLimit = Instance.new("UISizeConstraint")
panelLimit.MaxSize = Vector2.new(760, 330)
panelLimit.Parent = panel

local TAB_NAMES = { "Village", "Army", "Conquest" }
local tabButtons = {}
local tabPages = {}

local function showTab(name: string)
	for _, tabName in TAB_NAMES do
		tabPages[tabName].Visible = tabName == name
		tabButtons[tabName].BackgroundColor3 = if tabName == name then COLOR_BLUE else COLOR_ROW
	end
end

for index, name in TAB_NAMES do
	local button = makeButton(panel, UDim2.new(1 / 3, -8, 0, 36), UDim2.new((index - 1) / 3, 4, 0, 6), COLOR_ROW)
	button.Text = name
	button.TextSize = 16
	tabButtons[name] = button

	local page = Instance.new("ScrollingFrame")
	page.Position = UDim2.fromOffset(6, 48)
	page.Size = UDim2.new(1, -12, 1, -54)
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.ScrollBarThickness = 6
	page.CanvasSize = UDim2.new(0, 0, 0, 0)
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.Visible = false
	page.Parent = panel
	tabPages[name] = page

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = page

	button.Activated:Connect(function()
		showTab(name)
	end)
end

-- One line in a tab: text on the left, up to three buttons on the right.
local BUTTON_WIDTH = 118
local BUTTON_GAP = 6

local function makeRow(page: Instance, order: number, buttonCount: number)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -10, 0, 56)
	row.BackgroundColor3 = COLOR_ROW
	row.LayoutOrder = order
	row.Parent = page
	addCorner(row, 8)

	local buttonsWidth = buttonCount * (BUTTON_WIDTH + BUTTON_GAP) + BUTTON_GAP
	local info = makeText(row, UDim2.new(1, -(buttonsWidth + 12), 1, -8), UDim2.fromOffset(10, 4), COLOR_TEXT, 15)
	info.TextXAlignment = Enum.TextXAlignment.Left

	local buttons = {}
	for index = 1, buttonCount do
		-- index 1 is the button furthest to the right
		local offset = -(BUTTON_GAP + (index - 1) * (BUTTON_WIDTH + BUTTON_GAP))
		local button = makeButton(row, UDim2.fromOffset(BUTTON_WIDTH, 44), UDim2.new(1, offset, 0.5, 0), COLOR_DISABLED)
		button.AnchorPoint = Vector2.new(1, 0.5)
		buttons[index] = button
	end
	return info, buttons
end

-- Village tab: one row per building.
local buildingRows = {}
for index, building in GameConfig.Buildings do
	local info, buttons = makeRow(tabPages.Village, index, 3)
	local row = { info = info, upgrade = buttons[1], steward = buttons[2], collect = buttons[3] }
	buildingRows[building.id] = row

	row.upgrade.Activated:Connect(function()
		actionRemote:FireServer("Upgrade", building.id)
	end)
	row.steward.Activated:Connect(function()
		actionRemote:FireServer("Steward", building.id)
	end)
	row.collect.Activated:Connect(function()
		actionRemote:FireServer("Collect", building.id)
	end)
end

-- Army tab: one row per unit type.
local unitRows = {}
for index, unit in GameConfig.Units do
	local info, buttons = makeRow(tabPages.Army, index, 2)
	local row = { info = info, recruitTen = buttons[1], recruitOne = buttons[2] }
	unitRows[unit.id] = row

	row.recruitOne.Activated:Connect(function()
		actionRemote:FireServer("Recruit", unit.id, 1)
	end)
	row.recruitTen.Activated:Connect(function()
		actionRemote:FireServer("Recruit", unit.id, 10)
	end)
end

-- Conquest tab: the next land to attack, then the list of all lands.
local attackInfo, attackButtons = makeRow(tabPages.Conquest, 0, 1)
local attackButton = attackButtons[1]
attackButton.Activated:Connect(function()
	actionRemote:FireServer("Attack")
end)

local landRows = {}
for index, _ in GameConfig.Lands do
	local info = makeRow(tabPages.Conquest, index, 0)
	landRows[index] = info
end

showTab("Village")

---------------------------------------------------------------------------
-- Drawing the state the server sends
---------------------------------------------------------------------------

local function pointCameraAt(origin: Vector3)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 60
	-- Up and back from the village, looking down at it. The view is tilted
	-- upward a little so the village is not hidden behind the bottom panel.
	camera.CFrame = CFrame.lookAt(origin + Vector3.new(0, 85, 115), origin + Vector3.new(0, -25, 25))
end

local function draw(state)
	pointCameraAt(state.plotOrigin)

	local gold = state.gold
	goldLabel.Text = `{Format.short(gold)} gold`
	detailLabel.Text = `+{Format.short(state.goldPerSecond)} per second   |   Army power {Format.short(state.armyPower)}`

	for _, building in GameConfig.Buildings do
		local row = buildingRows[building.id]
		local info = state.buildings[building.id]
		if not info then
			continue
		end

		if info.locked then
			local land = GameConfig.Lands[building.requiresLands]
			row.info.Text = `{building.name}\nConquer {land.name} to unlock`
			setButton(row.upgrade, "Locked", false, COLOR_GREEN)
			row.steward.Visible = false
			row.collect.Visible = false
		elseif info.level == 0 then
			row.info.Text = `{building.name}\nNot built yet`
			setButton(row.upgrade, `Build\n{Format.short(info.upgradeCost)}`, gold >= info.upgradeCost, COLOR_GREEN)
			row.steward.Visible = false
			row.collect.Visible = false
		else
			setButton(row.upgrade, `Upgrade\n{Format.short(info.upgradeCost)}`, gold >= info.upgradeCost, COLOR_GREEN)
			if info.steward then
				row.info.Text = `{building.name}  Lv {info.level}\n{Format.short(info.income)} gold/s, steward collecting`
				row.steward.Visible = false
				row.collect.Visible = false
			else
				row.info.Text = `{building.name}  Lv {info.level}\n{Format.short(info.income)} gold/s, holds {Format.short(info.capacity)}`
				row.steward.Visible = true
				setButton(row.steward, `Steward\n{Format.short(info.stewardCost)}`, gold >= info.stewardCost, COLOR_BLUE)
				row.collect.Visible = true
				setButton(row.collect, `Collect\n{Format.short(info.stored)}`, info.stored >= 1, COLOR_GOLD)
				row.collect.TextColor3 = if info.stored >= 1 then Color3.fromRGB(40, 30, 10) else Color3.new(1, 1, 1)
			end
		end
	end

	for _, unit in GameConfig.Units do
		local row = unitRows[unit.id]
		local count = state.units[unit.id] or 0
		row.info.Text = `{unit.name} x{Format.short(count)}\n+{Format.short(unit.power)} power each`
		setButton(row.recruitOne, `Recruit 1\n{Format.short(unit.cost)}`, gold >= unit.cost, COLOR_GREEN)
		setButton(row.recruitTen, `Recruit 10\n{Format.short(unit.cost * 10)}`, gold >= unit.cost * 10, COLOR_GREEN)
	end

	local nextLand = GameConfig.Lands[state.landsConquered + 1]
	if nextLand then
		attackInfo.Text = `Next: {nextLand.name}\nNeeds {Format.short(nextLand.power)} power, you have {Format.short(state.armyPower)}`
		if state.attackWait > 0 then
			setButton(attackButton, `Resting\n{state.attackWait}s`, false, COLOR_RED)
		else
			setButton(attackButton, "Attack", true, COLOR_RED)
		end
	else
		attackInfo.Text = "Every land is conquered!\nA new reign is coming soon."
		setButton(attackButton, "Done", false, COLOR_RED)
	end

	for index, land in GameConfig.Lands do
		local status = if index <= state.landsConquered then "Conquered" else `Needs {Format.short(land.power)} power`
		landRows[index].Text = `{land.name}: {status}\nReward: +{math.floor(land.bonus * 100)}% gold`
	end
end

stateRemote.OnClientEvent:Connect(draw)

---------------------------------------------------------------------------
-- Toasts: short messages from the server
---------------------------------------------------------------------------

local toast = makeText(gui, UDim2.fromOffset(460, 40), UDim2.new(0.5, 0, 0, 86), Color3.new(1, 1, 1), 16)
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.BackgroundColor3 = COLOR_PANEL
toast.BackgroundTransparency = 0.15
toast.Visible = false
addCorner(toast, 10)

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
	local window = Instance.new("Frame")
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.4)
	window.Size = UDim2.fromOffset(380, 200)
	window.BackgroundColor3 = COLOR_PANEL
	window.ZIndex = 10
	window.Parent = gui
	addCorner(window, 14)

	local title = makeText(window, UDim2.new(1, -30, 0, 36), UDim2.fromOffset(15, 14), Color3.new(1, 1, 1), 22)
	title.Text = "Welcome back, my liege!"
	title.ZIndex = 11

	local body = makeText(window, UDim2.new(1, -30, 0, 60), UDim2.fromOffset(15, 58), COLOR_GOLD, 18)
	body.Text = `Your stewards collected {Format.short(amount)} gold while you were away.`
	body.ZIndex = 11

	local button = makeButton(window, UDim2.fromOffset(160, 44), UDim2.new(0.5, 0, 1, -14), COLOR_GREEN)
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Text = "Splendid"
	button.TextSize = 18
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
