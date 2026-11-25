-- Foes page, two tabs (like Idle Mafia's Bosses):
--   STAGES      a big fight panel for the chosen stage (you on the left,
--               VS in the middle, the foe on the right, ATTACK below),
--               a DAILY CLEAR / FIRST CLEAR reward strip, and a sidebar
--               listing every stage by house with its status.
--   TOKEN SHOP  supplies (refills, boosts, chests) and each house's gear
--               set sold piece by piece for boss tokens.
-- The tokens count sits at the right of the tab bar.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Format = require(Shared:WaitForChild("Format"))

local FoesPage = {}

local HOUSE_COLORS = {
	thornwood = Color3.fromRGB(70, 120, 60),
	reavers = Color3.fromRGB(70, 100, 140),
	ember = Color3.fromRGB(170, 70, 40),
	barony = Color3.fromRGB(110, 110, 120),
	hollow = Color3.fromRGB(110, 60, 140),
}
-- One picture per foe, in stage order.
local FOE_GLYPHS = {
	"\u{1F9D4}", -- Garrick: bearded man
	"\u{1F9D9}", -- Mad Hilda: mage
	"\u{1F3F9}", -- Wat Longshanks: bow
	"\u{1F9B9}", -- Baron Vex: villain
	"\u{1F5E1}\u{FE0F}", -- Orla Saltblade: dagger
	"\u{1F525}", -- Brother Cael: fire
	"\u{1F479}", -- Grimsby Ironjaw: ogre
	"\u{1F6E1}\u{FE0F}", -- Sir Aldous: shield
	"\u{1F56F}\u{FE0F}", -- Ash Acolyte Mira: candle
	"\u{1F465}", -- The Smoke Twins: two figures
	"\u{2696}\u{FE0F}", -- Pyre-Judge Holt: scales
	"\u{1F441}\u{FE0F}", -- The Ember Prophet: eye
	"\u{1F4B0}", -- Reeve Dunstan: money bag
	"\u{1F575}\u{FE0F}", -- Lady Corva: spy
	"\u{2694}\u{FE0F}", -- Marshal Brannoc: swords
	"\u{1F528}", -- The Iron Baron: hammer
	"\u{1F4EF}", -- The Pale Herald: horn
	"\u{1F940}", -- Dame Sorrow: wilted rose
	"\u{1F480}", -- The Gravewarden: skull
	"\u{1F451}", -- The Hollow King: crown
}
local SWORDS = "\u{2694}\u{FE0F}"
local LOCK = "\u{1F512}"
local CHECK = "\u{2714}"
local HEART = "\u{2764}\u{FE0F}"
local DAGGER = "\u{1F5E1}\u{FE0F}"
local SUPPLY_GLYPHS = {
	health = HEART,
	energy = "\u{26A1}",
	stamina = "\u{1F4EF}",
	xpBoost = "\u{1F56F}\u{FE0F}",
	skill = "\u{1F4D8}",
}
local GREEN = Color3.fromRGB(110, 210, 110)
local RED = Color3.fromRGB(190, 60, 55)
local BLUE = Color3.fromRGB(70, 130, 190)

local tab = "stages"
local selected = nil -- stage id the fight panel shows (nil: pick one)
local latest = nil
local resetAt = 0 -- os.clock() when the daily reset happens
local w = {}
local stageRows = {} -- [stage id] = widgets
local supplyCards = {} -- [item id] = widgets
local setCards = {} -- [shop id] = widgets
local setHeads = {} -- [set id] = widgets

local function commas(value: number): string
	local text = tostring(math.floor(value))
	local result = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (result:gsub("^,", ""))
end

local function houseOf(id: string)
	for _, house in GameConfig.Houses do
		if house.id == id then
			return house
		end
	end
	return nil
end

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

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d:%02d", seconds // 3600, seconds % 3600 // 60, seconds % 60)
end

-- Reached: the stage before it has been beaten at least once.
local function reached(state, stage): boolean
	return stage.index <= state.highestStage + 1
end

local function open(state, stage): boolean
	return state.level >= stage.level and reached(state, stage)
end

-- A small gold coin drawn in code (the boss token).
local function coin(ui, parent: Instance, size: number, position: UDim2): Frame
	local disc = ui.makeFrame(parent, UDim2.fromOffset(size, size), position, ui.colors.gold)
	ui.addCorner(disc, size)
	ui.art.gloss(disc, 1, 0.55)
	ui.art.stroke(disc, Color3.fromRGB(120, 80, 20), 1.5, 0)
	local inner = ui.makeFrame(disc, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.25, 0.25), Color3.fromRGB(200, 140, 40))
	ui.addCorner(inner, size)
	return disc
end

local function bar(ui, parent: Instance, position: UDim2, color: Color3)
	local back = ui.makeFrame(parent, UDim2.new(1, -24, 0, 24), position, Color3.fromRGB(16, 14, 12))
	ui.addCorner(back, 5)
	ui.art.stroke(back, Color3.new(0, 0, 0), 1, 0.3)
	local fill = ui.makeFrame(back, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), color)
	ui.addCorner(fill, 5)
	ui.art.gloss(fill, 1, 0.7)
	local label = ui.makeText(back, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1), 14)
	label.Font = Enum.Font.GothamBold
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextStrokeTransparency = 0.4
	label.ZIndex = fill.ZIndex + 1
	return { back = back, fill = fill, label = label }
