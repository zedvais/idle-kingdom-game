-- Profile popup, kept simple:
--   left   your Roblox picture in a gold frame with your level, your name
--          and title, and the three pieces you wear yourself,
--   right  STATS (renown, attack, defense, warband, income; tap attack or
--          defense to see where it comes from) and ACTIVITY.
-- All-time numbers live in MENU > Stats; titles and codes in MENU > Settings.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Format = require(Shared:WaitForChild("Format"))

local ProfilePage = {}

local SLOTS = { "Weapon", "Armor", "Mount" }
local ATTACK_COLOR = Color3.fromRGB(255, 140, 110)
local DEFENSE_COLOR = Color3.fromRGB(140, 190, 255)

local w = {}
local latest = nil
local popoverKind = nil -- "attack" / "defense" while the breakdown shows

local function commas(value: number): string
	local text = tostring(math.floor(value))
	local result = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (result:gsub("^,", ""))
end

local function header(ui, parent: Instance, y: number, text: string)
	local band = ui.makeFrame(parent, UDim2.new(1, 0, 0, 32), UDim2.fromOffset(0, y), Color3.fromRGB(24, 18, 14))
	band.BackgroundTransparency = 0.2
	local label = ui.makeText(band, UDim2.new(1, -20, 1, 0), UDim2.fromOffset(14, 0), ui.colors.gold, 17)
	label.Font = Enum.Font.GothamBlack
	label.Text = text
	return band
end

local function drawPopover(state, ui)
	local pop = w.popover
	pop.frame.Visible = popoverKind ~= nil
	if not popoverKind or not state then
		return
	end
	local stats = state.stats
	local attack = popoverKind == "attack"
	pop.title.Text = if attack then "\u{2694}\u{FE0F} ATTACK" else "\u{1F6E1}\u{FE0F} DEFENSE"
	pop.title.TextColor3 = if attack then ATTACK_COLOR else DEFENSE_COLOR
	local lines = {}
	for index, part in stats.breakdown or {} do
		local value = math.floor(if attack then part[2] else part[3])
		local sign = if index == #stats.breakdown then "+" else ""
		local color = if index == #stats.breakdown then "#F0C450" else "#EDE6D6"
		table.insert(lines, `<font color="{color}">{part[1]}</font>`)
		pop.values[index] = `<font color="{color}">{sign}{commas(value)}</font>`
	end
	pop.left.Text = table.concat(lines, "\n")
	local values = {}
	for index = 1, #(stats.breakdown or {}) do
		table.insert(values, pop.values[index])
	end
	pop.right.Text = table.concat(values, "\n")
end

