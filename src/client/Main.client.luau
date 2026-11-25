-- Client entry point. The whole game is menus: a status bar on top, a list
-- of sections on the left, and the open section in the middle.
-- The server sends a "state" table about once a second and after every
-- action. This script only draws that state and asks the server to do things.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local StoreConfig = require(Shared:WaitForChild("StoreConfig"))
local BountyConfig = require(Shared:WaitForChild("BountyConfig"))
local FestivalConfig = require(Shared:WaitForChild("FestivalConfig"))
local ResearchConfig = require(Shared:WaitForChild("ResearchConfig"))
local EstateConfig = require(Shared:WaitForChild("EstateConfig"))
local Format = require(Shared:WaitForChild("Format"))
local Art = require(script.Parent:WaitForChild("Art")) -- colors, icons and styling, all drawn in code
local ItemArt = require(script.Parent:WaitForChild("ItemArt")) -- item pictures with rarity glows
local ChestConfig = require(Shared:WaitForChild("ChestConfig")) -- chests (Market chest rows)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local actionRemote = remotes:WaitForChild("Action")
local stateRemote = remotes:WaitForChild("State")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Colors. Gold buttons are the main action, red is attack or danger,
-- blue is help, green is claim.
local COLOR_BACKGROUND = Color3.fromRGB(22, 17, 13)
local COLOR_PANEL = Color3.fromRGB(38, 30, 23)
local COLOR_ROW = Color3.fromRGB(54, 43, 33)
local COLOR_EDGE = Color3.fromRGB(96, 76, 50)
local COLOR_HEADER = Color3.fromRGB(226, 192, 120)
local COLOR_TEXT = Color3.fromRGB(242, 234, 216)
local COLOR_DIM = Color3.fromRGB(178, 166, 144)
local COLOR_GOLD = Color3.fromRGB(240, 196, 80)
local COLOR_ACTION = Color3.fromRGB(168, 58, 46)
local COLOR_BUY = Color3.fromRGB(218, 166, 60)
local COLOR_CLAIM = Color3.fromRGB(72, 142, 82)
local COLOR_INFO = Color3.fromRGB(70, 128, 176)
local COLOR_SELECTED = Color3.fromRGB(104, 76, 42)
local COLOR_DISABLED = Color3.fromRGB(78, 70, 62)
local COLOR_ENERGY = Color3.fromRGB(215, 170, 60)
local COLOR_STAMINA = Color3.fromRGB(70, 130, 190)
local COLOR_HEALTH = Color3.fromRGB(180, 65, 65)
local COLOR_XP = Color3.fromRGB(130, 100, 190)

local TOP_HEIGHT = 72
local RAIL_WIDTH = 150
local LEFT_BLOCK = 270 -- top bar: level, name and XP
local RIGHT_BLOCK = 240 -- top bar: energy, stamina and health
local ICON_BLOCK = 76 -- top bar: the Mail button

-- A plain backdrop that covers the whole screen, including the top strip.
do
	local backdropGui = Instance.new("ScreenGui")
	backdropGui.Name = "KingdomBackdrop"
	backdropGui.IgnoreGuiInset = true
	backdropGui.DisplayOrder = -1
	backdropGui.ResetOnSpawn = false
	backdropGui.Parent = playerGui

	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(1, 1, 1)
	backdrop.BorderSizePixel = 0
	backdrop.Parent = backdropGui
	-- Night sky fading to a warm glow at the horizon.
	local sky = Instance.new("UIGradient")
	sky.Rotation = 90
	sky.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(12, 12, 26)),
		ColorSequenceKeypoint.new(0.6, COLOR_BACKGROUND),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(70, 30, 18)),
	})
	sky.Parent = backdrop
	for _ = 1, 40 do
		local star = Instance.new("Frame")
		local size = math.random(1, 3)
		star.Size = UDim2.fromOffset(size, size)
		star.Position = UDim2.fromScale(math.random(), math.random() * 0.6)
		star.BackgroundColor3 = Color3.fromRGB(255, 240, 200)
		star.BackgroundTransparency = 0.2 + math.random() * 0.6
		star.BorderSizePixel = 0
		star.Parent = backdrop
	end
	local skyline = Instance.new("Frame")
	skyline.Size = UDim2.new(1, 0, 0, 70)
	skyline.Position = UDim2.fromScale(0, 1)
	skyline.AnchorPoint = Vector2.new(0, 1)
	skyline.BackgroundTransparency = 1
	skyline.Parent = backdrop
	Art.skyline(skyline, Color3.fromRGB(10, 7, 6), 0)
end

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

-- A thin border, for panels and cards.
local function addStroke(instance: Instance): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = COLOR_EDGE
	stroke.Transparency = 0.4
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = instance
	return stroke
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
	Art.button(button)
	return button
end

-- Shows a button as usable (its own color) or greyed out.
-- Bright buttons (gold) get dark text so it stays readable.
local function setButton(button: TextButton, text: string, usable: boolean, color: Color3)
	button.Text = text
	button.BackgroundColor3 = if usable then color else COLOR_DISABLED
	local bright = usable and (color.R * 0.299 + color.G * 0.587 + color.B * 0.114) > 0.55
	button.TextColor3 = if bright then Color3.fromRGB(40, 28, 12) else Color3.new(1, 1, 1)
end

local function send(action: string, id: string?)
	actionRemote:FireServer(action, id)
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
	label.TextStrokeTransparency = 0.5
	Art.bar(back, fill)
	return { fill = fill, label = label }
end

local function setBar(bar, value: number, maximum: number, text: string)
	local share = if maximum > 0 then math.clamp(value / maximum, 0, 1) else 0
	bar.fill.Size = UDim2.fromScale(share, 1)
	bar.label.Text = text
end

---------------------------------------------------------------------------
-- Top bar: you on the left, resources in the middle, bars on the right
---------------------------------------------------------------------------

local topBar = makeFrame(gui, UDim2.new(1, -12, 0, TOP_HEIGHT), UDim2.fromOffset(6, 4), Art.Colors.wood)
addCorner(topBar, 8)
Art.panel(topBar)

-- Popups (Profile, Mail, Rankings...) open over the menus. Defined with
-- the popup window further down.
local openModal
local ui -- the helpers page modules get; filled in further down
local railBadges = {} -- red count pills, by page or popup name

-- Your Roblox picture with the level on it, name and experience. Pressing
-- the picture or the name opens your Profile.
local levelBadge
do
	local avatar = Instance.new("ImageButton")
	avatar.Size = UDim2.fromOffset(56, 56)
	avatar.Position = UDim2.fromOffset(8, 8)
	avatar.BackgroundColor3 = COLOR_ROW
	avatar.BorderSizePixel = 0
	avatar.AutoButtonColor = true
	avatar.ScaleType = Enum.ScaleType.Crop
	avatar.Image = ""
	avatar.Parent = topBar
	addCorner(avatar, 28)
	local ring = Instance.new("UIStroke")
	ring.Color = COLOR_GOLD
	ring.Thickness = 2
	ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ring.Parent = avatar
	task.spawn(function()
		local ok, image = pcall(Players.GetUserThumbnailAsync, Players, player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		if ok and image then
			avatar.Image = image
		end
	end)

	levelBadge = makeText(avatar, UDim2.fromOffset(26, 18), UDim2.new(1, 4, 1, 2), Color3.fromRGB(40, 28, 12), 12)
	levelBadge.AnchorPoint = Vector2.new(1, 1)
	levelBadge.BackgroundTransparency = 0
	levelBadge.BackgroundColor3 = COLOR_GOLD
	levelBadge.Font = Enum.Font.GothamBlack
	levelBadge.TextXAlignment = Enum.TextXAlignment.Center
	levelBadge.ZIndex = 2
	addCorner(levelBadge, 9)
	Art.gloss(levelBadge, 1, 0.7)
	Art.stroke(levelBadge, Art.Colors.woodDark, 1.5, 0)

	-- The name and XP bar are under this clear button, so they open the
	-- Profile too.
	local nameHit = makeButton(topBar, UDim2.fromOffset(190, 26), UDim2.fromOffset(70, 8), COLOR_PANEL)
	nameHit.BackgroundTransparency = 1
	nameHit:SetAttribute("NoGlow", true)
	nameHit.Text = ""
	nameHit.ZIndex = 3
	for _, button in { avatar, nameHit } do
		button.Activated:Connect(function()
			openModal("Profile")
		end)
	end
end

local nameLabel = makeText(topBar, UDim2.fromOffset(190, 24), UDim2.fromOffset(70, 10), COLOR_HEADER, 20)
nameLabel.Font = Art.Fonts.heading
nameLabel.TextStrokeTransparency = 0.6
nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
nameLabel.TextWrapped = false
local xpBar = makeBar(topBar, UDim2.fromOffset(190, 16), UDim2.fromOffset(70, 40), COLOR_XP)

-- Resource chips: a big number with a small line under it.
local chips = {}
do
	local chipRow = makeFrame(topBar, UDim2.new(1, -(LEFT_BLOCK + RIGHT_BLOCK + ICON_BLOCK), 1, -12), UDim2.fromOffset(LEFT_BLOCK, 6), COLOR_PANEL)
	chipRow.BackgroundTransparency = 1
	local chipLayout = Instance.new("UIListLayout")
	chipLayout.FillDirection = Enum.FillDirection.Horizontal
	chipLayout.Padding = UDim.new(0, 6)
	chipLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	chipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chipLayout.Parent = chipRow

	local function makeChip(key: string, label: string, color: Color3)
		local chip = makeFrame(chipRow, UDim2.new(0.5, -6, 1, 0), UDim2.fromOffset(0, 0), Art.Colors.woodDark)
		chip.LayoutOrder = #chipRow:GetChildren()
		addCorner(chip, 8)
		Art.card(chip)
		Art.stroke(chip, color, 1.5, 0.35)
		local sizeLimit = Instance.new("UISizeConstraint")
		sizeLimit.MaxSize = Vector2.new(200, 100)
		sizeLimit.Parent = chip
		local icon = Art.icon(chip, Art.Icons[key] or "", 30, UDim2.new(0, 6, 0.5, 0))
		icon.AnchorPoint = Vector2.new(0, 0.5)
		local name = makeText(chip, UDim2.new(1, -46, 0, 14), UDim2.fromOffset(42, 3), color, 11)
		name.Font = Enum.Font.GothamBold
		name.Text = string.upper(label)
		local value = makeText(chip, UDim2.new(1, -46, 0, 22), UDim2.fromOffset(42, 16), COLOR_TEXT, 18)
		value.Font = Enum.Font.GothamBold
		value.TextScaled = true
		value.TextStrokeTransparency = 0.6
		local sub = makeText(chip, UDim2.new(1, -46, 0, 14), UDim2.fromOffset(42, 38), COLOR_DIM, 11)
		sub.TextTruncate = Enum.TextTruncate.AtEnd
		sub.TextWrapped = false
		chips[key] = { value = value, sub = sub }
	end
	makeChip("gold", "Gold", COLOR_GOLD)
	makeChip("crowns", "Crowns", Color3.fromRGB(200, 150, 230))
end

-- Square buttons that open popups, between the chips and the bars.
do
	local iconRow = makeFrame(topBar, UDim2.new(0, ICON_BLOCK - 10, 1, -12), UDim2.new(1, -(RIGHT_BLOCK + ICON_BLOCK - 4), 0, 6), COLOR_PANEL)
	iconRow.BackgroundTransparency = 1
	local iconLayout = Instance.new("UIListLayout")
	iconLayout.FillDirection = Enum.FillDirection.Horizontal
	iconLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	iconLayout.Padding = UDim.new(0, 6)
	iconLayout.SortOrder = Enum.SortOrder.LayoutOrder
	iconLayout.Parent = iconRow
	for index, entry in { { "Mail", Art.Icons.Mail, "Mail" } } do
		local button = makeButton(iconRow, UDim2.new(0, 56, 1, 0), UDim2.fromOffset(0, 0), COLOR_ROW)
		button.LayoutOrder = index
		button.Text = ""
		addStroke(button)
		local icon = makeText(button, UDim2.new(1, 0, 0, 28), UDim2.fromOffset(0, 4), COLOR_HEADER, 22)
		icon.TextXAlignment = Enum.TextXAlignment.Center
		icon.Text = entry[2]
		local label = makeText(button, UDim2.new(1, 0, 0, 14), UDim2.new(0, 0, 1, -18), COLOR_TEXT, 11)
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.Font = Enum.Font.GothamBold
		label.Text = string.upper(entry[3])
		local badge = makeText(button, UDim2.fromOffset(22, 16), UDim2.new(1, 4, 0, -4), Color3.new(1, 1, 1), 10)
		badge.AnchorPoint = Vector2.new(1, 0)
		badge.BackgroundTransparency = 0
		badge.BackgroundColor3 = COLOR_ACTION
		badge.Font = Enum.Font.GothamBold
		badge.TextXAlignment = Enum.TextXAlignment.Center
		badge.Visible = false
		badge.ZIndex = 2
		addCorner(badge, 8)
		railBadges[entry[1]] = badge
		button.Activated:Connect(function()
			openModal(entry[1])
		end)
	end
end

-- Energy, stamina and health, each with a + that opens the Shop's refills.
local barBlock = makeFrame(topBar, UDim2.new(0, RIGHT_BLOCK - 10, 1, 0), UDim2.new(1, -(RIGHT_BLOCK - 4), 0, 0), COLOR_PANEL)
barBlock.BackgroundTransparency = 1
local showPage -- defined with the pages below
local function makeTopBar(y: number, color: Color3, glyph: string)
	local bar = makeBar(barBlock, UDim2.new(1, -30, 0, 18), UDim2.fromOffset(0, y), color)
	local icon = Art.icon(bar.fill.Parent, glyph, 18, UDim2.fromOffset(-4, 0))
	icon.ZIndex = 2
	local plus = makeButton(barBlock, UDim2.fromOffset(22, 18), UDim2.new(1, -24, 0, y), COLOR_SELECTED)
	plus.Text = "+"
	plus.TextSize = 14
	plus.Activated:Connect(function()
		showPage("Shop")
	end)
	return bar
end
local energyBar = makeTopBar(8, COLOR_ENERGY, Art.Icons.energy)
local staminaBar = makeTopBar(29, COLOR_STAMINA, Art.Icons.stamina)
local healthBar = makeTopBar(50, COLOR_HEALTH, Art.Icons.health)

---------------------------------------------------------------------------
-- Left menu: pages grouped under small headings, with red count badges
---------------------------------------------------------------------------

local rail = Instance.new("ScrollingFrame")
rail.Size = UDim2.new(0, RAIL_WIDTH, 1, -(TOP_HEIGHT + 16))
rail.Position = UDim2.fromOffset(6, TOP_HEIGHT + 10)
rail.BackgroundColor3 = COLOR_PANEL
rail.BorderSizePixel = 0
rail.ScrollBarThickness = 4
rail.CanvasSize = UDim2.new(0, 0, 0, 0)
rail.AutomaticCanvasSize = Enum.AutomaticSize.Y
rail.Parent = gui
rail.ScrollBarImageColor3 = COLOR_GOLD
addCorner(rail, 8)
Art.panel(rail, false)

do
	local railLayout = Instance.new("UIListLayout")
	railLayout.Padding = UDim.new(0, 3)
	railLayout.SortOrder = Enum.SortOrder.LayoutOrder
	railLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	railLayout.Parent = rail

	local railPadding = Instance.new("UIPadding")
	railPadding.PaddingTop = UDim.new(0, 6)
	railPadding.PaddingBottom = UDim.new(0, 6)
	railPadding.Parent = rail
end

local main = makeFrame(gui, UDim2.new(1, -(RAIL_WIDTH + 18), 1, -(TOP_HEIGHT + 16)), UDim2.fromOffset(RAIL_WIDTH + 12, TOP_HEIGHT + 10), COLOR_PANEL)
addCorner(main, 8)
Art.panel(main)

-- Every page: its group, a one line description, and a tip shown until
-- the player presses Got it.
local PAGE_GROUPS = {
	{ name = "Realm", pages = { "Keep", "Estate", "Holdings", "Research", "Bank" } },
	{ name = "Daily", pages = { "Bounties", "Festival" } },
	{ name = "Campaign", pages = { "Quests", "Foes", "Expeditions" } },
	{ name = "Arena", pages = { "Rankings", "War Chronicle" } },
	{ name = "Court", pages = { "Warband", "Barracks", "Inventory", "Relic Hall", "Market" } },
	{ name = "Treasury", pages = { "Royal Pass", "Shop" } },
}
local PAGE_INFO = {
	Estate = {
		about = "Lumber, stone, iron and grain, your buildings, defenses and castles.",
		tip = "Upgrade the Lumber Camp and Quarry first. Resources pay for buildings, Keep upgrades and troops, and stop at your storage cap.",
	},
	Rankings = {
		about = "The mightiest players across every server.",
		tip = "Scores are sent while you play and the boards refresh every couple of minutes. Fights with other players come here later.",
	},
	["War Chronicle"] = {
		about = "Reports of your foe fights and expeditions, newest first.",
		tip = "Each expedition report shows the battle round by round, so you can see which troops to train.",
	},
	Barracks = {
		about = "Train troops for expeditions. Each type beats one kind of enemy.",
		tip = "Spearmen beat riders, archers beat spearmen, cavalry beat archers, and siege rams break forts.",
	},
	Expeditions = {
		about = "Send your army out on timed raids for gold, tokens and gear.",
		tip = "Your whole army marches. Check your power against each enemy before you send it.",
	},
	["Relic Hall"] = {
		about = "Your collection: gear on display gives flat attack and defense.",
		tip = "Copies of the same item stack into tiers at 1, 10, 100, 1000, 2500 and 10000. Take pieces back out any time.",
	},
	Keep = {
		about = "Your home, your numbers, daily rewards and skills.",
		tip = "Upgrade the Keep to raise income, attack and defense. Spend skill points from level ups on the skills below.",
	},
	Holdings = {
		about = "Lands that pay gold every hour, even while you are away.",
		tip = "Each holding uses one lot. Build more copies to earn more; demolish one to free its lot.",
	},
	Bank = {
		about = "Gold in the bank is safe. Gold on hand is what you spend.",
		tip = "Deposits cost a small fee. Withdraw before buying, since purchases use gold on hand.",
	},
	Research = {
		about = "Scholars' Hall: permanent bonuses that take real time to research.",
		tip = "One research runs at a time and keeps going while you are away. Some need another research first.",
	},
	Bounties = {
		about = "Daily and weekly tasks that pay Seals, plus your login streak.",
		tip = "Claim your streak reward every day; missing a day starts it over. Spend Seals in the Seal shop.",
	},
	Festival = {
		about = "A new festival every week, with a bonus for everyone and a leaderboard.",
		tip = "Earn points from normal play. Claim milestones as you go; rank rewards arrive the week after.",
	},
	Quests = {
		about = "Spend energy for gold, experience and the odd piece of gear.",
		tip = "Repeat a quest to earn bronze, silver and gold mastery. The Auto quests button opens the settings: repeat your last quest, earn mastery, or go for the most XP.",
	},
	Foes = {
		about = "Bring down each foe once a day for gold, tokens and set gear.",
		tip = "Each attack costs 1 stamina and the foe hits back. Beat a stage to open the next one.",
	},
	Warband = {
		about = "Soldiers add their attack and defense to yours.",
		tip = "Roll recruits for empty slots, then train them and give them gear. The Recruiting Sergeant pass rolls until your rarity turns up.",
	},
	Inventory = {
		about = "Your gear, gear sets and trophies.",
		tip = "Gear only counts while someone wears it. Take a piece off before selling it.",
	},
	Market = {
		about = "Gear for sale. The stock changes every 5 minutes.",
		tip = "Buy gear here. With the Market Steward pass, auto-buy picks up matching gear for you while you play.",
	},
	["Royal Pass"] = {
		about = "Fifty tiers of rewards each season.",
		tip = "Points come from quests, foes, playtime rewards and weekly challenges. The Noble track adds a second reward to every tier.",
	},
	Shop = {
		about = "Crowns, packs and passes, and things to spend Crowns on.",
		tip = "Game passes are yours forever. Coffers show their odds, and a pity counter guarantees a top piece.",
	},
}

local PAGE_NAMES = {}
local pageGroup = {}
for _, group in PAGE_GROUPS do
	for _, name in group.pages do
		table.insert(PAGE_NAMES, name)
		pageGroup[name] = group.name
	end
end

-- Page header: small group label, big title, description, boost chips.
local HEADER_HEIGHT = 64
-- A banner in the group's color behind the header, with a castle skyline
-- and a round emblem showing the page's icon.
local headerArt = {}
do
	local banner = makeFrame(main, UDim2.new(1, -12, 0, HEADER_HEIGHT - 6), UDim2.fromOffset(6, 4), COLOR_SELECTED)
	banner.ZIndex = 0
	addCorner(banner, 8)
	local fade = Instance.new("UIGradient")
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.6, 0.55),
		NumberSequenceKeypoint.new(1, 0.85),
	})
	fade.Parent = banner
	local skyline = Art.skyline(banner, Color3.new(0, 0, 0), 0.55)
	skyline.ZIndex = 0
	for _, part in skyline:GetDescendants() do
		if part:IsA("GuiObject") then
			part.ZIndex = 0
		end
	end
	local emblem, glyph = Art.emblem(main, "", 48, UDim2.fromOffset(14, 8), COLOR_SELECTED)
	headerArt.banner = banner
	headerArt.emblem = emblem
	headerArt.glyph = glyph
