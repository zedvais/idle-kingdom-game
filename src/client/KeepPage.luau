-- Keep page: a big animated picture of your Keep with its name, level and
-- next upgrade, then panels with your numbers, and the Skill points window
-- where points are added with + and - and saved with Apply.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local EstateConfig = require(Shared:WaitForChild("EstateConfig"))
local Format = require(Shared:WaitForChild("Format"))
local Scenes = require(script.Parent:WaitForChild("Scenes"))

local KeepPage = {}

local SKILL_ICONS = {
	energy = "\u{26A1}",
	stamina = "\u{1F5E1}\u{FE0F}",
	health = "\u{2764}\u{FE0F}",
	attack = "\u{2694}\u{FE0F}",
	defense = "\u{1F6E1}\u{FE0F}",
	lots = "\u{1F33E}",
}

local show = {} -- widgets of the Keep picture block
local panels = {} -- value labels in the panels, by key
local skillRows = {} -- the Skill points window, by skill id
local pending = {} -- [skill id] = points added in the window, not yet applied
local skillWindow = {}
local latest = nil
local drawnKeep = 0

---------------------------------------------------------------------------
-- Small builders
---------------------------------------------------------------------------

local function label(ui, parent, size, position, color, textSize, font)
	local l = ui.makeText(parent, size, position, color, textSize)
	l.Font = font or Enum.Font.GothamBold
	l.TextWrapped = false
	l.RichText = true
	return l
end

-- A panel with a title strip, an optional link button and label/value rows.
local function makePanel(ui, grid, title: string, rows, linkText: string?)
	local art = ui.art
	local frame = ui.makeFrame(grid, UDim2.fromOffset(100, 100), UDim2.fromOffset(0, 0), ui.colors.row)
	ui.addCorner(frame, 8)
	ui.addStroke(frame)
	art.card(frame)
	local strip = ui.makeFrame(frame, UDim2.new(1, 0, 0, 34), UDim2.fromOffset(0, 0), Color3.fromRGB(30, 23, 17))
	ui.addCorner(strip, 8)
	label(ui, strip, UDim2.new(1, -150, 1, 0), UDim2.fromOffset(12, 0), ui.colors.text, 14).Text = string.upper(title)
	local link = nil
	if linkText then
		link = ui.makeButton(strip, UDim2.fromOffset(128, 26), UDim2.new(1, -6, 0.5, 0), ui.colors.gold)
		link.AnchorPoint = Vector2.new(1, 0.5)
		link.TextSize = 12
		ui.setButton(link, linkText, true, ui.colors.gold)
	end
	local values, names = {}, {}
	for index, row in rows do
		local y = 40 + (index - 1) * 26
		local name = label(ui, frame, UDim2.new(0.6, -12, 0, 24), UDim2.fromOffset(12, y), ui.colors.dim, 13, Enum.Font.GothamMedium)
		name.Text = string.upper(row[2])
		local value = label(ui, frame, UDim2.new(0.4, -12, 0, 24), UDim2.new(0.6, 0, 0, y), ui.colors.text, 15)
		value.TextXAlignment = Enum.TextXAlignment.Right
		values[row[1]] = value
		names[row[1]] = name
	end
	return values, link, names
end

---------------------------------------------------------------------------
-- Skill points window
---------------------------------------------------------------------------

-- Points the window's additions would cost in total.
local function pendingCost(state): number
	local total = 0
	for _, skill in GameConfig.Skills do
		local bought = state.skills[skill.id] or 0
		for step = 0, (pending[skill.id] or 0) - 1 do
			total += GameConfig.getSkillCost(skill, bought + step)
		end
	end
	return total
end

local function skillValue(state, skill): number
	local stats = state.stats
	if skill.id == "energy" then
		return stats.maxEnergy
	elseif skill.id == "stamina" then
		return stats.maxStamina
	elseif skill.id == "health" then
		return stats.maxHealth
	elseif skill.id == "attack" then
		return GameConfig.BaseAttack + (state.skills.attack or 0) * skill.amount
	elseif skill.id == "defense" then
		return GameConfig.BaseDefense + (state.skills.defense or 0) * skill.amount
	elseif skill.id == "lots" then
		return stats.lots
	end
	return 0
