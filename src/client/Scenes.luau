-- Small animated pictures drawn with plain frames: one for each Keep level
-- (Timber Hall to Sunspire Palace), each Estate building and each holding.
--
-- Kept light on purpose: every picture is a few dozen frames, all the
-- motion runs from one shared loop 20 times a second, and a picture only
-- moves while its page is open.
--
-- Every picture is drawn on a 120 x 80 canvas (pixels, y grows down) and
-- scaled to fit with a UIScale.

local RunService = game:GetService("RunService")
local Assets = require(script.Parent:WaitForChild("Assets"))

local Scenes = {}

local W, H = 120, 80
local GROUND = 66 -- y of the ground line in most pictures

local C = {
	skyTop = Color3.fromRGB(120, 170, 220),
	skyLow = Color3.fromRGB(240, 210, 160),
	grass = Color3.fromRGB(86, 140, 70),
	grassDark = Color3.fromRGB(62, 108, 54),
	dirt = Color3.fromRGB(120, 88, 56),
	wood = Color3.fromRGB(128, 86, 50),
	woodDark = Color3.fromRGB(84, 56, 34),
	thatch = Color3.fromRGB(196, 160, 80),
	stone = Color3.fromRGB(150, 146, 138),
	stoneDark = Color3.fromRGB(104, 100, 94),
	stoneLight = Color3.fromRGB(196, 190, 178),
	marble = Color3.fromRGB(236, 230, 214),
	roofRed = Color3.fromRGB(168, 58, 46),
	roofBlue = Color3.fromRGB(58, 86, 150),
	gold = Color3.fromRGB(240, 196, 80),
	glow = Color3.fromRGB(255, 214, 120),
	dark = Color3.fromRGB(30, 22, 16),
	leaf = Color3.fromRGB(70, 130, 60),
	leafDark = Color3.fromRGB(50, 100, 46),
	white = Color3.fromRGB(250, 248, 240),
	banner = Color3.fromRGB(150, 36, 32),
	iron = Color3.fromRGB(110, 120, 136),
}

---------------------------------------------------------------------------
-- The shared motion loop
---------------------------------------------------------------------------

local movers = {} -- { root, gate, steps = { function(t) } }
local loopStarted = false

local function startLoop()
	if loopStarted then
		return
	end
	loopStarted = true
	RunService.RenderStepped:Connect(function(dt)
		-- every frame, so motion is smooth (steps use the clock, not dt)
		local t = os.clock()
		for index = #movers, 1, -1 do
			local mover = movers[index]
			if not mover.root.Parent then
				table.remove(movers, index)
			elseif mover.gate() then
				for _, step in mover.steps do
					step(t)
				end
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Drawing helpers. Later shapes sit on top of earlier ones.
---------------------------------------------------------------------------

local Pen = {}
Pen.__index = Pen

local function newPen(root: Frame)
	return setmetatable({ root = root, z = 1, steps = {} }, Pen)
end

function Pen:rect(x: number, y: number, w: number, h: number, color: Color3, radius: number?, parent: Instance?): Frame
	local f = Instance.new("Frame")
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	self.z += 1
	f.ZIndex = self.z
	f.Parent = parent or self.root
	if radius then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = if radius < 1 then UDim.new(radius, 0) else UDim.new(0, radius)
		corner.Parent = f
	end
	return f
end

-- A shape centered on (x, y).
function Pen:dot(x: number, y: number, w: number, h: number, color: Color3, radius: number?): Frame
	local f = self:rect(x, y, w, h, color, radius)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	return f
end

-- Light top, dark bottom shading on a shape.
local function shade(f: GuiObject, low: number?)
	local g = Instance.new("UIGradient")
	local l = low or 0.78
	g.Rotation = 90
	g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(l, l, l))
	g.Parent = f
end

-- A 45 degree roof: a turned square cut off at its middle.
function Pen:roof(cx: number, baseY: number, w: number, color: Color3): Frame
	local clip = Instance.new("Frame")
	clip.Position = UDim2.fromOffset(cx - w / 2, baseY - w / 2)
	clip.Size = UDim2.fromOffset(w, w / 2)
	clip.BackgroundTransparency = 1
	clip.ClipsDescendants = true
	self.z += 1
	clip.ZIndex = self.z
	clip.Parent = self.root
	local side = w / math.sqrt(2)
	local square = Instance.new("Frame")
	square.AnchorPoint = Vector2.new(0.5, 0.5)
	square.Position = UDim2.fromOffset(w / 2, w / 2)
	square.Size = UDim2.fromOffset(side, side)
	square.Rotation = 45
	square.BackgroundColor3 = color
	square.BorderSizePixel = 0
	square.ZIndex = self.z
	square.Parent = clip
	local g = Instance.new("UIGradient")
	g.Rotation = 45
	g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(0.7, 0.7, 0.7))
	g.Parent = square
	return clip
end

-- A run of merlons along a top edge.
function Pen:merlons(x: number, y: number, w: number, color: Color3)
	local count = math.max(2, math.floor(w / 6))
	local gap = (w - 4) / (count - 1)
	for index = 0, count - 1 do
		self:rect(x + index * gap, y - 4, 4, 4, color)
	end