end

local function setBar(part, value: number, maximum: number, text: string)
	local share = if maximum > 0 then math.clamp(value / maximum, 0, 1) else 0
	part.fill.Size = UDim2.fromScale(share, 1)
	part.fill.Visible = share > 0
	part.label.Text = text
end

local function centered(ui, parent: Instance, y: number, height: number, size: number, color: Color3): TextLabel
	local label = ui.makeText(parent, UDim2.new(1, -16, 0, height), UDim2.fromOffset(8, y), color, size)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextTruncate = Enum.TextTruncate.AtEnd
	return label
end

---------------------------------------------------------------------------
-- Building: tab bar
---------------------------------------------------------------------------

local function buildTabs(ui, page: Instance)
	local colors = ui.colors
	local bar = ui.makeFrame(page, UDim2.new(1, -10, 0, 56), UDim2.fromOffset(0, 0), Color3.fromRGB(44, 36, 22))
	bar.LayoutOrder = 1
	ui.addCorner(bar, 6)
	ui.art.stroke(bar, colors.gold, 1.5, 0.4)
	w.tabs = {}
	for index, info in { { "stages", "STAGES" }, { "shop", "TOKEN SHOP" } } do
		local button = ui.makeButton(bar, UDim2.fromOffset(180, 46), UDim2.fromOffset(10 + (index - 1) * 190, 5), Color3.new(0, 0, 0))
		button.BackgroundTransparency = 1
		button.TextSize = 20
		button.Font = Enum.Font.GothamBlack
		button.Text = info[2]
		button:SetAttribute("NoGlow", true)
		local line = ui.makeFrame(button, UDim2.new(1, -20, 0, 3), UDim2.new(0, 10, 1, -3), colors.gold)
		w.tabs[info[1]] = { button = button, line = line }
		button.Activated:Connect(function()
			tab = info[1]
			FoesPage.draw(latest, ui)
		end)
	end
	w.tokens = ui.makeText(bar, UDim2.fromOffset(300, 56), UDim2.new(1, -350, 0, 0), colors.gold, 22)
	w.tokens.Font = Enum.Font.GothamBlack
	w.tokens.TextXAlignment = Enum.TextXAlignment.Right
	coin(ui, bar, 30, UDim2.new(1, -42, 0.5, -15))
end

---------------------------------------------------------------------------
-- Building: STAGES tab
---------------------------------------------------------------------------

local function buildFighter(ui, parent: Instance, x: number): any
	local colors = ui.colors
	local card = ui.makeFrame(parent, UDim2.new(0.34, 0, 0, 286), UDim2.new(x, 0, 0, 66), Color3.fromRGB(18, 15, 12))
	card.BackgroundTransparency = 0.15
	ui.addCorner(card, 8)
	local stroke = ui.art.stroke(card, colors.gold, 2, 0.3)
	local portrait = ui.makeFrame(card, UDim2.fromOffset(96, 96), UDim2.new(0.5, -48, 0, 12), Color3.fromRGB(40, 34, 28))
	ui.addCorner(portrait, 10)
	local ring = ui.art.stroke(portrait, colors.gold, 2, 0)
	local glyph = ui.makeText(portrait, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1), 60)
	glyph.TextXAlignment = Enum.TextXAlignment.Center
	glyph.TextScaled = false
	glyph.ZIndex = portrait.ZIndex + 2
	local name = centered(ui, card, 114, 26, 20, colors.text)
	name.Font = Enum.Font.GothamBlack
	local sub = centered(ui, card, 140, 18, 14, colors.dim)
	sub.Font = Enum.Font.GothamBold
	return {
		card = card,
		stroke = stroke,
		portrait = portrait,
		ring = ring,
		glyph = glyph,
		name = name,
		sub = sub,
	}
end

