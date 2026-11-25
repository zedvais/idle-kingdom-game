-- Rankings page: all-time boards shared by every server.
--   * banner with the update note,
--   * board tabs (Mightiest, Most experienced, ...),
--   * a podium for the top 3 (gold, silver, bronze columns rising up),
--   * rows 4-10 with rank badges, and your own row pinned at the bottom.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ProfileConfig = require(Shared:WaitForChild("ProfileConfig"))
local Format = require(Shared:WaitForChild("Format"))
local Kit = require(script.Parent:WaitForChild("Kit"))

local RankingsPage = {}

local BOARD_GLYPHS = {
	power = "\u{2694}\u{FE0F}",
	level = "\u{2B50}",
	renown = "\u{1F3C5}",
	rebirths = "\u{1F31F}",
}
local MEDALS = {
	{ glyph = "\u{1F947}", color = Color3.fromRGB(240, 196, 80), height = 120 },
	{ glyph = "\u{1F948}", color = Color3.fromRGB(200, 205, 215), height = 92 },
	{ glyph = "\u{1F949}", color = Color3.fromRGB(205, 140, 80), height = 72 },
}
local PODIUM_SLOTS = { 2, 1, 3 } -- left to right

local w = {}
local tabs = {}
local podium = {}
local rows = {}
local selected = "power"
local lastKey = nil
local lastState = nil
local uiRef = nil

-- Your own score on a board, worked out from the state.
local function myScore(state, key: string): number
	if key == "power" then
		return state.stats.attack + state.stats.defense
	elseif key == "level" then
		return state.level
	elseif key == "renown" then
		return state.renown
	elseif key == "rebirths" then
		return state.rebirth.count
	end
	return 0
end

local function buildPodium(ui, page: Instance)
	local stage = ui.makeFrame(page, UDim2.new(1, -10, 0, 230), UDim2.fromOffset(0, 0), Color3.fromRGB(26, 22, 18))
	stage.LayoutOrder = 3
	stage.ClipsDescendants = true
	ui.addCorner(stage, 10)
	ui.art.stroke(stage, ui.colors.gold, 1.5, 0.4)
	ui.art.grain(stage)
	for column, place in PODIUM_SLOTS do
		local medal = MEDALS[place]
		local x = (column - 1) / 3
		local holder = ui.makeFrame(stage, UDim2.new(1 / 3, -24, 1, -10), UDim2.new(x, 12, 0, 10), Color3.new(0, 0, 0))
		holder.BackgroundTransparency = 1
		local block = ui.makeFrame(holder, UDim2.new(1, 0, 0, medal.height), UDim2.new(0, 0, 1, 0), Color3.new(1, 1, 1))
		block.AnchorPoint = Vector2.new(0, 1)
		ui.addCorner(block, 8)
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Color = ColorSequence.new(medal.color, medal.color:Lerp(Color3.new(0, 0, 0), 0.55))
		gradient.Parent = block
		ui.art.gloss(block, 1, 0.7)
		local number = ui.makeText(block, UDim2.new(1, 0, 0, 40), UDim2.fromOffset(0, 8), Color3.new(1, 1, 1), 34)
		number.Font = ui.art.Fonts.title
		number.TextXAlignment = Enum.TextXAlignment.Center
		number.TextStrokeTransparency = 0.3
		number.Text = tostring(place)
		number.ZIndex = block.ZIndex + 3
		local medalLabel = ui.makeText(holder, UDim2.new(1, 0, 0, 40), UDim2.new(0, 0, 1, -medal.height - 92), Color3.new(1, 1, 1), 34)
		medalLabel.TextXAlignment = Enum.TextXAlignment.Center
		medalLabel.Text = medal.glyph
		Kit.bob(medalLabel, 3, 1.5 + place * 0.3)
		local name = ui.makeText(holder, UDim2.new(1, 0, 0, 24), UDim2.new(0, 0, 1, -medal.height - 50), ui.colors.text, 16)
		name.Font = Enum.Font.GothamBlack
		name.TextXAlignment = Enum.TextXAlignment.Center
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.RichText = true
		local score = ui.makeText(holder, UDim2.new(1, 0, 0, 20), UDim2.new(0, 0, 1, -medal.height - 26), medal.color, 14)
		score.Font = Enum.Font.GothamBlack
		score.TextXAlignment = Enum.TextXAlignment.Center
		podium[place] = { block = block, name = name, score = score, height = medal.height }
	end
