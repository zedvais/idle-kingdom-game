-- Holdings page, two tabs:
--   * YOUR LANDS: one picture card for every holding you have built, with
--     what it earns per hour (all bonuses in). Press a card to build
--     another copy or demolish one.
--   * BUILD: a banner per region (levels it covers, +/- to fold it), and
--     under it a card per holding: picture, income per lot, level and
--     price. Press a card to build it.
-- Above both: total income (with the bonus and offline rate), the Golden
-- Ledger pass (2x income) and lots used, with the next lot's price.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local StoreConfig = require(Shared:WaitForChild("StoreConfig"))
local Format = require(Shared:WaitForChild("Format"))
local Scenes = require(script.Parent:WaitForChild("Scenes"))
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local HoldingsPage = {}

local GREEN = Color3.fromRGB(110, 210, 110)
local REGION_COLORS = {
	Oakvale = Color3.fromRGB(86, 140, 70),
	Greywatch = Color3.fromRGB(80, 110, 150),
	Emberreach = Color3.fromRGB(180, 80, 50),
}

local w = {} -- widgets
local tab = "lands"
local tabChosen = false
local landCards = {} -- pooled cards on YOUR LANDS
local buildCards = {} -- [holding id] = card on BUILD
local regionParts = {} -- [region id] = { banner, toggle, grid, open, levelText }
local regionsOpened = false
local latest = nil
local shownHolding = nil -- the holding the popup shows
local drawBonusNow -- set below: fills the income bonus popup
local timers = {} -- [holding id] = { base = seconds into the cycle, at = os.clock() }

local function holdingById(id: string)
	for _, holding in GameConfig.Holdings do
		if holding.id == id then
			return holding
		end
	end
	return nil
end

-- Gold per hour for one copy, with every bonus.
local function perCopy(state, holding): number
	local stats = state.stats
	return math.floor(holding.income * (1 + (stats.incomeBonus or stats.keepBonus or 0)) * (stats.incomeMultiplier or 1))
end

local function lotsSkill()
	for _, skill in GameConfig.Skills do
		if skill.id == "lots" then
			return skill
		end
	end
	return nil
end

local function percentText(value: number): string
	return `{math.floor(value * 100 + 0.5)}%`
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

local function chip(ui, parent: Instance, index: number, title: string)
	local colors = ui.colors
	local frame = ui.makeFrame(parent, UDim2.new(1 / 3, -8, 1, 0), UDim2.new((index - 1) / 3, (index - 1) * 4, 0, 0), Color3.fromRGB(30, 25, 20))
	ui.addCorner(frame, 8)
	ui.art.stroke(frame, colors.dim, 1, 0.6)
	local label = ui.makeText(frame, UDim2.new(1, -20, 0, 18), UDim2.fromOffset(14, 8), colors.dim, 13)
	label.Font = Enum.Font.GothamBold
	label.Text = title
	return frame
end

local function pill(ui, parent: Instance, position: UDim2, width: number): TextButton
	local button = ui.makeButton(parent, UDim2.fromOffset(width, 24), position, Color3.fromRGB(22, 18, 14))
	button.TextSize = 12
	button.Font = Enum.Font.GothamMedium
	button.TextColor3 = ui.colors.text
	ui.art.stroke(button, ui.colors.dim, 1, 0.5)
	return button
end

