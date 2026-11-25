-- Market page:
--   * a stall banner: awning stripes, the restock bar and countdown, the
--     festival discount (if any) and the AUTO-BUY button,
--   * the stock as item cards (picture, name, stats, rarity band, price
--     and BUY). Cards flip in one by one when new stock arrives; a bought
--     card gets a SOLD stamp.
--   * an auto-buy strip with the last pieces it bought.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Format = require(Shared:WaitForChild("Format"))
local ChestConfig = require(Shared:WaitForChild("ChestConfig"))
local FestivalConfig = require(Shared:WaitForChild("FestivalConfig"))

local MarketPage = {}

local GOLD = Color3.fromRGB(240, 196, 80)
local GREEN = Color3.fromRGB(120, 220, 120)
local STRIPES = { Color3.fromRGB(180, 50, 50), Color3.fromRGB(236, 226, 200) }

local w = {}
local cards = {}
local recentTiles = {}
local latest = nil
local windowShown = nil
local soldShown = {} -- [index] = true once the SOLD stamp played
local restock = { left = 0, at = 0 }

local function discount(state, kind: string): number
	local festival = FestivalConfig.getFestival(state.festival.week)
	return if festival.bonus.kind == kind then festival.bonus.amount else 0
end

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function buildBanner(ui, page: Instance)
	local colors = ui.colors
	local banner = ui.makeFrame(page, UDim2.new(1, -10, 0, 120), UDim2.fromOffset(0, 0), Color3.fromRGB(54, 40, 26))
	banner.LayoutOrder = 1
	banner.ClipsDescendants = true
	ui.addCorner(banner, 10)
	ui.art.stroke(banner, colors.gold, 2, 0.2)
	ui.art.grain(banner)
	-- Awning: stripes with a scalloped edge.
	local awning = ui.makeFrame(banner, UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	awning.BackgroundTransparency = 1
	for index = 0, 39 do
		local stripe = ui.makeFrame(awning, UDim2.new(1 / 40, 1, 1, 0), UDim2.new(index / 40, 0, 0, 0), STRIPES[index % 2 + 1])
		local scallop = ui.makeFrame(stripe, UDim2.new(1, 0, 0, 12), UDim2.new(0, 0, 1, -6), STRIPES[index % 2 + 1])
		ui.addCorner(scallop, 6)
	end
	w.awning = awning

	local title = ui.makeText(banner, UDim2.fromOffset(260, 50), UDim2.fromOffset(20, 40), colors.gold, 40)
	title.Font = ui.art.Fonts.title
	title.Text = "The Market"
	title.TextStrokeTransparency = 0.4
	w.discount = ui.makeText(banner, UDim2.fromOffset(260, 22), UDim2.fromOffset(22, 88), GREEN, 14)
	w.discount.Font = Enum.Font.GothamBlack

	-- Restock bar.
	local label = ui.makeText(banner, UDim2.new(0.36, 0, 0, 20), UDim2.new(0.32, 0, 0, 44), colors.text, 14)
	label.Font = Enum.Font.GothamBlack
	label.Text = "NEW STOCK IN"
	w.clock = ui.makeText(banner, UDim2.new(0.36, 0, 0, 20), UDim2.new(0.32, 0, 0, 44), GOLD, 16)
	w.clock.Font = Enum.Font.GothamBlack
	w.clock.TextXAlignment = Enum.TextXAlignment.Right
	local back = ui.makeFrame(banner, UDim2.new(0.36, 0, 0, 24), UDim2.new(0.32, 0, 0, 70), Color3.fromRGB(20, 16, 12))
	ui.addCorner(back, 8)
	local fill = ui.makeFrame(back, UDim2.fromScale(0, 1), UDim2.fromOffset(0, 0), GOLD)
	ui.addCorner(fill, 8)
	ui.art.gloss(fill, 1, 0.6)
	w.fill = fill

	w.auto = ui.makeButton(banner, UDim2.new(0.26, 0, 0, 56), UDim2.new(0.72, 0, 0, 44), Color3.fromRGB(30, 24, 16))
	w.auto.TextSize = 18
	w.auto.Font = Enum.Font.GothamBlack
	ui.art.stroke(w.auto, colors.gold, 2, 0)
	w.auto.Activated:Connect(function()
		local state = latest
		if state and state.passes.autobuy then
			ui.openAutoBuy()
		elseif ui.offerPass then
			ui.offerPass("autobuy")
		end
	end)
end

local function buildCard(ui, parent: Instance, index: number)
	local colors = ui.colors
	local card = ui.makeFrame(parent, UDim2.fromOffset(100, 100), UDim2.fromOffset(0, 0), Color3.fromRGB(30, 27, 24))
	card.LayoutOrder = index
	card.ClipsDescendants = true
	ui.addCorner(card, 8)
	local stroke = ui.art.stroke(card, colors.gold, 2.5, 0)
	local scale = Instance.new("UIScale")
	scale.Parent = card
	local kind = ui.makeText(card, UDim2.new(1, -20, 0, 20), UDim2.fromOffset(12, 8), colors.dim, 12)
	kind.Font = Enum.Font.GothamBlack
	local level = ui.makeText(card, UDim2.new(1, -20, 0, 20), UDim2.fromOffset(8, 8), colors.dim, 12)
	level.Font = Enum.Font.GothamBlack
	level.TextXAlignment = Enum.TextXAlignment.Right
	local back = ui.makeFrame(card, UDim2.new(1, -20, 0, 120), UDim2.fromOffset(10, 30), Color3.fromRGB(22, 20, 18))
	ui.addCorner(back, 6)
	local picture = ui.makeFrame(back, UDim2.fromOffset(110, 110), UDim2.new(0.5, -55, 0, 5), Color3.new(0, 0, 0))
	picture.BackgroundTransparency = 1
	local name = ui.makeText(card, UDim2.new(1, -16, 0, 40), UDim2.fromOffset(8, 154), colors.text, 16)
	name.Font = Enum.Font.GothamBlack
	name.TextXAlignment = Enum.TextXAlignment.Center
	local stats = ui.makeText(card, UDim2.new(1, -16, 0, 20), UDim2.fromOffset(8, 194), GREEN, 13)
	stats.Font = Enum.Font.GothamBold
	stats.TextXAlignment = Enum.TextXAlignment.Center
	local band = ui.makeText(card, UDim2.new(1, -20, 0, 22), UDim2.fromOffset(10, 218), Color3.fromRGB(30, 20, 10), 13)
	band.BackgroundTransparency = 0
	band.Font = Enum.Font.GothamBlack
	band.TextXAlignment = Enum.TextXAlignment.Center
	ui.addCorner(band, 3)
	local buy = ui.makeButton(card, UDim2.new(1, -20, 0, 44), UDim2.new(0, 10, 1, -52), colors.buy)
	buy.TextSize = 17
	buy.Font = Enum.Font.GothamBlack
	buy.Activated:Connect(function()
		-- The window goes with the row, so a click that lands after a
		-- restock can't buy the new item.
		if windowShown then
			ui.send("Buy", `{windowShown}:{index}`)
		end
	end)
	local stamp = ui.makeText(card, UDim2.fromOffset(170, 56), UDim2.new(0.5, -85, 0, 64), Color3.fromRGB(230, 70, 60), 40)
	stamp.Font = Enum.Font.GothamBlack
	stamp.Text = "SOLD"
	stamp.TextXAlignment = Enum.TextXAlignment.Center
	stamp.Rotation = -14
	stamp.ZIndex = 500
	stamp.BackgroundTransparency = 1
	local stampStroke = ui.art.stroke(stamp, Color3.fromRGB(230, 70, 60), 4, 0)
	stampStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stamp.BackgroundColor3 = Color3.fromRGB(30, 10, 10)
	stamp.BackgroundTransparency = 0.3
	ui.addCorner(stamp, 6)
	local shade = ui.makeFrame(card, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	shade.BackgroundTransparency = 0.45
	shade.ZIndex = 480
	cards[index] = {
		card = card,
		scale = scale,
		stroke = stroke,
		kind = kind,
		level = level,
		picture = picture,
		name = name,
		stats = stats,
		band = band,
		buy = buy,
		stamp = stamp,
		shade = shade,
	}
end

local function buildRecent(ui, page: Instance)
	local colors = ui.colors
	local strip = ui.makeFrame(page, UDim2.new(1, -10, 0, 150), UDim2.fromOffset(0, 0), Color3.fromRGB(34, 29, 24))
	strip.LayoutOrder = 3
	ui.addCorner(strip, 10)
	ui.art.stroke(strip, colors.dim, 1, 0.5)
	w.autoLine = ui.makeText(strip, UDim2.new(1, -28, 0, 26), UDim2.fromOffset(14, 8), colors.text, 16)
	w.autoLine.Font = Enum.Font.GothamBlack
	w.autoLine.RichText = true
	local row = ui.makeFrame(strip, UDim2.new(1, -28, 0, 96), UDim2.fromOffset(14, 42), Color3.new(0, 0, 0))
	row.BackgroundTransparency = 1
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	for index = 1, (GameConfig.AutoBuyRecent or 6) do
		local tile = ui.makeFrame(row, UDim2.fromOffset(96, 96), UDim2.fromOffset(0, 0), Color3.fromRGB(22, 20, 18))
		tile.LayoutOrder = index
		ui.addCorner(tile, 6)
		local stroke = ui.art.stroke(tile, colors.dim, 2, 0.2)
		local art = ui.makeFrame(tile, UDim2.fromOffset(66, 66), UDim2.new(0.5, -33, 0, 4), Color3.new(0, 0, 0))
		art.BackgroundTransparency = 1
		local price = ui.makeText(tile, UDim2.new(1, -6, 0, 20), UDim2.new(0, 3, 1, -22), GOLD, 12)
		price.Font = Enum.Font.GothamBlack
		price.TextXAlignment = Enum.TextXAlignment.Center
		recentTiles[index] = { tile = tile, stroke = stroke, art = art, price = price }
	end
	w.noRecent = ui.makeText(row, UDim2.fromOffset(400, 96), UDim2.fromOffset(0, 0), colors.dim, 14)
	w.noRecent.LayoutOrder = 99
	w.noRecent.Text = "Nothing bought by auto-buy yet."
end

function MarketPage.build(ui)
	local page = ui.pages.Market
	buildBanner(ui, page)
	local grid = ui.makeFrame(page, UDim2.new(1, -10, 0, 0), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	grid.BackgroundTransparency = 1
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.LayoutOrder = 2
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(1 / 4, -9, 0, 300)
	layout.CellPadding = UDim2.fromOffset(12, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	for index = 1, GameConfig.MarketSize do
		buildCard(ui, grid, index)
	end
	buildRecent(ui, page)

	-- The restock bar and clock run smoothly between updates; the awning sways.
	local t = 0
	RunService.RenderStepped:Connect(function(dt)
		if not page.Visible then
			return
		end
		t += dt
		local left = math.max(0, restock.left - (os.clock() - restock.at))
		w.clock.Text = clock(left)
		w.fill.Size = UDim2.fromScale(1 - left / GameConfig.MarketRestockSeconds, 1)
		w.awning.Position = UDim2.fromOffset(0, math.sin(t * 2) * 1.5)
	end)
end

-- New stock: cards flip in one after another.
local function flipIn()
	for index, part in cards do
		part.scale.Scale = 0.6
		part.card.Rotation = -6
		task.delay(index * 0.05, function()
			TweenService:Create(part.scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			TweenService:Create(part.card, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = 0 }):Play()
		end)
	end
end

local function stampIn(part)
	local scale = part.stamp:FindFirstChild("Pop") or Instance.new("UIScale")
	scale.Name = "Pop"
	scale.Parent = part.stamp
	scale.Scale = 2.2
	part.stamp.TextTransparency = 1
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(part.stamp, TweenInfo.new(0.2), { TextTransparency = 0 }):Play()
end

function MarketPage.draw(state, ui)
	if not state then
		return
	end
	latest = state
	local colors = ui.colors
	local page = ui.pages.Market
	restock = { left = state.marketRestock, at = os.clock() }
	local newWindow = windowShown ~= nil and windowShown ~= state.marketWindow
	windowShown = state.marketWindow
	if newWindow then
		table.clear(soldShown)
		if page.Visible then
			flipIn()
		end
	end

	local off = discount(state, "marketPrice")
	w.discount.Text = if off > 0 then `FESTIVAL: -{math.floor(off * 100 + 0.5)}% ON EVERYTHING` else "Gear rolls around your level"
	w.discount.TextColor3 = if off > 0 then GREEN else colors.dim

	-- Auto-buy button.
	local owns = state.passes.autobuy == true
	local rule = state.autoBuy
	local running = owns and rule.on
	w.auto.Text = if not owns then "\u{1F512} AUTO-BUY" elseif running then "AUTO-BUY ON" else "AUTO-BUY OFF"
	w.auto.TextColor3 = if running then GREEN else colors.gold

	for index, part in cards do
		local item = state.market[index]
		part.card.Visible = item ~= nil
		if item then
			local chest = if item.kind == "Chest" then ChestConfig.get(item.chest or "") else nil
			local rarity = GameConfig.getRarity(item.rarity or "Common")
			part.stroke.Color = if chest then chest.color else rarity.color
			ui.itemArt.set(part.picture, item)
			part.kind.Text = if chest then "CHEST" else string.upper(item.slot or "")
			local locked = state.level < (item.level or 1)
			part.level.Text = if chest then "" else `LV {item.level}`
			part.level.TextColor3 = if locked then Color3.fromRGB(255, 110, 100) else colors.dim
			part.name.Text = if chest then chest.name else item.name
			part.stats.Text = if chest then "Opens in your Inventory" else `+{item.attack or 0} Attack   +{item.defense or 0} Defense`
			part.stats.TextColor3 = if chest then colors.dim else GREEN
			part.band.Text = string.upper(rarity.id)
			part.band.BackgroundColor3 = if chest then chest.color else rarity.color
			local price = math.floor(item.price * (1 - off))
			if item.sold then
				ui.setButton(part.buy, "SOLD", false, colors.buy)
			elseif locked then
				ui.setButton(part.buy, `\u{1F512} LEVEL {item.level}`, false, colors.buy)
			else
				ui.setButton(part.buy, `BUY  {Format.short(price)}`, state.gold >= price, colors.buy)
			end
			part.stamp.Visible = item.sold == true
			part.shade.Visible = item.sold == true or locked
			if item.sold and not soldShown[index] then
				soldShown[index] = true
				if page.Visible then
					stampIn(part)
				end
			end
		end
	end

	-- Auto-buy recent strip.
	if owns then
		w.autoLine.Text = `AUTO-BUY {if running then "<font color=\"#7FE08A\">RUNNING</font>" else "OFF"}   \u{00B7}   bought {rule.bought}, spent {Format.short(rule.spent)} gold   \u{00B7}   {rule.minRarity} or better`
	else
		w.autoLine.Text = "AUTO-BUY   \u{00B7}   <font color=\"#B7A98F\">the Market Steward pass buys matching gear every restock</font>"
	end
	for index, tile in recentTiles do
		local buy = rule.recent[index]
		tile.tile.Visible = buy ~= nil
		if buy then
			ui.itemArt.set(tile.art, { kind = "Gear", slot = buy.slot, name = buy.name, rarity = buy.rarity })
			tile.stroke.Color = GameConfig.getRarity(buy.rarity).color
			tile.price.Text = Format.short(buy.price)
		end
	end
	w.noRecent.Visible = #rule.recent == 0
end

return MarketPage
