-- Expeditions page: send your army on timed raids for loot.
--   * banner with the army at home,
--   * march panel: a road from your castle to the target with the army
--     walking along it while away, or your troop counts while at home,
--   * a picture card per expedition: enemy scene, level and time chips,
--     your power vs theirs bar, loot tiles and a SEND ARMY button.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArmyConfig = require(Shared:WaitForChild("ArmyConfig"))
local Format = require(Shared:WaitForChild("Format"))
local Kit = require(script.Parent:WaitForChild("Kit"))

local ExpeditionsPage = {}

local ENEMY_STYLE = {
	cavalry = { glyph = "\u{1F40E}", top = Color3.fromRGB(70, 110, 60), bottom = Color3.fromRGB(26, 40, 22) },
	spear = { glyph = "\u{1F531}", top = Color3.fromRGB(130, 100, 60), bottom = Color3.fromRGB(48, 34, 20) },
	archer = { glyph = "\u{1F3F9}", top = Color3.fromRGB(80, 110, 130), bottom = Color3.fromRGB(26, 36, 48) },
	fort = { glyph = "\u{1F3F0}", top = Color3.fromRGB(110, 100, 110), bottom = Color3.fromRGB(36, 30, 40) },
	mixed = { glyph = "\u{1F480}", top = Color3.fromRGB(100, 60, 110), bottom = Color3.fromRGB(32, 18, 40) },
}
local TROOP_GLYPHS = {
	spear = "\u{1F531}",
	archer = "\u{1F3F9}",
	cavalry = "\u{1F40E}",
	knight = "\u{1F6E1}\u{FE0F}",
	siege = "\u{1FAB5}",
}
local RESOURCE_GLYPHS = {
	lumber = "\u{1FAB5}",
	stone = "\u{1FAA8}",
	iron = "\u{26D3}\u{FE0F}",
	grain = "\u{1F33E}",
}

local w = {}
local cards = {}
local troopChips = {}
local wasAway = false

local function lootTile(ui, row: Instance, order: number, glyph: string, text: string, color: Color3)
	local tile = ui.makeFrame(row, UDim2.fromOffset(0, 26), UDim2.fromOffset(0, 0), Color3.fromRGB(20, 18, 15))
	tile.AutomaticSize = Enum.AutomaticSize.X
	tile.LayoutOrder = order
	ui.addCorner(tile, 6)
	ui.art.stroke(tile, color, 1, 0.4)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = tile
	local label = ui.makeText(tile, UDim2.fromOffset(0, 26), UDim2.fromOffset(0, 0), color, 12)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Font = Enum.Font.GothamBlack
	label.Text = `{glyph} {text}`
	return tile
end