end

local function drawSkillWindow(ui)
	local state = latest
	if not state then
		return
	end
	local colors = ui.colors
	local cost = pendingCost(state)
	local left = state.skillPoints - cost
	skillWindow.available.Text = `{left} AVAILABLE`
	local anyPending = false
	for _, skill in GameConfig.Skills do
		local row = skillRows[skill.id]
		local add = pending[skill.id] or 0
		anyPending = anyPending or add > 0
		local bought = state.skills[skill.id] or 0
		local nextCost = GameConfig.getSkillCost(skill, bought + add)
		local value = skillValue(state, skill) + add * skill.amount
		row.value.Text = Format.short(value)
		row.value.TextColor3 = if add > 0 then colors.gold else colors.text
		row.added.Text = if add > 0 then `+{add}` else ""
		row.cost.Text = `{nextCost} {if nextCost == 1 then "POINT" else "POINTS"}`
		ui.setButton(row.minus, "-", add > 0, colors.selected)
		ui.setButton(row.plus, "+", left >= nextCost, colors.gold)
	end
	ui.setButton(skillWindow.undo, "UNDO", anyPending, colors.selected)
	ui.setButton(skillWindow.apply, if anyPending then `APPLY ({cost})` else "APPLY", anyPending, colors.claim)
end

-- Makes a button repeat while held down.
local function holdRepeat(button: GuiButton, action: () -> ())
	local holding = 0
	button.MouseButton1Down:Connect(function()
		holding += 1
		local mine = holding
		action()
		task.wait(0.35)
		while holding == mine do
			action()
			task.wait(0.08)
		end
	end)
	local function stop()
		holding += 1
	end
	button.MouseButton1Up:Connect(stop)
	button.MouseLeave:Connect(stop)
end

