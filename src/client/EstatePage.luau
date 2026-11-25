-- Estate page, laid out like Holdings:
--   * a tab bar with one tab per castle (locked ones show their level),
--   * four resource chips (stock / storage, rate per hour, a fill bar),
--   * a builder banner: claim the castle, the upgrade under construction
--     (picture, countdown, bar, Finish now with Crowns) or "builder free",
--   * a two-column grid of building cards: animated picture, level, what
--     the next level gives, its price and time. Press a card to upgrade.
-- Each castle has its own builder, who does one upgrade at a time.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local EstateConfig = require(Shared:WaitForChild("EstateConfig"))
local ResearchConfig = require(Shared:WaitForChild("ResearchConfig"))
local Format = require(Shared:WaitForChild("Format"))
local Scenes = require(script.Parent:WaitForChild("Scenes"))

local EstatePage = {}

local GREEN = Color3.fromRGB(110, 210, 110)
local AMBER = Color3.fromRGB(240, 196, 80)
local ARROW, CLOCK, LOCK = "\u{27A1}", "\u{23F1}", "\u{1F512}"
local RESOURCE_ICONS = {
	lumber = "\u{1F332}", -- wood
	stone = "\u{26F0}\u{FE0F}", -- rock
	iron = "\u{26CF}\u{FE0F}", -- pick
	grain = "\u{1F33E}", -- sheaf
}

local w = {}
local tabs = {} -- [castle key] = { button, line }
local chips = {} -- [resource key] = widgets
local cards = {} -- [building key] = widgets
local selected = "home"
local latest = nil -- the last state drawn
local shownLevels = {} -- [castle:building] = level last drawn, for the level up flash
local timer = nil -- { left, total, at } for the builder bar

