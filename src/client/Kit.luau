-- Small shared building blocks for the picture-card pages (Bounties,
-- Festival, Research, Expeditions, Barracks, Rankings, War Chronicle):
-- banners, grids, cards, bars, reward tiles and a few animations.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local StoreConfig = require(Shared:WaitForChild("StoreConfig"))

local Kit = {}

Kit.GOLD = Color3.fromRGB(240, 196, 80)
Kit.GREEN = Color3.fromRGB(110, 210, 110)
Kit.RED = Color3.fromRGB(230, 90, 80)
Kit.CARD = Color3.fromRGB(32, 28, 24)

Kit.REWARD_GLYPHS = {
	crowns = "\u{1F451}",
	gold = "\u{1F4B0}",
	xpBoost = "\u{2B50}",
	skill = "\u{1F4AA}",
	tokens = "\u{1F3C5}",
	energy = "\u{26A1}",
	stamina = "\u{1F4EF}",
	health = "\u{2764}\u{FE0F}",
	title = "\u{1F3F7}\u{FE0F}",
	seals = "\u{1F4DC}",
	chest = "\u{1F381}",
}

-- A wide banner with a gradient, skyline, grain and shine. Returns the frame.
function Kit.banner(ui, page: Instance, order: number, height: number, top: Color3, bottom: Color3, title: string, glyph: string)
	local frame = ui.makeFrame(page, UDim2.new(1, -10, 0, height), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1))
	frame.LayoutOrder = order
	frame.ClipsDescendants = true
	ui.addCorner(frame, 10)
	ui.art.stroke(frame, ui.colors.gold, 2, 0.1)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 12
	gradient.Color = ColorSequence.new(top, bottom)
	gradient.Parent = frame
	ui.art.skyline(frame, bottom:Lerp(Color3.new(0, 0, 0), 0.6), 0.35)
	ui.art.grain(frame)
	ui.art.shine(frame, 6)
	local icon = ui.makeFrame(frame, UDim2.fromOffset(84, 84), UDim2.new(0, 18, 0.5, -42), top:Lerp(Color3.new(0, 0, 0), 0.25))
	icon.ZIndex = 410
	ui.addCorner(icon, 42)
	ui.art.gloss(icon, 1, 0.6)
	ui.art.stroke(icon, ui.colors.gold, 3, 0)
	local mark = ui.makeText(icon, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1), 46)
	mark.TextXAlignment = Enum.TextXAlignment.Center
	mark.Text = glyph
	mark.ZIndex = 411
	Kit.bob(mark, 3, 1.6)
	local label = ui.makeText(frame, UDim2.new(0.5, -120, 0, 50), UDim2.fromOffset(118, 14), ui.colors.gold, 40)
	label.Font = ui.art.Fonts.title
	label.Text = title
	label.TextStrokeTransparency = 0.4
	label.ZIndex = 410
	return frame, label, icon
end

-- A text line on a banner (below the title).
function Kit.line(ui, parent: Instance, x: number, y: number, width: UDim, size: number, color: Color3): TextLabel
	local label = ui.makeText(parent, UDim2.new(width.Scale, width.Offset, 0, size + 8), UDim2.fromOffset(x, y), color, size)
	label.Font = Enum.Font.GothamBold
	label.RichText = true
	label.ZIndex = 410
	return label
end

-- A heading strip with a colored band on the left.
function Kit.heading(ui, page: Instance, order: number, text: string, color: Color3?)
	local frame = ui.makeFrame(page, UDim2.new(1, -10, 0, 40), UDim2.fromOffset(0, 0), Color3.fromRGB(40, 33, 24))
	frame.LayoutOrder = order
	ui.addCorner(frame, 6)
	local band = ui.makeFrame(frame, UDim2.new(0, 6, 1, 0), UDim2.fromOffset(0, 0), color or ui.colors.gold)
	ui.addCorner(band, 3)
	local label = ui.makeText(frame, UDim2.new(0.6, -20, 1, 0), UDim2.fromOffset(18, 0), ui.colors.gold, 20)
	label.Font = ui.art.Fonts.heading
	label.Text = text
	local right = ui.makeText(frame, UDim2.new(0.4, -16, 1, 0), UDim2.new(0.6, 0, 0, 0), ui.colors.dim, 13)
	right.Font = Enum.Font.GothamBlack
	right.TextXAlignment = Enum.TextXAlignment.Right
	return frame, label, right
