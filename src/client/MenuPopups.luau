-- Popups opened from the top-right MENU:
--   Settings  effects and notification switches, your title, promo codes
--   Stats     all-time numbers and where your attack and defense come from
--   Updates   what changed in the game, newest first
-- (Mail and Rankings have their own modules.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local RebirthConfig = require(Shared:WaitForChild("RebirthConfig"))
local Format = require(Shared:WaitForChild("Format"))

local MenuPopups = {}

local GREEN = Color3.fromRGB(90, 200, 100)
local OFF = Color3.fromRGB(70, 62, 54)
local MAX_TITLES = 24

-- Newest first. Shown in Updates.
local UPDATES = {
	{
		date = "26 Nov 2026",
		title = "Raids, guilds and the realm map",
		lines = {
			"Raids: attack other players' keeps for their gold on hand. Bank gold is always safe.",
			"Raids wound the defender; under 20 health they are incapacitated. Take revenge on anyone who raided you.",
			"Guilds: found or join one, donate to level it up, chat on the guild wall.",
			"Realm Map: guilds siege nine territories each week for bonuses.",
			"Foes and expeditions rebalanced to match real warband power.",
		},
	},
	{
		date = "25 Nov 2026",
		title = "Boss fights, battle pass and a new inventory",
		lines = {
			"Foes: a boss fight screen with a stage list, daily and first clear rewards.",
			"Token Shop: buy each house's gear set piece by piece.",
			"Royal Pass: a battle pass track with 50+ bonus rewards.",
			"Inventory: item cards, search, tabs and a rarity filter.",
			"Menu: Mail, Settings, Stats, Rankings and Updates in one place.",
		},
	},
	{
		date = "25 Nov 2026",
		title = "Holdings, Estate and Quests rebuilt",
		lines = {
			"Holdings pay together every 2.5 seconds, with a bar and a +gold pop.",
			"Building a holding takes 5 seconds; demolishing has its own animation.",
			"The Estate and Quests pages got picture cards and region banners.",
			"Auto quests: rule and activity tabs.",
		},
	},
	{
		date = "25 Nov 2026",
		title = "Warband and gear",
		lines = {
			"Soldiers roll their attack and defense once, when recruited.",
			"Timed training: +1% stats per rank, up to +10.",
			"Gear stacks without limit; the Relic Hall is a collection.",
		},
	},
}

local TILES = {
	{ "\u{1F5FA}\u{FE0F}", "Quests done", "quests" },
	{ "\u{1F409}", "Foes beaten", "foes" },
	{ "\u{2694}\u{FE0F}", "Attacks made", "attacks" },
	{ "\u{1F915}", "Knocked down", "knockdowns" },
	{ "\u{1F482}", "Recruits rolled", "rolls" },
	{ "\u{2696}\u{FE0F}", "Gear bought", "market" },
	{ "\u{1F4B0}", "Gold earned", "goldEarned" },
	{ "\u{231B}", "Time played", "playSeconds" },
	{ "\u{1F3C6}", "Trophies", "trophies" },
	{ "\u{1F3FA}", "Relic pieces", "relics" },
	{ "\u{1F31F}", "Rebirths", "rebirths" },
	{ "\u{1F39F}\u{FE0F}", "Codes used", "codes" },
}

local w = {}
local latest = nil

local function section(ui, page: Instance, title: string)
	local label = ui.makeText(page, UDim2.new(1, -10, 0, 30), UDim2.fromOffset(0, 0), ui.colors.gold, 20)
	label.LayoutOrder = ui.nextOrder()
	label.Font = ui.art.Fonts.heading
	label.Text = title
	return label
end

local function panel(ui, page: Instance, height: number): Frame
	local frame = ui.makeFrame(page, UDim2.new(1, -10, 0, height), UDim2.fromOffset(0, 0), Color3.fromRGB(30, 26, 22))
	frame.LayoutOrder = ui.nextOrder()
	ui.addCorner(frame, 8)
	ui.art.stroke(frame, ui.colors.dim, 1, 0.5)
	return frame
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

local function toggle(ui, parent: Instance, y: number, key: string, title: string, note: string)
	local colors = ui.colors
	local name = ui.makeText(parent, UDim2.new(1, -140, 0, 24), UDim2.fromOffset(16, y + 8), colors.text, 18)
	name.Font = Enum.Font.GothamBlack
	name.Text = title
	local sub = ui.makeText(parent, UDim2.new(1, -140, 0, 20), UDim2.fromOffset(16, y + 32), colors.dim, 13)
	sub.Text = note
	local switch = ui.makeButton(parent, UDim2.fromOffset(84, 38), UDim2.new(1, -104, 0, y + 10), OFF)
	switch.Text = ""
	switch:SetAttribute("NoGlow", true)
	ui.addCorner(switch, 19)
	local knob = ui.makeFrame(switch, UDim2.fromOffset(30, 30), UDim2.fromOffset(4, 4), Color3.new(1, 1, 1))
	ui.addCorner(knob, 15)
	ui.art.gloss(knob, 1, 0.7)
	local word = ui.makeText(switch, UDim2.new(1, -40, 1, 0), UDim2.fromOffset(38, 0), Color3.new(1, 1, 1), 13)
	word.Font = Enum.Font.GothamBlack
	word.TextXAlignment = Enum.TextXAlignment.Center
	local part = { switch = switch, knob = knob, word = word, on = nil }
	switch.Activated:Connect(function()
		local now = not part.on
		MenuPopups.setToggle(part, now, true)
		ui.send("Setting", `{key}:{if now then "on" else "off"}`)
	end)
	w.toggles[key] = part
end

function MenuPopups.setToggle(part, on: boolean, animate: boolean)
	if part.on == on then
		return
	end
	part.on = on
	local info = TweenInfo.new(if animate then 0.18 else 0, Enum.EasingStyle.Quad)
	TweenService:Create(part.knob, info, { Position = if on then UDim2.fromOffset(50, 4) else UDim2.fromOffset(4, 4) }):Play()
	TweenService:Create(part.switch, info, { BackgroundColor3 = if on then GREEN else OFF }):Play()
	part.word.Text = if on then "ON" else "OFF"
	part.word.Position = if on then UDim2.fromOffset(6, 0) else UDim2.fromOffset(38, 0)
end

local function buildSettings(ui)
	local page = ui.pages.Settings
	local colors = ui.colors
	w.toggles = {}
	section(ui, page, "Game")
	local box = panel(ui, page, 130)
	toggle(ui, box, 4, "effects", "Effects", "Damage numbers, level-up shower, income and quest pops")
	toggle(ui, box, 66, "toasts", "Notifications", "Messages in the bottom right corner")

	section(ui, page, "Title")
	local titleBox = panel(ui, page, 0)
	titleBox.AutomaticSize = Enum.AutomaticSize.Y
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = titleBox
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(1 / 3, -6, 0, 44)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = titleBox
	w.titleNote = ui.makeText(page, UDim2.new(1, -10, 0, 34), UDim2.fromOffset(0, 0), colors.dim, 13)
	w.titleNote.LayoutOrder = ui.nextOrder()
	w.titles = {}
	for index = 0, MAX_TITLES do
		local button = ui.makeButton(titleBox, UDim2.fromOffset(100, 44), UDim2.fromOffset(0, 0), colors.row)
		button.LayoutOrder = index
		button.TextSize = 14
		button.Font = Enum.Font.GothamBlack
		local entry = { button = button, title = if index == 0 then "" else nil }
		w.titles[index] = entry
		button.Activated:Connect(function()
			if entry.title then
				ui.send("Title", entry.title)
			end
		end)
	end

	section(ui, page, "Promo code")
	local codeRow = panel(ui, page, 60)
	local codeBox = ui.makeAmountBox(codeRow, UDim2.new(1, -150, 1, -16), UDim2.fromOffset(8, 8), "Type a code, then press Redeem")
	local redeem = ui.makeButton(codeRow, UDim2.fromOffset(124, 44), UDim2.new(1, -132, 0, 8), colors.buy)
	ui.setButton(redeem, "REDEEM", true, colors.buy)
	redeem.Font = Enum.Font.GothamBlack
	redeem.Activated:Connect(function()
		local text = string.sub(codeBox.Text, 1, 40)
		if text ~= "" then
			ui.send("Code", text)
			codeBox.Text = ""
		end
	end)
end

local function drawSettings(state, ui)
	local colors = ui.colors
	local settings = state.settings or {}
	for key, part in w.toggles do
		MenuPopups.setToggle(part, settings[key] ~= false, false)
	end
	local owned = {}
	for text in state.titles do
		table.insert(owned, text)
	end
	table.sort(owned)
	for index, entry in w.titles do
		if index == 0 then
			ui.setButton(entry.button, if state.title == "" then "NO TITLE \u{2714}" else "NO TITLE", state.title ~= "", colors.selected)
		else
			local text = owned[index]
			entry.title = text
			entry.button.Visible = text ~= nil
			if text then
				local using = state.title == text
				ui.setButton(entry.button, if using then `{text} \u{2714}` else text, not using, if using then colors.claim else colors.buy)
			end
		end
	end
	w.titleNote.Text = if #owned == 0
		then `No titles yet. Your first rebirth gives "{RebirthConfig.getTitle(1)}"; the Relic Hall, packs and codes give others.`
		else "The title you pick shows before your name."
end

---------------------------------------------------------------------------
-- Stats
---------------------------------------------------------------------------

local function tileValue(state, key: string): string
	if key == "playSeconds" then
		local seconds = math.floor(state.lifetime.playSeconds or 0)
		return `{seconds // 3600}h {seconds // 60 % 60}m`
	elseif key == "trophies" then
		local earned = 0
		for _ in state.trophies do
			earned += 1
		end
		return `{earned} / {#GameConfig.Trophies}`
	elseif key == "relics" then
		return Format.short(state.relics.count)
	elseif key == "rebirths" then
		return tostring(state.rebirth.count)
	end
	return Format.short(math.floor(state.lifetime[key] or 0))
end

local function buildStats(ui)
	local page = ui.pages.Stats
	local colors = ui.colors
	section(ui, page, "All-time record")
	local grid = ui.makeFrame(page, UDim2.new(1, -10, 0, 0), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	grid.BackgroundTransparency = 1
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.LayoutOrder = ui.nextOrder()
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(1 / 3, -6, 0, 66)
	layout.CellPadding = UDim2.fromOffset(8, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	w.tiles = {}
	for index, tile in TILES do
		local card = ui.makeFrame(grid, UDim2.fromOffset(100, 66), UDim2.fromOffset(0, 0), Color3.fromRGB(30, 26, 22))
		card.LayoutOrder = index
		ui.addCorner(card, 8)
		ui.art.stroke(card, colors.dim, 1, 0.5)
		local glyph = ui.makeText(card, UDim2.fromOffset(44, 66), UDim2.fromOffset(6, 0), Color3.new(1, 1, 1), 26)
		glyph.TextXAlignment = Enum.TextXAlignment.Center
		glyph.Text = tile[1]
		local label = ui.makeText(card, UDim2.new(1, -60, 0, 16), UDim2.fromOffset(54, 10), colors.dim, 11)
		label.Font = Enum.Font.GothamBold
		label.Text = string.upper(tile[2])
		local value = ui.makeText(card, UDim2.new(1, -60, 0, 28), UDim2.fromOffset(54, 28), colors.text, 22)
		value.Font = Enum.Font.GothamBlack
		w.tiles[index] = value
	end

	section(ui, page, "Where your power comes from")
	local box = panel(ui, page, 0)
	box.AutomaticSize = Enum.AutomaticSize.Y
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 2)
	list.Parent = box
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = box
	w.powerRows = {}
	for index = 0, 6 do
		local row = ui.makeFrame(box, UDim2.new(1, 0, 0, 34), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
		row.BackgroundTransparency = 1
		row.LayoutOrder = index
		local name = ui.makeText(row, UDim2.new(0.5, -16, 1, 0), UDim2.fromOffset(16, 0), colors.text, 16)
		name.Font = Enum.Font.GothamBold
		local attack = ui.makeText(row, UDim2.new(0.25, -10, 1, 0), UDim2.new(0.5, 0, 0, 0), Color3.fromRGB(255, 150, 120), 16)
		attack.Font = Enum.Font.GothamBlack
		attack.TextXAlignment = Enum.TextXAlignment.Right
		local defense = ui.makeText(row, UDim2.new(0.25, -20, 1, 0), UDim2.new(0.75, 0, 0, 0), Color3.fromRGB(140, 190, 255), 16)
		defense.Font = Enum.Font.GothamBlack
		defense.TextXAlignment = Enum.TextXAlignment.Right
		w.powerRows[index] = { row = row, name = name, attack = attack, defense = defense }
	end
	local head = w.powerRows[0]
	head.name.Text = "SOURCE"
	head.name.TextColor3 = colors.dim
	head.attack.Text = "\u{2694}\u{FE0F} ATTACK"
	head.defense.Text = "\u{1F6E1}\u{FE0F} DEFENSE"
end

local function drawStats(state, ui)
	for index, tile in TILES do
		w.tiles[index].Text = tileValue(state, tile[3])
	end
	local stats = state.stats
	local parts = stats.breakdown or {}
	for index = 1, 6 do
		local row = w.powerRows[index]
		local part = parts[index]
		if index == 6 then
			row.row.Visible = true
			row.name.Text = "TOTAL"
			row.name.TextColor3 = ui.colors.gold
			row.attack.Text = Format.short(stats.attack)
			row.defense.Text = Format.short(stats.defense)
		else
			row.row.Visible = part ~= nil
			if part then
				row.name.Text = part[1]
				local sign = if index == 5 then "+" else ""
				row.attack.Text = sign .. Format.short(math.floor(part[2]))
				row.defense.Text = sign .. Format.short(math.floor(part[3]))
			end
		end
	end
end

---------------------------------------------------------------------------
-- Updates
---------------------------------------------------------------------------

local function buildUpdates(ui)
	local page = ui.pages.Updates
	local colors = ui.colors
	for index, entry in UPDATES do
		local card = ui.makeFrame(page, UDim2.new(1, -10, 0, 0), UDim2.fromOffset(0, 0), Color3.fromRGB(30, 26, 22))
		card.LayoutOrder = ui.nextOrder()
		card.AutomaticSize = Enum.AutomaticSize.Y
		ui.addCorner(card, 8)
		ui.art.stroke(card, if index == 1 then colors.gold else colors.dim, if index == 1 then 2 else 1, 0.3)
		local list = Instance.new("UIListLayout")
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Padding = UDim.new(0, 4)
		list.Parent = card
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 10)
		pad.PaddingBottom = UDim.new(0, 12)
		pad.PaddingLeft = UDim.new(0, 16)
		pad.PaddingRight = UDim.new(0, 16)
		pad.Parent = card
		local date = ui.makeText(card, UDim2.new(1, 0, 0, 16), UDim2.fromOffset(0, 0), colors.dim, 12)
		date.LayoutOrder = 1
		date.Font = Enum.Font.GothamBold
		date.Text = if index == 1 then `NEW  \u{00B7}  {string.upper(entry.date)}` else string.upper(entry.date)
		if index == 1 then
			date.TextColor3 = GREEN
		end
		local title = ui.makeText(card, UDim2.new(1, 0, 0, 28), UDim2.fromOffset(0, 0), colors.gold, 20)
		title.LayoutOrder = 2
		title.Font = ui.art.Fonts.heading
		title.Text = entry.title
		for order, line in entry.lines do
			local text = ui.makeText(card, UDim2.new(1, 0, 0, 0), UDim2.fromOffset(0, 0), colors.text, 14)
			text.LayoutOrder = 2 + order
			text.AutomaticSize = Enum.AutomaticSize.Y
			text.Text = `\u{2022}  {line}`
		end
	end
end

---------------------------------------------------------------------------

function MenuPopups.build(ui)
	buildSettings(ui)
	buildStats(ui)
	buildUpdates(ui)
end

function MenuPopups.draw(state, ui)
	if not state then
		return
	end
	latest = state
	local Fx = require(script.Parent:WaitForChild("Fx"))
	Fx.quiet = state.settings ~= nil and state.settings.effects == false
	if ui.isOpen("Settings") then
		drawSettings(state, ui)
	end
	if ui.isOpen("Stats") then
		drawStats(state, ui)
	end
end

return MenuPopups