local function buildFight(ui, holder: Instance)
	local colors = ui.colors
	local panel = ui.makeFrame(holder, UDim2.new(1, -326, 0, 440), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1))
	panel.ClipsDescendants = true
	ui.addCorner(panel, 8)
	ui.art.stroke(panel, colors.gold, 2, 0.2)
	w.sky = Instance.new("UIGradient")
	w.sky.Rotation = 90
	w.sky.Parent = panel
	ui.art.skyline(panel, Color3.fromRGB(14, 12, 10), 0.35)
	ui.art.grain(panel)
	w.panel = panel

	w.stageTitle = ui.makeText(panel, UDim2.new(1, 0, 0, 52), UDim2.fromOffset(0, 8), colors.gold, 42)
	w.stageTitle.Font = ui.art.Fonts.title
	w.stageTitle.TextXAlignment = Enum.TextXAlignment.Center
	w.stageTitle.TextStrokeTransparency = 0.3
	w.stageTitle.ZIndex = 410

	-- You.
	local you = buildFighter(ui, panel, 0.03)
	w.you = you
	you.avatar = Instance.new("ImageLabel")
	you.avatar.Size = UDim2.fromScale(1, 1)
	you.avatar.BackgroundTransparency = 1
	you.avatar.ScaleType = Enum.ScaleType.Crop
	you.avatar.ZIndex = you.portrait.ZIndex + 1
	you.avatar.Parent = you.portrait
	ui.addCorner(you.avatar, 10)
	you.health = bar(ui, you.card, UDim2.fromOffset(12, 166), RED)
	you.stamina = bar(ui, you.card, UDim2.fromOffset(12, 196), BLUE)
	you.stat = centered(ui, you.card, 230, 24, 18, colors.gold)
	you.stat.Font = Enum.Font.GothamBlack
	you.note = centered(ui, you.card, 254, 20, 13, colors.dim)
	task.spawn(function()
		local player = Players.LocalPlayer
		local ok, image = pcall(Players.GetUserThumbnailAsync, Players, player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		if ok and image then
			you.avatar.Image = image
		end
	end)

	-- The foe.
	local foe = buildFighter(ui, panel, 0.63)
	w.foe = foe
	foe.health = bar(ui, foe.card, UDim2.fromOffset(12, 166), RED)
	foe.level = centered(ui, foe.card, 196, 24, 18, colors.text)
	foe.level.Font = Enum.Font.GothamBlack
	foe.stat = centered(ui, foe.card, 230, 24, 18, Color3.fromRGB(140, 190, 255))
	foe.stat.Font = Enum.Font.GothamBlack
	foe.note = centered(ui, foe.card, 254, 20, 13, colors.dim)

	-- VS in the middle.
	local vs = ui.makeText(panel, UDim2.new(0.26, 0, 0, 80), UDim2.new(0.37, 0, 0, 130), colors.gold, 72)
	vs.Font = ui.art.Fonts.title
	vs.Text = "VS"
	vs.TextXAlignment = Enum.TextXAlignment.Center
	vs.TextStrokeTransparency = 0.2
	vs.ZIndex = 410
	w.vs = vs
	local hint = ui.makeText(panel, UDim2.new(0.22, 0, 0, 70), UDim2.new(0.39, 0, 0, 214), colors.text, 14)
	hint.Font = Enum.Font.GothamBold
	hint.TextXAlignment = Enum.TextXAlignment.Center
	hint.TextStrokeTransparency = 0.4
	hint.Text = "LAND A HIT TO WEAR THE FOE DOWN"
	hint.ZIndex = 410

	-- ATTACK.
	w.attack = ui.makeButton(panel, UDim2.new(0.44, 0, 0, 58), UDim2.new(0.28, 0, 0, 368), colors.action)
	w.attack.TextSize = 24
	w.attack.Font = Enum.Font.GothamBlack
	w.attack.ZIndex = 410
	w.attack.Activated:Connect(function()
		local state = latest
		local stage = selected and GameConfig.Stages[tonumber(string.sub(selected, 2)) or 0]
		if state and stage and open(state, stage) and not state.stageCleared[stage.id] then
			ui.send("Fight", stage.id)
		end
	end)
end

-- One reward tile: a glyph and an amount.
local function tile(ui, parent: Instance, order: number): any
	local frame = ui.makeFrame(parent, UDim2.fromOffset(128, 58), UDim2.fromOffset(0, 0), Color3.fromRGB(26, 22, 18))
	frame.LayoutOrder = order
	ui.addCorner(frame, 6)
	local stroke = ui.art.stroke(frame, ui.colors.dim, 1, 0.4)
	local glyph = ui.makeText(frame, UDim2.fromOffset(40, 58), UDim2.fromOffset(6, 0), Color3.new(1, 1, 1), 28)
	glyph.TextXAlignment = Enum.TextXAlignment.Center
	local amount = ui.makeText(frame, UDim2.new(1, -50, 1, -8), UDim2.fromOffset(46, 4), ui.colors.text, 15)
	amount.Font = Enum.Font.GothamBlack
	amount.RichText = true
	return { frame = frame, glyph = glyph, amount = amount, stroke = stroke }
end

local function rewardRow(ui, parent: Instance, y: number, title: string): any
	local colors = ui.colors
	local row = ui.makeFrame(parent, UDim2.new(1, -20, 0, 66), UDim2.fromOffset(10, y), Color3.new(0, 0, 0))
	row.BackgroundTransparency = 1
	local label = ui.makeText(row, UDim2.fromOffset(130, 66), UDim2.fromOffset(0, 0), colors.gold, 18)
	label.Font = Enum.Font.GothamBlack
	label.Text = title
	local status = ui.makeText(row, UDim2.fromOffset(130, 20), UDim2.fromOffset(0, 44), colors.dim, 12)
	status.Font = Enum.Font.GothamBold
	local list = ui.makeFrame(row, UDim2.new(1, -136, 1, 0), UDim2.fromOffset(136, 4), Color3.new(0, 0, 0))
	list.BackgroundTransparency = 1
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	return { row = row, label = label, status = status, list = list }
end

local function buildRewards(ui, holder: Instance)
	local colors = ui.colors
	local strip = ui.makeFrame(holder, UDim2.new(1, -326, 0, 160), UDim2.fromOffset(0, 450), Color3.fromRGB(34, 29, 24))
	ui.addCorner(strip, 8)
	ui.art.stroke(strip, colors.dim, 1, 0.5)
	local daily = rewardRow(ui, strip, 8, "DAILY CLEAR")
	daily.gold = tile(ui, daily.list, 1)
	daily.gold.glyph.Text = "\u{1F4B0}"
	daily.xp = tile(ui, daily.list, 2)
	daily.xp.glyph.Text = "\u{2B50}"
	daily.tokens = tile(ui, daily.list, 3)
	daily.tokens.glyph.Text = ""
	coin(ui, daily.tokens.frame, 28, UDim2.fromOffset(12, 15))
	daily.chest = tile(ui, daily.list, 4)
	daily.chest.glyph.Text = ""
	daily.chestArt = ui.makeFrame(daily.chest.frame, UDim2.fromOffset(42, 42), UDim2.fromOffset(4, 8), Color3.new(0, 0, 0))
	daily.chestArt.BackgroundTransparency = 1
	daily.set = tile(ui, daily.list, 5)
	daily.set.frame.Size = UDim2.fromOffset(150, 58)
	daily.set.glyph.Text = "\u{1F6E1}\u{FE0F}"
	w.daily = daily

	local first = rewardRow(ui, strip, 84, "FIRST CLEAR")
	first.crowns = tile(ui, first.list, 1)
	first.crowns.glyph.Text = "\u{1F451}"
	first.tokens = tile(ui, first.list, 2)
	first.tokens.glyph.Text = ""
	coin(ui, first.tokens.frame, 28, UDim2.fromOffset(12, 15))
	first.unlock = tile(ui, first.list, 3)
	first.unlock.frame.Size = UDim2.fromOffset(220, 58)
	first.unlock.glyph.Text = "\u{1F513}"
	w.first = first
end

local function buildSidebar(ui, holder: Instance)
	local colors = ui.colors
	local side = ui.makeFrame(holder, UDim2.new(0, 316, 0, 610), UDim2.new(1, -316, 0, 0), Color3.fromRGB(30, 26, 21))
	ui.addCorner(side, 8)
	ui.art.stroke(side, colors.gold, 1.5, 0.4)
	local title = ui.makeText(side, UDim2.new(1, -20, 0, 30), UDim2.fromOffset(12, 6), colors.gold, 24)
	title.Font = ui.art.Fonts.title
	title.Text = "STAGES"
	w.highest = ui.makeText(side, UDim2.new(1, -24, 0, 18), UDim2.fromOffset(12, 38), colors.text, 13)
	w.highest.Font = Enum.Font.GothamBold
	w.reset = ui.makeText(side, UDim2.new(1, -24, 0, 18), UDim2.fromOffset(12, 56), colors.dim, 13)
	w.reset.Font = Enum.Font.GothamBold

	local list = Instance.new("ScrollingFrame")
	list.Size = UDim2.new(1, -12, 1, -84)
	list.Position = UDim2.fromOffset(6, 80)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = colors.gold
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = side
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	w.list = list

	local order, lastHouse = 0, nil
	for _, stage in GameConfig.Stages do
		if stage.house ~= lastHouse then
			lastHouse = stage.house
			order += 1
			local heading = ui.makeText(list, UDim2.new(1, -10, 0, 30), UDim2.fromOffset(0, 0), HOUSE_COLORS[stage.house] or colors.gold, 14)
			heading.LayoutOrder = order
			heading.Font = Enum.Font.GothamBlack
			heading.TextColor3 = (HOUSE_COLORS[stage.house] or colors.gold):Lerp(Color3.new(1, 1, 1), 0.45)
			local house = houseOf(stage.house)
			heading.Text = string.upper(house and house.name or stage.houseName)
		end
		order += 1
		local row = ui.makeButton(list, UDim2.new(1, -10, 0, 60), UDim2.fromOffset(0, 0), Color3.fromRGB(42, 36, 29))
		row.LayoutOrder = order
		row.Text = ""
		row:SetAttribute("NoGlow", true)
		local stroke = ui.art.stroke(row, colors.gold, 2, 1)
		local portrait = ui.makeFrame(row, UDim2.fromOffset(48, 48), UDim2.fromOffset(6, 6), HOUSE_COLORS[stage.house] or colors.row)
		ui.addCorner(portrait, 6)
		local glyph = ui.makeText(portrait, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1), 28)
		glyph.TextXAlignment = Enum.TextXAlignment.Center
		local number = ui.makeText(row, UDim2.new(1, -150, 0, 16), UDim2.fromOffset(62, 8), colors.gold, 12)
		number.Font = Enum.Font.GothamBlack
		number.Text = `STAGE {stage.index}`
		local name = ui.makeText(row, UDim2.new(1, -150, 0, 22), UDim2.fromOffset(62, 26), colors.text, 15)
		name.Font = Enum.Font.GothamBold
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.TextWrapped = false
		name.Text = stage.name
		local status = ui.makeText(row, UDim2.fromOffset(84, 44), UDim2.new(1, -90, 0, 8), colors.dim, 11)
		status.Font = Enum.Font.GothamBlack
		status.TextXAlignment = Enum.TextXAlignment.Right
		stageRows[stage.id] = { row = row, stroke = stroke, portrait = portrait, glyph = glyph, name = name, status = status, number = number }
		row.Activated:Connect(function()
			selected = stage.id
			FoesPage.draw(latest, ui)
		end)
	end