end

function Pen:add(step: (number) -> ())
	table.insert(self.steps, step)
end

---------------------------------------------------------------------------
-- Moving bits
---------------------------------------------------------------------------

-- A flag on a pole whose top is (x, y).
function Pen:flag(x: number, y: number, color: Color3)
	self:rect(x, y, 1, 14, C.woodDark)
	local cloth = self:rect(x + 1, y + 1, 10, 6, color)
	cloth.AnchorPoint = Vector2.new(0, 0)
	shade(cloth, 0.7)
	local seed = x * 0.37
	self:add(function(t)
		cloth.Size = UDim2.fromOffset(9 + math.sin(t * 5 + seed) * 2, 6 + math.sin(t * 7 + seed) * 0.6)
		cloth.Rotation = math.sin(t * 4 + seed) * 5
	end)
end

-- Smoke puffs rising from (x, y).
function Pen:smoke(x: number, y: number)
	local puffs = {}
	for index = 1, 3 do
		local puff = self:dot(x, y, 4, 4, Color3.fromRGB(220, 220, 220), 0.5)
		puffs[index] = puff
	end
	self:add(function(t)
		for index, puff in puffs do
			local phase = (t * 0.45 + index / 3) % 1
			local size = 3 + phase * 7
			puff.Position = UDim2.fromOffset(x + math.sin(phase * 6 + index) * 3 + phase * 4, y - phase * 22)
			puff.Size = UDim2.fromOffset(size, size)
			puff.BackgroundTransparency = 0.25 + phase * 0.75
		end
	end)
end

-- A lit window that flickers like a candle.
function Pen:window(x: number, y: number, w: number, h: number)
	local pane = self:rect(x, y, w, h, C.glow, 1)
	local seed = x * 1.7 + y
	self:add(function(t)
		pane.BackgroundTransparency = 0.05 + 0.3 * math.abs(math.sin(t * 9 + seed) * math.sin(t * 4.3 + seed))
	end)
	return pane
end

-- Rocks a frame back and forth around its center.
function Pen:sway(f: GuiObject, amount: number, speed: number)
	local seed = f.Position.X.Offset * 0.5
	self:add(function(t)
		f.Rotation = math.sin(t * speed + seed) * amount
	end)
end

-- A tiny pivot at (x, y): things put in it turn around that point.
function Pen:pivot(x: number, y: number): Frame
	local p = self:rect(x - 1, y - 1, 2, 2, C.dark)
	p.BackgroundTransparency = 1
	return p
end

-- A twinkle that blinks on and off.
function Pen:twinkle(x: number, y: number, color: Color3)
	local star = self:dot(x, y, 3, 3, color)
	star.Rotation = 45
	local seed = x + y * 0.3
	self:add(function(t)
		local v = (math.sin(t * 3 + seed) + 1) / 2
		star.BackgroundTransparency = 1 - v
		star.Size = UDim2.fromOffset(2 + v * 3, 2 + v * 3)
	end)
end

---------------------------------------------------------------------------
-- Building blocks
---------------------------------------------------------------------------

function Pen:sky(width: number)
	local sky = self:rect(0, 0, width, H, Color3.new(1, 1, 1))
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(C.skyTop, C.skyLow)
	g.Parent = sky
	self:dot(width - 24, 16, 12, 12, Color3.fromRGB(255, 236, 170), 0.5)
	-- Two clouds drifting slowly.
	for index = 1, 2 do
		local cloud = self:rect(0, 6 + index * 7, 18, 5, C.white, 0.5)
		cloud.BackgroundTransparency = 0.15
		local puff = self:rect(4, -3, 9, 6, C.white, 0.5, cloud)
		puff.BackgroundTransparency = 0.15
		puff.ZIndex = cloud.ZIndex
		local speed, offset = 3 + index * 1.5, index * 55
		self:add(function(t)
			cloud.Position = UDim2.fromOffset((t * speed + offset) % (width + 30) - 24, 6 + index * 7)
		end)
	end
end

function Pen:ground(width: number)
	for x = 30, width, 70 do
		self:dot(x, GROUND + 4, 90, 26, C.grassDark, 0.5)
	end
	local g = self:rect(0, GROUND, width, H - GROUND, C.grass)
	shade(g, 0.8)
end

function Pen:hall(cx: number, base: number, w: number, h: number, wall: Color3, roofColor: Color3)
	self:roof(cx, base - h + 1, w + 8, roofColor)
	local body = self:rect(cx - w / 2, base - h, w, h, wall)
	shade(body)
	self:rect(cx - 3, base - 9, 6, 9, C.dark, 2)
	self:window(cx - w / 2 + 4, base - h + 4, 4, 4)
	self:window(cx + w / 2 - 8, base - h + 4, 4, 4)
end

