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
-- "+N POINTS" next to the XP bar while you have unspent skill points;
-- it opens the Skills popup. The XP bar is shorter while it shows.
local pointsButton = makeButton(topBar, UDim2.fromOffset(84, 20), UDim2.fromOffset(186, 38), COLOR_GOLD)
pointsButton.TextSize = 11
pointsButton.Font = Enum.Font.GothamBlack
pointsButton.Visible = false
pointsButton.Activated:Connect(function()
	if ui and ui.openSkills then
		ui.openSkills()
	else
		openModal("Skills")
	end
end)

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
		Art.setIcon(icon, key)
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
	local iconRow = makeFrame(topBar, UDim2.new(0, ICON_BLOCK - 10, 1, -12), UDim2.new(1, -(ICON_BLOCK - 4), 0, 6), COLOR_PANEL)
	iconRow.BackgroundTransparency = 1
	local iconLayout = Instance.new("UIListLayout")
	iconLayout.FillDirection = Enum.FillDirection.Horizontal
	iconLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	iconLayout.Padding = UDim.new(0, 6)
	iconLayout.SortOrder = Enum.SortOrder.LayoutOrder
	iconLayout.Parent = iconRow
	-- One MENU button: a drop-down with Mail, Settings, Stats, Rankings
	-- and Updates. The Mail count shows on it.
	for index, entry in { { "Mail", "", "Menu" } } do
		local button = makeButton(iconRow, UDim2.new(0, 56, 1, 0), UDim2.fromOffset(0, 0), COLOR_ROW)
		button.LayoutOrder = index
		button.Text = ""
		addStroke(button).Color = COLOR_GOLD
		-- Three drawn gold bars (the font has no hamburger glyph).
		for line = 0, 2 do
			local strip = makeFrame(button, UDim2.fromOffset(28, 4), UDim2.new(0.5, -14, 0, 9 + line * 8), COLOR_GOLD)
			addCorner(strip, 2)
		end
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

		local menu = makeFrame(gui, UDim2.fromOffset(300, 0), UDim2.new(1, -10, 0, TOP_HEIGHT + 6), COLOR_PANEL)
		menu.AnchorPoint = Vector2.new(1, 0)
		menu.AutomaticSize = Enum.AutomaticSize.Y
		menu.Visible = false
		menu.ZIndex = 800
		addCorner(menu, 8)
		Art.stroke(menu, COLOR_GOLD, 2, 0)
		local menuList = Instance.new("UIListLayout")
		menuList.Padding = UDim.new(0, 6)
		menuList.SortOrder = Enum.SortOrder.LayoutOrder
		menuList.Parent = menu
		local menuPad = Instance.new("UIPadding")
		for _, side in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do
			menuPad[side] = UDim.new(0, 8)
		end
		menuPad.Parent = menu
		local mailCount = nil
		local items = {
			{ Art.Icons.Mail, "MAIL", function() openModal("Mail") end },
			{ "\u{2699}\u{FE0F}", "SETTINGS", function() openModal("Settings") end },
			{ Art.Icons.Rankings, "STATS", function() openModal("Stats") end },
			{ "\u{1F3C5}", "RANKINGS", function() if ui then ui.showPage("Rankings") end end },
			{ "\u{1F4F0}", "UPDATES", function() openModal("Updates") end },
		}
		for order, item in items do
			local row = makeButton(menu, UDim2.new(1, 0, 0, 58), UDim2.fromOffset(0, 0), COLOR_ROW)
			row.LayoutOrder = order
			row.Text = ""
			row.ZIndex = 801
			local glyph = makeText(row, UDim2.fromOffset(60, 58), UDim2.fromOffset(14, 0), COLOR_GOLD, 30)
			glyph.TextXAlignment = Enum.TextXAlignment.Center
			glyph.Text = item[1]
			glyph.ZIndex = 802
			local label = makeText(row, UDim2.new(1, -90, 1, 0), UDim2.fromOffset(86, 0), COLOR_HEADER, 24)
			label.Font = Enum.Font.GothamBlack
			label.Text = item[2]
			label.ZIndex = 802
			if order == 1 then
				mailCount = makeText(row, UDim2.fromOffset(34, 24), UDim2.new(1, -44, 0.5, -12), Color3.new(1, 1, 1), 13)
				mailCount.BackgroundTransparency = 0
				mailCount.BackgroundColor3 = COLOR_ACTION
				mailCount.Font = Enum.Font.GothamBlack
				mailCount.TextXAlignment = Enum.TextXAlignment.Center
				mailCount.ZIndex = 803
				addCorner(mailCount, 12)
			end
			row.Activated:Connect(function()
				menu.Visible = false
				item[3]()
			end)
		end
		button.Activated:Connect(function()
			menu.Visible = not menu.Visible
			if mailCount then
				mailCount.Visible = badge.Visible
				mailCount.Text = badge.Text
			end
			if menu.Visible then
				local scale = menu:FindFirstChild("Pop") or Instance.new("UIScale")
				scale.Name = "Pop"
				scale.Parent = menu
				scale.Scale = 0.85
				Art.tween(scale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
			end
		end)
		-- Pressing anywhere else closes it (a clear layer behind the menu).
		local catcher = makeButton(gui, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
		catcher.BackgroundTransparency = 1
		catcher.Text = ""
		catcher.AutoButtonColor = false
		catcher:SetAttribute("NoGlow", true)
		catcher.ZIndex = 790
		catcher.Visible = false
		catcher.Activated:Connect(function()
			menu.Visible = false
		end)
		menu:GetPropertyChangedSignal("Visible"):Connect(function()
			catcher.Visible = menu.Visible
		end)
	end
end

-- Energy, stamina and health, each with a + that opens the Shop's refills.
local barBlock = makeFrame(topBar, UDim2.new(0, RIGHT_BLOCK - 10, 1, 0), UDim2.new(1, -(RIGHT_BLOCK + ICON_BLOCK - 4), 0, 0), COLOR_PANEL)
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
	{ name = "Arena", pages = { "Raids", "Realm Map", "Guild", "Rankings", "War Chronicle" } },
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
		tip = "Scores are sent while you play and the boards refresh every couple of minutes.",
	},
	Raids = {
		about = "Raid other players' keeps for their gold on hand and resources.",
		tip = "Your attack roll against their defense roll. Gold in the Bank is always safe, and the Hidden Cellar protects resources. A raided keep gets a 30 minute shield.",
	},
	["Realm Map"] = {
		about = "Guilds siege the realm's territories every week.",
		tip = "Each siege costs 1 stamina and adds points for your guild. The guild with the most points on a territory holds it next week, and its members get that territory's bonus.",
	},
	Guild = {
		about = "Found or join a guild. Donations level it up for bonuses.",
		tip = "Every guild level gives all members more income, attack and defense, and room for more members. Guilds also fight over the realm map.",
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
		tip = "Each holding uses one lot. Build more copies on the BUILD tab; press one of your lands to build another or demolish it.",
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
		tip = "Repeat a quest to earn bronze, silver and gold mastery medals; each one raises its gold. AUTO QUESTS works on one quest, mastery, most XP or most gold for you.",
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
	Art.setIcon(headerArt.glyph, name)
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
			Art.setIcon(icon, name)
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

-- Three LayoutOrder slots for the playtime rewards (PlaytimeRewards.luau).
local playtimeOrder = nextOrder()
nextOrder()
nextOrder()

-- Quests: the page is built in QuestsPage.luau.

-- Holdings: the page is built in HoldingsPage.luau.

-- Bank: the page is built in BankPage.luau.

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

-- Market: the page is built in MarketPage.luau.

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
warbandSummary.Parent.Visible = false -- replaced by the chips below

-- Warband header: four stat chips, then a bar of buttons.
local warbandChips = {}
local warbandButtons = {}
do
	local chips = makeFrame(pages.Warband, UDim2.new(1, -10, 0, 50), UDim2.fromOffset(0, 0), COLOR_PANEL)
	chips.BackgroundTransparency = 1
	chips.LayoutOrder = nextOrder()
	local glyphs = { "\u{1F465}", Art.Icons.Weapon, Art.Icons.Armor, "\u{2B50}" }
	for index = 1, 4 do
		local chip = makeFrame(chips, UDim2.new(0.25, -6, 1, 0), UDim2.new((index - 1) * 0.25, 3, 0, 0), COLOR_ROW)
		addCorner(chip, 6)
		Art.card(chip)
		local icon = Art.icon(chip, glyphs[index] or "", 26, UDim2.fromOffset(10, 12))
		icon.ZIndex = chip.ZIndex + 1
		local label = makeText(chip, UDim2.new(1, -48, 1, 0), UDim2.fromOffset(44, 0), COLOR_TEXT, 14)
		label.Font = Enum.Font.GothamBold
		label.TextWrapped = true
		warbandChips[index] = label
	end
	local bar = makeFrame(pages.Warband, UDim2.new(1, -10, 0, 46), UDim2.fromOffset(0, 0), COLOR_PANEL)
	bar.BackgroundTransparency = 1
	bar.LayoutOrder = nextOrder()
	local names = { "GEAR SETS", "UNEQUIP ALL", "AUTO SORT", "EQUIP BEST", "NEW GEAR", "AUTO ROLL" }
	for index, name in names do
		local count = #names
		local button = makeButton(bar, UDim2.new(1 / count, -6, 1, 0), UDim2.new((index - 1) / count, 3, 0, 0), COLOR_PANEL)
		button.TextSize = 13
		button.TextColor3 = COLOR_GOLD
		Art.stroke(button, COLOR_GOLD, 1.5, 0.2)
		button.Text = name
		warbandButtons[index] = button
	end
	warbandButtons[2].Activated:Connect(function()
		send("UnequipAll")
	end)
	warbandButtons[3].Activated:Connect(function()
		send("SortCrew")
	end)
	warbandButtons[4].Activated:Connect(function()
		send("EquipBest")
	end)
	warbandButtons[6].Activated:Connect(function()
		if ownsAutoRoll then
			openRecruitWindow(0)
		else
			ui.offerPass("autoroll")
		end
	end)
end

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
warbandButtons[5].Activated:Connect(function()
	send("EquipNew", if equipNewOn then "off" else "on")
end)
equipButtons[1].Parent.Visible = false -- moved into the header bar

-- A warband card (like a crew card): order arrows, a portrait, name and
-- rarity, total attack and defense, Train / Auto / Release, and a tile for
-- each gear slot (press a tile to change that gear).
local CLASS_GLYPHS = {
	Militia = "\u{1F6E1}\u{FE0F}",
	Archer = "\u{1F3F9}",
	Knight = "\u{2694}\u{FE0F}",
	["Battle Mage"] = "\u{1F52E}",
	Ranger = "\u{1F332}",
}
local function makeCrewRow(order: number)
	local row = makeFrame(pages.Warband, UDim2.new(1, -10, 0, 160), UDim2.fromOffset(0, 0), COLOR_ROW)
	row.LayoutOrder = order
	addCorner(row, 8)
	Art.card(row)
	local edge = Art.stroke(row, COLOR_DIM, 1.5, 0.3)

	local up = makeButton(row, UDim2.fromOffset(30, 28), UDim2.fromOffset(6, 8), COLOR_SELECTED)
	up.Text = "\u{25B2}"
	up.TextSize = 12
	local down = makeButton(row, UDim2.fromOffset(30, 28), UDim2.fromOffset(6, 42), COLOR_SELECTED)
	down.Text = "\u{25BC}"
	down.TextSize = 12

	local portrait = makeFrame(row, UDim2.fromOffset(64, 64), UDim2.fromOffset(42, 6), Color3.fromRGB(26, 20, 16))
	addCorner(portrait, 8)
	local portraitStroke = Art.stroke(portrait, COLOR_DIM, 2, 0)
	local glyph = Art.icon(portrait, "", 38, UDim2.fromScale(0.5, 0.5))
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.ZIndex = portrait.ZIndex + 1

	local info = makeText(row, UDim2.new(0.42, -118, 0, 66), UDim2.fromOffset(114, 5), COLOR_TEXT, 14)
	info.RichText = true
	info.TextYAlignment = Enum.TextYAlignment.Top
	local statsText = makeText(row, UDim2.new(0.58, -250, 0, 66), UDim2.new(0.42, 0, 0, 5), COLOR_TEXT, 15)
	statsText.RichText = true
	statsText.Font = Enum.Font.GothamBold

	local function button(width: number, offset: number): TextButton
		local b = makeButton(row, UDim2.fromOffset(width, 60), UDim2.new(1, offset, 0, 8), COLOR_DISABLED)
		b.AnchorPoint = Vector2.new(1, 0)
		b.TextSize = 13
		return b
	end
	local release = button(50, -6)
	local roll = button(64, -60)
	roll.RichText = true
	local train = button(118, -128)

	-- Gear tiles.
	local tiles = {}
	for index, gearSlot in GameConfig.GearSlots do
		local tile = makeButton(row, UDim2.new(1 / 3, -8, 0, 78), UDim2.new((index - 1) / 3, 6 - (index - 1) * 2, 0, 76), Color3.fromRGB(26, 30, 30))
		tile.Text = ""
		tile.AutoButtonColor = true
		local tileStroke = Art.stroke(tile, COLOR_DIM, 1.5, 0.3)
		local picture = makeFrame(tile, UDim2.fromOffset(56, 56), UDim2.fromOffset(8, 11), Color3.fromRGB(14, 12, 10))
		picture.BackgroundTransparency = 0.3
		addCorner(picture, 6)
		local name = makeText(tile, UDim2.new(1, -76, 0, 22), UDim2.fromOffset(70, 6), COLOR_TEXT, 15)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.TextWrapped = false
		local rarityLabel = makeText(tile, UDim2.new(1, -76, 0, 16), UDim2.fromOffset(70, 28), COLOR_DIM, 11)
		rarityLabel.Font = Enum.Font.GothamBold
		rarityLabel.RichText = true
		rarityLabel.TextWrapped = false
		local tileStats = makeText(tile, UDim2.new(1, -76, 0, 22), UDim2.fromOffset(70, 48), COLOR_TEXT, 14)
		tileStats.RichText = true
		tileStats.Font = Enum.Font.GothamBold
		tiles[gearSlot] = { button = tile, stroke = tileStroke, picture = picture, name = name, rarity = rarityLabel, stats = tileStats }
	end
	-- gear is kept as a hidden button so older code paths still work.
	local gear = makeButton(row, UDim2.fromOffset(1, 1), UDim2.fromOffset(0, 0), COLOR_DISABLED)
	gear.Visible = false

	return {
		frame = row,
		edge = edge,
		up = up,
		down = down,
		portrait = portraitStroke,
		glyph = glyph,
		info = info,
		statsText = statsText,
		gearText = statsText,
		train = train,
		roll = roll,
		release = release,
		gear = gear,
		tiles = tiles,
	}
end

local youRow = makeCrewRow(nextOrder())
youRow.train.Visible = false
youRow.roll.Visible = false
youRow.release.Visible = false
youRow.up.Visible = false
youRow.down.Visible = false
youRow.glyph.Text = "\u{1F451}"
for _, tile in youRow.tiles do
	tile.button.Activated:Connect(function()
		openEquipWindow(0)
	end)
end

local crewRows = {}
for slot = 1, GameConfig.MaxSoldierSlots do
	local row = makeCrewRow(nextOrder())
	crewRows[slot] = row
	-- On an empty slot this button is RECRUIT: one roll for the slot.
	row.train.Activated:Connect(function()
		if row.empty then
			if row.rollId then
				send("Roll", row.rollId)
			end
		elseif ui and ui.offerTrain then
			ui.offerTrain(slot)
		end
	end)
	-- Auto: opens the auto roll window for this slot. Without the pass it
	-- shows as disabled and opens the pass popup instead.
	row.roll.Activated:Connect(function()
		if ownsAutoRoll then
			openRecruitWindow(slot)
		elseif ui and ui.offerPass then
			ui.offerPass("autoroll")
		end
	end)
	row.up.Activated:Connect(function()
		send("MoveSoldier", `{slot}:up`)
	end)
	row.down.Activated:Connect(function()
		send("MoveSoldier", `{slot}:down`)
	end)
	for _, tile in row.tiles do
		tile.button.Activated:Connect(function()
			openEquipWindow(slot)
		end)
	end
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

local redraw -- draws the last state again; defined after draw()
-- Warband header: GEAR SETS opens the Inventory on its Sets tab.
warbandButtons[1].Activated:Connect(function()
	if ui and ui.openInventory then
		ui.openInventory("Sets")
	end
end)

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
		{ key = "Profile", title = "Profile", width = 900, height = 560 },
		{ key = "Settings", title = "Settings", width = 620, height = 560 },
		{ key = "Stats", title = "Stats", width = 720, height = 560 },
		{ key = "Updates", title = "Updates", width = 640, height = 560 },
		{ key = "Item", title = "Item", width = 560, height = 520 },
		{ key = "Rebirth", title = "Rebirth" },
		{ key = "Mail", title = "Mail" },
		{ key = "AutoQuest", title = "Auto quests", width = 760, height = 560 },
		{ key = "AutoBuy", title = "Auto-buy", width = 600, height = 560 },
		{ key = "Amount", title = "How many?", width = 440, height = 330 },
		{ key = "Skills", title = "Skill points", width = 640, height = 590 },
		{ key = "Pass", title = "Game pass", width = 520, height = 300 },
		{ key = "ChestOdds", title = "Chest odds", width = 560, height = 580 },
		{ key = "Train", title = "Train soldier", width = 520, height = 470 },
		{ key = "Holding", title = "Holding", width = 520, height = 470 },
		{ key = "IncomeBonus", title = "Income bonus", width = 460, height = 420 },
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
				Art.setIcon(titleIcon, if Art.Icons[key] then key else "scroll")
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
	classGlyphs = CLASS_GLYPHS,
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
	playtimeOrder = playtimeOrder,
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
for _, name in { "AmountPopup", "ProfilePage", "RebirthPage", "RankingsPage", "MailPage", "RelicPage", "BarracksPage", "ExpeditionsPage", "ChroniclePage", "AutoPopups", "EstatePage", "KeepPage", "PassPopup", "ChestShelf", "RollReel", "TrainPopup", "HoldingsPage", "QuestsPage", "FoesPage", "RoyalPassPage", "InventoryPage", "MenuPopups", "BankPage", "MarketPage", "ShopPage", "BountiesPage", "FestivalPage", "ResearchPage", "PlaytimeRewards", "RaidsPage", "GuildPage", "RealmPage" } do
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

-- Shop: the page is built in ShopPage.luau.

local function draw(state)
	lastState = state
	local stats = state.stats
	local gold = state.gold
	for _, module in pageModules do
		module.draw(state, ui)
	end

	-- Top bar
	local title = if state.title ~= "" then state.title .. " " else ""
	levelBadge.Text = tostring(state.level)
	nameLabel.Text = `{title}{player.DisplayName}`
	nameLabel.TextColor3 = if state.passes.charter then COLOR_GOLD else COLOR_HEADER
	setBar(xpBar, state.xp, state.xpNeeded, `XP {state.xp} / {state.xpNeeded}`)
	local unspent = state.skillPoints or 0
	pointsButton.Visible = unspent > 0
	setButton(pointsButton, `+{Format.short(unspent)} POINTS`, true, COLOR_GOLD)
	xpBar.fill.Parent.Size = UDim2.fromOffset(if unspent > 0 then 112 else 190, 16)
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

	-- Header chips and bar.
	local filled = 0
	for _, soldier in crew do
		if soldier then
			filled += 1
		end
	end
	warbandChips[1].Text = `{filled} OF {#crew} SOLDIERS`
	warbandChips[2].Text = `+{Format.short(stats.attack)} ATTACK`
	warbandChips[3].Text = `+{Format.short(stats.defense)} DEFENSE`
	warbandChips[4].Text = `SIZE BONUS +{math.floor(stats.crewBonus * 100 + 0.5)}%`
	warbandButtons[5].Text = if equipNewOn then "NEW GEAR: WEAR" else "NEW GEAR: SPARE"
	warbandButtons[6].Text = if not ownsAutoRoll then "\u{1F512} AUTO ROLL" elseif autoRoll.on then "AUTO ROLL: ON" else "AUTO ROLL"

	-- A card's gear tiles, and its total attack and defense with gear.
	local function drawTiles(row, wearing, counts): (number, number)
		local attack, defense = 0, 0
		for gearSlot, tile in row.tiles do
			local item = wearing and wearing[gearSlot]
			if item then
				local rarity = GameConfig.getRarity(item.rarity)
				ItemArt.set(tile.picture, item)
				tile.name.Text = item.name
				tile.name.TextColor3 = rarity.color
				tile.rarity.Text = string.upper(item.rarity) .. setTag(item, counts)
				tile.rarity.TextColor3 = rarity.color
				tile.stats.Text = `<font color="#F08A6A">+{item.attack}</font>   <font color="#7FB4F0">+{item.defense}</font>`
				tile.stroke.Color = rarity.color
				attack += item.attack
				defense += item.defense
			else
				local drawn = tile.picture:FindFirstChild("ItemArt")
				if drawn then
					drawn:Destroy()
				end
				tile.picture:SetAttribute("ItemArtKey", nil)
				tile.name.Text = `No {string.lower(gearSlot)}`
				tile.name.TextColor3 = COLOR_DIM
				tile.rarity.Text = "TAP TO EQUIP"
				tile.rarity.TextColor3 = COLOR_DIM
				tile.stats.Text = ""
				tile.stroke.Color = COLOR_DIM
			end
		end
		return attack, defense
	end
	local function statsLines(attack: number, defense: number): string
		return `<font color="#F08A6A">+{Format.short(attack)} ATTACK</font>\n<font color="#7FB4F0">+{Format.short(defense)} DEFENSE</font>`
	end

	local youCounts = memberSetCounts(state, 0)
	local youGearAttack, youGearDefense = drawTiles(youRow, state.yourGear, youCounts)
	youRow.info.Text = `<font size="20" color="#F0C450"><b>YOU</b></font>\n<font color="#B2A690">Warband leader</font>`
	youRow.statsText.Text = statsLines(GameConfig.BaseAttack + (state.skills.attack or 0) + youGearAttack, GameConfig.BaseDefense + (state.skills.defense or 0) + youGearDefense)
	youRow.edge.Color = COLOR_GOLD
	setButton(youRow.gear, "Gear", true, COLOR_SELECTED)

	for slot, row in crewRows do
		local soldier = crew[slot]
		row.frame.Visible = soldier ~= nil
		if soldier == nil then
			continue
		end
		row.up.Visible = slot > 1
		row.down.Visible = crew[slot + 1] ~= nil
		local tier = oneRollTier(state)
		if soldier then
			local rarity = GameConfig.getRarity(soldier.rarity)
			local rank = if soldier.train > 0 then ` +{soldier.train}` else ""
			local color = string.format("#%02X%02X%02X", math.floor(rarity.color.R * 255 + 0.5), math.floor(rarity.color.G * 255 + 0.5), math.floor(rarity.color.B * 255 + 0.5))
			row.info.Text = `<font color="{color}" size="17"><b>{soldier.name}{rank}</b></font>\n`
				.. `<font color="{color}"><b>{string.upper(soldier.rarity)}</b></font> {soldier.class}\n<font color="#B2A690">{soldier.tier} recruit</font>`
			row.glyph.Text = CLASS_GLYPHS[soldier.class] or Art.Icons.soldier
			row.portrait.Color = rarity.color
			row.edge.Color = rarity.color
			local counts = memberSetCounts(state, slot)
			local gearAttack, gearDefense = drawTiles(row, soldier.gear, counts)
			row.statsText.Text = statsLines(soldier.attack + gearAttack, soldier.defense + gearDefense)
			for _, tile in row.tiles do
				tile.button.Visible = true
			end
			row.train.Visible = true
			if soldier.trainLeft then
				setButton(row.train, `TRAINING\n{formatClock(soldier.trainLeft)}`, true, COLOR_SELECTED)
			elseif soldier.train >= GameConfig.MaxTrainRank then
				setButton(row.train, "FULLY\nTRAINED", false, COLOR_BUY)
			else
				setButton(row.train, `TRAIN\n+{soldier.train} to +{soldier.train + 1}`, true, COLOR_BUY)
			end
			-- Without the pass the button makes one reroll (only a soldier
			-- at least as rare replaces this one).
			if GameConfig.getChanceAtLeast(tier, soldier.rarity) <= 0 then
				row.rollId = nil
			else
				row.rollId = `{slot}:{tier.id}:{soldier.rarity}:this:once`
			end
			row.empty = false
			setButton(row.roll, "AUTO", ownsAutoRoll, COLOR_ACTION)
			row.release.Visible = true
			setButton(row.release, "\u{1F5D1}\u{FE0F}", true, Color3.fromRGB(120, 40, 36))
		else
			row.info.Text = `<font size="17"><b>Empty slot {slot}</b></font>\nRecruit someone to fill it.`
			row.statsText.Text = ""
			row.glyph.Text = "?"
			row.portrait.Color = COLOR_DIM
			row.edge.Color = COLOR_DIM
			for _, tile in row.tiles do
				tile.button.Visible = false
			end
			row.release.Visible = false
			row.rollId = `{slot}:{tier.id}:Common:this:once`
			row.empty = true
			-- RECRUIT makes one roll; AUTO opens the auto roll window.
			row.train.Visible = true
			setButton(row.train, `RECRUIT\n{Format.short(oneRollCost(state, tier))}`, gold >= oneRollCost(state, tier), COLOR_BUY)
			setButton(row.roll, "AUTO", ownsAutoRoll, COLOR_ACTION)
		end
		-- Empty slots are short cards (no gear tiles).
		row.frame.Size = UDim2.new(1, -10, 0, if soldier then 160 else 76)
		-- While a roll is showing on this slot, the card shows the rolled soldier.
		if ui.showRoll then
			ui.showRoll(slot)
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
		if lastState and lastState.settings and lastState.settings.toasts == false then
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
end

print(`[{GameConfig.GameName}] client started`)
