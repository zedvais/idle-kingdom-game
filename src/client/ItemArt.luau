-- Item pictures drawn with frames: every weapon, armor and mount, and the
-- chests. Each rarity has its own glow behind the item:
--   Common     none
--   Uncommon   a soft green halo
--   Rare       a blue halo that breathes
--   Epic       a purple halo with slow light rays
--   Legendary  a gold halo, more rays and sparkles
--   Mythic     a red halo, two ray wheels turning both ways, sparkles
--
-- Light on purpose: a picture is drawn once (ItemArt.set only redraws when
-- the item changes), and the glows move from one loop at 20 updates a second,
-- only while the picture is on screen.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local ItemArt = {}

local S = 60 -- every picture is drawn on a 60 x 60 canvas

local STEEL = Color3.fromRGB(196, 204, 214)
local STEEL_DARK = Color3.fromRGB(120, 128, 140)
local WOOD = Color3.fromRGB(122, 80, 46)
local WOOD_DARK = Color3.fromRGB(80, 52, 30)
local LEATHER = Color3.fromRGB(140, 96, 58)
local GOLD = Color3.fromRGB(240, 196, 80)
local INK = Color3.fromRGB(24, 18, 14)
local SILHOUETTE = Color3.fromRGB(92, 80, 70) -- undiscovered items

-- Accent colors for set pieces, by set id.
local SET_COLORS = {
	briar = Color3.fromRGB(90, 150, 70),
	saltreaver = Color3.fromRGB(70, 130, 170),
	cinderveil = Color3.fromRGB(220, 100, 50),
	ironbaron = Color3.fromRGB(150, 150, 160),
	hollowcrown = Color3.fromRGB(120, 70, 160),
}

---------------------------------------------------------------------------
-- Motion loop (glows), only for pictures that are on screen
---------------------------------------------------------------------------

local movers = {}
local started = false

local function onScreen(object: GuiObject): boolean
	local node: Instance? = object
	while node do
		if node:IsA("ScreenGui") then
			if not node.Enabled then
				return false
			end
			break
		elseif node:IsA("GuiObject") and not node.Visible then
			return false
		end
		node = node.Parent
	end
	if not node then
		return false
	end
	local camera = workspace.CurrentCamera
	local view = if camera then camera.ViewportSize else Vector2.new(1920, 1080)
	local p, s = object.AbsolutePosition, object.AbsoluteSize
	return p.X + s.X > 0 and p.Y + s.Y > 0 and p.X < view.X and p.Y < view.Y
end

local function start()
	if started then
		return
	end
	started = true
	local wait = 0
	RunService.Heartbeat:Connect(function(dt)
		wait += dt
		if wait < 0.05 then
			return
		end
		wait = 0
		local t = os.clock()
		for index = #movers, 1, -1 do
			local mover = movers[index]
			if not mover.root.Parent then
				table.remove(movers, index)
			elseif onScreen(mover.root) then
				for _, step in mover.steps do
					step(t)
				end
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Drawing helpers
---------------------------------------------------------------------------

local Pen = {}
Pen.__index = Pen

function Pen:box(x: number, y: number, w: number, h: number, color: Color3, radius: number?, parent: Instance?): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	f.BackgroundColor3 = if self.dark then SILHOUETTE else color
	f.BorderSizePixel = 0
	self.z += 1
	f.ZIndex = self.z
	f.Parent = parent or self.layer
	if radius then
		local c = Instance.new("UICorner")
		c.CornerRadius = if radius < 1 then UDim.new(radius, 0) else UDim.new(0, radius)
		c.Parent = f
	end
	return f
end

-- Shading: light on top, darker below.
local function shade(f: GuiObject, low: number?)
	local g = Instance.new("UIGradient")
	local l = low or 0.72
	g.Rotation = 90
	g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(l, l, l))
	g.Parent = f
end

-- A frame turned around the canvas center, for weapons drawn upright and
-- shown on the diagonal.
function Pen:tilt(angle: number): Frame
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromOffset(S / 2, S / 2)
	holder.Size = UDim2.fromOffset(S, S)
	holder.BackgroundTransparency = 1
	holder.Rotation = angle
	self.z += 1
	holder.ZIndex = self.z
	holder.Parent = self.layer
	self.layer = holder
	return holder
end

