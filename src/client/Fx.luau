-- One-off effects the server asks for on the Fx remote:
--   gear     a chest opening (crate = true) or a small drop card
--   soldier  a recruit reveal from a single roll
--   hit      damage numbers on a foe fight
--   levelup  a banner with falling gold
-- Everything is drawn with frames and text, no images.

local Players = game:GetService("Players")

local Fx = {}

local Art
local GameConfig
local ItemArt -- item pictures (optional; falls back to emoji)
local layer: ScreenGui
local anchors = {} -- [name] = GuiObject, where damage numbers start

local function frame(parent: Instance, size: UDim2, position: UDim2, color: Color3, zindex: number): Frame
	local f = Instance.new("Frame")
	f.Size = size
	f.Position = position
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = zindex
	f.Parent = parent
	return f
end

local function text(parent: Instance, size: UDim2, position: UDim2, color: Color3, textSize: number, zindex: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = size
	label.Position = position
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.TextColor3 = color
	label.TextSize = textSize
	label.Font = Enum.Font.GothamBlack
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.3
	label.TextWrapped = true
	label.RichText = true
	label.ZIndex = zindex
	label.Parent = parent
	return label
end

local function rarityOf(id: string)
	local rank = GameConfig.getRarityRank(id)
	local rarity = GameConfig.Rarities[rank] or GameConfig.Rarities[1]
	return rarity, rank
end

---------------------------------------------------------------------------
-- Light rays that turn slowly behind a reveal
---------------------------------------------------------------------------

local function makeRays(parent: Instance, color: Color3, count: number, length: number, zindex: number): Frame
	local holder = frame(parent, UDim2.fromOffset(length, length), UDim2.fromScale(0.5, 0.5), color, zindex)
	holder.BackgroundTransparency = 1
	for index = 1, count do
		local ray = frame(holder, UDim2.fromOffset(18, length), UDim2.fromScale(0.5, 0.5), color, zindex)
		ray.Rotation = (index - 1) * (180 / count)
		ray.BackgroundTransparency = 0.35
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.35, 0.6),
			NumberSequenceKeypoint.new(0.5, 0.2),
			NumberSequenceKeypoint.new(0.65, 0.6),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = ray
	end
	task.spawn(function()
		while holder.Parent do
			holder.Rotation = 0
			local spin = Art.tween(holder, 12, { Rotation = 180 }, Enum.EasingStyle.Linear)
			spin.Completed:Wait()
		end
	end)
	return holder
end

-- Little squares that burst out from the middle.
local function sparks(parent: Instance, color: Color3, count: number, zindex: number)
	for _ = 1, count do
		local size = math.random(5, 11)
		local spark = frame(parent, UDim2.fromOffset(size, size), UDim2.fromScale(0.5, 0.5), color, zindex)
		spark.Rotation = math.random(0, 90)
		local angle = math.random() * math.pi * 2
		local distance = math.random(90, 220)
		Art.tween(spark, 0.7 + math.random() * 0.4, {
			Position = UDim2.new(0.5, math.cos(angle) * distance, 0.5, math.sin(angle) * distance),
			BackgroundTransparency = 1,
			Rotation = spark.Rotation + math.random(-180, 180),
		}, Enum.EasingStyle.Quart)
		task.delay(1.3, function()
			spark:Destroy()
		end)
	end
end

---------------------------------------------------------------------------
-- A chest, drawn with blocks
---------------------------------------------------------------------------

