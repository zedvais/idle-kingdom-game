-- Festival page:
--   * a festival banner (bunting that sways, this week's festival, its
--     bonus, time left and your points),
--   * a milestone track: a bar with four reward chests on it,
--   * "how to earn points" chips,
--   * the top 10 board with gold/silver/bronze podium rows,
--   * rank reward cards.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local StoreConfig = require(Shared:WaitForChild("StoreConfig"))
local FestivalConfig = require(Shared:WaitForChild("FestivalConfig"))
local Format = require(Shared:WaitForChild("Format"))
local Kit = require(script.Parent:WaitForChild("Kit"))

local FestivalPage = {}

local FESTIVAL_GLYPHS = { harvest = "\u{1F33D}", tournament = "\u{1F3C7}", muster = "\u{1F6E1}\u{FE0F}", merchants = "\u{1F3AA}" }
local FESTIVAL_COLORS = {
	harvest = { Color3.fromRGB(200, 130, 40), Color3.fromRGB(80, 50, 16) },
	tournament = { Color3.fromRGB(170, 50, 50), Color3.fromRGB(60, 20, 24) },
	muster = { Color3.fromRGB(60, 110, 170), Color3.fromRGB(20, 34, 60) },
	merchants = { Color3.fromRGB(140, 70, 160), Color3.fromRGB(50, 24, 60) },
}
local STAT_NAMES = { holdings = "Build a holding", quests = "Do a quest", claims = "Claim a playtime reward", foes = "Beat a foe", train = "Train a soldier", rolls = "Recruit roll", market = "Buy Market gear" }
local PODIUM = { Color3.fromRGB(240, 196, 80), Color3.fromRGB(200, 205, 215), Color3.fromRGB(205, 130, 70) }
local FLAGS = { Color3.fromRGB(220, 70, 60), Color3.fromRGB(240, 196, 80), Color3.fromRGB(70, 140, 220), Color3.fromRGB(90, 190, 100) }

local w = {}
local milestones = {}
local rows = {}
local shownKey = nil