local function buildSkillWindow(ui)
	local page = ui.pages.Skills
	local colors = ui.colors
	local art = ui.art

	local top = ui.makeFrame(page, UDim2.new(1, -10, 0, 34), UDim2.fromOffset(0, 0), colors.panel)
	top.BackgroundTransparency = 1
	top.LayoutOrder = 0
	local available = label(ui, top, UDim2.fromOffset(170, 30), UDim2.fromOffset(0, 2), colors.text, 15)
	available.BackgroundTransparency = 0
	available.BackgroundColor3 = Color3.fromRGB(30, 23, 17)
	available.TextXAlignment = Enum.TextXAlignment.Center
	ui.addCorner(available, 6)
	skillWindow.available = available
	local hint = label(ui, top, UDim2.new(1, -180, 1, 0), UDim2.fromOffset(180, 0), colors.dim, 12, Enum.Font.GothamMedium)
	hint.TextXAlignment = Enum.TextXAlignment.Right
	hint.Text = "Hold + or - to repeat"

	for index, skill in GameConfig.Skills do
		local row = ui.makeFrame(page, UDim2.new(1, -10, 0, 58), UDim2.fromOffset(0, 0), colors.row)
		row.LayoutOrder = index
		ui.addCorner(row, 6)
		ui.addStroke(row)
		art.card(row)
		local iconBox = ui.makeFrame(row, UDim2.fromOffset(44, 44), UDim2.fromOffset(7, 7), Color3.fromRGB(30, 23, 17))
		ui.addCorner(iconBox, 6)
		art.stroke(iconBox, colors.gold, 1, 0.5)
		local icon = art.icon(iconBox, SKILL_ICONS[skill.id] or "", 30, UDim2.fromScale(0.5, 0.5))
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		local name = label(ui, row, UDim2.new(1, -330, 0, 22), UDim2.fromOffset(60, 8), colors.text, 16)
		name.Text = string.upper(skill.name)
		local note = label(ui, row, UDim2.new(1, -330, 0, 16), UDim2.fromOffset(60, 31), colors.dim, 12, Enum.Font.GothamMedium)
		note.Text = if skill.growth then `{skill.note} (cost grows each time)` else `{skill.note} per upgrade`
		local value = label(ui, row, UDim2.fromOffset(80, 30), UDim2.new(1, -262, 0.5, -15), colors.text, 20)
		value.TextXAlignment = Enum.TextXAlignment.Right
		local added = label(ui, row, UDim2.fromOffset(40, 14), UDim2.new(1, -222, 0.5, 13), colors.gold, 11)
		added.TextXAlignment = Enum.TextXAlignment.Right
		local cost = label(ui, row, UDim2.fromOffset(80, 20), UDim2.new(1, -176, 0.5, -10), colors.gold, 11)
		cost.TextXAlignment = Enum.TextXAlignment.Center
		local minus = ui.makeButton(row, UDim2.fromOffset(42, 42), UDim2.new(1, -96, 0.5, -21), colors.selected)
		minus.TextSize = 22
		local plus = ui.makeButton(row, UDim2.fromOffset(42, 42), UDim2.new(1, -50, 0.5, -21), colors.gold)
		plus.TextSize = 22
		skillRows[skill.id] = { value = value, added = added, cost = cost, minus = minus, plus = plus }

		holdRepeat(plus, function()
			local state = latest
			if not state then
				return
			end
			local add = pending[skill.id] or 0
			local nextCost = GameConfig.getSkillCost(skill, (state.skills[skill.id] or 0) + add)
			if state.skillPoints - pendingCost(state) >= nextCost then
				pending[skill.id] = add + 1
				drawSkillWindow(ui)
			end
		end)
		holdRepeat(minus, function()
			local add = pending[skill.id] or 0
			if add > 0 then
				pending[skill.id] = add - 1
				drawSkillWindow(ui)
			end
		end)
	end

	local bottom = ui.makeFrame(page, UDim2.new(1, -10, 0, 48), UDim2.fromOffset(0, 0), colors.panel)
	bottom.BackgroundTransparency = 1
	bottom.LayoutOrder = #GameConfig.Skills + 1
	local undo = ui.makeButton(bottom, UDim2.new(0.4, -4, 1, -6), UDim2.fromOffset(0, 4), colors.selected)
	undo.TextSize = 16
	local apply = ui.makeButton(bottom, UDim2.new(0.6, -4, 1, -6), UDim2.new(0.4, 4, 0, 4), colors.claim)
	apply.TextSize = 16
	skillWindow.undo = undo
	skillWindow.apply = apply
	undo.Activated:Connect(function()
		table.clear(pending)
		drawSkillWindow(ui)
	end)
	apply.Activated:Connect(function()
		local parts = {}
		for _, skill in GameConfig.Skills do
			local add = pending[skill.id] or 0
			if add > 0 then
				table.insert(parts, `{skill.id}:{add}`)
			end
		end
		if #parts > 0 then
			ui.send("SkillMany", table.concat(parts, ","))
			table.clear(pending)
		end
	end)

	local foot = label(ui, page, UDim2.new(1, -10, 0, 20), UDim2.fromOffset(0, 0), colors.dim, 12, Enum.Font.GothamMedium)
	foot.LayoutOrder = #GameConfig.Skills + 2
	foot.TextXAlignment = Enum.TextXAlignment.Center
	foot.Text = `Earn more: each level up gives {GameConfig.SkillPointsPerLevel} points.`
end

---------------------------------------------------------------------------
-- Building the page
---------------------------------------------------------------------------

