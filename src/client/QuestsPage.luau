-- Quests page:
--   * a bar with the auto quest status (green dot while it runs), a Double
--     XP note, and the AUTO QUESTS button (settings, or the pass offer),
--   * a big banner per region (name, level, +/- to fold it),
--   * inside, TIER headings and a card per quest: name, energy / gold /
--     XP / gear drop pills, the mastery bar and its three medals, and a
--     big DO QUEST button. Doing a quest pops "+gold +XP" off its card.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Format = require(Shared:WaitForChild("Format"))

local QuestsPage = {}

local REGION_COLORS = {
	Oakvale = Color3.fromRGB(86, 140, 70),
	Greywatch = Color3.fromRGB(80, 110, 150),
	Emberreach = Color3.fromRGB(180, 80, 50),
}
local MEDAL_COLORS = { Color3.fromRGB(200, 132, 78), Color3.fromRGB(201, 210, 222), Color3.fromRGB(240, 200, 90) }
local RIBBON_COLORS = { Color3.fromRGB(60, 160, 90), Color3.fromRGB(60, 110, 200), Color3.fromRGB(200, 60, 60) }
local ENERGY, GOLD, XP, BAG = "\u{26A1}", "\u{1F4B0}", "\u{2B06}\u{FE0F}", "\u{1F392}"
local STAR = "\u{2B50}"

local w = {}
local cards = {} -- [quest id] = widgets
local regions = {} -- [region id] = { toggle, holder, open, region }
local regionsOpened = false
local latest = nil

local function tierLevel(region: string, tier: number): number
	local lowest = math.huge
	for _, quest in GameConfig.Quests do
		if quest.region == region and quest.tier == tier then
			lowest = math.min(lowest, quest.level)
		end
	end
	return lowest
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

local function buildBar(ui, page: Instance)
	local colors = ui.colors
	local bar = ui.makeFrame(page, UDim2.new(1, -10, 0, 60), UDim2.fromOffset(0, 0), Color3.fromRGB(44, 36, 22))
	bar.LayoutOrder = 1
	ui.addCorner(bar, 6)
	ui.art.stroke(bar, colors.gold, 1.5, 0.4)
	w.boost = ui.makeText(bar, UDim2.new(1, -330, 1, 0), UDim2.fromOffset(18, 0), Color3.fromRGB(180, 140, 240), 16)
	w.boost.Font = Enum.Font.GothamBold
	w.dot = ui.makeFrame(bar, UDim2.fromOffset(14, 14), UDim2.new(1, -290, 0.5, -7), Color3.fromRGB(90, 200, 90))
	ui.addCorner(w.dot, 3)
	w.auto = ui.makeButton(bar, UDim2.fromOffset(250, 44), UDim2.new(1, -262, 0, 8), Color3.fromRGB(30, 24, 16))
	w.auto.TextSize = 20
	w.auto.Font = Enum.Font.GothamBlack
	ui.art.stroke(w.auto, colors.gold, 2, 0)
	w.auto.Activated:Connect(function()
		local state = latest
		if state and state.passes.autoquest then
			ui.openAutoQuest()
		elseif ui.offerPass then
			ui.offerPass("autoquest")
		end
	end)
end

local function pill(ui, parent: Instance, x: number, width: number): TextLabel
	local label = ui.makeText(parent, UDim2.fromOffset(width, 30), UDim2.fromOffset(x, 48), ui.colors.text, 16)
	label.BackgroundTransparency = 0
	label.BackgroundColor3 = Color3.fromRGB(22, 18, 14)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.RichText = true
	ui.addCorner(label, 4)
	return label
end

