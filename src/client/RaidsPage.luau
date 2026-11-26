-- Raids page (Arena):
--   * banner with your attack and defense and your raid record,
--   * your health: under 20 you can not raid or be raided,
--   * target cards (players near your level and NPC keeps): portrait,
--     level, guild tag, their defense against your attack with a win
--     chance, gold on hand, ATTACK,
--   * recent attackers with a REVENGE button.
-- A raid plays out in a popup: two rolls race up, then VICTORY or DEFEAT.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local SocialConfig = require(Shared:WaitForChild("SocialConfig"))
local Format = require(Shared:WaitForChild("Format"))
local Kit = require(script.Parent:WaitForChild("Kit"))
local Fx = require(script.Parent:WaitForChild("Fx"))

local RaidsPage = {}

local MAX_TARGETS = 8
local w = {}
local cards = {}
local attackerRows = {}
local headshots = {} -- [userId] = image
local lastState = nil

-- Chance that attack x roll beats defense x roll (both rolls uniform).
local function winChance(attack: number, defense: number): number
	if defense <= 0 then
		return 1
	end
	local steps, wins = 24, 0
	for i = 0, steps - 1 do
		local a = attack * (SocialConfig.RollMin + (SocialConfig.RollMax - SocialConfig.RollMin) * (i + 0.5) / steps)
		for j = 0, steps - 1 do
			local d = defense * (SocialConfig.RollMin + (SocialConfig.RollMax - SocialConfig.RollMin) * (j + 0.5) / steps)
			if a > d then
				wins += 1
			end
		end
	end
	return wins / (steps * steps)
end

-- Fills an ImageLabel with a player's headshot (fetched once).
local function setHeadshot(image: ImageLabel, userId: number?)
	if not userId then
		image.Image = ""
		return
	end
	if headshots[userId] then
		image.Image = headshots[userId]
		return
	end
	image.Image = ""
	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		end)
		if ok then
			headshots[userId] = content
			if image:GetAttribute("User") == userId then
				image.Image = content
			end
		end
	end)
end

local function ago(seconds: number): string
	if seconds < 60 then
		return "just now"
	elseif seconds < 3600 then
		return `{seconds // 60}m ago`
	elseif seconds < 86400 then
		return `{seconds // 3600}h ago`
	end
	return `{seconds // 86400}d ago`
end

local function buildCard(ui, grid: Instance, index: number)
	local card, stroke = Kit.card(ui, grid, index, Kit.RED)
	card.Visible = false
	local top = ui.makeFrame(card, UDim2.new(1, 0, 0, 78), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1))
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.fromRGB(120, 44, 36), Kit.CARD)
	gradient.Parent = top
	local frame = ui.makeFrame(card, UDim2.fromOffset(62, 62), UDim2.fromOffset(12, 10), Color3.fromRGB(40, 30, 24))
	ui.addCorner(frame, 31)
	ui.art.stroke(frame, ui.colors.gold, 2, 0)
	local portrait = Instance.new("ImageLabel")
	portrait.Size = UDim2.fromScale(1, 1)
	portrait.BackgroundTransparency = 1
	portrait.ZIndex = frame.ZIndex + 1
	portrait.Parent = frame
	ui.addCorner(portrait, 31)
	local glyph = ui.makeText(frame, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1), 34)
	glyph.TextXAlignment = Enum.TextXAlignment.Center
	glyph.Text = "\u{1F3F0}"
	glyph.ZIndex = frame.ZIndex + 2
	local name = ui.makeText(card, UDim2.new(1, -92, 0, 22), UDim2.fromOffset(84, 12), ui.colors.text, 16)
	name.Font = Enum.Font.GothamBlack
	name.RichText = true
	name.TextTruncate = Enum.TextTruncate.AtEnd
	local sub = ui.makeText(card, UDim2.new(1, -92, 0, 18), UDim2.fromOffset(84, 36), ui.colors.dim, 12)
	sub.Font = Enum.Font.GothamBold
	sub.RichText = true
	local ribbon = ui.makeText(card, UDim2.fromOffset(80, 18), UDim2.new(1, -88, 0, 8), Color3.new(1, 1, 1), 10)
	ribbon.BackgroundTransparency = 0
	ribbon.BackgroundColor3 = Kit.RED
	ribbon.Font = Enum.Font.GothamBlack
	ribbon.TextXAlignment = Enum.TextXAlignment.Center
	ribbon.Text = "\u{2694}\u{FE0F} REVENGE"
	ribbon.ZIndex = 420
	ui.addCorner(ribbon, 4)
	local versus = ui.makeText(card, UDim2.new(1, -24, 0, 18), UDim2.fromOffset(12, 84), ui.colors.dim, 12)
	versus.Font = Enum.Font.GothamBlack
	versus.RichText = true
	local bar = Kit.bar(ui, card, UDim2.new(1, -24, 0, 18), UDim2.fromOffset(12, 104), Kit.GREEN)
	local loot = ui.makeText(card, UDim2.new(1, -24, 0, 18), UDim2.fromOffset(12, 128), Kit.GOLD, 13)
	loot.Font = Enum.Font.GothamBlack
	loot.RichText = true
	local button = ui.makeButton(card, UDim2.new(1, -24, 0, 40), UDim2.new(0, 12, 1, -50), Kit.RED)
	button.TextSize = 15
	button.Font = Enum.Font.GothamBlack
	local part = {
		card = card,
		stroke = stroke,
		portrait = portrait,
		glyph = glyph,
		name = name,
		sub = sub,
		ribbon = ribbon,
		versus = versus,
		bar = bar,
		loot = loot,
		button = button,
		id = nil,
	}
	button.Activated:Connect(function()
		if part.id then
			Kit.pop(card, 1.08)
			ui.send("Raid", part.id)
		end
	end)
	cards[index] = part
