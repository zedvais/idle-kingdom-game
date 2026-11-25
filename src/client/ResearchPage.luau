-- Scholars' Hall page:
--   * a banner with a turning globe and what the scholars are doing,
--   * the active research panel with a sliding bar and Finish now,
--   * each branch as a row of tech cards: level pips, now / next effect,
--     time, lock note, and a Research button. Cards pulse when they can
--     be started and the active one glows.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ResearchConfig = require(Shared:WaitForChild("ResearchConfig"))
local Format = require(Shared:WaitForChild("Format"))
local Kit = require(script.Parent:WaitForChild("Kit"))

local ResearchPage = {}

local BLUE = Color3.fromRGB(110, 160, 240)
local BRANCH_STYLE = {
	Husbandry = { glyph = "\u{1F33E}", color = Color3.fromRGB(120, 190, 90) },
	Warcraft = { glyph = "\u{2694}\u{FE0F}", color = Color3.fromRGB(220, 100, 80) },
	Provisions = { glyph = "\u{1F35E}", color = Color3.fromRGB(230, 170, 80) },
	Lore = { glyph = "\u{1F4DA}", color = BLUE },
}
local BONUS_GLYPHS = {
	income = "\u{1F4B0}",
	questGold = "\u{1F5FA}\u{FE0F}",
	lots = "\u{1F3D7}\u{FE0F}",
	attack = "\u{2694}\u{FE0F}",
	defense = "\u{1F6E1}\u{FE0F}",
	energy = "\u{26A1}",
	health = "\u{2764}\u{FE0F}",
	xp = "\u{2B50}",
}

local w = {}
local cards = {}
local lastActive = nil

local function buildActive(ui, page: Instance)
	local panel = ui.makeFrame(page, UDim2.new(1, -10, 0, 110), UDim2.fromOffset(0, 0), Kit.CARD)
	panel.LayoutOrder = 2
	ui.addCorner(panel, 10)
	w.activeStroke = ui.art.stroke(panel, BLUE, 2, 0.2)
	local disc, glyph = Kit.badge(ui, panel, "\u{1F4D6}", 76, UDim2.fromOffset(16, 17), Color3.fromRGB(50, 70, 110))
	w.activeDisc = disc
	w.activeGlyph = glyph
	local title = ui.makeText(panel, UDim2.new(1, -330, 0, 28), UDim2.fromOffset(108, 12), ui.colors.text, 20)
	title.Font = ui.art.Fonts.heading
	w.activeTitle = title
	local note = ui.makeText(panel, UDim2.new(1, -330, 0, 20), UDim2.fromOffset(108, 40), ui.colors.dim, 13)
	note.Font = Enum.Font.GothamBold
	w.activeNote = note
	w.activeBar = Kit.bar(ui, panel, UDim2.new(1, -330, 0, 24), UDim2.fromOffset(108, 70), BLUE)
	local finish = ui.makeButton(panel, UDim2.fromOffset(190, 56), UDim2.new(1, -206, 0.5, -28), ui.colors.selected)
	finish.TextSize = 15
	finish.Font = Enum.Font.GothamBlack
	finish.Activated:Connect(function()
		Kit.pop(panel, 1.04)
		ui.send("ResearchFinish")
	end)
	w.finish = finish
	w.panel = panel
end

