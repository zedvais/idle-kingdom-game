-- Royal Pass page, laid out like a battle pass:
--   * a hero banner: season, time left, a big tier badge, the points bar
--     to the next tier, CLAIM ALL and BUY TIER,
--   * a Noble track banner (unlock offer, or "unlocked"),
--   * a sideways track of all 50 tiers: FREE rewards on top, NOBLE rewards
--     below, a progress line with tier badges through the middle. Rewards
--     ready to take glow and pulse; press one to claim that tier. Claimed
--     ones get a check. Arrows scroll; the track jumps to your tier.
--   * weekly challenges as cards with progress bars.
-- Animations: claim pop and "+reward" float, tier-up banner with confetti,
-- the points bar sliding, pulsing glows on claimable rewards.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local StoreConfig = require(Shared:WaitForChild("StoreConfig"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Format = require(Shared:WaitForChild("Format"))

local RoyalPassPage = {}

local COL = 136 -- width of one tier column
local CARD_W, CARD_H = 118, 150
local PAD = 16
local LINE_Y = 186 -- the progress line, middle of the track
local TRACK_H = 380

local PURPLE = Color3.fromRGB(70, 40, 110)
local NOBLE = Color3.fromRGB(240, 196, 80)
local GREEN = Color3.fromRGB(90, 200, 100)
local CHECK = "\u{2714}"
local LOCK = "\u{1F512}"
local CROWN = "\u{1F451}"
local STAR = "\u{2B50}"
local LEFT, RIGHT = "\u{25C0}", "\u{25B6}"

local KIND_COLORS = {
	gold = Color3.fromRGB(120, 86, 24),
	crowns = Color3.fromRGB(92, 52, 130),
	xpBoost = Color3.fromRGB(46, 84, 140),
	tokens = Color3.fromRGB(110, 70, 40),
	skill = Color3.fromRGB(46, 110, 64),
}
local KIND_GLYPHS = {
	gold = "\u{1F4B0}",
	crowns = CROWN,
	xpBoost = STAR,
	tokens = "\u{1F3C5}",
	skill = "\u{1F4AA}",
}

local w = {}
local columns = {} -- [tier] = { free = card, noble = card, badge, ... }
local latest = nil
local lastTier = nil
local jumped = false
local pulsing = {} -- cards that can be claimed now
local barShown = 0 -- share of the points bar shown now (for the slide)

local function shortText(reward): string
	local kind = reward.kind
	if kind == "gold" and reward.minutes then
		return if reward.minutes % 60 == 0 then `{reward.minutes // 60}h income` else `{reward.minutes}m income`
	elseif kind == "crowns" then
		return `{reward.amount} Crowns`
	elseif kind == "xpBoost" then
		return `{reward.minutes}m 2x XP`
	elseif kind == "tokens" then
		return `{reward.amount} Tokens`
	elseif kind == "chest" then
		return `{reward.rarity} Chest`
	elseif kind == "skill" then
		return if reward.amount == 1 then "1 Skill pt" else `{reward.amount} Skill pts`
	end
	return StoreConfig.describe(reward)
end

local function days(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local d = seconds // 86400
	local h = seconds % 86400 // 3600
	local m = seconds % 3600 // 60
	if d > 0 then
		return `{d}d {h}h`
	elseif h > 0 then
		return `{h}h {m}m`
	end
	return `{m}m {seconds % 60}s`
end

local function pop(object: GuiObject, from: number)
	local scale = object:FindFirstChild("PopScale") :: UIScale?
	if not scale then
		local made = Instance.new("UIScale")
		made.Name = "PopScale"
		made.Parent = object
		scale = made
	end
	if scale then
		scale.Scale = from
		TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

local function float(ui, parent: GuiObject, text: string, color: Color3)
	local label = ui.makeText(parent, UDim2.fromOffset(200, 30), UDim2.new(0.5, -100, 0, 40), color, 20)
	label.Font = Enum.Font.GothamBlack
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextStrokeTransparency = 0.2
	label.ZIndex = 600
	label.Text = text
	local tween = TweenService:Create(label, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, -100, 0, -20),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	tween:Play()
	tween.Completed:Connect(function()
		label:Destroy()
	end)
end

---------------------------------------------------------------------------
-- Building: hero banner
---------------------------------------------------------------------------

local function buildHero(ui, page: Instance)
	local colors = ui.colors
	local hero = ui.makeFrame(page, UDim2.new(1, -10, 0, 178), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1))
	hero.LayoutOrder = 1
	hero.ClipsDescendants = true
	ui.addCorner(hero, 10)
	ui.art.stroke(hero, colors.gold, 2, 0)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 15
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(46, 22, 80)),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(96, 48, 140)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 96, 40)),
	})
	gradient.Parent = hero
	ui.art.skyline(hero, Color3.fromRGB(20, 10, 34), 0.35)
	ui.art.grain(hero)
	ui.art.shine(hero, 6)
	w.hero = hero

	local title = ui.makeText(hero, UDim2.new(0.36, -80, 0, 56), UDim2.fromOffset(22, 10), colors.gold, 48)
	title.Font = ui.art.Fonts.title
	title.Text = "Royal Pass"
	title.TextStrokeTransparency = 0.4
	title.ZIndex = 410
	w.season = ui.makeText(hero, UDim2.new(0.36, -80, 0, 22), UDim2.fromOffset(24, 64), Color3.new(1, 1, 1), 16)
	w.season.Font = Enum.Font.GothamBlack
	w.season.ZIndex = 410
	w.ends = ui.makeText(hero, UDim2.new(0.36, -80, 0, 20), UDim2.fromOffset(24, 88), Color3.fromRGB(230, 210, 255), 14)
	w.ends.Font = Enum.Font.GothamBold
	w.ends.ZIndex = 410

	-- Big tier badge.
	local badge = ui.makeFrame(hero, UDim2.fromOffset(100, 100), UDim2.new(0.36, -50, 0, 18), colors.gold)
	ui.addCorner(badge, 50)
	ui.art.gloss(badge, 1, 0.55)
	ui.art.stroke(badge, Color3.fromRGB(90, 60, 10), 4, 0)
	badge.ZIndex = 410
	local tierWord = ui.makeText(badge, UDim2.new(1, 0, 0, 20), UDim2.fromOffset(0, 14), Color3.fromRGB(70, 40, 10), 14)
	tierWord.Font = Enum.Font.GothamBlack
	tierWord.TextXAlignment = Enum.TextXAlignment.Center
	tierWord.Text = "TIER"
	tierWord.ZIndex = 411
	w.tier = ui.makeText(badge, UDim2.new(1, 0, 0, 52), UDim2.fromOffset(0, 32), Color3.fromRGB(60, 30, 6), 46)
	w.tier.Font = Enum.Font.GothamBlack
	w.tier.TextXAlignment = Enum.TextXAlignment.Center
	w.tier.ZIndex = 411
	w.badge = badge

	-- Points bar to the next tier.
	local bar = ui.makeFrame(hero, UDim2.new(0.36, -60, 0, 30), UDim2.new(0.36, 62, 0, 54), Color3.fromRGB(20, 12, 30))
	ui.addCorner(bar, 8)
	ui.art.stroke(bar, Color3.new(0, 0, 0), 1.5, 0.2)
	bar.ZIndex = 410
	local fill = ui.makeFrame(bar, UDim2.fromScale(0, 1), UDim2.fromOffset(0, 0), Color3.fromRGB(250, 200, 70))
	ui.addCorner(fill, 8)
	ui.art.gloss(fill, 1, 0.6)
	fill.ZIndex = 411
	w.barText = ui.makeText(bar, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1), 15)
	w.barText.Font = Enum.Font.GothamBlack
	w.barText.TextXAlignment = Enum.TextXAlignment.Center
	w.barText.TextStrokeTransparency = 0.3
	w.barText.ZIndex = 412
	w.fill = fill
	w.next = ui.makeText(hero, UDim2.new(0.36, -60, 0, 20), UDim2.new(0.36, 62, 0, 30), Color3.new(1, 1, 1), 14)
	w.next.Font = Enum.Font.GothamBlack
	w.next.ZIndex = 410
	w.how = ui.makeText(hero, UDim2.new(0.36, -60, 0, 40), UDim2.new(0.36, 62, 0, 90), Color3.fromRGB(230, 210, 255), 12)
	w.how.ZIndex = 410
	w.how.Text = "Points come from quests, foes, playtime rewards and weekly challenges."

	-- Buttons.
	w.claimAll = ui.makeButton(hero, UDim2.new(0.22, 0, 0, 56), UDim2.new(0.76, 0, 0, 24), ui.colors.claim)
	w.claimAll.TextSize = 20
	w.claimAll.Font = Enum.Font.GothamBlack
	w.claimAll.ZIndex = 410
	w.claimAll.Activated:Connect(function()
		ui.send("PassClaim", "all")
	end)
	w.skip = ui.makeButton(hero, UDim2.new(0.22, 0, 0, 48), UDim2.new(0.76, 0, 0, 92), ui.colors.selected)
	w.skip.TextSize = 16
	w.skip.Font = Enum.Font.GothamBlack
	w.skip.ZIndex = 410
	w.skip.Activated:Connect(function()
		ui.send("PassSkip")
	end)
