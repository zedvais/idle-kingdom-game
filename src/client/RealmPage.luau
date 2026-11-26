-- Realm Map page (Arena): nine territories in a 3 x 3 map. Each tile
-- shows who holds it this week (last week's winner), the top guilds this
-- week with their siege points, your guild's points and a SIEGE button.
-- Tiles your guild holds wear a gold crown and glow.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local SocialConfig = require(Shared:WaitForChild("SocialConfig"))
local Format = require(Shared:WaitForChild("Format"))
local Kit = require(script.Parent:WaitForChild("Kit"))
local Fx = require(script.Parent:WaitForChild("Fx"))

local RealmPage = {}

local w = {}
local tiles = {}

local function pct(amount: number): string
	return `+{math.floor(amount * 1000 + 0.5) / 10}%`
end

local function buildTile(ui, grid: Instance, index: number, territory)
	local tile = ui.makeFrame(grid, UDim2.fromOffset(100, 100), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1))
	tile.LayoutOrder = index
	tile.ClipsDescendants = true
	ui.addCorner(tile, 10)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 60
	gradient.Color = ColorSequence.new(territory.color:Lerp(Color3.new(0, 0, 0), 0.25), territory.color:Lerp(Color3.new(0, 0, 0), 0.75))
	gradient.Parent = tile
	ui.art.grain(tile)
	local stroke = ui.art.stroke(tile, territory.color, 2, 0.1)
	local scale = Instance.new("UIScale")
	scale.Name = "Pop"
	scale.Parent = tile
	-- big faint glyph behind
	local back = ui.makeText(tile, UDim2.fromOffset(150, 150), UDim2.new(1, -120, 0, -20), Color3.new(1, 1, 1), 110)
	back.TextXAlignment = Enum.TextXAlignment.Center
	back.TextTransparency = 0.82
	back.Text = territory.glyph
	local name = ui.makeText(tile, UDim2.new(1, -60, 0, 26), UDim2.fromOffset(12, 8), ui.colors.gold, 19)
	name.Font = ui.art.Fonts.heading
	name.Text = territory.name
	name.TextStrokeTransparency = 0.4
	name.ZIndex = 410
	local crown = ui.makeText(tile, UDim2.fromOffset(40, 40), UDim2.new(1, -48, 0, 4), Color3.new(1, 1, 1), 28)
	crown.TextXAlignment = Enum.TextXAlignment.Center
	crown.Text = "\u{1F451}"
	crown.ZIndex = 420
	Kit.bob(crown, 3, 2)
	local bonus = ui.makeText(tile, UDim2.fromOffset(150, 20), UDim2.fromOffset(12, 36), Color3.fromRGB(30, 20, 8), 12)
	bonus.BackgroundTransparency = 0
	bonus.BackgroundColor3 = Kit.GOLD
	bonus.Font = Enum.Font.GothamBlack
	bonus.TextXAlignment = Enum.TextXAlignment.Center
	bonus.Text = `{pct(territory.amount)} {string.upper(SocialConfig.BonusNames[territory.bonus] or territory.bonus)}`
	bonus.ZIndex = 410
	ui.addCorner(bonus, 5)
	local holder = ui.makeText(tile, UDim2.new(1, -24, 0, 18), UDim2.fromOffset(12, 62), Color3.new(1, 1, 1), 12)
	holder.Font = Enum.Font.GothamBlack
	holder.RichText = true
	holder.ZIndex = 410
	local leaders = {}
	for place = 1, 3 do
		local y = 84 + (place - 1) * 22
		local label = ui.makeText(tile, UDim2.new(0.5, -12, 0, 18), UDim2.fromOffset(12, y), ui.colors.text, 11)
		label.Font = Enum.Font.GothamBold
		label.RichText = true
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.ZIndex = 410
		local bar = Kit.bar(ui, tile, UDim2.new(0.5, -14, 0, 14), UDim2.new(0.5, 0, 0, y + 2), Kit.GOLD)
		bar.back.ZIndex = 410
		bar.fill.ZIndex = 411
		bar.text.ZIndex = 412
		bar.text.TextSize = 10
		leaders[place] = { label = label, bar = bar }
	end
	local mine = ui.makeText(tile, UDim2.new(1, -24, 0, 18), UDim2.fromOffset(12, 152), Kit.GOLD, 12)
	mine.Font = Enum.Font.GothamBlack
	mine.ZIndex = 410
	local button = ui.makeButton(tile, UDim2.new(1, -24, 0, 36), UDim2.new(0, 12, 1, -44), Kit.RED)
	button.TextSize = 14
	button.Font = Enum.Font.GothamBlack
	button.ZIndex = 420
	button.Activated:Connect(function()
		Kit.pop(tile, 1.05)
		ui.send("Siege", territory.id)
	end)
	tiles[territory.id] = {
		tile = tile,
		stroke = stroke,
		crown = crown,
		holder = holder,
		leaders = leaders,
		mine = mine,
		button = button,
		territory = territory,
	}
end