-- A time like "2d 4h", "3h 12m", "4m 05s" or "38s".
local function clock(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	local days, hours = seconds // 86400, seconds % 86400 // 3600
	local minutes, secs = seconds % 3600 // 60, seconds % 60
	if days > 0 then
		return `{days}d {hours}h`
	elseif hours > 0 then
		return `{hours}h {minutes}m`
	elseif minutes > 0 then
		return `{minutes}m {string.format("%02d", secs)}s`
	end
	return `{secs}s`
end

local function percent(value: number): string
	return `{math.floor(value * 1000 + 0.5) / 10}%`
end

-- What a building does at a level, as short words.
local function effect(building, level: number): string
	if building.kind == "produce" then
		return `{Format.short(EstateConfig.getRate(building, level))} {building.resource}/h`
	elseif building.kind == "storage" then
		return `+{Format.short(EstateConfig.getCapBonus(building, level))} storage`
	elseif building.kind == "cellar" then
		return `{percent(building.percent * level)} hidden`
	end
	return `+{percent(building.percent * level)} defense`
end

-- A price as colored parts; red where you are short.
local function priceText(cost, gold: number, stock): string
	local parts = {}
	if cost.gold and cost.gold > 0 then
		local color = if gold >= cost.gold then "#F0C450" else "#DC6E5A"
		table.insert(parts, `<font color="{color}"><b>{Format.short(cost.gold)}</b> gold</font>`)
	end
	for _, resource in EstateConfig.Resources do
		local amount = cost[resource.key]
		if amount and amount > 0 then
			local color = if (stock[resource.key] or 0) >= amount then resource.color else "#DC6E5A"
			table.insert(parts, `<font color="{color}"><b>{Format.short(amount)}</b> {string.lower(resource.name)}</font>`)
		end
	end
	return if #parts > 0 then table.concat(parts, "  ") else "free"
end

local function hazard(ui, parent: Instance, y: number, z: number)
	local tape = ui.makeFrame(parent, UDim2.new(1, 0, 0, 12), UDim2.new(0, 0, y, if y == 0 then 0 else -12), AMBER)
	tape.ZIndex = z
	tape.ClipsDescendants = true
	for index = 0, 60 do
		local stripe = ui.makeFrame(tape, UDim2.fromOffset(7, 28), UDim2.fromOffset(index * 16, -8), Color3.fromRGB(30, 26, 20))
		stripe.Rotation = 35
		stripe.ZIndex = z + 1
	end
	return tape
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

local function buildTabs(ui, page: Instance)
	local colors = ui.colors
	local bar = ui.makeFrame(page, UDim2.new(1, -10, 0, 52), UDim2.fromOffset(0, 0), Color3.fromRGB(44, 36, 22))
	bar.LayoutOrder = 1
	ui.addCorner(bar, 6)
	ui.art.stroke(bar, colors.gold, 1.5, 0.4)
	for index, castle in EstateConfig.Castles do
		local button = ui.makeButton(bar, UDim2.fromOffset(250, 44), UDim2.fromOffset(10 + (index - 1) * 260, 4), Color3.new(0, 0, 0))
		button.BackgroundTransparency = 1
		button.TextSize = 18
		button:SetAttribute("NoGlow", true)
		local line = ui.makeFrame(button, UDim2.new(1, -20, 0, 3), UDim2.new(0, 10, 1, -3), colors.gold)
		tabs[castle.key] = { button = button, line = line }
		button.Activated:Connect(function()
			selected = castle.key
			timer = nil
			EstatePage.draw(latest, ui)
		end)
	end
end

local function buildChips(ui, page: Instance)
	local colors = ui.colors
	local row = ui.makeFrame(page, UDim2.new(1, -10, 0, 104), UDim2.fromOffset(0, 0), colors.panel)
	row.BackgroundTransparency = 1
	row.LayoutOrder = 2
	local count = #EstateConfig.Resources
	for index, resource in EstateConfig.Resources do
		local color = Color3.fromHex(resource.color)
		local frame = ui.makeFrame(row, UDim2.new(1 / count, -8, 1, 0), UDim2.new((index - 1) / count, (index - 1) * 8 / count * 1.0, 0, 0), Color3.fromRGB(30, 25, 20))
		ui.addCorner(frame, 8)
		ui.art.stroke(frame, colors.dim, 1, 0.6)
		local icon = ui.art.icon(frame, RESOURCE_ICONS[resource.key] or "", 30, UDim2.fromOffset(12, 10))
		icon.ZIndex = frame.ZIndex + 1
		local name = ui.makeText(frame, UDim2.new(1, -60, 0, 18), UDim2.fromOffset(50, 8), colors.dim, 13)
		name.Font = Enum.Font.GothamBold
		name.Text = string.upper(resource.name)
		local full = ui.makeText(frame, UDim2.fromOffset(44, 18), UDim2.new(1, -52, 0, 8), AMBER, 11)
		full.Font = Enum.Font.GothamBold
		full.TextXAlignment = Enum.TextXAlignment.Center
		full.Text = "FULL"
		ui.art.stroke(full, AMBER, 1, 0.2)
		local amount = ui.makeText(frame, UDim2.new(1, -24, 0, 30), UDim2.fromOffset(12, 40), color, 24)
		amount.Font = Enum.Font.GothamBlack
		amount.RichText = true
		local barBack = ui.makeFrame(frame, UDim2.new(1, -24, 0, 8), UDim2.fromOffset(12, 72), Color3.fromRGB(18, 14, 10))
		ui.addCorner(barBack, 4)
		local fill = ui.makeFrame(barBack, UDim2.fromScale(0, 1), UDim2.fromOffset(0, 0), color)
		ui.addCorner(fill, 4)
		local rate = ui.makeText(frame, UDim2.new(1, -24, 0, 16), UDim2.fromOffset(12, 83), GREEN, 12)
		rate.Font = Enum.Font.GothamBold
		chips[resource.key] = { full = full, amount = amount, fill = fill, rate = rate }
	end
	w.extras = ui.makeText(page, UDim2.new(1, -10, 0, 20), UDim2.fromOffset(0, 0), colors.dim, 13)
	w.extras.LayoutOrder = 3
	w.extras.RichText = true
end

-- The builder banner: claim, under construction, or free.
local function buildBanner(ui, page: Instance)
	local colors = ui.colors
	local banner = ui.makeFrame(page, UDim2.new(1, -10, 0, 140), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1))
	banner.LayoutOrder = 4
	banner.ClipsDescendants = true
	ui.addCorner(banner, 8)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromRGB(24, 20, 16), Color3.fromRGB(60, 48, 30))
	gradient.Parent = banner
	ui.art.skyline(banner, Color3.new(0, 0, 0), 0.6)
	w.bannerStroke = ui.art.stroke(banner, colors.gold, 1.5, 0.4)
	w.banner = banner

	local picture = ui.makeFrame(banner, UDim2.new(0, 210, 1, -16), UDim2.fromOffset(8, 8), Color3.fromRGB(20, 16, 12))
	picture.ClipsDescendants = true
	picture.ZIndex = banner.ZIndex + 2
	ui.addCorner(picture, 6)
	w.bannerPicture = picture
	w.bannerHazard = { hazard(ui, picture, 0, 440), hazard(ui, picture, 1, 440) }
	w.bannerDim = ui.makeFrame(picture, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	w.bannerDim.BackgroundTransparency = 0.45
	w.bannerDim.ZIndex = 438

	w.bannerTitle = ui.makeText(banner, UDim2.new(1, -470, 0, 44), UDim2.fromOffset(234, 12), colors.gold, 34)
	w.bannerTitle.Font = ui.art.Fonts.title
	w.bannerTitle.ZIndex = banner.ZIndex + 2
	w.bannerTitle.TextTruncate = Enum.TextTruncate.AtEnd
	w.bannerTitle.TextWrapped = false
	w.bannerText = ui.makeText(banner, UDim2.new(1, -470, 0, 44), UDim2.fromOffset(234, 58), colors.text, 15)
	w.bannerText.RichText = true
	w.bannerText.ZIndex = banner.ZIndex + 2
	w.bannerText.TextYAlignment = Enum.TextYAlignment.Top
	local barBack = ui.makeFrame(banner, UDim2.new(1, -470, 0, 14), UDim2.new(0, 234, 1, -30), Color3.fromRGB(18, 14, 10))
	barBack.ZIndex = banner.ZIndex + 2
	ui.addCorner(barBack, 5)
	w.bannerBar = barBack
	w.bannerFill = ui.makeFrame(barBack, UDim2.fromScale(0, 1), UDim2.fromOffset(0, 0), AMBER)
	w.bannerFill.ZIndex = banner.ZIndex + 3
	ui.addCorner(w.bannerFill, 5)
	w.bannerTime = ui.makeText(banner, UDim2.fromOffset(120, 30), UDim2.new(1, -230, 1, -40), colors.text, 22)
	w.bannerTime.Font = Enum.Font.GothamBlack
	w.bannerTime.TextXAlignment = Enum.TextXAlignment.Right
	w.bannerTime.ZIndex = banner.ZIndex + 2

	w.bannerButton = ui.makeButton(banner, UDim2.fromOffset(200, 64), UDim2.new(1, -212, 0, 14), colors.buy)
	w.bannerButton.TextSize = 16
	w.bannerButton.ZIndex = banner.ZIndex + 3
	w.bannerButton.Activated:Connect(function()
		local state = latest
		if not state then
			return
		end
		local castle = state.estate.castles[selected]
		if not castle then
			ui.send("CastleBuy", selected)
		elseif castle.build.key ~= "" then
			ui.send("EstateFinish", selected)
		end
	end)
	w.bannerPictureKey = nil
end

local function buildCards(ui, page: Instance)
	local colors = ui.colors
	local grid = ui.makeFrame(page, UDim2.new(1, -10, 0, 0), UDim2.fromOffset(0, 0), colors.panel)
	grid.BackgroundTransparency = 1
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.LayoutOrder = 5
	local layout = Instance.new("UIGridLayout")
	layout.CellPadding = UDim2.fromOffset(10, 10)
	layout.CellSize = UDim2.new(0.5, -6, 0, 190)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	local function onPage()
		return page.Visible
	end
	for order, building in EstateConfig.Buildings do
		local card = ui.makeButton(grid, UDim2.fromOffset(100, 100), UDim2.fromOffset(0, 0), Color3.fromRGB(36, 30, 24))
		card.LayoutOrder = order
		card.Text = ""
		card.ClipsDescendants = true
		ui.addCorner(card, 8)
		local stroke = ui.art.stroke(card, colors.dim, 1.5, 0.5)
		local picture = ui.makeFrame(card, UDim2.new(0, 220, 1, -12), UDim2.fromOffset(6, 6), Color3.fromRGB(20, 16, 12))
		picture.ClipsDescendants = true
		ui.addCorner(picture, 6)
		Scenes.building(picture, building.key, onPage, 165)
		local level = ui.makeText(picture, UDim2.fromOffset(10, 26), UDim2.new(0, 8, 1, -34), colors.gold, 16)
		level.AutomaticSize = Enum.AutomaticSize.X
		level.TextWrapped = false
		level.Font = Enum.Font.GothamBlack
		level.BackgroundTransparency = 0.15
		level.BackgroundColor3 = Color3.fromRGB(26, 20, 16)
		level.ZIndex = 450
		ui.addCorner(level, 4)
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 8)
		pad.PaddingRight = UDim.new(0, 8)
		pad.Parent = level

		local name = ui.makeText(card, UDim2.new(1, -244, 0, 30), UDim2.fromOffset(238, 8), colors.text, 22)
		name.Font = Enum.Font.GothamBold
		name.Text = building.name
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.TextWrapped = false
		local note = ui.makeText(card, UDim2.new(1, -244, 0, 16), UDim2.fromOffset(238, 38), colors.dim, 12)
		note.Text = building.note
		local gain = ui.makeText(card, UDim2.new(1, -244, 0, 26), UDim2.fromOffset(238, 58), GREEN, 18)
		gain.Font = Enum.Font.GothamBlack
		gain.RichText = true
		local status = ui.makeText(card, UDim2.new(1, -244, 0, 20), UDim2.fromOffset(238, 88), colors.dim, 14)
		status.Font = Enum.Font.GothamBold
		local price = ui.makeText(card, UDim2.new(1, -244, 0, 40), UDim2.fromOffset(238, 110), colors.text, 14)
		price.RichText = true
		price.TextYAlignment = Enum.TextYAlignment.Top
		-- Level out of the max, as blocks of 5.
		local track = ui.makeFrame(card, UDim2.new(1, -250, 0, 8), UDim2.new(0, 238, 1, -20), Color3.fromRGB(18, 14, 10))
		ui.addCorner(track, 4)
		local fill = ui.makeFrame(track, UDim2.fromScale(0, 1), UDim2.fromOffset(0, 0), colors.gold)
		ui.addCorner(fill, 4)
		local shade = ui.makeFrame(card, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
		shade.BackgroundTransparency = 0.5
		shade.ZIndex = 460
		ui.addCorner(shade, 8)
		local tapes = { hazard(ui, card, 0, 461), hazard(ui, card, 1, 461) }
		cards[building.key] = {
			card = card,
			stroke = stroke,
			level = level,
			gain = gain,
			status = status,
			price = price,
			fill = fill,
			shade = shade,
			tapes = tapes,
		}
		card.Activated:Connect(function()
			ui.send("EstateBuild", `{selected}:{building.key}`)
		end)
	end
end

function EstatePage.build(ui)
	local page = ui.pages.Estate
	buildTabs(ui, page)
	buildChips(ui, page)
	buildBanner(ui, page)
	buildCards(ui, page)
	-- The builder bar and countdown move smoothly between updates.
	RunService.Heartbeat:Connect(function()
		if not page.Visible or not timer then
			return
		end
		local left = math.max(0, timer.left - (os.clock() - timer.at))
		w.bannerFill.Size = UDim2.fromScale(if timer.total > 0 then 1 - left / timer.total else 1, 1)
		w.bannerTime.Text = clock(math.ceil(left))
	end)
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

-- "LEVEL UP" rising from a card and a gold flash.
local function levelUp(ui, card, level: number)
	local label = ui.makeText(card.card, UDim2.fromOffset(10, 34), UDim2.new(0, 116, 0.5, 0), AMBER, 24)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.TextWrapped = false
	label.Font = Enum.Font.GothamBlack
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextStrokeTransparency = 0.2
	label.ZIndex = 480
	label.Text = `LEVEL {level}!`
	local scale = Instance.new("UIScale")
	scale.Scale = 0.5
	scale.Parent = label
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.1 }):Play()
	local rise = TweenService:Create(label, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0, 116, 0.2, 0),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	rise:Play()
	rise.Completed:Connect(function()
		label:Destroy()
	end)
	card.stroke.Color = AMBER
	card.stroke.Thickness = 4
	card.stroke.Transparency = 0
	TweenService:Create(card.stroke, TweenInfo.new(0.8), { Thickness = 1.5, Transparency = 0.5 }):Play()
