-- Daily playtime rewards on the Keep page:
--   * a heading with the reset clock,
--   * a timeline panel: minutes played today along a bar with a marker
--     for every reward (lit once reached),
--   * a picture card per reward: minutes tag, chest drawing or emoji,
--     name, a filling bar with the time left, and CLAIM. Ready cards pulse
--     and their picture bobs; claimed cards get a check.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Kit = require(script.Parent:WaitForChild("Kit"))

local PlaytimeRewards = {}

local w = {}
local cards = {}
local markers = {}
local lastClaimed = {}

-- The reward as Kit.rewardArt understands it.
local function artReward(reward)
	if reward.kind == "chest" then
		return { kind = "chest", rarity = reward.rarity }
	elseif reward.kind == "gold" or reward.kind == "xpBoost" then
		return { kind = reward.kind, minutes = reward.amount or 0 }
	end
	return { kind = reward.kind }
end

local function rewardColor(reward): Color3
	if reward.kind == "chest" then
		return GameConfig.getRarity(reward.rarity).color
	elseif reward.kind == "energy" then
		return Color3.fromRGB(240, 200, 70)
	elseif reward.kind == "stamina" then
		return Color3.fromRGB(90, 150, 230)
	elseif reward.kind == "xpBoost" then
		return Color3.fromRGB(150, 110, 230)
	end
	return Kit.GOLD
end

local function note(reward): string
	if reward.kind == "gold" then
		return `{reward.amount}m of income`
	elseif reward.kind == "xpBoost" then
		return `{reward.amount}m double XP`
	elseif reward.kind == "chest" then
		return `{reward.rarity}+ gear`
	end
	return "Full refill"
end

