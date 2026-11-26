-- Realm Map page (Arena) and the Territory window, laid out like Idle
-- Mafia's territories.
--
-- Page:
--   * top bar: TERRITORIES, help, the top three guilds with their score,
--     and the next stipend
--   * second bar: TERRITORIES list, MY GUILD (dims everyone else's land),
--     "YOUR GUILD HOLDS X OF 50", ALL BONUSES
--   * the map: a honeycomb of 50 territories packed together, five regions
--     (one per tier, Crownlands in the middle), each hex tinted by the
--     guild that holds it, with little buildings in the tier's style, its
--     name and number, and the holder. Drag to move, wheel or +/- to zoom,
--     region selector bottom left, RESET ZOOM bottom right.
--
-- Territory window (press a territory):
--   OVERVIEW   bonus, stipend, strength | garrison list, station, recall
--   ATTACK     CLAIM when nobody holds it, otherwise ATTACK (stamina)
--   SIEGE      SIEGE (energy, much harder hits)
--   RESIDENTS  live there; holders set open / application / closed, level, rent
--   FORTIFY    four buildings named for the tier: now vs next level
--   HISTORY    what happened there

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local SocialConfig = require(Shared:WaitForChild("SocialConfig"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Format = require(Shared:WaitForChild("Format"))
local Kit = require(script.Parent:WaitForChild("Kit"))
local Fx = require(script.Parent:WaitForChild("Fx"))
local Landmarks = require(script.Parent:WaitForChild("Landmarks"))

local RealmPage = {}

local DARK = Color3.fromRGB(26, 24, 22)
local PANEL = Color3.fromRGB(36, 33, 30)
local LINE = Color3.fromRGB(70, 62, 50)
local GOLD = Color3.fromRGB(240, 196, 80)
local GREEN_TEXT = "#6ED26E"
local PARCHMENT = Color3.fromRGB(196, 170, 120)
local GUILD_COLORS = {
	Color3.fromRGB(196, 64, 64), Color3.fromRGB(64, 120, 200), Color3.fromRGB(70, 160, 90), Color3.fromRGB(200, 140, 40),
	Color3.fromRGB(140, 80, 180), Color3.fromRGB(40, 160, 170), Color3.fromRGB(200, 90, 150), Color3.fromRGB(120, 140, 60),
	Color3.fromRGB(210, 110, 60), Color3.fromRGB(90, 90, 200), Color3.fromRGB(160, 60, 90), Color3.fromRGB(60, 140, 130),
}
local FORT_GLYPHS = { walls = "\u{1F6E1}\u{FE0F}", guard = "\u{2694}\u{FE0F}", heal = "\u{26D1}\u{FE0F}", homes = "\u{1F3E0}" }

local w = {}
local pop = {}
local cells = {} -- [territory id] = map hex widgets
local selected = "" -- territory open in the window
local tab = "overview"
local stationing = false -- the garrison column shows your warband to pick from
local latest = nil
local surrenderArmed = 0
local tierShown = nil -- region the map is zoomed to (nil = whole realm)
local onlyMine = false

-- Honeycomb geometry (flat-topped hexes, odd columns half a hex lower).
local SIDE = 96
local HEX_W, HEX_H = 2 * SIDE, math.sqrt(3) * SIDE
local STEP_X, STEP_Y = 1.5 * SIDE, HEX_H
local PAD = 50
local CANVAS_W = PAD * 2 + (SocialConfig.MapColumns - 1) * STEP_X + HEX_W
local CANVAS_H = PAD * 2 + SocialConfig.MapRows * STEP_Y + HEX_H / 2
local camera = { x = CANVAS_W / 2, y = CANVAS_H / 2, zoom = 0.5 }
local goal = { x = CANVAS_W / 2, y = CANVAS_H / 2, zoom = 0.5 }
local drag = { on = false, moved = false, from = Vector2.zero, start = Vector2.zero }

local function hexCenter(column: number, row: number): Vector2
	return Vector2.new(PAD + SIDE + column * STEP_X, PAD + HEX_H / 2 + row * STEP_Y + (if column % 2 == 1 then HEX_H / 2 else 0))
end

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
	return `{pct(territory.amount)} {SocialConfig.BonusNames[territory.bonus] or territory.bonus}`
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

local function hms(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d:%02d", seconds // 3600, seconds % 3600 // 60, seconds % 60)
end

-- A label with the usual settings.
local function text(ui, parent: Instance, size: UDim2, position: UDim2, color: Color3, textSize: number, font: Enum.Font?): TextLabel
	local label = ui.makeText(parent, size, position, color, textSize)
	label.Font = font or Enum.Font.GothamBlack
	label.RichText = true
	return label
end

-- A dark button with a gold outline (Idle Mafia style).
local function outlineButton(ui, parent: Instance, size: UDim2, position: UDim2, color: Color3?): TextButton
	local button = ui.makeButton(parent, size, position, DARK)
	button.Font = Enum.Font.GothamBlack
	button.TextSize = 13
	button.TextColor3 = color or GOLD
	for _, child in button:GetChildren() do
		if child:IsA("UIStroke") then
			child:Destroy()
		end
	end
	ui.art.stroke(button, color or GOLD, 2, 0)
	return button
end

local function setOutline(button: TextButton, label: string, usable: boolean, color: Color3?)
	button.Text = label
	local tint = if usable then (color or GOLD) else Color3.fromRGB(110, 104, 96)
	button.TextColor3 = tint
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = tint
	end
	button.AutoButtonColor = usable
end

local function dark(ui, parent: Instance, size: UDim2, position: UDim2, color: Color3?): Frame
	local frame = ui.makeFrame(parent, size, position, color or PANEL)
	ui.addCorner(frame, 6)
	return frame
end

---------------------------------------------------------------------------
-- The map
---------------------------------------------------------------------------

local function openTerritory(ui, territory)
	selected = territory.id
	tab = "overview"
	stationing = false
	surrenderArmed = 0
	ui.send("RealmView", territory.id)
	ui.openModal("Territory", territory.name)
end

local function fitZoom(): number
	local size = w.board.AbsoluteSize
	if size.X <= 0 then
		return 0.5
	end
	return math.min(size.X / CANVAS_W, size.Y / CANVAS_H)
end

local function clampGoal()
	goal.zoom = math.clamp(goal.zoom, fitZoom(), 1.6)
	goal.x = math.clamp(goal.x, 0, CANVAS_W)
	goal.y = math.clamp(goal.y, 0, CANVAS_H)
end

local function resetView()
	goal.x, goal.y = CANVAS_W / 2, CANVAS_H / 2
	goal.zoom = fitZoom()
end

local function focusOn(point: Vector2, zoom: number)
	goal.x, goal.y = point.X, point.Y
	goal.zoom = zoom
	clampGoal()
end

local function regionCenter(tier: number): Vector2
	local sum, count = Vector2.zero, 0
	for _, territory in SocialConfig.Territories do
		if territory.tier == tier then
			sum += hexCenter(territory.column, territory.row)
			count += 1
		end
	end
	return sum / math.max(1, count)
end

local function showTier(ui, tier: number?)
	tierShown = tier
	if tier then
		focusOn(regionCenter(tier), 0.9)
	else
		resetView()
	end
	ui.redraw()
end

-- A regular flat-topped hexagon: three turned rectangles. Returns them.
local function hexagon(ui, parent: Instance, center: Vector2, side: number, color: Color3, z: number)
	local parts = {}
	for index, rotation in { 0, 60, 120 } do
		local frame = ui.makeFrame(parent, UDim2.fromOffset(side, side * math.sqrt(3)), UDim2.fromOffset(center.X - side / 2, center.Y - side * math.sqrt(3) / 2), color)
		frame.Rotation = rotation
		frame.ZIndex = z
		parts[index] = frame
	end
	return parts
end

local function paint(parts, color: Color3, transparency: number?)
	for _, frame in parts do
		frame.BackgroundColor3 = color
		frame.BackgroundTransparency = transparency or 0
	end
end

-- Little buildings spread around the hex, away from the labels.
local SPOTS = { { -0.62, -0.42 }, { -0.12, -0.62 }, { 0.42, -0.5 }, { 0.66, 0.02 }, { -0.66, 0.12 }, { -0.36, 0.56 }, { 0.28, 0.6 } }

local function buildHex(ui, canvas: Frame, territory)
	local center = hexCenter(territory.column, territory.row)
	local edge = hexagon(ui, canvas, center, SIDE, Color3.new(1, 1, 1), 20)
	local fill = hexagon(ui, canvas, center, SIDE - 5, PARCHMENT, 21)
	for index, spot in SPOTS do
		Landmarks.mini(canvas, territory.tier, center.X + spot[1] * SIDE, center.Y + spot[2] * SIDE * 0.86, 22 + (index % 3) * 3, 24, territory.number + index)
	end
	local name = text(ui, canvas, UDim2.fromOffset(HEX_W - 30, 24), UDim2.fromOffset(center.X - HEX_W / 2 + 15, center.Y - 22), Color3.new(1, 1, 1), 16, ui.art.Fonts.heading)
	name.TextXAlignment = Enum.TextXAlignment.Center
	name.TextStrokeTransparency = 0.15
	name.Text = `{territory.name} <font size="12" color="#F0C450">{territory.number}</font>`
	name.ZIndex = 60
	local owner = text(ui, canvas, UDim2.fromOffset(HEX_W - 40, 18), UDim2.fromOffset(center.X - HEX_W / 2 + 20, center.Y + 3), Color3.new(1, 1, 1), 12)
	owner.TextXAlignment = Enum.TextXAlignment.Center
	owner.TextStrokeTransparency = 0.25
	owner.TextTruncate = Enum.TextTruncate.AtEnd
	owner.ZIndex = 60
	local flags = text(ui, canvas, UDim2.fromOffset(HEX_W - 40, 22), UDim2.fromOffset(center.X - HEX_W / 2 + 20, center.Y + 24), Color3.new(1, 1, 1), 16)
	flags.TextXAlignment = Enum.TextXAlignment.Center
	flags.ZIndex = 60
	-- the press area: round, so neighbouring hexes don't steal presses
	local press = ui.makeButton(canvas, UDim2.fromOffset(HEX_H * 0.95, HEX_H * 0.95), UDim2.fromOffset(center.X - HEX_H * 0.475, center.Y - HEX_H * 0.475), Color3.new(1, 1, 1))
	press.BackgroundTransparency = 1
	press.AutoButtonColor = false
	press:SetAttribute("NoGlow", true)
	press.Text = ""
	press.ZIndex = 70
	ui.addCorner(press, 999)
	press.MouseEnter:Connect(function()
		paint(edge, GOLD)
	end)
	press.MouseLeave:Connect(function()
		local part = cells[territory.id]
		paint(edge, part.edgeColor or Color3.new(1, 1, 1))
	end)
	press.Activated:Connect(function()
		if drag.moved then
			return -- that press was a drag of the map
		end
		openTerritory(ui, territory)
	end)
	cells[territory.id] = { edge = edge, fill = fill, owner = owner, flags = flags, name = name, territory = territory, center = center }
end

local function buildMap(ui, page: Instance)
	local board = ui.makeFrame(page, UDim2.new(1, -10, 0, 600), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1))
	board.LayoutOrder = 3
	board.ClipsDescendants = true
	board.Active = true
	ui.addCorner(board, 6)
	ui.art.stroke(board, LINE, 2, 0)
	w.board = board
	local sea = Instance.new("UIGradient")
	sea.Rotation = 90
	sea.Color = ColorSequence.new(Color3.fromRGB(60, 100, 120), Color3.fromRGB(30, 54, 70))
	sea.Parent = board
	local canvas = ui.makeFrame(board, UDim2.fromOffset(CANVAS_W, CANVAS_H), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	canvas.BackgroundTransparency = 1
	canvas.ZIndex = 2
	w.canvas = canvas
	w.canvasScale = Instance.new("UIScale")
	w.canvasScale.Parent = canvas
	for _, territory in SocialConfig.Territories do
		buildHex(ui, canvas, territory)
	end
	-- region names over each region
	w.regionLabels = {}
	for tier, info in SocialConfig.Tiers do
		local at = regionCenter(tier)
		local label = text(ui, canvas, UDim2.fromOffset(420, 40), UDim2.fromOffset(at.X - 210, at.Y - 20), Color3.new(1, 1, 1), 30, ui.art.Fonts.title)
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextTransparency = 0.45
		label.TextStrokeTransparency = 0.6
		label.Text = string.upper(info.name)
		label.ZIndex = 50
		w.regionLabels[tier] = label
	end

	-- region selector, bottom left
	local selector = ui.makeFrame(board, UDim2.fromOffset(380, 66), UDim2.new(0, 12, 1, -78), DARK)
	selector.ZIndex = 600
	ui.addCorner(selector, 4)
	local left = outlineButton(ui, selector, UDim2.fromOffset(64, 58), UDim2.fromOffset(4, 4))
	left.Text = "\u{2B05}"
	left.TextSize = 26
	left.ZIndex = 601
	local middle = outlineButton(ui, selector, UDim2.fromOffset(232, 58), UDim2.fromOffset(74, 4))
	middle.Text = ""
	middle.ZIndex = 601
	local flag = text(ui, middle, UDim2.fromOffset(36, 58), UDim2.fromOffset(8, 0), Color3.new(1, 1, 1), 22)
	flag.Text = "\u{1F6A9}"
	flag.ZIndex = 602
	w.regionName = text(ui, middle, UDim2.new(1, -50, 0, 30), UDim2.fromOffset(44, 4), GOLD, 22, ui.art.Fonts.title)
	w.regionName.TextXAlignment = Enum.TextXAlignment.Center
	w.regionName.TextScaled = true
	w.regionName.ZIndex = 602
	w.regionTier = text(ui, middle, UDim2.new(1, -50, 0, 18), UDim2.fromOffset(44, 34), Color3.fromRGB(200, 190, 170), 12)
	w.regionTier.TextXAlignment = Enum.TextXAlignment.Center
	w.regionTier.ZIndex = 602
	local right = outlineButton(ui, selector, UDim2.fromOffset(64, 58), UDim2.fromOffset(312, 4))
	right.Text = "\u{27A1}"
	right.TextSize = 26
	right.ZIndex = 601
	left.Activated:Connect(function()
		showTier(ui, math.clamp((tierShown or (#SocialConfig.Tiers + 1)) - 1, 1, #SocialConfig.Tiers))
	end)
	right.Activated:Connect(function()
		showTier(ui, math.clamp((tierShown or 0) + 1, 1, #SocialConfig.Tiers))
	end)
	middle.Activated:Connect(function()
		showTier(ui, nil)
	end)

	-- zoom, bottom right
	local zoomBar = ui.makeFrame(board, UDim2.fromOffset(250, 52), UDim2.new(1, -262, 1, -64), DARK)
	zoomBar.ZIndex = 600
	ui.addCorner(zoomBar, 4)
	local minus = outlineButton(ui, zoomBar, UDim2.fromOffset(44, 44), UDim2.fromOffset(4, 4), Color3.new(1, 1, 1))
	minus.Text = "\u{2212}"
	minus.TextSize = 24
	minus.ZIndex = 601
	local reset = outlineButton(ui, zoomBar, UDim2.fromOffset(146, 44), UDim2.fromOffset(52, 4), Color3.new(1, 1, 1))
	reset.Text = "RESET ZOOM"
	reset.TextSize = 16
	reset.ZIndex = 601
	local plus = outlineButton(ui, zoomBar, UDim2.fromOffset(44, 44), UDim2.fromOffset(202, 4), Color3.new(1, 1, 1))
	plus.Text = "+"
	plus.TextSize = 24
	plus.ZIndex = 601
	minus.Activated:Connect(function()
		goal.zoom /= 1.3
		clampGoal()
	end)
	plus.Activated:Connect(function()
		goal.zoom *= 1.3
		clampGoal()
	end)
	reset.Activated:Connect(function()
		showTier(ui, nil)
	end)

	-- drag, wheel and the smooth camera
	local function inside(position: Vector3): boolean
		if not page.Visible or ui.isOpen("Territory") or ui.isOpen("RealmBonuses") or ui.isOpen("RealmList") then
			return false
		end
		local at, size = board.AbsolutePosition, board.AbsoluteSize
		return position.X >= at.X and position.X <= at.X + size.X and position.Y >= at.Y and position.Y <= at.Y + size.Y
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
		w.canvasScale.Scale = camera.zoom
		canvas.Position = UDim2.new(0.5, -camera.x * camera.zoom, 0.5, -camera.y * camera.zoom)
	end)
	board:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if tierShown then
			focusOn(regionCenter(tierShown), 0.9)
		else
			resetView()
		end
	end)
	resetView()
	camera.x, camera.y, camera.zoom = goal.x, goal.y, goal.zoom
end

local function drawMap(state)
	local realm = state.realm
	local guildId = realm.guildId or ""
	for id, part in cells do
		local info = realm.lands[id] or {}
		local holder = info.holder
		local mine = holder ~= nil and guildId ~= "" and holder.id == guildId
		local land = SocialConfig.Tiers[part.territory.tier].land
		local color = if holder then guildColor(holder.id):Lerp(land, 0.3) else land:Lerp(PARCHMENT, 0.45)
		local dim = onlyMine and not mine
		paint(part.fill, color, if dim then 0.65 else 0)
		part.edgeColor = if mine then GOLD else color:Lerp(Color3.new(1, 1, 1), 0.55)
		paint(part.edge, part.edgeColor, if dim then 0.65 else 0)
		part.owner.Text = if holder then `<font color="#{guildColor(holder.id):Lerp(Color3.new(1, 1, 1), 0.3):ToHex()}">\u{25A0}</font> {holder.name}` else "<i>unclaimed</i>"
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
	end
	for tier, label in w.regionLabels do
		label.TextTransparency = if tierShown == nil or tierShown == tier then 0.35 else 0.7
	end
	if tierShown then
		local info = SocialConfig.Tiers[tierShown]
		w.regionName.Text = string.upper(info.name)
		w.regionTier.Text = `TIER {tierShown}  \u{2022}  LEVEL {info.level}+`
	else
		w.regionName.Text = "THE REALM"
		w.regionTier.Text = `ALL {#SocialConfig.Tiers} TIERS`
	end
end

---------------------------------------------------------------------------
-- The Territory window
---------------------------------------------------------------------------

local TABS = { { "overview", "OVERVIEW" }, { "attack", "ATTACK" }, { "siege", "SIEGE" }, { "residents", "RESIDENTS" }, { "fortify", "FORTIFY" } }
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

local function column(ui, parent: Instance, x: number, width: number): Frame
	local frame = ui.makeFrame(parent, UDim2.new(width, -6, 0, 0), UDim2.new(x, if x > 0 then 6 else 0, 0, 0), Color3.new(0, 0, 0))
	frame.BackgroundTransparency = 1
	frame.AutomaticSize = Enum.AutomaticSize.Y
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame
	return frame
end

-- A panel with a small caps title and a big line (left column cards).
local function block(ui, parent: Instance, order: number, height: number, title: string)
	local frame = dark(ui, parent, UDim2.new(1, 0, 0, height), UDim2.fromOffset(0, 0))
	frame.LayoutOrder = order
	local head = text(ui, frame, UDim2.new(1, -24, 0, 22), UDim2.fromOffset(14, 8), Color3.fromRGB(200, 190, 175), 15)
	head.Text = title
	local big = text(ui, frame, UDim2.new(1, -24, 0, 36), UDim2.fromOffset(14, 32), Color3.new(1, 1, 1), 28, Enum.Font.Gotham)
	local note = text(ui, frame, UDim2.new(1, -24, 0, 34), UDim2.fromOffset(14, 70), Color3.fromRGB(170, 160, 145), 13, Enum.Font.GothamMedium)
	note.TextYAlignment = Enum.TextYAlignment.Top
	return { frame = frame, head = head, big = big, note = note }
end

local function listRow(ui, parent: Instance, order: number, height: number, withButton: boolean)
	local row = dark(ui, parent, UDim2.new(1, 0, 0, height), UDim2.fromOffset(0, 0), Color3.fromRGB(44, 38, 30))
	row.LayoutOrder = order
	local label = text(ui, row, UDim2.new(1, if withButton then -150 else -24, 1, 0), UDim2.fromOffset(12, 0), Color3.new(1, 1, 1), 14, Enum.Font.GothamBold)
	label.TextTruncate = Enum.TextTruncate.AtEnd
	local button = nil
	if withButton then
		button = outlineButton(ui, row, UDim2.new(0, 122, 1, -12), UDim2.new(1, -130, 0, 6), Color3.new(1, 1, 1))
		button.TextSize = 16
	end
	return { row = row, text = label, button = button }
end

local function buildPopup(ui)
	local page = ui.pages.Territory

	-- header: picture, "REGION  TIER n  HELD BY ...", SURRENDER / MARK FOR DEFENSE
	local header = ui.makeFrame(page, UDim2.new(1, -10, 0, 96), UDim2.fromOffset(0, 0), DARK)
	header.LayoutOrder = 1
	ui.addCorner(header, 6)
	pop.header = header
	local picture = dark(ui, header, UDim2.fromOffset(124, 84), UDim2.fromOffset(6, 6), Color3.new(1, 1, 1))
	picture.ClipsDescendants = true
	pop.pictureGradient = Instance.new("UIGradient")
	pop.pictureGradient.Rotation = 90
	pop.pictureGradient.Parent = picture
	pop.picture = ui.makeFrame(picture, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	pop.picture.BackgroundTransparency = 1
	pop.picture.ZIndex = 400
	pop.region = text(ui, header, UDim2.new(1, -520, 0, 34), UDim2.fromOffset(144, 10), Color3.fromRGB(200, 196, 190), 26)
	pop.held = text(ui, header, UDim2.new(1, -520, 0, 26), UDim2.fromOffset(144, 48), Color3.fromRGB(200, 196, 190), 18)
	pop.flags = text(ui, header, UDim2.new(1, -520, 0, 18), UDim2.fromOffset(144, 74), Color3.fromRGB(255, 220, 190), 12, Enum.Font.GothamBold)
	pop.surrender = outlineButton(ui, header, UDim2.fromOffset(170, 40), UDim2.new(1, -360, 0, 10), Kit.RED)
	pop.surrender.TextSize = 16
	pop.mark = outlineButton(ui, header, UDim2.fromOffset(180, 40), UDim2.new(1, -184, 0, 10))
	pop.mark.TextSize = 14
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

	-- tabs: words with a gold underline under the open one
	local tabRow = ui.makeFrame(page, UDim2.new(1, -10, 0, 42), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	tabRow.BackgroundTransparency = 1
	tabRow.LayoutOrder = 2
	local rule = ui.makeFrame(tabRow, UDim2.new(1, 0, 0, 2), UDim2.new(0, 0, 1, -2), LINE)
	rule.ZIndex = 2
	pop.tabs = {}
	for index, entry in TABS do
		local button = ui.makeButton(tabRow, UDim2.fromOffset(150, 40), UDim2.fromOffset((index - 1) * 158, 0), DARK)
		button.BackgroundTransparency = 1
		button.Font = Enum.Font.GothamBlack
		button.TextSize = 18
		button.Text = entry[2]
		button:SetAttribute("NoGlow", true)
		local underline = ui.makeFrame(button, UDim2.new(0.8, 0, 0, 4), UDim2.new(0.1, 0, 1, -4), GOLD)
		underline.ZIndex = 3
		button.Activated:Connect(function()
			tab = entry[1]
			stationing = false
			ui.redraw()
		end)
		pop.tabs[entry[1]] = { button = button, underline = underline }
	end
	pop.bodies = {}

	-- OVERVIEW: bonus, stipend, strength | garrison
	local overview = ui.makeFrame(page, UDim2.new(1, -10, 0, 0), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	overview.BackgroundTransparency = 1
	overview.AutomaticSize = Enum.AutomaticSize.Y
	overview.LayoutOrder = 3
	pop.bodies.overview = overview
	local leftColumn = column(ui, overview, 0, 0.47)
	local rightColumn = column(ui, overview, 0.47, 0.53)
	pop.bonus = block(ui, leftColumn, 1, 116, "TERRITORY BONUS")
	pop.active = text(ui, pop.bonus.frame, UDim2.fromOffset(190, 22), UDim2.new(1, -200, 0, 8), Color3.fromRGB(110, 210, 110), 12)
	pop.active.BackgroundTransparency = 0
	pop.active.BackgroundColor3 = Color3.fromRGB(40, 70, 40)
	pop.active.TextXAlignment = Enum.TextXAlignment.Center
	ui.addCorner(pop.active, 3)
	pop.stipend = block(ui, leftColumn, 2, 116, "STIPEND, EVERY 2 HOURS")
	pop.strength = block(ui, leftColumn, 3, 106, "TERRITORY STRENGTH")
	pop.strength.big.Visible = false
	pop.strengthBar = Kit.bar(ui, pop.strength.frame, UDim2.new(1, -28, 0, 34), UDim2.fromOffset(14, 34), Color3.fromRGB(190, 80, 70))
	pop.strengthBar.text.TextSize = 18
	pop.strength.note.Position = UDim2.fromOffset(14, 74)
	pop.historyButton = outlineButton(ui, leftColumn, UDim2.new(1, 0, 0, 40), UDim2.fromOffset(0, 0))
	pop.historyButton.LayoutOrder = 4
	pop.historyButton.TextSize = 16
	pop.historyButton.Text = "\u{1F4DC} HISTORY"
	pop.historyButton.Activated:Connect(function()
		tab = "history"
		ui.redraw()
	end)

	local garrisonHead = ui.makeFrame(rightColumn, UDim2.new(1, 0, 0, 48), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	garrisonHead.BackgroundTransparency = 1
	garrisonHead.LayoutOrder = 1
	pop.garrisonTitle = text(ui, garrisonHead, UDim2.new(1, -200, 1, 0), UDim2.fromOffset(4, 0), Color3.new(1, 1, 1), 20)
	pop.stationButton = outlineButton(ui, garrisonHead, UDim2.fromOffset(190, 40), UDim2.new(1, -190, 0, 4))
	pop.stationButton.TextSize = 15
	pop.stationButton.Activated:Connect(function()
		stationing = not stationing
		ui.redraw()
	end)
	pop.garrisonEmpty = text(ui, rightColumn, UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 0), Color3.fromRGB(180, 172, 160), 17, Enum.Font.GothamMedium)
	pop.garrisonEmpty.LayoutOrder = 2
	pop.mineRows = {}
	for index = 1, ROWS do
		local row = listRow(ui, rightColumn, 2 + index, 64, true)
		row.button.Text = "RECALL"
		row.button.Activated:Connect(function()
			local stationIndex = row.row:GetAttribute("Index")
			if stationIndex then
				ui.send("RealmRecall", `{selected}:{stationIndex}`)
			end
		end)
		pop.mineRows[index] = row
	end
	pop.otherRows = {}
	for index = 1, 12 do
		pop.otherRows[index] = listRow(ui, rightColumn, 30 + index, 48, false)
	end
	pop.crewRows = {}
	for index = 1, ROWS do
		local row = listRow(ui, rightColumn, 50 + index, 56, true)
		row.button.Text = "STATION"
		row.button.Activated:Connect(function()
			local slot = row.row:GetAttribute("Slot")
			if slot then
				Kit.pop(row.row, 1.04)
				ui.send("RealmStation", `{selected}:{slot}`)
			end
		end)
		pop.crewRows[index] = row
	end
	pop.recallAll = outlineButton(ui, rightColumn, UDim2.new(1, 0, 0, 60), UDim2.fromOffset(0, 0))
	pop.recallAll.LayoutOrder = 90
	pop.recallAll.TextSize = 26
	pop.recallAll.Font = ui.art.Fonts.heading
	pop.recallAll.Activated:Connect(function()
		ui.send("RealmRecall", `{selected}:all`)
	end)

	-- ATTACK and SIEGE
	local function fightBody(order: number, key: string)
		local frame = body(ui, page, order)
		pop.bodies[key] = frame
		local card = dark(ui, frame, UDim2.new(1, 0, 0, 250), UDim2.fromOffset(0, 0))
		card.LayoutOrder = 1
		local head = text(ui, card, UDim2.new(1, -28, 0, 24), UDim2.fromOffset(14, 12), Color3.fromRGB(200, 190, 175), 16)
		local big = text(ui, card, UDim2.new(1, -28, 0, 40), UDim2.fromOffset(14, 40), Color3.new(1, 1, 1), 30, Enum.Font.Gotham)
		local bar = Kit.bar(ui, card, UDim2.new(1, -28, 0, 34), UDim2.fromOffset(14, 88), Color3.fromRGB(190, 80, 70))
		bar.text.TextSize = 18
		local note = text(ui, card, UDim2.new(1, -28, 0, 56), UDim2.fromOffset(14, 128), Color3.fromRGB(180, 170, 155), 15, Enum.Font.GothamMedium)
		note.TextYAlignment = Enum.TextYAlignment.Top
		local button = outlineButton(ui, card, UDim2.new(1, -28, 0, 52), UDim2.new(0, 14, 1, -64), Kit.RED)
		button.TextSize = 22
		return { card = card, head = head, big = big, bar = bar, note = note, button = button }
	end
	pop.attack = fightBody(4, "attack")
	pop.attack.button.Activated:Connect(function()
		local land = latest and latest.realm.lands[selected]
		if land and not land.holder then
			ui.send("RealmClaim", selected)
		else
			Kit.pop(pop.header, 1.03)
			ui.send("RealmAttack", `{selected}:attack`)
		end
	end)
	pop.siege = fightBody(5, "siege")
	pop.siege.button.Activated:Connect(function()
		Kit.pop(pop.header, 1.06)
		ui.send("RealmAttack", `{selected}:siege`)
	end)

	-- RESIDENTS
	local residents = body(ui, page, 6)
	pop.bodies.residents = residents
	pop.residentCard = block(ui, residents, 1, 150, "RESIDENTS")
	pop.liveButton = outlineButton(ui, pop.residentCard.frame, UDim2.fromOffset(240, 44), UDim2.new(1, -254, 0, 14), Kit.GREEN)
	pop.liveButton.TextSize = 16
	pop.liveButton.Activated:Connect(function()
		if latest and latest.realm.home == selected then
			ui.send("RealmLive", "")
		else
			ui.send("RealmLive", selected)
		end
	end)
	pop.residentCard.note.Size = UDim2.new(1, -28, 0, 70)
	pop.residentNames = text(ui, residents, UDim2.new(1, 0, 0, 0), UDim2.fromOffset(0, 0), Color3.fromRGB(180, 170, 155), 14, Enum.Font.GothamMedium)
	pop.residentNames.AutomaticSize = Enum.AutomaticSize.Y
	pop.residentNames.LayoutOrder = 2

	local rules = dark(ui, residents, UDim2.new(1, 0, 0, 170), UDim2.fromOffset(0, 0))
	rules.LayoutOrder = 3
	pop.rules = rules
	local rulesTitle = text(ui, rules, UDim2.new(1, -20, 0, 22), UDim2.fromOffset(14, 8), GOLD, 15)
	rulesTitle.Text = "RESIDENCY RULES  \u{2022}  your guild sets these"
	local function sendRules(mode: string?, level: number?, rent: number?)
		local land = latest and latest.realm.lands[selected]
		local policy = land and land.policy or { mode = "open", level = 0, rent = 0 }
		ui.send("RealmPolicy", `{selected}:{mode or policy.mode}:{math.max(0, level or policy.level or 0)}:{math.max(0, rent or policy.rent or 0)}`)
	end
	pop.modes = {}
	for index, entry in { { "open", "OPEN TO ALL" }, { "apply", "BY APPLICATION" }, { "closed", "CLOSED" } } do
		local button = outlineButton(ui, rules, UDim2.new(1 / 3, -14, 0, 38), UDim2.new((index - 1) / 3, 10, 0, 36))
		button.TextSize = 14
		button.Text = entry[2]
		button.Activated:Connect(function()
			sendRules(entry[1], nil, nil)
		end)
		pop.modes[entry[1]] = button
	end
	local function stepper(y: number, onStep): TextLabel
		local label = text(ui, rules, UDim2.new(1, -140, 0, 36), UDim2.fromOffset(14, y), Color3.new(1, 1, 1), 15, Enum.Font.GothamBold)
		local minusButton = outlineButton(ui, rules, UDim2.fromOffset(48, 36), UDim2.new(1, -114, 0, y), Color3.new(1, 1, 1))
		minusButton.Text = "\u{2212}"
		minusButton.TextSize = 22
		minusButton.Activated:Connect(function()
			onStep(-1)
		end)
		local plusButton = outlineButton(ui, rules, UDim2.fromOffset(48, 36), UDim2.new(1, -60, 0, y), Color3.new(1, 1, 1))
		plusButton.Text = "+"
		plusButton.TextSize = 22
		plusButton.Activated:Connect(function()
			onStep(1)
		end)
		return label
	end
	pop.levelRule = stepper(82, function(step: number)
		local land = latest and latest.realm.lands[selected]
		local level = land and land.policy and land.policy.level or 0
		sendRules(nil, math.clamp(level + step * 5, 0, SocialConfig.ResidentLevelMax), nil)
	end)
	pop.rentRule = stepper(124, function(step: number)
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
		sendRules(nil, nil, math.floor(most * steps[math.clamp(at + step, 1, #steps)]))
	end)
	pop.applicantsTitle = text(ui, residents, UDim2.new(1, 0, 0, 26), UDim2.fromOffset(0, 0), GOLD, 18, ui.art.Fonts.heading)
	pop.applicantsTitle.LayoutOrder = 4
	pop.applicantRows = {}
	for index = 1, SocialConfig.ApplicantsKept do
		local row = listRow(ui, residents, 4 + index, 44, true)
		row.button.Size = UDim2.new(0, 110, 1, -12)
		row.button.Position = UDim2.new(1, -236, 0, 6)
		row.button.TextSize = 13
		setOutline(row.button, "ACCEPT", true, Kit.GREEN)
		local no = outlineButton(ui, row.row, UDim2.new(0, 110, 1, -12), UDim2.new(1, -118, 0, 6), Kit.RED)
		no.TextSize = 13
		no.Text = "TURN DOWN"
		row.text.Size = UDim2.new(1, -260, 1, 0)
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
	local topLine = ui.makeFrame(fortify, UDim2.new(1, 0, 0, 44), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	topLine.BackgroundTransparency = 1
	topLine.LayoutOrder = 1
	local warning = text(ui, topLine, UDim2.new(1, -420, 1, 0), UDim2.fromOffset(4, 0), Color3.fromRGB(230, 110, 90), 15, Enum.Font.GothamBold)
	warning.Text = "Every fortification is lost if another guild captures this territory."
	pop.purse = text(ui, topLine, UDim2.fromOffset(240, 44), UDim2.new(1, -414, 0, 0), Color3.new(1, 1, 1), 22)
	pop.purse.TextXAlignment = Enum.TextXAlignment.Right
	local fortHistory = outlineButton(ui, topLine, UDim2.fromOffset(160, 44), UDim2.new(1, -160, 0, 0))
	fortHistory.TextSize = 18
	fortHistory.Text = "HISTORY"
	fortHistory.Activated:Connect(function()
		tab = "history"
		ui.redraw()
	end)
	local fortGrid = ui.makeFrame(fortify, UDim2.new(1, 0, 0, 0), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	fortGrid.BackgroundTransparency = 1
	fortGrid.AutomaticSize = Enum.AutomaticSize.Y
	fortGrid.LayoutOrder = 2
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0.5, -6, 0, 250)
	gridLayout.CellPadding = UDim2.fromOffset(12, 12)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = fortGrid
	pop.forts = {}
	for index, fort in SocialConfig.Forts do
		local card = dark(ui, fortGrid, UDim2.fromOffset(100, 100), UDim2.fromOffset(0, 0))
		card.LayoutOrder = index
		local scale = Instance.new("UIScale")
		scale.Name = "Pop"
		scale.Parent = card
		local picture = dark(ui, card, UDim2.fromOffset(110, 110), UDim2.fromOffset(12, 12), Color3.fromRGB(18, 16, 14))
		local glyph = text(ui, picture, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1), 60)
		glyph.TextXAlignment = Enum.TextXAlignment.Center
		glyph.Text = FORT_GLYPHS[fort.key]
		local name = text(ui, card, UDim2.new(1, -230, 0, 32), UDim2.fromOffset(134, 10), Color3.new(1, 1, 1), 26, ui.art.Fonts.heading)
		local pips = {}
		for pip = 1, SocialConfig.FortMax do
			pips[pip] = ui.makeFrame(card, UDim2.fromOffset(16, 16), UDim2.new(1, -106 + (pip - 1) * 19, 0, 16), Color3.fromRGB(60, 56, 52))
		end
		local nowHead = text(ui, card, UDim2.new(0.5, -80, 0, 18), UDim2.fromOffset(134, 46), Color3.fromRGB(170, 160, 145), 12)
		nowHead.Text = string.upper(fort.about)
		local nowValue = text(ui, card, UDim2.new(0.5, -80, 0, 26), UDim2.fromOffset(134, 64), Color3.new(1, 1, 1), 18, Enum.Font.GothamBold)
		local nextHead = text(ui, card, UDim2.new(0.5, -60, 0, 18), UDim2.new(0.5, 60, 0, 46), Color3.fromRGB(170, 160, 145), 12)
		local nextValue = text(ui, card, UDim2.new(0.5, -60, 0, 26), UDim2.new(0.5, 60, 0, 64), Color3.new(1, 1, 1), 18, Enum.Font.GothamBold)
		local goldLabel = text(ui, card, UDim2.new(1, -146, 0, 18), UDim2.fromOffset(134, 98), Color3.fromRGB(200, 190, 175), 13)
		local goldBar = Kit.bar(ui, card, UDim2.new(1, -146, 0, 8), UDim2.fromOffset(134, 118), GOLD)
		goldBar.text.Visible = false
		local energyLabel = text(ui, card, UDim2.new(1, -146, 0, 18), UDim2.fromOffset(134, 132), Color3.fromRGB(200, 190, 175), 13)
		local energyBar = Kit.bar(ui, card, UDim2.new(1, -146, 0, 8), UDim2.fromOffset(134, 152), Color3.fromRGB(230, 150, 60))
		energyBar.text.Visible = false
		local giveGold = outlineButton(ui, card, UDim2.new(0.5, -18, 0, 42), UDim2.new(0, 12, 1, -54))
		giveGold.TextSize = 13
		local giveEnergy = outlineButton(ui, card, UDim2.new(0.5, -18, 0, 42), UDim2.new(0.5, 6, 1, -54))
		giveEnergy.TextSize = 13
		local part = { card = card, name = name, pips = pips, nowValue = nowValue, nextHead = nextHead, nextValue = nextValue, goldLabel = goldLabel, goldBar = goldBar, energyLabel = energyLabel, energyBar = energyBar, giveGold = giveGold, giveEnergy = giveEnergy, gold = 0, energy = 0 }
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

	-- HISTORY
	local history = body(ui, page, 8)
	pop.bodies.history = history
	pop.historyRows = {}
	for index = 1, SocialConfig.HistoryKept do
		pop.historyRows[index] = listRow(ui, history, index, 40, false)
	end
	pop.noHistory = text(ui, history, UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 0), Color3.fromRGB(180, 170, 155), 16, Enum.Font.GothamMedium)
	pop.noHistory.LayoutOrder = 0
	pop.noHistory.Text = "Nothing has happened here yet."
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
		return `LEVEL {policy.level} NEEDED`, false
	elseif policy.mode == "apply" then
		return "\u{1F4DD} APPLY TO LIVE", true
	end
	return "\u{1F3E0} LIVE HERE", true
end

-- The effect of a fortification at a level, as text.
local function fortEffect(territory, key: string, level: number): string
	if key == "walls" then
		return `{Format.short(SocialConfig.maxStrength(territory.tier, level))} strength`
	elseif key == "guard" then
		return `x{1 + SocialConfig.Forts[2].per * level} soldier defense`
	elseif key == "heal" then
		return `{math.floor(SocialConfig.regenRate(level) * 100 + 0.5)}% an hour`
	end
	return `{math.floor(SocialConfig.residentShare(level) * 100 + 0.5)}% of the bonus`
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
	local inGuild = guildId ~= ""
	local mine = holder ~= nil and inGuild and holder.id == guildId
	local now = os.time()

	-- header
	pop.pictureGradient.Color = ColorSequence.new(tier.sky, tier.land:Lerp(Color3.new(0, 0, 0), 0.4))
	Landmarks.draw(pop.picture, territory.tier)
	pop.region.Text = `{string.upper(tier.name)}  <font color="#FFFFFF" size="20">TIER {territory.tier}</font>`
	if holder then
		local color = guildColor(holder.id):Lerp(Color3.new(1, 1, 1), 0.35):ToHex()
		pop.held.Text = `HELD BY  <font color="#{color}">\u{25A0} {string.upper(guildText(holder))}</font>{if mine then `  <font color="#F0C450">YOURS</font>` else ""}`
	else
		pop.held.Text = `<font color="#F0C450">UNCLAIMED</font>  \u{2022}  any guild can claim it`
	end
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
	if holder and (info.since or 0) > 0 then
		local held = string.gsub(ago(now - info.since), " ago", "")
		table.insert(flags, `held for {held}`)
	end
	pop.flags.Text = table.concat(flags, "   ")
	pop.surrender.Visible = mine and realm.officer
	setOutline(pop.surrender, if os.clock() - surrenderArmed < 4 then "PRESS AGAIN" else "SURRENDER", true, Kit.RED)
	pop.mark.Visible = mine and realm.officer
	setOutline(pop.mark, if info.marked then "UNMARK DEFENSE" else "MARK FOR DEFENSE", true)

	for key, entry in pop.tabs do
		local on = key == tab
		entry.button.TextColor3 = if on then Color3.new(1, 1, 1) else Color3.fromRGB(170, 160, 145)
		entry.underline.Visible = on
	end
	for key, frame in pop.bodies do
		frame.Visible = key == tab
	end

	-- OVERVIEW: left column
	local share = SocialConfig.residentShare(info.forts.homes or 0)
	pop.bonus.big.Text = `\u{1F4B0}  {bonusText(territory)}`
	pop.bonus.note.Text = `Residents receive {math.floor(share * 100 + 0.5)}% of this bonus.`
	pop.active.Visible = holder ~= nil
	pop.active.Text = if mine then "ACTIVE FOR YOUR GUILD" else "ACTIVE FOR HOLDER"
	local stipend = math.floor((realm.income or 0) * tier.stipendMinutes / 60)
	pop.stipend.big.Text = `<font color="{GREEN_TEXT}">\u{1F4B5}  {Format.short(stipend)}</font>`
	pop.stipend.note.Text = if mine then `\u{1F552}  Next payout in {hms(realm.stipendIn)}` else `{tier.stipendMinutes} minutes of income for each member of the holding guild.`
	if holder then
		Kit.setBar(pop.strengthBar, info.strength, info.max, `{Format.short(info.strength)} / {Format.short(info.max)}`)
		pop.strength.note.Text = `Regains {math.floor(info.regen * 100 + 0.5)}% strength per hour.`
	else
		Kit.setBar(pop.strengthBar, 0, 1, "UNCLAIMED")
		pop.strength.note.Text = "Nobody holds it. Claim it from the ATTACK tab."
	end

	-- OVERVIEW: garrison column
	pop.garrisonTitle.Text = `GARRISON {info.garrison} / {tier.garrison}   <font size="13" color="{GREEN_TEXT}">{pct(info.defense)} DEFENSE</font>`
	pop.stationButton.Visible = mine
	setOutline(pop.stationButton, if stationing then "BACK TO GARRISON" else "STATION SOLDIERS", true)
	local here, waiting = {}, 0
	for _, entry in realm.stationed do
		if entry.t == selected then
			table.insert(here, entry)
		elseif entry.t == "" then
			waiting += 1
		end
	end
	local players = view and view.garrison or {}
	local myId = ui.player.UserId
	local others = {}
	for _, entry in players do
		if entry.userId ~= myId then
			table.insert(others, entry)
		end
	end
	local showList = not stationing
	pop.garrisonEmpty.Visible = showList and #here == 0 and #others == 0
	pop.garrisonEmpty.Text = if holder then "Station your soldiers to defend this territory." else "Nobody holds it, so nobody guards it."
	for index, row in pop.mineRows do
		local entry = here[index]
		row.row.Visible = showList and entry ~= nil
		if entry then
			local color = GameConfig.getRarity(entry.rarity).color:ToHex()
			row.row:SetAttribute("Index", entry.index)
			row.text.Text = `<font color="#{color}">{entry.class} {entry.name}</font>\n<font color="#F0C450" size="12">YOU</font> <font color="#B2A690" size="13">@{ui.player.Name}</font>     \u{1F6E1}\u{FE0F} <font size="20">{Format.short(entry.defense)}</font>`
		end
	end
	for index, row in pop.otherRows do
		local entry = others[index]
		row.row.Visible = showList and entry ~= nil
		if entry then
			row.text.Text = `{entry.name}  <font color="#B2A690">{entry.count} soldier{if entry.count == 1 then "" else "s"}</font>     \u{1F6E1}\u{FE0F} {Format.short(entry.defense)}`
		end
	end
	local crew = {}
	if mine and stationing then
		for slot, soldier in state.crew or {} do
			if soldier then
				table.insert(crew, { slot = slot, soldier = soldier })
			end
		end
	end
	local full = info.garrison >= tier.garrison
	for index, row in pop.crewRows do
		local entry = crew[index]
		row.row.Visible = entry ~= nil
		if entry then
			local soldier = entry.soldier
			local color = GameConfig.getRarity(soldier.rarity).color:ToHex()
			row.row:SetAttribute("Slot", entry.slot)
			row.text.Text = `<font color="#{color}">{soldier.rarity} {soldier.class} {soldier.name}</font>     \u{1F6E1}\u{FE0F} {Format.short(soldier.defense or 0)}`
			setOutline(row.button, if full then "FULL" else "STATION", not full, Kit.GREEN)
		end
	end
	if stationing and #crew == 0 then
		pop.garrisonEmpty.Visible = true
		pop.garrisonEmpty.Text = "Your warband is empty. Recruit soldiers first."
	end
	pop.recallAll.Visible = showList and #here > 0
	pop.recallAll.Text = if waiting > 0 then `RECALL MY SOLDIERS ({#here})  \u{2022}  {waiting} WAITING` else `RECALL MY SOLDIERS ({#here})`

	-- ATTACK (or CLAIM) and SIEGE
	local levelOk = state.level >= tier.level
	local wounded = (state.health or 0) < GameConfig.MinHealthToFight
	local damageCut = 1 / (1 + (info.defense or 0))
	local attack, siege = pop.attack, pop.siege
	if holder == nil then
		attack.head.Text = "CLAIM THIS TERRITORY"
		attack.big.Text = `Claim for <font color="#F0C450">{Format.short(tier.claim)}</font> gold`
		attack.bar.back.Visible = false
		attack.note.Text = `No fight and no level needed. Your guild holds {realm.held} of its {realm.maxHeld} (2 + guild level). Holders get {bonusText(territory)} and a stipend every 2 hours.`
		local label = if not inGuild then "JOIN A GUILD FIRST" elseif realm.held >= realm.maxHeld then "YOUR GUILD IS AT ITS LIMIT" else "\u{1F6A9} CLAIM"
		setOutline(attack.button, label, inGuild and realm.held < realm.maxHeld and state.gold >= tier.claim, GOLD)
	elseif mine then
		attack.head.Text = "YOUR GUILD HOLDS THIS"
		attack.big.Text = "Defend it"
		attack.bar.back.Visible = true
		Kit.setBar(attack.bar, info.strength, info.max, `{Format.short(info.strength)} / {Format.short(info.max)}`)
		attack.note.Text = "Station soldiers in the garrison and build the fortifications so it is harder to take."
		setOutline(attack.button, "YOURS", false)
	else
		attack.head.Text = `ATTACK  \u{2022}  {SocialConfig.AttackStamina} STAMINA  \u{2022}  YOU HAVE {math.floor(state.stamina)}`
		attack.big.Text = `~{Format.short(math.floor(realm.attackDamage * damageCut))} damage a hit`
		attack.bar.back.Visible = true
		Kit.setBar(attack.bar, info.strength, info.max, `{Format.short(info.strength)} / {Format.short(info.max)}`)
		attack.note.Text = `Garrison of {info.garrison}: {pct(info.defense)} defense cuts your damage. Bring the strength to 0 and the guild that did the most damage takes it.`
		local label = if not inGuild then "JOIN A GUILD FIRST" elseif not levelOk then `LEVEL {tier.level} NEEDED` elseif wounded then "TOO WOUNDED" else "\u{2694}\u{FE0F} ATTACK"
		setOutline(attack.button, label, inGuild and levelOk and not wounded and state.stamina >= SocialConfig.AttackStamina, Kit.RED)
	end
	siege.bar.back.Visible = holder ~= nil
	if holder then
		Kit.setBar(siege.bar, info.strength, info.max, `{Format.short(info.strength)} / {Format.short(info.max)}`)
	end
	if holder == nil then
		siege.head.Text = "SIEGE"
		siege.big.Text = "Nothing to siege"
		siege.note.Text = "Nobody holds this territory. Claim it from the ATTACK tab instead."
		setOutline(siege.button, "UNCLAIMED", false)
	elseif mine then
		siege.head.Text = "SIEGE"
		siege.big.Text = "Your guild holds this"
		siege.note.Text = "Sieges are for territories other guilds hold."
		setOutline(siege.button, "YOURS", false)
	else
		siege.head.Text = `SIEGE  \u{2022}  {SocialConfig.SiegeEnergy} ENERGY  \u{2022}  YOU HAVE {math.floor(state.energy)}`
		siege.big.Text = `~{Format.short(math.floor(realm.siegeDamage * damageCut))} damage a siege`
		siege.note.Text = `A siege costs energy instead of stamina and hits about {math.floor(SocialConfig.SiegePower / SocialConfig.AttackPower + 0.5)} times as hard as an attack.`
		local label = if not inGuild then "JOIN A GUILD FIRST" elseif not levelOk then `LEVEL {tier.level} NEEDED` elseif wounded then "TOO WOUNDED" else "\u{1F40F} SIEGE"
		setOutline(siege.button, label, inGuild and levelOk and not wounded and state.energy >= SocialConfig.SiegeEnergy, Color3.fromRGB(230, 150, 60))
	end

	-- RESIDENTS
	local policy = info.policy or { mode = "open", level = 0, rent = 0 }
	local liveLabel, liveUsable = liveButton(state, realm, info)
	setOutline(pop.liveButton, liveLabel, liveUsable, Kit.GREEN)
	pop.residentCard.big.Text = `{info.residents} / {SocialConfig.ResidentsMax} live here`
	local homeLand = SocialConfig.TerritoryById[realm.home]
	local modeText = ({ open = "open to all", apply = "by application", closed = "closed" })[policy.mode] or "open to all"
	local rentText = if (policy.rent or 0) > 0 then `{Format.short(policy.rent)} gold rent every 2 hours` else "no rent"
	local where = if realm.home == selected then "This is your home." elseif homeLand then `You live in {homeLand.name}. Moving here moves you out.` else "You can live in one territory, in any guild or none."
	pop.residentCard.note.Text = `Residents get <font color="{GREEN_TEXT}">{math.floor(share * 100 + 0.5)}% of {bonusText(territory)}</font> while a guild holds it (members of the holding guild get all of it and pay no rent). {where}\n<font color="#F0C450">Rules: {modeText}, level {policy.level or 0}+, {rentText}.</font>`
	local names = view and view.names or {}
	pop.residentNames.Text = if #names > 0 then `Residents: {table.concat(names, ", ")}{if info.residents > #names then ` and {info.residents - #names} more` else ""}` else "Nobody lives here yet."
	pop.rules.Visible = mine and realm.officer
	for mode, button in pop.modes do
		setOutline(button, button.Text, true, if mode == policy.mode then GOLD else Color3.fromRGB(150, 140, 125))
		button.BackgroundColor3 = if mode == policy.mode then Color3.fromRGB(60, 50, 26) else DARK
	end
	pop.levelRule.Text = `Level needed: <font color="#F0C450">{policy.level or 0}+</font>`
	pop.rentRule.Text = `Rent every 2 hours: <font color="#F0C450">{Format.short(policy.rent or 0)}</font> gold <font color="#B2A690">(most {Format.short(SocialConfig.rentMax(territory.tier))}, paid to your guild as guild experience)</font>`
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

	-- FORTIFY
	pop.purse.Text = `\u{1F4B0} {Format.short(state.gold)}     \u{26A1} {math.floor(state.energy)}`
	for index, fort in SocialConfig.Forts do
		local part = pop.forts[fort.key]
		local progress = view and view.forts and view.forts[fort.key] or { l = info.forts[fort.key] or 0, g = 0, e = 0 }
		local level = progress.l
		local maxed = level >= SocialConfig.FortMax
		part.name.Text = tier.forts[index]
		for pip, dot in part.pips do
			dot.BackgroundColor3 = if pip <= level then GOLD else Color3.fromRGB(60, 56, 52)
		end
		part.nowValue.Text = if level == 0 and fort.key == "walls" then "Base walls" else fortEffect(territory, fort.key, level)
		part.nextHead.Text = if maxed then "FULLY BUILT" else `AT LEVEL {level + 1}`
		part.nextValue.Text = if maxed then "\u{2714}" else fortEffect(territory, fort.key, level + 1)
		local needGold, needEnergy = SocialConfig.fortCost(territory.tier, level)
		if maxed then
			part.goldLabel.Text = "\u{1F4B0} GOLD   <font color=\"#FFFFFF\">done</font>"
			part.energyLabel.Text = "\u{26A1} ENERGY   <font color=\"#FFFFFF\">done</font>"
			Kit.setBar(part.goldBar, 1, 1, "")
			Kit.setBar(part.energyBar, 1, 1, "")
		else
			part.goldLabel.Text = `\u{1F4B0} GOLD   <font color="#FFFFFF">{Format.short(progress.g)} / {Format.short(needGold)}</font>`
			part.energyLabel.Text = `\u{26A1} ENERGY   <font color="#FFFFFF">{Format.short(progress.e)} / {Format.short(needEnergy)}</font>`
			Kit.setBar(part.goldBar, progress.g, needGold, "")
			Kit.setBar(part.energyBar, progress.e, needEnergy, "")
		end
		part.gold = math.min(math.floor(state.gold), math.max(0, needGold - progress.g), math.ceil(needGold / 4))
		part.energy = math.min(math.floor(state.energy), math.max(0, needEnergy - progress.e))
		local open = mine and not maxed
		setOutline(part.giveGold, if not mine then "HOLDERS ONLY" elseif maxed then "BUILT" else `DONATE {Format.short(part.gold)} GOLD`, open and part.gold > 0)
		setOutline(part.giveEnergy, if not mine then "HOLDERS ONLY" elseif maxed then "BUILT" else `DONATE {Format.short(part.energy)} ENERGY`, open and part.energy > 0)
	end

	-- HISTORY
	local history = view and view.history or {}
	pop.noHistory.Visible = #history == 0
	for index, row in pop.historyRows do
		local entry = history[index]
		row.row.Visible = entry ~= nil
		if entry then
			row.text.Text = `<font color="#B2A690">{ago(now - (entry.t or now))}</font>   {entry.x}`
		end
	end
end

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------

function RealmPage.build(ui)
	local page = ui.pages["Realm Map"]

	-- top bar: TERRITORIES ?  TOP GUILDS #1 #2 #3   STIPEND
	local top = ui.makeFrame(page, UDim2.new(1, -10, 0, 70), UDim2.fromOffset(0, 0), Color3.fromRGB(44, 38, 26))
	top.LayoutOrder = 1
	ui.addCorner(top, 4)
	ui.art.stroke(top, Color3.fromRGB(110, 90, 50), 2, 0)
	local title = text(ui, top, UDim2.fromOffset(230, 70), UDim2.fromOffset(16, 0), GOLD, 34, ui.art.Fonts.title)
	title.Text = "TERRITORIES"
	local help = ui.makeButton(top, UDim2.fromOffset(34, 40), UDim2.fromOffset(246, 15), Color3.fromRGB(44, 38, 26))
	help.BackgroundTransparency = 1
	help.Text = "?"
	help.TextSize = 30
	help.Font = Enum.Font.GothamBlack
	help.TextColor3 = Color3.fromRGB(180, 170, 150)
	help.Activated:Connect(function()
		ui.openModal("RealmBonuses", "Territories")
	end)
	local topLabel = text(ui, top, UDim2.fromOffset(140, 70), UDim2.fromOffset(290, 0), Color3.fromRGB(190, 180, 160), 16)
	topLabel.Text = "TOP GUILDS"
	w.top = {}
	for place = 1, 3 do
		local chip = outlineButton(ui, top, UDim2.fromOffset(210, 54), UDim2.fromOffset(420 + (place - 1) * 220, 8), if place == 1 then GOLD else Color3.fromRGB(150, 140, 120))
		chip.Text = ""
		chip.AutoButtonColor = false
		local rank = text(ui, chip, UDim2.fromOffset(48, 54), UDim2.fromOffset(6, 0), if place == 1 then GOLD else Color3.new(1, 1, 1), 26, ui.art.Fonts.title)
		rank.Text = `#{place}`
		local swatch = ui.makeFrame(chip, UDim2.fromOffset(30, 30), UDim2.fromOffset(54, 12), Color3.fromRGB(60, 56, 52))
		ui.addCorner(swatch, 4)
		local name = text(ui, chip, UDim2.new(1, -96, 0, 24), UDim2.fromOffset(92, 6), Color3.new(1, 1, 1), 15)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local score = text(ui, chip, UDim2.new(1, -96, 0, 18), UDim2.fromOffset(92, 30), Color3.fromRGB(170, 160, 145), 12)
		w.top[place] = { chip = chip, swatch = swatch, name = name, score = score }
	end
	w.stipend = text(ui, top, UDim2.new(1, -1110, 1, 0), UDim2.fromOffset(1090, 0), GOLD, 14)
	w.stipend.TextXAlignment = Enum.TextXAlignment.Right

	-- second bar: TERRITORIES list, MY GUILD, holds X of N, ALL BONUSES
	local bar = ui.makeFrame(page, UDim2.new(1, -10, 0, 56), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	bar.BackgroundTransparency = 1
	bar.LayoutOrder = 2
	local list = ui.makeButton(bar, UDim2.fromOffset(200, 50), UDim2.fromOffset(0, 3), Color3.fromRGB(58, 56, 54))
	list.Font = Enum.Font.GothamBlack
	list.TextSize = 20
	list.Text = "TERRITORIES  \u{25BE}"
	list.Activated:Connect(function()
		ui.openModal("RealmList", "Territories")
	end)
	w.mine = ui.makeButton(bar, UDim2.fromOffset(160, 50), UDim2.fromOffset(208, 3), Color3.fromRGB(58, 56, 54))
	w.mine.Font = Enum.Font.GothamBlack
	w.mine.TextSize = 20
	w.mine.Text = "MY GUILD"
	w.mine.Activated:Connect(function()
		onlyMine = not onlyMine
		ui.redraw()
	end)
	w.holds = text(ui, bar, UDim2.new(1, -620, 1, 0), UDim2.fromOffset(384, 0), Color3.fromRGB(200, 190, 175), 20)
	local bonuses = ui.makeButton(bar, UDim2.fromOffset(220, 50), UDim2.new(1, -220, 0, 3), Color3.fromRGB(58, 56, 54))
	bonuses.Font = Enum.Font.GothamBlack
	bonuses.TextSize = 20
	bonuses.Text = "ALL BONUSES  \u{25BE}"
	bonuses.Activated:Connect(function()
		ui.openModal("RealmBonuses", "Realm bonuses")
	end)

	buildMap(ui, page)

	w.footer = text(ui, page, UDim2.new(1, -10, 0, 30), UDim2.fromOffset(0, 0), Color3.fromRGB(180, 170, 155), 13, Enum.Font.GothamBold)
	w.footer.LayoutOrder = 4

	-- bonuses + help window
	w.bonusList = text(ui, ui.pages.RealmBonuses, UDim2.new(1, -10, 0, 0), UDim2.fromOffset(0, 0), ui.colors.text, 15, Enum.Font.GothamBold)
	w.bonusList.AutomaticSize = Enum.AutomaticSize.Y
	w.bonusList.LayoutOrder = 1

	-- territories list window
	w.listRows = {}
	for index, territory in SocialConfig.Territories do
		local row = listRow(ui, ui.pages.RealmList, index, 40, true)
		row.button.Text = "OPEN"
		row.button.TextSize = 14
		row.button.Activated:Connect(function()
			ui.closeModal()
			tierShown = territory.tier
			focusOn(cells[territory.id].center, 1.1)
			openTerritory(ui, territory)
		end)
		w.listRows[territory.id] = row
	end

	buildPopup(ui)

	Fx.handlers.realm = function(info)
		local territory = SocialConfig.TerritoryById[info.territory or ""]
		if not territory then
			return
		end
		local target = if ui.isOpen("Territory") and selected == territory.id then pop.header else nil
		if target then
			if info.kind == "attack" or info.kind == "siege" then
				Kit.float(ui, target, `-{Format.short(info.damage or 0)}`, Kit.RED)
			elseif info.kind == "claim" then
				Kit.float(ui, target, "\u{1F6A9} CLAIMED!", GOLD)
			elseif info.kind == "capture" then
				Kit.float(ui, target, "\u{1F451} CAPTURED!", GOLD)
			elseif info.kind == "fortLevel" then
				Kit.float(ui, target, "\u{1F3F0} LEVEL UP!", Kit.GREEN)
			elseif info.kind == "station" then
				Kit.float(ui, target, "\u{1F6E1}\u{FE0F} ON GUARD", Kit.GREEN)
			end
		end
		local part = cells[territory.id]
		if part then
			paint(part.edge, GOLD)
			task.delay(0.6, function()
				paint(part.edge, part.edgeColor or Color3.new(1, 1, 1))
			end)
		end
	end
	page:GetPropertyChangedSignal("Visible"):Connect(function()
		if page.Visible then
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

	-- top guilds
	for place, chip in w.top do
		local entry = realm.top[place]
		if entry then
			chip.swatch.BackgroundColor3 = guildColor(entry.id)
			chip.name.Text = `[{entry.tag}] {string.upper(entry.name)}`
			chip.score.Text = `SCORE {entry.score}  \u{2022}  {entry.held} HELD`
		else
			chip.swatch.BackgroundColor3 = Color3.fromRGB(60, 56, 52)
			chip.name.Text = "\u{2014}"
			chip.score.Text = "NOBODY YET"
		end
	end
	w.stipend.Text = if realm.stipendNext > 0 then `STIPEND IN {hms(realm.stipendIn)}\n<font color="{GREEN_TEXT}">+{Format.short(realm.stipendNext)} GOLD</font>` else ""
	w.holds.Text = if guildId == "" then "JOIN A GUILD TO CLAIM TERRITORIES" else `YOUR GUILD HOLDS <font color="#FFFFFF">{realm.held}</font> OF {#SocialConfig.Territories} TERRITORIES  <font color="#B2A690">(MOST {realm.maxHeld})</font>`
	w.mine.BackgroundColor3 = if onlyMine then Color3.fromRGB(120, 96, 40) else Color3.fromRGB(58, 56, 54)

	drawMap(state)

	local stationed, waiting = 0, 0
	for _, entry in realm.stationed do
		if entry.t == "" then
			waiting += 1
		else
			stationed += 1
		end
	end
	local home = SocialConfig.TerritoryById[realm.home]
	w.footer.Text = `\u{1F6E1}\u{FE0F} {stationed} of your soldiers on guard{if waiting > 0 then `, {waiting} waiting for a free warband slot` else ""}   \u{2022}   \u{1F3E0} Home: {if home then home.name else "none"}   \u{2022}   \u{2694}\u{FE0F} {realm.attacks} attacks, {realm.captures} captures`

	-- territories list
	if ui.isOpen("RealmList") then
		for id, row in w.listRows do
			local territory = SocialConfig.TerritoryById[id]
			local info = realm.lands[id] or {}
			local holder = info.holder
			row.text.Text = `<font color="#F0C450">{territory.number}</font>  {territory.name}  <font color="#B2A690">tier {territory.tier}  \u{2022}  {bonusText(territory)}</font>  \u{2022}  {if holder then guildText(holder) else "<i>unclaimed</i>"}`
		end
	end

	-- bonuses and help
	if ui.isOpen("RealmBonuses") then
		local lines = {}
		local totals = {}
		for _, territory in SocialConfig.Territories do
			local info = realm.lands[territory.id]
			if info and info.holder then
				local amount, why = 0, ""
				if guildId ~= "" and info.holder.id == guildId then
					amount = territory.amount
					why = "your guild holds it"
				elseif realm.home == territory.id then
					amount = territory.amount * SocialConfig.residentShare(info.forts.homes or 0)
					why = "you live here"
				end
				if amount > 0 then
					totals[territory.bonus] = (totals[territory.bonus] or 0) + amount
					table.insert(lines, `<b>{territory.name}</b>  <font color="{GREEN_TEXT}">{pct(amount)} {SocialConfig.BonusNames[territory.bonus]}</font>  <font color="#B2A690">({why})</font>`)
				end
			end
		end
		local total = {}
		for kind, amount in totals do
			table.insert(total, `<font color="#F0C450">{pct(amount)} {SocialConfig.BonusNames[kind] or kind}</font>`)
		end
		local how = "<b>How territories work</b>\n"
			.. "\u{2022} Nobody holds it: any guild can CLAIM it for gold, no level needed.\n"
			.. "\u{2022} Another guild holds it: ATTACK (stamina) and SIEGE (energy) until its strength is 0. The guild that did the most damage takes it.\n"
			.. "\u{2022} Holders get the bonus and a stipend every 2 hours, station soldiers, and build fortifications.\n"
			.. "\u{2022} Anyone can live in one territory for a share of its bonus, if the holders allow it.\n"
			.. "\u{2022} Higher tiers give bigger bonuses.\n\n"
		local mineText = if #lines == 0 then "<b>Your realm bonuses</b>\nNone yet. Hold a territory with your guild, or live in one a guild holds."
			else `<b>Your realm bonuses</b>\nTotal: {table.concat(total, ", ")}\n\n{table.concat(lines, "\n")}`
		w.bonusList.Text = how .. mineText
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
