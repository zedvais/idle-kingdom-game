-- The game's look, drawn in code: no uploaded images. Colors, fonts,
-- icons (emoji) and small helpers that dress up frames and buttons with
-- gradients, borders, corner studs and hover effects.

local TweenService = game:GetService("TweenService")

local Assets = require(script.Parent:WaitForChild("Assets"))

local Art = {}

---------------------------------------------------------------------------
-- Fonts and colors
---------------------------------------------------------------------------

Art.Fonts = {
	title = Enum.Font.GrenzeGotisch, -- big page and popup titles
	heading = Enum.Font.Fondamento, -- small headings
	body = Enum.Font.GothamMedium,
	bold = Enum.Font.GothamBold,
}

Art.Colors = {
	ink = Color3.fromRGB(14, 10, 8),
	gold = Color3.fromRGB(240, 196, 80),
	goldDark = Color3.fromRGB(150, 108, 40),
	goldLight = Color3.fromRGB(255, 232, 160),
	wood = Color3.fromRGB(62, 42, 28),
	woodDark = Color3.fromRGB(36, 24, 16),
	parchment = Color3.fromRGB(232, 214, 172),
	blood = Color3.fromRGB(150, 36, 32),
}

-- Banner colors for each group of pages in the left menu.
Art.GroupColors = {
	Realm = Color3.fromRGB(46, 84, 150),
	Daily = Color3.fromRGB(36, 120, 110),
	Campaign = Color3.fromRGB(150, 44, 38),
	Arena = Color3.fromRGB(170, 96, 36),
	Court = Color3.fromRGB(104, 58, 140),
	Treasury = Color3.fromRGB(176, 130, 30),
}

-- An emoji for every page, popup and resource.
Art.Icons = {
	Keep = "\u{1F3F0}", -- castle
	Estate = "\u{1F332}", -- tree
	Holdings = "\u{1F33E}", -- sheaf of rice
	Research = "\u{1F4DA}", -- books
	Bank = "\u{1F3E6}", -- bank
	Bounties = "\u{1F4DC}", -- scroll
	Festival = "\u{1F3AA}", -- tent
	Quests = "\u{1F5FA}\u{FE0F}", -- map
	Foes = "\u{1F409}", -- dragon
	Expeditions = "\u{1F3D5}\u{FE0F}", -- camping
	Rankings = "\u{1F3C6}", -- trophy
	Raids = "\u{1F525}", -- fire
	["Realm Map"] = "\u{1F6A9}", -- flag
	Guild = "\u{1F465}", -- people
	["War Chronicle"] = "\u{1F4D6}", -- open book
	Warband = "\u{2694}\u{FE0F}", -- crossed swords
	Barracks = "\u{1F3F9}", -- bow and arrow
	Inventory = "\u{1F392}", -- backpack
	["Relic Hall"] = "\u{1F3FA}", -- amphora
	Market = "\u{2696}\u{FE0F}", -- scales
	["Royal Pass"] = "\u{1F396}\u{FE0F}", -- medal
	Shop = "\u{1F48E}", -- gem
	Profile = "\u{1F6E1}\u{FE0F}", -- shield
	Rebirth = "\u{1F31F}", -- glowing star
	Mail = "\u{2709}\u{FE0F}", -- envelope
	Skills = "\u{1F4AA}", -- flexed arm
	Pass = "\u{1F39F}\u{FE0F}", -- ticket
	gold = "\u{1F4B0}", -- money bag
	crowns = "\u{1F451}", -- crown
	energy = "\u{26A1}", -- lightning
	stamina = "\u{1F5E1}\u{FE0F}", -- dagger
	health = "\u{2764}\u{FE0F}", -- heart
	xp = "\u{2B50}", -- star
	Weapon = "\u{2694}\u{FE0F}",
	Armor = "\u{1F6E1}\u{FE0F}",
	Mount = "\u{1F40E}", -- horse
	soldier = "\u{1F482}", -- guard
	chest = "\u{1F381}",
	warn = "\u{26A0}\u{FE0F}",
	scroll = "\u{1F4DC}",
}

---------------------------------------------------------------------------
-- Small tools
---------------------------------------------------------------------------

function Art.tween(instance: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		goal
	)
	tween:Play()
	return tween
end

-- A color a share of the way to white (positive) or black (negative).
function Art.shade(color: Color3, amount: number): Color3
	if amount >= 0 then
		return color:Lerp(Color3.new(1, 1, 1), amount)
	end
	return color:Lerp(Color3.new(0, 0, 0), -amount)
end