local function makeChest(parent: Instance, zindex: number, royal: boolean): (Frame, Frame)
	local wood = if royal then Color3.fromRGB(110, 34, 52) else Color3.fromRGB(120, 76, 40)
	local band = if royal then Color3.fromRGB(255, 214, 110) else Color3.fromRGB(200, 160, 80)
	local box = frame(parent, UDim2.fromOffset(150, 96), UDim2.fromScale(0.5, 0.56), wood, zindex)
	Art.corner(box, 8)
	Art.grain(box, 0)
	Art.stroke(box, Color3.fromRGB(30, 18, 10), 3, 0)
	for _, x in { 0.2, 0.8 } do
		local strap = frame(box, UDim2.new(0, 14, 1, 0), UDim2.fromScale(x, 0.5), band, zindex + 1)
		Art.gloss(strap, 1, 0.6)
	end
	local lock = frame(box, UDim2.fromOffset(26, 30), UDim2.new(0.5, 0, 0, 14), band, zindex + 2)
	Art.corner(lock, 5)
	Art.gloss(lock, 1, 0.55)
	Art.stroke(lock, Color3.fromRGB(30, 18, 10), 2, 0)
	local hole = frame(lock, UDim2.fromOffset(6, 10), UDim2.fromScale(0.5, 0.55), Color3.fromRGB(30, 18, 10), zindex + 3)
	Art.corner(hole, 3)

	local lid = frame(parent, UDim2.fromOffset(160, 44), UDim2.new(0.5, 0, 0.56, -66), wood, zindex + 4)
	Art.corner(lid, 14)
	Art.gloss(lid, 1, 0.7)
	Art.stroke(lid, Color3.fromRGB(30, 18, 10), 3, 0)
	for _, x in { 0.2, 0.8 } do
		local strap = frame(lid, UDim2.new(0, 14, 1, 0), UDim2.fromScale(x, 0.5), band, zindex + 5)
		Art.gloss(strap, 1, 0.6)
	end
	return box, lid
end

-- A banner for recruits: a shield with crossed swords.
local function makeShield(parent: Instance, zindex: number, color: Color3): (Frame, Frame)
	local shield = frame(parent, UDim2.fromOffset(120, 140), UDim2.fromScale(0.5, 0.5), Color3.fromRGB(70, 46, 30), zindex)
	local shape = Instance.new("UICorner")
	shape.CornerRadius = UDim.new(0.35, 0)
	shape.Parent = shield
	Art.gloss(shield, 1, 0.6)
	Art.stroke(shield, color, 4, 0)
	local glyph = Art.icon(shield, Art.Icons.Warband, 64, UDim2.fromScale(0.5, 0.5))
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.ZIndex = zindex + 1
	return shield, shield
end

---------------------------------------------------------------------------
-- Reveal: a chest or a recruit, then the prize card
---------------------------------------------------------------------------

local queue = {}
local showing = false

-- An item picture in a square holder: drawn art when ItemArt is loaded.
local function prizePicture(parent: Instance, item, size: number, position: UDim2, zindex: number): Frame
	local holder = frame(parent, UDim2.fromOffset(size, size), position, Color3.new(), zindex)
	holder.BackgroundTransparency = 1
	if ItemArt and item.slot then
		ItemArt.draw(holder, item)
	else
		local glyph = if item.what == "soldier" then Art.Icons.soldier else (Art.Icons[item.slot or ""] or Art.Icons.chest)
		local icon = Art.icon(holder, glyph, math.floor(size * 0.8), UDim2.fromScale(0.5, 0.5))
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.ZIndex = zindex + 1
	end
	return holder
end

