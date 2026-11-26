-- War Chronicle page (Arena section): reports of foe fights and
-- expeditions, newest first.
--   * banner with win / loss counts,
--   * a report card per battle: colored VICTORY / DEFEAT ribbon, picture,
--     title, time ago, the story, and for expeditions a row per round
--     with the enemy's health bar draining.
-- A new report pops in with a bright outline.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArmyConfig = require(Shared:WaitForChild("ArmyConfig"))
local Format = require(Shared:WaitForChild("Format"))
local Kit = require(script.Parent:WaitForChild("Kit"))

local ChroniclePage = {}

local MAX_ROUNDS = 6
local w = {}
local cards = {}
local lastTop = nil

local function ago(seconds: number): string
	if seconds < 60 then
		return "JUST NOW"
	elseif seconds < 3600 then
		return `{math.floor(seconds / 60)}M AGO`
	elseif seconds < 86400 then
		return `{math.floor(seconds / 3600)}H AGO`
	end
	return `{math.floor(seconds / 86400)}D AGO`
end

local function buildCard(ui, list: Instance, index: number)
	local card = ui.makeFrame(list, UDim2.new(1, 0, 0, 96), UDim2.fromOffset(0, 0), Kit.CARD)
	card.LayoutOrder = index
	card.ClipsDescendants = true
	ui.addCorner(card, 10)
	local stroke = ui.art.stroke(card, ui.colors.dim, 1.5, 0.3)
	local ribbon = ui.makeFrame(card, UDim2.new(0, 8, 1, 0), UDim2.fromOffset(0, 0), ui.colors.dim)
	local disc, glyph = Kit.badge(ui, card, "\u{2694}\u{FE0F}", 56, UDim2.fromOffset(20, 14), Color3.fromRGB(70, 56, 40))
	local tag = ui.makeText(card, UDim2.fromOffset(96, 22), UDim2.fromOffset(88, 12), Color3.new(1, 1, 1), 12)
	tag.BackgroundTransparency = 0
	tag.Font = Enum.Font.GothamBlack
	tag.TextXAlignment = Enum.TextXAlignment.Center
	ui.addCorner(tag, 5)
	local title = ui.makeText(card, UDim2.new(1, -310, 0, 24), UDim2.fromOffset(194, 11), ui.colors.text, 16)
	title.Font = Enum.Font.GothamBlack
	title.TextTruncate = Enum.TextTruncate.AtEnd
	local when = ui.makeText(card, UDim2.fromOffset(100, 22), UDim2.new(1, -114, 0, 12), ui.colors.dim, 12)
	when.Font = Enum.Font.GothamBlack
	when.TextXAlignment = Enum.TextXAlignment.Right
	local story = ui.makeText(card, UDim2.new(1, -110, 0, 40), UDim2.fromOffset(88, 40), ui.colors.dim, 13)
	story.Font = Enum.Font.GothamBold
	story.TextWrapped = true
	story.TextYAlignment = Enum.TextYAlignment.Top
	local rounds = {}
	for round = 1, MAX_ROUNDS do
		local y = 86 + (round - 1) * 26
		local label = ui.makeText(card, UDim2.fromOffset(70, 20), UDim2.fromOffset(88, y), Kit.GOLD, 11)
		label.Font = Enum.Font.GothamBlack
		label.Text = `ROUND {round}`
		local bar = Kit.bar(ui, card, UDim2.new(0.45, -90, 0, 18), UDim2.fromOffset(160, y + 1), Kit.RED)
		local note = ui.makeText(card, UDim2.new(0.55, -100, 0, 20), UDim2.new(0.45, 80, 0, y), ui.colors.text, 12)
		note.Font = Enum.Font.GothamBold
		note.RichText = true
		rounds[round] = { label = label, bar = bar, note = note }
	end
	cards[index] = {
		card = card,
		stroke = stroke,
		ribbon = ribbon,
		disc = disc,
		glyph = glyph,
		tag = tag,
		title = title,
		when = when,
		story = story,
		rounds = rounds,
	}
end