local function medal(ui, parent: Instance, x: number, index: number)
	local holder = ui.makeFrame(parent, UDim2.fromOffset(34, 40), UDim2.new(1, x, 0, 84), Color3.new(0, 0, 0))
	holder.BackgroundTransparency = 1
	local ribbon = ui.makeFrame(holder, UDim2.fromOffset(20, 12), UDim2.fromOffset(7, 0), RIBBON_COLORS[index])
	ui.addCorner(ribbon, 3)
	local disc = ui.makeFrame(holder, UDim2.fromOffset(30, 30), UDim2.fromOffset(2, 8), MEDAL_COLORS[index])
	ui.addCorner(disc, 15)
	ui.art.gloss(disc, 1, 0.65)
	local inner = ui.makeFrame(disc, UDim2.fromOffset(16, 16), UDim2.fromOffset(7, 7), ui.art.shade(MEDAL_COLORS[index], 0.3))
	ui.addCorner(inner, 8)
	return { holder = holder, ribbon = ribbon, disc = disc, inner = inner }
end

local function buildCard(ui, parent: Instance, quest, order: number)
	local colors = ui.colors
	local card = ui.makeFrame(parent, UDim2.new(1, 0, 0, 136), UDim2.fromOffset(0, 0), Color3.fromRGB(34, 29, 24))
	card.LayoutOrder = order
	card.ClipsDescendants = true
	ui.addCorner(card, 6)
	local stroke = ui.art.stroke(card, colors.dim, 1, 0.6)

	local name = ui.makeText(card, UDim2.new(1, -330, 0, 36), UDim2.fromOffset(18, 8), colors.text, 28)
	name.Font = Enum.Font.GothamBold
	name.Text = quest.name
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.TextWrapped = false

	local energy = pill(ui, card, 18, 70)
	local gold = pill(ui, card, 94, 130)
	local xp = pill(ui, card, 230, 110)
	local drop = pill(ui, card, 346, 210)

	-- Mastery bar with its three medals at the right end.
	local bar = ui.makeFrame(card, UDim2.new(1, -470, 0, 30), UDim2.fromOffset(18, 90), Color3.fromRGB(22, 18, 14))
	ui.addCorner(bar, 4)
	local fill = ui.makeFrame(bar, UDim2.fromScale(0, 1), UDim2.fromOffset(0, 0), colors.gold)
	ui.addCorner(fill, 4)
	local barText = ui.makeText(bar, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), colors.text, 15)
	barText.Font = Enum.Font.GothamBlack
	barText.TextXAlignment = Enum.TextXAlignment.Center
	barText.ZIndex = fill.ZIndex + 1
	local medals = {}
	for index = 1, 3 do
		medals[index] = medal(ui, card, -444 + (index - 1) * 42, index)
	end

	local button = ui.makeButton(card, UDim2.fromOffset(270, 96), UDim2.new(1, -288, 0, 20), colors.gold)
	button.TextSize = 30
	button.Font = Enum.Font.GothamBlack
	button.Activated:Connect(function()
		ui.send("Quest", quest.id)
	end)
	local shade = ui.makeFrame(card, UDim2.new(1, -300, 1, 0), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	shade.BackgroundTransparency = 0.5
	shade.ZIndex = 400

	cards[quest.id] = {
		card = card,
		stroke = stroke,
		energy = energy,
		gold = gold,
		xp = xp,
		drop = drop,
		fill = fill,
		barText = barText,
		medals = medals,
		button = button,
		shade = shade,
	}
end

local function buildRegions(ui, page: Instance)
	local colors = ui.colors
	for index, region in GameConfig.Regions do
		local color = REGION_COLORS[region.id] or colors.dim
		local banner = ui.makeButton(page, UDim2.new(1, -10, 0, 100), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1))
		banner.LayoutOrder = 10 + index * 2
		banner.Text = ""
		banner.ClipsDescendants = true
		banner:SetAttribute("NoGlow", true)
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new(ui.art.shade(color, -0.55), ui.art.shade(color, -0.2))
		gradient.Parent = banner
		ui.art.skyline(banner, Color3.new(0, 0, 0), 0.55)
		ui.art.stroke(banner, colors.gold, 1.5, 0.4)
		local accent = ui.makeFrame(banner, UDim2.new(1, 0, 0, 4), UDim2.new(0, 0, 1, -4), colors.gold)
		accent.ZIndex = banner.ZIndex + 2
		local name = ui.makeText(banner, UDim2.new(1, -140, 1, 0), UDim2.fromOffset(30, 0), colors.gold, 52)
		name.Font = ui.art.Fonts.title
		name.Text = if region.level > 1 then `{string.upper(region.id)}   (LEVEL {region.level}+)` else string.upper(region.id)
		name.ZIndex = banner.ZIndex + 2
		name.TextStrokeTransparency = 0.5
		local toggle = ui.makeText(banner, UDim2.fromOffset(72, 72), UDim2.new(1, -90, 0, 13), colors.gold, 46)
		toggle.Font = Enum.Font.GothamBlack
		toggle.TextXAlignment = Enum.TextXAlignment.Center
		toggle.BackgroundColor3 = Color3.fromRGB(20, 16, 12)
		toggle.BackgroundTransparency = 0.2
		toggle.ZIndex = banner.ZIndex + 2
		ui.art.stroke(toggle, colors.gold, 2, 0)

		local holder = ui.makeFrame(page, UDim2.new(1, -10, 0, 0), UDim2.fromOffset(0, 0), Color3.fromRGB(24, 20, 16))
		holder.LayoutOrder = 11 + index * 2
		holder.AutomaticSize = Enum.AutomaticSize.Y
		ui.addCorner(holder, 6)
		local list = Instance.new("UIListLayout")
		list.Padding = UDim.new(0, 10)
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Parent = holder
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 14)
		pad.PaddingRight = UDim.new(0, 14)
		pad.PaddingTop = UDim.new(0, 10)
		pad.PaddingBottom = UDim.new(0, 14)
		pad.Parent = holder

		local part = { toggle = toggle, holder = holder, open = false, region = region, tiers = {} }
		regions[region.id] = part
		banner.Activated:Connect(function()
			part.open = not part.open
			QuestsPage.draw(latest, ui)
		end)

		local order = 0
		local lastTier = nil
		for _, quest in GameConfig.Quests do
			if quest.region == region.id then
				if quest.tier ~= lastTier then
					lastTier = quest.tier
					order += 1
					local heading = ui.makeText(holder, UDim2.new(1, 0, 0, 44), UDim2.fromOffset(0, 0), colors.dim, 34)
					heading.LayoutOrder = order
					heading.Font = ui.art.Fonts.title
					heading.Text = `TIER {quest.tier}   (LEVEL {tierLevel(region.id, quest.tier)}+)`
					part.tiers[quest.tier] = heading
				end
				order += 1
				buildCard(ui, holder, quest, order)
			end
		end
	end