end
local eyebrow = makeText(main, UDim2.new(0.5, 0, 0, 14), UDim2.fromOffset(72, 8), COLOR_DIM, 11)
eyebrow.Font = Enum.Font.GothamBold
local pageTitle = makeText(main, UDim2.new(0.5, 0, 0, 30), UDim2.fromOffset(72, 18), COLOR_HEADER, 32)
pageTitle.Font = Art.Fonts.title
pageTitle.TextStrokeTransparency = 0.5
local pageAbout = makeText(main, UDim2.new(0.55, -58, 0, 16), UDim2.fromOffset(72, 45), COLOR_TEXT, 12)
pageAbout.TextTruncate = Enum.TextTruncate.AtEnd
pageAbout.TextWrapped = false

-- Boost chips on the right of the header (double XP, passes, automation).
local boostRow = makeFrame(main, UDim2.new(0.45, -20, 0, 24), UDim2.new(1, -10, 0, 12), COLOR_PANEL)
boostRow.AnchorPoint = Vector2.new(1, 0)
boostRow.BackgroundTransparency = 1
local boostLayout = Instance.new("UIListLayout")
boostLayout.FillDirection = Enum.FillDirection.Horizontal
boostLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
boostLayout.Padding = UDim.new(0, 5)
boostLayout.SortOrder = Enum.SortOrder.LayoutOrder
boostLayout.Parent = boostRow

local boostChips = {}
local function setBoostChips(list)
	for index, entry in list do
		local chip = boostChips[index]
		if not chip then
			chip = makeText(boostRow, UDim2.fromOffset(0, 24), UDim2.fromOffset(0, 0), COLOR_TEXT, 12)
			chip.AutomaticSize = Enum.AutomaticSize.X
			chip.BackgroundTransparency = 0
			chip.TextWrapped = false
			chip.Font = Enum.Font.GothamBold
			chip.LayoutOrder = index
			local padding = Instance.new("UIPadding")
			padding.PaddingLeft = UDim.new(0, 8)
			padding.PaddingRight = UDim.new(0, 8)
			padding.Parent = chip
			addCorner(chip, 12)
			boostChips[index] = chip
		end
		chip.Text = entry[1]
		chip.BackgroundColor3 = entry[2]
		chip.Visible = true
	end
	for index = #list + 1, #boostChips do
		boostChips[index].Visible = false
	end
end

-- Tip strip under the header. Got it hides it for that page for good.
local tipStrip = makeFrame(main, UDim2.new(1, -24, 0, 34), UDim2.fromOffset(12, HEADER_HEIGHT), Color3.fromRGB(34, 48, 58))
addCorner(tipStrip, 6)
local tipStroke = addStroke(tipStrip)
tipStroke.Color = COLOR_INFO
local tipText = makeText(tipStrip, UDim2.new(1, -100, 1, -4), UDim2.fromOffset(10, 2), COLOR_TEXT, 12)
local tipButton = makeButton(tipStrip, UDim2.fromOffset(76, 24), UDim2.new(1, -6, 0.5, 0), COLOR_INFO)
tipButton.AnchorPoint = Vector2.new(1, 0.5)
tipButton.Text = "Got it"
tipButton.TextSize = 12

local tipsSeen = {} -- filled from the server's state
local currentPage = ""
local railButtons = {}
local pages = {}

local function placePage()
	local showTip = PAGE_INFO[currentPage] ~= nil and not tipsSeen[currentPage]
	tipStrip.Visible = showTip
	tipText.Text = if showTip then "Tip: " .. PAGE_INFO[currentPage].tip else ""
	local top = HEADER_HEIGHT + (if showTip then 40 else 0)
	local page = pages[currentPage]
	if page then
		page.Position = UDim2.fromOffset(8, top)
		page.Size = UDim2.new(1, -16, 1, -(top + 6))
	end
end

showPage = function(name: string)
	local changed = currentPage ~= name
	currentPage = name
	eyebrow.Text = string.upper(pageGroup[name] or "")
	pageTitle.Text = name
	pageAbout.Text = if PAGE_INFO[name] then PAGE_INFO[name].about else ""
	local groupColor = Art.GroupColors[pageGroup[name] or ""] or COLOR_SELECTED
	headerArt.banner.BackgroundColor3 = groupColor
	headerArt.emblem.BackgroundColor3 = groupColor
	headerArt.glyph.Text = Art.Icons[name] or ""
	for _, pageName in PAGE_NAMES do
		pages[pageName].Visible = pageName == name
		local selected = pageName == name
		local button = railButtons[pageName]
		button.BackgroundColor3 = if selected then COLOR_SELECTED else COLOR_PANEL
		button.BackgroundTransparency = if selected then 0 else 1
		button.TextColor3 = if selected then COLOR_GOLD else COLOR_TEXT
		local accent = button:FindFirstChild("Accent")
		if accent then
			accent.Visible = selected
		end
	end
	placePage()
	-- Slide the new page in.
	local page = pages[name]
	if page and changed then
		local target = page.Position
		page.Position = target + UDim2.fromOffset(0, 14)
		Art.tween(page, 0.2, { Position = target })
		Art.tween(headerArt.emblem, 0.08, { Rotation = -12 }).Completed:Connect(function()
			Art.tween(headerArt.emblem, 0.35, { Rotation = 0 }, Enum.EasingStyle.Back)
		end)
	end
end

tipButton.Activated:Connect(function()
	tipsSeen[currentPage] = true
	placePage()
	send("Tip", currentPage)
end)

-- A red pill with a count on a menu button; 0 hides it.
local function setBadge(name: string, count: number)
	local badge = railBadges[name]
	if not badge then
		return
	end
	badge.Visible = count > 0
	badge.Text = if count > 99 then "99+" else tostring(count)
end

local railOrder = 0
for _, group in PAGE_GROUPS do
	railOrder += 1
	local heading = makeText(rail, UDim2.new(1, -16, 0, 22), UDim2.fromOffset(0, 0), COLOR_HEADER, 15)
	heading.Font = Art.Fonts.heading
	heading.Text = group.name
	heading.LayoutOrder = railOrder
	heading.TextYAlignment = Enum.TextYAlignment.Bottom
	do
		-- A thin line in the group's color under the heading.
		local line = makeFrame(heading, UDim2.new(1, 0, 0, 2), UDim2.new(0, 0, 1, 1), Art.GroupColors[group.name] or COLOR_EDGE)
		local fade = Instance.new("UIGradient")
		fade.Transparency = NumberSequence.new(0, 1)
		fade.Parent = line
	end

	for _, name in group.pages do
		railOrder += 1
		local button = makeButton(rail, UDim2.new(1, -12, 0, 30), UDim2.fromOffset(0, 0), COLOR_PANEL)
		button.LayoutOrder = railOrder
		button.Text = name
		button.TextXAlignment = Enum.TextXAlignment.Left
		button.TextSize = 13
		button.BackgroundTransparency = 1
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 32)
		padding.Parent = button
		railButtons[name] = button
		do
			local icon = Art.icon(button, Art.Icons[name] or "", 20, UDim2.new(0, -27, 0.5, 0))
			icon.AnchorPoint = Vector2.new(0, 0.5)
			-- A gold edge on the left of the open page's button.
			local accent = makeFrame(button, UDim2.new(0, 4, 1, -8), UDim2.new(0, -32, 0.5, 0), COLOR_GOLD)
			accent.Name = "Accent"
			accent.AnchorPoint = Vector2.new(0, 0.5)
			accent.Visible = false
			addCorner(accent, 2)
		end

		local badge = makeText(button, UDim2.fromOffset(24, 18), UDim2.new(1, -4, 0.5, 0), Color3.new(1, 1, 1), 11)
		badge.AnchorPoint = Vector2.new(1, 0.5)
		badge.BackgroundTransparency = 0
		badge.BackgroundColor3 = COLOR_ACTION
		badge.Font = Enum.Font.GothamBold
		badge.TextXAlignment = Enum.TextXAlignment.Center
		badge.Visible = false
		addCorner(badge, 9)
		railBadges[name] = badge

		local page = Instance.new("ScrollingFrame")
		page.Position = UDim2.fromOffset(8, HEADER_HEIGHT)
		page.Size = UDim2.new(1, -16, 1, -(HEADER_HEIGHT + 6))
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
end

