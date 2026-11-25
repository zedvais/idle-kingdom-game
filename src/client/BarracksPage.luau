-- Barracks page: train troops for expeditions. Each troop type is strong
-- against one kind of enemy.
--   * banner with the army size,
--   * training yard panel: army capacity bar split home / away / training,
--     the batch in training with its own bar and Finish now,
--   * a picture card per troop: big emoji, owned count, attack / defense
--     chips, counter note, cost tiles, Train 1 and Train X.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArmyConfig = require(Shared:WaitForChild("ArmyConfig"))
local ResearchConfig = require(Shared:WaitForChild("ResearchConfig"))
local Format = require(Shared:WaitForChild("Format"))
local Kit = require(script.Parent:WaitForChild("Kit"))

local BarracksPage = {}

local TROOP_STYLE = {
	spear = { glyph = "\u{1F531}", color = Color3.fromRGB(150, 120, 80) },
	archer = { glyph = "\u{1F3F9}", color = Color3.fromRGB(90, 150, 90) },
	cavalry = { glyph = "\u{1F40E}", color = Color3.fromRGB(170, 110, 60) },
	knight = { glyph = "\u{1F6E1}\u{FE0F}", color = Color3.fromRGB(120, 140, 190) },
	siege = { glyph = "\u{1FAB5}", color = Color3.fromRGB(140, 100, 70) },
}
local RESOURCE_GLYPHS = {
	lumber = "\u{1FAB5}",
	stone = "\u{1FAA8}",
	iron = "\u{26D3}\u{FE0F}",
	grain = "\u{1F33E}",
}

local w = {}
local cards = {}
local latest = nil -- the last state drawn, for the Train X popup
local lastHave = {}

-- How many of a troop you could train right now.
local function canTrain(state, troop): number
	local total = ArmyConfig.countTroops(state.troops) + ArmyConfig.countTroops(state.expedition.sent) + state.training.count
	local room = state.armyCap - total
	local most = math.min(room, math.floor(state.gold / troop.cost))
	for resource, amount in troop.resources or {} do
		most = math.min(most, math.floor((state.estate.stock[resource] or 0) / amount))
	end
	return math.max(0, most)
end

-- "3 grain, 2 lumber" for one troop.
local function resourceText(troop): string
	local parts = {}
	for resource, amount in troop.resources or {} do
		table.insert(parts, `{amount} {resource}`)
	end
	table.sort(parts)
	return table.concat(parts, ", ")
end

local function chip(ui, parent: Instance, position: UDim2, width: number, color: Color3): TextLabel
	local label = ui.makeText(parent, UDim2.fromOffset(width, 22), position, Color3.new(1, 1, 1), 12)
	label.BackgroundTransparency = 0
	label.BackgroundColor3 = color
	label.Font = Enum.Font.GothamBlack
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.RichText = true
	ui.addCorner(label, 5)
	return label
end

local function buildYard(ui, page: Instance)
	local panel = ui.makeFrame(page, UDim2.new(1, -10, 0, 128), UDim2.fromOffset(0, 0), Kit.CARD)
	panel.LayoutOrder = 2
	ui.addCorner(panel, 10)
	ui.art.stroke(panel, ui.colors.gold, 2, 0.25)
	local capTitle = ui.makeText(panel, UDim2.new(1, -230, 0, 22), UDim2.fromOffset(14, 10), ui.colors.text, 16)
	capTitle.Font = ui.art.Fonts.heading
	capTitle.RichText = true
	w.capTitle = capTitle
	-- capacity bar split in three
	local back = ui.makeFrame(panel, UDim2.new(1, -230, 0, 22), UDim2.fromOffset(14, 36), Color3.fromRGB(16, 14, 12))
	back.ClipsDescendants = true
	ui.addCorner(back, 6)
	local function segment(color)
		local frame = ui.makeFrame(back, UDim2.fromScale(0, 1), UDim2.fromOffset(0, 0), color)
		ui.art.gloss(frame, 1, 0.7)
		return frame
	end
	w.capHome = segment(Kit.GREEN)
	w.capAway = segment(Kit.GOLD)
	w.capTrain = segment(Color3.fromRGB(110, 160, 240))
	w.capLegend = ui.makeText(panel, UDim2.new(1, -230, 0, 18), UDim2.fromOffset(14, 60), ui.colors.dim, 12)
	w.capLegend.Font = Enum.Font.GothamBold
	w.capLegend.RichText = true

	-- the current batch
	w.batchGlyph = ui.makeText(panel, UDim2.fromOffset(36, 36), UDim2.fromOffset(12, 84), Color3.new(1, 1, 1), 26)
	w.batchGlyph.TextXAlignment = Enum.TextXAlignment.Center
	Kit.bob(w.batchGlyph, 2, 6)
	w.batchBar = Kit.bar(ui, panel, UDim2.new(1, -284, 0, 24), UDim2.fromOffset(54, 90), Color3.fromRGB(110, 160, 240))

	local finish = ui.makeButton(panel, UDim2.fromOffset(190, 56), UDim2.new(1, -206, 0.5, -28), ui.colors.selected)
	finish.TextSize = 15
	finish.Font = Enum.Font.GothamBlack
	finish.Activated:Connect(function()
		Kit.pop(panel, 1.04)
		ui.send("TroopFinish")
	end)
	w.finish = finish
	w.panel = panel