function Pen:tower(cx: number, base: number, w: number, h: number, stone: Color3, opts)
	opts = opts or {}
	local top = base - h
	if opts.roof then
		self:roof(cx, top + 1, w + 6, opts.roof)
	end
	local body = self:rect(cx - w / 2, top, w, h, stone)
	shade(body, 0.72)
	if not opts.roof then
		self:merlons(cx - w / 2, top, w, stone)
	end
	if opts.trim then
		self:rect(cx - w / 2, top + 2, w, 2, opts.trim)
	end
	self:window(cx - 1.5, top + h * 0.3, 3, 6)
	if opts.flag then
		local flagTop = if opts.roof then top - (w + 6) / 2 - 12 else top - 16
		self:flag(cx, flagTop, opts.flag)
	end
end

function Pen:wall(x1: number, x2: number, base: number, h: number, stone: Color3)
	local body = self:rect(x1, base - h, x2 - x1, h, stone)
	shade(body, 0.75)
	self:merlons(x1, base - h, x2 - x1, stone)
end

function Pen:gate(cx: number, base: number, w: number, h: number)
	self:rect(cx - w / 2, base - h, w, h, C.dark, 3)
	for index = 1, 2 do
		self:rect(cx - w / 2 + index * w / 3, base - h + 2, 1, h - 2, C.woodDark)
	end
end

function Pen:palisade(x1: number, x2: number, base: number, h: number, gapFrom: number?, gapTo: number?)
	local x = x1
	while x < x2 do
		if not (gapFrom and x + 3 > gapFrom and x < gapTo) then
			local tall = h + (math.floor(x) % 3)
			self:rect(x, base - tall, 3, tall, C.wood)
			local tip = self:dot(x + 1.5, base - tall, 2.2, 2.2, C.wood)
			tip.Rotation = 45
		end
		x += 3.5
	end
end

function Pen:tree(x: number, base: number, size: number)
	self:rect(x - 1.5, base - size * 0.6, 3, size * 0.6, C.woodDark)
	local crown = self:dot(x, base - size * 0.75, size * 0.8, size * 0.8, C.leaf, 0.5)
	shade(crown, 0.7)
	self:sway(crown, 4, 1.5)
end

---------------------------------------------------------------------------
-- Keep levels
---------------------------------------------------------------------------

local KEEPS = {}

KEEPS[1] = function(p) -- Timber Hall
	p:rect(70, GROUND - 26, 4, 8, C.stoneDark)
	p:smoke(72, GROUND - 28)
	p:hall(60, GROUND, 44, 20, C.wood, C.thatch)
	p:palisade(14, 30, GROUND, 6)
	p:palisade(90, 106, GROUND, 6)
end

KEEPS[2] = function(p) -- Palisade Fort
	p:rect(66, GROUND - 26, 4, 8, C.stoneDark)
	p:smoke(68, GROUND - 28)
	p:hall(60, GROUND, 36, 18, C.wood, C.thatch)
	p:flag(60, GROUND - 52, C.banner)
	p:palisade(16, 104, GROUND, 12, 52, 68)
	p:gate(60, GROUND, 12, 10)
end

KEEPS[3] = function(p) -- Stone Tower
	p:hall(38, GROUND, 22, 12, C.wood, C.thatch)
	p:smoke(34, GROUND - 22)
	p:tower(62, GROUND, 22, 44, C.stone, { flag = C.banner })
	p:gate(62, GROUND, 8, 10)
	p:palisade(80, 104, GROUND, 8)
end

KEEPS[4] = function(p) -- Motte Castle
	local mound = p:dot(60, GROUND, 92, 30, C.grass, 0.5)
	shade(mound, 0.75)
	p:tower(60, GROUND - 12, 24, 36, C.stone, { flag = C.banner })
	p:palisade(10, 110, GROUND + 4, 9, 54, 66)
	p:gate(60, GROUND + 4, 10, 8)
end

KEEPS[5] = function(p) -- Curtain-Wall Keep
	p:tower(60, GROUND - 10, 26, 36, C.stone, { flag = C.banner })
	p:wall(22, 98, GROUND, 18, C.stoneLight)
	p:tower(22, GROUND, 14, 28, C.stone, {})
	p:tower(98, GROUND, 14, 28, C.stone, {})
	p:gate(60, GROUND, 12, 12)
end

KEEPS[6] = function(p) -- Fortress of the Vale
	p:tower(40, GROUND - 12, 12, 26, C.stone, { roof = C.roofBlue })
	p:tower(80, GROUND - 12, 12, 26, C.stone, { roof = C.roofBlue })
	p:tower(60, GROUND - 12, 26, 30, C.stone, { roof = C.roofBlue })
	p:wall(14, 106, GROUND, 16, C.stoneLight)
	p:tower(16, GROUND, 12, 26, C.stone, { flag = C.roofBlue })
	p:tower(104, GROUND, 12, 26, C.stone, { flag = C.roofBlue })
	p:gate(60, GROUND, 12, 12)
end