function KeepPage.build(ui)
	local page = ui.pages.Keep
	local colors = ui.colors
	local art = ui.art

	-- The picture block sits above everything else on the page.
	local block = ui.makeFrame(page, UDim2.new(1, -10, 0, 330), UDim2.fromOffset(0, 0), Color3.fromRGB(20, 15, 11))
	block.LayoutOrder = -10
	ui.addCorner(block, 8)
	art.stroke(block, colors.gold, 1.5, 0.3)
	local picture = ui.makeFrame(block, UDim2.new(1, -16, 0, 200), UDim2.fromOffset(8, 8), Color3.fromRGB(12, 9, 7))
	picture.ClipsDescendants = true
	ui.addCorner(picture, 6)
	show.picture = picture
	show.gate = function()
		return page.Visible
	end
	local rule = ui.makeFrame(block, UDim2.new(1, -16, 0, 2), UDim2.fromOffset(8, 212), colors.gold)
	rule.BackgroundTransparency = 0.3

	local name = label(ui, block, UDim2.new(0.6, -16, 0, 44), UDim2.fromOffset(16, 216), colors.gold, 40, art.Fonts.title)
	name.TextStrokeTransparency = 0.5
	show.name = name

	local function statBox(x: number, width: number, title: string)
		local box = ui.makeFrame(block, UDim2.new(width, -8, 0, 52), UDim2.new(x, 16, 0, 266), Color3.fromRGB(34, 27, 20))
		ui.addCorner(box, 6)
		local small = label(ui, box, UDim2.new(1, -16, 0, 14), UDim2.fromOffset(10, 6), colors.dim, 10)
		small.Text = title
		local big = label(ui, box, UDim2.new(1, -16, 0, 26), UDim2.fromOffset(10, 21), colors.text, 22, art.Fonts.heading)
		return big
	end
	show.level = statBox(0, 0.2, "KEEP LEVEL")
	show.bonus = statBox(0.2, 0.28, "INCOME, ATTACK AND DEFENSE")

	local nextText = label(ui, block, UDim2.new(0.5, -24, 0, 18), UDim2.new(0.5, 8, 0, 222), colors.dim, 13)
	nextText.TextXAlignment = Enum.TextXAlignment.Right
	show.nextText = nextText
	local costText = label(ui, block, UDim2.new(0.5, -24, 0, 16), UDim2.new(0.5, 8, 0, 242), colors.dim, 11, Enum.Font.GothamMedium)
	costText.TextXAlignment = Enum.TextXAlignment.Right
	costText.TextTruncate = Enum.TextTruncate.AtEnd
	show.costText = costText
	local upgrade = ui.makeButton(block, UDim2.new(0.34, 0, 0, 52), UDim2.new(1, -16, 0, 266), colors.buy)
	upgrade.AnchorPoint = Vector2.new(1, 0)
	upgrade.TextSize = 18
	upgrade.Activated:Connect(function()
		ui.send("Keep")
	end)
	show.upgrade = upgrade

	-- Panels with your numbers, two per row.
	local grid = ui.makeGrid(page, ui.nextOrder(), 214, 2)
	panels.stats = makePanel(ui, grid, "Your stats", {
		{ "renown", "Renown" },
		{ "attack", "Attack power" },
		{ "defense", "Defense power" },
		{ "income", "Holding income" },
		{ "lots", "Holding lots" },
		{ "relics", "Relic bonus" },
	})
	local upgradeLink
	panels.upgrades, upgradeLink = makePanel(ui, grid, "Your upgrades", {
		{ "points", "Skill points" },
		{ "energy", "Max energy" },
		{ "stamina", "Max stamina" },
		{ "health", "Max health" },
		{ "attack", "Base attack" },
		{ "defense", "Base defense" },
	}, "SPEND POINTS")
	upgradeLink.Activated:Connect(function()
		table.clear(pending)
		ui.openModal("Skills")
	end)
	local warbandLink
	panels.warband, warbandLink = makePanel(ui, grid, "Your warband", {
		{ "soldiers", "Soldiers" },
		{ "gear", "Gear" },
		{ "warAttack", "Warband attack" },
		{ "warDefense", "Warband defense" },
	}, "OPEN \u{203A}")
	warbandLink.Activated:Connect(function()
		ui.showPage("Warband")
	end)
	local sourceValues, _noLink, sourceNames = makePanel(ui, grid, "Where your power comes from", {
		{ "1", "" },
		{ "2", "" },
		{ "3", "" },
		{ "4", "" },
		{ "5", "" },
		{ "6", "" },
	})

	panels.sources = sourceValues
	panels.sourceNames = sourceNames

	buildSkillWindow(ui)
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