local function corner(instance: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = instance
end
Art.corner = function(instance: Instance, radius: number)
	corner(instance, UDim.new(0, radius))
end

local function cornerOf(instance: Instance): UDim
	local existing = instance:FindFirstChildOfClass("UICorner")
	return if existing then existing.CornerRadius else UDim.new(0, 6)
end

-- A vertical gradient that multiplies the background: light top, dark
-- bottom. Works with any background color, so buttons keep their color.
function Art.gloss(instance: Instance, top: number?, bottom: number?)
	local gradient = Instance.new("UIGradient")
	local hi = top or 1
	local lo = bottom or 0.72
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(hi, hi, hi)),
		ColorSequenceKeypoint.new(0.5, Color3.new((hi + lo) / 2 + 0.06, (hi + lo) / 2 + 0.06, (hi + lo) / 2 + 0.06)),
		ColorSequenceKeypoint.new(0.52, Color3.new((hi + lo) / 2, (hi + lo) / 2, (hi + lo) / 2)),
		ColorSequenceKeypoint.new(1, Color3.new(lo, lo, lo)),
	})
	gradient.Rotation = 90
	gradient.Parent = instance
	return gradient
end

-- Wood grain: soft bands across a panel. Multiplies the background.
function Art.grain(instance: Instance, rotation: number?)
	local gradient = Instance.new("UIGradient")
	local points = {}
	local shades = { 1, 0.9, 0.97, 0.86, 1, 0.92, 0.84, 0.96, 0.9, 1, 0.88 }
	for index, value in shades do
		table.insert(points, ColorSequenceKeypoint.new((index - 1) / (#shades - 1), Color3.new(value, value * 0.97, value * 0.94)))
	end
	gradient.Color = ColorSequence.new(points)
	gradient.Rotation = rotation or 90
	gradient.Parent = instance
	return gradient
end

function Art.stroke(instance: Instance, color: Color3, thickness: number?, transparency: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 1
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = instance
	return s
end

-- Four little gold diamonds on the corners of a panel, like rivets.
function Art.studs(instance: GuiObject, size: number?)
	local s = size or 8
	for _, spot in { Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) } do
		local stud = Instance.new("Frame")
		stud.Name = "Stud"
		stud.Size = UDim2.fromOffset(s, s)
		stud.AnchorPoint = Vector2.new(0.5, 0.5)
		stud.Position = UDim2.new(spot.X, if spot.X == 0 then s else -s, spot.Y, if spot.Y == 0 then s else -s)
		stud.Rotation = 45
		stud.BackgroundColor3 = Art.Colors.gold
		stud.BorderSizePixel = 0
		stud.ZIndex = instance.ZIndex + 1
		stud.Parent = instance
		Art.gloss(stud, 1, 0.6)
		Art.stroke(stud, Art.Colors.woodDark, 1, 0.3)
	end
end

-- A big panel (top bar, left menu, page area, popups): wood grain, a
-- gold rim and corner studs.
function Art.panel(frame: GuiObject, studs: boolean?)
	Art.grain(frame, 90)
	for _, child in frame:GetChildren() do
		if child:IsA("UIStroke") then
			child:Destroy()
		end
	end
	Art.stroke(frame, Art.Colors.goldDark, 2, 0.1)
	if studs ~= false then
		Art.studs(frame)
	end
end

-- A row or card inside a page: soft gradient, thin warm edge.
function Art.card(frame: GuiObject)
	Art.gloss(frame, 1, 0.84)
end

-- Hover and press feedback for a button: a light layer on hover and a
-- dark one on press. No size change, so lists and grids never shift.
function Art.button(button: GuiButton)
	Art.gloss(button)
	local edge = Art.stroke(button, Art.Colors.ink, 1.5, 0.35)
	-- Clear buttons (click areas over other things) get no edge.
	local function syncEdge()
		edge.Enabled = button.BackgroundTransparency < 0.9
	end
	syncEdge()
	button:GetPropertyChangedSignal("BackgroundTransparency"):Connect(syncEdge)

	local layer = Instance.new("Frame")
	layer.Name = "Glow"
	layer.Size = UDim2.fromScale(1, 1)
	layer.BackgroundColor3 = Color3.new(1, 1, 1)
	layer.BackgroundTransparency = 1
	layer.BorderSizePixel = 0
	layer.Active = false
	layer.ZIndex = button.ZIndex
	layer.Parent = button
	task.defer(function()
		corner(layer, cornerOf(button))
	end)
	button:GetPropertyChangedSignal("ZIndex"):Connect(function()
		layer.ZIndex = button.ZIndex
	end)

	local hovering = false
	local function show(transparency: number, color: Color3)
		layer.BackgroundColor3 = color
		Art.tween(layer, 0.12, { BackgroundTransparency = transparency })
	end
	-- NoGlow marks big clear click areas (popup shades) that should not light up.
	button.MouseEnter:Connect(function()
		hovering = true
		if not button:GetAttribute("NoGlow") then
			show(0.88, Color3.new(1, 1, 1))
		end
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		show(1, Color3.new(1, 1, 1))
	end)
	button.MouseButton1Down:Connect(function()
		if not button:GetAttribute("NoGlow") then
			show(0.75, Color3.new(0, 0, 0))
		end
	end)
	button.MouseButton1Up:Connect(function()
		show(if hovering then 0.88 else 1, Color3.new(1, 1, 1))
	end)
end

-- An emoji label. The emoji keeps its own colors.
function Art.icon(parent: Instance, glyph: string, size: number, position: UDim2): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "Icon"
	label.Size = UDim2.fromOffset(size, size)
	label.Position = position
	label.BackgroundTransparency = 1
	label.Text = glyph
	label.TextScaled = true
	label.Font = Enum.Font.GothamMedium
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = parent
	return label
end

-- Shows icon `key` on an emoji label: the uploaded art from Assets.luau
-- when that slot is set, otherwise the emoji from Art.Icons.
function Art.setIcon(label: TextLabel, key: string)
	Assets.icon(label, key, Art.Icons[key] or "")
end

-- A round badge with an emoji in it, ringed in gold: page emblems and
-- popup titles.
function Art.emblem(parent: Instance, glyph: string, size: number, position: UDim2, color: Color3): (Frame, TextLabel)
	local disc = Instance.new("Frame")
	disc.Name = "Emblem"
	disc.Size = UDim2.fromOffset(size, size)
	disc.Position = position
	disc.BackgroundColor3 = color
	disc.BorderSizePixel = 0
	disc.Parent = parent
	corner(disc, UDim.new(0.5, 0))
	Art.gloss(disc, 1, 0.55)
	Art.stroke(disc, Art.Colors.gold, 2, 0)
	local inner = Art.icon(disc, glyph, math.floor(size * 0.62), UDim2.fromScale(0.5, 0.5))
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	return disc, inner
end

-- A castle skyline drawn with blocks, for banners. Fills its parent's
-- bottom; color is the silhouette color.
function Art.skyline(parent: Instance, color: Color3, transparency: number)
	local holder = Instance.new("Frame")
	holder.Name = "Skyline"
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.ClipsDescendants = true
	holder.Parent = parent
	-- { x share, width px, height px, merlons }
	local shapes = {
		{ 0.02, 26, 30, 3 },
		{ 0.08, 60, 18, 0 },
		{ 0.15, 34, 44, 3 },
		{ 0.24, 80, 22, 5 },
		{ 0.38, 22, 52, 0 },
		{ 0.45, 70, 26, 4 },
		{ 0.57, 30, 40, 3 },
		{ 0.64, 90, 16, 0 },
		{ 0.78, 28, 48, 3 },
		{ 0.86, 64, 24, 4 },
		{ 0.95, 24, 36, 2 },
	}
	for _, shape in shapes do
		local block = Instance.new("Frame")
		block.AnchorPoint = Vector2.new(0, 1)
		block.Position = UDim2.new(shape[1], 0, 1, 0)
		block.Size = UDim2.fromOffset(shape[2], shape[3])
		block.BackgroundColor3 = color
		block.BackgroundTransparency = transparency
		block.BorderSizePixel = 0
		block.Parent = holder
		local merlons = shape[4]
		if merlons > 0 then
			local gap = shape[2] / (merlons * 2 - 1)
			for index = 0, merlons - 1 do
				local merlon = Instance.new("Frame")
				merlon.AnchorPoint = Vector2.new(0, 1)
				merlon.Position = UDim2.fromOffset(math.floor(index * gap * 2), 0)
				merlon.Size = UDim2.fromOffset(math.max(2, math.floor(gap)), 6)
				merlon.BackgroundColor3 = color
				merlon.BackgroundTransparency = transparency
				merlon.BorderSizePixel = 0
				merlon.Parent = block
			end
		elseif shape[3] > 40 then
			-- A spire on tall towers.
			local spire = Instance.new("Frame")
			spire.AnchorPoint = Vector2.new(0.5, 1)
			spire.Position = UDim2.fromScale(0.5, 0)
			spire.Size = UDim2.fromOffset(4, 12)
			spire.BackgroundColor3 = color
			spire.BackgroundTransparency = transparency
			spire.BorderSizePixel = 0
			spire.Parent = block
		end
	end
	return holder
end

-- A light streak that sweeps across a frame now and then. For gold and
-- premium things only, so it stays special.
function Art.shine(frame: GuiObject, every: number?)
	local streak = Instance.new("Frame")
	streak.Name = "Shine"
	streak.Size = UDim2.fromScale(1, 1)
	streak.BackgroundColor3 = Color3.new(1, 1, 1)
	streak.BackgroundTransparency = 0.55
	streak.BorderSizePixel = 0
	streak.Active = false
	streak.ZIndex = frame.ZIndex
	streak.Parent = frame
	task.defer(function()
		corner(streak, cornerOf(frame))
	end)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 20
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.42, 1),
		NumberSequenceKeypoint.new(0.5, 0.2),
		NumberSequenceKeypoint.new(0.58, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Offset = Vector2.new(-1, 0)
	gradient.Parent = streak
	task.spawn(function()
		while streak.Parent do
			gradient.Offset = Vector2.new(-1, 0)
			Art.tween(gradient, 0.9, { Offset = Vector2.new(1, 0) }, Enum.EasingStyle.Sine)
			task.wait((every or 4) + math.random() * 2)
		end
	end)
	return streak
end

-- A glossy fill for progress bars.
function Art.bar(back: GuiObject, fill: GuiObject)
	Art.stroke(back, Art.Colors.ink, 1, 0.2)
	Art.gloss(fill, 1, 0.7)
end

-- Progress bars under a row's or card's text. The first call adds the bar
-- (a row grows 8 pixels for it); later calls move the fill smoothly.
-- maximum <= 0 hides it. Full bars turn green unless a color is forced.
local progressBars = setmetatable({}, { __mode = "k" })
local PROGRESS_GREEN = Color3.fromRGB(90, 180, 95)
function Art.progress(info: GuiObject, value: number, maximum: number, color: Color3?, keepColor: boolean?)
	local bar = progressBars[info]
	if not bar then
		local holder = info.Parent :: GuiObject
		local card = info.Size.Y.Offset <= -40 -- card text leaves room for a button below
		local back = Instance.new("Frame")
		back.Name = "Progress"
		back.BackgroundColor3 = Color3.fromRGB(16, 12, 10)
		back.BorderSizePixel = 0
		back.Size = UDim2.new(info.Size.X.Scale, info.Size.X.Offset, 0, 7)
		if card then
			back.Position = UDim2.new(info.Position.X.Scale, info.Position.X.Offset, 1, -51)
			info.Size -= UDim2.fromOffset(0, 9)
		else
			holder.Size += UDim2.fromOffset(0, 8)
			info.Size -= UDim2.fromOffset(0, 8)
			back.Position = UDim2.new(info.Position.X.Scale, info.Position.X.Offset, 1, -11)
		end
		back.ZIndex = info.ZIndex
		back.Parent = holder
		corner(back, UDim.new(0, 4))
		Art.stroke(back, Art.Colors.ink, 1, 0.3)
		local fill = Instance.new("Frame")
		fill.BorderSizePixel = 0
		fill.Size = UDim2.fromScale(0, 1)
		fill.ZIndex = info.ZIndex
		fill.Parent = back
		corner(fill, UDim.new(0, 4))
		Art.gloss(fill, 1, 0.65)
		bar = { back = back, fill = fill, share = -1 }
		progressBars[info] = bar
	end
	bar.back.Visible = maximum > 0
	if maximum <= 0 then
		return
	end
	local share = math.clamp(value / maximum, 0, 1)
	bar.fill.BackgroundColor3 = if share >= 1 and not keepColor then PROGRESS_GREEN else (color or Art.Colors.gold)
	if share ~= bar.share then
		if bar.share < 0 then
			bar.fill.Size = UDim2.fromScale(share, 1)
		else
			Art.tween(bar.fill, 0.35, { Size = UDim2.fromScale(share, 1) })
		end
		bar.share = share
	end
end

-- Picks an emoji for a toast message from its words.
function Art.toastIcon(text: string): string
	local lower = string.lower(text)
	if string.find(lower, "level %d") then
		return Art.Icons.xp
	elseif string.find(lower, "not enough") or string.find(lower, "need") or string.find(lower, "full") or string.find(lower, "can't") then
		return Art.Icons.warn
	elseif string.find(lower, "chest") or string.find(lower, "coffer") or string.find(lower, "opened") then
		return Art.Icons.chest
	elseif string.find(lower, "crown") then
		return Art.Icons.crowns
	elseif string.find(lower, "joined") or string.find(lower, "recruit") or string.find(lower, "rolled") then
		return Art.Icons.soldier
	elseif string.find(lower, "stage") or string.find(lower, "hit") or string.find(lower, "knocked") then
		return Art.Icons.Foes
	elseif string.find(lower, "gold") then
		return Art.Icons.gold
	end
	return Art.Icons.scroll
end

return Art
