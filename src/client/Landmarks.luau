-- The building drawn for each realm tier, made of frames and animated:
--   1 The Hamlets        thatched cottage and a windmill with turning sails
--   2 Greywatch Marches  stone watchtower with a waving banner
--   3 The Ember Wilds    forge with a glowing furnace and rising smoke
--   4 Iron Baronies      iron gatehouse with twin towers and flickering torches
--   5 The Crownlands     golden palace with domes, spires and sparkles
-- Landmarks.draw(holder, tier) fills `holder` (any size); call it again to
-- swap the tier. Assets.Pictures.realm[tier] replaces the drawing when set.

local RunService = game:GetService("RunService")
local Assets = require(script.Parent:WaitForChild("Assets"))

local Landmarks = {}

local movers = {} -- { object, kind, base, phase, extra }
local running = false

local function visible(object: GuiObject): boolean
	local node: Instance? = object
	while node and node:IsA("GuiObject") do
		if not node.Visible then
			return false
		end
		node = node.Parent
	end
	if node and node:IsA("ScreenGui") then
		return node.Enabled
	end
	return node ~= nil
end

local function start()
	if running then
		return
	end
	running = true
	local t = 0
	local checkAt = 0
	local shown = {}
	RunService.RenderStepped:Connect(function(dt)
		t += dt
		-- which drawings are on screen, checked a few times a second
		if t >= checkAt then
			checkAt = t + 0.25
			table.clear(shown)
			for index = #movers, 1, -1 do
				local entry = movers[index]
				if not entry.object.Parent then
					table.remove(movers, index)
				elseif visible(entry.object) then
					table.insert(shown, entry)
				end
			end
		end
		for _, entry in shown do
			local object = entry.object
			local phase = t + entry.phase
			if entry.kind == "spin" then
				object.Rotation = (phase * 40) % 360
			elseif entry.kind == "wave" then
				object.Rotation = math.sin(phase * 3) * 8
			elseif entry.kind == "glow" then
				local wave = (math.sin(phase * 4) + 1) / 2
				object.BackgroundColor3 = entry.base:Lerp(Color3.fromRGB(255, 230, 120), wave * 0.6)
			elseif entry.kind == "flicker" then
				object.BackgroundTransparency = 0.1 + math.abs(math.sin(phase * 9) * math.sin(phase * 5.3)) * 0.5
			elseif entry.kind == "smoke" then
				local cycle = (phase * 0.35) % 1
				object.Position = entry.base + UDim2.fromScale(math.sin(cycle * 6) * 0.03, -cycle * 0.35)
				object.BackgroundTransparency = 0.35 + cycle * 0.65
				local size = 0.06 + cycle * 0.08
				object.Size = UDim2.fromScale(size, size * entry.extra)
			elseif entry.kind == "twinkle" then
				local wave = math.max(0, math.sin(phase * 2.2))
				object.TextTransparency = 1 - wave
				object.Rotation = phase * 30
			end
		end
	end)
end

local function move(object: GuiObject, kind: string, extra: number?)
	table.insert(movers, { object = object, kind = kind, base = if kind == "glow" then object.BackgroundColor3 else object.Position, phase = math.random() * 6, extra = extra or 1 })
	start()
end

-- A box in scale coordinates (x, y = top-left, 0 to 1 of the holder).
local function box(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, z: number, round: number?): Frame
	local frame = Instance.new("Frame")
	frame.Position = UDim2.fromScale(x, y)
	frame.Size = UDim2.fromScale(w, h)
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.ZIndex = z
	if round then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(round, 0)
		corner.Parent = frame
	end
	frame.Parent = parent
	return frame
end

-- A pointed roof: a turned square whose lower half hides behind the wall.
local function roof(parent: Instance, cx: number, y: number, w: number, color: Color3, z: number, aspect: number)
	local size = w * 0.72
	local frame = box(parent, cx - size / 2, y - size * aspect / 2, size, size * aspect, color, z)
	frame.Rotation = 45
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 1
	ratio.Parent = frame
	return frame
end