end

function Kit.grid(ui, page: Instance, order: number, height: number, columns: number): Frame
	local frame = ui.makeFrame(page, UDim2.new(1, -10, 0, 0), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	frame.BackgroundTransparency = 1
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.LayoutOrder = order
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(1 / columns, -10, 0, height)
	layout.CellPadding = UDim2.fromOffset(12, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame
	return frame
end

-- A card (in a grid, or sized by the caller). Returns frame and its stroke.
function Kit.card(ui, parent: Instance, order: number, color: Color3?): (Frame, UIStroke)
	local frame = ui.makeFrame(parent, UDim2.new(1, -10, 0, 100), UDim2.fromOffset(0, 0), Kit.CARD)
	frame.LayoutOrder = order
	frame.ClipsDescendants = true
	ui.addCorner(frame, 8)
	local stroke = ui.art.stroke(frame, color or ui.colors.dim, 1.5, 0.3)
	local scale = Instance.new("UIScale")
	scale.Name = "Pop"
	scale.Parent = frame
	return frame, stroke
end

-- A round picture with an emoji.
function Kit.badge(ui, parent: Instance, glyph: string, size: number, position: UDim2, color: Color3): (Frame, TextLabel)
	local disc = ui.makeFrame(parent, UDim2.fromOffset(size, size), position, color)
	ui.addCorner(disc, size / 2)
	ui.art.gloss(disc, 1, 0.65)
	ui.art.stroke(disc, color:Lerp(Color3.new(0, 0, 0), 0.5), 2, 0)
	local label = ui.makeText(disc, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1), math.floor(size * 0.55))
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Text = glyph
	label.ZIndex = disc.ZIndex + 2
	return disc, label
end

-- A progress bar. Returns { back, fill, text }.
function Kit.bar(ui, parent: Instance, size: UDim2, position: UDim2, color: Color3)
	local back = ui.makeFrame(parent, size, position, Color3.fromRGB(16, 14, 12))
	ui.addCorner(back, 6)
	local fill = ui.makeFrame(back, UDim2.fromScale(0, 1), UDim2.fromOffset(0, 0), color)
	ui.addCorner(fill, 6)
	ui.art.gloss(fill, 1, 0.65)
	local text = ui.makeText(back, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1), 12)
	text.Font = Enum.Font.GothamBlack
	text.TextXAlignment = Enum.TextXAlignment.Center
	text.TextStrokeTransparency = 0.4
	text.ZIndex = fill.ZIndex + 1
	return { back = back, fill = fill, text = text }
end

-- Sets a bar (slides to the new value).
function Kit.setBar(bar, value: number, maximum: number, text: string)
	local share = if maximum > 0 then math.clamp(value / maximum, 0, 1) else 0
	if math.abs(bar.fill.Size.X.Scale - share) > 0.001 then
		TweenService:Create(bar.fill, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(share, 1) }):Play()
	end
	bar.fill.Visible = share > 0
	bar.text.Text = text
end

-- A reward picture (chest drawing or emoji) filling `holder`.
function Kit.rewardArt(ui, holder: GuiObject, reward)
	if holder:GetAttribute("Reward") == StoreConfig.describe(reward) then
		return
	end
	holder:SetAttribute("Reward", StoreConfig.describe(reward))
	for _, child in holder:GetChildren() do
		if child.Name == "RewardGlyph" then
			child:Destroy()
		end
	end
	if reward.kind == "chest" then
		ui.itemArt.chest(holder, reward.rarity)
	else
		local old = holder:FindFirstChild("ItemArt")
		if old then
			old:Destroy()
		end
		local label = ui.makeText(holder, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1), math.floor(holder.AbsoluteSize.Y * 0.6 + 0.5))
		label.Name = "RewardGlyph"
		label.TextScaled = true
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.Text = Kit.REWARD_GLYPHS[reward.kind] or "\u{1F381}"
	end