end

local function drawChips(state)
	local stock = state.estate.stock
	local summary = state.estateSummary
	for _, resource in EstateConfig.Resources do
		local chip = chips[resource.key]
		local have = stock[resource.key] or 0
		local cap = summary.caps[resource.key]
		chip.amount.Text = `{Format.short(have)} <font size="14" color="#B2A690">/ {Format.short(cap)}</font>`
		chip.fill.Size = UDim2.fromScale(if cap > 0 then math.min(1, have / cap) else 0, 1)
		chip.full.Visible = have >= cap
		chip.rate.Text = `+{Format.short(summary.rates[resource.key])}/h`
	end
	w.extras.Text = `Hidden Cellar keeps <b>{percent(summary.cellar)}</b> of your stock safe from raids.   Walls and towers: <b>+{percent(summary.defense)}</b> defense.`
end

local function drawBanner(state, ui)
	local colors = ui.colors
	local castleDef = EstateConfig.getCastle(selected)
	local castle = state.estate.castles[selected]
	local building = castle and castle.build.key ~= "" and EstateConfig.getBuilding(castle.build.key)
	-- Picture: the building under construction, else the Keep.
	local pictureKey = if building then building.key else "castle"
	if w.bannerPictureKey ~= pictureKey then
		w.bannerPictureKey = pictureKey
		for _, child in w.bannerPicture:GetChildren() do
			if child.Name == "Picture" then
				child:Destroy()
			end
		end
		local function gate()
			return ui.pages.Estate.Visible
		end
		if building then
			Scenes.building(w.bannerPicture, building.key, gate, 170)
		else
			Scenes.keep(w.bannerPicture, math.max(1, state.keep or 1), gate, 170)
		end
	end
	local busy = building ~= nil
	for _, tape in w.bannerHazard do
		tape.Visible = busy
	end
	w.bannerDim.Visible = busy or not castle
	w.bannerBar.Visible = busy
	w.bannerTime.Visible = busy
	w.bannerButton.Visible = true

	if not castle then
		timer = nil
		local cost = castleDef.cost or {}
		w.bannerTitle.Text = string.upper(castleDef.name)
		w.bannerText.Text = if state.level < castleDef.level
			then `Unlocks at level <b>{castleDef.level}</b>. Comes with its own builder and buildings.\n{priceText(cost, state.gold, state.estate.stock)}`
			else `Claim it to get a second builder and its own buildings.\n{priceText(cost, state.gold, state.estate.stock)}`
		if state.level < castleDef.level then
			ui.setButton(w.bannerButton, `LEVEL {castleDef.level}`, false, colors.buy)
		else
			ui.setButton(w.bannerButton, "CLAIM", EstateConfig.canPay(cost, state.gold, state.estate.stock), colors.buy)
		end
	elseif building then
		local left = state.estateLeft[selected] or 0
		local total = EstateConfig.getSeconds(building, castle.build.level - 1)
		if not timer or math.abs(timer.left - (os.clock() - timer.at) - left) > 1.5 then
			timer = { left = left, total = total, at = os.clock() }
		end
		local finish = ResearchConfig.getFinishCost(left)
		w.bannerTitle.Text = "\u{1F6A7} UNDER CONSTRUCTION"
		w.bannerText.Text = `<b>{building.name}</b> to level {castle.build.level} at {castleDef.name}.\n<font color="#B2A690">It keeps building while you are away.</font>`
		ui.setButton(w.bannerButton, `FINISH NOW\n{finish} Crowns`, state.crowns >= finish, colors.selected)
	else
		timer = nil
		w.bannerTitle.Text = string.upper(castleDef.name)
		w.bannerText.Text = `<font color="#6ED26E"><b>Builder free.</b></font> Press a building below to upgrade it.\n<font color="#B2A690">One upgrade at a time per castle.</font>`
		w.bannerButton.Visible = false
	end
	w.bannerStroke.Color = if busy then AMBER else colors.gold