local function buildBanner(ui, page: Instance)
	local banner, title, icon = Kit.banner(ui, page, 1, 150, FESTIVAL_COLORS.harvest[1], FESTIVAL_COLORS.harvest[2], "Festival", "\u{1F3AA}")
	w.banner, w.title, w.icon = banner, title, icon
	w.gradient = banner:FindFirstChildOfClass("UIGradient")
	-- Bunting along the top.
	local bunting = ui.makeFrame(banner, UDim2.new(1, 0, 0, 22), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	bunting.BackgroundTransparency = 1
	bunting.ZIndex = 405
	for index = 0, 29 do
		local flag = ui.makeFrame(bunting, UDim2.fromOffset(18, 18), UDim2.new(index / 30, 6, 0, -9), FLAGS[index % #FLAGS + 1])
		flag.Rotation = 45
		flag.ZIndex = 405
	end
	w.bunting = bunting
	w.bonus = Kit.line(ui, banner, 120, 64, UDim.new(0.55, -120), 18, Color3.fromRGB(255, 230, 160))
	w.bonus.Font = Enum.Font.GothamBlack
	w.ends = Kit.line(ui, banner, 120, 96, UDim.new(0.55, -120), 14, Color3.fromRGB(240, 230, 220))
	local box = ui.makeFrame(banner, UDim2.fromOffset(230, 90), UDim2.new(1, -250, 0, 34), Color3.fromRGB(20, 14, 10))
	box.BackgroundTransparency = 0.15
	box.ZIndex = 410
	ui.addCorner(box, 10)
	ui.art.stroke(box, Kit.GOLD, 2, 0)
	local label = ui.makeText(box, UDim2.new(1, -20, 0, 20), UDim2.fromOffset(10, 10), Kit.GOLD, 13)
	label.Font = Enum.Font.GothamBlack
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Text = "YOUR POINTS"
	label.ZIndex = 411
	w.points = ui.makeText(box, UDim2.new(1, -20, 0, 44), UDim2.fromOffset(10, 32), Color3.new(1, 1, 1), 38)
	w.points.Font = Enum.Font.GothamBlack
	w.points.TextXAlignment = Enum.TextXAlignment.Center
	w.points.ZIndex = 411
end

local function buildMilestones(ui, page: Instance)
	Kit.heading(ui, page, 2, "Milestones", Kit.GOLD)
	local track = ui.makeFrame(page, UDim2.new(1, -10, 0, 190), UDim2.fromOffset(0, 0), Kit.CARD)
	track.LayoutOrder = 3
	ui.addCorner(track, 10)
	ui.art.stroke(track, ui.colors.dim, 1, 0.5)
	w.track = Kit.bar(ui, track, UDim2.new(1, -60, 0, 16), UDim2.fromOffset(30, 92), Color3.fromRGB(230, 120, 70))
	local top = FestivalConfig.Milestones[#FestivalConfig.Milestones].points
	for index, milestone in FestivalConfig.Milestones do
		local share = milestone.points / top
		local holder = ui.makeFrame(track, UDim2.fromOffset(120, 180), UDim2.new(0, 30, 0, 6), Color3.new(0, 0, 0))
		holder.BackgroundTransparency = 1
		holder.Position = UDim2.new(share * 0.94, 30 - 60 - share * 30, 0, 4)
		local art = ui.makeFrame(holder, UDim2.fromOffset(64, 64), UDim2.new(0.5, -32, 0, 4), Color3.new(0, 0, 0))
		art.BackgroundTransparency = 1
		Kit.rewardArt(ui, art, milestone.reward)
		local dot = ui.makeFrame(holder, UDim2.fromOffset(22, 22), UDim2.new(0.5, -11, 0, 85), Color3.fromRGB(60, 50, 40))
		ui.addCorner(dot, 11)
		local ring = ui.art.stroke(dot, Kit.GOLD, 2, 0)
		local points = Kit.centered(ui, holder, 110, 18, 13, Kit.GOLD)
		points.Font = Enum.Font.GothamBlack
		points.Text = `{milestone.points} PTS`
		local button = ui.makeButton(holder, UDim2.new(1, -10, 0, 32), UDim2.new(0, 5, 0, 136), ui.colors.claim)
		button.TextSize = 12
		button.Font = Enum.Font.GothamBlack
		button.Activated:Connect(function()
			Kit.pop(holder, 1.15)
			Kit.float(ui, holder, `+{StoreConfig.describe(milestone.reward)}`, Kit.GOLD)
			ui.send("FestivalMilestone", tostring(index))
		end)
		milestones[index] = { holder = holder, dot = dot, ring = ring, button = button, art = art }
	end
end

local function buildEarn(ui, page: Instance)
	Kit.heading(ui, page, 4, "How to earn points", Color3.fromRGB(230, 120, 70))
	local row = ui.makeFrame(page, UDim2.new(1, -10, 0, 56), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	row.BackgroundTransparency = 1
	row.LayoutOrder = 5
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 10)
	layout.Parent = row
	w.earn = row
end

local function buildBoard(ui, page: Instance)
	local _, _, right = Kit.heading(ui, page, 6, "Top 10 (all servers)", Kit.GOLD)
	right.Text = "UPDATES EVERY MINUTE"
	local board = ui.makeFrame(page, UDim2.new(1, -10, 0, 0), UDim2.fromOffset(0, 0), Kit.CARD)
	board.AutomaticSize = Enum.AutomaticSize.Y
	board.LayoutOrder = 7
	ui.addCorner(board, 10)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = board
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = board
	for index = 1, FestivalConfig.LeaderboardSize do
		local row = ui.makeFrame(board, UDim2.new(1, 0, 0, 44), UDim2.fromOffset(0, 0), Color3.fromRGB(40, 34, 28))
		row.LayoutOrder = index
		ui.addCorner(row, 6)
		local stroke = ui.art.stroke(row, Kit.GOLD, 2, 1)
		local medal = ui.makeFrame(row, UDim2.fromOffset(34, 34), UDim2.fromOffset(6, 5), PODIUM[index] or Color3.fromRGB(70, 60, 50))
		ui.addCorner(medal, 17)
		ui.art.gloss(medal, 1, 0.6)
		local number = ui.makeText(medal, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.fromRGB(40, 26, 8), 16)
		number.Font = Enum.Font.GothamBlack
		number.TextXAlignment = Enum.TextXAlignment.Center
		number.Text = tostring(index)
		number.ZIndex = medal.ZIndex + 2
		if not PODIUM[index] then
			number.TextColor3 = Color3.new(1, 1, 1)
		end
		local name = ui.makeText(row, UDim2.new(0.7, -60, 1, 0), UDim2.fromOffset(52, 0), ui.colors.text, 17)
		name.Font = Enum.Font.GothamBold
		local points = ui.makeText(row, UDim2.new(0.3, -16, 1, 0), UDim2.new(0.7, 0, 0, 0), Kit.GOLD, 17)
		points.Font = Enum.Font.GothamBlack
		points.TextXAlignment = Enum.TextXAlignment.Right
		rows[index] = { row = row, stroke = stroke, name = name, points = points }
	end
	w.boardEmpty = ui.makeText(board, UDim2.new(1, 0, 0, 40), UDim2.fromOffset(0, 0), ui.colors.dim, 14)
	w.boardEmpty.LayoutOrder = 100
	w.boardEmpty.TextXAlignment = Enum.TextXAlignment.Center
	w.boardEmpty.Text = "No scores yet this week. The board fills in about a minute after games save."
end

local function buildRankRewards(ui, page: Instance)
	local _, _, right = Kit.heading(ui, page, 8, "Rank rewards", Kit.GOLD)
	right.Text = "PAID NEXT WEEK BY MAIL"
	local grid = Kit.grid(ui, page, 9, 150, #FestivalConfig.RankRewards)
	for index, entry in FestivalConfig.RankRewards do
		local card = Kit.card(ui, grid, index, PODIUM[index] or ui.colors.dim)
		local label = Kit.centered(ui, card, 8, 22, 15, PODIUM[index] or ui.colors.text)
		label.Font = Enum.Font.GothamBlack
		label.Text = string.upper(entry.label)
		local tiles = ui.makeFrame(card, UDim2.new(1, -10, 0, 56), UDim2.fromOffset(5, 36), Color3.new(0, 0, 0))
		tiles.BackgroundTransparency = 1
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.Padding = UDim.new(0, 4)
		layout.Parent = tiles
		for order, reward in entry.rewards do
			local art = ui.makeFrame(tiles, UDim2.fromOffset(54, 54), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
			art.BackgroundTransparency = 1
			art.LayoutOrder = order
			Kit.rewardArt(ui, art, reward)
		end
		local text = Kit.centered(ui, card, 96, 44, 11, ui.colors.dim)
		text.Text = StoreConfig.describeList(entry.rewards)
	end
end

function FestivalPage.build(ui)
	local page = ui.pages.Festival
	buildBanner(ui, page)
	buildMilestones(ui, page)
	buildEarn(ui, page)
	buildBoard(ui, page)
	buildRankRewards(ui, page)
	local t = 0
	RunService.RenderStepped:Connect(function(dt)
		if not page.Visible then
			return
		end
		t += dt
		w.bunting.Position = UDim2.fromOffset(math.sin(t * 1.5) * 4, math.sin(t * 2.2) * 2)
	end)
	page:GetPropertyChangedSignal("Visible"):Connect(function()
		if page.Visible then
			Kit.popAll(page)
		end
	end)
end

function FestivalPage.draw(state, ui)
	if not state then
		return
	end
	local colors = ui.colors
	local fs = state.festival
	local festival = FestivalConfig.getFestival(fs.week)
	local points = math.floor(fs.points)

	-- Banner: colors and the earn chips change with the festival.
	if shownKey ~= festival.key then
		shownKey = festival.key
		local pair = FESTIVAL_COLORS[festival.key] or FESTIVAL_COLORS.harvest
		if w.gradient then
			w.gradient.Color = ColorSequence.new(pair[1], pair[2])
		end
		w.icon.BackgroundColor3 = pair[1]:Lerp(Color3.new(0, 0, 0), 0.25)
		local mark = w.icon:FindFirstChildWhichIsA("TextLabel")
		if mark then
			mark.Text = FESTIVAL_GLYPHS[festival.key] or "\u{1F3AA}"
		end
		for _, child in w.earn:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local list = {}
		for stat, value in festival.points do
			table.insert(list, { stat, value })
		end
		table.sort(list, function(a, b)
			return a[2] > b[2]
		end)
		for order, pair2 in list do
			local chip = ui.makeText(w.earn, UDim2.fromOffset(0, 56), UDim2.fromOffset(0, 0), colors.text, 15)
			chip.AutomaticSize = Enum.AutomaticSize.X
			chip.LayoutOrder = order
			chip.BackgroundTransparency = 0
			chip.BackgroundColor3 = Kit.CARD
			chip.Font = Enum.Font.GothamBold
			chip.RichText = true
			chip.Text = `   {STAT_NAMES[pair2[1]] or pair2[1]}  <font color="#F0C450"><b>+{pair2[2]}</b></font>   `
			ui.addCorner(chip, 8)
			ui.art.stroke(chip, Kit.GOLD, 1.5, 0.4)
		end
	end
	w.title.Text = festival.name
	w.bonus.Text = `\u{2728} THIS WEEK: {string.upper(festival.bonusText)}`
	w.ends.Text = `Ends in {Kit.clock(state.weekSecondsLeft or 0)}`
	w.points.Text = Format.short(points)

	-- Milestones.
	local top = FestivalConfig.Milestones[#FestivalConfig.Milestones].points
	Kit.setBar(w.track, points, top, "")
	local ready = 0
	for index, milestone in FestivalConfig.Milestones do
		local part = milestones[index]
		local claimed = fs.milestones[tostring(index)] == true
		local reached = points >= milestone.points
		if reached and not claimed then
			ready += 1
		end
		part.dot.BackgroundColor3 = if reached then Kit.GOLD else Color3.fromRGB(60, 50, 40)
		ui.setButton(part.button, if claimed then "\u{2714} CLAIMED" elseif reached then "CLAIM!" else `{Format.short(points)} / {milestone.points}`, reached and not claimed, colors.claim)
		Kit.setPulse(part.ring, reached and not claimed, Kit.GOLD)
	end
	ui.setBadge("Festival", ready)

	-- Board.
	local me = Players.LocalPlayer.Name
	for index, part in rows do
		local entry = state.festivalTop[index]
		part.row.Visible = entry ~= nil
		if entry then
			local mine = entry[1] == me
			part.name.Text = if mine then `{entry[1]}  (you)` else entry[1]
			part.name.TextColor3 = if mine then Kit.GOLD else colors.text
			part.points.Text = Format.short(entry[2])
			part.stroke.Transparency = if mine then 0 else 1
		end
	end
	w.boardEmpty.Visible = #state.festivalTop == 0
end

return FestivalPage
