-- Shop page:
--   * a hero banner: Crowns balance (counts up), passes owned,
--   * tabs: CROWNS (Crown bundles + the Tithe Chest), OFFERS (packs),
--     PASSES, CROWN SHOP and COFFERS,
--   * every product is a picture card with a shine and a price button.
--     Cards pop in when a tab opens.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local StoreConfig = require(Shared:WaitForChild("StoreConfig"))
local Format = require(Shared:WaitForChild("Format"))

local ShopPage = {}

local CROWN = "\u{1F451}"
local PURPLE = Color3.fromRGB(200, 150, 230)
local GOLD = Color3.fromRGB(240, 196, 80)
local GREEN = Color3.fromRGB(120, 220, 120)
local TABS = {
	{ "crowns", "CROWNS" },
	{ "offers", "OFFERS" },
	{ "passes", "GAME PASSES" },
	{ "crownshop", "CROWN SHOP" },
	{ "coffers", "COFFERS" },
}
local PASS_GLYPHS = {
	charter = "\u{1F4DC}",
	couriers = "\u{1F40E}",
	nightwatch = "\u{1F319}",
	treasury = "\u{1F3E6}",
	doubleincome = "\u{1F4D2}",
	autoquest = "\u{1F5FA}\u{FE0F}",
	autoroll = "\u{1F482}",
	autobuy = "\u{2696}\u{FE0F}",
}
local REWARD_GLYPHS = {
	crowns = CROWN,
	gold = "\u{1F4B0}",
	xpBoost = "\u{2B50}",
	skill = "\u{1F4AA}",
	tokens = "\u{1F3C5}",
	energy = "\u{26A1}",
	stamina = "\u{1F4EF}",
	health = "\u{2764}\u{FE0F}",
	title = "\u{1F3F7}\u{FE0F}",
	seals = "\u{1F4DC}",
	chest = "\u{1F381}",
}
local CROWN_COUNTS = { crowns1 = 1, crowns2 = 2, crowns3 = 3, crowns4 = 4 }

local tab = "crowns"
local w = {}
local sections = {} -- [tab] = frame
local productCards = {}
local passCards = {}
local crownShopCards = {}
local cofferCards = {}
local latest = nil
local shownCrowns = nil