end

local function drawCards(state, ui)
	local colors = ui.colors
	local castle = state.estate.castles[selected]
	local stock = state.estate.stock
	local busyKey = castle and castle.build.key ~= "" and castle.build.key or nil
	for _, building in EstateConfig.Buildings do
		local card = cards[building.key]
		local level = if castle then castle.levels[building.key] or 0 else 0
		local memo = `{selected}:{building.key}`
		if castle and shownLevels[memo] and level > shownLevels[memo] then
			levelUp(ui, card, level)
		end
		shownLevels[memo] = if castle then level else nil
		card.level.Text = if level > 0 then `LV {level}` else "NOT BUILT"
		card.fill.Size = UDim2.fromScale(level / EstateConfig.MaxLevel, 1)
		local upgrading = busyKey == building.key
		for _, tape in card.tapes do
			tape.Visible = upgrading
		end
		local locked = not castle or state.level < building.level
		card.shade.Visible = locked or upgrading
		if level >= EstateConfig.MaxLevel then
			card.gain.Text = effect(building, level)
			card.status.Text = "MAX LEVEL"
			card.status.TextColor3 = colors.gold
			card.price.Text = ""
			card.stroke.Color = colors.gold
			continue
		end
		card.gain.Text = `{effect(building, level)}  <font color="#B2A690">{ARROW}</font>  {effect(building, level + 1)}`
		local cost = EstateConfig.getCost(building, level)
		local seconds = EstateConfig.getSeconds(building, level)
		card.price.Text = `{priceText(cost, state.gold, stock)}\n<font color="#7FB4F0">{CLOCK} {clock(seconds)}</font>`
		local canPay = EstateConfig.canPay(cost, state.gold, stock)
		if not castle then
			card.status.Text = "CLAIM THIS CASTLE FIRST"
			card.status.TextColor3 = colors.dim
		elseif state.level < building.level then
			card.status.Text = `UNLOCKS AT LEVEL {building.level}`
			card.status.TextColor3 = colors.dim
		elseif upgrading then
			card.status.Text = `UPGRADING TO LV {castle.build.level}...`
			card.status.TextColor3 = AMBER
		elseif busyKey then
			card.status.Text = "BUILDER BUSY"
			card.status.TextColor3 = AMBER
		elseif canPay then
			card.status.Text = if level == 0 then "PRESS TO BUILD" else "PRESS TO UPGRADE"
			card.status.TextColor3 = GREEN
		else
			card.status.Text = "NOT ENOUGH RESOURCES"
			card.status.TextColor3 = Color3.fromRGB(220, 110, 90)
		end
		card.stroke.Color = if castle and not locked and not busyKey and canPay then colors.gold else colors.dim
	end
end

function EstatePage.draw(state, ui)
	if not state then
		return
	end
	latest = state
	local colors = ui.colors
	for _, castle in EstateConfig.Castles do
		local tab = tabs[castle.key]
		local owned = state.estate.castles[castle.key] ~= nil
		local on = castle.key == selected
		tab.button.Text = if owned or state.level >= castle.level then string.upper(castle.name) else `{string.upper(castle.name)}  {LOCK}{castle.level}`
		tab.button.TextColor3 = if on then colors.text else colors.dim
		tab.line.Visible = on
	end
	drawChips(state)
	drawBanner(state, ui)
	drawCards(state, ui)
end

return EstatePage