local function buildBranch(ui, page: Instance, order: number, branch)
	local style = BRANCH_STYLE[branch.name] or { glyph = "\u{1F4DC}", color = ui.colors.gold }
	local _, label, right = Kit.heading(ui, page, order, `{style.glyph}  {branch.name}`, style.color)
	local _ = label
	right.Text = `{#branch.techs} STUDIES`
	local grid = Kit.grid(ui, page, order + 1, 206, 3)
	for index, tech in branch.techs do
		local card, stroke = Kit.card(ui, grid, index, style.color)
		Kit.badge(ui, card, BONUS_GLYPHS[tech.bonus] or style.glyph, 54, UDim2.fromOffset(12, 12), style.color:Lerp(Color3.new(0, 0, 0), 0.45))
		local name = ui.makeText(card, UDim2.new(1, -84, 0, 24), UDim2.fromOffset(74, 12), ui.colors.text, 16)
		name.Font = Enum.Font.GothamBlack
		name.Text = tech.name
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local level = ui.makeText(card, UDim2.new(1, -84, 0, 18), UDim2.fromOffset(74, 36), style.color, 12)
		level.Font = Enum.Font.GothamBlack
		-- level pips
		local pipRow = ui.makeFrame(card, UDim2.new(1, -24, 0, 8), UDim2.fromOffset(12, 74), Color3.new(0, 0, 0))
		pipRow.BackgroundTransparency = 1
		local pips = {}
		for pip = 1, tech.maxLevel do
			local width = 1 / tech.maxLevel
			local dot = ui.makeFrame(pipRow, UDim2.new(width, -3, 1, 0), UDim2.new(width * (pip - 1), 0, 0, 0), Color3.fromRGB(60, 54, 46))
			ui.addCorner(dot, 3)
			pips[pip] = dot
		end
		local now = ui.makeText(card, UDim2.new(1, -24, 0, 18), UDim2.fromOffset(12, 90), ui.colors.dim, 12)
		now.RichText = true
		now.Font = Enum.Font.GothamBold
		local nextLine = ui.makeText(card, UDim2.new(1, -24, 0, 34), UDim2.fromOffset(12, 108), ui.colors.text, 12)
		nextLine.RichText = true
		nextLine.TextWrapped = true
		nextLine.Font = Enum.Font.GothamBold
		local button = ui.makeButton(card, UDim2.new(1, -24, 0, 40), UDim2.new(0, 12, 1, -50), ui.colors.buy)
		button.TextSize = 14
		button.Font = Enum.Font.GothamBlack
		local lock = ui.makeText(card, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.fromRGB(230, 200, 170), 13)
		lock.BackgroundTransparency = 0.35
		lock.BackgroundColor3 = Color3.new(0, 0, 0)
		lock.Font = Enum.Font.GothamBlack
		lock.TextXAlignment = Enum.TextXAlignment.Center
		lock.TextWrapped = true
		lock.ZIndex = 450
		button.Activated:Connect(function()
			Kit.pop(card, 1.08)
			ui.send("Research", tech.key)
		end)
		cards[tech.key] = {
			card = card,
			stroke = stroke,
			color = style.color,
			level = level,
			pips = pips,
			now = now,
			nextLine = nextLine,
			button = button,
			lock = lock,
			tech = tech,
		}
	end
end

function ResearchPage.build(ui)
	local page = ui.pages.Research
	local banner = Kit.banner(ui, page, 1, 120, Color3.fromRGB(60, 80, 140), Color3.fromRGB(24, 26, 56), "Scholars' Hall", "\u{1F52D}")
	w.status = Kit.line(ui, banner, 120, 66, UDim.new(0.5, -120), 18, Color3.new(1, 1, 1))
	w.status.Font = Enum.Font.GothamBlack
	local note = Kit.line(ui, banner, 0, 0, UDim.new(0.4, 0), 13, Color3.fromRGB(210, 220, 255))
	note.Position = UDim2.new(0.58, 0, 0, 40)
	note.Size = UDim2.new(0.4, -10, 0, 44)
	note.TextWrapped = true
	note.Text = "Research gives permanent bonuses. One study runs at a time and keeps going while you are away."
	buildActive(ui, page)
	local order = 3
	for _, branch in ResearchConfig.Branches do
		buildBranch(ui, page, order, branch)
		order += 2
	end
	page:GetPropertyChangedSignal("Visible"):Connect(function()
		if page.Visible then
			Kit.popAll(page)
		end
	end)
	-- the open book on the active panel gently turns while busy
	task.spawn(function()
		while true do
			task.wait(1.2)
			if page.Visible and lastActive and lastActive ~= "" then
				TweenService:Create(w.activeGlyph, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, true), {
					Rotation = 12,
				}):Play()
			end
		end
	end)
end