KEEPS[7] = function(p) -- Highcrown Citadel
	p:tower(38, GROUND - 8, 14, 34, C.stoneLight, { roof = C.roofRed, flag = C.gold })
	p:tower(82, GROUND - 8, 14, 34, C.stoneLight, { roof = C.roofRed, flag = C.gold })
	p:tower(60, GROUND - 8, 20, 40, C.stoneLight, { roof = C.roofRed, trim = C.gold })
	p:wall(10, 110, GROUND, 18, C.stone)
	p:tower(12, GROUND, 12, 28, C.stone, { roof = C.roofRed })
	p:tower(108, GROUND, 12, 28, C.stone, { roof = C.roofRed })
	p:gate(60, GROUND, 14, 13)
	p:rect(58, GROUND - 5, 4, 2, C.gold)
end

KEEPS[8] = function(p) -- Sunspire Palace
	-- Slow golden rays behind the palace.
	local rays = p:dot(60, 26, 2, 2, C.gold)
	rays.BackgroundTransparency = 1
	for index = 1, 6 do
		local ray = p:dot(1, 1, 4, 90, C.glow)
		ray.Parent = rays
		ray.Position = UDim2.fromOffset(1, 1)
		ray.Rotation = index * 30
		ray.BackgroundTransparency = 0.7
	end
	p:add(function(t)
		rays.Rotation = (t * 6) % 360
	end)
	p:tower(36, GROUND - 10, 16, 32, C.marble, { roof = C.gold, trim = C.gold, flag = C.banner })
	p:tower(84, GROUND - 10, 16, 32, C.marble, { roof = C.gold, trim = C.gold, flag = C.banner })
	p:tower(60, GROUND - 10, 20, 40, C.marble, { roof = C.gold, trim = C.gold })
	p:twinkle(60, 4, C.white)
	p:wall(8, 112, GROUND, 16, C.marble)
	p:rect(8, GROUND - 14, 104, 2, C.gold)
	p:gate(60, GROUND, 14, 12)
	p:twinkle(30, 14, C.white)
	p:twinkle(92, 30, C.white)
	p:twinkle(14, 36, C.glow)
end

---------------------------------------------------------------------------
-- Estate buildings
---------------------------------------------------------------------------

local BUILDINGS = {}

BUILDINGS.lumbercamp = function(p)
	p:tree(16, GROUND, 26)
	p:tree(34, GROUND, 32)
	p:tree(104, GROUND, 28)
	-- Log pile.
	for row = 0, 1 do
		for index = 0, 2 - row do
			local log = p:dot(80 + index * 7 + row * 3.5, GROUND - 3 - row * 6, 7, 7, C.wood, 0.5)
			p:dot(log.Position.X.Offset, log.Position.Y.Offset, 3, 3, C.thatch, 0.5)
		end
	end
	-- A chopping block and a swinging axe.
	p:rect(54, GROUND - 8, 12, 8, C.woodDark, 2)
	local pivot = p:pivot(60, GROUND - 10)
	local handle = p:rect(-1, -16, 2, 16, C.wood, nil, pivot)
	handle.ZIndex = pivot.ZIndex + 1
	local head = p:rect(-5, -18, 7, 5, C.iron, 1, pivot)
	head.ZIndex = pivot.ZIndex + 1
	p:add(function(t)
		local swing = (t * 1.4) % 1
		pivot.Rotation = if swing < 0.75 then -60 + swing / 0.75 * 30 else -30 + (swing - 0.75) / 0.25 * 85
	end)
end

BUILDINGS.quarry = function(p)
	local cliff = p:rect(4, 20, 64, 50, C.stone, 10)
	shade(cliff, 0.7)
	p:rect(14, 34, 20, 3, C.stoneDark)
	p:rect(30, 48, 26, 3, C.stoneDark)
	for index = 0, 4 do
		p:dot(78 + index * 7, GROUND - 3 - (index % 2) * 4, 8, 7, C.stoneLight, 2)
	end
	local pivot = p:pivot(96, GROUND - 16)
	local handle = p:rect(-1, -14, 2, 16, C.wood, nil, pivot)
	handle.ZIndex = pivot.ZIndex + 1
	local head = p:rect(-7, -16, 14, 3, C.iron, 1, pivot)
	head.ZIndex = pivot.ZIndex + 1
	local dust = p:dot(86, GROUND - 6, 6, 6, C.stoneLight, 0.5)
	p:add(function(t)
		local swing = (t * 1.2) % 1
		pivot.Rotation = if swing < 0.7 then 40 - swing / 0.7 * 30 else 10 - (swing - 0.7) / 0.3 * 70
		local puff = (t * 1.2 + 0.05) % 1
		dust.BackgroundTransparency = if puff < 0.15 then 1 else 0.3 + (puff - 0.15) * 0.8
		dust.Size = UDim2.fromOffset(4 + puff * 10, 4 + puff * 10)
	end)
end

BUILDINGS.farm = function(p)
	p:hall(96, GROUND, 24, 16, C.roofRed, C.woodDark)
	for row = 0, 1 do
		for index = 0, 9 do
			local x = 6 + index * 7 + row * 3
			local base = GROUND + 4 + row * 6
			local stalk = p:rect(x, base - 14, 1.5, 14, Color3.fromRGB(170, 150, 70))
			local head = p:rect(-1.5, -2, 4.5, 6, C.thatch, 2, stalk)
			head.ZIndex = stalk.ZIndex
			p:sway(stalk, 7, 1.8)
		end
	end