function KeepPage.draw(state, ui)
	latest = state
	local colors = ui.colors
	local stats = state.stats

	-- Picture: drawn again only when the Keep level changes.
	if drawnKeep ~= state.keep then
		drawnKeep = state.keep
		local old = show.picture:FindFirstChild("Picture")
		if old then
			old:Destroy()
		end
		Scenes.keep(show.picture, state.keep, show.gate, 360)
	end

	local keep = GameConfig.KeepLevels[state.keep]
	local nextKeep = GameConfig.KeepLevels[state.keep + 1]
	show.name.Text = string.upper(keep.name)
	show.level.Text = `{state.keep} of {#GameConfig.KeepLevels}`
	show.bonus.Text = `+{math.floor(keep.bonus * 100)}%`
	if nextKeep then
		local keepCost = table.clone(nextKeep.resources or {})
		keepCost.gold = nextKeep.cost
		show.nextText.Text = `NEXT: <font color="#F2EAD8">{string.upper(nextKeep.name)}</font>, +{math.floor(nextKeep.bonus * 100)}%`
		show.costText.Text = EstateConfig.describeCost(keepCost, Format.short)
		if state.level < nextKeep.level then
			ui.setButton(show.upgrade, `REQUIRES LEVEL {nextKeep.level}`, false, colors.buy)
		else
			ui.setButton(show.upgrade, `UPGRADE  {Format.short(nextKeep.cost)}`, EstateConfig.canPay(keepCost, state.gold, state.estate.stock), colors.buy)
		end
	else
		show.nextText.Text = "THE GREATEST KEEP IN THE REALM"
		show.costText.Text = ""
		ui.setButton(show.upgrade, "MAX LEVEL", false, colors.buy)
	end

	-- Panels
	local breakdown = {}
	for _, part in stats.breakdown do
		breakdown[part[1]] = part
	end
	local p = panels.stats
	p.renown.Text = Format.short(state.renown)
	p.attack.Text = Format.short(stats.attack)
	p.defense.Text = Format.short(stats.defense)
	p.income.Text = `{Format.short(stats.incomePerHour)} / hr`
	p.lots.Text = `{stats.lotsUsed} of {stats.lots}`
	local relic = breakdown["Relic Hall"]
	p.relics.Text = if relic then `+{Format.short(relic[2])} / +{Format.short(relic[3])}` else "none"

	local u = panels.upgrades
	u.points.Text = `<font color="#F0C450">{state.skillPoints}</font>`
	u.energy.Text = Format.short(stats.maxEnergy)
	u.stamina.Text = Format.short(stats.maxStamina)
	u.health.Text = Format.short(stats.maxHealth)
	u.attack.Text = Format.short(GameConfig.BaseAttack + (state.skills.attack or 0))
	u.defense.Text = Format.short(GameConfig.BaseDefense + (state.skills.defense or 0))

	local w = panels.warband
	local filled, slots = 0, 0
	for _, soldier in state.crew do
		if soldier then
			slots += #GameConfig.GearSlots
			for _ in soldier.gear or {} do
				filled += 1
			end
		end
	end
	w.soldiers.Text = `{stats.crewSize} of {#state.crew}`
	w.gear.Text = `{filled} of {slots} slots`
	local war = breakdown.Warband
	w.warAttack.Text = if war then Format.short(war[2]) else "0"
	w.warDefense.Text = if war then Format.short(war[3]) else "0"

	-- Each source of power on its own line: name on the left, numbers right.
	local s = panels.sources
	for index = 1, 6 do
		local part = stats.breakdown[index]
		local value = s[tostring(index)]
		panels.sourceNames[tostring(index)].Text = if part then string.upper(part[1]) else ""
		value.Text = if part then `{Format.short(part[2])} atk  {Format.short(part[3])} def` else ""
	end

	if ui.isOpen("Skills") then
		drawSkillWindow(ui)
	end
end

return KeepPage