local function buildMarch(ui, page: Instance)
	local panel = ui.makeFrame(page, UDim2.new(1, -10, 0, 120), UDim2.fromOffset(0, 0), Kit.CARD)
	panel.LayoutOrder = 2
	panel.ClipsDescendants = true
	ui.addCorner(panel, 10)
	w.marchStroke = ui.art.stroke(panel, ui.colors.gold, 2, 0.2)
	w.marchTitle = ui.makeText(panel, UDim2.new(1, -24, 0, 26), UDim2.fromOffset(14, 8), ui.colors.text, 18)
	w.marchTitle.Font = ui.art.Fonts.heading
	w.marchNote = ui.makeText(panel, UDim2.new(1, -24, 0, 18), UDim2.fromOffset(14, 34), ui.colors.dim, 12)
	w.marchNote.Font = Enum.Font.GothamBold

	-- the road (shown while away)
	local road = ui.makeFrame(panel, UDim2.new(1, -140, 0, 10), UDim2.fromOffset(70, 86), Color3.fromRGB(90, 70, 46))
	ui.addCorner(road, 5)
	local walked = ui.makeFrame(road, UDim2.fromScale(0, 1), UDim2.fromOffset(0, 0), ui.colors.gold)
	ui.addCorner(walked, 5)
	local home = ui.makeText(panel, UDim2.fromOffset(50, 50), UDim2.fromOffset(14, 64), Color3.new(1, 1, 1), 34)
	home.TextXAlignment = Enum.TextXAlignment.Center
	home.Text = "\u{1F3F0}"
	local goal = ui.makeText(panel, UDim2.fromOffset(50, 50), UDim2.new(1, -64, 0, 64), Color3.new(1, 1, 1), 34)
	goal.TextXAlignment = Enum.TextXAlignment.Center
	local army = ui.makeFrame(road, UDim2.fromOffset(60, 40), UDim2.new(0, -30, 0, -36), Color3.new(0, 0, 0))
	army.BackgroundTransparency = 1
	local walkers = ui.makeText(army, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1), 26)
	walkers.TextXAlignment = Enum.TextXAlignment.Center
	walkers.Text = "\u{1F482}\u{1F40E}"
	walkers.ZIndex = 420
	Kit.bob(walkers, 3, 4)
	local clock = ui.makeText(road, UDim2.fromOffset(120, 18), UDim2.new(0.5, -60, 1, 4), Kit.GOLD, 12)
	clock.Font = Enum.Font.GothamBlack
	clock.TextXAlignment = Enum.TextXAlignment.Center
	w.road = { road = road, walked = walked, home = home, goal = goal, army = army, clock = clock }

	-- troop chips (shown while at home)
	local chips = ui.makeFrame(panel, UDim2.new(1, -24, 0, 44), UDim2.fromOffset(12, 64), Color3.new(0, 0, 0))
	chips.BackgroundTransparency = 1
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = chips
	for index, troop in ArmyConfig.Troops do
		local chip = ui.makeFrame(chips, UDim2.new(0.2, -7, 1, 0), UDim2.fromOffset(0, 0), Color3.fromRGB(44, 38, 30))
		chip.LayoutOrder = index
		ui.addCorner(chip, 8)
		ui.art.gloss(chip, 1, 0.8)
		local label = ui.makeText(chip, UDim2.new(1, -10, 1, 0), UDim2.fromOffset(8, 0), ui.colors.text, 14)
		label.Font = Enum.Font.GothamBlack
		label.RichText = true
		troopChips[troop.key] = label
	end
	w.chips = chips
	w.panel = panel
end