local function buildHeader(ui, page: Instance)
	local colors = ui.colors
	-- Tabs.
	local bar = ui.makeFrame(page, UDim2.new(1, -10, 0, 52), UDim2.fromOffset(0, 0), Color3.fromRGB(44, 36, 22))
	bar.LayoutOrder = 1
	ui.addCorner(bar, 6)
	ui.art.stroke(bar, colors.gold, 1.5, 0.4)
	w.tabs = {}
	for index, info in { { "lands", "YOUR LANDS" }, { "build", "BUILD" } } do
		local button = ui.makeButton(bar, UDim2.fromOffset(170, 44), UDim2.fromOffset(10 + (index - 1) * 180, 4), Color3.new(0, 0, 0))
		button.BackgroundTransparency = 1
		button.TextSize = 20
		button.Text = info[2]
		button:SetAttribute("NoGlow", true)
		local line = ui.makeFrame(button, UDim2.new(1, -20, 0, 3), UDim2.new(0, 10, 1, -3), colors.gold)
		w.tabs[info[1]] = { button = button, line = line }
		button.Activated:Connect(function()
			tab = info[1]
			tabChosen = true
			HoldingsPage.draw(latest, ui)
		end)
	end

	-- Chips: income, Golden Ledger, lots.
	local row = ui.makeFrame(page, UDim2.new(1, -10, 0, 112), UDim2.fromOffset(0, 0), colors.panel)
	row.BackgroundTransparency = 1
	row.LayoutOrder = 2

	local income = chip(ui, row, 1, "INCOME")
	w.income = ui.makeText(income, UDim2.new(1, -20, 0, 40), UDim2.fromOffset(14, 28), GREEN, 32)
	w.income.Font = Enum.Font.GothamBlack
	w.bonus = pill(ui, income, UDim2.fromOffset(14, 76), 120)
	w.bonus.Activated:Connect(function()
		if latest then
			drawBonusNow(latest)
		end
		ui.openModal("IncomeBonus", "Income bonus")
	end)
	w.offline = pill(ui, income, UDim2.fromOffset(142, 76), 150)
	w.offline.AutoButtonColor = false
	w.offline:SetAttribute("NoGlow", true)

	local ledger = chip(ui, row, 2, "GOLDEN LEDGER")
	local coin = ui.art.icon(ledger, ui.art.Icons.gold, 52, UDim2.fromOffset(14, 34))
	coin.ZIndex = ledger.ZIndex + 1
	w.ledger = ui.makeText(ledger, UDim2.new(1, -90, 0, 36), UDim2.fromOffset(78, 28), colors.gold, 28)
	w.ledger.Font = Enum.Font.GothamBlack
	w.ledgerNote = ui.makeText(ledger, UDim2.new(1, -90, 0, 18), UDim2.fromOffset(78, 64), colors.dim, 12)
	w.ledgerButton = ui.makeButton(ledger, UDim2.fromOffset(110, 26), UDim2.new(1, -122, 0, 6), colors.gold)
	w.ledgerButton.TextSize = 12
	w.ledgerButton.Activated:Connect(function()
		if ui.offerPass then
			ui.offerPass("doubleincome")
		end
	end)

	local lots = chip(ui, row, 3, "LOTS")
	w.lots = ui.makeText(lots, UDim2.new(1, -20, 0, 36), UDim2.fromOffset(14, 26), colors.gold, 30)
	w.lots.Font = Enum.Font.GothamBlack
	w.lotsFull = ui.makeText(lots, UDim2.fromOffset(60, 22), UDim2.new(1, -72, 0, 8), colors.gold, 12)
	w.lotsFull.Font = Enum.Font.GothamBold
	w.lotsFull.TextXAlignment = Enum.TextXAlignment.Center
	w.lotsFull.Text = "FULL"
	ui.art.stroke(w.lotsFull, colors.gold, 1, 0.2)
	w.lotsBar = ui.makeFrame(lots, UDim2.new(1, -28, 0, 14), UDim2.fromOffset(14, 66), Color3.fromRGB(18, 14, 10))
	ui.addCorner(w.lotsBar, 3)
	w.lotsFill = ui.makeFrame(w.lotsBar, UDim2.fromScale(0, 1), UDim2.fromOffset(0, 0), colors.gold)
	ui.addCorner(w.lotsFill, 3)
	w.lotsSegments = {}
	w.lotsNext = ui.makeText(lots, UDim2.new(1, -20, 0, 18), UDim2.fromOffset(14, 86), colors.dim, 12)
	w.lotsNext.RichText = true
end