end

BUILDINGS.mine = function(p)
	p:roof(50, GROUND, 100, C.stoneDark)
	p:roof(50, GROUND, 70, C.stone)
	p:rect(38, GROUND - 22, 24, 22, C.dark, 10)
	p:rect(36, GROUND - 24, 28, 3, C.wood)
	p:rect(36, GROUND - 24, 3, 24, C.wood)
	p:rect(61, GROUND - 24, 3, 24, C.wood)
	p:rect(30, GROUND - 2, 90, 2, C.woodDark)
	local cart = p:rect(0, GROUND - 10, 16, 8, C.iron, 2)
	local ore = p:rect(2, -3, 12, 4, Color3.fromRGB(180, 140, 110), 2, cart)
	ore.ZIndex = cart.ZIndex
	for _, x in { 2, 11 } do
		local wheel = p:rect(x, 6, 4, 4, C.dark, 0.5, cart)
		wheel.ZIndex = cart.ZIndex + 1
	end
	p:add(function(t)
		local phase = (t * 0.25) % 1
		local along = if phase < 0.5 then phase * 2 else 2 - phase * 2
		cart.Position = UDim2.fromOffset(52 + along * 48, GROUND - 10)
	end)
end

BUILDINGS.storehouse = function(p)
	p:hall(46, GROUND, 52, 30, C.wood, C.roofRed)
	p:rect(36, GROUND - 18, 20, 18, C.woodDark, 2)
	for _, spot in { { 86, 0 }, { 98, 0 }, { 92, 1 } } do
		local crate = p:rect(spot[1], GROUND - 10 - spot[2] * 10, 10, 10, C.thatch, 1)
		shade(crate, 0.7)
		p:rect(spot[1] + 4, GROUND - 10 - spot[2] * 10, 2, 10, C.wood)
	end
	local lifted = p:rect(16, GROUND - 10, 9, 9, C.thatch, 1)
	p:add(function(t)
		lifted.Position = UDim2.fromOffset(16, GROUND - 10 - math.abs(math.sin(t * 2)) * 6)
	end)
end

BUILDINGS.granary = function(p)
	local silo = p:rect(26, GROUND - 40, 26, 40, C.stoneLight, 4)
	shade(silo, 0.75)
	p:dot(39, GROUND - 40, 28, 18, C.roofRed, 0.5)
	p:rect(34, GROUND - 12, 10, 12, C.dark, 2)
	for index = 0, 2 do
		p:dot(70 + index * 11, GROUND - 5, 10, 11, C.thatch, 4)
	end
	p:dot(81, GROUND - 13, 10, 11, C.thatch, 4)
	-- A bird circling.
	local bird = p:rect(0, 0, 8, 3, C.dark)
	p:rect(0, 0, 4, 1.5, C.dark, nil, bird).Rotation = -25
	p:add(function(t)
		bird.Position = UDim2.fromOffset(74 + math.cos(t * 0.8) * 26, 18 + math.sin(t * 0.8) * 6)
		bird.Size = UDim2.fromOffset(8, 2 + math.abs(math.sin(t * 8)) * 2)
	end)
end

BUILDINGS.cellar = function(p)
	p:rect(30, GROUND - 2, 60, 16, C.dirt, 3)
	p:rect(40, GROUND, 40, 14, C.dark, 2)
	local light = p:rect(42, GROUND + 2, 36, 10, C.glow, 2)
	-- The open trapdoor, leaning back.
	local door = p:rect(40, GROUND - 20, 40, 18, C.wood, 2)
	door.Rotation = -8
	p:rect(44, GROUND - 14, 32, 2, C.woodDark)
	p:rect(58, GROUND - 18, 4, 4, C.iron, 0.5)
	p:add(function(t)
		light.BackgroundTransparency = 0.1 + 0.35 * math.abs(math.sin(t * 6) * math.sin(t * 2.3))
	end)
	p:twinkle(50, GROUND + 6, C.white)
	p:twinkle(70, GROUND + 8, C.white)
	p:twinkle(60, GROUND + 4, C.gold)
end

BUILDINGS.walls = function(p)
	p:wall(0, 120, GROUND, 28, C.stone)
	for row = 0, 2 do
		for index = 0, 6 do
			p:rect(index * 18 + (row % 2) * 9, GROUND - 24 + row * 8, 1, 6, C.stoneDark)
		end
	end
	p:gate(60, GROUND, 16, 18)
	p:flag(60, GROUND - 48, C.banner)
	p:rect(30, GROUND - 22, 2, 8, C.woodDark)
	p:window(29, GROUND - 26, 4, 4)
	p:rect(88, GROUND - 22, 2, 8, C.woodDark)
	p:window(87, GROUND - 26, 4, 4)
end