-- One line in a page: text on the left and up to one button on the right.
local BUTTON_WIDTH = 112

local function makeRow(page: Instance, order: number, height: number, hasButton: boolean)
	local row = makeFrame(page, UDim2.new(1, -10, 0, height), UDim2.fromOffset(0, 0), COLOR_ROW)
	row.LayoutOrder = order
	addCorner(row, 6)
	addStroke(row)
	Art.card(row)

	local textWidthOffset = if hasButton then -(BUTTON_WIDTH + 26) else -20
	local info = makeText(row, UDim2.new(1, textWidthOffset, 1, -8), UDim2.fromOffset(10, 4), COLOR_TEXT, 14)

	local button = nil
	if hasButton then
		button = makeButton(row, UDim2.fromOffset(BUTTON_WIDTH, math.min(42, height - 10)), UDim2.new(1, -6, 0.5, 0), COLOR_DISABLED)
		button.AnchorPoint = Vector2.new(1, 0.5)
	end
	return info, button
end

-- A grid of cards that wrap into `columns` columns.
local function makeGrid(page: Instance, order: number, cardHeight: number, columns: number): Frame
	local grid = makeFrame(page, UDim2.new(1, -10, 0, 0), UDim2.fromOffset(0, 0), COLOR_PANEL)
	grid.BackgroundTransparency = 1
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.LayoutOrder = order
	local layout = Instance.new("UIGridLayout")
	layout.CellPadding = UDim2.fromOffset(6, 6)
	layout.CellSize = UDim2.new(1 / columns, -6, 0, cardHeight)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	return grid
end

-- One card in a grid: text at the top and one wide button at the bottom.
-- Returns the same (text, button) pair as makeRow, so drawing works the same.
local cardCount = 0
local function makeCard(grid: Instance)
	cardCount += 1
	local card = makeFrame(grid, UDim2.fromOffset(100, 100), UDim2.fromOffset(0, 0), COLOR_ROW)
	card.LayoutOrder = cardCount
	addCorner(card, 8)
	addStroke(card)
	Art.card(card)
	local info = makeText(card, UDim2.new(1, -16, 1, -52), UDim2.fromOffset(8, 6), COLOR_TEXT, 13)
	info.TextYAlignment = Enum.TextYAlignment.Top
	local button = makeButton(card, UDim2.new(1, -16, 0, 36), UDim2.new(0, 8, 1, -42), COLOR_DISABLED)
	button.TextSize = 13
	return info, button
end

-- A small heading between groups of rows.
local function makeHeading(page: Instance, order: number, text: string)
	local label = makeText(page, UDim2.new(1, -10, 0, 28), UDim2.fromOffset(0, 0), COLOR_HEADER, 20)
	label.LayoutOrder = order
	label.Font = Art.Fonts.heading
	label.TextYAlignment = Enum.TextYAlignment.Bottom
	label.TextStrokeTransparency = 0.6
	label.Text = text
	-- A gold rule under the heading that fades out to the right.
	local line = makeFrame(label, UDim2.new(1, 0, 0, 1), UDim2.new(0, 0, 1, 1), COLOR_GOLD)
	local fade = Instance.new("UIGradient")
	fade.Transparency = NumberSequence.new(0.2, 1)
	fade.Parent = line
end

-- A row with a label on the left and several buttons sharing the rest.
local function makeButtonRow(page: Instance, order: number, labelText: string, names: { string }, labelWidth: number?)
	local row = makeFrame(page, UDim2.new(1, -10, 0, 44), UDim2.fromOffset(0, 0), COLOR_ROW)
	row.LayoutOrder = order
	addCorner(row, 6)
	Art.card(row)
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

-- Keep: the picture, numbers and skills are in KeepPage.luau; the daily
-- playtime rewards are here.

makeHeading(pages.Keep, nextOrder(), "Daily playtime rewards")
local playtimeSummary = makeRow(pages.Keep, nextOrder(), 32, false)
local rewardRows = {}
do
	local rewardGrid = makeGrid(pages.Keep, nextOrder(), 92, 4)
	for index, reward in GameConfig.PlaytimeRewards do
		local info, button = makeCard(rewardGrid)
		rewardRows[index] = { info = info, button = button }
		button.Activated:Connect(function()
			send("Claim", tostring(index))
		end)
		info.RichText = true
		info.Text = `<b>{reward.label}</b>\nAfter {reward.minutes} min`
	end
end


-- Quests, in folding regions.
local questRows = {}
local autoQuestInfo, autoQuestButton = makeRow(pages.Quests, nextOrder(), 50, true)
autoQuestInfo.RichText = true
local autoQuestOn = false
local ownsAutoQuest = false
-- Auto buttons without their game pass are locked and offer the pass.
autoQuestButton.Activated:Connect(function()
	if ownsAutoQuest then
		ui.openAutoQuest()
	else
		ui.offerPass("autoquest")
	end
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
	local grid = makeGrid(pages.Holdings, nextOrder(), 112, 3)
	addRow(grid)
	for _, holding in GameConfig.Holdings do
		if holding.region == region.id then
			local info, button = makeCard(grid)
			holdingRows[holding.id] = { info = info, button = button }
			button.Activated:Connect(function()
				send("Holding", holding.id)
			end)
		end
	end
end

-- Bank: move gold in and out. Gold in the bank is safe from raids.
local bankSummary = makeRow(pages.Bank, nextOrder(), 74, false)
do
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
end

-- This week's festival bonus of one kind ("marketPrice", "rollCost"), or 0.
local function festivalDiscount(state, kind: string): number
	local festival = FestivalConfig.getFestival(state.festival.week)
	return if festival.bonus.kind == kind then festival.bonus.amount else 0
end

local function formatClock(seconds: number): string
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function formatLong(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local days = math.floor(seconds / 86400)
	local hours = math.floor(seconds % 86400 / 3600)
	if days > 0 then
		return `{days}d {hours}h`
	end
	return `{hours}h {math.floor(seconds % 3600 / 60)}m`
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
	-- The item's picture on the left, with its rarity glow.
	local picture = makeFrame(info.Parent, UDim2.fromOffset(44, 44), UDim2.fromOffset(6, 4), COLOR_PANEL)
	picture.BackgroundTransparency = 0.4
	addCorner(picture, 6)
	info.Position = info.Position + UDim2.fromOffset(48, 0)
	info.Size = info.Size - UDim2.fromOffset(48, 0)
	return { info = info, button = button, picture = picture }
end

-- Market: a fixed number of rows that are refilled each restock.
local marketSummary = makeRow(pages.Market, nextOrder(), 50, false)
local marketRows = {}
-- The restock window of the stock on screen, set each time the Market is drawn.
local marketWindowShown: number? = nil
for index = 1, GameConfig.MarketSize do
	local row = makeItemRow(pages.Market, nextOrder())
	marketRows[index] = row
	row.button.Activated:Connect(function()
		-- Send which stock the player is looking at with the row, so a click
		-- that reaches the server after a restock can't buy the new item.
		if marketWindowShown then
			send("Buy", `{marketWindowShown}:{index}`)
		end
	end)
end

makeHeading(pages.Market, nextOrder(), "Auto-buy")
local autoBuyInfo, autoBuyButton = makeRow(pages.Market, nextOrder(), 56, true)
autoBuyInfo.RichText = true
local autoBuyRunning = false
local ownsAutoBuy = false
autoBuyButton.Activated:Connect(function()
	if ownsAutoBuy then
		ui.openAutoBuy()
	else
		ui.offerPass("autobuy")
	end
end)

local recentBuys = makeRow(pages.Market, nextOrder(), 110, false)
recentBuys.RichText = true
recentBuys.TextYAlignment = Enum.TextYAlignment.Top

-- Warband: one row for you, one per unlocked slot, and the next locked slot.
local openRecruitWindow -- defined further down, with the recruit window

-- Single rolls from a slot's Recruit or Reroll button use the best recruit
-- tier your level allows and your gold covers (Village if none).
local function oneRollCost(state, tier): number
	return math.floor(tier.cost * (1 - festivalDiscount(state, "rollCost")))
end
local function oneRollTier(state)
	local best = GameConfig.RecruitTiers[1]
	for _, tier in GameConfig.RecruitTiers do
		if state.level >= tier.level and state.gold >= oneRollCost(state, tier) then
			best = tier
		end
	end
	return best
end

local warbandSummary, autoRollButton = makeRow(pages.Warband, nextOrder(), 56, true)
setButton(autoRollButton, "Recruit", true, COLOR_ACTION)
local ownsAutoRoll = false
autoRollButton.Activated:Connect(function()
	if ownsAutoRoll then
		openRecruitWindow(0)
	else
		ui.offerPass("autoroll")
	end
end)

-- How many pieces of each set one member wears: { [setId] = count }.
-- member 0 is you, 1 and up is a warband slot.
local function memberSetCounts(state, member: number)
	local counts = {}
	local list = state.gearSets and state.gearSets[tostring(member)]
	if list then
		for _, entry in list do
			counts[entry.set] = entry.count
		end
	end
	return counts
end

-- A green tag naming an item's set, with the bonus it gets on its wearer.
local function setTag(item, counts): string
	local set = item and GameConfig.getGearSet(item.set)
	if not set then
		return ""
	end
	local count = counts and counts[item.set] or 0
	local bonus = GameConfig.SetPieceBonus[count]
	local bonusText = if bonus then ` {count}/{GameConfig.SetPieceCount} +{math.floor(bonus * 100 + 0.5)}%` else ""
	return ` <font color="#9FD49A">[{set.name}{bonusText}]</font>`
end

-- The realm bonus of a full set, as text: "+5% quest gold".
local function perkText(perk): string
	local parts = {}
	for _, pair in GameConfig.TrophyBonusNames do
		local amount = perk[pair[1]]
		if amount then
			table.insert(parts, `+{math.floor(amount * 100 + 0.5)}% {pair[2]}`)
		end
	end
	return table.concat(parts, ", ")
end

-- Who a member is: "You" or the soldier's name.
local function memberLabel(state, member: number?): string
	if member == 0 then
		return "You"
	end
	local soldier = member and state.crew[member]
	return if soldier then soldier.name else "Nobody"
end

-- One worn piece for a Warband row. Kept short so it fits on one line;
-- the Gear window shows full stats.
local function gearLine(item, counts): string
	if not item then
		return `<font color="#7F847E">empty</font>`
	end
	return `{rarityName(item)}{setTag(item, counts)}`
end

local openEquipWindow -- defined further down, with the equip window

local equipButtons = makeButtonRow(pages.Warband, nextOrder(), "Gear", { "Equip best", "New gear" }, 70)
equipButtons[1].Activated:Connect(function()
	send("EquipBest")
end)
local equipNewOn = true
equipButtons[2].Activated:Connect(function()
	send("EquipNew", if equipNewOn then "off" else "on")
end)

local function makeCrewRow(order: number)
	local row = makeFrame(pages.Warband, UDim2.new(1, -10, 0, 76), UDim2.fromOffset(0, 0), COLOR_ROW)
	row.LayoutOrder = order
	addCorner(row, 6)

	local info = makeText(row, UDim2.new(0.3, -10, 1, -8), UDim2.fromOffset(10, 4), COLOR_TEXT, 13)
	info.RichText = true
	local gearText = makeText(row, UDim2.new(0.7, -306, 1, -8), UDim2.new(0.3, 0, 0, 4), COLOR_DIM, 12)
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
	local gear = button(56, -246)

	return { frame = row, info = info, gearText = gearText, train = train, roll = roll, release = release, gear = gear }
end

local youRow = makeCrewRow(nextOrder())
youRow.train.Visible = false
youRow.roll.Visible = false
youRow.release.Visible = false
-- The you row has only the Gear button, so it sits on the right.
youRow.gear.Position = UDim2.new(1, -6, 0.5, 0)
youRow.gearText.Size = UDim2.new(0.7, -76, 1, -8)
youRow.gear.Activated:Connect(function()
	openEquipWindow(0)
end)

local crewRows = {}
for slot = 1, GameConfig.MaxSoldierSlots do
	local row = makeCrewRow(nextOrder())
	crewRows[slot] = row
	row.train.Activated:Connect(function()
		send("Train", tostring(slot))
	end)
	-- One roll for this slot (set up by the draw code below). Auto roll
	-- lives in its own window.
	row.roll.Activated:Connect(function()
		if row.rollId then
			send("Roll", row.rollId)
		end
	end)
	row.release.Activated:Connect(function()
		send("Release", tostring(slot))
	end)
	row.gear.Activated:Connect(function()
		openEquipWindow(slot)
	end)
end

local lockedInfo, unlockButton = makeRow(pages.Warband, nextOrder(), 56, true)
unlockButton.Activated:Connect(function()
	send("Slot")
end)

-- Inventory: tabs for gear by slot and for trophies, and a rarity filter.
local INVENTORY_TABS = { "All", "Weapon", "Armor", "Mount", "Sets", "Trophies" }
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
local setRows = {}
for _, set in GameConfig.GearSets do
	local info, button = makeRow(pages.Inventory, nextOrder(), 70, true)
	info.RichText = true
	info.TextSize = 13
	button.AutoButtonColor = false
	setRows[set.id] = { info = info, button = button }
end
-- Inventory rows: one per stack of identical spare pieces or worn piece.
-- Rows are made as needed (the armory has no limit).
local gearRows = {}
local gearHolder = makeFrame(pages.Inventory, UDim2.new(1, 0, 0, 0), UDim2.fromOffset(0, 0), COLOR_PANEL)
gearHolder.BackgroundTransparency = 1
gearHolder.AutomaticSize = Enum.AutomaticSize.Y
gearHolder.LayoutOrder = nextOrder()
do
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 5)
	list.Parent = gearHolder
end
local function gearRow(index: number)
	local row = gearRows[index]
	if row then
		return row
	end
	row = makeItemRow(gearHolder, index)
	row.uid = nil
	row.count = 1
	gearRows[index] = row
	row.button.Activated:Connect(function()
		if not row.uid then
			return
		end
		if row.count > 1 and ui and ui.askAmount then
			local uid, price, name = row.uid, row.price or 0, row.name or "pieces"
			ui.askAmount({
				title = "Sell how many?",
				note = `<b>{name}</b>: {row.count} spare.`,
				max = row.count,
				confirm = "Sell",
				preview = function(amount: number)
					return `+{Format.short(math.floor(price * GameConfig.SellShare) * amount)} gold`
				end,
				onConfirm = function(amount: number)
					send("Sell", `{uid}:{amount}`)
				end,
			})
		else
			send("Sell", row.uid)
		end
	end)
	return row
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
do
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
end

makeHeading(pages.Foes, nextOrder(), "Token shop")
local tokenRows = {}
do
	local tokenGrid = makeGrid(pages.Foes, nextOrder(), 96, 3)
	for _, item in GameConfig.TokenShop do
		local info, button = makeCard(tokenGrid)
		info.Text = `<b>{item.name}</b>\n{item.note}`
		info.RichText = true
		tokenRows[item.id] = button
		button.Activated:Connect(function()
			send("TokenBuy", item.id)
		end)
	end
end

-- Shop: Robux items at the top, then things bought with Crowns.
local function robuxText(price: number): string
	return `R$ {price}`
end

---------------------------------------------------------------------------
-- Popup window: Profile, Rebirth, Mail and the settings windows open over
-- the menus instead of having their own place in the left menu. Each
-- popup's content is a scrolling list stored in `pages`, so page modules
-- build into it the same way as into a page.
---------------------------------------------------------------------------

local isModalOpen, closeModal
do
	-- width and height are optional; the default is 680 x 560.
	local MODALS = {
		{ key = "Profile", title = "Profile" },
		{ key = "Rebirth", title = "Rebirth" },
		{ key = "Mail", title = "Mail" },
		{ key = "AutoQuest", title = "Auto quests", width = 520, height = 400 },
		{ key = "AutoBuy", title = "Auto-buy", width = 600, height = 560 },
		{ key = "Amount", title = "How many?", width = 440, height = 330 },
		{ key = "Skills", title = "Skill points", width = 640, height = 590 },
		{ key = "Pass", title = "Game pass", width = 520, height = 300 },
		{ key = "ChestOdds", title = "Chest odds", width = 560, height = 580 },
	}
	local DEFAULT_WIDTH, DEFAULT_HEIGHT = 680, 560

	local popupGui = Instance.new("ScreenGui")
	popupGui.Name = "KingdomPopups"
	popupGui.DisplayOrder = 4
	popupGui.ResetOnSpawn = false
	popupGui.Enabled = false
	popupGui.Parent = playerGui

	-- Pressing the dark area around the window closes it.
	local shade = makeButton(popupGui, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Color3.new(0, 0, 0))
	shade.BackgroundTransparency = 0.45
	shade.AutoButtonColor = false
	shade:SetAttribute("NoGlow", true)
	shade.Text = ""

	local window = makeFrame(popupGui, UDim2.fromOffset(DEFAULT_WIDTH, DEFAULT_HEIGHT), UDim2.fromScale(0.5, 0.5), COLOR_PANEL)
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Active = true
	addCorner(window, 10)
	Art.panel(window)
	local windowScale = Instance.new("UIScale")
	windowScale.Parent = window

	-- A red ribbon across the top for the title.
	local ribbon = makeFrame(window, UDim2.new(1, -40, 0, 40), UDim2.fromOffset(20, 8), Art.Colors.blood)
	addCorner(ribbon, 8)
	Art.gloss(ribbon, 1, 0.65)
	Art.stroke(ribbon, COLOR_GOLD, 1.5, 0.2)
	local titleIcon = Art.icon(window, "", 28, UDim2.fromOffset(30, 14))
	local titleLabel = makeText(window, UDim2.new(1, -130, 0, 34), UDim2.fromOffset(66, 11), Art.Colors.goldLight, 30)
	titleLabel.Font = Art.Fonts.title
	titleLabel.TextStrokeTransparency = 0.4
	local closeButton = makeButton(window, UDim2.fromOffset(32, 32), UDim2.new(1, -58, 0, 12), COLOR_ACTION)
	closeButton.Text = "X"
	closeButton.TextSize = 18

	local contents = {}
	for _, modal in MODALS do
		local content = Instance.new("ScrollingFrame")
		content.Position = UDim2.fromOffset(12, 54)
		content.Size = UDim2.new(1, -18, 1, -64)
		content.BackgroundTransparency = 1
		content.BorderSizePixel = 0
		content.ScrollBarThickness = 6
		content.CanvasSize = UDim2.new(0, 0, 0, 0)
		content.AutomaticCanvasSize = Enum.AutomaticSize.Y
		content.Visible = false
		content.Parent = window
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 5)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = content
		contents[modal.key] = content
		pages[modal.key] = content
	end

	local openKey = ""
	closeModal = function()
		openKey = ""
		popupGui.Enabled = false
		for _, content in contents do
			content.Visible = false
		end
		redraw()
	end

	openModal = function(key: string, title: string?)
		if not contents[key] then
			return
		end
		openKey = key
		for name, content in contents do
			content.Visible = name == key
		end
		contents[key].CanvasPosition = Vector2.zero
		local width, height = DEFAULT_WIDTH, DEFAULT_HEIGHT
		for _, modal in MODALS do
			if modal.key == key then
				titleLabel.Text = title or modal.title
				titleIcon.Text = Art.Icons[key] or Art.Icons.scroll
				width = modal.width or DEFAULT_WIDTH
				height = modal.height or DEFAULT_HEIGHT
			end
		end
		window.Size = UDim2.fromOffset(width, height)
		-- Shrink the window on small screens so it always fits.
		local camera = workspace.CurrentCamera
		local view = if camera then camera.ViewportSize else Vector2.new(1280, 720)
		local fit = math.clamp(math.min((view.X - 20) / width, (view.Y - 40) / height), 0.5, 1)
		if not popupGui.Enabled then
			-- Pop in when the window opens.
			windowScale.Scale = fit * 0.85
			Art.tween(windowScale, 0.22, { Scale = fit }, Enum.EasingStyle.Back)
		else
			windowScale.Scale = fit
		end
		popupGui.Enabled = true
		redraw()
	end

	isModalOpen = function(key: string): boolean
		return openKey == key
	end

	shade.Activated:Connect(closeModal)
	closeButton.Activated:Connect(closeModal)