-- One picture card on YOUR LANDS (made when first needed).
local function landCard(ui, index: number)
	local card = landCards[index]
	if card then
		return card
	end
	local colors = ui.colors
	local frame = ui.makeButton(w.landsGrid, UDim2.fromOffset(100, 100), UDim2.fromOffset(0, 0), Color3.fromRGB(40, 32, 24))
	frame.LayoutOrder = index
	frame.Text = ""
	frame.ClipsDescendants = true
	ui.addCorner(frame, 8)
	local stroke = ui.art.stroke(frame, colors.gold, 1.5, 0.5)
	local picture = ui.makeFrame(frame, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), colors.panel)
	picture.BackgroundTransparency = 1
	local name = ui.makeText(frame, UDim2.fromOffset(10, 30), UDim2.new(0.5, 0, 0, 10), colors.text, 17)
	name.AnchorPoint = Vector2.new(0.5, 0)
	name.AutomaticSize = Enum.AutomaticSize.X
	name.TextWrapped = false
	name.Font = Enum.Font.GothamBold
	name.TextXAlignment = Enum.TextXAlignment.Center
	name.BackgroundTransparency = 0.15
	name.BackgroundColor3 = Color3.fromRGB(26, 20, 16)
	name.ZIndex = 50
	ui.addCorner(name, 4)
	local namePad = Instance.new("UIPadding")
	namePad.PaddingLeft = UDim.new(0, 10)
	namePad.PaddingRight = UDim.new(0, 10)
	namePad.Parent = name
	local income = ui.makeText(frame, UDim2.fromOffset(10, 30), UDim2.new(0.5, 0, 1, -50), GREEN, 18)
	income.AnchorPoint = Vector2.new(0.5, 0)
	income.AutomaticSize = Enum.AutomaticSize.X
	income.TextWrapped = false
	income.Font = Enum.Font.GothamBlack
	income.TextXAlignment = Enum.TextXAlignment.Center
	income.BackgroundTransparency = 0.15
	income.BackgroundColor3 = Color3.fromRGB(26, 20, 16)
	income.ZIndex = 50
	ui.addCorner(income, 4)
	local incomePad = Instance.new("UIPadding")
	incomePad.PaddingLeft = UDim.new(0, 12)
	incomePad.PaddingRight = UDim.new(0, 12)
	incomePad.Parent = income
	-- The pay cycle: fills up, then the holding pays.
	local bar = ui.makeFrame(frame, UDim2.new(0.5, 0, 0, 8), UDim2.new(0.25, 0, 1, -16), Color3.fromRGB(20, 16, 12))
	bar.ZIndex = 50
	ui.addCorner(bar, 4)
	ui.art.stroke(bar, Color3.fromRGB(20, 16, 12), 1.5, 0)
	local fill = ui.makeFrame(bar, UDim2.fromScale(0, 1), UDim2.fromOffset(0, 0), GREEN)
	fill.ZIndex = 51
	ui.addCorner(fill, 4)
	card = { frame = frame, picture = picture, name = name, income = income, bar = bar, fill = fill, stroke = stroke, id = nil }
	frame.Activated:Connect(function()
		if card.id then
			shownHolding = card.id
			HoldingsPage.drawPopup(latest, ui)
			ui.openModal("Holding", "Holding")
		end
	end)
	landCards[index] = card
	return card
end