end

local function buildRows(ui, page: Instance)
	local list = ui.makeFrame(page, UDim2.new(1, -10, 0, 0), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	list.BackgroundTransparency = 1
	list.AutomaticSize = Enum.AutomaticSize.Y
	list.LayoutOrder = 4
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	for index = 4, ProfileConfig.BoardSize do
		local row = ui.makeFrame(list, UDim2.new(1, 0, 0, 40), UDim2.fromOffset(0, 0), Kit.CARD)
		row.LayoutOrder = index
		ui.addCorner(row, 8)
		local stroke = ui.art.stroke(row, ui.colors.dim, 1, 0.6)
		local scale = Instance.new("UIScale")
		scale.Name = "Pop"
		scale.Parent = row
		local disc = ui.makeFrame(row, UDim2.fromOffset(30, 30), UDim2.fromOffset(8, 5), Color3.fromRGB(70, 60, 46))
		ui.addCorner(disc, 15)
		local rank = ui.makeText(disc, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), ui.colors.text, 13)
		rank.Font = Enum.Font.GothamBlack
		rank.TextXAlignment = Enum.TextXAlignment.Center
		rank.Text = tostring(index)
		local name = ui.makeText(row, UDim2.new(0.6, -50, 1, 0), UDim2.fromOffset(48, 0), ui.colors.text, 15)
		name.Font = Enum.Font.GothamBold
		name.RichText = true
		local score = ui.makeText(row, UDim2.new(0.4, -16, 1, 0), UDim2.new(0.6, 0, 0, 0), Kit.GOLD, 15)
		score.Font = Enum.Font.GothamBlack
		score.TextXAlignment = Enum.TextXAlignment.Right
		rows[index] = { row = row, stroke = stroke, name = name, score = score }
	end
	-- you
	local mine = ui.makeFrame(list, UDim2.new(1, 0, 0, 48), UDim2.fromOffset(0, 0), Color3.fromRGB(56, 44, 22))
	mine.LayoutOrder = 100
	ui.addCorner(mine, 8)
	ui.art.stroke(mine, ui.colors.gold, 2, 0.1)
	ui.art.gloss(mine, 1, 0.85)
	local label = ui.makeText(mine, UDim2.new(0.6, -16, 1, 0), UDim2.fromOffset(14, 0), ui.colors.gold, 16)
	label.Font = Enum.Font.GothamBlack
	label.RichText = true
	local score = ui.makeText(mine, UDim2.new(0.4, -16, 1, 0), UDim2.new(0.6, 0, 0, 0), Color3.new(1, 1, 1), 17)
	score.Font = Enum.Font.GothamBlack
	score.TextXAlignment = Enum.TextXAlignment.Right
	w.mine = { label = label, score = score }
	w.empty = ui.makeText(list, UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 0), ui.colors.dim, 13)
	w.empty.LayoutOrder = 99
	w.empty.TextXAlignment = Enum.TextXAlignment.Center
	w.empty.Text = "No scores yet. Boards fill in once the game is published and players have saved."
end

local function selectBoard(key: string)
	selected = key
	if lastState and uiRef then
		RankingsPage.draw(lastState, uiRef)
	end
end