end

-- Pages that live in their own modules. Each gets the shared helpers in
-- `ui`, builds its widgets once and draws every state.
ui = {
	art = Art,
	itemArt = ItemArt,
	crewRows = crewRows,
	pages = pages,
	player = player,
	colors = {
		text = COLOR_TEXT,
		dim = COLOR_DIM,
		header = COLOR_HEADER,
		gold = COLOR_GOLD,
		action = COLOR_ACTION,
		buy = COLOR_BUY,
		claim = COLOR_CLAIM,
		info = COLOR_INFO,
		selected = COLOR_SELECTED,
		row = COLOR_ROW,
		panel = COLOR_PANEL,
		disabled = COLOR_DISABLED,
	},
	makeRow = makeRow,
	makeGrid = makeGrid,
	makeCard = makeCard,
	makeHeading = makeHeading,
	makeButtonRow = makeButtonRow,
	makeAmountBox = makeAmountBox,
	makeText = makeText,
	makeFrame = makeFrame,
	makeButton = makeButton,
	addCorner = addCorner,
	addStroke = addStroke,
	setButton = setButton,
	setBadge = setBadge,
	send = send,
	nextOrder = nextOrder,
	formatLong = formatLong,
	formatClock = formatClock,
	rarityName = rarityName,
	statText = statText,
	robuxText = robuxText,
	redraw = function()
		redraw()
	end,
	openModal = function(key: string, title: string?)
		openModal(key, title)
	end,
	showPage = function(name: string)
		showPage(name)
	end,
	closeModal = function()
		closeModal()
	end,
	isOpen = function(key: string): boolean
		return isModalOpen(key)
	end,
}
local pageModules = {}
for _, name in { "AmountPopup", "ProfilePage", "RebirthPage", "RankingsPage", "MailPage", "RelicPage", "BarracksPage", "ExpeditionsPage", "ChroniclePage", "AutoPopups", "EstatePage", "KeepPage", "PassPopup", "ChestShelf", "RollReel" } do
	local module = require(script.Parent:WaitForChild(name))
	module.build(ui)
	table.insert(pageModules, module)
end

showPage("Quests")

---------------------------------------------------------------------------
-- Drawing the state the server sends
---------------------------------------------------------------------------

local lastState = nil
local refreshRecruitWindow -- defined further down, with the recruit window