BUILDINGS.towers = function(p)
	p:wall(0, 120, GROUND, 14, C.stoneDark)
	p:tower(34, GROUND, 18, 46, C.stone, { roof = C.roofRed, flag = C.banner })
	p:tower(92, GROUND, 14, 34, C.stone, {})
	-- Arrows flying from the tower.
	local arrows = {}
	for index = 1, 2 do
		local arrow = p:rect(0, 0, 10, 1.5, C.woodDark)
		local tip = p:rect(9, -1, 3, 3, C.iron, nil, arrow)
		tip.Rotation = 45
		tip.ZIndex = arrow.ZIndex
		arrows[index] = arrow
	end
	p:add(function(t)
		for index, arrow in arrows do
			local phase = (t * 0.6 + index * 0.5) % 1
			arrow.Position = UDim2.fromOffset(40 + phase * 90, 26 + phase * phase * 20 - phase * 6)
			arrow.Rotation = -10 + phase * 30
			arrow.BackgroundTransparency = if phase > 0.85 then 1 else 0
		end
	end)
end

---------------------------------------------------------------------------
-- Holdings
---------------------------------------------------------------------------

local HOLDINGS = {}

HOLDINGS.field = function(p)
	p:hall(100, GROUND - 2, 22, 14, C.wood, C.thatch)
	for row = 0, 2 do
		for index = 0, 11 do
			local x = 4 + index * 7 + row * 3
			local base = GROUND + 2 + row * 5
			local stalk = p:rect(x, base - 16, 1.5, 16, Color3.fromRGB(176, 156, 72))
			local head = p:rect(-1.5, -3, 4.5, 7, C.thatch, 2, stalk)
			head.ZIndex = stalk.ZIndex
			p:sway(stalk, 8, 1.6)
		end
	end
	-- A scarecrow.
	p:rect(92, GROUND - 26, 2, 24, C.woodDark)
	p:rect(84, GROUND - 22, 18, 2, C.woodDark)
	p:dot(93, GROUND - 28, 6, 6, C.thatch, 0.5)
end

HOLDINGS.mill = function(p)
	local water = p:rect(0, GROUND - 2, 120, 16, Color3.fromRGB(70, 130, 190))
	shade(water, 0.7)
	p:hall(42, GROUND - 2, 40, 30, C.stoneLight, C.thatch)
	-- The water wheel turns.
	local hub = p:pivot(78, GROUND - 10)
	for index = 0, 3 do
		local spoke = p:rect(-13, -1, 26, 2, C.woodDark, nil, hub)
		spoke.Position = UDim2.fromOffset(-12, 0)
		spoke.Rotation = index * 45
		spoke.ZIndex = hub.ZIndex + 1
	end
	local rim = p:dot(78, GROUND - 10, 26, 26, C.wood, 0.5)
	rim.BackgroundTransparency = 0.55
	p:add(function(t)
		hub.Rotation = (t * 40) % 360
	end)
	p:twinkle(96, GROUND + 4, C.white)
	p:twinkle(14, GROUND + 8, C.white)
end

HOLDINGS.tavern = function(p)
	p:rect(60, GROUND - 46, 5, 12, C.stoneDark)
	p:smoke(62, GROUND - 48)
	p:hall(54, GROUND, 52, 26, C.wood, C.roofRed)
	p:window(36, GROUND - 14, 5, 5)
	p:window(68, GROUND - 14, 5, 5)
	-- A sign swinging on its bracket.
	p:rect(84, GROUND - 24, 14, 2, C.woodDark)
	local sign = p:rect(88, GROUND - 22, 10, 8, C.thatch, 1)
	sign.AnchorPoint = Vector2.new(0.5, 0)
	sign.Position = UDim2.fromOffset(93, GROUND - 22)
	p:rect(2, 2, 6, 4, C.banner, 1, sign).ZIndex = sign.ZIndex + 1
	p:sway(sign, 10, 2.2)
	-- Barrels.
	p:rect(100, GROUND - 10, 8, 10, C.wood, 2)
	p:rect(109, GROUND - 10, 8, 10, C.wood, 2)
end

HOLDINGS.smithy = function(p)
	p:rect(26, GROUND - 44, 6, 16, C.stoneDark)
	p:smoke(29, GROUND - 46)
	p:hall(36, GROUND, 44, 24, C.stone, C.woodDark)
	local forge = p:rect(24, GROUND - 12, 16, 10, C.glow, 3)
	p:add(function(t)
		forge.BackgroundTransparency = 0.1 + 0.4 * math.abs(math.sin(t * 7) * math.sin(t * 2.9))
	end)
	-- Anvil and a hammer striking with sparks.
	p:rect(78, GROUND - 6, 6, 6, C.dark)
	p:rect(72, GROUND - 10, 18, 4, C.iron, 1)
	local pivot = p:pivot(96, GROUND - 14)
	local handle = p:rect(-14, -1, 16, 2, C.wood, nil, pivot)
	handle.ZIndex = pivot.ZIndex + 1
	local head = p:rect(-17, -3, 5, 6, C.iron, 1, pivot)
	head.ZIndex = pivot.ZIndex + 1
	local sparks = {}
	for index = 1, 3 do
		sparks[index] = p:dot(80, GROUND - 12, 2, 2, C.gold)
	end
	p:add(function(t)
		local swing = (t * 1.5) % 1
		pivot.Rotation = if swing < 0.7 then -40 + swing / 0.7 * 40 else -(swing - 0.7) / 0.3 * 40
		for index, spark in sparks do
			local phase = swing * 3 - 0.1 * index
			spark.BackgroundTransparency = if swing < 0.1 or swing > 0.4 then 1 else 0
			spark.Position = UDim2.fromOffset(80 + (index - 2) * 6 * phase, GROUND - 12 - phase * 8)
		end
	end)