end

function QuestsPage.build(ui)
	local page = ui.pages.Quests
	buildBar(ui, page)
	buildRegions(ui, page)
	local Fx = require(script.Parent:WaitForChild("Fx"))
	Fx.onQuest = function(info)
		local card = cards[info.id]
		if card and page.Visible and card.card.AbsoluteSize.Y > 0 then
			QuestsPage.pop(ui, card, info)
		end
	end
end

-- "+gold +XP" (and "GEAR!") rising from the quest's card.
function QuestsPage.pop(ui, card, info)
	local label = ui.makeText(card.card, UDim2.fromOffset(10, 34), UDim2.new(1, -153, 0, 60), ui.colors.gold, 24)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.TextWrapped = false
	label.RichText = true
	label.Font = Enum.Font.GothamBlack
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextStrokeTransparency = 0.2
	label.ZIndex = 500
	local gear = if info.drop then `  <font color="#7FE0FF">{BAG} GEAR!</font>` else ""
	label.Text = `<font color="#F0C450">+{Format.short(tonumber(info.gold) or 0)}</font>  <font color="#B48CF0">+{Format.short(tonumber(info.xp) or 0)} XP</font>{gear}`
	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = label
	TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	local rise = TweenService:Create(label, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(1, -153, 0, 14),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	rise:Play()
	rise.Completed:Connect(function()
		label:Destroy()
	end)
	card.stroke.Color = ui.colors.gold
	card.stroke.Transparency = 0
	card.stroke.Thickness = 3
	TweenService:Create(card.stroke, TweenInfo.new(0.5), { Thickness = 1, Transparency = 0.6 }):Play()
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

function QuestsPage.draw(state, ui)
	if not state then
		return
	end
	latest = state
	local colors = ui.colors

	-- Auto quests bar.
	local owns = state.passes.autoquest == true
	local running = owns and state.autoQuestOn == true
	w.dot.Visible = owns
	w.dot.BackgroundColor3 = if running then Color3.fromRGB(90, 200, 90) else Color3.fromRGB(120, 110, 100)
	w.auto.Text = if not owns then "\u{1F512} AUTO QUESTS" elseif running then "AUTO QUESTS ON" else "AUTO QUESTS OFF"
	w.auto.TextColor3 = colors.gold
	w.boost.Text = if (state.xpBoostLeft or 0) > 0 then `{STAR} Double XP: {ui.formatClock(state.xpBoostLeft)} left` else ""

	-- Regions: the newest unlocked one opens the first time.
	if not regionsOpened then
		regionsOpened = true
		local newest = nil
		for _, region in GameConfig.Regions do
			if state.level >= region.level then
				newest = region.id
			end
		end
		for id, part in regions do
			part.open = id == newest
		end
	end
	for _, part in regions do
		part.toggle.Text = if part.open then "-" else "+"
		part.holder.Visible = part.open
	end

	for _, quest in GameConfig.Quests do
		local card = cards[quest.id]
		local done = state.quests[quest.id] or 0
		local rank = GameConfig.getMasteryRank(done)
		local regionLevel = GameConfig.getRegion(quest.region).level
		local locked = state.level < quest.level or state.level < regionLevel

		card.energy.Text = `<font color="#F0A040">{ENERGY}</font> {quest.energy}`
		card.gold.Text = `{GOLD} {Format.short(GameConfig.getQuestGold(quest, done))}`
		card.xp.Text = `{XP} {quest.xp} XP`
		card.drop.Text = `{BAG} {string.format("%g", math.floor(quest.drop * 1000 + 0.5) / 10)}% GEAR DROP`

		if rank >= GameConfig.MaxMasteryRanks then
			card.fill.Size = UDim2.fromScale(1, 1)
			card.fill.BackgroundColor3 = MEDAL_COLORS[3]
			card.barText.Text = "GOLD MASTERY"
			card.barText.TextColor3 = Color3.fromRGB(40, 28, 12)
		else
			local into = done % GameConfig.MasteryPerRank
			card.fill.Size = UDim2.fromScale(into / GameConfig.MasteryPerRank, 1)
			card.fill.BackgroundColor3 = MEDAL_COLORS[rank + 1]
			card.barText.Text = `{string.upper(GameConfig.MasteryMedals[rank + 1])} MASTERY  {into} / {GameConfig.MasteryPerRank}`
			card.barText.TextColor3 = colors.text
		end
		for index, piece in card.medals do
			local earned = index <= rank
			piece.disc.BackgroundTransparency = if earned then 0 else 0.75
			piece.inner.BackgroundTransparency = if earned then 0 else 0.75
			piece.ribbon.BackgroundTransparency = if earned then 0 else 0.75
		end

		card.shade.Visible = locked
		if locked then
			ui.setButton(card.button, `LEVEL {math.max(quest.level, regionLevel)}`, false, colors.gold)
		else
			ui.setButton(card.button, `{ENERGY} DO QUEST`, state.energy >= quest.energy, colors.gold)
		end
	end
end

return QuestsPage