function ChroniclePage.build(ui)
	local page = ui.pages["War Chronicle"]
	local banner = Kit.banner(ui, page, 1, 120, Color3.fromRGB(130, 40, 40), Color3.fromRGB(40, 14, 14), "War Chronicle", "\u{1F4D6}")
	w.status = Kit.line(ui, banner, 120, 66, UDim.new(0.5, -120), 18, Color3.new(1, 1, 1))
	w.status.Font = Enum.Font.GothamBlack
	local note = Kit.line(ui, banner, 0, 0, UDim.new(0.4, 0), 13, Color3.fromRGB(255, 215, 205))
	note.Position = UDim2.new(0.58, 0, 0, 40)
	note.Size = UDim2.new(0.4, -10, 0, 44)
	note.TextWrapped = true
	note.Text = `Every foe fight and expedition is written here. The last {ArmyConfig.ChronicleKept} are kept.`

	local list = ui.makeFrame(page, UDim2.new(1, -10, 0, 0), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	list.BackgroundTransparency = 1
	list.AutomaticSize = Enum.AutomaticSize.Y
	list.LayoutOrder = 2
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	w.empty = ui.makeText(list, UDim2.new(1, 0, 0, 80), UDim2.fromOffset(0, 0), ui.colors.dim, 15)
	w.empty.LayoutOrder = 0
	w.empty.TextXAlignment = Enum.TextXAlignment.Center
	w.empty.TextWrapped = true
	w.empty.Text = "\u{1F54A}\u{FE0F}  No battles yet. Beat a foe or send an expedition and the report shows up here."
	for index = 1, ArmyConfig.ChronicleKept do
		buildCard(ui, list, index)
	end
end

function ChroniclePage.draw(state, ui)
	if not state or not state.chronicle then
		return
	end
	local colors = ui.colors
	local now = os.time()
	local reports = state.chronicle
	w.empty.Visible = #reports == 0
	local wins, losses = 0, 0
	for _, report in reports do
		if report.win == true then
			wins += 1
		elseif report.win == false then
			losses += 1
		end
	end
	w.status.Text = `<font color="#6ED26E">{wins} WON</font>   <font color="#E66A5A">{losses} LOST</font>`

	for index, part in cards do
		local report = reports[index]
		part.card.Visible = report ~= nil
		if not report then
			continue
		end
		local color = if report.win == true then Kit.GREEN elseif report.win == false then Kit.RED else colors.dim
		local isExpedition = string.sub(report.title, 1, 10) == "Expedition"
		part.ribbon.BackgroundColor3 = color
		part.stroke.Color = color
		part.glyph.Text = if isExpedition then "\u{1F5FA}\u{FE0F}" elseif report.win == false then "\u{1F480}" else "\u{1F409}"
		part.tag.BackgroundColor3 = color:Lerp(Color3.new(0, 0, 0), 0.35)
		part.tag.Text = if report.win == true then "\u{1F3C6} VICTORY" elseif report.win == false then "\u{1F480} DEFEAT" else "REPORT"
		part.title.Text = report.title
		part.when.Text = ago(now - (report.time or now))
		part.story.Text = report.text or ""
		local roundCount = 0
		for round, row in part.rounds do
			local entry = report.rounds and report.rounds[round]
			row.label.Visible = entry ~= nil
			row.bar.back.Visible = entry ~= nil
			row.note.Visible = entry ~= nil
			if entry then
				roundCount = round
				local full = report.enemyHealth or 0
				local leftShare = if full > 0 then entry.enemyLeft / full else 0
				Kit.setBar(row.bar, entry.enemyLeft, full, `ENEMY {math.floor(leftShare * 100 + 0.5)}%`)
				row.note.Text = `\u{2694}\u{FE0F} <font color="#6ED26E">{Format.short(entry.dealt)}</font>   \u{1F494} <font color="#E66A5A">{Format.short(entry.taken)}</font>`
			end
		end
		part.card.Size = UDim2.new(1, 0, 0, 90 + roundCount * 26)
	end

	-- pop the newest report when it arrives
	local top = reports[1] and reports[1].id
	if top ~= lastTop then
		if lastTop ~= nil and top and cards[1] then
			local card = cards[1].card
			Kit.pop(card, 0.8)
			cards[1].stroke.Thickness = 5
			TweenService:Create(cards[1].stroke, TweenInfo.new(0.8), { Thickness = 1.5 }):Play()
		end
		lastTop = top
	end
end

return ChroniclePage