end

local function buildNoble(ui, page: Instance)
	local strip = ui.makeFrame(page, UDim2.new(1, -10, 0, 78), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1))
	strip.LayoutOrder = 2
	strip.ClipsDescendants = true
	ui.addCorner(strip, 10)
	ui.art.stroke(strip, NOBLE, 2, 0)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromRGB(120, 80, 20), Color3.fromRGB(60, 36, 10))
	gradient.Parent = strip
	ui.art.shine(strip, 3)
	local crown = ui.makeText(strip, UDim2.fromOffset(70, 78), UDim2.fromOffset(10, 0), Color3.new(1, 1, 1), 46)
	crown.TextXAlignment = Enum.TextXAlignment.Center
	crown.Text = CROWN
	crown.ZIndex = 410
	w.nobleTitle = ui.makeText(strip, UDim2.new(1, -360, 0, 30), UDim2.fromOffset(86, 10), NOBLE, 24)
	w.nobleTitle.Font = ui.art.Fonts.heading
	w.nobleTitle.ZIndex = 410
	w.nobleNote = ui.makeText(strip, UDim2.new(1, -360, 0, 30), UDim2.fromOffset(86, 40), Color3.fromRGB(255, 236, 200), 14)
	w.nobleNote.ZIndex = 410
	w.nobleButton = ui.makeButton(strip, UDim2.fromOffset(240, 52), UDim2.new(1, -256, 0, 13), NOBLE)
	w.nobleButton.TextSize = 20
	w.nobleButton.Font = Enum.Font.GothamBlack
	w.nobleButton.ZIndex = 410
	w.nobleButton.Activated:Connect(function()
		if latest and not latest.pass.noble then
			ui.send("Robux", "product:passPremium")
		end
	end)
	w.noble = strip