function RankingsPage.build(ui)
	uiRef = ui
	local page = ui.pages.Rankings
	local banner = Kit.banner(ui, page, 1, 120, Color3.fromRGB(150, 110, 40), Color3.fromRGB(50, 34, 12), "Hall of Fame", "\u{1F3C6}")
	w.status = Kit.line(ui, banner, 120, 66, UDim.new(0.5, -120), 18, Color3.new(1, 1, 1))
	w.status.Font = Enum.Font.GothamBlack
	local note = Kit.line(ui, banner, 0, 0, UDim.new(0.4, 0), 13, Color3.fromRGB(255, 235, 200))
	note.Position = UDim2.new(0.58, 0, 0, 40)
	note.Size = UDim2.new(0.4, -10, 0, 44)
	note.TextWrapped = true
	note.Text = `Boards cover every server and update about every {math.floor(ProfileConfig.BoardSeconds / 60)} minutes.`

	local tabRow = ui.makeFrame(page, UDim2.new(1, -10, 0, 48), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	tabRow.BackgroundTransparency = 1
	tabRow.LayoutOrder = 2
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = tabRow
	local count = #ProfileConfig.Boards
	for index, board in ProfileConfig.Boards do
		local button = ui.makeButton(tabRow, UDim2.new(1 / count, -8, 1, 0), UDim2.fromOffset(0, 0), ui.colors.row)
		button.LayoutOrder = index
		button.TextSize = 14
		button.Font = Enum.Font.GothamBlack
		button.Text = `{BOARD_GLYPHS[board.key] or ""} {string.upper(board.name)}`
		button.Activated:Connect(function()
			selectBoard(board.key)
		end)
		tabs[board.key] = button
	end
	buildPodium(ui, page)
	buildRows(ui, page)
	page:GetPropertyChangedSignal("Visible"):Connect(function()
		if page.Visible then
			Kit.popAll(page)
			lastKey = nil
			if lastState then
				RankingsPage.draw(lastState, ui)
			end
		end
	end)
end

function RankingsPage.draw(state, ui)
	if not state or not state.rankings then
		return
	end
	lastState = state
	local colors = ui.colors
	local board = ProfileConfig.Boards[1]
	for _, entry in ProfileConfig.Boards do
		if entry.key == selected then
			board = entry
		end
		ui.setButton(tabs[entry.key], `{BOARD_GLYPHS[entry.key] or ""} {string.upper(entry.name)}`, true, if entry.key == selected then colors.selected else colors.row)
	end
	local list = state.rankings[board.key] or {}
	local me = ui.player.Name
	local myRank = nil
	for index, entry in list do
		if entry[1] == me then
			myRank = index
		end
	end
	local changed = lastKey ~= board.key
	lastKey = board.key

	for place, part in podium do
		local entry = list[place]
		if entry then
			local you = entry[1] == me
			part.name.Text = if you then `<font color="#F0C450">{entry[1]} (you)</font>` else entry[1]
			part.score.Text = Format.short(entry[2])
		else
			part.name.Text = `<font color="#7A6E5E">empty</font>`
			part.score.Text = "-"
		end
		if changed then
			part.block.Size = UDim2.new(1, 0, 0, 0)
			TweenService:Create(part.block, TweenInfo.new(0.5 + place * 0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = UDim2.new(1, 0, 0, part.height),
			}):Play()
		end
	end
	for index, part in rows do
		local entry = list[index]
		part.row.Visible = entry ~= nil
		if entry then
			local you = entry[1] == me
			part.name.Text = if you then `<font color="#F0C450"><b>{entry[1]} (you)</b></font>` else entry[1]
			part.score.Text = Format.short(entry[2])
			part.stroke.Color = if you then colors.gold else colors.dim
			part.row.BackgroundColor3 = if you then Color3.fromRGB(56, 44, 22) else Kit.CARD
		end
	end
	w.empty.Visible = #list == 0
	w.mine.label.Text = `YOU  <font color="#FFFFFF">{if myRank then "#" .. myRank else "unranked"}</font>   <font color="#B2A690">{board.note}</font>`
	w.mine.score.Text = Format.short(myScore(state, board.key))
	w.status.Text = `{BOARD_GLYPHS[board.key] or ""} {board.name}: <font color="#F0C450">{if myRank then "#" .. myRank else "unranked"}</font>`
end

return RankingsPage