end

function Kit.rewardColor(reward): Color3
	if reward.kind == "chest" then
		return GameConfig.getRarity(reward.rarity).color
	end
	return Kit.GOLD
end

-- Scale pop (from a size back to 1).
function Kit.pop(object: GuiObject, from: number)
	local scale = object:FindFirstChild("Pop") :: UIScale?
	if not scale then
		local made = Instance.new("UIScale")
		made.Name = "Pop"
		made.Parent = object
		scale = made
	end
	if scale then
		scale.Scale = from
		TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

-- Pops every card (UIScale named Pop) under `root` one after another.
function Kit.popAll(root: Instance)
	local index = 0
	for _, scale in root:GetDescendants() do
		if scale:IsA("UIScale") and scale.Name == "Pop" then
			index += 1
			scale.Scale = 0.75
			task.delay(math.min(index, 20) * 0.03, function()
				TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end)
		end
	end
end

-- Bobs an object up and down forever (while it exists).
local bobbers = {}
local bobbing = false
function Kit.bob(object: GuiObject, pixels: number, speed: number)
	table.insert(bobbers, { object = object, base = object.Position, pixels = pixels, speed = speed, phase = math.random() * 6 })
	if bobbing then
		return
	end
	bobbing = true
	local t = 0
	RunService.RenderStepped:Connect(function(dt)
		t += dt
		for index = #bobbers, 1, -1 do
			local entry = bobbers[index]
			if not entry.object.Parent then
				table.remove(bobbers, index)
			elseif entry.object.Visible then
				entry.object.Position = entry.base + UDim2.fromOffset(0, math.sin(t * entry.speed + entry.phase) * entry.pixels)
			end
		end
	end)
end

-- Glowing pulse on strokes of things that can be claimed. Call
-- Kit.setPulse(stroke, true/false).
local pulsing = {}
local pulseRunning = false
function Kit.setPulse(stroke: UIStroke, on: boolean, base: Color3?)
	if on then
		pulsing[stroke] = base or stroke.Color
	elseif pulsing[stroke] then
		stroke.Color = pulsing[stroke]
		stroke.Thickness = 1.5
		pulsing[stroke] = nil
	end
	if pulseRunning then
		return
	end
	pulseRunning = true
	local t = 0
	RunService.RenderStepped:Connect(function(dt)
		t += dt
		local wave = (math.sin(t * 5) + 1) / 2
		for item in pulsing do
			if item.Parent then
				item.Color = Kit.GREEN:Lerp(Kit.GOLD, wave)
				item.Thickness = 2 + wave * 2.5
				item.Transparency = 0
			end
		end
	end)
end

-- "+text" rising from an object.
function Kit.float(ui, parent: GuiObject, text: string, color: Color3)
	local label = ui.makeText(parent, UDim2.fromOffset(240, 30), UDim2.new(0.5, -120, 0.4, 0), color, 20)
	label.Font = Enum.Font.GothamBlack
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextStrokeTransparency = 0.2
	label.ZIndex = 700
	label.Text = text
	local tween = TweenService:Create(label, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, -120, 0, -10),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	tween:Play()
	tween.Completed:Connect(function()
		label:Destroy()
	end)
end

function Kit.centered(ui, parent: Instance, y: number, height: number, size: number, color: Color3): TextLabel
	local label = ui.makeText(parent, UDim2.new(1, -16, 0, height), UDim2.fromOffset(8, y), color, size)
	label.TextXAlignment = Enum.TextXAlignment.Center
	return label
end

function Kit.clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local d = seconds // 86400
	local h = seconds % 86400 // 3600
	local m = seconds % 3600 // 60
	if d > 0 then
		return `{d}d {h}h`
	elseif h > 0 then
		return `{h}h {m}m`
	end
	return string.format("%d:%02d", m, seconds % 60)
end

return Kit