end

local function buildTroop(ui, grid: Instance, index: number, troop)
	local style = TROOP_STYLE[troop.key] or { glyph = "\u{1F482}", color = ui.colors.gold }
	local card, stroke = Kit.card(ui, grid, index, style.color)
	-- picture strip
	local scene = ui.makeFrame(card, UDim2.new(1, 0, 0, 80), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1))
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(style.color, style.color:Lerp(Color3.new(0, 0, 0), 0.7))
	gradient.Parent = scene
	ui.art.grain(scene)
	local glyph = ui.makeText(scene, UDim2.fromOffset(76, 76), UDim2.fromOffset(8, 2), Color3.new(1, 1, 1), 50)
	glyph.TextXAlignment = Enum.TextXAlignment.Center
	glyph.Text = style.glyph
	glyph.ZIndex = 410
	local name = ui.makeText(scene, UDim2.new(1, -96, 0, 26), UDim2.fromOffset(88, 10), ui.colors.gold, 20)
	name.Font = ui.art.Fonts.heading
	name.Text = troop.name
	name.TextStrokeTransparency = 0.4
	name.ZIndex = 410
	local have = ui.makeText(scene, UDim2.new(1, -96, 0, 20), UDim2.fromOffset(88, 40), Color3.new(1, 1, 1), 13)
	have.Font = Enum.Font.GothamBlack
	have.RichText = true
	have.ZIndex = 410
	local lock = ui.makeText(scene, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.fromRGB(240, 210, 180), 16)
	lock.BackgroundTransparency = 0.35
	lock.BackgroundColor3 = Color3.new(0, 0, 0)
	lock.Font = Enum.Font.GothamBlack
	lock.TextXAlignment = Enum.TextXAlignment.Center
	lock.Text = `\u{1F512} UNLOCKS AT LEVEL {troop.level}`
	lock.ZIndex = 450

	chip(ui, card, UDim2.fromOffset(12, 88), 74, Color3.fromRGB(150, 60, 50)).Text = `\u{2694}\u{FE0F} {troop.attack}`
	chip(ui, card, UDim2.fromOffset(92, 88), 74, Color3.fromRGB(60, 90, 150)).Text = `\u{1F6E1}\u{FE0F} {troop.defense}`
	chip(ui, card, UDim2.fromOffset(172, 88), 66, Color3.fromRGB(70, 60, 46)).Text = `\u{23F3} {troop.seconds}s`
	local note = ui.makeText(card, UDim2.new(1, -24, 0, 18), UDim2.fromOffset(12, 114), Kit.GOLD, 12)
	note.Font = Enum.Font.GothamBold
	note.Text = `\u{2728} {troop.note}`

	local costs = { `\u{1F4B0} {Format.short(troop.cost)}` }
	local resources = {}
	for resource in troop.resources or {} do
		table.insert(resources, resource)
	end
	table.sort(resources)
	for _, resource in resources do
		table.insert(costs, `{RESOURCE_GLYPHS[resource] or ""} {troop.resources[resource]}`)
	end
	local cost = ui.makeText(card, UDim2.new(1, -24, 0, 18), UDim2.fromOffset(12, 134), ui.colors.dim, 12)
	cost.Font = Enum.Font.GothamBlack
	cost.Text = "EACH: " .. table.concat(costs, "   ")

	local one = ui.makeButton(card, UDim2.new(0.5, -16, 0, 38), UDim2.new(0, 12, 1, -48), ui.colors.buy)
	one.TextSize = 14
	one.Font = Enum.Font.GothamBlack
	local many = ui.makeButton(card, UDim2.new(0.5, -16, 0, 38), UDim2.new(0.5, 4, 1, -48), ui.colors.buy)
	many.TextSize = 14
	many.Font = Enum.Font.GothamBlack
	one.Activated:Connect(function()
		Kit.pop(card, 1.06)
		ui.send("TroopTrain", `{troop.key}:1`)
	end)
	many.Activated:Connect(function()
		if not latest then
			return
		end
		local most = canTrain(latest, troop)
		if most < 1 then
			return
		end
		ui.askAmount({
			title = `Train {troop.name}`,
			note = `<b>{troop.name}</b>: {Format.short(troop.cost)} gold, {resourceText(troop)} and {troop.seconds}s each.`,
			max = most,
			confirm = "Train",
			onConfirm = function(amount)
				Kit.pop(card, 1.06)
				ui.send("TroopTrain", `{troop.key}:{amount}`)
			end,
		})
	end)
	cards[troop.key] = { card = card, stroke = stroke, have = have, lock = lock, button = one, many = many, glyph = glyph }