function RealmPage.build(ui)
	local page = ui.pages["Realm Map"]
	local banner = Kit.banner(ui, page, 1, 120, Color3.fromRGB(60, 110, 70), Color3.fromRGB(20, 40, 24), "Realm of Ashvale", "\u{1F6A9}")
	w.status = Kit.line(ui, banner, 120, 66, UDim.new(0.5, -120), 15, Color3.new(1, 1, 1))
	w.status.Font = Enum.Font.GothamBlack
	w.note = Kit.line(ui, banner, 0, 0, UDim.new(0.4, 0), 13, Color3.fromRGB(220, 255, 220))
	w.note.Position = UDim2.new(0.58, 0, 0, 30)
	w.note.Size = UDim2.new(0.4, -10, 0, 70)
	w.note.TextWrapped = true

	local _, _, right = Kit.heading(ui, page, 2, "\u{1F5FA}\u{FE0F}  The map", Color3.fromRGB(110, 190, 110))
	w.clock = right
	-- the map: a parchment board with a 3 x 3 grid
	local board = ui.makeFrame(page, UDim2.new(1, -10, 0, 0), UDim2.fromOffset(0, 0), Color3.fromRGB(70, 56, 36))
	board.LayoutOrder = 3
	board.AutomaticSize = Enum.AutomaticSize.Y
	ui.addCorner(board, 12)
	ui.art.stroke(board, ui.colors.gold, 2, 0.2)
	ui.art.grain(board)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = board
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(1 / 3, -8, 0, 236)
	layout.CellPadding = UDim2.fromOffset(12, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = board
	for index, territory in SocialConfig.Territories do
		buildTile(ui, board, index, territory)
	end
	Fx.handlers.siege = function(info)
		local part = tiles[info.territory or ""]
		if part then
			Kit.pop(part.tile, 1.08)
			Kit.float(ui, part.tile, `+{info.points} SIEGE POINTS`, Kit.GOLD)
			part.stroke.Thickness = 6
			TweenService:Create(part.stroke, TweenInfo.new(0.6), { Thickness = 2 }):Play()
		end
	end
	page:GetPropertyChangedSignal("Visible"):Connect(function()
		if page.Visible then
			Kit.popAll(page)
			ui.send("RealmRefresh")
		end
	end)
end

function RealmPage.draw(state, ui)
	if not state or not state.realm then
		return
	end
	local realm = state.realm
	local guild = state.guild
	local myId = guild and guild.id or ""
	local held = 0
	for _, part in tiles do
		local territory = part.territory
		local info = realm.territories[territory.id] or { leaders = {}, mine = 0 }
		local holder = info.holder
		local mineHeld = holder ~= nil and holder.id == myId and myId ~= ""
		if mineHeld then
			held += 1
		end
		part.crown.Visible = mineHeld
		part.holder.Text = if holder then `HELD BY <font color="#F0C450">[{holder.tag}] {holder.name}</font>` else "UNCLAIMED THIS WEEK"
		local top = (info.leaders[1] and info.leaders[1].p) or 1
		for place, row in part.leaders do
			local leader = info.leaders[place]
			row.label.Visible = leader ~= nil
			row.bar.back.Visible = leader ~= nil
			if leader then
				local medal = ({ "\u{1F947}", "\u{1F948}", "\u{1F949}" })[place]
				local isMine = leader.id == myId
				row.label.Text = `{medal} {if isMine then "<font color=\"#F0C450\">" else ""}[{leader.tag}] {leader.name}{if isMine then "</font>" else ""}`
				Kit.setBar(row.bar, leader.p, top, Format.short(leader.p))
			end
		end
		if not info.leaders[1] then
			part.leaders[1].label.Visible = true
			part.leaders[1].label.Text = "No sieges yet this week"
		end
		part.mine.Text = if myId ~= "" then `YOUR GUILD: {Format.short(info.mine or 0)} POINTS` else ""
		local usable = myId ~= "" and state.level >= SocialConfig.SiegeMinLevel and state.stamina >= SocialConfig.SiegeStamina
		local label = if myId == "" then "JOIN A GUILD"
			elseif state.level < SocialConfig.SiegeMinLevel then `LEVEL {SocialConfig.SiegeMinLevel}`
			else `\u{2694}\u{FE0F} SIEGE  +{realm.points}`
		ui.setButton(part.button, label, usable, Kit.RED)
		Kit.setPulse(part.stroke, mineHeld, territory.color)
	end
	w.clock.Text = `WEEK ENDS IN {string.upper(Kit.clock(realm.secondsLeft))}`
	if myId == "" then
		w.status.Text = "You are not in a guild"
		w.note.Text = "Join or found a guild on the Guild page to siege territories. Winners hold them for a week and every member gets the bonus."
	else
		w.status.Text = `[{guild.tag}] holds <font color="#F0C450">{held}</font> of {#SocialConfig.Territories}  \u{2022}  {realm.sieges} sieges by you`
		w.note.Text = `Each siege costs {SocialConfig.SiegeStamina} stamina and adds {realm.points} points for your guild. Most points at week's end holds the territory next week.`
	end
end

return RealmPage