function Pen:diamond(x: number, y: number, size: number, color: Color3): Frame
	local d = self:box(x, y, size, size, color)
	d.Rotation = 45
	return d
end

---------------------------------------------------------------------------
-- Weapons (drawn upright: tip at the top, then tilted 45 degrees)
---------------------------------------------------------------------------

local function sword(p, accent)
	p:tilt(45)
	local blade = p:box(30, 22, 6, 34, STEEL, 2)
	shade(blade, 0.65)
	p:box(30, 22, 1.5, 30, Color3.new(1, 1, 1)).BackgroundTransparency = 0.4
	p:diamond(30, 5, 4.5, STEEL)
	p:box(30, 40, 20, 4, accent, 2)
	p:box(30, 47, 4, 10, LEATHER, 1)
	p:box(30, 53, 7, 7, accent, 0.5)
end

local function spear(p, accent)
	p:tilt(45)
	p:box(30, 34, 3.5, 46, WOOD, 1)
	local tip = p:diamond(30, 10, 9, STEEL)
	shade(tip, 0.6)
	p:box(30, 17, 6, 3, accent, 1)
	p:box(30, 56, 5, 4, accent, 1)
end

local function axe(p, accent)
	p:tilt(45)
	p:box(30, 32, 4, 48, WOOD, 1)
	local head = p:box(21, 15, 16, 18, STEEL, 0.5)
	shade(head, 0.62)
	p:box(27, 15, 6, 12, STEEL_DARK)
	p:box(30, 15, 6, 6, accent, 1)
	p:box(30, 52, 5, 6, LEATHER, 1)
end

local function mace(p, accent)
	p:tilt(45)
	p:box(30, 38, 4, 36, WOOD, 1)
	local head = p:box(30, 14, 16, 16, STEEL, 0.5)
	shade(head, 0.6)
	for _, spot in { { 30, 4 }, { 40, 14 }, { 20, 14 }, { 30, 24 } } do
		p:diamond(spot[1], spot[2], 5, STEEL_DARK)
	end
	p:box(30, 25, 7, 3, accent, 1)
	p:box(30, 53, 5, 7, LEATHER, 1)
end

local function hammer(p, accent)
	p:tilt(45)
	p:box(30, 36, 4, 42, WOOD, 1)
	local head = p:box(30, 14, 24, 12, STEEL, 2)
	shade(head, 0.6)
	p:box(30, 14, 6, 12, accent)
	p:box(30, 54, 5, 6, LEATHER, 1)
end

local function halberd(p, accent)
	p:tilt(45)
	p:box(30, 34, 3.5, 50, WOOD, 1)
	p:diamond(30, 6, 7, STEEL)
	local blade = p:box(22, 18, 12, 14, STEEL, 0.4)
	shade(blade, 0.62)
	p:box(37, 17, 7, 4, STEEL_DARK, 1)
	p:box(30, 25, 6, 3, accent, 1)
end

local function bow(p, accent)
	p:tilt(45)
	-- The limbs: short pieces along a curve.
	for index = 0, 10 do
		local a = math.rad(-70 + index * 14)
		local x = 22 + math.cos(a) * 16
		local y = 30 + math.sin(a) * 24
		local piece = p:box(x, y, 4, 7, WOOD)
		piece.Rotation = math.deg(a) + 90
	end
	p:box(18, 30, 1, 46, Color3.fromRGB(230, 220, 200))
	p:box(34, 30, 5, 8, accent, 1)
	-- An arrow on the string.
	local shaft = p:box(30, 30, 30, 1.5, WOOD_DARK)
	shaft.Position = UDim2.fromOffset(28, 30)
	p:diamond(44, 30, 4, STEEL)
end

local function staff(p, accent)
	p:tilt(45)
	p:box(30, 36, 4, 46, WOOD, 1)
	p:box(30, 14, 10, 4, GOLD, 1)
	local orb = p:box(30, 8, 12, 12, accent, 0.5)
	shade(orb, 0.55)
	p:box(28, 6, 3, 3, Color3.new(1, 1, 1), 0.5).BackgroundTransparency = 0.3
end

---------------------------------------------------------------------------
-- Armor (a torso seen from the front)
---------------------------------------------------------------------------

local function torso(p, color: Color3, accent: Color3)
	p:box(18, 18, 14, 12, color, 0.5)
	p:box(42, 18, 14, 12, color, 0.5)
	local body = p:box(30, 32, 26, 30, color, 4)
	shade(body, 0.7)
	p:box(30, 13, 10, 5, INK, 0.5)
	p:box(30, 42, 26, 4, accent)
	return body