local function buildCard(ui, grid: Instance, index: number, expedition)
	local style = ENEMY_STYLE[expedition.enemy] or ENEMY_STYLE.mixed
	local card, stroke = Kit.card(ui, grid, index, style.top)
	-- scene strip
	local scene = ui.makeFrame(card, UDim2.new(1, 0, 0, 74), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1))
	scene.ClipsDescendants = true
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(style.top, style.bottom)
	gradient.Parent = scene
	ui.art.skyline(scene, style.bottom:Lerp(Color3.new(0, 0, 0), 0.5), 0.3)
	local foe = ui.makeText(scene, UDim2.fromOffset(70, 70), UDim2.new(1, -84, 0, 2), Color3.new(1, 1, 1), 44)
	foe.TextXAlignment = Enum.TextXAlignment.Center
	foe.Text = style.glyph
	foe.ZIndex = 410
	Kit.bob(foe, 2, 1.2 + index * 0.1)
	local name = ui.makeText(scene, UDim2.new(1, -100, 0, 28), UDim2.fromOffset(12, 8), ui.colors.gold, 20)
	name.Font = ui.art.Fonts.heading
	name.Text = expedition.name
	name.TextStrokeTransparency = 0.4
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.ZIndex = 410
	local sub = ui.makeText(scene, UDim2.new(1, -100, 0, 20), UDim2.fromOffset(12, 40), Color3.new(1, 1, 1), 12)
	sub.Font = Enum.Font.GothamBlack
	sub.Text = `LV {expedition.level}  \u{2022}  \u{23F3} {expedition.minutes} MIN  \u{2022}  VS {string.upper(ArmyConfig.EnemyNames[expedition.enemy] or expedition.enemy)}`
	sub.TextStrokeTransparency = 0.5
	sub.ZIndex = 410

	-- power vs power
	local powerText = ui.makeText(card, UDim2.new(1, -24, 0, 18), UDim2.fromOffset(12, 80), ui.colors.dim, 12)
	powerText.Font = Enum.Font.GothamBlack
	powerText.RichText = true
	local bar = Kit.bar(ui, card, UDim2.new(1, -24, 0, 16), UDim2.fromOffset(12, 100), Kit.GREEN)

	-- loot
	local loot = ui.makeFrame(card, UDim2.new(1, -24, 0, 58), UDim2.fromOffset(12, 124), Color3.new(0, 0, 0))
	loot.BackgroundTransparency = 1
	local flow = Instance.new("UIListLayout")
	flow.FillDirection = Enum.FillDirection.Horizontal
	flow.Wraps = true
	flow.Padding = UDim.new(0, 6)
	flow.SortOrder = Enum.SortOrder.LayoutOrder
	flow.Parent = loot
	local order = 0
	local function add(glyph, text, color)
		order += 1
		lootTile(ui, loot, order, glyph, text, color)
	end
	add("\u{1F4B0}", `{expedition.goldMinutes}m income`, Kit.GOLD)
	add("\u{1F3C5}", `{expedition.tokens} tokens`, Color3.fromRGB(220, 170, 110))
	local plunder = {}
	for resource, amount in expedition.plunder or {} do
		table.insert(plunder, { resource = resource, amount = amount })
	end
	table.sort(plunder, function(a, b)
		return a.resource < b.resource
	end)
	for _, entry in plunder do
		add(RESOURCE_GLYPHS[entry.resource] or "\u{1F4E6}", Format.short(entry.amount), Color3.fromRGB(190, 180, 160))
	end
	if expedition.chest then
		add("\u{1F381}", `{math.floor(expedition.chestChance * 100)}% {expedition.chest}`, Color3.fromRGB(170, 140, 230))
	end
	if expedition.crowns then
		add("\u{1F451}", `{math.floor(expedition.crownChance * 100)}% {expedition.crowns}`, Kit.GOLD)
	end

	local button = ui.makeButton(card, UDim2.new(1, -24, 0, 40), UDim2.new(0, 12, 1, -50), ui.colors.action)
	button.TextSize = 15
	button.Font = Enum.Font.GothamBlack
	button.Activated:Connect(function()
		Kit.pop(card, 1.06)
		ui.send("Expedition", expedition.key)
	end)
	cards[expedition.key] = { card = card, stroke = stroke, powerText = powerText, bar = bar, button = button, style = style }
end

function ExpeditionsPage.build(ui)
	local page = ui.pages.Expeditions
	local banner = Kit.banner(ui, page, 1, 120, Color3.fromRGB(120, 70, 40), Color3.fromRGB(40, 24, 14), "Expeditions", "\u{1F5FA}\u{FE0F}")
	w.status = Kit.line(ui, banner, 120, 66, UDim.new(0.5, -120), 18, Color3.new(1, 1, 1))
	w.status.Font = Enum.Font.GothamBlack
	local note = Kit.line(ui, banner, 0, 0, UDim.new(0.4, 0), 13, Color3.fromRGB(255, 225, 200))
	note.Position = UDim2.new(0.58, 0, 0, 34)
	note.Size = UDim2.new(0.4, -10, 0, 56)
	note.TextWrapped = true
	note.Text = "Your whole army marches. Beat the enemy's power to win; the closer the fight, the more you lose. Reports go to the War Chronicle."
	buildMarch(ui, page)
	Kit.heading(ui, page, 3, "Raid targets", ui.colors.gold)
	local grid = Kit.grid(ui, page, 4, 244, 2)
	for index, expedition in ArmyConfig.Expeditions do
		buildCard(ui, grid, index, expedition)
	end
	page:GetPropertyChangedSignal("Visible"):Connect(function()
		if page.Visible then
			Kit.popAll(page)
		end
	end)