function ResearchPage.draw(state, ui)
	if not state or not state.research then
		return
	end
	local colors = ui.colors
	local research = state.research
	local busy = research.active ~= ""
	local left = state.researchLeft or 0
	local started = 0
	if lastActive ~= research.active then
		if lastActive and lastActive ~= "" and not busy then
			Kit.pop(w.panel, 1.06)
			Kit.float(ui, w.panel, "RESEARCH COMPLETE!", Kit.GOLD)
		end
		lastActive = research.active
	end

	if busy then
		local tech = ResearchConfig.Techs[research.active]
		local level = (research.levels[research.active] or 0) + 1
		local total = if tech then ResearchConfig.getSeconds(tech, level - 1) else 0
		w.activeGlyph.Text = if tech then BONUS_GLYPHS[tech.bonus] or "\u{1F4D6}" else "\u{1F4D6}"
		w.activeTitle.Text = `Studying {tech and tech.name or research.active} \u{2022} Lv {level}`
		w.activeNote.Text = if tech then `When done: {ResearchConfig.describe(tech, level)}` else ""
		Kit.setBar(w.activeBar, total - left, total, `{ui.formatLong(left)} LEFT`)
		local cost = ResearchConfig.getFinishCost(left)
		ui.setButton(w.finish, `FINISH NOW\n\u{1F451} {cost} CROWNS`, state.crowns >= cost, colors.selected)
		w.status.Text = `\u{1F4D6} <font color="#AFC8FF">BUSY</font>  {ui.formatLong(left)} left`
		Kit.setPulse(w.activeStroke, false, BLUE)
	else
		w.activeGlyph.Text = "\u{1F4A4}"
		w.activeTitle.Text = "The scholars are idle"
		w.activeNote.Text = "Pick a study below to start it."
		Kit.setBar(w.activeBar, 0, 1, "IDLE")
		ui.setButton(w.finish, "IDLE", false, colors.selected)
		w.status.Text = `\u{1F4A4} <font color="#F0C450">IDLE</font>  pick a study`
	end

	for key, part in cards do
		local tech = part.tech
		local level = research.levels[key] or 0
		part.level.Text = `LEVEL {level} / {tech.maxLevel}`
		for pip, dot in part.pips do
			dot.BackgroundColor3 = if pip <= level then part.color else Color3.fromRGB(60, 54, 46)
		end
		part.now.Text = if level > 0 then `Now: <font color="#FFFFFF">{ResearchConfig.describe(tech, level)}</font>` else "Now: nothing yet"
		local locked = false
		if tech.needs and (research.levels[tech.needs[1]] or 0) < tech.needs[2] then
			local need = ResearchConfig.Techs[tech.needs[1]]
			part.lock.Text = `\u{1F512}\nNEEDS {string.upper(need and need.name or tech.needs[1])}\nLEVEL {tech.needs[2]}`
			locked = true
		end
		part.lock.Visible = locked
		local maxed = level >= tech.maxLevel
		if maxed then
			part.nextLine.Text = `<font color="#6ED26E">\u{2714} Fully researched</font>`
		else
			part.nextLine.Text = `Next: <font color="#AFC8FF">{ResearchConfig.describe(tech, level + 1)}</font>\n\u{23F3} {ui.formatLong(ResearchConfig.getSeconds(tech, level))}`
		end
		local canStart = false
		if maxed then
			ui.setButton(part.button, "\u{2714} MAXED", false, colors.buy)
		elseif research.active == key then
			ui.setButton(part.button, `STUDYING... {ui.formatLong(left)}`, false, colors.buy)
		elseif locked then
			ui.setButton(part.button, "LOCKED", false, colors.buy)
		else
			local cost = ResearchConfig.getCost(tech, level)
			canStart = not busy and state.gold >= cost
			ui.setButton(part.button, `RESEARCH  \u{1F4B0} {Format.short(cost)}`, canStart, colors.buy)
		end
		if canStart then
			started += 1
		end
		Kit.setPulse(part.stroke, canStart, part.color)
		part.card.BackgroundColor3 = if research.active == key then Color3.fromRGB(34, 40, 62) else Kit.CARD
	end
	ui.setBadge("Research", if busy then 0 else math.min(started, 1))
end

return ResearchPage