end

local function tunic(p, accent)
	torso(p, LEATHER, accent)
	for y = 22, 36, 7 do
		p:box(30, y, 2, 3, WOOD_DARK)
	end
end

local function mail(p, accent)
	local body = torso(p, STEEL, accent)
	for row = 0, 3 do
		for col = 0, 3 do
			local ring = p:box(6 + col * 5 + (row % 2) * 2, 6 + row * 6, 3, 3, STEEL_DARK, 0.5, body)
			ring.ZIndex = body.ZIndex
		end
	end
end

local function plate(p, accent)
	local body = torso(p, STEEL, accent)
	p:box(30, 24, 22, 2, STEEL_DARK)
	p:box(30, 33, 22, 2, STEEL_DARK)
	local shine = p:box(23, 28, 4, 14, Color3.new(1, 1, 1), 2)
	shine.BackgroundTransparency = 0.5
	p:box(30, 21, 4, 4, accent, 1)
	return body
end

local function robe(p, accent)
	local hood = p:box(30, 14, 22, 20, accent, 0.5)
	shade(hood, 0.6)
	p:box(30, 17, 12, 12, INK, 0.5)
	local body = p:box(30, 40, 30, 32, accent, 6)
	shade(body, 0.6)
	p:box(30, 40, 4, 30, GOLD)
end

---------------------------------------------------------------------------
-- Mounts (a head in profile, facing left)
---------------------------------------------------------------------------

local function horseHead(p, color: Color3, mane: Color3, small: boolean?)
	-- Profile facing left: neck rising from the bottom right, head angled
	-- down to the muzzle at the left.
	local k = if small then 0.88 else 1
	local neck = p:box(40, 44, 17 * k, 32 * k, color, 5)
	neck.Rotation = -25
	shade(neck, 0.7)
	p:box(46, 38, 5, 28 * k, mane, 2).Rotation = -25
	p:box(33, 25, 16 * k, 16 * k, color, 0.5) -- cheek
	local head = p:box(25, 27, 30 * k, 14 * k, color, 6)
	head.Rotation = -35
	shade(head, 0.75)
	p:diamond(38, 13, 6 * k, color) -- ear
	p:box(30, 22, 3, 3, INK, 0.5) -- eye
	p:box(15, 34, 3, 2, INK, 1) -- nostril
	return head
end

local function horse(p, accent)
	horseHead(p, Color3.fromRGB(140, 92, 56), Color3.fromRGB(60, 40, 26))
	p:box(21, 30, 3, 15, accent, 1).Rotation = 55
end

local function pony(p, accent)
	horseHead(p, Color3.fromRGB(196, 170, 130), Color3.fromRGB(240, 230, 210), true)
	p:box(21, 30, 3, 13, accent, 1).Rotation = 55
end

local function mule(p, accent)
	horseHead(p, Color3.fromRGB(130, 120, 110), Color3.fromRGB(70, 64, 58), true)
	p:box(42, 9, 4, 13, Color3.fromRGB(130, 120, 110), 2).Rotation = 15
	p:box(21, 30, 3, 13, accent, 1).Rotation = 55
end

local function warhorse(p, accent)
	horseHead(p, Color3.fromRGB(70, 60, 56), Color3.fromRGB(30, 26, 24))
	local barding = p:box(27, 24, 16, 9, STEEL, 2)
	barding.Rotation = -35
	shade(barding, 0.6)
	p:box(42, 48, 16, 10, accent, 2).Rotation = -25
end

local function elk(p, accent)
	horseHead(p, Color3.fromRGB(150, 110, 70), Color3.fromRGB(110, 76, 46))
	local bone = Color3.fromRGB(230, 214, 180)
	p:box(44, 8, 20, 3, bone, 1).Rotation = -20 -- main beam
	for index = 0, 2 do
		p:box(38 + index * 6, 6 - index * 1, 2.5, 9, bone, 1).Rotation = 10
	end
	p:box(21, 30, 3, 15, accent, 1).Rotation = 55
end