local function lastMinutes(): number
	local rewards = GameConfig.PlaytimeRewards
	return rewards[#rewards].minutes
end

local function buildTimeline(ui, page: Instance, order: number)
	local panel = ui.makeFrame(page, UDim2.new(1, -10, 0, 92), UDim2.fromOffset(0, 0), Kit.CARD)
	panel.LayoutOrder = order
	ui.addCorner(panel, 10)
	ui.art.stroke(panel, ui.colors.gold, 1.5, 0.3)
	ui.art.grain(panel)
	local _, clockGlyph = Kit.badge(ui, panel, "\u{23F1}\u{FE0F}", 56, UDim2.fromOffset(14, 18), Color3.fromRGB(90, 70, 40))
	w.clockGlyph = clockGlyph
	local played = ui.makeText(panel, UDim2.new(0.5, -80, 0, 24), UDim2.fromOffset(82, 10), ui.colors.text, 17)
	played.Font = Enum.Font.GothamBlack
	played.RichText = true
	w.played = played
	local nextText = ui.makeText(panel, UDim2.new(0.5, -20, 0, 24), UDim2.new(0.5, 0, 0, 10), ui.colors.dim, 13)
	nextText.Font = Enum.Font.GothamBlack
	nextText.TextXAlignment = Enum.TextXAlignment.Right
	nextText.RichText = true
	w.nextText = nextText

	local track = ui.makeFrame(panel, UDim2.new(1, -110, 0, 14), UDim2.fromOffset(88, 56), Color3.fromRGB(16, 14, 12))
	ui.addCorner(track, 7)
	local fill = ui.makeFrame(track, UDim2.fromScale(0, 1), UDim2.fromOffset(0, 0), Kit.GOLD)
	ui.addCorner(fill, 7)
	ui.art.gloss(fill, 1, 0.6)
	w.fill = fill
	local total = lastMinutes()
	for index, reward in GameConfig.PlaytimeRewards do
		local share = reward.minutes / total
		local dot = ui.makeFrame(track, UDim2.fromOffset(20, 20), UDim2.new(share, -10, 0.5, -10), Color3.fromRGB(60, 52, 42))
		dot.ZIndex = fill.ZIndex + 2
		ui.addCorner(dot, 10)
		local stroke = ui.art.stroke(dot, Color3.fromRGB(20, 16, 12), 2, 0)
		local label = ui.makeText(track, UDim2.fromOffset(50, 14), UDim2.new(share, -25, 1, 6), ui.colors.dim, 10)
		label.Font = Enum.Font.GothamBlack
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.Text = `{reward.minutes}M`
		markers[index] = { dot = dot, stroke = stroke, label = label }
	end
end

local function buildCard(ui, grid: Instance, index: number, reward)
	local color = rewardColor(reward)
	local card, stroke = Kit.card(ui, grid, index, color)
	local glow = ui.makeFrame(card, UDim2.new(1, 0, 0, 110), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1))
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(color:Lerp(Color3.new(0, 0, 0), 0.45), Kit.CARD)
	gradient.Parent = glow
	local tag = ui.makeText(card, UDim2.fromOffset(64, 20), UDim2.fromOffset(8, 8), Color3.fromRGB(30, 20, 8), 11)
	tag.BackgroundTransparency = 0
	tag.BackgroundColor3 = color
	tag.Font = Enum.Font.GothamBlack
	tag.TextXAlignment = Enum.TextXAlignment.Center
	tag.Text = `\u{23F1} {reward.minutes} MIN`
	tag.ZIndex = 420
	ui.addCorner(tag, 5)
	-- the picture sits in a holder that bobs; the art fills the holder
	local holder = ui.makeFrame(card, UDim2.fromOffset(76, 76), UDim2.new(0.5, -38, 0, 22), Color3.new(0, 0, 0))
	holder.BackgroundTransparency = 1
	local art = ui.makeFrame(holder, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	art.BackgroundTransparency = 1
	Kit.rewardArt(ui, art, artReward(reward))
	local name = Kit.centered(ui, card, 102, 22, 16, ui.colors.text)
	name.Font = Enum.Font.GothamBlack
	name.Text = reward.label
	local sub = Kit.centered(ui, card, 124, 16, 12, ui.colors.dim)
	sub.Font = Enum.Font.GothamBold
	sub.Text = note(reward)
	local bar = Kit.bar(ui, card, UDim2.new(1, -24, 0, 18), UDim2.fromOffset(12, 146), color)
	local button = ui.makeButton(card, UDim2.new(1, -24, 0, 36), UDim2.new(0, 12, 1, -44), ui.colors.claim)
	button.TextSize = 14
	button.Font = Enum.Font.GothamBlack
	local check = ui.makeText(card, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Kit.GREEN, 50)
	check.BackgroundTransparency = 0.45
	check.BackgroundColor3 = Color3.new(0, 0, 0)
	check.Font = Enum.Font.GothamBlack
	check.TextXAlignment = Enum.TextXAlignment.Center
	check.Text = "\u{2714}"
	check.ZIndex = 450
	check.Visible = false
	button.Activated:Connect(function()
		Kit.pop(card, 1.12)
		Kit.float(ui, card, `+{reward.label}`, Kit.GOLD)
		ui.send("Claim", tostring(index))
	end)
	cards[index] = { card = card, stroke = stroke, holder = holder, bar = bar, button = button, check = check, color = color, ready = false }
end

function PlaytimeRewards.build(ui)
	local page = ui.pages.Keep
	local order = ui.playtimeOrder or ui.nextOrder()
	local _, _, right = Kit.heading(ui, page, order, "\u{1F381}  Daily playtime rewards", Kit.GOLD)
	w.reset = right
	buildTimeline(ui, page, order + 1)
	local grid = Kit.grid(ui, page, order + 2, 228, 4)
	for index, reward in GameConfig.PlaytimeRewards do
		buildCard(ui, grid, index, reward)
	end
	page:GetPropertyChangedSignal("Visible"):Connect(function()
		if page.Visible then
			Kit.popAll(page)
		end
	end)
	-- ready rewards bob and wiggle; the stopwatch ticks
	task.spawn(function()
		local up = false
		while true do
			task.wait(0.6)
			if not page.Visible then
				continue
			end
			up = not up
			for _, part in cards do
				local lift = if part.ready and up then -8 else 0
				TweenService:Create(part.holder, TweenInfo.new(0.55, Enum.EasingStyle.Sine), {
					Position = UDim2.new(0.5, -38, 0, 22 + lift),
					Rotation = if part.ready then (if up then 6 else -6) else 0,
				}):Play()
			end
			TweenService:Create(w.clockGlyph, TweenInfo.new(0.15), { Rotation = if up then 10 else -10 }):Play()
		end
	end)
end

function PlaytimeRewards.draw(state, ui)
	if not state or not state.claimed then
		return
	end
	local played = state.playSeconds or 0
	local dayLeft = 86400 - os.time() % 86400
	w.reset.Text = `RESETS IN {string.upper(Kit.clock(dayLeft))}`
	w.played.Text = `PLAYED TODAY  <font color="#F0C450">{math.floor(played / 3600)}h {math.floor(played / 60) % 60}m</font>`
	local total = lastMinutes() * 60
	local share = math.clamp(played / total, 0, 1)
	if math.abs(w.fill.Size.X.Scale - share) > 0.0005 then
		TweenService:Create(w.fill, TweenInfo.new(0.9, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(share, 1) }):Play()
	end

	local nextReward = nil
	local readyCount = 0
	for index, reward in GameConfig.PlaytimeRewards do
		local key = tostring(index)
		local part = cards[index]
		local claimed = state.claimed[key] == true
		local need = reward.minutes * 60
		local ready = not claimed and played >= need
		part.ready = ready
		if ready then
			readyCount += 1
		end
		if not claimed and not ready and not nextReward then
			nextReward = reward
		end
		local marker = markers[index]
		local reached = played >= need
		marker.dot.BackgroundColor3 = if claimed then Kit.GREEN elseif reached then Kit.GOLD else Color3.fromRGB(60, 52, 42)
		marker.label.TextColor3 = if reached then Kit.GOLD else ui.colors.dim

		part.check.Visible = claimed
		if claimed and lastClaimed[key] == false then
			Kit.pop(part.card, 1.15)
		end
		lastClaimed[key] = claimed
		Kit.setPulse(part.stroke, ready, part.color)
		if claimed then
			Kit.setBar(part.bar, 1, 1, "CLAIMED")
			ui.setButton(part.button, "\u{2714} CLAIMED", false, ui.colors.buy)
		elseif ready then
			Kit.setBar(part.bar, 1, 1, "READY!")
			ui.setButton(part.button, "\u{1F381} CLAIM!", true, ui.colors.claim)
		else
			Kit.setBar(part.bar, played, need, `{ui.formatClock(need - played)} LEFT`)
			ui.setButton(part.button, `IN {ui.formatClock(need - played)}`, false, ui.colors.buy)
		end
	end
	if readyCount > 0 then
		w.nextText.Text = `<font color="#6ED26E">{readyCount} READY TO CLAIM</font>`
	elseif nextReward then
		w.nextText.Text = `NEXT: <font color="#FFFFFF">{string.upper(nextReward.label)}</font> IN {ui.formatClock(nextReward.minutes * 60 - played)}`
	else
		w.nextText.Text = "ALL CLAIMED TODAY \u{2714}"
	end
end

return PlaytimeRewards