end

local function buildStagesTab(ui, page: Instance)
	local holder = ui.makeFrame(page, UDim2.new(1, -10, 0, 610), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	holder.BackgroundTransparency = 1
	holder.LayoutOrder = 2
	w.stages = holder
	buildFight(ui, holder)
	buildRewards(ui, holder)
	buildSidebar(ui, holder)
end

---------------------------------------------------------------------------
-- Building: TOKEN SHOP tab
---------------------------------------------------------------------------

local function heading(ui, parent: Instance, order: number, title: string, color: Color3): any
	local frame = ui.makeFrame(parent, UDim2.new(1, 0, 0, 58), UDim2.fromOffset(0, 0), Color3.fromRGB(34, 29, 24))
	frame.LayoutOrder = order
	ui.addCorner(frame, 6)
	local band = ui.makeFrame(frame, UDim2.new(0, 6, 1, 0), UDim2.fromOffset(0, 0), color)
	ui.addCorner(band, 3)
	local label = ui.makeText(frame, UDim2.new(1, -30, 0, 28), UDim2.fromOffset(18, 4), ui.colors.gold, 22)
	label.Font = ui.art.Fonts.heading
	label.Text = title
	local note = ui.makeText(frame, UDim2.new(1, -30, 0, 22), UDim2.fromOffset(18, 32), ui.colors.dim, 13)
	note.RichText = true
	return { frame = frame, label = label, note = note }
end

local function grid(ui, parent: Instance, order: number, height: number): Frame
	local frame = ui.makeFrame(parent, UDim2.new(1, 0, 0, 0), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	frame.BackgroundTransparency = 1
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.LayoutOrder = order
	local layout = Instance.new("UIGridLayout")
	layout.CellPadding = UDim2.fromOffset(12, 12)
	layout.CellSize = UDim2.new(1 / 3, -8, 0, height)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame
	return frame
end

local function priceButton(ui, parent: Instance, position: UDim2, size: UDim2): TextButton
	local button = ui.makeButton(parent, size, position, ui.colors.buy)
	button.TextSize = 18
	button.Font = Enum.Font.GothamBlack
	return button
end

local function buildSupplyCard(ui, parent: Instance, item, order: number)
	local colors = ui.colors
	local card = ui.makeFrame(parent, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.fromRGB(34, 29, 24))
	card.LayoutOrder = order
	ui.addCorner(card, 8)
	ui.art.stroke(card, colors.dim, 1, 0.5)
	local picture = ui.makeFrame(card, UDim2.fromOffset(72, 72), UDim2.fromOffset(12, 12), Color3.fromRGB(22, 18, 14))
	ui.addCorner(picture, 8)
	if item.kind == "chest" then
		local art = ui.makeFrame(picture, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
		art.BackgroundTransparency = 1
		ui.itemArt.chest(art, item.rarity)
	else
		local glyph = ui.makeText(picture, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1), 42)
		glyph.TextXAlignment = Enum.TextXAlignment.Center
		glyph.Text = SUPPLY_GLYPHS[item.kind] or "\u{1F381}"
	end
	local name = ui.makeText(card, UDim2.new(1, -104, 0, 26), UDim2.fromOffset(96, 12), colors.text, 18)
	name.Font = Enum.Font.GothamBlack
	name.Text = item.name
	name.TextTruncate = Enum.TextTruncate.AtEnd
	if item.rarity then
		local rarity = GameConfig.getRarity(item.rarity)
		name.TextColor3 = rarity.color
	end
	local note = ui.makeText(card, UDim2.new(1, -104, 0, 40), UDim2.fromOffset(96, 40), colors.dim, 13)
	note.Text = item.note
	local button = priceButton(ui, card, UDim2.new(0, 12, 1, -50), UDim2.new(1, -24, 0, 40))
	button.Activated:Connect(function()
		ui.send("TokenBuy", item.id)
	end)
	supplyCards[item.id] = { button = button }
end

local function buildSetCard(ui, parent: Instance, entry, order: number)
	local colors = ui.colors
	local rarity = GameConfig.getRarity(entry.rarity)
	local card = ui.makeFrame(parent, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1))
	card.LayoutOrder = order
	card.ClipsDescendants = true
	ui.addCorner(card, 10)
	ui.art.stroke(card, rarity.color, 2.5, 0.1)
	local glow = Instance.new("UIGradient")
	glow.Rotation = 90
	glow.Color = ColorSequence.new(rarity.color:Lerp(Color3.new(0, 0, 0), 0.55), Color3.fromRGB(30, 26, 22))
	glow.Parent = card
	ui.art.shine(card, 4)

	local tag = ui.makeText(card, UDim2.fromOffset(96, 22), UDim2.fromOffset(10, 10), colors.text, 11)
	tag.BackgroundTransparency = 0.2
	tag.BackgroundColor3 = Color3.fromRGB(16, 14, 12)
	tag.Font = Enum.Font.GothamBlack
	tag.TextXAlignment = Enum.TextXAlignment.Center
	tag.Text = "SET PIECE"
	ui.addCorner(tag, 4)

	local picture = ui.makeFrame(card, UDim2.fromOffset(140, 140), UDim2.new(0.5, -70, 0, 20), Color3.new(0, 0, 0))
	picture.BackgroundTransparency = 1
	ui.itemArt.set(picture, { kind = "Gear", slot = entry.slot, name = entry.name, rarity = entry.rarity, set = entry.set })

	local rarityLabel = centered(ui, card, 166, 20, 15, rarity.color)
	rarityLabel.Font = Enum.Font.GothamBlack
	rarityLabel.Text = string.upper(ui.rarityName and ui.rarityName(rarity.id) or rarity.id)
	local name = centered(ui, card, 186, 26, 20, colors.text)
	name.Font = Enum.Font.GothamBlack
	name.Text = entry.name
	local attack, defense = GameConfig.getGearStats(entry.slot, entry.name, rarity)
	local stats = centered(ui, card, 214, 22, 16, colors.text)
	stats.Font = Enum.Font.GothamBold
	stats.RichText = true
	stats.Text = `<font color="#FF9A7A">+{attack} ATTACK</font>   <font color="#8FC8FF">+{defense} DEFENSE</font>`
	local price = ui.makeText(card, UDim2.new(1, -60, 0, 26), UDim2.fromOffset(48, 244), colors.gold, 17)
	price.Font = Enum.Font.GothamBlack
	price.Text = `{commas(entry.cost)} BOSS TOKENS`
	coin(ui, card, 24, UDim2.fromOffset(16, 245))
	local button = priceButton(ui, card, UDim2.new(0, 12, 1, -52), UDim2.new(1, -24, 0, 42))
	button.Text = "BUY"
	button.Activated:Connect(function()
		ui.send("TokenSet", entry.id)
	end)
	local shade = ui.makeFrame(card, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	shade.BackgroundTransparency = 0.35
	shade.ZIndex = 400
	local lockText = ui.makeText(shade, UDim2.new(1, -30, 0, 60), UDim2.new(0, 15, 0.5, -30), colors.text, 16)
	lockText.Font = Enum.Font.GothamBlack
	lockText.TextXAlignment = Enum.TextXAlignment.Center
	lockText.ZIndex = 401
	setCards[entry.id] = { button = button, shade = shade, lockText = lockText, entry = entry }
end

local function buildShopTab(ui, page: Instance)
	local holder = ui.makeFrame(page, UDim2.new(1, -10, 0, 0), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	holder.BackgroundTransparency = 1
	holder.AutomaticSize = Enum.AutomaticSize.Y
	holder.LayoutOrder = 3
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = holder
	w.shop = holder

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	local supplies = heading(ui, holder, nextOrder(), "SUPPLIES", ui.colors.gold)
	supplies.note.Text = "Refills, boosts and chests. Bought chests go to your Inventory."
	local supplyGrid = grid(ui, holder, nextOrder(), 150)
	for index, item in GameConfig.TokenShop do
		buildSupplyCard(ui, supplyGrid, item, index)
	end

	for _, set in GameConfig.GearSets do
		local house = houseOf(set.house)
		local head = heading(ui, holder, nextOrder(), string.upper(set.name) .. " SET", HOUSE_COLORS[set.house] or ui.colors.gold)
		setHeads[set.id] = { head = head, set = set, house = house }
		local setGrid = grid(ui, holder, nextOrder(), 310)
		local index = 0
		for _, entry in GameConfig.SetShop do
			if entry.set == set.id then
				index += 1
				buildSetCard(ui, setGrid, entry, index)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------

function FoesPage.build(ui)
	local page = ui.pages.Foes
	buildTabs(ui, page)
	buildStagesTab(ui, page)
	buildShopTab(ui, page)

	local Fx = require(script.Parent:WaitForChild("Fx"))
	Fx.setAnchor("foe", w.foe.health.back)
	Fx.setAnchor("you", w.you.health.back)
	-- After a win, move on to the next stage still to beat.
	Fx.onHit = function(info)
		FoesPage.pulse()
		if info.result == "cleared" then
			task.delay(1.4, function()
				selected = nil
				FoesPage.draw(latest, ui)
			end)
		end
	end

	-- Reset countdown, once a second while the page shows.
	task.spawn(function()
		while true do
			task.wait(1)
			if page.Visible and latest then
				w.reset.Text = `RESETS IN {clock(resetAt - os.clock())}`
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function pickStage(state)
	local stage = selected and GameConfig.Stages[tonumber(string.sub(selected, 2)) or 0]
	if stage then
		return stage
	end
	-- First stage still to beat today, else the highest one reached.
	local fallback = GameConfig.Stages[1]
	for _, candidate in GameConfig.Stages do
		if open(state, candidate) then
			fallback = candidate
			if not state.stageCleared[candidate.id] then
				selected = candidate.id
				return candidate
			end
		end
	end
	selected = fallback.id
	return fallback
end

local function drawFight(state, ui, stage)
	local colors = ui.colors
	local stats = state.stats
	local color = HOUSE_COLORS[stage.house] or Color3.fromRGB(60, 60, 60)
	w.sky.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.15), color:Lerp(Color3.new(0, 0, 0), 0.7))
	w.stageTitle.Text = `STAGE {stage.index}`

	-- You.
	local you = w.you
	you.name.Text = Players.LocalPlayer.DisplayName
	you.sub.Text = `LEVEL {state.level}`
	setBar(you.health, state.health, stats.maxHealth, `{HEART} {commas(state.health)} / {commas(stats.maxHealth)}`)
	setBar(you.stamina, state.stamina, stats.maxStamina, `{DAGGER} {state.stamina} / {stats.maxStamina}`)
	local hit = GameConfig.getHit(stats.attack, stage.defense)
	local low = math.max(1, math.floor(hit * GameConfig.HitRollMin))
	local high = math.max(1, math.floor(hit * GameConfig.HitRollMax))
	you.stat.Text = `ATTACK {Format.short(low)} TO {Format.short(high)}`
	you.note.Text = `Your attack {Format.short(stats.attack)}, defense {Format.short(stats.defense)}`

	-- The foe.
	local foe = w.foe
	local known = reached(state, stage)
	foe.portrait.BackgroundColor3 = if known then color else Color3.new(0, 0, 0)
	foe.glyph.Text = if known then FOE_GLYPHS[stage.index] or "\u{1F409}" else "???"
	foe.glyph.TextSize = if known then 60 else 34
	foe.glyph.Font = Enum.Font.GothamBlack
	foe.name.Text = stage.name
	foe.sub.Text = string.upper(stage.title)
	local cleared = state.stageCleared[stage.id] == true
	local health = if cleared then 0 else (state.stageHealth[stage.id] or stage.health)
	setBar(foe.health, health, stage.health, `{HEART} {Format.short(health)} / {Format.short(stage.health)}`)
	foe.level.Text = `LEVEL {stage.level}`
	foe.level.TextColor3 = if state.level >= stage.level then colors.text else Color3.fromRGB(255, 110, 100)
	foe.stat.Text = `DEFENSE {Format.short(stage.defense)}`
	local back = GameConfig.getHit(stage.attack, stats.defense)
	foe.note.Text = `Hits back {Format.short(math.max(1, math.floor(back * GameConfig.HitRollMin)))} to {Format.short(math.max(1, math.floor(back * GameConfig.HitRollMax)))}`
	foe.stroke.Color = if cleared then GREEN else colors.gold

	-- The button.
	local usable = false
	local label
	if cleared then
		label = `{CHECK} DONE TODAY`
	elseif state.level < stage.level then
		label = `Requires level {stage.level}`
	elseif not reached(state, stage) then
		label = `Beat stage {stage.index - 1} first`
	elseif state.stamina < 1 then
		label = "No stamina"
	elseif state.health < GameConfig.MinHealthToFight then
		label = "Too wounded"
	else
		label = `{SWORDS} ATTACK  (1 stamina)`
		usable = true
	end
	ui.setButton(w.attack, label, usable, colors.action)
	if not usable then
		w.attack.TextSize = 20
	else
		w.attack.TextSize = 24
	end
end

local function setTile(part, text: string, done: boolean)
	part.amount.Text = text
	part.frame.BackgroundTransparency = if done then 0.5 else 0
	part.amount.TextTransparency = if done then 0.5 else 0
	part.glyph.TextTransparency = if done then 0.5 else 0
end

local function drawRewards(state, ui, stage)
	local colors = ui.colors
	local daily, first = w.daily, w.first
	local cleared = state.stageCleared[stage.id] == true
	daily.status.Text = if cleared then `{CHECK} WON TODAY` else "every day"
	daily.status.TextColor3 = if cleared then GREEN else colors.dim
	setTile(daily.gold, `{Format.short(stage.gold)}\n<font size="11" color="#B7A98F">GOLD</font>`, cleared)
	setTile(daily.xp, `{Format.short(stage.xp)}\n<font size="11" color="#B7A98F">XP</font>`, cleared)
	setTile(daily.tokens, `x{stage.tokens}\n<font size="11" color="#B7A98F">TOKENS</font>`, cleared)
	daily.chest.frame.Visible = stage.chest ~= nil
	if stage.chest then
		if daily.chestArt:GetAttribute("Chest") ~= stage.chest then
			daily.chestArt:SetAttribute("Chest", stage.chest)
			ui.itemArt.chest(daily.chestArt, stage.chest)
		end
		setTile(daily.chest, `{stage.chest}\n<font size="11" color="#B7A98F">CHEST</font>`, cleared)
		daily.chest.stroke.Color = GameConfig.getRarity(stage.chest).color
	end
	local set = GameConfig.getHouseSet(stage.house)
	daily.set.frame.Visible = set ~= nil
	if set then
		setTile(daily.set, `{math.floor(GameConfig.SetDropChance * 100)}%\n<font size="11" color="#B7A98F">{string.upper(set.name)} PIECE</font>`, cleared)
	end

	local firstDone = state.firstClears[stage.id] == true
	first.status.Text = if firstDone then `{CHECK} CLAIMED` else "once ever"
	first.status.TextColor3 = if firstDone then GREEN else colors.dim
	setTile(first.crowns, `{stage.firstCrowns}\n<font size="11" color="#B7A98F">CROWNS</font>`, firstDone)
	setTile(first.tokens, `x{stage.firstTokens}\n<font size="11" color="#B7A98F">TOKENS</font>`, firstDone)
	local unlocks = set and set.bossStage == stage.id
	first.unlock.frame.Visible = unlocks == true
	if unlocks and set then
		setTile(first.unlock, `{string.upper(set.name)} SET\n<font size="11" color="#B7A98F">IN THE TOKEN SHOP</font>`, firstDone)
	end
end

local function drawSidebar(state, ui)
	local colors = ui.colors
	w.highest.Text = `HIGHEST STAGE  {state.highestStage}`
	w.reset.Text = `RESETS IN {clock(resetAt - os.clock())}`
	for _, stage in GameConfig.Stages do
		local row = stageRows[stage.id]
		local known = reached(state, stage)
		local on = stage.id == selected
		row.row.BackgroundColor3 = if on then Color3.fromRGB(120, 92, 36) else Color3.fromRGB(42, 36, 29)
		row.stroke.Transparency = if on then 0 else 1
		row.portrait.BackgroundColor3 = if known then HOUSE_COLORS[stage.house] or colors.row else Color3.new(0, 0, 0)
		row.glyph.Text = if known then FOE_GLYPHS[stage.index] or "" else "?"
		row.glyph.TextColor3 = if known then Color3.new(1, 1, 1) else colors.dim
		local text, color
		if state.stageCleared[stage.id] then
			text, color = "DONE\nTODAY", GREEN
		elseif state.level < stage.level then
			text, color = `LEVEL {stage.level}`, Color3.fromRGB(255, 120, 100)
		elseif not known then
			text, color = `{LOCK}`, colors.dim
		else
			local health = state.stageHealth[stage.id]
			if health then
				text = `{math.ceil(health / stage.health * 100)}%\nHEALTH`
			else
				text = "READY"
			end
			color = colors.gold
		end
		row.status.Text = text
		row.status.TextColor3 = color
		row.name.TextColor3 = if known then colors.text else colors.dim
	end
end

local function drawShop(state, ui)
	local colors = ui.colors
	for _, item in GameConfig.TokenShop do
		local card = supplyCards[item.id]
		ui.setButton(card.button, `BUY  {commas(item.cost)} TOKENS`, state.tokens >= item.cost, colors.buy)
	end
	for _, part in setHeads do
		local set, house = part.set, part.house
		local boss = set.bossStage and GameConfig.Stages[tonumber(string.sub(set.bossStage, 2)) or 0]
		local unlocked = set.bossStage ~= nil and state.firstClears[set.bossStage] == true
		local lock = if unlocked
			then `<font color="#9FD49A">{CHECK} Unlocked</font>`
			else `<font color="#FF9A7A">{LOCK} Beat {boss and boss.name or "the house boss"} once to unlock</font>`
		part.head.note.Text = `{house and house.name or ""}  ·  {set.rarity or ""}  ·  Full set: {perkText(set.perk)}   {lock}`
	end
	for _, card in setCards do
		local entry = card.entry
		local unlocked = state.firstClears[entry.bossStage] == true
		card.shade.Visible = not unlocked
		if not unlocked then
			local boss = GameConfig.Stages[tonumber(string.sub(entry.bossStage, 2)) or 0]
			card.lockText.Text = `{LOCK}\nBeat {boss and boss.name or "the house boss"}`
		end
		ui.setButton(card.button, if state.tokens >= entry.cost then "BUY" else "NOT ENOUGH TOKENS", unlocked and state.tokens >= entry.cost, colors.buy)
	end
end

function FoesPage.draw(state, ui)
	if not state then
		return
	end
	latest = state
	resetAt = os.clock() + (state.stageReset or 0)
	local colors = ui.colors
	for key, part in w.tabs do
		local on = key == tab
		part.line.Visible = on
		part.button.TextColor3 = if on then colors.text else colors.dim
	end
	w.tokens.Text = `{commas(state.tokens)} BOSS TOKENS`
	w.stages.Visible = tab == "stages"
	w.shop.Visible = tab == "shop"

	if tab == "stages" then
		local stage = pickStage(state)
		drawFight(state, ui, stage)
		drawRewards(state, ui, stage)
		drawSidebar(state, ui)
	else
		drawShop(state, ui)
	end
end

-- The "VS" pops on every attack.
function FoesPage.pulse()
	if w.vs then
		local scale = Instance.new("UIScale")
		scale.Scale = 1.3
		scale.Parent = w.vs
		local tween = TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 })
		tween:Play()
		tween.Completed:Connect(function()
			scale:Destroy()
		end)
	end
end

return FoesPage