local function grid(ui, parent: Instance, order: number, height: number, columns: number): Frame
	local frame = ui.makeFrame(parent, UDim2.new(1, 0, 0, 0), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	frame.BackgroundTransparency = 1
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.LayoutOrder = order
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(1 / columns, -10, 0, height)
	layout.CellPadding = UDim2.fromOffset(12, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame
	return frame
end

local function section(ui, page: Instance, key: string, order: number): Frame
	local frame = ui.makeFrame(page, UDim2.new(1, -10, 0, 0), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	frame.BackgroundTransparency = 1
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.LayoutOrder = order
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame
	sections[key] = frame
	return frame
end

-- A card with a colored top glow, a picture area and a shine.
local function card(ui, parent: Instance, order: number, color: Color3): Frame
	local frame = ui.makeFrame(parent, UDim2.fromOffset(100, 100), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1))
	frame.LayoutOrder = order
	frame.ClipsDescendants = true
	ui.addCorner(frame, 10)
	ui.art.stroke(frame, color, 2, 0.15)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(color:Lerp(Color3.new(0, 0, 0), 0.45), Color3.fromRGB(26, 22, 18))
	gradient.Parent = frame
	ui.art.shine(frame, 5)
	local scale = Instance.new("UIScale")
	scale.Name = "Pop"
	scale.Parent = frame
	return frame
end

local function glyph(ui, parent: Instance, text: string, size: number, position: UDim2, box: number): TextLabel
	local label = ui.makeText(parent, UDim2.fromOffset(box, box), position, Color3.new(1, 1, 1), size)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Text = text
	return label
end

local function centered(ui, parent: Instance, y: number, height: number, size: number, color: Color3): TextLabel
	local label = ui.makeText(parent, UDim2.new(1, -16, 0, height), UDim2.fromOffset(8, y), color, size)
	label.TextXAlignment = Enum.TextXAlignment.Center
	return label
end

local function priceButton(ui, parent: Instance, color: Color3): TextButton
	local button = ui.makeButton(parent, UDim2.new(1, -24, 0, 46), UDim2.new(0, 12, 1, -56), color)
	button.TextSize = 18
	button.Font = Enum.Font.GothamBlack
	return button
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

local function buildHero(ui, page: Instance)
	local colors = ui.colors
	local hero = ui.makeFrame(page, UDim2.new(1, -10, 0, 120), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1))
	hero.LayoutOrder = 1
	hero.ClipsDescendants = true
	ui.addCorner(hero, 10)
	ui.art.stroke(hero, colors.gold, 2, 0)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 10
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(60, 24, 90)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(140, 90, 30)),
	})
	gradient.Parent = hero
	ui.art.skyline(hero, Color3.fromRGB(20, 10, 30), 0.4)
	ui.art.shine(hero, 5)
	local title = ui.makeText(hero, UDim2.fromOffset(320, 56), UDim2.fromOffset(22, 16), colors.gold, 44)
	title.Font = ui.art.Fonts.title
	title.Text = "Royal Shop"
	title.TextStrokeTransparency = 0.4
	title.ZIndex = 410
	w.passes = ui.makeText(hero, UDim2.fromOffset(360, 22), UDim2.fromOffset(24, 76), Color3.fromRGB(240, 225, 255), 15)
	w.passes.Font = Enum.Font.GothamBold
	w.passes.ZIndex = 410
	local balance = ui.makeFrame(hero, UDim2.fromOffset(280, 76), UDim2.new(1, -300, 0, 22), Color3.fromRGB(24, 14, 34))
	balance.BackgroundTransparency = 0.15
	balance.ZIndex = 410
	ui.addCorner(balance, 10)
	ui.art.stroke(balance, PURPLE, 2, 0)
	local crown = glyph(ui, balance, CROWN, 40, UDim2.fromOffset(8, 8), 60)
	crown.ZIndex = 411
	w.crownIcon = crown
	local label = ui.makeText(balance, UDim2.new(1, -80, 0, 18), UDim2.fromOffset(72, 10), PURPLE, 13)
	label.Font = Enum.Font.GothamBlack
	label.Text = "YOUR CROWNS"
	label.ZIndex = 411
	w.crowns = ui.makeText(balance, UDim2.new(1, -80, 0, 36), UDim2.fromOffset(72, 30), Color3.new(1, 1, 1), 32)
	w.crowns.Font = Enum.Font.GothamBlack
	w.crowns.ZIndex = 411
end