-- Shop and Royal Pass pages, built and drawn inside one block so their
-- widgets do not count toward the main chunk's limit of 200 locals.
local drawStore
do
	local shopSummary = makeRow(pages.Shop, nextOrder(), 50, false)
	shopSummary.RichText = true

	local productRows = {}
	local function makeProductRow(product, grid: Instance?)
		local info, button
		if grid then
			info, button = makeCard(grid)
		else
			info, button = makeRow(pages.Shop, nextOrder(), 60, true)
		end
		info.RichText = true
		productRows[product.key] = { info = info, button = button, frame = info.Parent }
		button.Activated:Connect(function()
			send("Robux", "product:" .. product.key)
		end)
	end

	makeHeading(pages.Shop, nextOrder(), "Crowns")
	local crownGrid = makeGrid(pages.Shop, nextOrder(), 96, 4)
	for _, product in StoreConfig.Products do
		if product.group == "crowns" then
			makeProductRow(product, crownGrid)
		end
	end

	makeHeading(pages.Shop, nextOrder(), "Special offers")
	local packGrid = makeGrid(pages.Shop, nextOrder(), 136, 3)
	for _, product in StoreConfig.Products do
		if product.group == "pack" then
			makeProductRow(product, packGrid)
		end
	end

	makeHeading(pages.Shop, nextOrder(), "Tithe Chest")
	for _, product in StoreConfig.Products do
		if product.group == "tithe" then
			makeProductRow(product, nil)
		end
	end

	makeHeading(pages.Shop, nextOrder(), "Game passes (yours forever)")
	local passRows = {}
	local passGrid = makeGrid(pages.Shop, nextOrder(), 124, 3)
	for _, pass in StoreConfig.Passes do
		local info, button = makeCard(passGrid)
		info.RichText = true
		info.Text = `<b>{pass.name}</b>\n{pass.note}`
		passRows[pass.key] = button
		button.Activated:Connect(function()
			send("Robux", "pass:" .. pass.key)
		end)
	end

	makeHeading(pages.Shop, nextOrder(), "Crown shop")
	local crownRows = {}
	local crownShopGrid = makeGrid(pages.Shop, nextOrder(), 96, 3)
	for _, item in StoreConfig.CrownShop do
		local info, button = makeCard(crownShopGrid)
		info.RichText = true
		info.Text = `<b>{item.name}</b>\n{item.note}`
		crownRows[item.key] = button
		button.Activated:Connect(function()
			send("CrownBuy", item.key)
		end)
	end

	makeHeading(pages.Shop, nextOrder(), "Royal Coffers (best gear, odds shown, open them in your Inventory)")
	local cofferRows = {}
	local cofferGrid = makeGrid(pages.Shop, nextOrder(), 132, 2)
	for _, coffer in StoreConfig.Coffers do
		local info, first = makeCard(cofferGrid)
		info.RichText = true
		-- Buy 1, a bundle of 5 or a bundle of 10 (bundles cost less each).
		local buttons = {}
		for index, bundle in StoreConfig.CofferBundles do
			local button = first
			if index > 1 then
				button = makeButton(info.Parent, UDim2.new(1, -16, 0, 36), UDim2.new(0, 8, 1, -42), COLOR_DISABLED)
				button.TextSize = 12
			end
			local count = #StoreConfig.CofferBundles
			button.Size = UDim2.new(1 / count, -(8 + 8 / count), 0, 40)
			button.Position = UDim2.new((index - 1) / count, 8 - (index - 1) * 4, 1, -46)
			button.TextSize = 12
			buttons[index] = button
			button.Activated:Connect(function()
				send("Coffer", `{coffer.key}:{bundle.count}`)
			end)
		end
		cofferRows[coffer.key] = { info = info, buttons = buttons }
	end

	-- Royal Pass: progress, weekly challenges, then every tier.
	local passInfo, nobleButton = makeRow(pages["Royal Pass"], nextOrder(), 74, true)
	passInfo.RichText = true
	nobleButton.Activated:Connect(function()
		send("Robux", "product:passPremium")
	end)

	local passBarRow = makeFrame(pages["Royal Pass"], UDim2.new(1, -10, 0, 30), UDim2.fromOffset(0, 0), COLOR_ROW)
	passBarRow.LayoutOrder = nextOrder()
	addCorner(passBarRow, 6)
	local passBar = makeBar(passBarRow, UDim2.new(1, -20, 0, 18), UDim2.fromOffset(10, 6), COLOR_GOLD)

	local passButtons = makeButtonRow(pages["Royal Pass"], nextOrder(), "", { "Claim all", "Buy a tier" })
	passButtons[1].Activated:Connect(function()
		send("PassClaim", "all")
	end)
	passButtons[2].Activated:Connect(function()
		send("PassSkip")
	end)

	makeHeading(pages["Royal Pass"], nextOrder(), "Weekly challenges")
	local challengeRows = {}
	for _, challenge in StoreConfig.WeeklyChallenges do
		local info, button = makeRow(pages["Royal Pass"], nextOrder(), 46, true)
		info.RichText = true
		challengeRows[challenge.key] = { info = info, button = button }
		button.Activated:Connect(function()
			send("WeeklyClaim", challenge.key)
		end)
	end

	makeHeading(pages["Royal Pass"], nextOrder(), "Rewards")
	local tierRows = {}
	for tier = 1, StoreConfig.PassTiers do
		local info, button = makeRow(pages["Royal Pass"], nextOrder(), 46, true)
		info.RichText = true
		tierRows[tier] = { info = info, button = button }
		button.Activated:Connect(function()
			send("PassClaim", tostring(tier))
		end)
	end

	drawStore = function(state)
		local crowns = state.crowns
		local ownedPasses = 0
		for _ in state.passes do
			ownedPasses += 1
		end
		shopSummary.Text = `<b>{crowns} Crowns</b>   |   {ownedPasses} of {#StoreConfig.Passes} game passes owned\n`
			.. "Crowns buy refills, boosts, coffers and Royal Pass tiers. Robux buttons open the Roblox purchase window."

		for _, product in StoreConfig.Products do
			local row = productRows[product.key]
			if not row then
				continue
			end
			if product.group == "crowns" then
				local tag = if product.tag then `   <font color="#F0C85A">{product.tag}</font>` else ""
				row.info.Text = `<b>{product.name}</b>{tag}\n{product.crowns} Crowns`
				setButton(row.button, robuxText(product.price), true, COLOR_BUY)
			elseif product.group == "pack" then
				local bought = state.packsBought[product.key] == true
				local secondsLeft = if product.hours then product.hours * 3600 - state.secondsSinceFirstVisit else 0
				local expired = product.hours ~= nil and secondsLeft <= 0
				row.frame.Visible = bought or not expired
				local when = product.note
				if product.hours and not bought then
					when = `Ends in {formatLong(secondsLeft)}`
				end
				row.info.Text = `<b>{product.name}</b>   {when}\n{StoreConfig.describeList(product.rewards)}`
				if bought then
					setButton(row.button, "Owned", false, COLOR_BUY)
				elseif product.level and state.level < product.level then
					setButton(row.button, `Level {product.level}`, false, COLOR_BUY)
				else
					setButton(row.button, robuxText(product.price), true, COLOR_BUY)
				end
			elseif product.group == "tithe" then
				Art.progress(row.info, state.tithe, StoreConfig.TitheMax, Color3.fromRGB(200, 150, 230))
				row.info.Text = `<b>Tithe Chest: {state.tithe} / {StoreConfig.TitheMax} Crowns</b>\n`
					.. `Fills as you play: 1 Crown per {StoreConfig.TitheEnergyPerCrown} quest energy and {StoreConfig.TitheCrownsPerFoe} per foe beaten. `
					.. `Break it once it holds {StoreConfig.TitheMinToBreak}.`
				setButton(row.button, `Break\n{robuxText(product.price)}`, state.tithe >= StoreConfig.TitheMinToBreak, COLOR_BUY)
			end
		end

		for _, pass in StoreConfig.Passes do
			local owned = state.passes[pass.key] == true
			setButton(passRows[pass.key], if owned then "Owned" else robuxText(pass.price), not owned, COLOR_BUY)
		end

		for _, item in StoreConfig.CrownShop do
			setButton(crownRows[item.key], `Buy\n{item.cost} Crowns`, crowns >= item.cost, COLOR_BUY)
		end

		for _, coffer in StoreConfig.Coffers do
			local row = cofferRows[coffer.key]
			local odds = {}
			for _, pair in coffer.odds do
				local label = rarityName({ rarity = pair[1], name = "" })
				table.insert(odds, `{label}{pair[2]}%`)
			end
			local left = coffer.pityEvery - (state.pity[coffer.key] or 0)
			Art.progress(row.info, coffer.pityEvery - left, coffer.pityEvery, Color3.fromRGB(180, 100, 230))
			row.info.Text = `<b>{coffer.name}</b>: Royal gear, the strongest stats\n{table.concat(odds, "   ")}\n`
				.. `{coffer.pityRarity} or better guaranteed within {left} opens`
			for index, bundle in StoreConfig.CofferBundles do
				local cost = StoreConfig.bundleCost(coffer, bundle.count) or 0
				local off = if bundle.discount > 0 then `  -{math.floor(bundle.discount * 100 + 0.5)}%` else ""
				setButton(row.buttons[index], `x{bundle.count}{off}\n{cost} Crowns`, crowns >= cost, if bundle.discount > 0 then COLOR_CLAIM else COLOR_BUY)
			end
		end

		-- Royal Pass
		local pass = state.pass
		local tier = StoreConfig.getTier(pass.points)
		local maxTier = StoreConfig.PassTiers
		local season = pass.season + 1
		passInfo.Text = `<b>ROYAL PASS, SEASON {season}</b>   Ends in {formatLong(state.passSecondsLeft)}\n`
			.. `Tier {tier} of {maxTier}. Earn points from quests, foes, playtime rewards and weekly challenges. `
			.. (if pass.noble then "<font color=\"#F0C85A\">Noble track unlocked.</font>" else "The Noble track adds a second reward to every tier.")
		if pass.noble then
			setButton(nobleButton, "Noble\nunlocked", false, COLOR_GOLD)
		else
			local product = StoreConfig.getProduct("passPremium")
			setButton(nobleButton, `Unlock Noble\n{robuxText(product and product.price or 0)}`, true, COLOR_SELECTED)
		end
		if tier >= maxTier then
			setBar(passBar, 1, 1, "Every tier reached")
		else
			local into = pass.points - tier * StoreConfig.PointsPerTier
			setBar(passBar, into, StoreConfig.PointsPerTier, `{into} / {StoreConfig.PointsPerTier} points to tier {tier + 1}`)
		end

		local claimable = 0
		for index = 1, maxTier do
			local key = tostring(index)
			local rewards = StoreConfig.PassRewards[index]
			local freeDone = pass.claimedFree[key] == true
			local nobleDone = pass.claimedNoble[key] == true
			local reached = index <= tier
			local function part(label: string, reward, done: boolean, locked: boolean): string
				local text = `{label}: {StoreConfig.describe(reward)}`
				if done then
					return `<font color="#9FD49A">{text} (claimed)</font>`
				elseif locked then
					return `<font color="#8C918A">{text}</font>`
				end
				return text
			end
			local row = tierRows[index]
			row.info.Text = `<b>Tier {index}</b>\n{part("Free", rewards.free, freeDone, false)}   |   {part("Noble", rewards.noble, nobleDone, not pass.noble)}`
			local open = reached and (not freeDone or (pass.noble and not nobleDone))
			if open then
				claimable += 1
				setButton(row.button, "Claim", true, COLOR_CLAIM)
			elseif reached then
				setButton(row.button, "Claimed", false, COLOR_BUY)
			else
				setButton(row.button, "Locked", false, COLOR_BUY)
			end
		end
		setButton(passButtons[1], if claimable > 0 then `Claim all ({claimable})` else "Claim all", claimable > 0, COLOR_CLAIM)
		setButton(passButtons[2], `Buy a tier ({StoreConfig.TierSkipCost} Crowns)`, tier < maxTier and crowns >= StoreConfig.TierSkipCost, COLOR_SELECTED)

		local weekly = state.weekly
		for _, challenge in StoreConfig.WeeklyChallenges do
			local row = challengeRows[challenge.key]
			local value = math.min(challenge.goal, weekly[challenge.stat] or 0)
			Art.progress(row.info, value, challenge.goal)
			local shown = if challenge.stat == "play"
				then `{math.floor(value / 60)} / {math.floor(challenge.goal / 60)} min`
				else `{value} / {challenge.goal}`
			row.info.Text = `<b>{challenge.name}</b>   +{challenge.points} points\n{shown}   |   New challenges in {formatLong(state.weekSecondsLeft)}`
			if weekly.claimed[challenge.key] then
				setButton(row.button, "Done", false, COLOR_BUY)
			else
				setButton(row.button, "Claim", value >= challenge.goal, COLOR_CLAIM)
			end
		end

		-- Red-dot style counts on the rail.
		local weeklyReady = 0
		for _, challenge in StoreConfig.WeeklyChallenges do
			if not state.weekly.claimed[challenge.key] and (state.weekly[challenge.stat] or 0) >= challenge.goal then
				weeklyReady += 1
			end
		end
		setBadge("Royal Pass", claimable + weeklyReady)
	end
end

