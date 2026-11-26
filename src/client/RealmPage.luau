-- Realm Map page (Arena) and the Territory popup.
--
-- Page: banner with the top three guilds, how many territories your guild
-- holds and the next stipend; a tier selector (five lands, each with its
-- own look); the tier's map with six territories colored by the guild
-- that holds them, each showing its building, holder, strength and bonus,
-- all on one grid map of the realm (drag, zoom, jump to a region).
--
-- Territory popup (press a territory), like Idle Mafia's district window:
--   OVERVIEW  bonus, stipend, strength, garrison and history
--   ATTACK    CLAIM when nobody holds it, otherwise ATTACK and SIEGE
--   GARRISON  station soldiers from your warband, recall them
--   RESIDENTS live there for a share of its bonus; holders set the rules
--             (open, by application or closed, a level and a rent)
--   FORTIFY   four buildings (named for the tier), funded with gold and energy

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local SocialConfig = require(Shared:WaitForChild("SocialConfig"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Format = require(Shared:WaitForChild("Format"))
local Kit = require(script.Parent:WaitForChild("Kit"))
local Fx = require(script.Parent:WaitForChild("Fx"))
local Landmarks = require(script.Parent:WaitForChild("Landmarks"))

local RealmPage = {}

local w = {}
local pop = {} -- Territory popup widgets
local tierShown = nil -- region the map is zoomed to (nil = whole map)
local selected = "" -- territory open in the popup
local tab = "overview"
local latest = nil
local surrenderArmed = 0

local byTier = {}
for _, territory in SocialConfig.Territories do
	byTier[territory.tier] = byTier[territory.tier] or {}
	byTier[territory.tier][territory.slot] = territory
end

local PARCHMENT = Color3.fromRGB(150, 132, 100)
local GUILD_COLORS = {
	Color3.fromRGB(196, 64, 64), Color3.fromRGB(64, 120, 200), Color3.fromRGB(70, 160, 90), Color3.fromRGB(200, 140, 40),
	Color3.fromRGB(140, 80, 180), Color3.fromRGB(40, 160, 170), Color3.fromRGB(200, 90, 150), Color3.fromRGB(120, 140, 60),
	Color3.fromRGB(210, 110, 60), Color3.fromRGB(90, 90, 200), Color3.fromRGB(160, 60, 90), Color3.fromRGB(60, 140, 130),
}

local function guildColor(id: string): Color3
	local hash = 0
	for index = 1, #id do
		hash = (hash * 31 + string.byte(id, index)) % 100003
	end
	return GUILD_COLORS[hash % #GUILD_COLORS + 1]
end

local function pct(amount: number): string
	return `+{math.floor(amount * 1000 + 0.5) / 10}%`
end

local function bonusText(territory): string
	return `{pct(territory.amount)} {string.upper(SocialConfig.BonusNames[territory.bonus] or territory.bonus)}`
end

local function guildText(holder): string
	return `[{holder.tag}] {holder.name}`
end

local function ago(seconds: number): string
	if seconds < 60 then
		return "just now"
	elseif seconds < 3600 then
		return `{math.floor(seconds / 60)}m ago`
	elseif seconds < 86400 then
		return `{math.floor(seconds / 3600)}h ago`
	end
	return `{math.floor(seconds / 86400)}d ago`
end

---------------------------------------------------------------------------
-- Map page
---------------------------------------------------------------------------

local function openTerritory(ui, territory)
	selected = territory.id
	tab = "overview"
	surrenderArmed = 0
	ui.send("RealmView", territory.id)
	ui.openModal("Territory", territory.name)
end

-- The realm is one big grid map, like Idle Mafia's: each tier is a region
-- of 3 x 2 territories, laid out in a 3 x 2 grid of regions (the top left
-- corner is the sea). Drag to move, zoom with the wheel or the buttons,
-- jump between regions with the arrows.
local CELL_W, CELL_H, CELL_GAP = 210, 170, 6
local REGION_GAP = 40
local REGION_W, REGION_H = 3 * CELL_W + 4 * CELL_GAP, 2 * CELL_H + 3 * CELL_GAP
local REGION_SPOT = { { 0, 1 }, { 1, 1 }, { 2, 1 }, { 2, 0 }, { 1, 0 } } -- tier -> region column, row
local CANVAS_W = 3 * REGION_W + 4 * REGION_GAP
local CANVAS_H = 2 * REGION_H + 3 * REGION_GAP
local cells = {} -- [territory id] = cell widgets
local camera = { x = CANVAS_W / 2, y = CANVAS_H / 2, zoom = 0.5 }
local goal = { x = CANVAS_W / 2, y = CANVAS_H / 2, zoom = 0.5 }
local drag = { on = false, moved = false, from = Vector2.zero, start = nil }

local function regionOrigin(tier: number): Vector2
	local spot = REGION_SPOT[tier]
	return Vector2.new(REGION_GAP + spot[1] * (REGION_W + REGION_GAP), REGION_GAP + spot[2] * (REGION_H + REGION_GAP))
end

local function fitZoom(): number
	local size = w.board.AbsoluteSize
	if size.X <= 0 then
		return 0.5
	end
	return math.min(size.X / CANVAS_W, size.Y / CANVAS_H)
end

local function clampGoal()
	local fit = fitZoom()
	goal.zoom = math.clamp(goal.zoom, fit, 1.6)
	goal.x = math.clamp(goal.x, 0, CANVAS_W)
	goal.y = math.clamp(goal.y, 0, CANVAS_H)
end

local function resetView()
	goal.x, goal.y = CANVAS_W / 2, CANVAS_H / 2
	goal.zoom = fitZoom()
end

local function focusRegion(tier: number)
	local origin = regionOrigin(tier)
	goal.x = origin.X + REGION_W / 2
	goal.y = origin.Y + REGION_H / 2
	local size = w.board.AbsoluteSize
	goal.zoom = if size.X > 0 then math.min(size.X / (REGION_W + 80), size.Y / (REGION_H + 80), 1.3) else 1
	clampGoal()
end

local function applyCamera()
	w.canvasScale.Scale = camera.zoom
	w.canvas.Position = UDim2.new(0.5, -camera.x * camera.zoom, 0.5, -camera.y * camera.zoom)
end

local function buildCell(ui, region: Frame, territory)
	local column = (territory.slot - 1) % 3
	local row = (territory.slot - 1) // 3
	local cell = ui.makeButton(region, UDim2.fromOffset(CELL_W, CELL_H), UDim2.fromOffset(CELL_GAP + column * (CELL_W + CELL_GAP), CELL_GAP + row * (CELL_H + CELL_GAP)), PARCHMENT)
	cell.AutoButtonColor = false
	cell.ZIndex = 22
	cell.ClipsDescendants = true
	ui.addCorner(cell, 8)
	for _, child in cell:GetChildren() do
		if child:IsA("UIStroke") then
			child:Destroy() -- the button edge; the cell gets its own border
		end
	end
	local stroke = ui.art.stroke(cell, Color3.fromRGB(30, 22, 14), 3, 0)
	ui.art.grain(cell)
	local scale = Instance.new("UIScale")
	scale.Name = "Pop"
	scale.Parent = cell
	local picture = ui.makeFrame(cell, UDim2.fromOffset(110, 74), UDim2.new(0.5, -55, 0, 4), Color3.new(0, 0, 0))
	picture.BackgroundTransparency = 1
	picture.ZIndex = 400
	local name = ui.makeText(cell, UDim2.new(1, -12, 0, 22), UDim2.fromOffset(6, 78), ui.colors.gold, 17)
	name.Font = ui.art.Fonts.heading
	name.TextXAlignment = Enum.TextXAlignment.Center
	name.TextStrokeTransparency = 0.2
	name.Text = territory.name
	name.ZIndex = 430
	local owner = ui.makeText(cell, UDim2.new(1, -12, 0, 16), UDim2.fromOffset(6, 100), Color3.new(1, 1, 1), 12)
	owner.Font = Enum.Font.GothamBlack
	owner.TextXAlignment = Enum.TextXAlignment.Center
	owner.TextStrokeTransparency = 0.3
	owner.TextTruncate = Enum.TextTruncate.AtEnd
	owner.ZIndex = 430
	local bar = Kit.bar(ui, cell, UDim2.new(1, -24, 0, 13), UDim2.fromOffset(12, 120), Kit.RED)
	bar.back.ZIndex = 430
	bar.fill.ZIndex = 431
	bar.text.ZIndex = 432
	bar.text.TextSize = 10
	local pill = ui.makeText(cell, UDim2.new(1, -40, 0, 18), UDim2.fromOffset(20, 140), Color3.fromRGB(30, 20, 8), 11)
	pill.BackgroundTransparency = 0
	pill.BackgroundColor3 = Kit.GOLD
	pill.Font = Enum.Font.GothamBlack
	pill.TextXAlignment = Enum.TextXAlignment.Center
	pill.Text = bonusText(territory)
	pill.ZIndex = 430
	ui.addCorner(pill, 5)
	local flags = ui.makeText(cell, UDim2.new(1, -10, 0, 22), UDim2.fromOffset(4, 4), Color3.new(1, 1, 1), 16)
	flags.TextXAlignment = Enum.TextXAlignment.Right
	flags.ZIndex = 440
	local number = ui.makeText(cell, UDim2.fromOffset(40, 20), UDim2.fromOffset(8, 4), Color3.new(1, 1, 1), 12)
	number.Font = Enum.Font.GothamBlack
	number.TextStrokeTransparency = 0.3
	number.Text = `{territory.tier}-{territory.slot}`
	number.ZIndex = 440
	cell.Activated:Connect(function()
		if drag.moved then
			return -- that press was a drag of the map
		end
		Kit.pop(cell, 1.06)
		openTerritory(ui, territory)
	end)
	Landmarks.draw(picture, territory.tier)
	cells[territory.id] = { cell = cell, stroke = stroke, owner = owner, bar = bar, flags = flags, territory = territory }
end

-- Scenery in the sea corner.
local function buildSea(ui, canvas: Frame)
	local sea = ui.makeFrame(canvas, UDim2.fromOffset(REGION_W, REGION_H), UDim2.fromOffset(REGION_GAP, REGION_GAP), Color3.fromRGB(50, 100, 150))
	sea.ZIndex = 10
	ui.addCorner(sea, 40)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.fromRGB(90, 150, 200), Color3.fromRGB(30, 70, 120))
	gradient.Parent = sea
	for index, glyph in { "\u{26F5}", "\u{1F30A}", "\u{1F433}", "\u{1F30A}", "\u{2693}" } do
		local label = ui.makeText(sea, UDim2.fromOffset(70, 70), UDim2.fromScale(({ 0.15, 0.45, 0.7, 0.2, 0.8 })[index], ({ 0.2, 0.15, 0.4, 0.65, 0.75 })[index]), Color3.new(1, 1, 1), 46)
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.Text = glyph
		label.ZIndex = 11
		Kit.bob(label, 6, 0.8 + index * 0.2)
	end
	local title = ui.makeText(sea, UDim2.new(1, 0, 0, 40), UDim2.new(0, 0, 0.5, -20), Color3.fromRGB(220, 240, 255), 30)
	title.Font = ui.art.Fonts.title
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.TextTransparency = 0.3
	title.Text = "The Sundering Sea"
	title.ZIndex = 12
end

local function buildMap(ui, page: Instance)
	local board = ui.makeFrame(page, UDim2.new(1, -10, 0, 540), UDim2.fromOffset(0, 0), Color3.fromRGB(46, 40, 30))
	board.LayoutOrder = 3
	board.ClipsDescendants = true
	board.Active = true
	ui.addCorner(board, 12)
	ui.art.stroke(board, ui.colors.gold, 2, 0.2)
	ui.art.grain(board)
	w.board = board
	local canvas = ui.makeFrame(board, UDim2.fromOffset(CANVAS_W, CANVAS_H), UDim2.fromOffset(0, 0), Color3.fromRGB(120, 104, 72))
	canvas.ZIndex = 2
	ui.addCorner(canvas, 24)
	ui.art.grain(canvas)
	w.canvas = canvas
	w.canvasScale = Instance.new("UIScale")
	w.canvasScale.Parent = canvas
	buildSea(ui, canvas)
	w.regions = {}
	for tier, info in SocialConfig.Tiers do
		local origin = regionOrigin(tier)
		local region = ui.makeFrame(canvas, UDim2.fromOffset(REGION_W, REGION_H), UDim2.fromOffset(origin.X, origin.Y), Color3.new(1, 1, 1))
		region.ZIndex = 10
		ui.addCorner(region, 14)
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Color = ColorSequence.new(info.land:Lerp(info.sky, 0.25), info.land:Lerp(Color3.new(0, 0, 0), 0.45))
		gradient.Parent = region
		local edge = ui.art.stroke(region, info.land:Lerp(Color3.new(1, 1, 1), 0.3), 4, 0)
		local label = ui.makeText(canvas, UDim2.fromOffset(REGION_W, 32), UDim2.fromOffset(origin.X, origin.Y - 36), info.land:Lerp(Color3.new(1, 1, 1), 0.55), 24)
		label.Font = ui.art.Fonts.title
		label.TextStrokeTransparency = 0.3
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.Text = `{info.glyph}  {string.upper(info.name)}  \u{2022}  TIER {tier}  \u{2022}  LEVEL {info.level}+`
		label.ZIndex = 15
		w.regions[tier] = { frame = region, edge = edge }
		for _, territory in byTier[tier] do
			buildCell(ui, region, territory)
		end
	end
	-- zoom buttons
	local function zoomButton(text: string, x: number, onPress)
		local button = ui.makeButton(board, UDim2.fromOffset(if #text > 2 then 110 else 40, 36), UDim2.new(1, x, 0, 10), Color3.fromRGB(60, 50, 36))
		button.Font = Enum.Font.GothamBlack
		button.TextSize = if #text > 2 then 12 else 20
		button.Text = text
		button.ZIndex = 600
		button.Activated:Connect(onPress)
	end
	zoomButton("+", -100, function()
		goal.zoom *= 1.3
		clampGoal()
	end)
	zoomButton("\u{2212}", -54, function()
		goal.zoom /= 1.3
		clampGoal()
	end)
	zoomButton("RESET ZOOM", -220, function()
		tierShown = nil
		resetView()
	end)
	local hint = ui.makeText(board, UDim2.fromOffset(300, 20), UDim2.new(0, 12, 1, -28), Color3.fromRGB(230, 220, 200), 12)
	hint.Font = Enum.Font.GothamBold
	hint.TextStrokeTransparency = 0.4
	hint.Text = "Drag to move the map, zoom with the wheel"
	hint.ZIndex = 600

	-- drag, wheel and the smooth camera
	local UserInputService = game:GetService("UserInputService")
	local RunService = game:GetService("RunService")
	local function inside(position: Vector3): boolean
		if not board.Visible or not page.Visible or ui.isOpen("Territory") or ui.isOpen("RealmBonuses") then
			return false
		end
		local at, size = board.AbsolutePosition, board.AbsoluteSize
		local x, y = position.X, position.Y
		return x >= at.X and x <= at.X + size.X and y >= at.Y and y <= at.Y + size.Y
	end
	UserInputService.InputBegan:Connect(function(input)
		if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) and inside(input.Position) then
			drag.on = true
			drag.moved = false
			drag.from = Vector2.new(input.Position.X, input.Position.Y)
			drag.start = Vector2.new(goal.x, goal.y)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if drag.on and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = Vector2.new(input.Position.X, input.Position.Y) - drag.from
			if delta.Magnitude > 6 then
				drag.moved = true
			end
			if drag.moved then
				goal.x = drag.start.X - delta.X / camera.zoom
				goal.y = drag.start.Y - delta.Y / camera.zoom
				clampGoal()
				camera.x, camera.y = goal.x, goal.y
			end
		elseif input.UserInputType == Enum.UserInputType.MouseWheel and inside(input.Position) then
			local step = if input.Position.Z > 0 then 1.15 else 1 / 1.15
			goal.zoom *= step
			clampGoal()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			drag.on = false
			task.defer(function()
				drag.moved = false
			end)
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		if not page.Visible then
			return
		end
		local blend = math.min(1, dt * 10)
		camera.x += (goal.x - camera.x) * blend
		camera.y += (goal.y - camera.y) * blend
		camera.zoom += (goal.zoom - camera.zoom) * blend
		applyCamera()
	end)
	board:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if tierShown then
			focusRegion(tierShown)
		else
			resetView()
		end
	end)
	resetView()
	camera.x, camera.y, camera.zoom = goal.x, goal.y, goal.zoom
end

---------------------------------------------------------------------------
-- Territory popup
---------------------------------------------------------------------------

local TABS = { { "overview", "OVERVIEW" }, { "attack", "ATTACK" }, { "garrison", "GARRISON" }, { "residents", "RESIDENTS" }, { "fortify", "FORTIFY" } }
local ROWS = 20

local function body(ui, page: Instance, order: number): Frame
	local frame = ui.makeFrame(page, UDim2.new(1, -10, 0, 0), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	frame.BackgroundTransparency = 1
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.LayoutOrder = order
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame
	return frame
end

-- A card with a title, a big line, a note and an optional button.
local function infoCard(ui, parent: Instance, order: number, title: string, withButton: boolean)
	local card, stroke = Kit.card(ui, parent, order, ui.colors.dim)
	local head = ui.makeText(card, UDim2.new(1, -20, 0, 18), UDim2.fromOffset(12, 8), Kit.GOLD, 12)
	head.Font = Enum.Font.GothamBlack
	head.Text = title
	local big = ui.makeText(card, UDim2.new(1, -20, 0, 30), UDim2.fromOffset(12, 26), ui.colors.text, 22)
	big.Font = ui.art.Fonts.heading
	big.RichText = true
	local note = ui.makeText(card, UDim2.new(1, -20, 0, 36), UDim2.fromOffset(12, 58), ui.colors.dim, 12)
	note.Font = Enum.Font.GothamBold
	note.RichText = true
	note.TextYAlignment = Enum.TextYAlignment.Top
	local button = nil
	if withButton then
		button = ui.makeButton(card, UDim2.new(1, -24, 0, 34), UDim2.new(0, 12, 1, -42), Kit.RED)
		button.Font = Enum.Font.GothamBlack
		button.TextSize = 14
	end
	return { card = card, stroke = stroke, head = head, big = big, note = note, button = button }
end

local function listRow(ui, parent: Instance, order: number, withButton: boolean)
	local row = ui.makeFrame(parent, UDim2.new(1, 0, 0, 36), UDim2.fromOffset(0, 0), Kit.CARD)
	row.LayoutOrder = order
	ui.addCorner(row, 6)
	local text = ui.makeText(row, UDim2.new(1, if withButton then -150 else -20, 1, 0), UDim2.fromOffset(12, 0), ui.colors.text, 13)
	text.Font = Enum.Font.GothamBold
	text.RichText = true
	text.TextTruncate = Enum.TextTruncate.AtEnd
	local button = nil
	if withButton then
		button = ui.makeButton(row, UDim2.fromOffset(126, 28), UDim2.new(1, -132, 0, 4), Kit.RED)
		button.Font = Enum.Font.GothamBlack
		button.TextSize = 12
	end
	return { row = row, text = text, button = button }
end

local function sectionTitle(ui, parent: Instance, order: number): TextLabel
	local label = ui.makeText(parent, UDim2.new(1, 0, 0, 24), UDim2.fromOffset(0, 0), Kit.GOLD, 16)
	label.Font = ui.art.Fonts.heading
	label.LayoutOrder = order
	return label
end

local function buildPopup(ui)
	local page = ui.pages.Territory
	-- header: the tier's building, name, holder and actions
	local header = ui.makeFrame(page, UDim2.new(1, -10, 0, 150), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1))
	header.LayoutOrder = 1
	header.ClipsDescendants = true
	ui.addCorner(header, 10)
	ui.art.stroke(header, ui.colors.gold, 2, 0.1)
	pop.headerGradient = Instance.new("UIGradient")
	pop.headerGradient.Rotation = 90
	pop.headerGradient.Parent = header
	ui.art.grain(header)
	pop.header = header
	local picture = ui.makeFrame(header, UDim2.fromOffset(190, 134), UDim2.fromOffset(10, 8), Color3.new(0, 0, 0))
	picture.BackgroundTransparency = 1
	picture.ZIndex = 400
	pop.picture = picture
	pop.name = ui.makeText(header, UDim2.new(1, -420, 0, 40), UDim2.fromOffset(212, 10), ui.colors.gold, 32)
	pop.name.Font = ui.art.Fonts.title
	pop.name.TextStrokeTransparency = 0.3
	pop.name.ZIndex = 410
	pop.tier = ui.makeText(header, UDim2.new(1, -420, 0, 20), UDim2.fromOffset(212, 52), Color3.new(1, 1, 1), 13)
	pop.tier.Font = Enum.Font.GothamBlack
	pop.tier.TextStrokeTransparency = 0.5
	pop.tier.ZIndex = 410
	pop.held = ui.makeText(header, UDim2.new(1, -420, 0, 24), UDim2.fromOffset(212, 76), Color3.new(1, 1, 1), 16)
	pop.held.Font = Enum.Font.GothamBlack
	pop.held.RichText = true
	pop.held.TextStrokeTransparency = 0.4
	pop.held.ZIndex = 410
	pop.flags = ui.makeText(header, UDim2.new(1, -420, 0, 22), UDim2.fromOffset(212, 104), Color3.fromRGB(255, 230, 200), 13)
	pop.flags.Font = Enum.Font.GothamBold
	pop.flags.RichText = true
	pop.flags.TextStrokeTransparency = 0.5
	pop.flags.ZIndex = 410
	local function headerButton(y: number, color: Color3): TextButton
		local button = ui.makeButton(header, UDim2.fromOffset(190, 36), UDim2.new(1, -200, 0, y), color)
		button.Font = Enum.Font.GothamBlack
		button.TextSize = 13
		button.ZIndex = 420
		return button
	end
	pop.surrender = headerButton(10, Kit.RED)
	pop.mark = headerButton(56, Color3.fromRGB(60, 110, 170))
	pop.live = headerButton(102, Color3.fromRGB(70, 140, 80))
	pop.surrender.Activated:Connect(function()
		if os.clock() - surrenderArmed < 4 then
			surrenderArmed = 0
			ui.send("RealmSurrender", selected)
		else
			surrenderArmed = os.clock()
			ui.redraw()
		end
	end)
	pop.mark.Activated:Connect(function()
		ui.send("RealmMark", selected)
	end)
	pop.live.Activated:Connect(function()
		if latest and latest.realm.home == selected then
			ui.send("RealmLive", "")
		else
			ui.send("RealmLive", selected)
		end
	end)

	-- tabs
	local tabRow = ui.makeFrame(page, UDim2.new(1, -10, 0, 40), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	tabRow.BackgroundTransparency = 1
	tabRow.LayoutOrder = 2
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 6)
	tabLayout.Parent = tabRow
	pop.tabs = {}
	for _, entry in TABS do
		local button = ui.makeButton(tabRow, UDim2.new(0.2, -5, 1, 0), UDim2.fromOffset(0, 0), ui.colors.row)
		button.Font = Enum.Font.GothamBlack
		button.TextSize = 14
		button.Text = entry[2]
		button.Activated:Connect(function()
			tab = entry[1]
			ui.redraw()
		end)
		pop.tabs[entry[1]] = button
	end
	pop.bodies = {}

	-- OVERVIEW
	local overview = body(ui, page, 3)
	pop.bodies.overview = overview
	local grid = Kit.grid(ui, overview, 1, 120, 2)
	grid.Size = UDim2.new(1, 0, 0, 0)
	pop.bonus = infoCard(ui, grid, 1, "TERRITORY BONUS", false)
	pop.stipend = infoCard(ui, grid, 2, "STIPEND  \u{2022}  EVERY 2 HOURS", false)
	pop.strength = infoCard(ui, grid, 3, "TERRITORY STRENGTH", false)
	pop.strengthBar = Kit.bar(ui, pop.strength.card, UDim2.new(1, -24, 0, 20), UDim2.fromOffset(12, 30), Kit.RED)
	pop.strength.big.Visible = false
	pop.strength.note.Position = UDim2.fromOffset(12, 58)
	pop.garrison = infoCard(ui, grid, 4, "GARRISON", false)
	sectionTitle(ui, overview, 2).Text = "\u{1F4DC}  History"
	pop.history = {}
	for index = 1, SocialConfig.HistoryKept do
		pop.history[index] = listRow(ui, overview, 2 + index, false)
	end
	pop.noHistory = listRow(ui, overview, 2, false)
	pop.noHistory.row.LayoutOrder = 3
	pop.noHistory.text.Text = "Nothing has happened here yet."

	-- ATTACK
	local attack = body(ui, page, 4)
	pop.bodies.attack = attack
	local attackGrid = Kit.grid(ui, attack, 1, 150, 2)
	attackGrid.Size = UDim2.new(1, 0, 0, 0)
	pop.claim = infoCard(ui, attackGrid, 1, "UNCLAIMED", true)
	pop.claim.button.BackgroundColor3 = Kit.GOLD
	pop.claim.button.Activated:Connect(function()
		ui.send("RealmClaim", selected)
	end)
	pop.claimInfo = infoCard(ui, attackGrid, 2, "WHAT YOU GET", false)
	pop.hit = infoCard(ui, attackGrid, 3, "\u{2694}\u{FE0F} ATTACK", true)
	pop.hit.button.Activated:Connect(function()
		Kit.pop(pop.hit.card, 1.05)
		ui.send("RealmAttack", `{selected}:attack`)
	end)
	pop.siege = infoCard(ui, attackGrid, 4, "\u{1F40F} SIEGE", true)
	pop.siege.button.Activated:Connect(function()
		Kit.pop(pop.siege.card, 1.05)
		ui.send("RealmAttack", `{selected}:siege`)
	end)
	pop.enemy = infoCard(ui, attackGrid, 5, "ITS DEFENSE", false)
	pop.enemyBar = Kit.bar(ui, pop.enemy.card, UDim2.new(1, -24, 0, 20), UDim2.fromOffset(12, 30), Kit.RED)
	pop.enemy.big.Visible = false
	pop.yours = infoCard(ui, attackGrid, 6, "YOUR GUILD HOLDS THIS", false)

	-- GARRISON
	local garrison = body(ui, page, 5)
	pop.bodies.garrison = garrison
	pop.garrisonSummary = listRow(ui, garrison, 1, true)
	pop.garrisonSummary.row.Size = UDim2.new(1, 0, 0, 44)
	pop.garrisonSummary.button.Text = "RECALL ALL MINE"
	pop.garrisonSummary.button.Activated:Connect(function()
		ui.send("RealmRecall", `{selected}:all`)
	end)
	pop.mineTitle = sectionTitle(ui, garrison, 2)
	pop.mineRows = {}
	for index = 1, ROWS do
		local row = listRow(ui, garrison, 2 + index, true)
		row.button.Text = "RECALL"
		pop.mineRows[index] = row
	end
	pop.crewTitle = sectionTitle(ui, garrison, 30)
	pop.crewRows = {}
	for index = 1, ROWS do
		local row = listRow(ui, garrison, 30 + index, true)
		row.button.BackgroundColor3 = Kit.GREEN
		pop.crewRows[index] = row
	end
	pop.playersTitle = sectionTitle(ui, garrison, 60)
	pop.playerRows = {}
	for index = 1, 12 do
		pop.playerRows[index] = listRow(ui, garrison, 60 + index, false)
	end

	-- RESIDENTS
	local residents = body(ui, page, 6)
	pop.bodies.residents = residents
	local residentGrid = Kit.grid(ui, residents, 1, 150, 2)
	residentGrid.Size = UDim2.new(1, 0, 0, 0)
	pop.residentCard = infoCard(ui, residentGrid, 1, "RESIDENTS", true)
	pop.residentCard.button.BackgroundColor3 = Color3.fromRGB(70, 140, 80)
	pop.residentCard.button.Activated:Connect(function()
		if latest and latest.realm.home == selected then
			ui.send("RealmLive", "")
		else
			ui.send("RealmLive", selected)
		end
	end)
	pop.residentCard.note.Size = UDim2.new(1, -20, 0, 50)
	pop.residentShare = infoCard(ui, residentGrid, 2, "WHAT RESIDENTS GET", false)
	pop.residentNames = ui.makeText(residents, UDim2.new(1, 0, 0, 0), UDim2.fromOffset(0, 0), ui.colors.dim, 13)
	pop.residentNames.AutomaticSize = Enum.AutomaticSize.Y
	pop.residentNames.LayoutOrder = 2
	pop.residentNames.Font = Enum.Font.GothamBold
	pop.residentNames.RichText = true

	-- rules the holders set: who may live here, from what level, and rent
	local rules, rulesStroke = Kit.card(ui, residents, 3, Kit.GOLD)
	rules.Size = UDim2.new(1, 0, 0, 160)
	local _ = rulesStroke
	pop.rules = rules
	local rulesTitle = ui.makeText(rules, UDim2.new(1, -20, 0, 20), UDim2.fromOffset(12, 8), Kit.GOLD, 14)
	rulesTitle.Font = Enum.Font.GothamBlack
	rulesTitle.Text = "\u{1F4DC} RESIDENCY RULES  \u{2022}  your guild sets these"
	local function sendRules(mode: string?, level: number?, rent: number?)
		local land = latest and latest.realm.lands[selected]
		local policy = land and land.policy or { mode = "open", level = 0, rent = 0 }
		ui.send("RealmPolicy", `{selected}:{mode or policy.mode}:{math.max(0, level or policy.level or 0)}:{math.max(0, rent or policy.rent or 0)}`)
	end
	pop.modes = {}
	for index, entry in { { "open", "OPEN TO ALL" }, { "apply", "BY APPLICATION" }, { "closed", "CLOSED" } } do
		local button = ui.makeButton(rules, UDim2.new(1 / 3, -12, 0, 34), UDim2.new((index - 1) / 3, 8, 0, 34), ui.colors.row)
		button.Font = Enum.Font.GothamBlack
		button.TextSize = 13
		button.Text = entry[2]
		button.Activated:Connect(function()
			sendRules(entry[1], nil, nil)
		end)
		pop.modes[entry[1]] = button
	end
	local function stepper(y: number, title: string, onStep)
		local label = ui.makeText(rules, UDim2.new(0.5, -20, 0, 34), UDim2.fromOffset(12, y), ui.colors.text, 14)
		label.Font = Enum.Font.GothamBold
		label.RichText = true
		label.Text = title
		local minus = ui.makeButton(rules, UDim2.fromOffset(44, 34), UDim2.new(1, -110, 0, y), Kit.RED)
		minus.Text = "\u{2212}"
		minus.TextSize = 20
		minus.Activated:Connect(function()
			onStep(-1)
		end)
		local plus = ui.makeButton(rules, UDim2.fromOffset(44, 34), UDim2.new(1, -56, 0, y), Kit.GREEN)
		plus.Text = "+"
		plus.TextSize = 20
		plus.Activated:Connect(function()
			onStep(1)
		end)
		return label
	end
	pop.levelRule = stepper(76, "", function(step: number)
		local land = latest and latest.realm.lands[selected]
		local level = land and land.policy and land.policy.level or 0
		sendRules(nil, math.clamp(level + step * 5, 0, SocialConfig.ResidentLevelMax), nil)
	end)
	pop.rentRule = stepper(116, "", function(step: number)
		local territory = SocialConfig.TerritoryById[selected]
		local land = latest and latest.realm.lands[selected]
		if not territory then
			return
		end
		local most = SocialConfig.rentMax(territory.tier)
		local rent = land and land.policy and land.policy.rent or 0
		-- steps: none, then 1%, 2%, 5%, 10%, 25%, 50%, 100% of the most allowed
		local steps = { 0, 0.01, 0.02, 0.05, 0.1, 0.25, 0.5, 1 }
		local at = 1
		for index, share in steps do
			if rent >= math.floor(most * share) then
				at = index
			end
		end
		at = math.clamp(at + step, 1, #steps)
		sendRules(nil, nil, math.floor(most * steps[at]))
	end)

	pop.applicantsTitle = sectionTitle(ui, residents, 4)
	pop.applicantRows = {}
	for index = 1, SocialConfig.ApplicantsKept do
		local row = listRow(ui, residents, 4 + index, true)
		row.button.Size = UDim2.fromOffset(90, 28)
		row.button.Position = UDim2.new(1, -196, 0, 4)
		row.button.BackgroundColor3 = Kit.GREEN
		row.button.Text = "ACCEPT"
		local no = ui.makeButton(row.row, UDim2.fromOffset(90, 28), UDim2.new(1, -98, 0, 4), Kit.RED)
		no.Font = Enum.Font.GothamBlack
		no.TextSize = 12
		no.Text = "TURN DOWN"
		row.button.Activated:Connect(function()
			local userId = row.row:GetAttribute("UserId")
			if userId then
				ui.send("RealmAnswer", `{selected}:{userId}:yes`)
			end
		end)
		no.Activated:Connect(function()
			local userId = row.row:GetAttribute("UserId")
			if userId then
				ui.send("RealmAnswer", `{selected}:{userId}:no`)
			end
		end)
		pop.applicantRows[index] = row
	end

	-- FORTIFY
	local fortify = body(ui, page, 7)
	pop.bodies.fortify = fortify
	local warning = listRow(ui, fortify, 1, false)
	warning.text.Text = "\u{26A0}\u{FE0F}  Every fortification is lost if another guild captures this territory."
	warning.text.TextColor3 = Color3.fromRGB(255, 200, 150)
	local fortGrid = Kit.grid(ui, fortify, 2, 200, 2)
	fortGrid.Size = UDim2.new(1, 0, 0, 0)
	pop.forts = {}
	for index, fort in SocialConfig.Forts do
		local card, stroke = Kit.card(ui, fortGrid, index, ui.colors.dim)
		local name = ui.makeText(card, UDim2.new(1, -24, 0, 24), UDim2.fromOffset(12, 8), Kit.GOLD, 18)
		name.Font = ui.art.Fonts.heading
		local about = ui.makeText(card, UDim2.new(1, -24, 0, 18), UDim2.fromOffset(12, 34), ui.colors.dim, 12)
		about.Font = Enum.Font.GothamBold
		about.RichText = true
		local pips = {}
		for pip = 1, SocialConfig.FortMax do
			local dot = ui.makeFrame(card, UDim2.fromOffset(26, 10), UDim2.fromOffset(12 + (pip - 1) * 32, 58), Color3.fromRGB(60, 52, 44))
			ui.addCorner(dot, 4)
			pips[pip] = dot
		end
		local goldBar = Kit.bar(ui, card, UDim2.new(1, -24, 0, 18), UDim2.fromOffset(12, 78), Kit.GOLD)
		local energyBar = Kit.bar(ui, card, UDim2.new(1, -24, 0, 18), UDim2.fromOffset(12, 102), Color3.fromRGB(90, 160, 230))
		local giveGold = ui.makeButton(card, UDim2.new(0.5, -18, 0, 34), UDim2.new(0, 12, 1, -44), Kit.GOLD)
		giveGold.Font = Enum.Font.GothamBlack
		giveGold.TextSize = 12
		local giveEnergy = ui.makeButton(card, UDim2.new(0.5, -18, 0, 34), UDim2.new(0.5, 6, 1, -44), Color3.fromRGB(90, 160, 230))
		giveEnergy.Font = Enum.Font.GothamBlack
		giveEnergy.TextSize = 12
		local part = { card = card, stroke = stroke, name = name, about = about, pips = pips, goldBar = goldBar, energyBar = energyBar, giveGold = giveGold, giveEnergy = giveEnergy, gold = 0, energy = 0 }
		giveGold.Activated:Connect(function()
			if part.gold > 0 then
				Kit.pop(card, 1.04)
				ui.send("RealmDonate", `{selected}:{fort.key}:gold:{part.gold}`)
			end
		end)
		giveEnergy.Activated:Connect(function()
			if part.energy > 0 then
				Kit.pop(card, 1.04)
				ui.send("RealmDonate", `{selected}:{fort.key}:energy:{part.energy}`)
			end
		end)
		pop.forts[fort.key] = part
	end
end

-- What the LIVE HERE button says and whether it can be pressed.
local function liveButton(state, realm, info): (string, boolean)
	local policy = info.policy or { mode = "open", level = 0, rent = 0 }
	if realm.home == selected then
		return "\u{1F3E0} MOVE OUT", true
	elseif realm.applied == selected then
		return "APPLICATION SENT", false
	elseif policy.mode == "closed" then
		return "\u{1F512} CLOSED", false
	elseif state.level < (policy.level or 0) then
		return `LEVEL {policy.level}`, false
	elseif policy.mode == "apply" then
		return "\u{1F4DD} APPLY TO LIVE", true
	end
	return "\u{1F3E0} LIVE HERE", true
end

local function drawPopup(state, ui)
	local realm = state.realm
	local territory = SocialConfig.TerritoryById[selected]
	if not territory then
		return
	end
	local tier = SocialConfig.Tiers[territory.tier]
	local info = realm.lands[territory.id] or { strength = 0, max = 1, garrison = 0, defense = 0, residents = 0, forts = {}, regen = SocialConfig.RegenPerHour }
	local view = if realm.view and realm.view.id == selected then realm.view else nil
	local holder = info.holder
	local guildId = realm.guildId or ""
	local mine = holder ~= nil and guildId ~= "" and holder.id == guildId
	local now = os.time()

	-- header
	pop.headerGradient.Color = ColorSequence.new(tier.sky, tier.land:Lerp(Color3.new(0, 0, 0), 0.4))
	Landmarks.draw(pop.picture, territory.tier)
	pop.name.Text = territory.name
	pop.tier.Text = `TIER {territory.tier}  \u{2022}  {string.upper(tier.name)}  \u{2022}  LEVEL {tier.level}+`
	pop.held.Text = if holder then `HELD BY <font color="#F0C450">{guildText(holder)}</font>` else "UNCLAIMED"
	local flags = {}
	if info.marked then
		table.insert(flags, "\u{1F6E1}\u{FE0F} Marked for defense")
	end
	if info.hot then
		table.insert(flags, "\u{1F525} Under attack")
	end
	if realm.home == selected then
		table.insert(flags, "\u{1F3E0} You live here")
	end
	if holder and info.since and info.since > 0 then
		table.insert(flags, `held since {ago(now - info.since)}`)
	end
	pop.flags.Text = table.concat(flags, "   ")
	pop.surrender.Visible = mine and realm.officer
	ui.setButton(pop.surrender, if os.clock() - surrenderArmed < 4 then "PRESS AGAIN TO GIVE UP" else "\u{1F3F3}\u{FE0F} SURRENDER", true, Kit.RED)
	pop.mark.Visible = mine and realm.officer
	ui.setButton(pop.mark, if info.marked then "UNMARK DEFENSE" else "\u{1F6E1}\u{FE0F} MARK FOR DEFENSE", true, Color3.fromRGB(60, 110, 170))
	local liveLabel, liveUsable = liveButton(state, realm, info)
	ui.setButton(pop.live, liveLabel, liveUsable, Color3.fromRGB(70, 140, 80))

	for key, button in pop.tabs do
		local on = key == tab
		button.BackgroundColor3 = if on then Kit.GOLD else ui.colors.row
		button.TextColor3 = if on then Color3.fromRGB(40, 28, 12) else Color3.new(1, 1, 1)
	end
	for key, frame in pop.bodies do
		frame.Visible = key == tab
	end

	-- OVERVIEW
	local share = SocialConfig.residentShare(info.forts.homes or 0)
	pop.bonus.big.Text = bonusText(territory)
	pop.bonus.note.Text = (if holder then `<font color="#6ED26E">ACTIVE FOR {string.upper(guildText(holder))}</font>` else "Nobody holds it, so nobody gets it.")
		.. `\nResidents get {math.floor(share * 100 + 0.5)}% of this bonus.`
	pop.stipend.big.Text = `{tier.stipendMinutes} min of income`
	pop.stipend.note.Text = if mine then `Paid to every member while they play. Next in <font color="#F0C450">{Kit.clock(realm.stipendIn)}</font>.` else "Paid to every member of the holding guild."
	if holder then
		Kit.setBar(pop.strengthBar, info.strength, info.max, `{Format.short(info.strength)} / {Format.short(info.max)}`)
		pop.strength.note.Text = `Regains {math.floor(info.regen * 100 + 0.5)}% an hour. At 0 the attacking guild captures it.`
	else
		Kit.setBar(pop.strengthBar, 0, 1, "UNCLAIMED")
		pop.strength.note.Text = "Nobody holds it. Any guild can claim it without a fight."
	end
	pop.garrison.big.Text = `{info.garrison} / {tier.garrison} soldiers`
	pop.garrison.note.Text = `<font color="#6ED26E">{pct(info.defense)} DEFENSE</font>: attacks on it do less damage.`
	local history = view and view.history or {}
	pop.noHistory.row.Visible = #history == 0
	for index, row in pop.history do
		local entry = history[index]
		row.row.Visible = entry ~= nil
		if entry then
			row.text.Text = `<font color="#B2A690">{ago(now - (entry.t or now))}</font>   {entry.x}`
		end
	end

	-- ATTACK
	local inGuild = guildId ~= ""
	local levelOk = state.level >= tier.level
	pop.claim.card.Visible = holder == nil
	pop.claimInfo.card.Visible = holder == nil
	pop.hit.card.Visible = holder ~= nil and not mine
	pop.siege.card.Visible = holder ~= nil and not mine
	pop.enemy.card.Visible = holder ~= nil and not mine
	pop.yours.card.Visible = mine
	if holder == nil then
		pop.claim.big.Text = `Claim for <font color="#F0C450">{Format.short(tier.claim)}</font> gold`
		pop.claim.note.Text = `No fight and no level needed. Your guild holds {realm.held} of its {realm.maxHeld} (2 + guild level).`
		local label = if not inGuild then "JOIN A GUILD"
			elseif realm.held >= realm.maxHeld then "GUILD AT ITS LIMIT"
			else "\u{1F6A9} CLAIM"
		ui.setButton(pop.claim.button, label, inGuild and realm.held < realm.maxHeld and state.gold >= tier.claim, Kit.GOLD)
		pop.claimInfo.big.Text = bonusText(territory)
		pop.claimInfo.note.Text = `For every member, plus a stipend of {tier.stipendMinutes} min of income every 2 hours. Other guilds can then attack it.`
	elseif not mine then
		local damageCut = 1 / (1 + info.defense)
		local attackDamage = math.floor(realm.attackDamage * damageCut)
		local siegeDamage = math.floor(realm.siegeDamage * damageCut)
		local wounded = (state.health or 0) < GameConfig.MinHealthToFight
		pop.hit.big.Text = `~{Format.short(attackDamage)} damage`
		pop.hit.note.Text = `Costs {SocialConfig.AttackStamina} stamina. You have {math.floor(state.stamina)}.`
		local attackLabel = if not inGuild then "JOIN A GUILD" elseif not levelOk then `LEVEL {tier.level}` elseif wounded then "TOO WOUNDED" else "\u{2694}\u{FE0F} ATTACK"
		ui.setButton(pop.hit.button, attackLabel, inGuild and levelOk and not wounded and state.stamina >= SocialConfig.AttackStamina, Kit.RED)
		pop.siege.big.Text = `~{Format.short(siegeDamage)} damage`
		pop.siege.note.Text = `Costs {SocialConfig.SiegeEnergy} energy. You have {math.floor(state.energy)}.`
		local siegeLabel = if not inGuild then "JOIN A GUILD" elseif not levelOk then `LEVEL {tier.level}` elseif wounded then "TOO WOUNDED" else "\u{1F40F} SIEGE"
		ui.setButton(pop.siege.button, siegeLabel, inGuild and levelOk and not wounded and state.energy >= SocialConfig.SiegeEnergy, Color3.fromRGB(170, 90, 40))
		Kit.setBar(pop.enemyBar, info.strength, info.max, `{Format.short(info.strength)} / {Format.short(info.max)}`)
		pop.enemy.note.Text = `Garrison {info.garrison} soldiers: {pct(info.defense)} defense cuts your damage. Bring it to 0 to capture it.`
	else
		pop.yours.big.Text = "Defend it"
		pop.yours.note.Text = "Station soldiers in the GARRISON tab and build the FORTIFY buildings so it is harder to take."
	end

	-- GARRISON
	pop.garrisonSummary.text.Text = `<font color="#F0C450">{info.garrison} / {tier.garrison}</font> soldiers  \u{2022}  <font color="#6ED26E">{pct(info.defense)} defense</font>`
	local here, waiting = {}, 0
	for _, entry in realm.stationed do
		if entry.t == selected then
			table.insert(here, entry)
		elseif entry.t == "" then
			waiting += 1
		end
	end
	pop.garrisonSummary.button.Visible = #here > 0
	pop.mineTitle.Text = if waiting > 0 then `Your soldiers here ({#here})  \u{2022}  {waiting} waiting for a free warband slot` else `Your soldiers here ({#here})`
	for index, row in pop.mineRows do
		local entry = here[index]
		row.row.Visible = entry ~= nil
		if entry then
			local color = GameConfig.getRarity(entry.rarity).color
			row.text.Text = `<font color="#{color:ToHex()}">{entry.rarity}</font> {entry.class} {entry.name}   \u{1F6E1}\u{FE0F} {Format.short(entry.defense)}`
			local stationIndex = entry.index
			row.button:SetAttribute("Index", stationIndex)
		end
	end
	local crew = {}
	if mine then
		for slot, soldier in state.crew or {} do
			if soldier then
				table.insert(crew, { slot = slot, soldier = soldier })
			end
		end
	end
	pop.crewTitle.Visible = mine
	pop.crewTitle.Text = if #crew > 0 then "Station from your warband (they leave the warband while on guard)" else "Your warband is empty"
	local full = info.garrison >= tier.garrison
	for index, row in pop.crewRows do
		local entry = crew[index]
		row.row.Visible = entry ~= nil
		if entry then
			local soldier = entry.soldier
			local color = GameConfig.getRarity(soldier.rarity).color
			row.text.Text = `<font color="#{color:ToHex()}">{soldier.rarity}</font> {soldier.class} {soldier.name}   \u{1F6E1}\u{FE0F} {Format.short(soldier.defense or 0)}`
			row.button:SetAttribute("Slot", entry.slot)
			ui.setButton(row.button, if full then "GARRISON FULL" else "STATION", not full, Kit.GREEN)
		end
	end
	local players = view and view.garrison or {}
	pop.playersTitle.Text = if holder then `Garrison of {guildText(holder)}` else "No garrison"
	for index, row in pop.playerRows do
		local entry = players[index]
		row.row.Visible = entry ~= nil
		if entry then
			row.text.Text = `{entry.name}   <font color="#B2A690">{entry.count} soldier{if entry.count == 1 then "" else "s"}</font>   \u{1F6E1}\u{FE0F} {Format.short(entry.defense)}`
		end
	end

	-- RESIDENTS
	pop.residentCard.big.Text = `{info.residents} / {SocialConfig.ResidentsMax} live here`
	local homeLand = SocialConfig.TerritoryById[realm.home]
	local homeName = if homeLand then homeLand.name else "another territory"
	pop.residentCard.note.Text = if realm.home == selected then "This is your home." elseif realm.home ~= "" then `You live in {homeName}. Moving here moves you out.` else "Any player can live in one territory, in any guild or none."
	ui.setButton(pop.residentCard.button, liveLabel, liveUsable, Color3.fromRGB(70, 140, 80))
	local policy = info.policy or { mode = "open", level = 0, rent = 0 }
	local modeText = ({ open = "open to all", apply = "by application", closed = "closed" })[policy.mode] or "open to all"
	local rentText = if (policy.rent or 0) > 0 then `{Format.short(policy.rent)} gold rent every 2 hours` else "no rent"
	pop.residentCard.note.Text ..= `\n<font color="#F0C450">Rules: {modeText}, level {policy.level or 0}+, {rentText}.</font>`
	pop.rules.Visible = mine and realm.officer
	for mode, button in pop.modes do
		button.BackgroundColor3 = if mode == policy.mode then Kit.GOLD else ui.colors.row
		button.TextColor3 = if mode == policy.mode then Color3.fromRGB(40, 28, 12) else Color3.new(1, 1, 1)
	end
	pop.levelRule.Text = `Level needed: <font color="#F0C450">{policy.level or 0}+</font>`
	pop.rentRule.Text = `Rent every 2 hours: <font color="#F0C450">{Format.short(policy.rent or 0)}</font> gold <font color="#B2A690">(most {Format.short(SocialConfig.rentMax(territory.tier))})</font>`
	local applicants = view and view.applicants or {}
	local showApplicants = mine and realm.officer and policy.mode == "apply"
	pop.applicantsTitle.Visible = showApplicants
	pop.applicantsTitle.Text = if #applicants > 0 then `Applications ({#applicants})` else "No applications waiting"
	for index, row in pop.applicantRows do
		local entry = applicants[index]
		row.row.Visible = showApplicants and entry ~= nil
		if entry then
			row.row:SetAttribute("UserId", entry.userId)
			row.text.Text = `{entry.name}   <font color="#B2A690">level {entry.level}, {ago(now - entry.time)}</font>`
		end
	end
	pop.residentShare.big.Text = `{math.floor(share * 100 + 0.5)}% of {bonusText(territory)}`
	pop.residentShare.note.Text = "While any guild holds it. Members of the holding guild get the full bonus and pay no rent. The townhouse building raises the share. Rent goes to the holding guild as guild experience."
	local names = view and view.names or {}
	pop.residentNames.Text = if #names > 0 then `Residents: {table.concat(names, ", ")}{if info.residents > #names then ` and {info.residents - #names} more` else ""}` else "Nobody lives here yet."

	-- FORTIFY
	for index, fort in SocialConfig.Forts do
		local part = pop.forts[fort.key]
		local progress = view and view.forts and view.forts[fort.key] or { l = info.forts[fort.key] or 0, g = 0, e = 0 }
		local level = progress.l
		part.name.Text = tier.forts[index]
		part.about.Text = `{fort.about}: <font color="#6ED26E">{fort.text}</font>  \u{2022}  LEVEL {level}/{SocialConfig.FortMax}`
		for pip, dot in part.pips do
			dot.BackgroundColor3 = if pip <= level then Kit.GOLD else Color3.fromRGB(60, 52, 44)
		end
		local maxed = level >= SocialConfig.FortMax
		local needGold, needEnergy = SocialConfig.fortCost(territory.tier, level)
		if maxed then
			Kit.setBar(part.goldBar, 1, 1, "FULLY BUILT")
			Kit.setBar(part.energyBar, 1, 1, "FULLY BUILT")
		else
			Kit.setBar(part.goldBar, progress.g, needGold, `\u{1F4B0} {Format.short(progress.g)} / {Format.short(needGold)}`)
			Kit.setBar(part.energyBar, progress.e, needEnergy, `\u{26A1} {Format.short(progress.e)} / {Format.short(needEnergy)}`)
		end
		local goldLeft = math.max(0, needGold - progress.g)
		local energyLeft = math.max(0, needEnergy - progress.e)
		part.gold = math.min(math.floor(state.gold), goldLeft, math.ceil(needGold / 4))
		part.energy = math.min(math.floor(state.energy), energyLeft)
		local open = mine and not maxed
		ui.setButton(part.giveGold, if not mine then "HOLDERS ONLY" elseif maxed then "BUILT" else `GIVE {Format.short(part.gold)} GOLD`, open and part.gold > 0, Kit.GOLD)
		ui.setButton(part.giveEnergy, if not mine then "HOLDERS ONLY" elseif maxed then "BUILT" else `GIVE {Format.short(part.energy)} ENERGY`, open and part.energy > 0, Color3.fromRGB(90, 160, 230))
		Kit.setPulse(part.stroke, maxed, ui.colors.dim)
	end
end

---------------------------------------------------------------------------

function RealmPage.build(ui)
	local page = ui.pages["Realm Map"]
	local banner = Kit.banner(ui, page, 1, 130, Color3.fromRGB(60, 110, 70), Color3.fromRGB(20, 40, 24), "Realm of Ashvale", "\u{1F6A9}")
	w.status = Kit.line(ui, banner, 120, 64, UDim.new(0.5, -120), 15, Color3.new(1, 1, 1))
	w.status.Font = Enum.Font.GothamBlack
	w.stipend = Kit.line(ui, banner, 120, 90, UDim.new(0.5, -120), 13, Color3.fromRGB(220, 255, 220))
	-- top guilds
	local top = ui.makeFrame(banner, UDim2.new(0.42, -14, 1, -20), UDim2.new(0.58, 0, 0, 10), Color3.fromRGB(10, 20, 12))
	top.BackgroundTransparency = 0.35
	top.ZIndex = 410
	ui.addCorner(top, 8)
	local topTitle = ui.makeText(top, UDim2.new(1, -150, 0, 20), UDim2.fromOffset(12, 4), Kit.GOLD, 13)
	topTitle.Font = Enum.Font.GothamBlack
	topTitle.Text = "\u{1F3C6} TOP GUILDS"
	topTitle.ZIndex = 411
	w.bonuses = ui.makeButton(top, UDim2.fromOffset(130, 24), UDim2.new(1, -138, 0, 4), Color3.fromRGB(60, 110, 70))
	w.bonuses.Font = Enum.Font.GothamBlack
	w.bonuses.TextSize = 11
	w.bonuses.Text = "MY BONUSES"
	w.bonuses.ZIndex = 412
	w.bonuses.Activated:Connect(function()
		ui.openModal("RealmBonuses", "Realm bonuses")
	end)
	w.top = {}
	for place = 1, 3 do
		local label = ui.makeText(top, UDim2.new(1, -24, 0, 24), UDim2.fromOffset(12, 6 + place * 24), Color3.new(1, 1, 1), 14)
		label.Font = Enum.Font.GothamBlack
		label.RichText = true
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.ZIndex = 411
		w.top[place] = label
	end

	-- region selector
	local strip = ui.makeFrame(page, UDim2.new(1, -10, 0, 58), UDim2.fromOffset(0, 0), Color3.fromRGB(40, 33, 24))
	strip.LayoutOrder = 2
	ui.addCorner(strip, 8)
	ui.art.stroke(strip, ui.colors.gold, 1.5, 0.3)
	local function showTier(tier: number?)
		tierShown = tier
		if tier then
			focusRegion(tier)
		else
			resetView()
		end
		ui.redraw()
	end
	local function arrow(text: string, position: UDim2, step: number)
		local button = ui.makeButton(strip, UDim2.fromOffset(42, 42), position, Color3.fromRGB(70, 56, 36))
		button.Text = text
		button.TextSize = 20
		button.Font = Enum.Font.GothamBlack
		button.Activated:Connect(function()
			local at = tierShown or (if step > 0 then 0 else #SocialConfig.Tiers + 1)
			showTier(math.clamp(at + step, 1, #SocialConfig.Tiers))
		end)
	end
	arrow("\u{25C0}", UDim2.fromOffset(8, 8), -1)
	arrow("\u{25B6}", UDim2.new(0.55, -50, 0, 8), 1)
	w.tierName = ui.makeText(strip, UDim2.new(0.55, -116, 0, 26), UDim2.fromOffset(58, 4), Kit.GOLD, 20)
	w.tierName.Font = ui.art.Fonts.heading
	w.tierName.TextXAlignment = Enum.TextXAlignment.Center
	w.tierAbout = ui.makeText(strip, UDim2.new(0.55, -116, 0, 20), UDim2.fromOffset(58, 32), ui.colors.dim, 11)
	w.tierAbout.Font = Enum.Font.GothamBold
	w.tierAbout.TextXAlignment = Enum.TextXAlignment.Center
	w.tierTabs = {}
	for index, tier in SocialConfig.Tiers do
		local button = ui.makeButton(strip, UDim2.new(0.09, -6, 0, 42), UDim2.new(0.55 + (index - 1) * 0.09, 0, 0, 8), tier.land)
		button.Font = Enum.Font.GothamBlack
		button.TextSize = 12
		button.Activated:Connect(function()
			showTier(if tierShown == index then nil else index)
		end)
		w.tierTabs[index] = button
	end

	buildMap(ui, page)
	w.footer = ui.makeText(page, UDim2.new(1, -10, 0, 30), UDim2.fromOffset(0, 0), ui.colors.dim, 13)
	w.footer.LayoutOrder = 4
	w.footer.Font = Enum.Font.GothamBold
	w.footer.RichText = true

	-- bonuses popup
	local bonusPage = ui.pages.RealmBonuses
	w.bonusList = ui.makeText(bonusPage, UDim2.new(1, -10, 0, 0), UDim2.fromOffset(0, 0), ui.colors.text, 15)
	w.bonusList.AutomaticSize = Enum.AutomaticSize.Y
	w.bonusList.Font = Enum.Font.GothamBold
	w.bonusList.RichText = true
	w.bonusList.LayoutOrder = 1

	buildPopup(ui)
	for index, row in pop.mineRows do
		row.button.Activated:Connect(function()
			local stationIndex = row.button:GetAttribute("Index")
			if stationIndex then
				ui.send("RealmRecall", `{selected}:{stationIndex}`)
			end
		end)
		local _ = index
	end
	for _, row in pop.crewRows do
		row.button.Activated:Connect(function()
			local slot = row.button:GetAttribute("Slot")
			if slot then
				Kit.pop(row.row, 1.04)
				ui.send("RealmStation", `{selected}:{slot}`)
			end
		end)
	end

	Fx.handlers.realm = function(info)
		local territory = SocialConfig.TerritoryById[info.territory or ""]
		if not territory then
			return
		end
		local part = cells[territory.id]
		local onMap = part ~= nil and w.board.Parent ~= nil and not ui.isOpen("Territory")
		local target = if ui.isOpen("Territory") and selected == territory.id then pop.header elseif onMap then part.cell else nil
		if not target then
			return
		end
		if info.kind == "attack" or info.kind == "siege" then
			Kit.float(ui, target, `-{Format.short(info.damage or 0)}`, Kit.RED)
			Kit.pop(target, if info.kind == "siege" then 1.08 else 1.03)
		elseif info.kind == "claim" or info.kind == "capture" then
			Kit.float(ui, target, if info.kind == "claim" then "\u{1F6A9} CLAIMED!" else "\u{1F451} CAPTURED!", Kit.GOLD)
			Kit.pop(target, 1.12)
		elseif info.kind == "fortLevel" then
			Kit.float(ui, target, "\u{1F3F0} LEVEL UP!", Kit.GREEN)
		elseif info.kind == "station" then
			Kit.float(ui, target, "\u{1F6E1}\u{FE0F} ON GUARD", Kit.GREEN)
		end
		if onMap then
			part.stroke.Thickness = 7
			TweenService:Create(part.stroke, TweenInfo.new(0.6), { Thickness = 3 }):Play()
		end
	end
	page:GetPropertyChangedSignal("Visible"):Connect(function()
		if page.Visible then
			Kit.popAll(w.board)
			ui.send("RealmRefresh")
		end
	end)
end

function RealmPage.draw(state, ui)
	if not state or not state.realm or not state.realm.lands then
		return
	end
	latest = state
	local realm = state.realm
	local guildId = realm.guildId or ""

	-- banner
	if guildId == "" then
		w.status.Text = "You are not in a guild"
		w.stipend.Text = "Join or found one on the Guild page to claim and fight for territories."
	else
		w.status.Text = `Your guild holds <font color="#F0C450">{realm.held}</font> of {#SocialConfig.Territories} territories (most {realm.maxHeld})`
		w.stipend.Text = if realm.stipendNext > 0 then `Next stipend in {Kit.clock(realm.stipendIn)}: <font color="#F0C450">+{Format.short(realm.stipendNext)}</font> gold` else "Hold a territory for a stipend every 2 hours."
	end
	local medals = { "\u{1F947}", "\u{1F948}", "\u{1F949}" }
	for place, label in w.top do
		local entry = realm.top[place]
		label.Visible = entry ~= nil or place == 1
		if entry then
			local color = guildColor(entry.id):ToHex()
			label.Text = `{medals[place]} <font color="#{color}">\u{25A0}</font> [{entry.tag}] {entry.name}   <font color="#F0C450">{entry.score} pts</font>  <font color="#B2A690">({entry.held} held)</font>`
		else
			label.Text = "No guild holds a territory yet. Be the first!"
		end
	end

	-- region selector
	if tierShown then
		local info = SocialConfig.Tiers[tierShown]
		w.tierName.Text = `{info.glyph}  {string.upper(info.name)}`
		w.tierAbout.Text = `TIER {tierShown}  \u{2022}  LEVEL {info.level}+  \u{2022}  {info.about}`
	else
		w.tierName.Text = "\u{1F5FA}\u{FE0F}  THE WHOLE REALM"
		w.tierAbout.Text = `{#SocialConfig.Territories} TERRITORIES IN {#SocialConfig.Tiers} TIERS  \u{2022}  PICK A REGION OR DRAG THE MAP`
	end
	-- tier tabs: how many each tier your guild holds
	for index, button in w.tierTabs do
		local held = 0
		for _, territory in byTier[index] do
			local info = realm.lands[territory.id]
			if info and info.holder and guildId ~= "" and info.holder.id == guildId then
				held += 1
			end
		end
		local locked = state.level < SocialConfig.Tiers[index].level
		button.Text = `{if locked then "\u{1F512}" else SocialConfig.Tiers[index].glyph}\n{if held > 0 then `{held}/6` else `T{index}`}`
		local stroke = button:FindFirstChildOfClass("UIStroke")
		button.BackgroundColor3 = SocialConfig.Tiers[index].land:Lerp(Color3.new(0, 0, 0), if index == tierShown then 0 else 0.45)
		if stroke then
			stroke.Color = if index == tierShown then Kit.GOLD else Color3.fromRGB(20, 16, 10)
		end
	end

	-- the map cells
	for id, part in cells do
		local info = realm.lands[id] or {}
		local holder = info.holder
		local mine = holder ~= nil and guildId ~= "" and holder.id == guildId
		local land = SocialConfig.Tiers[part.territory.tier].land
		part.cell.BackgroundColor3 = if holder then guildColor(holder.id) else land:Lerp(PARCHMENT, 0.6)
		part.cell.BackgroundTransparency = if holder then 0.05 else 0.25
		part.owner.Text = if holder then guildText(holder) else "UNCLAIMED"
		part.bar.back.Visible = holder ~= nil
		if holder then
			Kit.setBar(part.bar, info.strength or 0, info.max or 1, Format.short(info.strength or 0))
		end
		local flags = {}
		if mine then
			table.insert(flags, "\u{1F451}")
		end
		if info.marked then
			table.insert(flags, "\u{1F6E1}\u{FE0F}")
		end
		if info.hot then
			table.insert(flags, "\u{1F525}")
		end
		if realm.home == id then
			table.insert(flags, "\u{1F3E0}")
		end
		part.flags.Text = table.concat(flags, " ")
		Kit.setPulse(part.stroke, mine, Color3.fromRGB(30, 22, 14))
	end
	for tier, region in w.regions do
		region.edge.Color = if tier == tierShown then Kit.GOLD else SocialConfig.Tiers[tier].land:Lerp(Color3.new(1, 1, 1), 0.3)
	end

	local stationed, waiting = 0, 0
	for _, entry in realm.stationed do
		if entry.t == "" then
			waiting += 1
		else
			stationed += 1
		end
	end
	local home = SocialConfig.TerritoryById[realm.home]
	w.footer.Text = `\u{1F6E1}\u{FE0F} {stationed} of your soldiers on guard{if waiting > 0 then `, {waiting} waiting for a free warband slot` else ""}   \u{2022}   \u{1F3E0} Home: {if home then home.name else "none (open a territory and press LIVE HERE)"}   \u{2022}   \u{2694}\u{FE0F} {realm.attacks} attacks, {realm.captures} captures`

	-- bonuses popup
	if ui.isOpen("RealmBonuses") then
		local lines = {}
		local totals = {}
		for _, territory in SocialConfig.Territories do
			local info = realm.lands[territory.id]
			if info and info.holder then
				local amount = 0
				local why = ""
				if guildId ~= "" and info.holder.id == guildId then
					amount = territory.amount
					why = "your guild holds it"
				elseif realm.home == territory.id then
					amount = territory.amount * SocialConfig.residentShare(info.forts.homes or 0)
					why = "you live here"
				end
				if amount > 0 then
					totals[territory.bonus] = (totals[territory.bonus] or 0) + amount
					table.insert(lines, `{SocialConfig.Tiers[territory.tier].glyph} <b>{territory.name}</b>  <font color="#6ED26E">{pct(amount)} {SocialConfig.BonusNames[territory.bonus]}</font>  <font color="#B2A690">({why})</font>`)
				end
			end
		end
		local total = {}
		for kind, amount in totals do
			table.insert(total, `<font color="#F0C450">{pct(amount)} {SocialConfig.BonusNames[kind] or kind}</font>`)
		end
		w.bonusList.Text = if #lines == 0 then "No realm bonuses yet. Hold a territory with your guild, or live in one a guild holds."
			else `<b>Total:</b> {table.concat(total, ", ")}\n\n{table.concat(lines, "\n")}`
	end

	if selected ~= "" and not ui.isOpen("Territory") then
		selected = ""
		ui.send("RealmView", "")
	end
	if ui.isOpen("Territory") then
		drawPopup(state, ui)
	end
end

return RealmPage