end

HOLDINGS.quarry = BUILDINGS.quarry

HOLDINGS.tollbridge = function(p)
	local water = p:rect(0, GROUND - 4, 120, 18, Color3.fromRGB(70, 130, 190))
	shade(water, 0.7)
	-- The bridge on two arches.
	p:rect(0, GROUND - 14, 120, 6, C.stone)
	p:rect(0, GROUND - 16, 120, 2, C.stoneDark)
	for _, x in { 26, 70 } do
		p:rect(x, GROUND - 8, 24, 12, C.stoneDark, 8)
	end
	p:tower(96, GROUND - 14, 16, 26, C.stone, { roof = C.roofBlue, flag = C.banner })
	p:rect(102, GROUND - 22, 2, 8, C.woodDark)
	-- The toll bar lifts and falls.
	local bar = p:pivot(86, GROUND - 22)
	local arm = p:rect(-32, -1, 32, 2.5, C.banner, nil, bar)
	arm.ZIndex = bar.ZIndex + 1
	p:add(function(t)
		local phase = (t * 0.4) % 1
		bar.Rotation = if phase < 0.5 then 0 elseif phase < 0.6 then (phase - 0.5) * 10 * 50 elseif phase < 0.9 then 50 else (1 - phase) * 10 * 50
	end)
	-- A cart rolling across.
	local cart = p:rect(0, GROUND - 22, 12, 6, C.wood, 1)
	p:add(function(t)
		local phase = (t * 0.4) % 1
		local x = if phase < 0.5 then 10 + phase * 2 * 40 elseif phase < 0.6 then 50 else 50 + (phase - 0.6) / 0.4 * 80
		cart.Position = UDim2.fromOffset(x, GROUND - 22)
		cart.Visible = x < 112
	end)
end

HOLDINGS.markethall = function(p)
	p:hall(60, GROUND, 56, 28, C.stoneLight, C.roofBlue)
	p:flag(60, GROUND - 62, C.banner)
	-- Stalls with striped awnings.
	for index, color in { C.banner, C.gold, Color3.fromRGB(70, 130, 90) } do
		local x = 4 + (index - 1) * 14
		if index == 3 then
			x = 96
		end
		p:rect(x, GROUND - 10, 12, 10, C.wood, 1)
		local awning = p:rect(x - 1, GROUND - 14, 14, 5, color, 1)
		shade(awning, 0.75)
	end
	p:twinkle(14, GROUND - 4, C.gold)
	p:twinkle(102, GROUND - 4, C.white)
end

HOLDINGS.glassworks = function(p)
	p:rect(40, GROUND - 52, 8, 26, C.stoneDark)
	p:smoke(44, GROUND - 54)
	local kiln = p:dot(44, GROUND - 14, 46, 36, C.stone, 0.5)
	shade(kiln, 0.7)
	local mouth = p:rect(36, GROUND - 14, 16, 12, C.glow, 6)
	p:add(function(t)
		mouth.BackgroundTransparency = 0.05 + 0.35 * math.abs(math.sin(t * 5))
	end)
	-- Coloured bottles on a shelf, glinting.
	p:rect(74, GROUND - 16, 40, 3, C.woodDark)
	for index, color in { Color3.fromRGB(90, 170, 220), Color3.fromRGB(110, 200, 120), Color3.fromRGB(220, 120, 200), Color3.fromRGB(240, 200, 90) } do
		local x = 76 + (index - 1) * 10
		local bottle = p:rect(x, GROUND - 28, 6, 12, color, 2)
		bottle.BackgroundTransparency = 0.15
		p:rect(x + 2, GROUND - 31, 2, 3, color)
	end
	p:twinkle(80, GROUND - 24, C.white)
	p:twinkle(100, GROUND - 22, C.white)
end

HOLDINGS.mint = function(p)
	p:hall(60, GROUND, 64, 30, C.marble, C.gold)
	for x = 34, 86, 13 do
		p:rect(x, GROUND - 26, 4, 26, C.white)
	end
	p:rect(28, GROUND - 4, 64, 4, C.stoneLight)
	-- Coins tumbling into a pile.
	for index = 0, 3 do
		p:dot(14 + index * 6, GROUND - 2 - (index % 2) * 3, 7, 4, C.gold, 0.5)
	end
	local coin = p:dot(22, 10, 6, 6, C.gold, 0.5)
	p:add(function(t)
		local phase = (t * 0.8) % 1
		coin.Position = UDim2.fromOffset(22, 10 + phase * (GROUND - 14))
		coin.Size = UDim2.fromOffset(2 + math.abs(math.cos(t * 9)) * 5, 6)
	end)
	p:twinkle(100, 20, C.white)
	p:twinkle(60, 8, C.glow)