local function shade(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

local function hamlet(root: Frame, z: number, aspect: number)
	-- windmill on the left
	local tower = box(root, 0.12, 0.3, 0.16, 0.6, Color3.fromRGB(200, 180, 140), z + 2, 0.15)
	box(tower, 0.35, 0.7, 0.3, 0.3, Color3.fromRGB(90, 60, 40), z + 3, 0.4)
	roof(root, 0.2, 0.3, 0.2, Color3.fromRGB(120, 70, 50), z + 1, aspect)
	local hub = box(root, 0.2 - 0.02, 0.3 - 0.02 * aspect, 0.04, 0.04 * aspect, Color3.fromRGB(80, 50, 30), z + 6, 0.5)
	local sails = box(root, 0.2 - 0.17, 0.3 - 0.17 * aspect, 0.34, 0.34 * aspect, Color3.new(1, 1, 1), z + 5)
	sails.BackgroundTransparency = 1
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 1
	ratio.Parent = sails
	for _, rotation in { 0, 90 } do
		local blade = box(sails, 0.45, 0, 0.1, 1, Color3.fromRGB(240, 230, 210), z + 5)
		blade.Rotation = rotation
	end
	move(sails, "spin")
	local _ = hub
	-- cottage on the right
	box(root, 0.42, 0.52, 0.46, 0.38, Color3.fromRGB(236, 220, 180), z + 2, 0.05)
	roof(root, 0.65, 0.52, 0.52, Color3.fromRGB(190, 150, 70), z + 1, aspect)
	box(root, 0.6, 0.68, 0.1, 0.22, Color3.fromRGB(110, 70, 40), z + 3, 0.2)
	local window = box(root, 0.47, 0.6, 0.08, 0.1, Color3.fromRGB(255, 220, 120), z + 3, 0.1)
	move(window, "glow")
	box(root, 0.76, 0.6, 0.08, 0.1, Color3.fromRGB(255, 220, 120), z + 3, 0.1)
	-- fence
	for index = 0, 8 do
		box(root, 0.04 + index * 0.105, 0.86, 0.025, 0.1, Color3.fromRGB(140, 100, 60), z + 4)
	end
	box(root, 0.04, 0.89, 0.9, 0.02, Color3.fromRGB(140, 100, 60), z + 4)
end

local function marches(root: Frame, z: number, aspect: number)
	local stone = Color3.fromRGB(150, 150, 155)
	-- curtain wall
	box(root, 0.06, 0.62, 0.88, 0.3, shade(stone, 0.15), z + 1)
	for index = 0, 7 do
		box(root, 0.06 + index * 0.115, 0.57, 0.07, 0.06, shade(stone, 0.15), z + 1)
	end
	-- the tower
	box(root, 0.36, 0.2, 0.28, 0.72, stone, z + 2)
	for index = 0, 3 do
		box(root, 0.34 + index * 0.085, 0.14, 0.06, 0.07, stone, z + 2)
	end
	box(root, 0.46, 0.34, 0.035, 0.1, Color3.fromRGB(30, 30, 40), z + 3, 0.5)
	box(root, 0.52, 0.5, 0.035, 0.1, Color3.fromRGB(30, 30, 40), z + 3, 0.5)
	box(root, 0.44, 0.74, 0.12, 0.18, Color3.fromRGB(70, 50, 35), z + 3, 0.3)
	-- banner on a pole
	box(root, 0.495, 0.0, 0.012, 0.16, Color3.fromRGB(90, 70, 50), z + 3)
	local flag = box(root, 0.505, 0.01, 0.13, 0.07, Color3.fromRGB(170, 40, 40), z + 3)
	flag.AnchorPoint = Vector2.new(0, 0)
	move(flag, "wave")
	-- stones on the wall
	for index = 0, 5 do
		box(root, 0.1 + index * 0.14, 0.72 + (index % 2) * 0.08, 0.06, 0.03, shade(stone, 0.3), z + 2)
	end
	local _ = aspect
end

local function ember(root: Frame, z: number, aspect: number)
	local wall = Color3.fromRGB(70, 50, 45)
	-- chimney and smoke
	box(root, 0.64, 0.12, 0.1, 0.4, shade(wall, 0.2), z + 1)
	for index = 1, 4 do
		local puff = box(root, 0.66, 0.1, 0.06, 0.06 * aspect, Color3.fromRGB(120, 110, 110), z + 6, 0.5)
		move(puff, "smoke", aspect)
		local entry = movers[#movers]
		entry.phase = index * 0.7
	end
	-- forge house
	box(root, 0.14, 0.44, 0.72, 0.48, wall, z + 2, 0.04)
	roof(root, 0.5, 0.44, 0.76, Color3.fromRGB(50, 35, 30), z + 1, aspect)
	local furnace = box(root, 0.24, 0.6, 0.22, 0.32, Color3.fromRGB(255, 120, 40), z + 3, 0.35)
	move(furnace, "glow")
	box(root, 0.24, 0.6, 0.22, 0.06, shade(wall, 0.4), z + 4)
	-- anvil
	box(root, 0.58, 0.72, 0.18, 0.06, Color3.fromRGB(40, 40, 46), z + 4, 0.2)
	box(root, 0.63, 0.78, 0.08, 0.1, Color3.fromRGB(40, 40, 46), z + 4)
	-- lava cracks on the ground
	for index = 0, 3 do
		local crack = box(root, 0.08 + index * 0.24, 0.94, 0.14, 0.025, Color3.fromRGB(255, 140, 40), z + 4, 0.5)
		move(crack, "glow")
	end
end

local function iron(root: Frame, z: number, aspect: number)
	local metal = Color3.fromRGB(96, 100, 116)
	-- towers
	for _, x in { 0.06, 0.7 } do
		box(root, x, 0.22, 0.24, 0.7, metal, z + 2)
		for index = 0, 2 do
			box(root, x - 0.01 + index * 0.095, 0.16, 0.06, 0.07, metal, z + 2)
		end
		box(root, x + 0.09, 0.36, 0.05, 0.12, Color3.fromRGB(25, 25, 35), z + 3, 0.5)
		local torch = box(root, x + 0.08, 0.58, 0.07, 0.07 * aspect, Color3.fromRGB(255, 160, 50), z + 4, 0.5)
		move(torch, "flicker")
	end
	-- gatehouse and gate
	box(root, 0.28, 0.36, 0.44, 0.56, shade(metal, 0.15), z + 1)
	box(root, 0.36, 0.56, 0.28, 0.36, Color3.fromRGB(20, 20, 26), z + 2, 0.45)
	for index = 0, 4 do
		box(root, 0.38 + index * 0.055, 0.56, 0.015, 0.36, Color3.fromRGB(150, 150, 160), z + 3)
	end
	for index = 0, 2 do
		box(root, 0.36, 0.64 + index * 0.09, 0.28, 0.012, Color3.fromRGB(150, 150, 160), z + 3)
	end
	-- rivets
	for index = 0, 5 do
		box(root, 0.31 + index * 0.07, 0.42, 0.025, 0.025 * aspect, Color3.fromRGB(180, 180, 190), z + 2, 0.5)
	end
end

local function crown(root: Frame, z: number, aspect: number)
	local white = Color3.fromRGB(240, 232, 214)
	local gold = Color3.fromRGB(230, 190, 70)
	-- spires
	for _, x in { 0.08, 0.78 } do
		box(root, x, 0.34, 0.14, 0.58, white, z + 2)
		roof(root, x + 0.07, 0.34, 0.2, gold, z + 1, aspect)
		box(root, x + 0.045, 0.5, 0.05, 0.1, Color3.fromRGB(80, 120, 200), z + 3, 0.5)
	end
	-- palace and dome
	box(root, 0.22, 0.5, 0.56, 0.42, white, z + 2, 0.03)
	local dome = box(root, 0.33, 0.24, 0.34, 0.34 * aspect, gold, z + 1, 0.5)
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 1
	ratio.Parent = dome
	box(root, 0.495, 0.1, 0.01, 0.16, gold, z + 1)
	box(root, 0.22, 0.5, 0.56, 0.04, gold, z + 3)
	box(root, 0.44, 0.7, 0.12, 0.22, Color3.fromRGB(150, 60, 60), z + 3, 0.4)
	for index = 0, 3 do
		box(root, 0.27 + index * (if index >= 2 then 0.15 else 0.1), 0.62, 0.05, 0.12, Color3.fromRGB(80, 120, 200), z + 3, 0.4)
	end
	-- sparkles
	for index = 1, 4 do
		local star = Instance.new("TextLabel")
		star.BackgroundTransparency = 1
		star.Text = "\u{2726}"
		star.TextScaled = true
		star.TextColor3 = Color3.fromRGB(255, 240, 160)
		star.Size = UDim2.fromScale(0.1, 0.1 * aspect)
		star.Position = UDim2.fromScale(({ 0.1, 0.3, 0.62, 0.84 })[index], ({ 0.18, 0.06, 0.1, 0.22 })[index])
		star.ZIndex = z + 6
		star.Parent = root
		move(star, "twinkle")
	end
end

local DRAW = { hamlet, marches, ember, iron, crown }

function Landmarks.draw(holder: GuiObject, tier: number)
	if holder:GetAttribute("Tier") == tier then
		return
	end
	holder:SetAttribute("Tier", tier)
	if not holder:GetAttribute("Watched") then
		-- drawn before it had a size (page hidden): draw again once sized
		holder:SetAttribute("Watched", true)
		local drawnAt = holder.AbsoluteSize
		holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			local size = holder.AbsoluteSize
			if size.X > 0 and size.Y > 0 and (math.abs(size.X - drawnAt.X) > 8 or math.abs(size.Y - drawnAt.Y) > 8) then
				drawnAt = size
				local current = holder:GetAttribute("Tier")
				holder:SetAttribute("Tier", nil)
				Landmarks.draw(holder, current)
			end
		end)
	end
	local old = holder:FindFirstChild("Landmark")
	if old then
		old:Destroy()
	end
	local entry = Assets.get("Pictures", tier, "realm")
	local root = Instance.new("Frame")
	root.Name = "Landmark"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.ZIndex = holder.ZIndex
	root.Parent = holder
	if entry then
		Assets.show(root, entry, false)
		return
	end
	-- Shapes are laid out for a square; aspect keeps circles round when
	-- the holder is wider than tall.
	local size = holder.AbsoluteSize
	local aspect = if size.Y > 0 then math.clamp(size.X / size.Y, 0.5, 2) else 1
	DRAW[math.clamp(tier, 1, #DRAW)](root, holder.ZIndex, aspect)
end

return Landmarks