end

local function buildResult(ui)
	local layer = Instance.new("ScreenGui")
	layer.Name = "RaidResult"
	layer.DisplayOrder = 60
	layer.IgnoreGuiInset = true
	layer.ResetOnSpawn = false
	layer.Enabled = false
	layer.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local shade = Instance.new("TextButton")
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.45
	shade.Text = ""
	shade.AutoButtonColor = false
	shade.Parent = layer
	local box = ui.makeFrame(layer, UDim2.fromOffset(520, 330), UDim2.new(0.5, -260, 0.5, -165), Color3.fromRGB(30, 24, 18))
	box.ZIndex = 5
	ui.addCorner(box, 12)
	ui.art.stroke(box, ui.colors.gold, 3, 0)
	ui.art.grain(box)
	local scale = Instance.new("UIScale")
	scale.Parent = box
	local title = ui.makeText(box, UDim2.new(1, -20, 0, 44), UDim2.fromOffset(10, 12), ui.colors.gold, 34)
	title.Font = ui.art.Fonts.title
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.ZIndex = 10
	local against = ui.makeText(box, UDim2.new(1, -20, 0, 20), UDim2.fromOffset(10, 58), ui.colors.dim, 14)
	against.Font = Enum.Font.GothamBold
	against.TextXAlignment = Enum.TextXAlignment.Center
	against.ZIndex = 10
	local function rollRow(y: number, label: string, color: Color3)
		local text = ui.makeText(box, UDim2.fromOffset(120, 22), UDim2.fromOffset(24, y), color, 14)
		text.Font = Enum.Font.GothamBlack
		text.Text = label
		text.ZIndex = 10
		local bar = Kit.bar(ui, box, UDim2.new(1, -170, 0, 26), UDim2.fromOffset(146, y - 2), color)
		bar.back.ZIndex = 10
		bar.fill.ZIndex = 11
		bar.text.ZIndex = 12
		return bar
	end
	local attackBar = rollRow(104, "\u{2694}\u{FE0F} YOUR ATTACK", Kit.GREEN)
	local defenseBar = rollRow(146, "\u{1F6E1}\u{FE0F} THEIR DEFENSE", Color3.fromRGB(110, 150, 230))
	local verdict = ui.makeText(box, UDim2.new(1, -20, 0, 50), UDim2.fromOffset(10, 186), Kit.GOLD, 40)
	verdict.Font = ui.art.Fonts.title
	verdict.TextXAlignment = Enum.TextXAlignment.Center
	verdict.TextStrokeTransparency = 0.3
	verdict.ZIndex = 10
	local loot = ui.makeText(box, UDim2.new(1, -20, 0, 22), UDim2.fromOffset(10, 236), ui.colors.text, 15)
	loot.Font = Enum.Font.GothamBold
	loot.TextXAlignment = Enum.TextXAlignment.Center
	loot.ZIndex = 10
	local close = ui.makeButton(box, UDim2.fromOffset(160, 40), UDim2.new(0.5, -80, 1, -56), ui.colors.action)
	close.Text = "CONTINUE"
	close.Font = Enum.Font.GothamBlack
	close.ZIndex = 10
	local function hide()
		layer.Enabled = false
	end
	close.Activated:Connect(hide)
	shade.Activated:Connect(hide)
	w.result = {
		layer = layer,
		box = box,
		scale = scale,
		title = title,
		against = against,
		attackBar = attackBar,
		defenseBar = defenseBar,
		verdict = verdict,
		loot = loot,
	}