local function griffin(p, accent)
	local wing = p:box(40, 34, 22, 30, Color3.fromRGB(200, 170, 110), 8)
	wing.Rotation = 25
	shade(wing, 0.7)
	for index = 0, 2 do
		p:box(44 + index * 3, 38 + index * 5, 18, 3, Color3.fromRGB(170, 140, 90), 1).Rotation = 25
	end
	local head = p:box(26, 24, 22, 22, Color3.fromRGB(240, 236, 226), 0.5)
	shade(head, 0.8)
	p:diamond(14, 28, 10, GOLD)
	p:box(24, 21, 4, 4, INK, 0.5)
	p:box(28, 36, 18, 3, accent, 1)
end

local function salamander(p, accent)
	local head = p:box(28, 30, 36, 18, accent, 8)
	shade(head, 0.65)
	p:box(22, 26, 5, 5, Color3.fromRGB(255, 220, 90), 0.5)
	p:box(22, 26, 2, 4, INK, 1)
	p:box(12, 34, 10, 2, INK, 1)
	for index = 0, 3 do
		p:diamond(32 + index * 6, 21, 5, Color3.fromRGB(250, 170, 60))
	end
end

local function nightmare(p, accent)
	horseHead(p, Color3.fromRGB(36, 30, 44), accent)
	p:box(26, 21, 4, 4, Color3.fromRGB(255, 80, 80), 0.5)
	p:diamond(30, 34, 5, accent)
end

-- Which drawing a name gets, by the words in it.
local function pick(slot: string, name: string)
	local lower = string.lower(name)
	local function has(word: string): boolean
		return string.find(lower, word, 1, true) ~= nil
	end
	if slot == "Weapon" then
		if has("bow") then
			return bow
		elseif has("staff") then
			return staff
		elseif has("halberd") then
			return halberd
		elseif has("hammer") then
			return hammer
		elseif has("axe") then
			return axe
		elseif has("mace") then
			return mace
		elseif has("spear") then
			return spear
		end
		return sword
	elseif slot == "Armor" then
		if has("robe") or has("hood") then
			return robe
		elseif has("plate") or has("harness") then
			return plate
		elseif has("chain") or has("mail") or has("hauberk") then
			return mail
		end
		return tunic
	end
	if has("griffin") then
		return griffin
	elseif has("elk") or has("stag") then
		return elk
	elseif has("salamander") then
		return salamander
	elseif has("nightmare") then
		return nightmare
	elseif has("mule") then
		return mule
	elseif has("pony") then
		return pony
	elseif has("war") or has("destrier") or has("charger") then
		return warhorse
	end
	return horse
end

---------------------------------------------------------------------------
-- Rarity glows
---------------------------------------------------------------------------

local function glow(p, rank: number, color: Color3)
	if rank <= 1 then
		return
	end
	local halo = p:box(30, 30, 54, 54, color, 0.5)
	halo.BackgroundTransparency = 0.72
	local soft = Instance.new("UIGradient")
	soft.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 0.6),
	})
	soft.Parent = halo
	if rank >= 3 then
		table.insert(p.steps, function(t)
			halo.BackgroundTransparency = 0.55 + 0.25 * (math.sin(t * 2.2) + 1) / 2
		end)
	end
	local function wheel(count: number, speed: number, transparency: number)
		local hub = p:box(30, 30, 2, 2, color)
		hub.BackgroundTransparency = 1
		for index = 1, count do
			local ray = p:box(1, 1, 5, 58, color, nil, hub)
			ray.Rotation = index * (180 / count)
			ray.BackgroundTransparency = transparency
			local fade = Instance.new("UIGradient")
			fade.Rotation = 90
			fade.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.2),
				NumberSequenceKeypoint.new(1, 1),
			})
			fade.Parent = ray
		end
		table.insert(p.steps, function(t)
			hub.Rotation = (t * speed) % 360
		end)
	end
	if rank >= 4 then
		wheel(if rank >= 5 then 6 else 4, 14, 0.55)
	end
	if rank >= 6 then
		wheel(5, -22, 0.65)
	end
	if rank >= 5 then
		for index, spot in { { 10, 12 }, { 50, 16 }, { 46, 50 }, { 12, 46 } } do
			if index <= rank - 3 then
				local star = p:diamond(spot[1], spot[2], 4, Color3.fromRGB(255, 250, 220))
				local seed = index * 1.7
				table.insert(p.steps, function(t)
					local v = (math.sin(t * 3 + seed) + 1) / 2
					star.BackgroundTransparency = 1 - v
					star.Size = UDim2.fromOffset(2 + v * 4, 2 + v * 4)
				end)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