end

---------------------------------------------------------------------------
-- Building: the track
---------------------------------------------------------------------------

local function coin(ui, parent: Instance, size: number)
	local disc = ui.makeFrame(parent, UDim2.fromOffset(size, size), UDim2.new(0.5, -size / 2, 0.5, -size / 2), ui.colors.gold)
	ui.addCorner(disc, size)
	ui.art.gloss(disc, 1, 0.55)
	ui.art.stroke(disc, Color3.fromRGB(120, 80, 20), 2, 0)
	local inner = ui.makeFrame(disc, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.25, 0.25), Color3.fromRGB(200, 140, 40))
	ui.addCorner(inner, size)
end

local function buildCard(ui, parent: Instance, tier: number, track: string, y: number)
	local colors = ui.colors
	local reward = StoreConfig.PassRewards[tier][track]
	local milestone = tier % 10 == 0
	local base = KIND_COLORS[reward.kind] or Color3.fromRGB(60, 50, 40)
	if reward.kind == "chest" then
		base = GameConfig.getRarity(reward.rarity).color:Lerp(Color3.new(0, 0, 0), 0.6)
	end
	local x = PAD + (tier - 1) * COL + (COL - CARD_W) / 2
	local card = ui.makeFrame(parent, UDim2.fromOffset(CARD_W, CARD_H), UDim2.fromOffset(x, y), Color3.new(1, 1, 1))
	ui.addCorner(card, 10)
	-- A clear button on top takes the clicks (the card keeps one gradient
	-- and one stroke of its own).
	local hit = ui.makeButton(card, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.ZIndex = 450
	hit:SetAttribute("NoGlow", true)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(base:Lerp(Color3.new(1, 1, 1), 0.12), base:Lerp(Color3.new(0, 0, 0), 0.55))
	gradient.Parent = card
	local stroke = ui.art.stroke(card, if track == "noble" then NOBLE else Color3.fromRGB(200, 190, 170), if milestone then 3 else 1.5, 0.3)

	-- Picture.
	local picture = ui.makeFrame(card, UDim2.fromOffset(78, 78), UDim2.new(0.5, -39, 0, 18), Color3.new(0, 0, 0))
	picture.BackgroundTransparency = 1
	if reward.kind == "chest" then
		ui.itemArt.chest(picture, reward.rarity)
	elseif reward.kind == "tokens" then
		coin(ui, picture, 56)
	else
		local glyph = ui.makeText(picture, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1), 54)
		glyph.TextXAlignment = Enum.TextXAlignment.Center
		glyph.Text = KIND_GLYPHS[reward.kind] or "\u{1F381}"
	end
	if milestone then
		local tag = ui.makeText(card, UDim2.new(1, -12, 0, 16), UDim2.fromOffset(6, 4), NOBLE, 11)
		tag.Font = Enum.Font.GothamBlack
		tag.TextXAlignment = Enum.TextXAlignment.Center
		tag.Text = `{STAR} MILESTONE {STAR}`
		tag.ZIndex = 405
		ui.art.shine(card, 3)
	end

	local label = ui.makeText(card, UDim2.new(1, -8, 0, 36), UDim2.new(0, 4, 1, -48), Color3.new(1, 1, 1), 14)
	label.Font = Enum.Font.GothamBlack
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextStrokeTransparency = 0.4
	label.Text = shortText(reward)
	label.ZIndex = 405
	if reward.kind == "chest" then
		label.TextColor3 = GameConfig.getRarity(reward.rarity).color:Lerp(Color3.new(1, 1, 1), 0.3)
	end

	-- CLAIM ribbon, claimed check, lock.
	local ribbon = ui.makeText(card, UDim2.new(1, 0, 0, 26), UDim2.new(0, 0, 1, -26), Color3.fromRGB(30, 50, 20), 15)
	ribbon.BackgroundTransparency = 0
	ribbon.BackgroundColor3 = GREEN
	ribbon.Font = Enum.Font.GothamBlack
	ribbon.TextXAlignment = Enum.TextXAlignment.Center
	ribbon.Text = "CLAIM!"
	ribbon.ZIndex = 420
	ui.addCorner(ribbon, 8)
	local done = ui.makeFrame(card, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	done.BackgroundTransparency = 0.45
	done.ZIndex = 430
	ui.addCorner(done, 10)
	local check = ui.makeText(done, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), GREEN, 56)
	check.Font = Enum.Font.GothamBlack
	check.TextXAlignment = Enum.TextXAlignment.Center
	check.Text = CHECK
	check.TextStrokeTransparency = 0.3
	check.ZIndex = 431
	local shade = ui.makeFrame(card, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	shade.BackgroundTransparency = 0.5
	shade.ZIndex = 425
	ui.addCorner(shade, 10)
	local lock = ui.makeText(card, UDim2.fromOffset(28, 28), UDim2.new(1, -30, 0, 2), Color3.new(1, 1, 1), 18)
	lock.TextXAlignment = Enum.TextXAlignment.Center
	lock.Text = LOCK
	lock.ZIndex = 432

	local part = {
		card = card,
		stroke = stroke,
		picture = picture,
		ribbon = ribbon,
		done = done,
		shade = shade,
		lock = lock,
		reward = reward,
		tier = tier,
		track = track,
		milestone = milestone,
		claimable = false,
	}
	hit.Activated:Connect(function()
		if part.claimable then
			pop(card, 1.18)
			float(ui, card, `+{shortText(reward)}`, NOBLE)
			ui.send("PassClaim", tostring(tier))
		elseif latest then
			pop(card, 0.92)
		end
	end)
	return part
end

local function buildTrack(ui, page: Instance)
	local colors = ui.colors
	local panel = ui.makeFrame(page, UDim2.new(1, -10, 0, TRACK_H + 20), UDim2.fromOffset(0, 0), Color3.fromRGB(28, 22, 34))
	panel.LayoutOrder = 3
	ui.addCorner(panel, 10)
	ui.art.stroke(panel, colors.gold, 1.5, 0.4)

	-- Row labels on the left.
	local side = ui.makeFrame(panel, UDim2.new(0, 96, 1, -20), UDim2.fromOffset(10, 10), Color3.fromRGB(20, 16, 26))
	ui.addCorner(side, 8)
	local free = ui.makeText(side, UDim2.new(1, 0, 0.5, -20), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1), 20)
	free.Font = Enum.Font.GothamBlack
	free.TextXAlignment = Enum.TextXAlignment.Center
	free.Text = "FREE"
	local noble = ui.makeText(side, UDim2.new(1, 0, 0.5, -20), UDim2.new(0, 0, 0.5, 20), NOBLE, 20)
	noble.Font = Enum.Font.GothamBlack
	noble.TextXAlignment = Enum.TextXAlignment.Center
	noble.Text = `{CROWN}\nNOBLE`
	w.nobleLabel = noble

	-- The scrolling track.
	local track = Instance.new("ScrollingFrame")
	track.Size = UDim2.new(1, -170, 1, -10)
	track.Position = UDim2.fromOffset(140, 6)
	track.BackgroundTransparency = 1
	track.BorderSizePixel = 0
	track.ScrollingDirection = Enum.ScrollingDirection.X
	track.ScrollBarThickness = 8
	track.ScrollBarImageColor3 = colors.gold
	track.CanvasSize = UDim2.fromOffset(PAD * 2 + (StoreConfig.PassTiers + 1) * COL + 20, 0)
	track.ElasticBehavior = Enum.ElasticBehavior.Never
	track.Parent = panel
	w.track = track

	-- Progress line through the middle.
	local lineBack = ui.makeFrame(track, UDim2.fromOffset(StoreConfig.PassTiers * COL, 12), UDim2.fromOffset(PAD, LINE_Y - 6), Color3.fromRGB(14, 10, 20))
	ui.addCorner(lineBack, 6)
	local lineFill = ui.makeFrame(lineBack, UDim2.fromScale(0, 1), UDim2.fromOffset(0, 0), colors.gold)
	ui.addCorner(lineFill, 6)
	ui.art.gloss(lineFill, 1, 0.6)
	w.lineFill = lineFill

	for tier = 1, StoreConfig.PassTiers do
		local milestone = tier % 10 == 0
		local size = if milestone then 46 else 36
		local cx = PAD + (tier - 1) * COL + COL / 2
		local badge = ui.makeFrame(track, UDim2.fromOffset(size, size), UDim2.fromOffset(cx - size / 2, LINE_Y - size / 2), Color3.fromRGB(60, 50, 70))
		ui.addCorner(badge, size)
		local ring = ui.art.stroke(badge, Color3.fromRGB(20, 14, 26), 3, 0)
		badge.ZIndex = 300
		local number = ui.makeText(badge, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1), if milestone then 18 else 15)
		number.Font = Enum.Font.GothamBlack
		number.TextXAlignment = Enum.TextXAlignment.Center
		number.Text = tostring(tier)
		number.ZIndex = 301
		columns[tier] = {
			free = buildCard(ui, track, tier, "free", LINE_Y - 30 - CARD_H),
			noble = buildCard(ui, track, tier, "noble", LINE_Y + 30),
			badge = badge,
			ring = ring,
			number = number,
		}
	end

	-- 50+ bonus: one tall card after the last tier, paid again and again.
	do
		local x = PAD + StoreConfig.PassTiers * COL + 10
		local top = LINE_Y - 30 - CARD_H
		local card = ui.makeFrame(track, UDim2.fromOffset(CARD_W + 10, CARD_H * 2 + 60), UDim2.fromOffset(x, top), Color3.new(1, 1, 1))
		ui.addCorner(card, 12)
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Color = ColorSequence.new(Color3.fromRGB(150, 110, 30), Color3.fromRGB(50, 30, 10))
		gradient.Parent = card
		local stroke = ui.art.stroke(card, NOBLE, 2, 0.2)
		ui.art.shine(card, 3)
		local title = ui.makeText(card, UDim2.new(1, -8, 0, 40), UDim2.fromOffset(4, 10), NOBLE, 22)
		title.Font = Enum.Font.GothamBlack
		title.TextXAlignment = Enum.TextXAlignment.Center
		title.Text = "50+\nBONUS"
		title.ZIndex = 405
		local picture = ui.makeText(card, UDim2.new(1, 0, 0, 80), UDim2.fromOffset(0, 70), Color3.new(1, 1, 1), 58)
		picture.TextXAlignment = Enum.TextXAlignment.Center
		picture.Text = KIND_GLYPHS[StoreConfig.BonusReward.kind] or "\u{1F381}"
		picture.ZIndex = 405
		local note = ui.makeText(card, UDim2.new(1, -10, 0, 56), UDim2.fromOffset(5, 156), Color3.new(1, 1, 1), 13)
		note.Font = Enum.Font.GothamBold
		note.TextXAlignment = Enum.TextXAlignment.Center
		note.Text = `{shortText(StoreConfig.BonusReward)} every {StoreConfig.BonusPoints} points after tier {StoreConfig.PassTiers}`
		note.ZIndex = 405
		local back = ui.makeFrame(card, UDim2.new(1, -16, 0, 18), UDim2.fromOffset(8, 222), Color3.fromRGB(20, 12, 6))
		ui.addCorner(back, 6)
		back.ZIndex = 405
		local fill = ui.makeFrame(back, UDim2.fromScale(0, 1), UDim2.fromOffset(0, 0), NOBLE)
		ui.addCorner(fill, 6)
		fill.ZIndex = 406
		local count = ui.makeText(back, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1), 11)
		count.Font = Enum.Font.GothamBlack
		count.TextXAlignment = Enum.TextXAlignment.Center
		count.TextStrokeTransparency = 0.3
		count.ZIndex = 407
		local ribbon = ui.makeText(card, UDim2.new(1, 0, 0, 40), UDim2.new(0, 0, 1, -40), Color3.fromRGB(30, 50, 20), 15)
		ribbon.BackgroundTransparency = 0
		ribbon.BackgroundColor3 = GREEN
		ribbon.Font = Enum.Font.GothamBlack
		ribbon.TextXAlignment = Enum.TextXAlignment.Center
		ribbon.ZIndex = 420
		ui.addCorner(ribbon, 10)
		local hit = ui.makeButton(card, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.ZIndex = 450
		hit:SetAttribute("NoGlow", true)
		local part = {
			card = card,
			stroke = stroke,
			picture = ui.makeFrame(card, UDim2.fromOffset(0, 0), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0)),
			fill = fill,
			count = count,
			ribbon = ribbon,
			claimable = false,
		}
		part.picture.Visible = false
		hit.Activated:Connect(function()
			if part.claimable then
				pop(card, 1.12)
				float(ui, card, `+{shortText(StoreConfig.BonusReward)}`, NOBLE)
				ui.send("PassClaim", "bonus")
			else
				pop(card, 0.95)
			end
		end)
		w.bonus = part
	end

	-- Arrows.
	local function arrow(text: string, x: UDim, step: number)
		local button = ui.makeButton(panel, UDim2.fromOffset(28, 80), UDim2.new(x.Scale, x.Offset, 0.5, -40), Color3.fromRGB(50, 40, 60))
		button.Text = text
		button.TextSize = 16
		button.ZIndex = 500
		button.Activated:Connect(function()
			local maxX = math.max(0, track.AbsoluteCanvasSize.X - track.AbsoluteWindowSize.X)
			local goal = math.clamp(track.CanvasPosition.X + step * COL * 4, 0, maxX)
			TweenService:Create(track, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { CanvasPosition = Vector2.new(goal, 0) }):Play()
		end)
	end
	arrow(LEFT, UDim.new(0, 110), -1)
	arrow(RIGHT, UDim.new(1, -28), 1)