function ProfilePage.build(ui)
	local page = ui.pages.Profile
	local colors = ui.colors
	local body = ui.makeFrame(page, UDim2.new(1, -10, 0, 476), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1))
	body.LayoutOrder = 1
	ui.addCorner(body, 10)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.fromRGB(96, 26, 24), Color3.fromRGB(48, 14, 14))
	gradient.Parent = body
	ui.art.grain(body)
	w.body = body

	-- Picture in a gold frame, level badge in the corner.
	local frame = ui.makeFrame(body, UDim2.fromOffset(190, 190), UDim2.fromOffset(24, 20), ui.colors.gold)
	ui.addCorner(frame, 14)
	ui.art.gloss(frame, 1, 0.55)
	ui.art.stroke(frame, Color3.fromRGB(110, 70, 20), 3, 0)
	ui.art.studs(frame, 10)
	local picture = Instance.new("ImageLabel")
	picture.Size = UDim2.new(1, -24, 1, -24)
	picture.Position = UDim2.fromOffset(12, 12)
	picture.BackgroundColor3 = Color3.fromRGB(30, 24, 20)
	picture.BorderSizePixel = 0
	picture.ScaleType = Enum.ScaleType.Crop
	picture.ZIndex = frame.ZIndex + 3
	picture.Parent = frame
	ui.addCorner(picture, 8)
	task.spawn(function()
		local ok, image = pcall(Players.GetUserThumbnailAsync, Players, ui.player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
		if ok and image then
			picture.Image = image
		end
	end)
	w.level = ui.makeText(frame, UDim2.fromOffset(64, 44), UDim2.new(1, 8, 1, 8), Color3.fromRGB(40, 26, 8), 28)
	w.level.AnchorPoint = Vector2.new(1, 1)
	w.level.BackgroundTransparency = 0
	w.level.BackgroundColor3 = colors.gold
	w.level.Font = Enum.Font.GothamBlack
	w.level.TextXAlignment = Enum.TextXAlignment.Center
	w.level.ZIndex = frame.ZIndex + 5
	ui.addCorner(w.level, 6)
	ui.art.stroke(w.level, Color3.fromRGB(90, 60, 10), 2, 0)
	w.stars = ui.makeText(frame, UDim2.fromOffset(70, 26), UDim2.fromOffset(-8, -8), colors.gold, 14)
	w.stars.BackgroundTransparency = 0
	w.stars.BackgroundColor3 = Color3.fromRGB(24, 18, 14)
	w.stars.Font = Enum.Font.GothamBlack
	w.stars.TextXAlignment = Enum.TextXAlignment.Center
	w.stars.ZIndex = frame.ZIndex + 5
	ui.addCorner(w.stars, 6)

	-- Name card.
	local nameCard = ui.makeFrame(body, UDim2.fromOffset(250, 62), UDim2.fromOffset(16, 226), Color3.fromRGB(24, 18, 14))
	nameCard.BackgroundTransparency = 0.1
	ui.addCorner(nameCard, 6)
	w.name = ui.makeText(nameCard, UDim2.new(1, -16, 0, 28), UDim2.fromOffset(8, 6), colors.text, 20)
	w.name.Font = Enum.Font.GothamBlack
	w.name.TextXAlignment = Enum.TextXAlignment.Center
	w.name.TextTruncate = Enum.TextTruncate.AtEnd
	w.title = ui.makeText(nameCard, UDim2.new(1, -16, 0, 20), UDim2.fromOffset(8, 34), colors.gold, 14)
	w.title.Font = Enum.Font.GothamBlack
	w.title.TextXAlignment = Enum.TextXAlignment.Center

	-- Equipped: your own three slots.
	header(ui, body, 300, "EQUIPPED")
	w.slots = {}
	for index, slot in SLOTS do
		local tile = ui.makeFrame(body, UDim2.fromOffset(76, 76), UDim2.fromOffset(16 + (index - 1) * 87, 340), Color3.fromRGB(24, 18, 14))
		ui.addCorner(tile, 6)
		local stroke = ui.art.stroke(tile, colors.dim, 2, 0.2)
		local art = ui.makeFrame(tile, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
		art.BackgroundTransparency = 1
		local empty = ui.makeText(tile, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), colors.dim, 28)
		empty.TextXAlignment = Enum.TextXAlignment.Center
		empty.Text = ui.art.Icons[slot] or "?"
		empty.TextTransparency = 0.6
		w.slots[slot] = { tile = tile, stroke = stroke, art = art, empty = empty }
	end
	local rebirth = ui.makeButton(body, UDim2.fromOffset(250, 40), UDim2.fromOffset(16, 424), colors.selected)
	ui.setButton(rebirth, "\u{1F31F} REBIRTH", true, colors.selected)
	rebirth.Font = Enum.Font.GothamBlack
	rebirth.TextSize = 16
	rebirth.Activated:Connect(function()
		ui.openModal("Rebirth")
	end)

	-- Stats.
	local right = ui.makeFrame(body, UDim2.new(1, -310, 1, -40), UDim2.fromOffset(290, 20), Color3.new(0, 0, 0))
	right.BackgroundTransparency = 1
	header(ui, right, 0, "STATS")
	local statBox = ui.makeFrame(right, UDim2.new(1, 0, 0, 232), UDim2.fromOffset(0, 36), Color3.fromRGB(26, 22, 20))
	ui.addCorner(statBox, 4)
	ui.art.stroke(statBox, Color3.new(0, 0, 0), 1, 0.4)
	w.stats = {}
	local rows = {
		{ "renown", "\u{2B50}", "Renown" },
		{ "attack", "\u{2694}\u{FE0F}", "Attack Power" },
		{ "defense", "\u{1F6E1}\u{FE0F}", "Defense Power" },
		{ "crew", "\u{1F465}", "Warband Size" },
		{ "income", "\u{1F4B0}", "Income / hr" },
	}
	for index, info in rows do
		local y = 6 + (index - 1) * 45
		local row = ui.makeButton(statBox, UDim2.new(1, -12, 0, 42), UDim2.fromOffset(6, y), Color3.new(0, 0, 0))
		row.BackgroundTransparency = 1
		row.Text = ""
		row:SetAttribute("NoGlow", info[1] ~= "attack" and info[1] ~= "defense")
		local glyph = ui.makeText(row, UDim2.fromOffset(40, 42), UDim2.fromOffset(8, 0), Color3.new(1, 1, 1), 24)
		glyph.TextXAlignment = Enum.TextXAlignment.Center
		glyph.Text = info[2]
		local label = ui.makeText(row, UDim2.new(0.6, -60, 1, 0), UDim2.fromOffset(58, 0), colors.text, 20)
		label.Text = `{info[3]}:`
		local value = ui.makeText(row, UDim2.new(0.4, -10, 1, 0), UDim2.new(0.6, 0, 0, 0), colors.text, 22)
		value.Font = Enum.Font.GothamBlack
		value.TextXAlignment = Enum.TextXAlignment.Right
		w.stats[info[1]] = value
		if info[1] == "attack" or info[1] == "defense" then
			local kind = info[1]
			row.MouseEnter:Connect(function()
				popoverKind = kind
				drawPopover(latest, ui)
			end)
			row.MouseLeave:Connect(function()
				if popoverKind == kind then
					popoverKind = nil
					drawPopover(latest, ui)
				end
			end)
			row.Activated:Connect(function()
				popoverKind = if popoverKind == kind then nil else kind
				drawPopover(latest, ui)
			end)
		end
	end
	w.statColors = { attack = ATTACK_COLOR, defense = DEFENSE_COLOR }

	header(ui, right, 284, "ACTIVITY")
	local activity = ui.makeFrame(right, UDim2.new(1, 0, 0, 96), UDim2.fromOffset(0, 320), Color3.fromRGB(26, 22, 20))
	ui.addCorner(activity, 4)
	w.since = ui.makeText(activity, UDim2.new(1, -28, 0, 44), UDim2.fromOffset(14, 4), colors.text, 18)
	w.since.RichText = true
	w.best = ui.makeText(activity, UDim2.new(1, -28, 0, 44), UDim2.fromOffset(14, 48), colors.text, 18)
	w.best.RichText = true

	-- Breakdown pop-over (hover or tap attack / defense).
	local pop = ui.makeFrame(body, UDim2.fromOffset(330, 240), UDim2.new(1, -350, 0, 212), Color3.fromRGB(22, 18, 16))
	pop.ZIndex = 600
	pop.Visible = false
	ui.addCorner(pop, 6)
	ui.art.stroke(pop, colors.gold, 2, 0)
	local title = ui.makeText(pop, UDim2.new(1, -24, 0, 40), UDim2.fromOffset(16, 8), ATTACK_COLOR, 26)
	title.Font = Enum.Font.GothamBlack
	title.ZIndex = 601
	local left = ui.makeText(pop, UDim2.new(0.6, -16, 1, -60), UDim2.fromOffset(16, 52), colors.text, 18)
	left.RichText = true
	left.TextYAlignment = Enum.TextYAlignment.Top
	left.LineHeight = 1.3
	left.ZIndex = 601
	local valuesText = ui.makeText(pop, UDim2.new(0.4, -16, 1, -60), UDim2.new(0.6, 0, 0, 52), colors.text, 18)
	valuesText.RichText = true
	valuesText.TextYAlignment = Enum.TextYAlignment.Top
	valuesText.TextXAlignment = Enum.TextXAlignment.Right
	valuesText.LineHeight = 1.3
	valuesText.Font = Enum.Font.GothamBlack
	valuesText.ZIndex = 601
	w.popover = { frame = pop, title = title, left = left, right = valuesText, values = {} }
end

function ProfilePage.draw(state, ui)
	if not state then
		return
	end
	latest = state
	if not ui.isOpen("Profile") then
		popoverKind = nil
		w.popover.frame.Visible = false
		return
	end
	local colors = ui.colors
	local stats = state.stats
	w.level.Text = tostring(state.level)
	local stars = state.rebirth.stars
	w.stars.Visible = stars > 0
	w.stars.Text = `\u{2B50} {stars}`
	w.name.Text = string.upper(ui.player.DisplayName)
	w.title.Text = if state.title ~= "" then string.upper(state.title) else `@{string.upper(ui.player.Name)}`

	-- Your own worn pieces.
	local worn = {}
	for _, item in state.gear do
		if item.wornBy == 0 then
			worn[item.slot] = item
		end
	end
	for _, slot in SLOTS do
		local part = w.slots[slot]
		local item = worn[slot]
		part.empty.Visible = item == nil
		part.art.Visible = item ~= nil
		if item then
			ui.itemArt.set(part.art, item)
			part.stroke.Color = GameConfig.getRarity(item.rarity).color
		else
			part.stroke.Color = colors.dim
		end
	end

	w.stats.renown.Text = commas(state.renown)
	w.stats.renown.TextColor3 = colors.gold
	w.stats.attack.Text = commas(stats.attack)
	w.stats.defense.Text = commas(stats.defense)
	w.stats.crew.Text = tostring(stats.crewSize)
	w.stats.income.Text = Format.short(stats.incomePerHour)
	w.stats.income.TextColor3 = Color3.fromRGB(120, 220, 120)

	local since = if state.firstSeen > 0 then os.date("!%d %b %Y", state.firstSeen) else "today"
	w.since.Text = `\u{1F4C5}  In the realm since: <b><font color="#F0C450">{since}</font></b>`
	w.best.Text = `\u{1F409}  Best foe stage: <b><font color="#F0C450">{state.highestStage}</font></b>`
	drawPopover(state, ui)
end

return ProfilePage