end

local function showResult(info)
	local r = w.result
	if not r then
		return
	end
	r.layer.Enabled = true
	r.scale.Scale = 0.6
	TweenService:Create(r.scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	r.title.Text = "RAID!"
	r.against.Text = `against {info.name or "a keep"}`
	r.verdict.Text = ""
	r.loot.Text = ""
	local top = math.max(1, info.attack or 0, info.defense or 0)
	r.attackBar.fill.Size = UDim2.fromScale(0, 1)
	r.defenseBar.fill.Size = UDim2.fromScale(0, 1)
	r.attackBar.fill.Visible = true
	r.defenseBar.fill.Visible = true
	r.attackBar.text.Text = ""
	r.defenseBar.text.Text = ""
	task.spawn(function()
		local steps = 20
		for step = 1, steps do
			local share = step / steps
			r.attackBar.fill.Size = UDim2.fromScale((info.attack or 0) / top * share, 1)
			r.defenseBar.fill.Size = UDim2.fromScale((info.defense or 0) / top * share, 1)
			r.attackBar.text.Text = Format.short(math.floor((info.attack or 0) * share))
			r.defenseBar.text.Text = Format.short(math.floor((info.defense or 0) * share))
			task.wait(0.05)
		end
		r.verdict.Text = if info.win then "VICTORY!" else "DEFEAT"
		r.verdict.TextColor3 = if info.win then Kit.GOLD else Kit.RED
		r.verdict.TextTransparency = 1
		TweenService:Create(r.verdict, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
		if info.win then
			r.loot.Text = `\u{1F4B0} +{Format.short(info.gold or 0)} gold{if info.loot and info.loot ~= "" then "   +" .. info.loot else ""}`
		else
			r.loot.Text = "Their defense held. You lost some health."
		end
	end)
end

function RaidsPage.build(ui)
	local page = ui.pages.Raids
	local banner = Kit.banner(ui, page, 1, 120, Color3.fromRGB(150, 50, 36), Color3.fromRGB(46, 14, 10), "Raids", "\u{1F525}")
	w.power = Kit.line(ui, banner, 120, 64, UDim.new(0.5, -120), 17, Color3.new(1, 1, 1))
	w.power.Font = Enum.Font.GothamBlack
	w.record = Kit.line(ui, banner, 0, 0, UDim.new(0.4, 0), 13, Color3.fromRGB(255, 220, 200))
	w.record.Position = UDim2.new(0.58, 0, 0, 30)
	w.record.Size = UDim2.new(0.4, -10, 0, 70)
	w.record.TextWrapped = true

	-- your health / bank note
	local strip = ui.makeFrame(page, UDim2.new(1, -10, 0, 52), UDim2.fromOffset(0, 0), Color3.fromRGB(30, 40, 60))
	strip.LayoutOrder = 2
	ui.addCorner(strip, 8)
	w.shieldStroke = ui.art.stroke(strip, Color3.fromRGB(110, 150, 230), 1.5, 0.2)
	w.shield = ui.makeText(strip, UDim2.new(1, -24, 1, 0), UDim2.fromOffset(14, 0), ui.colors.text, 14)
	w.shield.Font = Enum.Font.GothamBold
	w.shield.RichText = true
	w.strip = strip

	local _, _, right = Kit.heading(ui, page, 3, "\u{1F3AF}  Targets", Kit.RED)
	w.targetsNote = right
	local bar = ui.makeFrame(page, UDim2.new(1, -10, 0, 44), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	bar.BackgroundTransparency = 1
	bar.LayoutOrder = 4
	local scout = ui.makeButton(bar, UDim2.fromOffset(220, 40), UDim2.fromOffset(0, 2), ui.colors.action)
	scout.Font = Enum.Font.GothamBlack
	scout.TextSize = 15
	scout.Activated:Connect(function()
		ui.send("RaidLook")
	end)
	w.scout = scout
	w.offline = ui.makeText(bar, UDim2.new(1, -240, 1, 0), UDim2.fromOffset(234, 0), ui.colors.dim, 12)
	w.offline.Font = Enum.Font.GothamBold
	w.offline.TextWrapped = true
	local grid = Kit.grid(ui, page, 5, 214, 3)
	for index = 1, MAX_TARGETS do
		buildCard(ui, grid, index)
	end
	w.empty = ui.makeText(page, UDim2.new(1, -10, 0, 40), UDim2.fromOffset(0, 0), ui.colors.dim, 14)
	w.empty.LayoutOrder = 6
	w.empty.TextXAlignment = Enum.TextXAlignment.Center

	local _, _, attackersRight = Kit.heading(ui, page, 7, "\u{1F6E1}\u{FE0F}  Raids on you", Color3.fromRGB(110, 150, 230))
	attackersRight.Text = "BANK GOLD IS ALWAYS SAFE"
	local list = ui.makeFrame(page, UDim2.new(1, -10, 0, 0), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	list.BackgroundTransparency = 1
	list.AutomaticSize = Enum.AutomaticSize.Y
	list.LayoutOrder = 8
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	w.noAttackers = ui.makeText(list, UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 0), ui.colors.dim, 13)
	w.noAttackers.TextXAlignment = Enum.TextXAlignment.Center
	w.noAttackers.Text = "No one has raided you yet."
	for index = 1, SocialConfig.AttackersKept do
		local row = ui.makeFrame(list, UDim2.new(1, 0, 0, 44), UDim2.fromOffset(0, 0), Kit.CARD)
		row.LayoutOrder = index
		ui.addCorner(row, 8)
		local stroke = ui.art.stroke(row, ui.colors.dim, 1, 0.5)
		local text = ui.makeText(row, UDim2.new(1, -170, 1, 0), UDim2.fromOffset(14, 0), ui.colors.text, 14)
		text.Font = Enum.Font.GothamBold
		text.RichText = true
		local button = ui.makeButton(row, UDim2.fromOffset(140, 32), UDim2.new(1, -150, 0.5, -16), Kit.RED)
		button.Font = Enum.Font.GothamBlack
		button.TextSize = 13
		local part = { row = row, stroke = stroke, text = text, button = button, userId = nil }
		button.Activated:Connect(function()
			if part.userId then
				ui.send("RaidRevenge", tostring(part.userId))
			end
		end)
		attackerRows[index] = part
	end
	buildResult(ui)
	Fx.handlers.raid = showResult
	page:GetPropertyChangedSignal("Visible"):Connect(function()
		if page.Visible then
			Kit.popAll(page)
			if lastState and lastState.raid and #lastState.raid.targets == 0 and lastState.level >= SocialConfig.RaidMinLevel then
				ui.send("RaidLook")
			end
		end
	end)
end

function RaidsPage.draw(state, ui)
	if not state or not state.raid then
		return
	end
	lastState = state
	local raid = state.raid
	local stats = state.stats
	w.power.Text = `\u{2694}\u{FE0F} <font color="#F0C450">{Format.short(stats.attack)}</font>   \u{1F6E1}\u{FE0F} <font color="#AFC8FF">{Format.short(stats.defense)}</font>`
	w.record.Text = `RAIDS WON {raid.wins} / LOST {raid.losses}\nHELD OFF {raid.held} / FELL {raid.fell}\nGOLD TAKEN {Format.short(raid.stolen)} / LOST {Format.short(raid.lost)}`

	local locked = state.level < SocialConfig.RaidMinLevel
	if locked then
		w.shield.Text = `\u{1F512} Raids open at level {SocialConfig.RaidMinLevel}. Until then no one can raid you either.`
	elseif state.health < 20 then
		w.shield.Text = `\u{1F480} <b><font color="#E66A5A">INCAPACITATED</font></b>  {state.health} / {stats.maxHealth} health. Under 20 you can not raid, and no one can raid you, until you recover.`
	else
		w.shield.Text = `\u{2764}\u{FE0F} {state.health} / {stats.maxHealth} health   \u{2022}   \u{1F4B0} <font color="#F0C450">{Format.short(state.gold)}</font> gold on hand can be raided. Bank it to keep it safe.`
	end
	Kit.setPulse(w.shieldStroke, state.health < 20, Kit.RED)

	ui.setButton(w.scout, if raid.lookIn > 0 and #raid.targets > 0 then `\u{1F50E} SCOUT IN {raid.lookIn}s` else "\u{1F50E} SCOUT FOR TARGETS", not locked and (raid.lookIn <= 0 or #raid.targets == 0), ui.colors.action)
	w.offline.Text = if raid.online
		then `Players within {SocialConfig.RaidLevelRange} levels of you, and NPC keeps when few are around. {SocialConfig.RaidStamina} stamina per raid.`
		else "Studio test: only NPC keeps show here. Real players appear once the game is published."
	w.targetsNote.Text = `YOU: LV {state.level}  \u{2022}  \u{1F4EF} {state.stamina} STAMINA`

	local shown = 0
	for index, part in cards do
		local target = raid.targets[index]
		part.card.Visible = target ~= nil
		if not target then
			part.id = nil
			continue
		end
		shown += 1
		part.id = target.id
		part.portrait:SetAttribute("User", target.userId)
		if target.npc then
			part.portrait.Image = ""
			part.glyph.Visible = true
		else
			part.glyph.Visible = false
			setHeadshot(part.portrait, target.userId)
		end
		local tag = if target.tag ~= "" then `<font color="#F0C450">[{target.tag}]</font> ` else ""
		part.name.Text = `{tag}{target.name}`
		part.sub.Text = `LEVEL {target.level}  \u{2022}  {if target.npc then "NPC KEEP" else "PLAYER"}  \u{2022}  \u{2764}\u{FE0F} {target.health or "?"} / {target.maxHealth or "?"}`
		part.ribbon.Visible = target.revenge
		local chance = winChance(stats.attack, target.defense)
		local color = if chance >= 0.65 then Kit.GREEN elseif chance >= 0.35 then Kit.GOLD else Kit.RED
		part.versus.Text = `\u{2694}\u{FE0F} {Format.short(stats.attack)}  VS  \u{1F6E1}\u{FE0F} {Format.short(target.defense)}`
		part.bar.fill.BackgroundColor3 = color
		Kit.setBar(part.bar, chance, 1, `{math.floor(chance * 100 + 0.5)}% TO WIN`)
		local take = math.floor(target.gold * SocialConfig.StealGold)
		part.loot.Text = `\u{1F4B0} ON HAND {Format.short(target.gold)}  >  <font color="#FFFFFF">+{Format.short(take)}</font>`
		local down = not target.npc and (target.health or 100) < 20
		if down then
			ui.setButton(part.button, "\u{1F480} INCAPACITATED", false, Kit.RED)
		elseif state.health < 20 then
			ui.setButton(part.button, "TOO WOUNDED", false, Kit.RED)
		elseif locked then
			ui.setButton(part.button, `LEVEL {SocialConfig.RaidMinLevel}`, false, Kit.RED)
		else
			ui.setButton(part.button, "\u{2694}\u{FE0F} ATTACK", state.stamina >= SocialConfig.RaidStamina and state.health >= 20, Kit.RED)
		end
		Kit.setPulse(part.stroke, target.revenge, Kit.RED)
	end
	w.empty.Visible = shown == 0
	w.empty.Text = if locked then "" else "Press SCOUT FOR TARGETS to find keeps to raid."

	local now = os.time()
	w.noAttackers.Visible = #raid.attackers == 0
	for index, part in attackerRows do
		local attacker = raid.attackers[index]
		part.row.Visible = attacker ~= nil
		if attacker then
			part.userId = attacker.userId
			local result = if attacker.win then `<font color="#E66A5A">raided you</font>` else `<font color="#6ED26E">was driven off</font>`
			part.text.Text = `<b>{attacker.name}</b> {result}   <font color="#B2A690">{ago(now - (attacker.time or now))}</font>`
			part.stroke.Color = if attacker.win then Kit.RED else Kit.GREEN
			ui.setButton(part.button, "\u{2694}\u{FE0F} REVENGE", not locked and attacker.userId ~= nil, Kit.RED)
		end
	end
	ui.setBadge("Raids", 0)
end

return RaidsPage