end

function BarracksPage.build(ui)
	local page = ui.pages.Barracks
	local banner = Kit.banner(ui, page, 1, 120, Color3.fromRGB(110, 60, 40), Color3.fromRGB(36, 22, 16), "Barracks", "\u{1F6E1}\u{FE0F}")
	w.status = Kit.line(ui, banner, 120, 66, UDim.new(0.5, -120), 18, Color3.new(1, 1, 1))
	w.status.Font = Enum.Font.GothamBlack
	local note = Kit.line(ui, banner, 0, 0, UDim.new(0.4, 0), 13, Color3.fromRGB(255, 225, 205))
	note.Position = UDim2.new(0.58, 0, 0, 34)
	note.Size = UDim2.new(0.4, -10, 0, 56)
	note.TextWrapped = true
	note.Text = `One batch trains at a time and keeps going while you are away. Each Keep level adds +{ArmyConfig.CapPerKeep} army room.`
	buildYard(ui, page)
	Kit.heading(ui, page, 3, "Troops", ui.colors.gold)
	local grid = Kit.grid(ui, page, 4, 232, 3)
	for index, troop in ArmyConfig.Troops do
		buildTroop(ui, grid, index, troop)
	end
	page:GetPropertyChangedSignal("Visible"):Connect(function()
		if page.Visible then
			Kit.popAll(page)
		end
	end)
end

function BarracksPage.draw(state, ui)
	if not state or not state.training then
		return
	end
	latest = state
	local colors = ui.colors
	local home = ArmyConfig.countTroops(state.troops)
	local away = ArmyConfig.countTroops(state.expedition.sent)
	local training = state.training
	local total = home + away + training.count
	local cap = math.max(1, state.armyCap)
	local busy = training.count > 0

	w.capTitle.Text = `ARMY <font color="#F0C450">{total} / {state.armyCap}</font>`
	w.capHome.Size = UDim2.fromScale(home / cap, 1)
	w.capAway.Size = UDim2.fromScale(away / cap, 1)
	w.capAway.Position = UDim2.fromScale(home / cap, 0)
	w.capTrain.Size = UDim2.fromScale(training.count / cap, 1)
	w.capTrain.Position = UDim2.fromScale((home + away) / cap, 0)
	w.capLegend.Text = `\u{1F7E9} {home} home   \u{1F7E8} {away} away   \u{1F7E6} {training.count} training`
	w.status.Text = `\u{1F482} <font color="#F0C450">{total}</font> / {state.armyCap} troops`

	if busy then
		local troop = ArmyConfig.getTroop(training.kind)
		local totalSeconds = if troop then troop.seconds * training.count else 0
		w.batchGlyph.Text = (TROOP_STYLE[training.kind] or { glyph = "\u{1F482}" }).glyph
		Kit.setBar(w.batchBar, totalSeconds - state.trainingLeft, totalSeconds, `TRAINING {training.count} {string.upper(troop and troop.name or training.kind)}  \u{2022}  {ui.formatLong(state.trainingLeft)}`)
		local cost = ResearchConfig.getFinishCost(state.trainingLeft)
		ui.setButton(w.finish, `FINISH NOW\n\u{1F451} {cost} CROWNS`, state.crowns >= cost, colors.selected)
	else
		w.batchGlyph.Text = "\u{1F3D5}\u{FE0F}"
		Kit.setBar(w.batchBar, 0, 1, "THE YARD IS FREE")
		ui.setButton(w.finish, "IDLE", false, colors.selected)
	end

	local room = state.armyCap - total
	for _, troop in ArmyConfig.Troops do
		local part = cards[troop.key]
		local have = state.troops[troop.key] or 0
		part.have.Text = `YOU HAVE <font color="#F0C450">{have}</font>`
		if lastHave[troop.key] and have > lastHave[troop.key] then
			Kit.pop(part.card, 1.08)
			Kit.float(ui, part.card, `+{have - lastHave[troop.key]} {troop.name}`, Kit.GREEN)
		end
		lastHave[troop.key] = have
		local locked = state.level < troop.level
		part.lock.Visible = locked
		local most = canTrain(state, troop)
		if locked then
			ui.setButton(part.button, `LEVEL {troop.level}`, false, colors.buy)
			ui.setButton(part.many, "LOCKED", false, colors.buy)
		elseif busy then
			ui.setButton(part.button, "BUSY", false, colors.buy)
			ui.setButton(part.many, "BUSY", false, colors.buy)
		elseif room <= 0 then
			ui.setButton(part.button, "ARMY FULL", false, colors.buy)
			ui.setButton(part.many, "ARMY FULL", false, colors.buy)
		else
			ui.setButton(part.button, "TRAIN 1", most >= 1, colors.buy)
			ui.setButton(part.many, if most >= 1 then `TRAIN X ({most})` else "TRAIN X", most >= 1, colors.buy)
		end
	end
end

return BarracksPage