local function canvasIn(holder: GuiObject): (Frame, any)
	local old = holder:FindFirstChild("ItemArt")
	if old then
		old:Destroy()
	end
	local canvas = Instance.new("Frame")
	canvas.Name = "ItemArt"
	canvas.AnchorPoint = Vector2.new(0.5, 0.5)
	canvas.Position = UDim2.fromScale(0.5, 0.5)
	canvas.Size = UDim2.fromOffset(S, S)
	canvas.BackgroundTransparency = 1
	canvas.ZIndex = holder.ZIndex
	canvas.Parent = holder
	local scale = Instance.new("UIScale")
	scale.Parent = canvas
	local function fit()
		local size = holder.AbsoluteSize
		if size.X > 0 then
			scale.Scale = math.min(size.X, size.Y) / S
		end
	end
	fit()
	holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	local pen = setmetatable({ layer = canvas, z = holder.ZIndex, steps = {}, dark = false }, Pen)
	return canvas, pen
end

-- Draws an item into `holder` (fills it, keeps it square).
-- item: { slot, name, rarity, set? }. hidden = true draws a dark
-- silhouette with no glow (not discovered yet).
function ItemArt.draw(holder: GuiObject, item, hidden: boolean?)
	local canvas, pen = canvasIn(holder)
	local rarity = GameConfig.getRarity(item.rarity or "Common")
	local rank = GameConfig.getRarityRank(rarity.id)
	if not hidden then
		glow(pen, rank, rarity.color)
	end
	pen.dark = hidden == true
	local accent = SET_COLORS[item.set or ""] or rarity.color
	local draw = pick(item.slot or "Weapon", item.name or "")
	draw(pen, accent)
	-- Royal Coffer items wear a small gold crown in the corner.
	if not hidden and GameConfig.GearPoolOf and GameConfig.GearPoolOf[item.name or ""] == "premium" then
		pen.layer = canvas
		pen:box(51, 11, 13, 5, GOLD, 1)
		for _, x in { 46, 51, 56 } do
			pen:diamond(x, 7, 4, GOLD)
		end
		pen:box(51, 11, 3, 3, Color3.fromRGB(220, 60, 70), 0.5)
	end
	if #pen.steps > 0 then
		table.insert(movers, { root = canvas, steps = pen.steps })
		start()
	end
	return canvas
end

-- Like draw, but does nothing when the holder already shows this item.
function ItemArt.set(holder: GuiObject, item, hidden: boolean?)
	local key = `{item.slot}|{item.name}|{item.rarity}|{item.set or ""}|{hidden == true}`
	if holder:GetAttribute("ItemArtKey") == key then
		return
	end
	holder:SetAttribute("ItemArtKey", key)
	ItemArt.draw(holder, item, hidden)
end

-- A chest: wood with bands and a lock. The glow follows `rarityId`; the
-- bands use `band` (default: the rarity color). `crown` adds a gold crown.
function ItemArt.chest(holder: GuiObject, rarityId: string, band: Color3?, crown: boolean?)
	local canvas, pen = canvasIn(holder)
	local rarity = GameConfig.getRarity(rarityId)
	local rank = GameConfig.getRarityRank(rarity.id)
	glow(pen, rank, rarity.color)
	local bandColor = band or rarity.color
	local body = pen:box(30, 38, 44, 26, WOOD, 4)
	shade(body, 0.7)
	local lid = pen:box(30, 22, 46, 14, WOOD, 6)
	shade(lid, 0.75)
	for _, x in { 16, 44 } do
		pen:box(x, 32, 5, 40, bandColor, 1)
	end
	pen:box(30, 29, 46, 3, bandColor)
	local lock = pen:box(30, 33, 9, 10, GOLD, 2)
	shade(lock, 0.6)
	pen:box(30, 34, 2, 4, INK, 1)
	if crown then
		pen:box(30, 11, 16, 5, GOLD, 1)
		for _, x in { 24, 30, 36 } do
			pen:diamond(x, 7, 5, GOLD)
		end
		pen:box(30, 11, 3, 3, Color3.fromRGB(220, 60, 70), 0.5)
	end
	if #pen.steps > 0 then
		table.insert(movers, { root = canvas, steps = pen.steps })
		start()
	end
	return canvas
end

return ItemArt