local function playReveal(info)
	local rarity, rank = rarityOf(info.rarity or "Common")
	local color = rarity.color
	local Z = 50

	local shade = Instance.new("TextButton")
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 1
	shade.AutoButtonColor = false
	shade.Text = ""
	shade.ZIndex = Z
	shade.Parent = layer
	Art.tween(shade, 0.25, { BackgroundTransparency = 0.35 })

	local stage = frame(shade, UDim2.fromOffset(520, 460), UDim2.fromScale(0.5, 0.5), Color3.new(), Z + 1)
	stage.BackgroundTransparency = 1
	local scale = Instance.new("UIScale")
	local camera = workspace.CurrentCamera
	local view = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	scale.Scale = math.clamp(math.min(view.X / 560, view.Y / 500), 0.5, 1)
	scale.Parent = stage

	local glow = frame(stage, UDim2.fromOffset(60, 60), UDim2.fromScale(0.5, 0.5), color, Z + 1)
	Art.corner(glow, 999)
	glow.BackgroundTransparency = 0.6

	local isSoldier = info.what == "soldier"
	local body, lid
	if isSoldier then
		body, lid = makeShield(stage, Z + 3, Color3.fromRGB(200, 160, 80))
	else
		body, lid = makeChest(stage, Z + 3, info.royal == true)
	end

	-- Shake: longer and wilder for rarer prizes.
	local shakes = 2 + math.min(rank, 6)
	for index = 1, shakes do
		local angle = (if index % 2 == 0 then 1 else -1) * (4 + index * 1.5)
		Art.tween(body, 0.07, { Rotation = angle })
		if lid ~= body then
			Art.tween(lid, 0.07, { Rotation = angle })
		end
		Art.tween(glow, 0.07, {
			Size = UDim2.fromOffset(60 + index * 30, 60 + index * 30),
			BackgroundTransparency = 0.6 - index * 0.04,
		})
		task.wait(0.09)
	end
	Art.tween(body, 0.05, { Rotation = 0 })

	-- Burst open.
	local flash = frame(shade, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), Color3.new(1, 1, 1), Z + 20)
	flash.BackgroundTransparency = if rank >= 5 then 0.1 else 0.6
	Art.tween(flash, 0.5, { BackgroundTransparency = 1 })
	task.delay(0.6, function()
		flash:Destroy()
	end)
	if lid ~= body then
		Art.tween(lid, 0.45, { Position = lid.Position + UDim2.fromOffset(40, -220), Rotation = 50, BackgroundTransparency = 1 })
		for _, child in lid:GetDescendants() do
			if child:IsA("Frame") then
				Art.tween(child, 0.3, { BackgroundTransparency = 1 })
			elseif child:IsA("UIStroke") then
				Art.tween(child, 0.3, { Transparency = 1 })
			end
		end
	end
	Art.tween(body, 0.35, { Position = body.Position + UDim2.fromOffset(0, 40) })
	Art.tween(glow, 0.4, { Size = UDim2.fromOffset(360, 360), BackgroundTransparency = 0.75 })
	local rays = makeRays(stage, color, 4 + rank, 480, Z + 2)
	sparks(stage, color, 10 + rank * 4, Z + 6)
	task.wait(0.25)

	-- The prize card: one prize, or a grid of up to ten (Open 10).
	local many = type(info.items) == "table" and #info.items > 1
	local cardSize = if many then UDim2.fromOffset(520, 300) else UDim2.fromOffset(320, 196)
	local card = frame(stage, cardSize, UDim2.fromScale(0.5, 0.5), Color3.fromRGB(34, 26, 20), Z + 10)
	Art.corner(card, 12)
	Art.gloss(card, 1, 0.8)
	Art.stroke(card, color, 3, 0)
	local cardScale = Instance.new("UIScale")
	cardScale.Scale = 0.3
	cardScale.Parent = card
	Art.tween(cardScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)

	local ribbon = frame(card, UDim2.new(1, 0, 0, 30), UDim2.new(0.5, 0, 0, 15), color, Z + 11)
	Art.corner(ribbon, 12)
	Art.gloss(ribbon, 1, 0.65)
	local ribbonText = text(ribbon, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), Color3.new(1, 1, 1), 18, Z + 12)
	ribbonText.Text = string.upper(rarity.id)
	if many then
		ribbonText.Text = `OPENED {#info.items} x {string.upper(info.chestName or (rarity.id .. " chest"))}`
		for index, item in info.items do
			if index > 10 then
				break
			end
			local itemRarity = rarityOf(item.rarity or "Common")
			local column, row = (index - 1) % 5, (index - 1) // 5
			local cell = frame(card, UDim2.fromOffset(92, 120), UDim2.fromOffset(60 + column * 100, 100 + row * 128), Color3.fromRGB(48, 38, 30), Z + 11)
			Art.corner(cell, 8)
			Art.stroke(cell, itemRarity.color, 2, 0)
			prizePicture(cell, item, 72, UDim2.new(0.5, 0, 0, 42), Z + 12)
			local label = text(cell, UDim2.new(1, -8, 0, 34), UDim2.new(0.5, 0, 1, -20), itemRarity.color, 12, Z + 13)
			label.TextWrapped = true
			label.Text = item.name or ""
			local cellScale = Instance.new("UIScale")
			cellScale.Scale = 0
			cellScale.Parent = cell
			task.delay(0.05 * index, function()
				Art.tween(cellScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
			end)
		end
	else
		prizePicture(card, info, 84, UDim2.new(0.5, 0, 0, 78), Z + 11)
	end
	local name = text(card, UDim2.new(1, -20, 0, 26), UDim2.new(0.5, 0, 0, 136), color, 20, Z + 11)
	name.Text = info.name or ""
	name.TextScaled = true
	name.Visible = not many
	local note = text(card, UDim2.new(1, -20, 0, 32), UDim2.new(0.5, 0, 0, 170), Color3.fromRGB(220, 208, 186), 13, Z + 11)
	note.Font = Enum.Font.GothamMedium
	note.TextStrokeTransparency = 1
	note.Visible = not many
	if isSoldier then
		note.Text = if info.kept then `{info.tier or ""} recruit joined your warband!` else "Not rare enough, so your soldier stayed."
	else
		note.Text = info.source or ""
	end
	if rank >= 4 then
		Art.shine(card, 2)
	end

	local tap = text(stage, UDim2.new(1, 0, 0, 20), UDim2.new(0.5, 0, 0.5, if many then 170 else 120), Color3.new(1, 1, 1), 14, Z + 11)
	tap.Font = Enum.Font.GothamBold
	tap.Text = "Tap to continue"
	tap.TextTransparency = 1
	Art.tween(tap, 0.6, { TextTransparency = 0.2 })

	-- After opening a chest: open more of the same right from here.
	local again = nil -- set to a count when an "open more" button is pressed
	local offerMore = info.chestId ~= nil and (info.left or 0) > 0 and Fx.send ~= nil
	if offerMore then
		tap.Text = `{info.left} left`
		local choices = { { label = "Open 1", count = 1 } }
		if info.left > 1 then
			table.insert(choices, { label = `Open {math.min(10, info.left)}`, count = 10 })
		end
		table.insert(choices, { label = "Done", count = 0 })
		local width = 130
		local y = (if many then 300 else 196) / 2 + 60
		for index, choice in choices do
			local x = (index - (#choices + 1) / 2) * (width + 10)
			local button = Instance.new("TextButton")
			button.AnchorPoint = Vector2.new(0.5, 0.5)
			button.Size = UDim2.fromOffset(width, 42)
			button.Position = UDim2.new(0.5, x, 0.5, y)
			button.BackgroundColor3 = if choice.count == 0 then Color3.fromRGB(70, 60, 52) elseif choice.count == 1 then Color3.fromRGB(200, 150, 50) else Color3.fromRGB(60, 150, 80)
			button.TextColor3 = Color3.new(1, 1, 1)
			button.Font = Enum.Font.GothamBold
			button.TextSize = 16
			button.Text = choice.label
			button.AutoButtonColor = true
			button.ZIndex = Z + 15
			button.Parent = stage
			Art.corner(button, 8)
			Art.gloss(button, 1, 0.7)
			button.Activated:Connect(function()
				if choice.count > 0 then
					again = choice.count
				end
				if shade:GetAttribute("Close") == nil then
					shade:SetAttribute("Close", true)
				end
			end)
		end
	end

	-- Closes on a tap, or by itself so auto play is never blocked.
	local closed = false
	local done = Instance.new("BindableEvent")
	local function close()
		if closed then
			return
		end
		closed = true
		Art.tween(cardScale, 0.18, { Scale = 0.6 })
		Art.tween(shade, 0.2, { BackgroundTransparency = 1 })
		for _, child in shade:GetDescendants() do
			if child:IsA("GuiObject") then
				Art.tween(child, 0.18, { BackgroundTransparency = 1 })
			end
			if child:IsA("TextLabel") then
				Art.tween(child, 0.18, { TextTransparency = 1, TextStrokeTransparency = 1 })
			end
		end
		task.wait(0.22)
		rays:Destroy()
		shade:Destroy()
		done:Fire()
	end
	shade:GetAttributeChangedSignal("Close"):Connect(close)
	task.wait(0.4)
	shade.Activated:Connect(close)
	-- With "open more" buttons the player decides; otherwise it closes by
	-- itself so auto play is never blocked.
	if not offerMore then
		task.delay(if #queue > 0 then 1.6 elseif many then 8 else 5, close)
	else
		task.delay(30, close)
	end
	done.Event:Wait()
	done:Destroy()
	if again and Fx.send then
		Fx.send("ChestOpen", `{info.chestId}:{again}`)
	end
end

local function runQueue()
	if showing then
		return
	end
	showing = true
	while #queue > 0 do
		local info = table.remove(queue, 1)
		local ok, err = pcall(playReveal, info)
		if not ok then
			warn("[Fx] reveal failed: " .. tostring(err))
		end
	end
	showing = false
end

function Fx.reveal(info)
	-- A long line of reveals (claim all) keeps only the best few.
	if #queue >= 4 then
		table.sort(queue, function(a, b)
			return GameConfig.getRarityRank(a.rarity) > GameConfig.getRarityRank(b.rarity)
		end)
		table.remove(queue)
	end
	table.insert(queue, info)
	task.spawn(runQueue)
end

---------------------------------------------------------------------------
-- Small drop card: gear found on a quest slides up and fades
---------------------------------------------------------------------------

local dropCount = 0
function Fx.drop(info)
	local rarity = rarityOf(info.rarity or "Common")
	dropCount += 1
	local lane = dropCount % 3
	local card = frame(layer, UDim2.fromOffset(250, 52), UDim2.new(0.5, 0, 1, -110 - lane * 58), Color3.fromRGB(34, 26, 20), 30)
	Art.corner(card, 10)
	Art.gloss(card, 1, 0.8)
	Art.stroke(card, rarity.color, 2, 0)
	local icon = prizePicture(card, info, 44, UDim2.fromOffset(28, 26), 31)
	local label = text(card, UDim2.new(1, -56, 1, -8), UDim2.new(0.5, 22, 0.5, 0), Color3.new(1, 1, 1), 14, 31)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Font = Enum.Font.GothamBold
	label.TextStrokeTransparency = 1
	local r, g, b = math.floor(rarity.color.R * 255), math.floor(rarity.color.G * 255), math.floor(rarity.color.B * 255)
	label.Text = `<font color="rgb({r},{g},{b})">{rarity.id}</font> {info.name or ""}`
	local scale = Instance.new("UIScale")
	scale.Scale = 0.5
	scale.Parent = card
	Art.tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	if GameConfig.getRarityRank(rarity.id) >= 4 then
		Art.shine(card, 1.5)
	end
	task.delay(2.4, function()
		Art.tween(card, 0.5, { Position = card.Position - UDim2.fromOffset(0, 40), BackgroundTransparency = 1 })
		Art.tween(label, 0.5, { TextTransparency = 1 })
		for _, child in icon:GetDescendants() do
			if child:IsA("GuiObject") then
				Art.tween(child, 0.5, { BackgroundTransparency = 1 })
			end
		end
		for _, child in card:GetDescendants() do
			if child:IsA("UIStroke") then
				Art.tween(child, 0.5, { Transparency = 1 })
			end
		end
		task.wait(0.55)
		card:Destroy()
	end)
end

-- A chest went to the inventory: a small chest card pops up and fades.
function Fx.chestGot(info)
	local rarity = rarityOf(info.rarity or "Common")
	dropCount += 1
	local lane = dropCount % 3
	local card = frame(layer, UDim2.fromOffset(250, 52), UDim2.new(0.5, 0, 1, -110 - lane * 58), Color3.fromRGB(34, 26, 20), 30)
	Art.corner(card, 10)
	Art.gloss(card, 1, 0.8)
	Art.stroke(card, rarity.color, 2, 0)
	local holder = frame(card, UDim2.fromOffset(44, 44), UDim2.fromOffset(28, 26), Color3.new(), 31)
	holder.BackgroundTransparency = 1
	if ItemArt then
		ItemArt.chest(holder, rarity.id)
	else
		local icon = Art.icon(holder, Art.Icons.chest, 34, UDim2.fromScale(0.5, 0.5))
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.ZIndex = 32
	end
	local label = text(card, UDim2.new(1, -56, 1, -8), UDim2.new(0.5, 22, 0.5, 0), Color3.new(1, 1, 1), 14, 31)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Font = Enum.Font.GothamBold
	label.TextStrokeTransparency = 1
	local r, g, b = math.floor(rarity.color.R * 255), math.floor(rarity.color.G * 255), math.floor(rarity.color.B * 255)
	label.Text = `<font color="rgb({r},{g},{b})">{info.name or (rarity.id .. " Chest")}</font> added to Inventory`
	local scale = Instance.new("UIScale")
	scale.Scale = 0.5
	scale.Parent = card
	Art.tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(2.4, function()
		Art.tween(label, 0.5, { TextTransparency = 1 })
		for _, child in card:GetDescendants() do
			if child:IsA("UIStroke") then
				Art.tween(child, 0.5, { Transparency = 1 })
			elseif child:IsA("GuiObject") then
				Art.tween(child, 0.5, { BackgroundTransparency = 1 })
			end
		end
		Art.tween(card, 0.5, { Position = card.Position - UDim2.fromOffset(0, 40), BackgroundTransparency = 1 })
		task.wait(0.55)
		card:Destroy()
	end)
end

---------------------------------------------------------------------------
-- Damage numbers on the Foes fight panel
---------------------------------------------------------------------------

local function floatNumber(anchor: GuiObject?, content: string, color: Color3, size: number)
	local position
	if anchor and anchor.Parent and anchor.AbsoluteSize.X > 0 and anchor.Visible then
		local inset = game:GetService("GuiService"):GetGuiInset()
		position = UDim2.fromOffset(
			anchor.AbsolutePosition.X + anchor.AbsoluteSize.X * (0.35 + math.random() * 0.3),
			anchor.AbsolutePosition.Y + inset.Y
		)
	else
		position = UDim2.fromScale(0.5 + (math.random() - 0.5) * 0.1, 0.45)
	end
	local label = text(layer, UDim2.fromOffset(240, 40), position, color, size, 40)
	label.Text = content
	label.TextStrokeTransparency = 0
	local pop = Instance.new("UIScale")
	pop.Scale = 0.4
	pop.Parent = label
	Art.tween(pop, 0.18, { Scale = 1.15 }, Enum.EasingStyle.Back)
	Art.tween(label, 0.9, { Position = position - UDim2.fromOffset(math.random(-20, 20), 60) }, Enum.EasingStyle.Quad)
	task.delay(0.55, function()
		Art.tween(label, 0.4, { TextTransparency = 1, TextStrokeTransparency = 1 })
		task.wait(0.45)
		label:Destroy()
	end)
end

local shaking = {}
local function shake(target: GuiObject?)
	if not target or not target.Parent or shaking[target] then
		return
	end
	shaking[target] = true
	local start = target.Position
	task.spawn(function()
		for index = 1, 5 do
			target.Position = start + UDim2.fromOffset((if index % 2 == 0 then 4 else -4), 0)
			task.wait(0.035)
		end
		target.Position = start
		shaking[target] = nil
	end)
end

local function banner(content: string, color: Color3)
	local label = text(layer, UDim2.fromOffset(600, 80), UDim2.fromScale(0.5, 0.38), color, 64, 45)
	label.Font = Art.Fonts.title
	label.Text = content
	label.TextStrokeTransparency = 0
	local pop = Instance.new("UIScale")
	pop.Scale = 2
	pop.Parent = label
	Art.tween(pop, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(1.4, function()
		Art.tween(label, 0.4, { TextTransparency = 1, TextStrokeTransparency = 1 })
		task.wait(0.45)
		label:Destroy()
	end)
end

function Fx.hit(info)
	local damage = tonumber(info.damage) or 0
	local hurt = tonumber(info.hurt) or 0
	floatNumber(anchors.foe, `-{Fx.short(damage)}`, Color3.fromRGB(255, 226, 120), 30)
	shake(anchors.foe)
	if hurt > 0 then
		task.delay(0.2, function()
			floatNumber(anchors.you, `-{Fx.short(hurt)}`, Color3.fromRGB(255, 90, 80), 24)
			shake(anchors.you)
		end)
	end
	if info.result == "cleared" then
		banner("Victory!", Art.Colors.gold)
	elseif info.result == "down" then
		banner("Defeated", Color3.fromRGB(230, 70, 60))
	end
end

---------------------------------------------------------------------------
-- Level up: a banner and a shower of gold
---------------------------------------------------------------------------

function Fx.levelUp(info)
	local Z = 45
	local ribbon = frame(layer, UDim2.fromOffset(420, 86), UDim2.new(0.5, 0, 0, -60), Art.Colors.blood, Z)
	Art.corner(ribbon, 14)
	Art.gloss(ribbon, 1, 0.6)
	Art.stroke(ribbon, Art.Colors.gold, 3, 0)
	Art.studs(ribbon, 10)
	local star = Art.icon(ribbon, Art.Icons.xp, 48, UDim2.new(0, 20, 0.5, 0))
	star.AnchorPoint = Vector2.new(0, 0.5)
	star.ZIndex = Z + 1
	local title = text(ribbon, UDim2.new(1, -90, 0, 44), UDim2.new(0.5, 30, 0, 32), Art.Colors.goldLight, 40, Z + 1)
	title.Font = Art.Fonts.title
	title.Text = `Level {tonumber(info.level) or ""}`
	local sub = text(ribbon, UDim2.new(1, -90, 0, 18), UDim2.new(0.5, 30, 0, 66), Color3.new(1, 1, 1), 13, Z + 1)
	sub.Font = Enum.Font.GothamBold
	sub.TextStrokeTransparency = 1
	sub.Text = "Skill points earned, everything refilled"
	Art.shine(ribbon, 1)
	Art.tween(ribbon, 0.5, { Position = UDim2.new(0.5, 0, 0, 120) }, Enum.EasingStyle.Back)

	for _ = 1, 40 do
		local size = math.random(6, 12)
		local coin = frame(layer, UDim2.fromOffset(size, size), UDim2.new(math.random(), 0, 0, -20), Art.Colors.gold, Z - 1)
		Art.corner(coin, 999)
		Art.gloss(coin, 1, 0.55)
		local fall = 1.4 + math.random() * 1.2
		task.delay(math.random() * 0.6, function()
			Art.tween(coin, fall, {
				Position = coin.Position + UDim2.new((math.random() - 0.5) * 0.1, 0, 1.05, 0),
				Rotation = math.random(-360, 360),
			}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.wait(fall)
			coin:Destroy()
		end)
	end

	task.delay(2.8, function()
		Art.tween(ribbon, 0.35, { Position = UDim2.new(0.5, 0, 0, -80) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.wait(0.4)
		ribbon:Destroy()
	end)
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------

-- Short numbers (1.2K) without needing Format here.
function Fx.short(value: number): string
	return Fx.format and Fx.format(value) or tostring(value)
end

function Fx.setAnchor(name: string, object: GuiObject)
	anchors[name] = object
end

function Fx.init(art, gameConfig, format, remote: RemoteEvent, itemArt, send)
	Art = art
	ItemArt = itemArt
	Fx.send = send -- sends an action to the server (open more chests)
	GameConfig = gameConfig
	Fx.format = format
	layer = Instance.new("ScreenGui")
	layer.Name = "KingdomEffects"
	layer.DisplayOrder = 20
	layer.IgnoreGuiInset = true
	layer.ResetOnSpawn = false
	layer.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	remote.OnClientEvent:Connect(function(kind: string, info)
		if type(info) ~= "table" then
			return
		end
		if kind == "gear" then
			if info.crate then
				info.what = "gear"
				Fx.reveal(info)
			elseif GameConfig.getRarityRank(info.rarity or "Common") >= 3 then
				Fx.drop(info)
			end
		elseif kind == "chestOpen" then
			if type(info.items) ~= "table" or #info.items == 0 then
				return
			end
			local first = info.items[1]
			Fx.reveal({
				what = "gear",
				rarity = if #info.items == 1 then first.rarity else info.rarity,
				name = first.name,
				slot = first.slot,
				source = info.name or `{info.rarity} chest`,
				chestName = info.name,
				items = info.items,
				chestId = info.chest,
				left = tonumber(info.left) or 0,
			})
		elseif kind == "chestGot" then
			Fx.chestGot(info)
		elseif kind == "roll" then
			if Fx.onRoll then
				Fx.onRoll(info)
			end
		elseif kind == "income" then
			if Fx.onIncome then
				Fx.onIncome(info)
			end
		elseif kind == "soldier" then
			info.what = "soldier"
			Fx.reveal(info)
		elseif kind == "hit" then
			Fx.hit(info)
		elseif kind == "levelup" then
			Fx.levelUp(info)
		end
	end)
end

return Fx