end

---------------------------------------------------------------------------
-- Building: weekly challenges
---------------------------------------------------------------------------

local CHALLENGE_GLYPHS = { energy = "\u{26A1}", foes = "\u{1F409}", market = "\u{2696}\u{FE0F}", play = "\u{231B}" }

local function buildWeekly(ui, page: Instance)
	local colors = ui.colors
	local head = ui.makeFrame(page, UDim2.new(1, -10, 0, 44), UDim2.fromOffset(0, 0), Color3.fromRGB(44, 36, 22))
	head.LayoutOrder = 4
	ui.addCorner(head, 6)
	local title = ui.makeText(head, UDim2.new(0.5, 0, 1, 0), UDim2.fromOffset(16, 0), colors.gold, 22)
	title.Font = ui.art.Fonts.heading
	title.Text = "Weekly challenges"
	w.weekLeft = ui.makeText(head, UDim2.new(0.5, -20, 1, 0), UDim2.new(0.5, 0, 0, 0), colors.dim, 14)
	w.weekLeft.Font = Enum.Font.GothamBold
	w.weekLeft.TextXAlignment = Enum.TextXAlignment.Right

	local grid = ui.makeFrame(page, UDim2.new(1, -10, 0, 0), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	grid.BackgroundTransparency = 1
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.LayoutOrder = 5
	local layout = Instance.new("UIGridLayout")
	layout.CellPadding = UDim2.fromOffset(12, 12)
	layout.CellSize = UDim2.new(0.5, -6, 0, 112)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	w.challenges = {}
	for index, challenge in StoreConfig.WeeklyChallenges do
		local card = ui.makeFrame(grid, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.fromRGB(34, 29, 24))
		card.LayoutOrder = index
		ui.addCorner(card, 8)
		local stroke = ui.art.stroke(card, colors.dim, 1, 0.5)
		local icon = ui.makeFrame(card, UDim2.fromOffset(72, 72), UDim2.fromOffset(14, 20), PURPLE)
		ui.addCorner(icon, 12)
		ui.art.gloss(icon, 1, 0.6)
		local glyph = ui.makeText(icon, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1), 40)
		glyph.TextXAlignment = Enum.TextXAlignment.Center
		glyph.Text = CHALLENGE_GLYPHS[challenge.key] or STAR
		glyph.ZIndex = icon.ZIndex + 2
		local name = ui.makeText(card, UDim2.new(1, -250, 0, 24), UDim2.fromOffset(100, 14), colors.text, 17)
		name.Font = Enum.Font.GothamBold
		name.Text = challenge.name
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local reward = ui.makeText(card, UDim2.fromOffset(110, 26), UDim2.new(1, -124, 0, 12), Color3.fromRGB(40, 24, 6), 13)
		reward.BackgroundTransparency = 0
		reward.BackgroundColor3 = colors.gold
		reward.Font = Enum.Font.GothamBlack
		reward.TextXAlignment = Enum.TextXAlignment.Center
		reward.Text = `+{challenge.points} POINTS`
		ui.addCorner(reward, 6)
		local back = ui.makeFrame(card, UDim2.new(1, -250, 0, 26), UDim2.fromOffset(100, 52), Color3.fromRGB(16, 14, 12))
		ui.addCorner(back, 6)
		local fill = ui.makeFrame(back, UDim2.fromScale(0, 1), UDim2.fromOffset(0, 0), Color3.fromRGB(150, 100, 230))
		ui.addCorner(fill, 6)
		ui.art.gloss(fill, 1, 0.65)
		local value = ui.makeText(back, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1), 13)
		value.Font = Enum.Font.GothamBlack
		value.TextXAlignment = Enum.TextXAlignment.Center
		value.TextStrokeTransparency = 0.4
		value.ZIndex = fill.ZIndex + 1
		local button = ui.makeButton(card, UDim2.fromOffset(130, 48), UDim2.new(1, -144, 0, 50), colors.claim)
		button.TextSize = 16
		button.Font = Enum.Font.GothamBlack
		button.Activated:Connect(function()
			pop(card, 1.05)
			ui.send("WeeklyClaim", challenge.key)
		end)
		w.challenges[challenge.key] = { card = card, stroke = stroke, fill = fill, value = value, button = button }
	end