end

---------------------------------------------------------------------------
-- Making a picture
---------------------------------------------------------------------------

-- Uploaded art from Assets.luau, cropped to fill the holder. Nil when the
-- slot is empty (then the picture is drawn in code).
local function uploaded(holder: GuiObject, subgroup: string, key: any): Frame?
	local entry = Assets.get("Pictures", key, subgroup)
	if not entry then
		return nil
	end
	local canvas = Instance.new("Frame")
	canvas.Name = "Picture"
	canvas.Size = UDim2.fromScale(1, 1)
	canvas.BackgroundTransparency = 1
	canvas.ClipsDescendants = true
	canvas.ZIndex = holder.ZIndex
	canvas.Parent = holder
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = canvas
	Assets.show(canvas, entry, true)
	return canvas
end

-- Draws a picture inside `holder`, scaled to fit its height. gate() says
-- whether it should move right now (its page is open).
-- `width` above 120 widens the sky and ground; the picture stays centered
-- and the sides get a few trees.
-- width "fill" makes the canvas as wide as the holder's shape, so the
-- picture covers the whole holder with no empty sides; it is drawn again
-- when the holder changes shape.
local make
function make(holder: GuiObject, draw, background: boolean, gate: () -> boolean, width: (number | string)?): Frame
	local fill = width == "fill"
	local fullWidth = W
	if fill then
		local size = holder.AbsoluteSize
		if size.Y > 0 then
			fullWidth = math.max(W, math.floor(size.X / size.Y * H + 0.5))
		end
	elseif type(width) == "number" then
		fullWidth = width
	end
	local canvas = Instance.new("Frame")
	canvas.Name = "Picture"
	canvas.AnchorPoint = Vector2.new(0.5, 0.5)
	canvas.Position = UDim2.fromScale(0.5, 0.5)
	canvas.Size = UDim2.fromOffset(fullWidth, H)
	canvas.BackgroundTransparency = 1
	canvas.ClipsDescendants = true
	canvas.ZIndex = holder.ZIndex
	canvas.Parent = holder
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = canvas
	local scale = Instance.new("UIScale")
	scale.Parent = canvas
	local function fit()
		local size = holder.AbsoluteSize
		if size.Y > 0 then
			scale.Scale = math.min(size.X / fullWidth, size.Y / H)
		end
	end
	fit()
	local resized
	resized = holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if not canvas.Parent then
			resized:Disconnect()
			return
		end
		local size = holder.AbsoluteSize
		if fill and size.Y > 0 and math.abs(math.max(W, math.floor(size.X / size.Y * H + 0.5)) - fullWidth) > 3 then
			resized:Disconnect()
			canvas:Destroy()
			make(holder, draw, background, gate, width)
			return
		end
		fit()
	end)

	local pen = newPen(canvas)
	pen.z = holder.ZIndex
	if background then
		pen:sky(fullWidth)
		pen:ground(fullWidth)
	end
	if fullWidth > W then
		local side = (fullWidth - W) / 2
		for x = 10, side - 10, 22 do
			pen:tree(x, GROUND + 2, 18 + (x % 3) * 4)
			pen:tree(fullWidth - x, GROUND + 2, 18 + ((x + 1) % 3) * 4)
		end
		-- The main picture goes in a centered 120 wide frame on top.
		local middle = Instance.new("Frame")
		middle.Position = UDim2.fromOffset(side, 0)
		middle.Size = UDim2.fromOffset(W, H)
		middle.BackgroundTransparency = 1
		pen.z += 1
		middle.ZIndex = pen.z
		middle.Parent = canvas
		pen.root = middle
	end
	draw(pen)
	if #pen.steps > 0 then
		table.insert(movers, { root = canvas, gate = gate, steps = pen.steps })
		startLoop()
	end
	return canvas
end

-- A Keep level picture (1 = Timber Hall ... 8 = Sunspire Palace).
-- width is the canvas width (default 120, the height is always 80).
function Scenes.keep(holder: GuiObject, level: number, gate: () -> boolean, width: (number | string)?): Frame
	level = math.clamp(level, 1, #KEEPS)
	local art = uploaded(holder, "keep", level)
	if art then
		return art
	end
	local draw = KEEPS[level]
	return make(holder, draw, true, gate, width)
end

-- An Estate building picture, by building key. Nil for unknown keys.
function Scenes.building(holder: GuiObject, key: string, gate: () -> boolean, width: (number | string)?): Frame?
	local art = uploaded(holder, "building", key)
	if art then
		return art
	end
	local draw = BUILDINGS[key]
	if not draw then
		return nil
	end
	return make(holder, draw, true, gate, width)
end

-- A Holdings picture, by holding id. Nil for unknown ids.
function Scenes.holding(holder: GuiObject, id: string, gate: () -> boolean, width: (number | string)?): Frame?
	local art = uploaded(holder, "holding", id)
	if art then
		return art
	end
	local draw = HOLDINGS[id]
	if not draw then
		return nil
	end
	return make(holder, draw, true, gate, width)
end

return Scenes