end

function ExpeditionsPage.draw(state, ui)
	if not state or not state.expedition then
		return
	end
	local colors = ui.colors
	local away = state.expedition
	local isAway = away.target ~= ""
	local home = ArmyConfig.countTroops(state.troops)
	local left = state.expeditionLeft or 0

	w.road.road.Visible = isAway
	w.road.home.Visible = isAway
	w.road.goal.Visible = isAway
	w.chips.Visible = not isAway
	if isAway then
		local target = ArmyConfig.getExpedition(away.target)
		local total = if target then target.minutes * 60 else 1
		local share = math.clamp((total - left) / math.max(1, total), 0, 1)
		w.marchTitle.Text = `\u{2694}\u{FE0F} Marching on {target and target.name or away.target}`
		w.marchNote.Text = `{ArmyConfig.countTroops(away.sent)} troops away. The battle is fought when they arrive.`
		w.road.goal.Text = (ENEMY_STYLE[target and target.enemy or "mixed"] or ENEMY_STYLE.mixed).glyph
		TweenService:Create(w.road.walked, TweenInfo.new(0.9, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(share, 1) }):Play()
		TweenService:Create(w.road.army, TweenInfo.new(0.9, Enum.EasingStyle.Linear), { Position = UDim2.new(share, -30, 0, -36) }):Play()
		w.road.clock.Text = `BACK IN {string.upper(Kit.clock(left))}`
		w.status.Text = `\u{1F6B6} <font color="#F0C450">AWAY</font>  {Kit.clock(left)}`
	else
		if wasAway then
			Kit.pop(w.panel, 1.05)
			Kit.float(ui, w.panel, "THE ARMY IS BACK!", Kit.GOLD)
		end
		w.marchTitle.Text = `\u{1F3F0} {home} troops at home`
		w.marchNote.Text = "Train troops that counter the enemy for more power."
		for _, troop in ArmyConfig.Troops do
			local count = state.troops[troop.key] or 0
			troopChips[troop.key].Text = `{TROOP_GLYPHS[troop.key] or ""} <font color="#F0C450">{count}</font>  {troop.name}`
		end
		w.status.Text = `\u{1F3F0} <font color="#6ED26E">HOME</font>  {home} troops`
	end
	wasAway = isAway

	for _, expedition in ArmyConfig.Expeditions do
		local part = cards[expedition.key]
		local attack = ArmyConfig.getPower(state.troops, expedition.enemy)
		local strong = attack >= expedition.power
		part.powerText.Text = `YOUR POWER <font color="{if strong then "#6ED26E" else "#E66A5A"}">{Format.short(attack)}</font>  VS  ENEMY <font color="#FFFFFF">{Format.short(expedition.power)}</font>`
		part.bar.fill.BackgroundColor3 = if strong then Kit.GREEN else Kit.RED
		Kit.setBar(part.bar, attack, expedition.power, if strong then "STRONG ENOUGH" else `{math.floor(math.min(1, attack / math.max(1, expedition.power)) * 100)}%`)
		local ready = false
		if state.level < expedition.level then
			ui.setButton(part.button, `\u{1F512} LEVEL {expedition.level}`, false, colors.action)
		elseif isAway then
			ui.setButton(part.button, if away.target == expedition.key then "\u{1F6B6} ARMY HERE" else "ARMY AWAY", false, colors.action)
		elseif home == 0 then
			ui.setButton(part.button, "NO TROOPS", false, colors.action)
		else
			ready = strong
			ui.setButton(part.button, if strong then "\u{2694}\u{FE0F} SEND ARMY" else "SEND ARMY (RISKY)", true, colors.action)
		end
		Kit.setPulse(part.stroke, ready, part.style.top)
	end
end

return ExpeditionsPage