end

---------------------------------------------------------------------------
-- Tier up: a banner and confetti over the hero
---------------------------------------------------------------------------

local function tierUp(ui, tier: number)
	pop(w.badge, 1.5)
	local hero = w.hero
	local ribbon = ui.makeText(hero, UDim2.fromOffset(420, 60), UDim2.new(0.5, -210, 0, -70), NOBLE, 38)
	ribbon.Font = ui.art.Fonts.title
	ribbon.TextXAlignment = Enum.TextXAlignment.Center
	ribbon.BackgroundTransparency = 0.1
	ribbon.BackgroundColor3 = Color3.fromRGB(70, 20, 30)
	ribbon.TextStrokeTransparency = 0.2
	ribbon.Text = `Tier {tier} reached!`
	ribbon.ZIndex = 700
	ui.addCorner(ribbon, 10)
	ui.art.stroke(ribbon, NOBLE, 2, 0)
	TweenService:Create(ribbon, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, -210, 0, 58) }):Play()
	local palette = { NOBLE, GREEN, Color3.fromRGB(150, 100, 230), Color3.fromRGB(240, 90, 90), Color3.new(1, 1, 1) }
	for _ = 1, 36 do
		local size = math.random(6, 11)
		local bit = ui.makeFrame(hero, UDim2.fromOffset(size, size), UDim2.new(math.random(), 0, 0, -12), palette[math.random(1, #palette)])
		bit.ZIndex = 690
		bit.Rotation = math.random(0, 90)
		local fall = 1 + math.random() * 1.2
		task.delay(math.random() * 0.5, function()
			TweenService:Create(bit, TweenInfo.new(fall, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = bit.Position + UDim2.new((math.random() - 0.5) * 0.15, 0, 0, 200),
				Rotation = math.random(-360, 360),
			}):Play()
			task.wait(fall)
			bit:Destroy()
		end)
	end
	task.delay(2.4, function()
		local leave = TweenService:Create(ribbon, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Position = UDim2.new(0.5, -210, 0, -80) })
		leave:Play()
		leave.Completed:Connect(function()
			ribbon:Destroy()
		end)
	end)
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------

function RoyalPassPage.build(ui)
	local page = ui.pages["Royal Pass"]
	buildHero(ui, page)
	buildNoble(ui, page)
	buildTrack(ui, page)
	buildWeekly(ui, page)

	-- Claimable rewards pulse; the points bar slides to its new value.
	local clock = 0
	RunService.RenderStepped:Connect(function(dt)
		if not page.Visible then
			return
		end
		clock += dt
		local wave = (math.sin(clock * 5) + 1) / 2
		for _, part in pulsing do
			part.stroke.Thickness = 2 + wave * 3
			part.stroke.Transparency = 0.1 * wave
			part.stroke.Color = GREEN:Lerp(NOBLE, wave)
			part.picture.Position = UDim2.new(0.5, -39, 0, 16 + wave * 4)
		end
		if w.goal then
			barShown += (w.goal - barShown) * math.min(1, dt * 6)
			w.fill.Size = UDim2.fromScale(barShown, 1)
		end
		if not w.nobleOwned then
			w.nobleButton.Rotation = math.sin(clock * 3) * 2
		end
	end)

	-- Jump to the current tier the first time the page shows.
	page:GetPropertyChangedSignal("Visible"):Connect(function()
		if page.Visible then
			jumped = false
			RoyalPassPage.draw(latest, ui)
		end
	end)
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function drawCard(part, reached: boolean, claimed: boolean, locked: boolean)
	part.done.Visible = claimed
	part.lock.Visible = locked and not claimed
	part.shade.Visible = locked and not claimed
	part.claimable = reached and not claimed and not locked
	part.ribbon.Visible = part.claimable
	if part.claimable then
		table.insert(pulsing, part)
	else
		part.stroke.Thickness = if part.milestone then 3 else 1.5
		part.stroke.Transparency = if reached then 0.1 else 0.45
		part.stroke.Color = if part.track == "noble" then NOBLE else Color3.fromRGB(200, 190, 170)
		part.picture.Position = UDim2.new(0.5, -39, 0, 18)
	end
end

function RoyalPassPage.draw(state, ui)
	if not state then
		return
	end
	latest = state
	local colors = ui.colors
	local pass = state.pass
	local tier = StoreConfig.getTier(pass.points)
	local maxTier = StoreConfig.PassTiers

	-- Hero.
	w.season.Text = `SEASON {pass.season + 1}`
	w.ends.Text = `Ends in {days(state.passSecondsLeft or 0)}`
	w.tier.Text = tostring(tier)
	if tier >= maxTier then
		w.goal = 1
		w.barText.Text = "EVERY TIER REACHED"
		w.next.Text = "Season complete!"
	else
		local into = pass.points - tier * StoreConfig.PointsPerTier
		w.goal = into / StoreConfig.PointsPerTier
		w.barText.Text = `{into} / {StoreConfig.PointsPerTier} POINTS`
		w.next.Text = `NEXT: TIER {tier + 1}`
	end
	if lastTier and tier > lastTier and ui.pages["Royal Pass"].Visible then
		tierUp(ui, tier)
		jumped = false
	end
	lastTier = tier

	-- Noble banner.
	w.nobleOwned = pass.noble == true
	if pass.noble then
		w.nobleTitle.Text = "Noble track unlocked"
		w.nobleNote.Text = "Every tier gives you its Noble reward too. Claim them on the track below."
		ui.setButton(w.nobleButton, `{CHECK} UNLOCKED`, false, NOBLE)
		w.nobleButton.Rotation = 0
	else
		local product = StoreConfig.getProduct("passPremium")
		w.nobleTitle.Text = "Unlock the Noble track"
		w.nobleNote.Text = "A second reward on all 50 tiers: Crowns, skill points, Legendary and Mythic chests. Earlier tiers pay out at once."
		ui.setButton(w.nobleButton, `UNLOCK  {ui.robuxText(product and product.price or 0)}`, true, NOBLE)
	end
	w.nobleLabel.TextTransparency = if pass.noble then 0 else 0.35

	-- Track.
	table.clear(pulsing)
	local claimable = 0
	for index = 1, maxTier do
		local key = tostring(index)
		local column = columns[index]
		local reached = index <= tier
		local freeDone = pass.claimedFree[key] == true
		local nobleDone = pass.claimedNoble[key] == true
		drawCard(column.free, reached, freeDone, false)
		drawCard(column.noble, reached, nobleDone, not pass.noble)
		if reached and (not freeDone or (pass.noble and not nobleDone)) then
			claimable += 1
		end
		column.badge.BackgroundColor3 = if reached then colors.gold else Color3.fromRGB(60, 50, 70)
		column.number.TextColor3 = if reached then Color3.fromRGB(50, 30, 6) else Color3.new(1, 1, 1)
		column.ring.Color = if index == tier + 1 then Color3.new(1, 1, 1) else Color3.fromRGB(20, 14, 26)
	end
	-- 50+ bonus card.
	do
		local part = w.bonus
		local bonus = pass.bonus or 0
		local ready = math.max(0, math.floor(bonus / StoreConfig.BonusPoints) - (pass.bonusClaimed or 0))
		local into = bonus % StoreConfig.BonusPoints
		part.fill.Size = UDim2.fromScale(if tier >= maxTier then into / StoreConfig.BonusPoints else 0, 1)
		part.count.Text = if tier >= maxTier then `{into} / {StoreConfig.BonusPoints}` else `Reach tier {maxTier}`
		part.claimable = ready > 0
		part.ribbon.Visible = true
		part.ribbon.Text = if ready > 0 then `CLAIM x{ready}!` else "KEEP EARNING"
		part.ribbon.BackgroundColor3 = if ready > 0 then GREEN else Color3.fromRGB(70, 60, 50)
		part.ribbon.TextColor3 = if ready > 0 then Color3.fromRGB(30, 50, 20) else Color3.fromRGB(200, 190, 170)
		if ready > 0 then
			claimable += 1
			table.insert(pulsing, part)
		else
			part.stroke.Thickness = 2
			part.stroke.Color = NOBLE
			part.stroke.Transparency = 0.2
		end
	end
	local lineShare = math.clamp((tier - 0.5) / maxTier, 0, 1)
	if tier < maxTier then
		local into = (pass.points - tier * StoreConfig.PointsPerTier) / StoreConfig.PointsPerTier
		lineShare = math.clamp((tier - 0.5 + into) / maxTier, 0, 1)
	end
	TweenService:Create(w.lineFill, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(lineShare, 1) }):Play()

	ui.setButton(w.claimAll, if claimable > 0 then `CLAIM ALL ({claimable})` else "NOTHING TO CLAIM", claimable > 0, colors.claim)
	ui.setButton(w.skip, `BUY TIER  {StoreConfig.TierSkipCost} {CROWN}`, tier < maxTier and state.crowns >= StoreConfig.TierSkipCost, colors.selected)

	if not jumped and ui.pages["Royal Pass"].Visible then
		jumped = true
		task.defer(function()
			local track = w.track
			local focus = math.max(1, math.min(maxTier, tier))
			-- Show the first unclaimed tier, else the current one.
			for index = 1, tier do
				local key = tostring(index)
				if not pass.claimedFree[key] or (pass.noble and not pass.claimedNoble[key]) then
					focus = index
					break
				end
			end
			local maxX = math.max(0, track.AbsoluteCanvasSize.X - track.AbsoluteWindowSize.X)
			local goal = math.clamp(PAD + (focus - 2) * COL, 0, maxX)
			TweenService:Create(track, TweenInfo.new(0.6, Enum.EasingStyle.Quint), { CanvasPosition = Vector2.new(goal, 0) }):Play()
		end)
	end

	-- Weekly challenges.
	w.weekLeft.Text = `NEW CHALLENGES IN {string.upper(days(state.weekSecondsLeft or 0))}`
	local weekly = state.weekly
	local weeklyReady = 0
	for _, challenge in StoreConfig.WeeklyChallenges do
		local part = w.challenges[challenge.key]
		local value = math.min(challenge.goal, weekly[challenge.stat] or 0)
		part.fill.Size = UDim2.fromScale(value / challenge.goal, 1)
		part.value.Text = if challenge.stat == "play"
			then `{math.floor(value / 60)} / {math.floor(challenge.goal / 60)} MIN`
			else `{Format.short(value)} / {Format.short(challenge.goal)}`
		local done = weekly.claimed[challenge.key] == true
		local ready = not done and value >= challenge.goal
		if ready then
			weeklyReady += 1
		end
		part.stroke.Color = if ready then GREEN elseif done then colors.dim else colors.dim
		part.stroke.Thickness = if ready then 3 else 1
		part.stroke.Transparency = if ready then 0 else 0.5
		ui.setButton(part.button, if done then `{CHECK} DONE` elseif ready then "CLAIM" else "IN PROGRESS", ready, colors.claim)
	end
	ui.setBadge("Royal Pass", claimable + weeklyReady)
end

return RoyalPassPage