-- Bounties, Festival and Research pages, built and drawn in one block.
-- drawLoop returns how many things are ready to claim on Bounties and
-- Festival, for the menu badges.
local drawLoop
do
	-- Bounties: login streak, daily and weekly tasks, and the Seal shop.
	makeHeading(pages.Bounties, nextOrder(), "Login streak")
	local streakCards = {}
	local streakGrid = makeGrid(pages.Bounties, nextOrder(), 88, 4)
	for day, reward in BountyConfig.Streak do
		local info, button = makeCard(streakGrid)
		info.RichText = true
		info.Text = `<b>Day {day}</b>\n{StoreConfig.describe(reward)}`
		streakCards[day] = button
		button.Activated:Connect(function()
			send("StreakClaim")
		end)
	end

	local bountySummary = makeRow(pages.Bounties, nextOrder(), 44, false)
	bountySummary.RichText = true

	local dailyHeading = makeText(pages.Bounties, UDim2.new(1, -10, 0, 22), UDim2.fromOffset(0, 0), COLOR_HEADER, 14)
	dailyHeading.LayoutOrder = nextOrder()
	dailyHeading.Font = Enum.Font.GothamBold
	local bountyRows = {}
	for _, task in BountyConfig.Daily do
		local info, button = makeRow(pages.Bounties, nextOrder(), 46, true)
		info.RichText = true
		bountyRows[task.key] = { info = info, button = button }
		button.Activated:Connect(function()
			send("BountyClaim", task.key)
		end)
	end
	local weeklyHeading = makeText(pages.Bounties, UDim2.new(1, -10, 0, 22), UDim2.fromOffset(0, 0), COLOR_HEADER, 14)
	weeklyHeading.LayoutOrder = nextOrder()
	weeklyHeading.Font = Enum.Font.GothamBold
	for _, task in BountyConfig.Weekly do
		local info, button = makeRow(pages.Bounties, nextOrder(), 46, true)
		info.RichText = true
		bountyRows[task.key] = { info = info, button = button }
		button.Activated:Connect(function()
			send("BountyClaim", task.key)
		end)
	end

	makeHeading(pages.Bounties, nextOrder(), "Seal shop (stock refills every Monday)")
	local sealRows = {}
	local sealGrid = makeGrid(pages.Bounties, nextOrder(), 96, 3)
	for _, item in BountyConfig.Shop do
		local info, button = makeCard(sealGrid)
		info.RichText = true
		sealRows[item.key] = { info = info, button = button }
		button.Activated:Connect(function()
			send("SealBuy", item.key)
		end)
	end

	-- Festival: this week's festival, milestones and the leaderboard.
	local festivalInfo = makeRow(pages.Festival, nextOrder(), 92, false)
	festivalInfo.RichText = true

	makeHeading(pages.Festival, nextOrder(), "Milestones")
	local milestoneRows = {}
	local milestoneGrid = makeGrid(pages.Festival, nextOrder(), 88, 4)
	for index, milestone in FestivalConfig.Milestones do
		local info, button = makeCard(milestoneGrid)
		info.RichText = true
		info.Text = `<b>{milestone.points} points</b>\n{StoreConfig.describe(milestone.reward)}`
		milestoneRows[index] = button
		button.Activated:Connect(function()
			send("FestivalMilestone", tostring(index))
		end)
	end

	makeHeading(pages.Festival, nextOrder(), "Leaderboard (all servers, updates every minute)")
	local leaderText = makeRow(pages.Festival, nextOrder(), 20 * FestivalConfig.LeaderboardSize + 16, false)
	leaderText.RichText = true
	leaderText.TextYAlignment = Enum.TextYAlignment.Top

	makeHeading(pages.Festival, nextOrder(), "Rank rewards (paid next week)")
	local rankText = makeRow(pages.Festival, nextOrder(), 20 * #FestivalConfig.RankRewards + 16, false)
	rankText.TextYAlignment = Enum.TextYAlignment.Top
	do
		local lines = {}
		for _, entry in FestivalConfig.RankRewards do
			table.insert(lines, `{entry.label}: {StoreConfig.describeList(entry.rewards)}`)
		end
		lines[#lines] ..= ` (with at least {FestivalConfig.MinPointsForReward} points)`
		rankText.Text = table.concat(lines, "\n")
	end

	-- Research: what is running, then every tech by branch.
	local researchInfo, researchFinish = makeRow(pages.Research, nextOrder(), 56, true)
	researchInfo.RichText = true
	researchFinish.Activated:Connect(function()
		send("ResearchFinish")
	end)
	local techRows = {}
	for _, branch in ResearchConfig.Branches do
		makeHeading(pages.Research, nextOrder(), branch.name)
		local grid = makeGrid(pages.Research, nextOrder(), 128, 3)
		for _, tech in branch.techs do
			local info, button = makeCard(grid)
			info.RichText = true
			info.TextSize = 12
			techRows[tech.key] = { info = info, button = button }
			button.Activated:Connect(function()
				send("Research", tech.key)
			end)
		end
	end

	drawLoop = function(state): (number, number)
		local bounty = state.bounty
		local bountyReady = 0

		-- Login streak
		for day, button in streakCards do
			if state.streakReady and day == state.streakDay then
				bountyReady += 1
				setButton(button, "Claim", true, COLOR_CLAIM)
			elseif day < state.streakDay or (not state.streakReady and day == state.streakDay) then
				setButton(button, "Claimed", false, COLOR_CLAIM)
			else
				setButton(button, `Day {day}`, false, COLOR_CLAIM)
			end
		end

		local dayLeft = 86400 - os.time() % 86400
		bountySummary.Text = `<b>{state.seals} Seals</b>   |   Finish bounties for Seals, then spend them in the Seal shop below.`
		dailyHeading.Text = `DAILY BOUNTIES   (new ones in {formatLong(dayLeft)})`
		weeklyHeading.Text = `WEEKLY BOUNTIES   (new ones in {formatLong(state.weekSecondsLeft)})`
		local function drawTask(task, counts)
			local row = bountyRows[task.key]
			local value = math.min(task.goal, counts[task.stat] or 0)
			Art.progress(row.info, value, task.goal)
			row.info.Text = `<b>{task.name}</b>   +{task.seals} Seals\n{value} / {task.goal}`
			if bounty.claimed[task.key] then
				setButton(row.button, "Done", false, COLOR_CLAIM)
			elseif value >= task.goal then
				bountyReady += 1
				setButton(row.button, "Claim", true, COLOR_CLAIM)
			else
				setButton(row.button, "Claim", false, COLOR_CLAIM)
			end
		end
		for _, task in BountyConfig.Daily do
			drawTask(task, bounty.daily)
		end
		for _, task in BountyConfig.Weekly do
			drawTask(task, bounty.weekly)
		end
		for _, item in BountyConfig.Shop do
			local row = sealRows[item.key]
			local left = item.limit - (bounty.bought[item.key] or 0)
			row.info.Text = `<b>{item.name}</b>\n{StoreConfig.describe(item.reward)}\n{left} of {item.limit} left this week`
			if left <= 0 then
				setButton(row.button, "Sold out", false, COLOR_BUY)
			else
				setButton(row.button, `Buy\n{item.cost} Seals`, state.seals >= item.cost, COLOR_BUY)
			end
		end

		-- Festival
		local festivalState = state.festival
		local festival = FestivalConfig.getFestival(festivalState.week)
		local festivalReady = 0
		local pointParts = {}
		for stat, points in festival.points do
			table.insert(pointParts, `{stat} +{points}`)
		end
		table.sort(pointParts)
		festivalInfo.Text = `<b>{string.upper(festival.name)}</b>   Ends in {formatLong(state.weekSecondsLeft)}\n`
			.. `<font color="#F0C450">This week: {festival.bonusText}</font>\n`
			.. `Your points: <b>{math.floor(festivalState.points)}</b>\n`
			.. `Points for: {table.concat(pointParts, ", ")}`
		do
			local goal = 0
			for _, milestone in FestivalConfig.Milestones do
				if festivalState.points < milestone.points then
					goal = milestone.points
					break
				end
			end
			if goal > 0 then
				Art.progress(festivalInfo, festivalState.points, goal, Color3.fromRGB(230, 120, 70))
			else
				Art.progress(festivalInfo, 1, 1)
			end
		end
		for index, milestone in FestivalConfig.Milestones do
			local button = milestoneRows[index]
			if festivalState.milestones[tostring(index)] then
				setButton(button, "Claimed", false, COLOR_CLAIM)
			elseif festivalState.points >= milestone.points then
				festivalReady += 1
				setButton(button, "Claim", true, COLOR_CLAIM)
			else
				setButton(button, `{math.floor(festivalState.points)} / {milestone.points}`, false, COLOR_CLAIM)
			end
		end
		local lines = {}
		for index, entry in state.festivalTop do
			local name = entry[1]
			if name == player.Name then
				name = `<b>{name} (you)</b>`
			end
			table.insert(lines, `#{index}   {name}   {Format.short(entry[2])}`)
		end
		if #lines == 0 then
			table.insert(lines, "No scores yet this week. The board fills in once games save (about every minute).")
		end
		leaderText.Text = table.concat(lines, "\n")

		-- Research
		local research = state.research
		local busy = research.active ~= ""
		if busy then
			local tech = ResearchConfig.Techs[research.active]
			local level = (research.levels[research.active] or 0) + 1
			local total = if tech then ResearchConfig.getSeconds(tech, level - 1) else 0
			Art.progress(researchInfo, total - state.researchLeft, total, COLOR_INFO)
			researchInfo.Text = `<b>Researching {tech and tech.name or research.active} level {level}</b>\n`
				.. `Done in {formatLong(state.researchLeft)}. Research keeps going while you are away.`
			local cost = ResearchConfig.getFinishCost(state.researchLeft)
			setButton(researchFinish, `Finish now\n{cost} Crowns`, state.crowns >= cost, COLOR_SELECTED)
		else
			researchInfo.Text = "<b>The scholars are idle.</b>\nPick a research below. Only one runs at a time."
			Art.progress(researchInfo, 0, 1)
			setButton(researchFinish, "Idle", false, COLOR_SELECTED)
		end
		for key, row in techRows do
			local tech = ResearchConfig.Techs[key]
			local level = research.levels[key] or 0
			local nowText = if level > 0 then ResearchConfig.describe(tech, level) else "nothing yet"
			Art.progress(row.info, level, tech.maxLevel, COLOR_INFO)
			local text = `<b>{tech.name}</b>   Lv {level} / {tech.maxLevel}\nNow: {nowText}`
			local locked = false
			if tech.needs and (research.levels[tech.needs[1]] or 0) < tech.needs[2] then
				local need = ResearchConfig.Techs[tech.needs[1]]
				text ..= `\n<font color="#C8846E">Needs {need and need.name or tech.needs[1]} level {tech.needs[2]}</font>`
				locked = true
			elseif level < tech.maxLevel then
				text ..= `\nNext: {ResearchConfig.describe(tech, level + 1)}, {formatLong(ResearchConfig.getSeconds(tech, level))}`
			end
			row.info.Text = text
			if level >= tech.maxLevel then
				setButton(row.button, "Fully researched", false, COLOR_BUY)
			elseif research.active == key then
				setButton(row.button, `In progress\n{formatLong(state.researchLeft)}`, false, COLOR_BUY)
			elseif locked then
				setButton(row.button, "Locked", false, COLOR_BUY)
			else
				local cost = ResearchConfig.getCost(tech, level)
				setButton(row.button, `Research\n{Format.short(cost)}`, not busy and state.gold >= cost, COLOR_BUY)
			end
		end

		return bountyReady, festivalReady
	end
end

local function draw(state)
	lastState = state
	local stats = state.stats
	local gold = state.gold
	drawStore(state)
	local bountyReady, festivalReady = drawLoop(state)
	setBadge("Bounties", bountyReady)
	setBadge("Festival", festivalReady)
	for _, module in pageModules do
		module.draw(state, ui)
	end

	-- Top bar
	local title = if state.title ~= "" then state.title .. " " else ""
	levelBadge.Text = tostring(state.level)
	nameLabel.Text = `{title}{player.DisplayName}`
	nameLabel.TextColor3 = if state.passes.charter then COLOR_GOLD else COLOR_HEADER
	setBar(xpBar, state.xp, state.xpNeeded, `XP {state.xp} / {state.xpNeeded}`)
	chips.gold.value.Text = Format.short(gold)
	chips.gold.sub.Text = `Banked {Format.short(state.banked)}`
	chips.crowns.value.Text = Format.short(state.crowns)
	chips.crowns.sub.Text = if state.tithe > 0 then `{state.tithe} in Tithe Chest` else "premium"
	do
		-- "(+1 0:07)" until the next point, or FULL.
		local regen = state.regenIn or {}
		local function regenText(key: string): string
			local left = regen[key] or 0
			return if left > 0 then `   (+1 {math.floor(left / 60)}:{string.format("%02d", left % 60)})` else "   (FULL)"
		end
		setBar(energyBar, state.energy, stats.maxEnergy, `{state.energy} / {stats.maxEnergy}{regenText("energy")}`)
		setBar(staminaBar, state.stamina, stats.maxStamina, `{state.stamina} / {stats.maxStamina}{regenText("stamina")}`)
		setBar(healthBar, state.health, stats.maxHealth, `{state.health} / {stats.maxHealth}{regenText("health")}`)
	end

	-- Header chips for anything boosting the player right now.
	local boosts = {}
	if state.xpBoostLeft > 0 then
		table.insert(boosts, { `2x XP {formatClock(state.xpBoostLeft)}`, COLOR_XP })
	end
	if state.autoQuestOn and state.passes.autoquest then
		table.insert(boosts, { "Auto quests", COLOR_INFO })
	end
	if state.autoBuy.on and state.passes.autobuy then
		table.insert(boosts, { "Auto-buy", COLOR_INFO })
	end
	if state.passes.charter then
		table.insert(boosts, { "Royal Charter", COLOR_SELECTED })
	end
	setBoostChips(boosts)

	-- Tips the player has dismissed, saved on the server.
	local tipsChanged = false
	for name in state.tipsSeen do
		if not tipsSeen[name] then
			tipsSeen[name] = true
			tipsChanged = true
		end
	end
	if tipsChanged then
		placePage()
	end

	-- Badges: skill points to spend and playtime rewards ready on the Keep.
	local keepCount = state.skillPoints
	for index, reward in GameConfig.PlaytimeRewards do
		if not state.claimed[tostring(index)] and state.playSeconds >= reward.minutes * 60 then
			keepCount += 1
		end
	end
	setBadge("Keep", keepCount)

	local played = state.playSeconds
	playtimeSummary.Text = `Played today: {math.floor(played / 3600)}h {math.floor(played / 60) % 60}m. Rewards reset at 00:00 UTC.`
	for index, reward in GameConfig.PlaytimeRewards do
		local row = rewardRows[index]
		local key = tostring(index)
		Art.progress(row.info, if state.claimed[key] then 1 else played, if state.claimed[key] then 1 else reward.minutes * 60)
		if state.claimed[key] then
			setButton(row.button, "Claimed", false, COLOR_BUY)
		elseif played >= reward.minutes * 60 then
			setButton(row.button, "Claim", true, COLOR_CLAIM)
		else
			setButton(row.button, `In {formatClock(reward.minutes * 60 - played)}`, false, COLOR_BUY)
		end
	end

	-- Quests
	ownsAutoQuest = state.passes.autoquest == true
	autoQuestOn = state.autoQuestOn and ownsAutoQuest
	local autoTarget = GameConfig.pickAutoQuest(state.autoQuestMode, state.level, state.quests, state.autoQuest)
	local modeName = "Repeat last quest"
	for _, mode in GameConfig.AutoQuestModes do
		if mode.id == state.autoQuestMode then
			modeName = mode.name
		end
	end
	if not ownsAutoQuest then
		autoQuestInfo.Text = "<b>Auto quests</b>\nThe Quest Herald game pass does quests for you whenever you have the energy."
	else
		autoQuestInfo.Text = `<b>Auto quests: {if autoQuestOn then "ON" else "OFF"}</b>   ({modeName})\n`
			.. (if autoTarget then `Next: <b>{autoTarget.name}</b>, {autoTarget.energy} energy.` else "Do a quest once first.")
	end
	if ownsAutoQuest then
		setButton(autoQuestButton, if autoQuestOn then "Auto: ON\nSettings" else "Auto quests\nSettings", true, if autoQuestOn then COLOR_CLAIM else COLOR_SELECTED)
	else
		setButton(autoQuestButton, "\u{1F512} Auto quests\nGet pass", false, COLOR_SELECTED)
	end
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
		if rank >= GameConfig.MaxMasteryRanks then
			Art.progress(row.info, 1, 1, Color3.fromHex(medalColors[#medalColors]), true)
		else
			Art.progress(row.info, done % GameConfig.MasteryPerRank, GameConfig.MasteryPerRank, Color3.fromHex(medalColors[rank + 1] or "#F0C85A"))
		end
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
	Art.progress(holdingSummary, stats.lotsUsed, stats.lots, Color3.fromRGB(110, 170, 90), true)
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
	marketWindowShown = state.marketWindow
	Art.progress(marketSummary, GameConfig.MarketRestockSeconds - state.marketRestock, GameConfig.MarketRestockSeconds, COLOR_INFO, true)
	marketSummary.Text = `New stock in {formatClock(state.marketRestock)}\nItems roll around your level. Rarer items are stronger and cost more.`
	for index, row in marketRows do
		local item = state.market[index]
		if not item then
			row.info.Parent.Visible = false
			continue
		end
		row.info.Parent.Visible = true
		ItemArt.set(row.picture, item)
		local chest = if item.kind == "Chest" then ChestConfig.get(item.chest or "") else nil
		if chest then
			local c = chest.color
			local hex = string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
			row.info.Text = `<font color="{hex}"><b>{chest.name}</b></font>  (chest, opens in your Inventory)\n{chest.note}`
		else
			local needs = if state.level < item.level then `<font color="#F07060">Needs Lv {item.level}</font>` else `Lv {item.level}`
			row.info.Text = `{rarityName(item)}  ({string.lower(item.slot or "")})  {needs}\n{statText(item.attack or 0, item.defense or 0)}`
		end
		if item.sold then
			setButton(row.button, "Sold", false, COLOR_BUY)
		elseif state.level < item.level then
			setButton(row.button, `Level {item.level}`, false, COLOR_BUY)
		else
			local price = math.floor(item.price * (1 - festivalDiscount(state, "marketPrice")))
			setButton(row.button, `Buy\n{Format.short(price)}`, gold >= price, COLOR_BUY)
		end
	end

	-- Auto-buy
	local rule = state.autoBuy
	ownsAutoBuy = state.passes.autobuy == true
	autoBuyRunning = rule.on and ownsAutoBuy
	if ownsAutoBuy then
		autoBuyInfo.Text = `<b>Auto-buy: {if autoBuyRunning then "RUNNING" else "OFF"}</b>   Bought {rule.bought}, spent {Format.short(rule.spent)} gold\n`
			.. `{rule.minRarity} or better. Buys matching Market items as they appear, while you are in the game.`
	else
		autoBuyInfo.Text = "<b>Auto-buy</b>\nThe Market Steward game pass buys gear that matches your rules every restock."
	end
	if ownsAutoBuy then
		setButton(autoBuyButton, if autoBuyRunning then "Auto: ON\nSettings" else "Auto-buy\nSettings", true, if autoBuyRunning then COLOR_CLAIM else COLOR_SELECTED)
	else
		setButton(autoBuyButton, "\u{1F512} Auto-buy\nGet pass", false, COLOR_SELECTED)
	end
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
	local autoRoll = state.autoRoll
	warbandSummary.Text = `Soldiers {stats.crewSize} / {#crew}   |   Attack {Format.short(stats.attack)}   |   Defense {Format.short(stats.defense)}\n`
		.. (if autoRoll.on
			then `Auto roll is on: {autoRoll.tier} recruits until {autoRoll.rarity}, {autoRoll.rolls} rolls so far.`
			else `Warband size bonus +{math.floor(stats.crewBonus * 100 + 0.5)}% attack and defense`)
	ownsAutoRoll = state.passes.autoroll == true
	if ownsAutoRoll then
		setButton(autoRollButton, if autoRoll.on then "Auto roll: ON\nSettings" else "Auto roll", true, if autoRoll.on then COLOR_CLAIM else COLOR_ACTION)
	else
		setButton(autoRollButton, "\u{1F512} Auto roll\nGet pass", false, COLOR_ACTION)
	end

	equipNewOn = state.autoEquipNew == true
	setButton(equipButtons[1], "Equip best", true, COLOR_BUY)
	setButton(equipButtons[2], if equipNewOn then "New gear: put on" else "New gear: keep spare", true, COLOR_SELECTED)

	youRow.info.Text = `<b>You</b>, leader\nAttack {GameConfig.BaseAttack + (state.skills.attack or 0)}, defense {GameConfig.BaseDefense + (state.skills.defense or 0)} before gear`
	local youCounts = memberSetCounts(state, 0)
	youRow.gearText.Text = `Weapon: {gearLine(state.yourGear.Weapon, youCounts)}\nArmor: {gearLine(state.yourGear.Armor, youCounts)}\nMount: {gearLine(state.yourGear.Mount, youCounts)}`
	setButton(youRow.gear, "Gear", true, COLOR_SELECTED)

	for slot, row in crewRows do
		local soldier = crew[slot]
		row.frame.Visible = soldier ~= nil
		if soldier == nil then
			continue
		end
		if soldier then
			local rank = if soldier.train > 0 then ` +{soldier.train}` else ""
			row.info.Text = `{rarityName({ rarity = soldier.rarity, name = soldier.class })}{rank}\n{soldier.name}, {soldier.tier} recruit\n{statText(soldier.attack, soldier.defense)}`
			local counts = memberSetCounts(state, slot)
			row.gearText.Text = `Weapon: {gearLine(soldier.gear.Weapon, counts)}\nArmor: {gearLine(soldier.gear.Armor, counts)}\nMount: {gearLine(soldier.gear.Mount, counts)}`
			row.gear.Visible = true
			setButton(row.gear, "Gear", true, COLOR_SELECTED)
			row.train.Visible = true
			if soldier.train >= GameConfig.MaxTrainRank then
				setButton(row.train, "Fully trained", false, COLOR_BUY)
			else
				setButton(row.train, `Train +{soldier.train + 1}\n{Format.short(soldier.trainCost)}`, gold >= soldier.trainCost, COLOR_BUY)
			end
			-- A reroll only replaces the soldier with one at least as rare.
			local tier = oneRollTier(state)
			local keep = soldier.rarity
			if GameConfig.getChanceAtLeast(tier, keep) <= 0 then
				row.rollId = nil
				setButton(row.roll, `Reroll\n{tier.id} can't beat`, false, COLOR_ACTION)
			else
				row.rollId = `{slot}:{tier.id}:{keep}:this:once`
				setButton(row.roll, `Reroll\n{tier.id} {Format.short(oneRollCost(state, tier))}`, gold >= oneRollCost(state, tier), COLOR_ACTION)
			end
			row.release.Visible = true
			setButton(row.release, "Release", true, COLOR_DISABLED)
		else
			row.info.Text = `<b>Empty slot {slot}</b>\nRecruit someone to fill it.`
			row.gearText.Text = ""
			row.train.Visible = false
			row.release.Visible = false
			row.gear.Visible = false
			local tier = oneRollTier(state)
			row.rollId = `{slot}:{tier.id}:Common:this:once`
			setButton(row.roll, `Recruit\n{tier.id} {Format.short(oneRollCost(state, tier))}`, gold >= oneRollCost(state, tier), COLOR_ACTION)
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
		setButton(tabButtons[index], if tab == "Trophies" or tab == "Sets" then tab else (if tab == "All" then "All gear" else tab .. "s"), tab == inventoryTab, COLOR_SELECTED)
	end
	local showTrophies = inventoryTab == "Trophies"
	local showSets = inventoryTab == "Sets"
	filterInfo.Parent.Visible = not showTrophies and not showSets
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
		Art.progress(row.info, if earned then 1 else progress, if earned then 1 else trophy.value)
		row.info.Text = `<b>{trophy.name}</b>   <font color="#9FD49A">{table.concat(bonuses, ", ")}</font>\n`
			.. (if earned then trophy.note else `{trophy.note}   ({progress} / {trophy.value})`)
		setButton(row.button, if earned then "Earned" else "Locked", earned, COLOR_GOLD)
		row.button.TextColor3 = if earned then Color3.fromRGB(35, 28, 10) else Color3.new(1, 1, 1)
	end

	-- Sets: which pieces you own, and whether anyone wears the full set.
	local ownedNames = {}
	for _, item in state.gear do
		if item.set then
			ownedNames[item.name] = true
		end
	end
	for _, set in GameConfig.GearSets do
		local row = setRows[set.id]
		row.info.Parent.Visible = showSets
		local house = "a foe house"
		for _, candidate in GameConfig.Houses do
			if candidate.id == set.house then
				house = candidate.name
			end
		end
		local have, missing = {}, {}
		for _, slot in GameConfig.GearSlots do
			local name = set.pieces[slot]
			table.insert(if ownedNames[name] then have else missing, name)
		end
		local two = math.floor(GameConfig.SetPieceBonus[2] * 100 + 0.5)
		local three = math.floor(GameConfig.SetPieceBonus[3] * 100 + 0.5)
		row.info.Text = `<b>{set.name}</b>   <font color="#9FD49A">Full set: {perkText(set.perk)}</font>\n`
			.. `Drops from {house}. One person wearing 2 pieces: +{two}% on them, all 3: +{three}%.\n`
			.. `Owned: {if #have > 0 then table.concat(have, ", ") else "none"}`
			.. (if #missing > 0 and #have > 0 then `   <font color="#7F847E">Missing: {table.concat(missing, ", ")}</font>` else "")
		local full = state.fullSets and state.fullSets[set.id] == true
		Art.progress(row.info, #have, GameConfig.SetPieceCount)
		setButton(row.button, if full then "Worn in full" else (if #missing == 0 then "Owned" else `{#have} / {GameConfig.SetPieceCount}`), full, COLOR_GOLD)
		row.button.TextColor3 = if full then Color3.fromRGB(35, 28, 10) else Color3.new(1, 1, 1)
	end

	if showSets then
		local bonus = stats.setBonus or {}
		local active = perkText(bonus)
		armorySummary.Text = `Gear sets. Wear all {GameConfig.SetPieceCount} pieces of a set on one person to switch on its bonus for your whole realm. `
			.. `Equip set pieces by hand with the Gear button on the Warband page. Now: {if active ~= "" then active else "no full sets worn"}`
	elseif showTrophies then
		local bonus = stats.trophyBonus
		armorySummary.Text = `Trophies {earnedCount} / {#GameConfig.Trophies}. Their bonuses never go away.   Now: `
			.. `+{math.floor(bonus.attack * 100 + 0.5)}% attack, +{math.floor(bonus.defense * 100 + 0.5)}% defense, `
			.. `+{math.floor(bonus.income * 100 + 0.5)}% income, +{math.floor(bonus.xp * 100 + 0.5)}% quest XP, +{math.floor(bonus.questGold * 100 + 0.5)}% quest gold`
	else
		local wornCount = 0
		for _ in state.gearInUse do
			wornCount += 1
		end
		local pieces = 0
		for _, item in state.gear do
			pieces += item.count or 1
		end
		armorySummary.Text = `Gear: {Format.short(pieces)} pieces, {wornCount} worn. No limit: identical spares stack. Gear only counts while someone wears it. `
			.. `Use the Gear buttons on the Warband page, or Equip best there. Take gear off before selling it.`
	end
	local gear = {}
	for _, item in state.gear do
		local slotMatches = inventoryTab == "All" or item.slot == inventoryTab
		if not showTrophies and not showSets and slotMatches and GameConfig.getRarityRank(item.rarity) >= math.max(1, inventoryRarity) then
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
	for index = 1, math.max(#gear, #gearRows) do
		local item = gear[index]
		local row = if item then gearRow(index) else gearRows[index]
		row.uid = if item then item.uid else nil
		row.count = if item then (item.count or 1) else 1
		row.price = if item then item.price else 0
		row.name = if item then `{item.rarity} {item.name}` else nil
		row.info.Parent.Visible = item ~= nil
		if item then
			ItemArt.set(row.picture, item)
			local worn = item.wornBy ~= nil
			local status = if worn then `Worn by {memberLabel(state, item.wornBy)}` else "Spare"
			local counts = if worn then memberSetCounts(state, item.wornBy) else nil
			local stackText = if (item.count or 1) > 1 then `  <b>x{Format.short(item.count)}</b>` else ""
			row.info.Text = `{rarityName(item)}{stackText}  ({string.lower(item.slot)}){setTag(item, counts)}\n{statText(item.attack, item.defense)}   |   {status}`
			if worn then
				setButton(row.button, "Worn", false, COLOR_ACTION)
			elseif (item.count or 1) > 1 then
				setButton(row.button, `Sell...\n+{Format.short(item.price * GameConfig.SellShare)} each`, true, COLOR_ACTION)
			else
				setButton(row.button, `Sell\n+{Format.short(item.price * GameConfig.SellShare)}`, true, COLOR_ACTION)
			end
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
			.. (if state.firstClears[chosen.id] then "" else `\n<font color="#F0C450">First clear bonus: +{chosen.firstCrowns} Crowns, +{chosen.firstTokens} tokens</font>`)
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
		if state.stageCleared[stage.id] then
			Art.progress(row.info, 1, 1)
		else
			Art.progress(row.info, state.stageHealth[stage.id] or stage.health, stage.health, COLOR_HEALTH, true)
		end
		local chest = if stage.chest then `   {stage.chest} chest` else ""
		local first = if state.firstClears[stage.id] then "" else `   <font color="#F0C450">First clear: +{stage.firstCrowns} Crowns</font>`
		row.info.Text = `<b>Stage {stage.index}: {stage.name}</b>   Level {stage.level}\n`
			.. `{Format.short(stage.health)} health, {Format.short(stage.defense)} defense   |   {stage.tokens} tokens{chest}{first}`
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

local refreshEquipWindow -- defined further down, with the equip window

stateRemote.OnClientEvent:Connect(function(state)
	draw(state)
	refreshRecruitWindow()
	refreshEquipWindow()
end)

---------------------------------------------------------------------------
-- Recruit window: roll soldiers until one of the chosen rarity turns up
---------------------------------------------------------------------------

do
	local recruitGui = Instance.new("ScreenGui")
	recruitGui.Name = "KingdomRecruit"
	recruitGui.DisplayOrder = 5
	recruitGui.ResetOnSpawn = false
	recruitGui.Enabled = false
	recruitGui.Parent = playerGui

	local shade = makeFrame(recruitGui, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Color3.new(0, 0, 0))
	shade.BackgroundTransparency = 0.45

	local recruitWindow = makeFrame(recruitGui, UDim2.fromOffset(540, 490), UDim2.fromScale(0.5, 0.5), Color3.fromRGB(20, 25, 22))
	recruitWindow.AnchorPoint = Vector2.new(0.5, 0.5)
	addCorner(recruitWindow, 10)
	recruitWindow.BackgroundColor3 = COLOR_PANEL
	Art.panel(recruitWindow)
	local windowLimit = Instance.new("UISizeConstraint")
	windowLimit.MaxSize = Vector2.new(540, 490)
	windowLimit.Parent = recruitWindow
	local windowScale = Instance.new("UIScale")
	windowScale.Parent = recruitWindow

	local recruitTitle = makeText(recruitWindow, UDim2.new(1, -70, 0, 34), UDim2.fromOffset(16, 10), COLOR_HEADER, 24)
	recruitTitle.Font = Art.Fonts.title
	recruitTitle.TextSize = 30
	recruitTitle.Text = "Auto roll"

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

	sectionLabel("WHEN GOLD RUNS OUT", 332)
	local brokeButtons = buttonRow(2, 352, 30)
	brokeButtons[1].Text = "WAIT FOR MORE GOLD"
	brokeButtons[2].Text = "STOP AUTO ROLL"
	local chanceBox = makeFrame(recruitWindow, UDim2.new(1, -32, 0, 38), UDim2.fromOffset(16, 390), COLOR_ROW)
	addCorner(chanceBox, 6)
	local chanceText = makeText(chanceBox, UDim2.new(1, -16, 1, 0), UDim2.fromOffset(8, 0), COLOR_TEXT, 12)

	-- Cancel closes without rolling; the gold button saves and starts.
	-- Cancel closes; Start auto roll saves the settings and keeps rolling
	-- (Recruiting Sergeant pass). Single rolls are on each slot's button.
	local cancelButton = makeButton(recruitWindow, UDim2.new(0.5, -24, 0, 44), UDim2.new(0, 16, 1, -14), COLOR_ROW)
	cancelButton.AnchorPoint = Vector2.new(0, 1)
	cancelButton.TextSize = 15
	cancelButton.Text = "CANCEL"
	local startButton = makeButton(recruitWindow, UDim2.new(0.5, -24, 0, 44), UDim2.new(1, -16, 1, -14), COLOR_GOLD)
	startButton.AnchorPoint = Vector2.new(1, 1)
	startButton.TextColor3 = Color3.fromRGB(35, 28, 10)
	startButton.TextSize = 15
	startButton.Text = "START AUTO ROLL"

	local SCOPES = { "this", "empty", "below" }
	local recruitSlot = 0
	local chosenTier = 1
	local chosenRarity = 3
	local chosenScope = "this"
	local chosenBroke = "wait" -- "wait" for more gold or "stop"
	for index, mode in { "wait", "stop" } do
		brokeButtons[index].TextSize = 12
		brokeButtons[index].Activated:Connect(function()
			chosenBroke = mode
			refreshRecruitWindow()
		end)
	end

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
		windowScale.Scale = math.min(1, (viewport.X - 20) / 540, (viewport.Y - 20) / 490)

		local slotSoldier = if recruitSlot > 0 then state.crew[recruitSlot] else nil
		if recruitSlot > 0 and slotSoldier then
			local rank = if slotSoldier.train > 0 then ` +{slotSoldier.train}` else ""
			targetText.Text = `{rarityName({ rarity = slotSoldier.rarity, name = slotSoldier.class })}{rank}  {slotSoldier.name}\n<font color="#E08A7A">Slot {recruitSlot} is replaced when a roll hits. Training is lost.</font>`
		elseif recruitSlot > 0 then
			targetText.Text = `<b>Slot {recruitSlot}</b>\nThis slot is empty.`
		else
			targetText.Text = "<b>Your warband</b>\nRoll for every empty slot, or for every slot below a rarity."
		end

		local rollFactor = 1 - festivalDiscount(state, "rollCost")
		for index, tier in GameConfig.RecruitTiers do
			local b = tierButtons[index]
			local unlocked = state.level >= tier.level
			local costText = if unlocked then Format.short(math.floor(tier.cost * rollFactor)) else `Level {tier.level}`
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
		local rollCost = math.floor(tier.cost * rollFactor)
		local expected = if chance > 0 then rollCost / chance else 0
		chanceText.Text = string.format("Chance per roll: %.2f%%   |   Average cost per hit: %s gold", chance * 100, Format.short(expected))

		for index, mode in { "wait", "stop" } do
			brokeButtons[index].BackgroundColor3 = if mode == chosenBroke then COLOR_SELECTED else COLOR_ROW
		end
		local auto = state.autoRoll
		if auto.on then
			local waiting = if auto.waiting then " Waiting for gold." else ""
			local stopped = 0
			for _ in auto.skip or {} do
				stopped += 1
			end
			local stoppedText = if stopped > 0 then ` {stopped} slot{if stopped == 1 then "" else "s"} stopped by hand.` else ""
			chanceText.Text ..= `\nAuto rolling {auto.tier} for {auto.rarity}: {auto.rolls} rolls, {Format.short(auto.spent)} gold so far.{waiting}{stoppedText} Stop single slots with STOP on the Warband rows, or everything here.`
		elseif state.passes.autoroll then
			chanceText.Text ..= `\nAuto roll rolls every chosen slot at once, one roll per slot each second, until it hits, gold runs out or you stop it.`
		else
			chanceText.Text ..= "\nAuto roll needs the Recruiting Sergeant pass. Single rolls are on each slot's Recruit button."
		end
		local ready = state.level >= tier.level and gold >= rollCost and scopeCount(state, chosenScope) > 0
		if auto.on then
			startButton.Text = "STOP ALL AUTO ROLL"
			startButton.BackgroundColor3 = COLOR_ACTION
			startButton.TextColor3 = Color3.new(1, 1, 1)
		else
			startButton.Text = if state.passes.autoroll then "START AUTO ROLL" else `START AUTO ROLL\n<font size="11">pass {robuxText(StoreConfig.getPass("autoroll").price)}</font>`
			startButton.RichText = true
			startButton.BackgroundColor3 = if ready or not state.passes.autoroll then COLOR_GOLD else COLOR_DISABLED
			startButton.TextColor3 = Color3.fromRGB(35, 28, 10)
		end
	end

	function openRecruitWindow(slot: number)
		recruitSlot = slot
		if lastState then
			chosenBroke = lastState.autoRoll.whenBroke or "wait"
		end
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

	for _, button in { closeButton, cancelButton } do
		button.Activated:Connect(function()
			recruitGui.Enabled = false
		end)
	end

	local function rollId(): string
		local tier = GameConfig.RecruitTiers[chosenTier]
		local rarity = GameConfig.Rarities[chosenRarity]
		return `{math.max(recruitSlot, 1)}:{tier.id}:{rarity.id}:{chosenScope}`
	end
	startButton.Activated:Connect(function()
		if not lastState then
			return
		end
		if lastState.autoRoll.on then
			send("AutoRollStop")
		elseif not lastState.passes.autoroll then
			send("Robux", "pass:autoroll")
		else
			send("Roll", `{rollId()}:{chosenBroke}`)
		end
	end)
end

---------------------------------------------------------------------------
-- Equip window: pick what one member wears
---------------------------------------------------------------------------

do
	local equipGui = Instance.new("ScreenGui")
	equipGui.Name = "KingdomEquip"
	equipGui.DisplayOrder = 5
	equipGui.ResetOnSpawn = false
	equipGui.Enabled = false
	equipGui.Parent = playerGui

	local equipShade = makeFrame(equipGui, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Color3.new(0, 0, 0))
	equipShade.BackgroundTransparency = 0.45

	local EQUIP_WIDTH, EQUIP_HEIGHT = 580, 480
	local equipWindow = makeFrame(equipGui, UDim2.fromOffset(EQUIP_WIDTH, EQUIP_HEIGHT), UDim2.fromScale(0.5, 0.5), Color3.fromRGB(20, 25, 22))
	equipWindow.AnchorPoint = Vector2.new(0.5, 0.5)
	addCorner(equipWindow, 10)
	equipWindow.BackgroundColor3 = COLOR_PANEL
	Art.panel(equipWindow)
	local equipScale = Instance.new("UIScale")
	equipScale.Parent = equipWindow

	local equipTitle = makeText(equipWindow, UDim2.new(1, -70, 0, 34), UDim2.fromOffset(16, 10), COLOR_HEADER, 24)
	equipTitle.Font = Art.Fonts.title
	equipTitle.TextSize = 30
	equipTitle.Text = "Gear"

	local equipClose = makeButton(equipWindow, UDim2.fromOffset(36, 36), UDim2.new(1, -46, 0, 10), COLOR_ROW)
	equipClose.Text = "X"
	equipClose.TextSize = 18
	equipClose.Activated:Connect(function()
		equipGui.Enabled = false
	end)

	local equipWho = makeText(equipWindow, UDim2.new(1, -32, 0, 36), UDim2.fromOffset(16, 46), COLOR_TEXT, 13)
	equipWho.RichText = true

	-- One box per gear slot: what is worn there, and a Take off button.
	-- Clicking a box lists the pieces you own for that slot.
	local equipMember = 0 -- 0 is you, 1 and up is a warband slot
	local equipSlot = "Weapon"
	local slotBoxes = {}
	for index, gearSlot in GameConfig.GearSlots do
		local columns = #GameConfig.GearSlots
		local box = makeButton(
			equipWindow,
			UDim2.new(1 / columns, -8 - 32 / columns, 0, 74),
			UDim2.new((index - 1) / columns, 20 - 32 * (index - 1) / columns, 0, 88),
			COLOR_ROW
		)
		box.AutoButtonColor = true
		local label = makeText(box, UDim2.new(1, -12, 1, -8), UDim2.fromOffset(6, 4), COLOR_TEXT, 12)
		label.RichText = true
		label.TextYAlignment = Enum.TextYAlignment.Top
		local takeOff = makeButton(
			equipWindow,
			UDim2.new(1 / columns, -8 - 32 / columns, 0, 26),
			UDim2.new((index - 1) / columns, 20 - 32 * (index - 1) / columns, 0, 166),
			COLOR_DISABLED
		)
		takeOff.TextSize = 12
		slotBoxes[gearSlot] = { box = box, label = label, takeOff = takeOff, uid = nil }
		box.Activated:Connect(function()
			equipSlot = gearSlot
			refreshEquipWindow()
		end)
		takeOff.Activated:Connect(function()
			local uid = slotBoxes[gearSlot].uid
			if uid then
				send("Unequip", uid)
			end
		end)
	end

	local listLabel = makeText(equipWindow, UDim2.new(1, -32, 0, 18), UDim2.fromOffset(16, 200), COLOR_DIM, 12)
	listLabel.Font = Enum.Font.GothamBold

	local equipList = Instance.new("ScrollingFrame")
	equipList.Position = UDim2.fromOffset(16, 222)
	equipList.Size = UDim2.new(1, -32, 1, -234)
	equipList.BackgroundTransparency = 1
	equipList.BorderSizePixel = 0
	equipList.ScrollBarThickness = 6
	equipList.CanvasSize = UDim2.new(0, 0, 0, 0)
	equipList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	equipList.Parent = equipWindow
	local equipLayout = Instance.new("UIListLayout")
	equipLayout.Padding = UDim.new(0, 4)
	equipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	equipLayout.Parent = equipList

	local emptyNote = makeText(equipList, UDim2.new(1, -10, 0, 40), UDim2.fromOffset(0, 0), COLOR_DIM, 13)
	emptyNote.LayoutOrder = 0
	emptyNote.Text = "You own nothing for this slot yet. Buy gear in the Market or win it from quests and foes."

	local equipRows = {}
	local function equipRow(index: number)
		if equipRows[index] then
			return equipRows[index]
		end
		local row = makeFrame(equipList, UDim2.new(1, -10, 0, 46), UDim2.fromOffset(0, 0), COLOR_ROW)
		row.LayoutOrder = index
		addCorner(row, 6)
		local info = makeText(row, UDim2.new(1, -110, 1, -6), UDim2.fromOffset(8, 3), COLOR_TEXT, 12)
		info.RichText = true
		local button = makeButton(row, UDim2.fromOffset(90, 34), UDim2.new(1, -6, 0.5, 0), COLOR_DISABLED)
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.TextSize = 12
		local entry = { frame = row, info = info, button = button, uid = nil, usable = false }
		equipRows[index] = entry
		button.Activated:Connect(function()
			if entry.uid and entry.usable then
				send("Equip", `{entry.uid}:{equipMember}`)
			end
		end)
		return entry
	end

	function refreshEquipWindow()
		if not equipGui.Enabled or not lastState then
			return
		end
		local state = lastState

		local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(800, 600)
		equipScale.Scale = math.min(1, (viewport.X - 20) / EQUIP_WIDTH, (viewport.Y - 20) / EQUIP_HEIGHT)

		-- The soldier may have been released while the window was open.
		local soldier = if equipMember > 0 then state.crew[equipMember] else nil
		if equipMember > 0 and not soldier then
			equipGui.Enabled = false
			return
		end
		local wearing = if equipMember == 0 then state.yourGear else soldier.gear
		local counts = memberSetCounts(state, equipMember)

		-- Header: who, and any set bonuses they have going.
		local setParts = {}
		for setId, count in counts do
			local set = GameConfig.getGearSet(setId)
			local bonus = GameConfig.SetPieceBonus[count]
			if set and bonus then
				local full = if count >= GameConfig.SetPieceCount then `, realm {perkText(set.perk)}` else ""
				table.insert(setParts, `{set.name} {count}/{GameConfig.SetPieceCount}: +{math.floor(bonus * 100 + 0.5)}% on those pieces{full}`)
			end
		end
		local setLine = if #setParts > 0
			then `<font color="#9FD49A">{table.concat(setParts, "   ")}</font>`
			else `<font color="#7F847E">No set bonus. Wear 2 or 3 pieces of one set to get one.</font>`
		if equipMember == 0 then
			equipTitle.Text = "YOUR GEAR"
			equipWho.Text = `<b>You</b>, leader\n{setLine}`
		else
			equipTitle.Text = string.upper(`{soldier.name}'s gear`)
			equipWho.Text = `{rarityName({ rarity = soldier.rarity, name = soldier.class })}  {soldier.name}, slot {equipMember}\n{setLine}`
		end

		for _, gearSlot in GameConfig.GearSlots do
			local box = slotBoxes[gearSlot]
			local item = wearing[gearSlot]
			box.uid = if item then item.uid else nil
			box.box.BackgroundColor3 = if gearSlot == equipSlot then COLOR_SELECTED else COLOR_ROW
			if item then
				box.label.Text = `<b>{string.upper(gearSlot)}</b>\n{rarityName(item)}\n{statText(item.attack, item.defense)}{setTag(item, counts)}`
				setButton(box.takeOff, "Take off", true, COLOR_ACTION)
			else
				box.label.Text = `<b>{string.upper(gearSlot)}</b>\n<font color="#7F847E">empty</font>`
				setButton(box.takeOff, "Nothing worn", false, COLOR_ACTION)
			end
		end

		-- Every piece you own for the chosen slot, strongest first. Pieces of
		-- a set this member already wears come first among equals.
		local pieces = {}
		for _, item in state.gear do
			if item.slot == equipSlot then
				table.insert(pieces, item)
			end
		end
		table.sort(pieces, function(a, b)
			local aPower, bPower = a.attack + a.defense, b.attack + b.defense
			if aPower ~= bPower then
				return aPower > bPower
			end
			return a.uid < b.uid
		end)
		listLabel.Text = `YOUR {string.upper(equipSlot)}S ({#pieces}), STRONGEST FIRST`
		emptyNote.Visible = #pieces == 0

		for index = 1, math.max(#pieces, #equipRows) do
			local item = pieces[index]
			local row = if item then equipRow(index) else equipRows[index]
			row.uid = if item then item.uid else nil
			row.frame.Visible = item ~= nil
			if not item then
				continue
			end
			local where
			if item.wornBy == equipMember then
				where = `<font color="#9FD49A">Wearing now</font>`
			elseif item.wornBy ~= nil then
				where = `Worn by {memberLabel(state, item.wornBy)}`
			else
				where = "Spare"
			end
			local stackText = if (item.count or 1) > 1 then ` x{Format.short(item.count)}` else ""
			row.info.Text = `{rarityName(item)}{stackText} {setTag(item, nil)}\n{statText(item.attack, item.defense)}   |   {where}`
			if item.wornBy == equipMember then
				row.usable = false
				setButton(row.button, "Wearing", false, COLOR_BUY)
			elseif item.wornBy ~= nil then
				row.usable = true
				setButton(row.button, "Take and\nequip", true, COLOR_SELECTED)
			else
				row.usable = true
				setButton(row.button, "Equip", true, COLOR_BUY)
			end
		end
	end

	function openEquipWindow(member: number)
		equipMember = member
		equipGui.Enabled = true
		equipList.CanvasPosition = Vector2.new(0, 0)
		refreshEquipWindow()
	end
end

---------------------------------------------------------------------------
-- Toasts: short messages from the server
---------------------------------------------------------------------------

do
	local toastGui = Instance.new("ScreenGui")
	toastGui.Name = "KingdomToasts"
	toastGui.DisplayOrder = 10
	toastGui.ResetOnSpawn = false
	toastGui.Parent = playerGui

	-- Toasts stack in the bottom right corner, newest at the bottom, and each
	-- fades out after a few seconds.
	local TOAST_SECONDS = 4
	local MAX_TOASTS = 4
	local toastStack = makeFrame(toastGui, UDim2.fromOffset(340, 300), UDim2.new(1, -16, 1, -16), Color3.new(0, 0, 0))
	toastStack.AnchorPoint = Vector2.new(1, 1)
	toastStack.BackgroundTransparency = 1
	local toastLayout = Instance.new("UIListLayout")
	toastLayout.Padding = UDim.new(0, 6)
	toastLayout.SortOrder = Enum.SortOrder.LayoutOrder
	toastLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	toastLayout.Parent = toastStack

	local toastCount = 0
	local liveToasts = {}
	local function showToast()
		local text = player:GetAttribute("ToastText")
		if typeof(text) ~= "string" or text == "" then
			return
		end
		toastCount += 1
		local card = makeText(toastStack, UDim2.new(1, 0, 0, 0), UDim2.fromOffset(0, 0), COLOR_TEXT, 14)
		card.AutomaticSize = Enum.AutomaticSize.Y
		card.BackgroundTransparency = 0.05
		card.BackgroundColor3 = COLOR_PANEL
		card.LayoutOrder = toastCount
		card.Text = text
		addCorner(card, 8)
		Art.card(card)
		local stroke = addStroke(card)
		stroke.Color = COLOR_GOLD
		local icon = Art.icon(card, Art.toastIcon(text), 24, UDim2.new(0, -32, 0.5, 0))
		icon.AnchorPoint = Vector2.new(0, 0.5)
		card.BackgroundTransparency = 1
		card.TextTransparency = 1
		Art.tween(card, 0.25, { BackgroundTransparency = 0.05, TextTransparency = 0 })
		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0, 8)
		padding.PaddingBottom = UDim.new(0, 8)
		padding.PaddingLeft = UDim.new(0, 42)
		padding.PaddingRight = UDim.new(0, 10)
		padding.Parent = card

		table.insert(liveToasts, card)
		while #liveToasts > MAX_TOASTS do
			table.remove(liveToasts, 1):Destroy()
		end
		task.delay(TOAST_SECONDS, function()
			if not table.find(liveToasts, card) then
				return
			end
			Art.tween(card, 0.3, { BackgroundTransparency = 1, TextTransparency = 1 })
			Art.tween(icon, 0.3, { TextTransparency = 1 })
			Art.tween(stroke, 0.3, { Transparency = 1 })
			task.wait(0.3)
			local index = table.find(liveToasts, card)
			if index then
				table.remove(liveToasts, index)
				card:Destroy()
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
		window.BackgroundColor3 = COLOR_PANEL
		Art.panel(window)
		local coins = Art.icon(window, Art.Icons.gold, 40, UDim2.new(0.5, 0, 0, -10))
		coins.AnchorPoint = Vector2.new(0.5, 0.5)
		coins.ZIndex = 12

		local title = makeText(window, UDim2.new(1, -30, 0, 34), UDim2.fromOffset(15, 14), COLOR_HEADER, 20)
		title.Font = Art.Fonts.title
		title.TextSize = 28
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
		button.TextColor3 = Color3.fromRGB(40, 28, 12)
		button.TextSize = 16
		button.ZIndex = 11
		Art.shine(button, 2)
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
end

do
	local Fx = require(script.Parent:WaitForChild("Fx"))
	Fx.init(Art, GameConfig, Format.short, remotes:WaitForChild("Fx"), ItemArt, send)
	Fx.setAnchor("foe", foeFightBar.fill.Parent)
	Fx.setAnchor("you", yourFightBar.fill.Parent)
end

print(`[{GameConfig.GameName}] client started`)