local function buildTabs(ui, page: Instance)
	local colors = ui.colors
	local bar = ui.makeFrame(page, UDim2.new(1, -10, 0, 50), UDim2.fromOffset(0, 0), Color3.fromRGB(44, 36, 22))
	bar.LayoutOrder = 2
	ui.addCorner(bar, 6)
	ui.art.stroke(bar, colors.gold, 1.5, 0.4)
	w.tabs = {}
	for index, info in TABS do
		local button = ui.makeButton(bar, UDim2.new(1 / #TABS, -8, 1, -8), UDim2.new((index - 1) / #TABS, 4, 0, 4), Color3.new(0, 0, 0))
		button.BackgroundTransparency = 1
		button.TextSize = 16
		button.Font = Enum.Font.GothamBlack
		button.Text = info[2]
		button:SetAttribute("NoGlow", true)
		local line = ui.makeFrame(button, UDim2.new(1, -20, 0, 3), UDim2.new(0, 10, 1, -3), colors.gold)
		w.tabs[info[1]] = { button = button, line = line }
		button.Activated:Connect(function()
			if tab ~= info[1] then
				tab = info[1]
				ShopPage.draw(latest, ui)
				ShopPage.popIn()
			end
		end)
	end
end

local function buildCrowns(ui, page: Instance)
	local holder = section(ui, page, "crowns", 3)
	local crownGrid = grid(ui, holder, 1, 250, 4)
	for _, product in StoreConfig.Products do
		if product.group == "crowns" then
			local frame = card(ui, crownGrid, #crownGrid:GetChildren(), PURPLE)
			-- A pile of crowns: more crowns, a bigger pile.
			local pile = ui.makeFrame(frame, UDim2.new(1, 0, 0, 100), UDim2.fromOffset(0, 14), Color3.new(0, 0, 0))
			pile.BackgroundTransparency = 1
			local count = CROWN_COUNTS[product.key] or 1
			for index = 1, count do
				local size = 46 + count * 4
				local x = (index - (count + 1) / 2) * 30
				local y = if index % 2 == 0 then 10 else 26
				glyph(ui, pile, CROWN, size, UDim2.new(0.5, x - size / 2, 0, y - 10), size)
			end
			local name = centered(ui, frame, 120, 24, 17, Color3.new(1, 1, 1))
			name.Font = Enum.Font.GothamBlack
			name.Text = product.name
			local amount = centered(ui, frame, 144, 30, 26, GOLD)
			amount.Font = Enum.Font.GothamBlack
			amount.Text = `{Format.short(product.crowns)} {CROWN}`
			if product.tag then
				local ribbon = ui.makeText(frame, UDim2.fromOffset(150, 24), UDim2.new(1, -110, 0, 18), Color3.fromRGB(30, 20, 6), 12)
				ribbon.BackgroundTransparency = 0
				ribbon.BackgroundColor3 = GOLD
				ribbon.Font = Enum.Font.GothamBlack
				ribbon.TextXAlignment = Enum.TextXAlignment.Center
				ribbon.Text = string.upper(product.tag)
				ribbon.Rotation = 35
				ribbon.ZIndex = 420
			end
			local button = priceButton(ui, frame, ui.colors.buy)
			button.Activated:Connect(function()
				ui.send("Robux", "product:" .. product.key)
			end)
			productCards[product.key] = { frame = frame, button = button }
		end
	end

	-- Tithe Chest: a chest that fills with Crowns as you play.
	for _, product in StoreConfig.Products do
		if product.group == "tithe" then
			local frame = card(ui, holder, 2, PURPLE)
			frame.Size = UDim2.new(1, 0, 0, 170)
			local chest = ui.makeFrame(frame, UDim2.fromOffset(130, 130), UDim2.fromOffset(16, 20), Color3.new(0, 0, 0))
			chest.BackgroundTransparency = 1
			ui.itemArt.chest(chest, "Epic", PURPLE, true)
			local title = ui.makeText(frame, UDim2.new(1, -420, 0, 30), UDim2.fromOffset(160, 18), GOLD, 24)
			title.Font = ui.art.Fonts.heading
			title.Text = "Tithe Chest"
			local note = ui.makeText(frame, UDim2.new(1, -420, 0, 40), UDim2.fromOffset(160, 50), ui.colors.dim, 13)
			note.Text = `Fills as you play: 1 Crown per {StoreConfig.TitheEnergyPerCrown} quest energy and {StoreConfig.TitheCrownsPerFoe} per foe beaten. Break it once it holds {StoreConfig.TitheMinToBreak}.`
			local back = ui.makeFrame(frame, UDim2.new(1, -420, 0, 30), UDim2.fromOffset(160, 104), Color3.fromRGB(20, 12, 28))
			ui.addCorner(back, 8)
			local fill = ui.makeFrame(back, UDim2.fromScale(0, 1), UDim2.fromOffset(0, 0), PURPLE)
			ui.addCorner(fill, 8)
			ui.art.gloss(fill, 1, 0.6)
			local value = ui.makeText(back, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1), 15)
			value.Font = Enum.Font.GothamBlack
			value.TextXAlignment = Enum.TextXAlignment.Center
			value.ZIndex = fill.ZIndex + 1
			local button = ui.makeButton(frame, UDim2.fromOffset(220, 60), UDim2.new(1, -240, 0.5, -30), ui.colors.buy)
			button.TextSize = 18
			button.Font = Enum.Font.GothamBlack
			button.Activated:Connect(function()
				ui.send("Robux", "product:" .. product.key)
			end)
			productCards[product.key] = { frame = frame, button = button, fill = fill, value = value, chest = chest }
		end
	end
end

local function rewardTiles(ui, parent: Instance, rewards, y: number)
	local row = ui.makeFrame(parent, UDim2.new(1, -24, 0, 84), UDim2.fromOffset(12, y), Color3.new(0, 0, 0))
	row.BackgroundTransparency = 1
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = row
	for index, reward in rewards do
		local tile = ui.makeFrame(row, UDim2.fromOffset(84, 84), UDim2.fromOffset(0, 0), Color3.fromRGB(22, 18, 14))
		tile.LayoutOrder = index
		ui.addCorner(tile, 8)
		if reward.kind == "chest" then
			local art = ui.makeFrame(tile, UDim2.fromOffset(56, 56), UDim2.new(0.5, -28, 0, 2), Color3.new(0, 0, 0))
			art.BackgroundTransparency = 1
			ui.itemArt.chest(art, reward.rarity)
			ui.art.stroke(tile, GameConfig.getRarity(reward.rarity).color, 1.5, 0.2)
		else
			glyph(ui, tile, REWARD_GLYPHS[reward.kind] or "\u{1F381}", 32, UDim2.new(0.5, -28, 0, 2), 56)
			ui.art.stroke(tile, ui.colors.dim, 1, 0.4)
		end
		local text = ui.makeText(tile, UDim2.new(1, -6, 0, 26), UDim2.new(0, 3, 1, -28), Color3.new(1, 1, 1), 11)
		text.Font = Enum.Font.GothamBlack
		text.TextXAlignment = Enum.TextXAlignment.Center
		text.Text = StoreConfig.describe(reward)
	end
end

local function buildOffers(ui, page: Instance)
	local holder = section(ui, page, "offers", 4)
	local offerGrid = grid(ui, holder, 1, 290, 3)
	for _, product in StoreConfig.Products do
		if product.group == "pack" then
			local frame = card(ui, offerGrid, #offerGrid:GetChildren(), Color3.fromRGB(200, 110, 50))
			local name = centered(ui, frame, 14, 30, 22, GOLD)
			name.Font = ui.art.Fonts.heading
			name.Text = product.name
			local when = centered(ui, frame, 46, 20, 13, Color3.fromRGB(255, 200, 150))
			when.Font = Enum.Font.GothamBlack
			rewardTiles(ui, frame, product.rewards, 76)
			local level = centered(ui, frame, 168, 20, 13, ui.colors.dim)
			level.Text = if product.level then `From level {product.level}` else (if product.once then "Once per player" else "")
			local button = priceButton(ui, frame, ui.colors.buy)
			button.Activated:Connect(function()
				ui.send("Robux", "product:" .. product.key)
			end)
			productCards[product.key] = { frame = frame, button = button, when = when }
		end
	end
end

local function buildPasses(ui, page: Instance)
	local holder = section(ui, page, "passes", 5)
	local passGrid = grid(ui, holder, 1, 250, 4)
	for index, pass in StoreConfig.Passes do
		local frame = card(ui, passGrid, index, GOLD)
		local back = ui.makeFrame(frame, UDim2.fromOffset(84, 84), UDim2.new(0.5, -42, 0, 14), Color3.fromRGB(40, 30, 14))
		ui.addCorner(back, 42)
		ui.art.gloss(back, 1, 0.7)
		ui.art.stroke(back, GOLD, 2, 0)
		glyph(ui, back, PASS_GLYPHS[pass.key] or "\u{1F39F}\u{FE0F}", 44, UDim2.fromOffset(0, 0), 84)
		local name = centered(ui, frame, 104, 24, 17, Color3.new(1, 1, 1))
		name.Font = Enum.Font.GothamBlack
		name.Text = pass.name
		local note = centered(ui, frame, 128, 56, 12, ui.colors.dim)
		note.Text = pass.note
		local owned = ui.makeText(frame, UDim2.fromOffset(90, 22), UDim2.fromOffset(8, 8), Color3.fromRGB(20, 40, 20), 11)
		owned.BackgroundTransparency = 0
		owned.BackgroundColor3 = GREEN
		owned.Font = Enum.Font.GothamBlack
		owned.TextXAlignment = Enum.TextXAlignment.Center
		owned.Text = "\u{2714} OWNED"
		owned.ZIndex = 420
		ui.addCorner(owned, 4)
		local button = priceButton(ui, frame, ui.colors.buy)
		button.Activated:Connect(function()
			ui.send("Robux", "pass:" .. pass.key)
		end)
		passCards[pass.key] = { frame = frame, button = button, owned = owned }
	end
end

local function buildCrownShop(ui, page: Instance)
	local holder = section(ui, page, "crownshop", 6)
	local shopGrid = grid(ui, holder, 1, 210, 3)
	for index, item in StoreConfig.CrownShop do
		local frame = card(ui, shopGrid, index, PURPLE)
		glyph(ui, frame, REWARD_GLYPHS[item.reward.kind] or "\u{1F381}", 50, UDim2.new(0.5, -40, 0, 10), 80)
		local name = centered(ui, frame, 92, 24, 18, Color3.new(1, 1, 1))
		name.Font = Enum.Font.GothamBlack
		name.Text = item.name
		local note = centered(ui, frame, 116, 30, 13, ui.colors.dim)
		note.Text = item.note
		local button = priceButton(ui, frame, ui.colors.buy)
		button.Activated:Connect(function()
			ui.send("CrownBuy", item.key)
		end)
		crownShopCards[item.key] = { frame = frame, button = button }
	end
end

local function buildCoffers(ui, page: Instance)
	local holder = section(ui, page, "coffers", 7)
	for index, coffer in StoreConfig.Coffers do
		local top = GameConfig.getRarity(coffer.pityRarity)
		local frame = card(ui, holder, index, top.color)
		frame.Size = UDim2.new(1, 0, 0, 230)
		local chest = ui.makeFrame(frame, UDim2.fromOffset(170, 170), UDim2.fromOffset(20, 24), Color3.new(0, 0, 0))
		chest.BackgroundTransparency = 1
		ui.itemArt.chest(chest, coffer.pityRarity, top.color, true)
		local name = ui.makeText(frame, UDim2.new(1, -230, 0, 34), UDim2.fromOffset(210, 14), GOLD, 28)
		name.Font = ui.art.Fonts.heading
		name.Text = coffer.name
		local note = ui.makeText(frame, UDim2.new(1, -230, 0, 18), UDim2.fromOffset(210, 48), ui.colors.dim, 13)
		note.Text = "Royal gear, the strongest stats. Opens in your Inventory."
		-- Odds as colored chips.
		local chips = ui.makeFrame(frame, UDim2.new(1, -230, 0, 30), UDim2.fromOffset(210, 72), Color3.new(0, 0, 0))
		chips.BackgroundTransparency = 1
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.Padding = UDim.new(0, 6)
		layout.Parent = chips
		for order, pair in coffer.odds do
			local rarity = GameConfig.getRarity(pair[1])
			local chip = ui.makeText(chips, UDim2.fromOffset(120, 30), UDim2.fromOffset(0, 0), rarity.color, 13)
			chip.LayoutOrder = order
			chip.BackgroundTransparency = 0
			chip.BackgroundColor3 = Color3.fromRGB(20, 16, 12)
			chip.Font = Enum.Font.GothamBlack
			chip.TextXAlignment = Enum.TextXAlignment.Center
			chip.Text = `{string.upper(rarity.id)} {pair[2]}%`
			ui.addCorner(chip, 6)
			ui.art.stroke(chip, rarity.color, 1.5, 0.2)
		end
		-- Pity bar.
		local back = ui.makeFrame(frame, UDim2.new(1, -230, 0, 24), UDim2.fromOffset(210, 110), Color3.fromRGB(20, 14, 26))
		ui.addCorner(back, 8)
		local fill = ui.makeFrame(back, UDim2.fromScale(0, 1), UDim2.fromOffset(0, 0), top.color)
		ui.addCorner(fill, 8)
		ui.art.gloss(fill, 1, 0.6)
		local pity = ui.makeText(back, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1), 12)
		pity.Font = Enum.Font.GothamBlack
		pity.TextXAlignment = Enum.TextXAlignment.Center
		pity.TextStrokeTransparency = 0.4
		pity.ZIndex = fill.ZIndex + 1
		local buttons = {}
		local count = #StoreConfig.CofferBundles
		for order, bundle in StoreConfig.CofferBundles do
			local button = ui.makeButton(frame, UDim2.new((1 / count) * 0.72, -10, 0, 56), UDim2.new(0.25 + (order - 1) * 0.72 / count, 0, 0, 152), ui.colors.buy)
			button.TextSize = 15
			button.Font = Enum.Font.GothamBlack
			button.Activated:Connect(function()
				ui.send("Coffer", `{coffer.key}:{bundle.count}`)
			end)
			buttons[order] = button
		end
		cofferCards[coffer.key] = { frame = frame, fill = fill, pity = pity, buttons = buttons, chest = chest }
	end
end

function ShopPage.build(ui)
	local page = ui.pages.Shop
	buildHero(ui, page)
	buildTabs(ui, page)
	buildCrowns(ui, page)
	buildOffers(ui, page)
	buildPasses(ui, page)
	buildCrownShop(ui, page)
	buildCoffers(ui, page)
	-- The crown in the balance bobs; the balance counts toward its value.
	local t = 0
	RunService.RenderStepped:Connect(function(dt)
		if not page.Visible or not latest then
			return
		end
		t += dt
		w.crownIcon.Rotation = math.sin(t * 2) * 8
		local target = latest.crowns
		if shownCrowns == nil then
			shownCrowns = target
		end
		if math.abs(target - shownCrowns) < 1 then
			shownCrowns = target
		else
			shownCrowns += (target - shownCrowns) * math.min(1, dt * 8)
		end
		w.crowns.Text = Format.short(math.floor(shownCrowns))
	end)
	page:GetPropertyChangedSignal("Visible"):Connect(function()
		if page.Visible then
			ShopPage.popIn()
		end
	end)
	-- Other pages open a tab: ui.openShop("coffers").
	ui.openShop = function(which: string)
		tab = which
		ui.showPage("Shop")
		ShopPage.draw(latest, ui)
	end
end

-- The open tab's cards pop in one after another.
function ShopPage.popIn()
	local holder = sections[tab]
	if not holder then
		return
	end
	local index = 0
	for _, scale in holder:GetDescendants() do
		if scale:IsA("UIScale") and scale.Name == "Pop" then
			index += 1
			scale.Scale = 0.7
			task.delay(index * 0.04, function()
				TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end)
		end
	end
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

function ShopPage.draw(state, ui)
	if not state then
		return
	end
	latest = state
	local colors = ui.colors
	local crowns = state.crowns
	local owned = 0
	for _ in state.passes do
		owned += 1
	end
	w.passes.Text = `{owned} of {#StoreConfig.Passes} game passes owned  \u{00B7}  passes are yours forever`
	for key, part in w.tabs do
		local on = key == tab
		part.line.Visible = on
		part.button.TextColor3 = if on then colors.text else colors.dim
	end
	for key, frame in sections do
		frame.Visible = key == tab
	end

	for _, product in StoreConfig.Products do
		local part = productCards[product.key]
		if not part then
			continue
		end
		if product.group == "crowns" then
			ui.setButton(part.button, ui.robuxText(product.price), true, colors.buy)
		elseif product.group == "pack" then
			local bought = state.packsBought[product.key] == true
			local secondsLeft = if product.hours then product.hours * 3600 - state.secondsSinceFirstVisit else 0
			local expired = product.hours ~= nil and secondsLeft <= 0
			part.frame.Visible = bought or not expired
			part.when.Text = if product.hours and not bought then `\u{23F3} ENDS IN {string.upper(ui.formatLong(secondsLeft))}` else string.upper(product.note or "")
			if bought then
				ui.setButton(part.button, "\u{2714} OWNED", false, colors.buy)
			elseif product.level and state.level < product.level then
				ui.setButton(part.button, `\u{1F512} LEVEL {product.level}`, false, colors.buy)
			else
				ui.setButton(part.button, ui.robuxText(product.price), true, colors.buy)
			end
		elseif product.group == "tithe" then
			part.fill.Size = UDim2.fromScale(math.clamp(state.tithe / StoreConfig.TitheMax, 0, 1), 1)
			part.value.Text = `{state.tithe} / {StoreConfig.TitheMax} {CROWN}`
			local ready = state.tithe >= StoreConfig.TitheMinToBreak
			ui.setButton(part.button, if ready then `BREAK IT  {ui.robuxText(product.price)}` else `FILLS AT {StoreConfig.TitheMinToBreak}`, ready, colors.buy)
		end
	end

	for _, pass in StoreConfig.Passes do
		local part = passCards[pass.key]
		local has = state.passes[pass.key] == true
		part.owned.Visible = has
		ui.setButton(part.button, if has then "\u{2714} OWNED" else ui.robuxText(pass.price), not has, colors.buy)
	end

	for _, item in StoreConfig.CrownShop do
		ui.setButton(crownShopCards[item.key].button, `{item.cost} {CROWN}`, crowns >= item.cost, colors.buy)
	end

	for _, coffer in StoreConfig.Coffers do
		local part = cofferCards[coffer.key]
		local opened = state.pity[coffer.key] or 0
		local left = coffer.pityEvery - opened
		part.fill.Size = UDim2.fromScale(opened / coffer.pityEvery, 1)
		part.pity.Text = `{string.upper(coffer.pityRarity)} OR BETTER WITHIN {left} OPENS`
		for index, bundle in StoreConfig.CofferBundles do
			local cost = StoreConfig.bundleCost(coffer, bundle.count) or 0
			local off = if bundle.discount > 0 then `  -{math.floor(bundle.discount * 100 + 0.5)}%` else ""
			ui.setButton(part.buttons[index], `OPEN x{bundle.count}{off}\n{cost} {CROWN}`, crowns >= cost, if bundle.discount > 0 then colors.claim else colors.buy)
		end
	end
end

return ShopPage