local function buildBuildTab(ui, page: Instance)
	local colors = ui.colors
	w.build = ui.makeFrame(page, UDim2.new(1, -10, 0, 0), UDim2.fromOffset(0, 0), colors.panel)
	w.build.BackgroundTransparency = 1
	w.build.AutomaticSize = Enum.AutomaticSize.Y
	w.build.LayoutOrder = 4
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = w.build

	local function gateBuild(): boolean
		return page.Visible and tab == "build"
	end

	for index, region in GameConfig.Regions do
		local color = REGION_COLORS[region.id] or colors.dim
		local banner = ui.makeButton(w.build, UDim2.new(1, 0, 0, 96), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1))
		banner.LayoutOrder = index * 2 - 1
		banner.Text = ""
		banner.ClipsDescendants = true
		banner:SetAttribute("NoGlow", true)
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new(Color3.fromRGB(24, 20, 16), ui.art.shade(color, -0.35))
		gradient.Parent = banner
		ui.art.skyline(banner, Color3.new(0, 0, 0), 0.6)
		ui.art.stroke(banner, colors.gold, 1.5, 0.45)
		local accent = ui.makeFrame(banner, UDim2.new(1, 0, 0, 4), UDim2.new(0, 0, 1, -4), color)
		accent.ZIndex = banner.ZIndex + 2
		local name = ui.makeText(banner, UDim2.new(0.5, 0, 1, 0), UDim2.fromOffset(28, 0), colors.gold, 48)
		name.Font = ui.art.Fonts.title
		name.Text = string.upper(region.id)
		name.ZIndex = banner.ZIndex + 2
		local levels = ui.makeText(banner, UDim2.new(0.5, -120, 1, 0), UDim2.new(0.5, 0, 0, 0), colors.text, 24)
		levels.Font = Enum.Font.GothamBlack
		levels.TextXAlignment = Enum.TextXAlignment.Right
		levels.TextTransparency = 0.15
		levels.ZIndex = banner.ZIndex + 2
		local toggle = ui.makeText(banner, UDim2.fromOffset(70, 70), UDim2.new(1, -86, 0, 13), colors.gold, 44)
		toggle.Font = Enum.Font.GothamBlack
		toggle.TextXAlignment = Enum.TextXAlignment.Center
		toggle.BackgroundColor3 = Color3.fromRGB(20, 16, 12)
		toggle.BackgroundTransparency = 0.2
		toggle.ZIndex = banner.ZIndex + 2
		ui.art.stroke(toggle, colors.gold, 2, 0)

		local grid = ui.makeFrame(w.build, UDim2.new(1, 0, 0, 0), UDim2.fromOffset(0, 0), colors.panel)
		grid.BackgroundTransparency = 1
		grid.AutomaticSize = Enum.AutomaticSize.Y
		grid.LayoutOrder = index * 2
		local layout = Instance.new("UIGridLayout")
		layout.CellPadding = UDim2.fromOffset(10, 10)
		layout.CellSize = UDim2.new(0.5, -6, 0, 170)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = grid

		local nextRegion = GameConfig.Regions[index + 1]
		local part = {
			banner = banner,
			toggle = toggle,
			grid = grid,
			open = false,
			region = region,
			levels = levels,
			toLevel = if nextRegion then nextRegion.level - 1 else nil,
		}
		regionParts[region.id] = part
		banner.Activated:Connect(function()
			part.open = not part.open
			HoldingsPage.draw(latest, ui)
		end)

		for order, holding in GameConfig.Holdings do
			if holding.region == region.id then
				local card = ui.makeButton(grid, UDim2.fromOffset(100, 100), UDim2.fromOffset(0, 0), Color3.fromRGB(36, 30, 24))
				card.LayoutOrder = order
				card.Text = ""
				card.AutoButtonColor = true
				ui.addCorner(card, 8)
				local stroke = ui.art.stroke(card, colors.dim, 1.5, 0.5)
				local picture = ui.makeFrame(card, UDim2.new(0, 220, 1, -12), UDim2.fromOffset(6, 6), Color3.fromRGB(20, 16, 12))
				ui.addCorner(picture, 6)
				picture.ClipsDescendants = true
				Scenes.holding(picture, holding.id, gateBuild, 165)
				local nameText = ui.makeText(card, UDim2.new(1, -244, 0, 32), UDim2.fromOffset(238, 12), colors.text, 24)
				nameText.Font = Enum.Font.GothamBold
				nameText.Text = holding.name
				nameText.TextTruncate = Enum.TextTruncate.AtEnd
				nameText.TextWrapped = false
				local incomeText = ui.makeText(card, UDim2.new(1, -244, 0, 28), UDim2.fromOffset(238, 48), GREEN, 20)
				incomeText.Font = Enum.Font.GothamBlack
				local status = ui.makeText(card, UDim2.new(1, -244, 0, 24), UDim2.fromOffset(238, 86), colors.dim, 16)
				status.Font = Enum.Font.GothamBold
				local cost = ui.makeText(card, UDim2.new(1, -244, 0, 28), UDim2.fromOffset(238, 118), colors.text, 20)
				cost.RichText = true
				-- Darkens the card while it is locked.
				local shade = ui.makeFrame(card, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
				shade.BackgroundTransparency = 0.5
				shade.ZIndex = 60
				ui.addCorner(shade, 8)
				buildCards[holding.id] = { card = card, stroke = stroke, income = incomeText, status = status, cost = cost, shade = shade }
				card.Activated:Connect(function()
					local state = latest
					if state and state.level >= holding.level then
						ui.send("Holding", holding.id)
					end
				end)
			end
		end
	end
end

local function buildPopups(ui)
	local colors = ui.colors
	-- One holding: picture, numbers, build another or demolish one.
	local page = ui.pages.Holding
	local picture = ui.makeFrame(page, UDim2.new(1, -10, 0, 190), UDim2.fromOffset(0, 0), Color3.fromRGB(20, 16, 12))
	picture.LayoutOrder = 1
	picture.ClipsDescendants = true
	ui.addCorner(picture, 8)
	w.popupPicture = picture
	w.popupName = ui.makeText(page, UDim2.new(1, -10, 0, 30), UDim2.fromOffset(0, 0), colors.gold, 24)
	w.popupName.LayoutOrder = 2
	w.popupName.Font = Enum.Font.GothamBold
	w.popupName.TextXAlignment = Enum.TextXAlignment.Center
	w.popupInfo = ui.makeText(page, UDim2.new(1, -10, 0, 70), UDim2.fromOffset(0, 0), colors.text, 15)
	w.popupInfo.LayoutOrder = 3
	w.popupInfo.RichText = true
	w.popupInfo.TextXAlignment = Enum.TextXAlignment.Center
	local buttons = ui.makeFrame(page, UDim2.new(1, -10, 0, 52), UDim2.fromOffset(0, 0), colors.panel)
	buttons.BackgroundTransparency = 1
	buttons.LayoutOrder = 4
	w.popupDemolish = ui.makeButton(buttons, UDim2.new(0.5, -4, 1, 0), UDim2.fromOffset(0, 0), colors.disabled)
	w.popupDemolish.TextSize = 15
	w.popupBuild = ui.makeButton(buttons, UDim2.new(0.5, -4, 1, 0), UDim2.new(0.5, 4, 0, 0), colors.buy)
	w.popupBuild.TextSize = 15
	w.popupDemolish.Activated:Connect(function()
		if shownHolding then
			ui.send("Demolish", shownHolding)
		end
	end)
	w.popupBuild.Activated:Connect(function()
		if shownHolding then
			ui.send("Holding", shownHolding)
		end
	end)

	-- Where the income bonus comes from.
	local bonusPage = ui.pages.IncomeBonus
	w.bonusList = ui.makeText(bonusPage, UDim2.new(1, -10, 0, 300), UDim2.fromOffset(0, 0), colors.text, 17)
	w.bonusList.LayoutOrder = 1
	w.bonusList.RichText = true
	w.bonusList.TextYAlignment = Enum.TextYAlignment.Top
end

function HoldingsPage.build(ui)
	local page = ui.pages.Holdings
	buildHeader(ui, page)

	-- YOUR LANDS grid.
	w.lands = ui.makeFrame(page, UDim2.new(1, -10, 0, 0), UDim2.fromOffset(0, 0), ui.colors.panel)
	w.lands.BackgroundTransparency = 1
	w.lands.AutomaticSize = Enum.AutomaticSize.Y
	w.lands.LayoutOrder = 3
	w.landsEmpty = ui.makeText(w.lands, UDim2.new(1, 0, 0, 60), UDim2.fromOffset(0, 0), ui.colors.dim, 16)
	w.landsEmpty.TextXAlignment = Enum.TextXAlignment.Center
	w.landsEmpty.Text = "Nothing built yet. Open BUILD to build your first holding."
	w.landsGrid = ui.makeFrame(w.lands, UDim2.new(1, 0, 0, 0), UDim2.fromOffset(0, 0), ui.colors.panel)
	w.landsGrid.BackgroundTransparency = 1
	w.landsGrid.AutomaticSize = Enum.AutomaticSize.Y
	local layout = Instance.new("UIGridLayout")
	layout.CellPadding = UDim2.fromOffset(12, 12)
	layout.CellSize = UDim2.new(1 / 3, -8, 0, 240)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = w.landsGrid
	w.gateLands = function(): boolean
		return page.Visible and tab == "lands"
	end

	buildBuildTab(ui, page)
	buildPopups(ui)

	-- Cycle bars move smoothly between server updates.
	RunService.Heartbeat:Connect(function()
		if not w.gateLands() then
			return
		end
		local now = os.clock()
		for _, card in landCards do
			if card.frame.Visible and card.id then
				local holding = holdingById(card.id)
				local timer = timers[card.id]
				local cycle = (holding and holding.cycle) or 60
				local elapsed = if timer then timer.base + (now - timer.at) else 0
				card.fill.Size = UDim2.fromScale(math.clamp(elapsed / cycle, 0, 1), 1)
			end
		end
	end)

	-- A holding paid: "+gold" rises from each of its cards.
	local Fx = require(script.Parent:WaitForChild("Fx"))
	Fx.onIncome = function(info)
		timers[info.id] = { base = 0, at = os.clock() }
		if not w.gateLands() then
			return
		end
		for _, card in landCards do
			if card.frame.Visible and card.id == info.id then
				HoldingsPage.pop(ui, card, tonumber(info.amount) or 0)
			end
		end
	end
end

-- "+amount gold" floating up from a card, and a quick gold flash.
function HoldingsPage.pop(ui, card, amount: number)
	local label = ui.makeText(card.frame, UDim2.fromOffset(10, 34), UDim2.new(0.5, 0, 0.55, 0), ui.colors.gold, 26)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.TextWrapped = false
	label.Font = Enum.Font.GothamBlack
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextStrokeTransparency = 0.2
	label.TextStrokeColor3 = Color3.fromRGB(40, 28, 12)
	label.ZIndex = 80
	label.Text = `+{Format.short(amount)} {ui.art.Icons.gold}`
	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = label
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	local rise = TweenService:Create(label, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0.25, 0),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	rise:Play()
	rise.Completed:Connect(function()
		label:Destroy()
	end)
	card.stroke.Thickness = 4
	card.stroke.Transparency = 0
	card.fill.Size = UDim2.fromScale(1, 1)
	TweenService:Create(card.stroke, TweenInfo.new(0.6), { Thickness = 1.5, Transparency = 0.5 }):Play()
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function drawHeader(state, ui)
	local colors = ui.colors
	local stats = state.stats
	for key, part in w.tabs do
		local on = key == tab
		part.line.Visible = on
		part.button.TextColor3 = if on then colors.text else colors.dim
	end

	w.income.Text = `{Format.short(stats.incomePerHour)}/hr`
	w.bonus.Text = `+{percentText(stats.incomeBonus or stats.keepBonus or 0)} bonus`
	local nightwatch = state.passes and state.passes.nightwatch
	w.offline.Text = if nightwatch then "100% while away" else `{percentText(GameConfig.OfflineRate)} while away`

	local doubled = (stats.incomeMultiplier or 1) > 1
	w.ledger.Text = if doubled then "2x INCOME" else "1x income"
	w.ledgerNote.Text = if doubled then "Golden Ledger: every holding pays double" else "Golden Ledger pass doubles all holding income"
	w.ledgerButton.Visible = not doubled
	local pass = StoreConfig.getPass and StoreConfig.getPass("doubleincome")
	ui.setButton(w.ledgerButton, if pass then `GET 2x  R$ {pass.price}` else "GET 2x", true, colors.gold)

	local lots, used = stats.lots, stats.lotsUsed
	w.lots.Text = `{used} / {lots}`
	w.lotsFull.Visible = used >= lots
	-- Up to 40 lots show as blocks, more as one bar.
	local blocks = lots <= 40
	w.lotsFill.Visible = not blocks
	w.lotsFill.Size = UDim2.fromScale(if lots > 0 then math.min(1, used / lots) else 0, 1)
	for index = 1, math.max(lots, #w.lotsSegments) do
		local segment = w.lotsSegments[index]
		if index <= lots and blocks then
			if not segment then
				segment = ui.makeFrame(w.lotsBar, UDim2.fromScale(0, 1), UDim2.fromOffset(0, 0), colors.gold)
				ui.addCorner(segment, 2)
				w.lotsSegments[index] = segment
			end
			segment.Visible = true
			segment.Size = UDim2.new(1 / lots, -2, 1, 0)
			segment.Position = UDim2.new((index - 1) / lots, 1, 0, 0)
			segment.BackgroundColor3 = if index <= used then colors.gold else Color3.fromRGB(70, 58, 40)
		elseif segment then
			segment.Visible = false
		end
	end
	local skill = lotsSkill()
	if skill then
		local price = GameConfig.getSkillCost(skill, (state.skills and state.skills.lots) or 0)
		w.lotsNext.Text = `Next lot: <font color="#F0C450">{price} skill points</font> (Keep skills)`
	end
end

local function drawLands(state, ui)
	-- One card per copy, best holdings first.
	local index = 0
	for position = #GameConfig.Holdings, 1, -1 do
		local holding = GameConfig.Holdings[position]
		local count = state.holdings[holding.id] or 0
		local income = perCopy(state, holding)
		for _ = 1, count do
			index += 1
			local card = landCard(ui, index)
			card.frame.Visible = true
			if card.id ~= holding.id then
				card.id = holding.id
				card.picture:ClearAllChildren()
				Scenes.holding(card.picture, holding.id, w.gateLands, 180)
				card.name.Text = holding.name
			end
			card.income.Text = `{Format.short(income)}/hr`
		end
	end
	for extra = index + 1, #landCards do
		landCards[extra].frame.Visible = false
	end
	w.landsEmpty.Visible = index == 0
end

local function drawBuild(state, ui)
	local colors = ui.colors
	local stats = state.stats
	local lotsFull = stats.lotsUsed >= stats.lots
	-- First time: open the newest unlocked region and the next locked one.
	if not regionsOpened then
		regionsOpened = true
		local newest, nextLocked = nil, nil
		for _, region in GameConfig.Regions do
			if state.level >= region.level then
				newest = region.id
			elseif not nextLocked then
				nextLocked = region.id
			end
		end
		for id, part in regionParts do
			part.open = id == newest or id == nextLocked
		end
	end
	for _, part in regionParts do
		local region = part.region
		part.toggle.Text = if part.open then "-" else "+"
		part.grid.Visible = part.open
		if state.level < region.level then
			part.levels.Text = `UNLOCKS AT LEVEL {region.level}`
		elseif part.toLevel then
			part.levels.Text = `LEVELS {region.level} TO {part.toLevel}`
		else
			part.levels.Text = `LEVEL {region.level}+`
		end
	end
	for _, holding in GameConfig.Holdings do
		local card = buildCards[holding.id]
		local count = state.holdings[holding.id] or 0
		local price = GameConfig.getHoldingCost(holding, count)
		local locked = state.level < holding.level
		card.shade.Visible = locked
		card.income.Text = `+{Format.short(perCopy(state, holding))}/hr per lot`
		if locked then
			card.status.Text = `UNLOCKS AT LEVEL {holding.level}`
			card.status.TextColor3 = colors.dim
		elseif lotsFull then
			card.status.Text = `LOTS FULL  ·  YOU HAVE {count}`
			card.status.TextColor3 = Color3.fromRGB(220, 110, 90)
		else
			card.status.Text = if count > 0 then `YOU HAVE {count}` else "NOT BUILT YET"
			card.status.TextColor3 = colors.dim
		end
		local affordable = state.gold >= price
		local priceColor = if affordable then "#6ED26E" else "#DC6E5A"
		card.cost.Text = `<font color="{priceColor}"><b>{Format.short(price)}</b></font> gold to build`
		card.stroke.Color = if not locked and not lotsFull and affordable then colors.gold else colors.dim
	end
end

function HoldingsPage.drawPopup(state, ui)
	if not state or not shownHolding then
		return
	end
	local holding = holdingById(shownHolding)
	if not holding then
		return
	end
	local colors = ui.colors
	if w.popupPicture:GetAttribute("Holding") ~= holding.id then
		w.popupPicture:SetAttribute("Holding", holding.id)
		w.popupPicture:ClearAllChildren()
		ui.addCorner(w.popupPicture, 8)
		Scenes.holding(w.popupPicture, holding.id, function()
			return ui.isOpen("Holding")
		end, 260)
	end
	local count = state.holdings[holding.id] or 0
	local income = perCopy(state, holding)
	w.popupName.Text = holding.name
	w.popupInfo.Text = `<font color="#6ED26E"><b>{Format.short(income)} gold/hr</b></font> each, with your bonuses\n`
		.. `Pays <b>{Format.short(math.floor(income / 3600 * (holding.cycle or 60)))} gold</b> each every {holding.cycle or 60} s. You have {count}, `
		.. `<b>{Format.short(income * count)} gold/hr</b> together\n`
		.. `<font color="#B2A690">{holding.region}, from level {holding.level}</font>`
	local price = GameConfig.getHoldingCost(holding, count)
	local stats = state.stats
	local canBuild = state.level >= holding.level and stats.lotsUsed < stats.lots and state.gold >= price
	ui.setButton(w.popupBuild, `BUILD ANOTHER\n{Format.short(price)}`, canBuild, colors.buy)
	if count > 0 then
		local refund = math.floor(GameConfig.getHoldingCost(holding, count - 1) * GameConfig.DemolishRefund)
		ui.setButton(w.popupDemolish, `DEMOLISH 1\n+{Format.short(refund)} back`, true, Color3.fromRGB(120, 40, 36))
	else
		ui.setButton(w.popupDemolish, "DEMOLISH 1", false, colors.disabled)
	end
end

function drawBonusNow(state)
	local stats = state.stats
	local lines = {}
	for _, part in stats.incomeParts or {} do
		local name, value = part[1], part[2]
		local color = if value > 0 then "#6ED26E" else "#7A6E5E"
		table.insert(lines, `<font color="{color}"><b>+{percentText(value)}</b></font>  {name}`)
	end
	table.insert(lines, `\n<b>Total bonus: +{percentText(stats.incomeBonus or 0)}</b>`)
	if (stats.incomeMultiplier or 1) > 1 then
		table.insert(lines, `<font color="#F0C450"><b>x{stats.incomeMultiplier}</b></font>  Golden Ledger, after the bonus`)
	else
		table.insert(lines, `<font color="#7A6E5E">x2 with the Golden Ledger pass</font>`)
	end
	w.bonusList.Text = table.concat(lines, "\n")
end

function HoldingsPage.draw(state, ui)
	if not state then
		return
	end
	latest = state
	-- Where each pay cycle is, from the server.
	local now = os.clock()
	for id, seconds in state.holdingTimers or {} do
		local timer = timers[id]
		local guess = if timer then timer.base + (now - timer.at) else -1
		-- Only snap when the bar has drifted (avoids jitter every second).
		if math.abs(guess - seconds) > 1.5 then
			timers[id] = { base = seconds, at = now }
		end
	end
	if not tabChosen then
		local any = false
		for _, count in state.holdings do
			if count > 0 then
				any = true
			end
		end
		tab = if any then "lands" else "build"
	end
	w.lands.Visible = tab == "lands"
	w.build.Visible = tab == "build"
	drawHeader(state, ui)
	if tab == "lands" then
		drawLands(state, ui)
	else
		drawBuild(state, ui)
	end
	if ui.isOpen("Holding") then
		HoldingsPage.drawPopup(state, ui)
	end
	if ui.isOpen("IncomeBonus") then
		drawBonusNow(state)
	end
end

return HoldingsPage
