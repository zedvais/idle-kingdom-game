-- Settings popups for the auto features. Each page has one button that
-- opens its popup; changes are only sent when you press Save, and Cancel
-- (or X) throws them away.
--   ui.openAutoQuest()  auto quests: rule (mode) and activity (this run)
--   ui.openAutoBuy()    Market auto-buy: on or off and what to buy
-- Auto roll for the warband uses the Recruit window, which works the same
-- way (Save and start, or Cancel).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local StoreConfig = require(Shared:WaitForChild("StoreConfig"))
local Format = require(Shared:WaitForChild("Format"))

local AutoPopups = {}

local latest = nil
local quest = { on = false, mode = "last" } -- the draft being edited
local buy = { on = false, slots = {}, rarity = "Rare", minPrice = 0, maxPrice = 0, broke = "wait" }
local widgets = {}
local MARKET_RARITIES = {} -- filled when the popup is built

-- An On / Off pair. Returns the two buttons.
local function onOffRow(ui, page, label: string)
	local buttons = ui.makeButtonRow(page, ui.nextOrder(), label, { "On", "Off" }, 150)
	return buttons
end

-- Save and Cancel at the bottom of a popup.
local function saveRow(ui, page, onSave)
	local colors = ui.colors
	local row = ui.makeFrame(page, UDim2.new(1, -10, 0, 46), UDim2.fromOffset(0, 0), colors.panel)
	row.LayoutOrder = ui.nextOrder()
	row.BackgroundTransparency = 1
	local cancel = ui.makeButton(row, UDim2.new(0.5, -4, 1, 0), UDim2.fromOffset(0, 0), colors.selected)
	ui.setButton(cancel, "Cancel", true, colors.selected)
	cancel.Activated:Connect(function()
		ui.closeModal()
	end)
	local save = ui.makeButton(row, UDim2.new(0.5, -4, 1, 0), UDim2.new(0.5, 4, 0, 0), colors.buy)
	ui.setButton(save, "Save", true, colors.buy)
	save.Activated:Connect(function()
		onSave()
		ui.closeModal()
	end)
	return save
end

local function pick(ui, button: TextButton, chosen: boolean)
	local colors = ui.colors
	button.BackgroundColor3 = if chosen then colors.selected else colors.row
	button.TextColor3 = if chosen then colors.gold else colors.text
end

-- Auto quests popup, two tabs:
--   RULE: which quest to work on (four modes) and what it picks now.
--   ACTIVITY: the quest being done, energy, and this run's totals.
-- At the bottom: Save changes (mode) and Start / Stop.
local questTab = "rule"

local function sectionLabel(ui, parent: Instance, y: number, title: string, note: string?)
	local colors = ui.colors
	local label = ui.makeText(parent, UDim2.fromOffset(180, 24), UDim2.fromOffset(0, y), colors.text, 18)
	label.Font = Enum.Font.GothamBlack
	label.Text = title
	if note then
		local small = ui.makeText(parent, UDim2.fromOffset(180, 40), UDim2.fromOffset(0, y + 24), colors.dim, 13)
		small.TextYAlignment = Enum.TextYAlignment.Top
		small.Text = note
		return label, small
	end
	return label, nil
end

local function statBox(ui, parent: Instance, x: number, y: number, title: string, color: Color3): TextLabel
	local colors = ui.colors
	local box = ui.makeFrame(parent, UDim2.new(0.5, -6, 0, 70), UDim2.new(x, if x > 0 then 6 else 0, 0, y), Color3.fromRGB(30, 26, 22))
	ui.addCorner(box, 6)
	local label = ui.makeText(box, UDim2.new(1, -20, 0, 20), UDim2.fromOffset(12, 8), colors.dim, 14)
	label.Font = Enum.Font.GothamBold
	label.Text = title
	local value = ui.makeText(box, UDim2.new(1, -20, 0, 34), UDim2.fromOffset(12, 30), color, 26)
	value.Font = ui.art.Fonts.heading
	return value
end

local function buildAutoQuest(ui)
	local page = ui.pages.AutoQuest
	local colors = ui.colors

	-- Status pill and tabs.
	local top = ui.makeFrame(page, UDim2.new(1, -10, 0, 50), UDim2.fromOffset(0, 0), colors.panel)
	top.BackgroundTransparency = 1
	top.LayoutOrder = 1
	widgets.questTabs = {}
	for index, info in { { "rule", "RULE" }, { "activity", "ACTIVITY" } } do
		local button = ui.makeButton(top, UDim2.fromOffset(130, 42), UDim2.fromOffset((index - 1) * 140, 4), Color3.new(0, 0, 0))
		button.BackgroundTransparency = 1
		button.TextSize = 18
		button.Text = info[2]
		button:SetAttribute("NoGlow", true)
		local line = ui.makeFrame(button, UDim2.new(1, -20, 0, 3), UDim2.new(0, 10, 1, -3), colors.gold)
		widgets.questTabs[info[1]] = { button = button, line = line }
		button.Activated:Connect(function()
			questTab = info[1]
			AutoPopups.draw(latest, ui)
		end)
	end
	widgets.questStatus = ui.makeText(top, UDim2.fromOffset(150, 32), UDim2.new(1, -156, 0, 9), Color3.fromRGB(110, 210, 110), 15)
	widgets.questStatus.Font = Enum.Font.GothamBlack
	widgets.questStatus.TextXAlignment = Enum.TextXAlignment.Center
	widgets.questStatus.BackgroundTransparency = 0
	widgets.questStatus.BackgroundColor3 = Color3.fromRGB(30, 26, 22)
	ui.addCorner(widgets.questStatus, 4)

	-- RULE tab.
	local rule = ui.makeFrame(page, UDim2.new(1, -10, 0, 250), UDim2.fromOffset(0, 0), colors.panel)
	rule.BackgroundTransparency = 1
	rule.LayoutOrder = 2
	widgets.questRule = rule
	local _, modeNote = sectionLabel(ui, rule, 10, "WORK ON", "")
	widgets.questModeNote = modeNote
	widgets.questModes = {}
	local count = #GameConfig.AutoQuestModes
	for index, mode in GameConfig.AutoQuestModes do
		local button = ui.makeButton(rule, UDim2.new(1 / count, -8, 0, 56), UDim2.new((index - 1) / count, 0, 0, 0), colors.row)
		-- The buttons sit right of the labels: shift the whole row.
		button.Size = UDim2.new((1 / count) * 1, -(190 / count) - 8, 0, 56)
		button.Position = UDim2.new((index - 1) / count, 190 - (190 * (index - 1) / count), 0, 6)
		button.TextSize = 15
		button.Font = Enum.Font.GothamBlack
		button.Text = string.upper(mode.name)
		local stroke = ui.art.stroke(button, colors.dim, 1.5, 0.5)
		widgets.questModes[index] = { button = button, stroke = stroke }
		button.Activated:Connect(function()
			quest.mode = mode.id
			AutoPopups.draw(latest, ui)
		end)
	end
	sectionLabel(ui, rule, 96, "PICKS NOW")
	widgets.questPick = ui.makeText(rule, UDim2.new(1, -190, 0, 50), UDim2.fromOffset(190, 84), colors.text, 18)
	widgets.questPick.Font = Enum.Font.GothamBold
	widgets.questPick.BackgroundTransparency = 0
	widgets.questPick.BackgroundColor3 = Color3.fromRGB(30, 26, 22)
	widgets.questPick.RichText = true
	ui.addCorner(widgets.questPick, 6)
	local pickPad = Instance.new("UIPadding")
	pickPad.PaddingLeft = UDim.new(0, 16)
	pickPad.Parent = widgets.questPick
	sectionLabel(ui, rule, 160, "ENERGY", "Quests run while you have energy")
	widgets.questEnergyNote = ui.makeText(rule, UDim2.new(1, -190, 0, 60), UDim2.fromOffset(190, 150), colors.dim, 14)
	widgets.questEnergyNote.RichText = true
	widgets.questEnergyNote.TextYAlignment = Enum.TextYAlignment.Center

	-- ACTIVITY tab.
	local activity = ui.makeFrame(page, UDim2.new(1, -10, 0, 330), UDim2.fromOffset(0, 0), colors.panel)
	activity.BackgroundTransparency = 1
	activity.LayoutOrder = 3
	widgets.questActivity = activity
	sectionLabel(ui, activity, 4, "NOW DOING")
	local now = ui.makeFrame(activity, UDim2.new(1, 0, 0, 80), UDim2.fromOffset(0, 32), Color3.fromRGB(30, 26, 22))
	ui.addCorner(now, 6)
	widgets.questNowName = ui.makeText(now, UDim2.new(1, -24, 0, 30), UDim2.fromOffset(14, 6), colors.text, 20)
	widgets.questNowName.Font = Enum.Font.GothamBold
	widgets.questNowInfo = ui.makeText(now, UDim2.new(1, -24, 0, 28), UDim2.fromOffset(14, 42), Color3.fromRGB(240, 160, 64), 15)
	widgets.questNowInfo.Font = Enum.Font.GothamBlack
	widgets.questNowInfo.RichText = true
	local energyLabel = ui.makeText(activity, UDim2.fromOffset(90, 20), UDim2.fromOffset(0, 124), colors.dim, 15)
	energyLabel.Font = Enum.Font.GothamBold
	energyLabel.Text = "ENERGY"
	local energyBack = ui.makeFrame(activity, UDim2.new(1, -220, 0, 10), UDim2.fromOffset(94, 129), Color3.fromRGB(30, 26, 22))
	ui.addCorner(energyBack, 4)
	widgets.questEnergyFill = ui.makeFrame(energyBack, UDim2.fromScale(0, 1), UDim2.fromOffset(0, 0), Color3.fromRGB(230, 140, 50))
	ui.addCorner(widgets.questEnergyFill, 4)
	widgets.questEnergyText = ui.makeText(activity, UDim2.fromOffset(110, 20), UDim2.new(1, -110, 0, 124), Color3.fromRGB(240, 160, 64), 15)
	widgets.questEnergyText.Font = Enum.Font.GothamBlack
	widgets.questEnergyText.TextXAlignment = Enum.TextXAlignment.Right
	sectionLabel(ui, activity, 158, "THIS RUN")
	widgets.questRunQuests = statBox(ui, activity, 0, 186, "QUESTS", colors.text)
	widgets.questRunGold = statBox(ui, activity, 0.5, 186, "GOLD", Color3.fromRGB(110, 210, 110))
	widgets.questRunXp = statBox(ui, activity, 0, 262, "EXP", Color3.fromRGB(180, 140, 240))
	widgets.questRunItems = statBox(ui, activity, 0.5, 262, "GEAR FOUND", colors.text)

	-- Footer: note, Save changes, Start / Stop.
	local footer = ui.makeFrame(page, UDim2.new(1, -10, 0, 64), UDim2.fromOffset(0, 0), colors.panel)
	footer.BackgroundTransparency = 1
	footer.LayoutOrder = 4
	local note = ui.makeText(footer, UDim2.new(0.34, 0, 1, 0), UDim2.fromOffset(0, 0), colors.dim, 13)
	note.Text = "Runs only while you are in the game, on any page."
	widgets.questSave = ui.makeButton(footer, UDim2.new(0.33, -6, 0, 54), UDim2.new(0.34, 0, 0, 5), colors.row)
	widgets.questSave.TextSize = 17
	widgets.questSave.Font = Enum.Font.GothamBlack
	widgets.questStart = ui.makeButton(footer, UDim2.new(0.33, -6, 0, 54), UDim2.new(0.67, 6, 0, 5), colors.row)
	widgets.questStart.TextSize = 17
	widgets.questStart.Font = Enum.Font.GothamBlack
	widgets.questStartStroke = ui.art.stroke(widgets.questStart, colors.gold, 2, 0)
	widgets.questSave.Activated:Connect(function()
		local state = latest
		if not state or quest.mode == (state.autoQuestMode or "last") then
			return
		end
		-- Keeps running (or stopped) as it is, with the new mode.
		ui.send("AutoQuest", `save:{if state.autoQuestOn then "on" else "off"}:{quest.mode}`)
	end)
	widgets.questStart.Activated:Connect(function()
		local state = latest
		if not state then
			return
		end
		if not state.passes.autoquest then
			if ui.offerPass then
				ui.closeModal()
				ui.offerPass("autoquest")
			end
		elseif state.autoQuestOn then
			ui.send("AutoQuest", "off")
		else
			ui.send("AutoQuest", `save:on:{quest.mode}`)
			questTab = "activity"
		end
	end)

	function ui.openAutoQuest()
		if not latest then
			return
		end
		quest.mode = latest.autoQuestMode or "last"
		questTab = if latest.autoQuestOn then "activity" else "rule"
		AutoPopups.draw(latest, ui)
		ui.openModal("AutoQuest")
	end
end

local function buildAutoBuy(ui)
	local page = ui.pages.AutoBuy
	widgets.buyStatus = ui.makeRow(page, ui.nextOrder(), 50, false)
	widgets.buyStatus.RichText = true
	widgets.buyOnOff = onOffRow(ui, page, "Auto-buy")
	widgets.buyOnOff[1].Activated:Connect(function()
		buy.on = true
		AutoPopups.draw(latest, ui)
	end)
	widgets.buyOnOff[2].Activated:Connect(function()
		buy.on = false
		AutoPopups.draw(latest, ui)
	end)

	widgets.buySlots = ui.makeButtonRow(page, ui.nextOrder(), "Slots", GameConfig.GearSlots, 150)
	for index, slot in GameConfig.GearSlots do
		widgets.buySlots[index].Activated:Connect(function()
			buy.slots[slot] = not buy.slots[slot]
			AutoPopups.draw(latest, ui)
		end)
	end

	ui.makeHeading(page, ui.nextOrder(), "Lowest rarity to buy")
	-- Only rarities the Market can have (Divine never shows up there).
	local rarityNames = {}
	for _, rarity in GameConfig.Rarities do
		if rarity.chance > 0 then
			table.insert(MARKET_RARITIES, rarity)
			table.insert(rarityNames, rarity.id)
		end
	end
	widgets.buyRarity = ui.makeButtonRow(page, ui.nextOrder(), "", rarityNames)
	for index, rarity in MARKET_RARITIES do
		widgets.buyRarity[index].TextSize = 11
		widgets.buyRarity[index].Activated:Connect(function()
			buy.rarity = rarity.id
			AutoPopups.draw(latest, ui)
		end)
	end

	local priceRow = ui.makeFrame(page, UDim2.new(1, -10, 0, 48), UDim2.fromOffset(0, 0), ui.colors.row)
	priceRow.LayoutOrder = ui.nextOrder()
	ui.addCorner(priceRow, 6)
	local label = ui.makeText(priceRow, UDim2.fromOffset(140, 48), UDim2.fromOffset(10, 0), ui.colors.text, 13)
	label.Text = "Price (gold)"
	widgets.minBox = ui.makeAmountBox(priceRow, UDim2.new(0.5, -84, 1, -12), UDim2.fromOffset(150, 6), "Min: none")
	widgets.maxBox = ui.makeAmountBox(priceRow, UDim2.new(0.5, -84, 1, -12), UDim2.new(0.5, 76, 0, 6), "Max: none")
	local function readPrice(box: TextBox): number
		local text = string.gsub(box.Text, "%s", "")
		if text == "" or text == "0" then
			return 0
		end
		return math.floor(Format.parse(text) or 0)
	end
	widgets.minBox.FocusLost:Connect(function()
		buy.minPrice = readPrice(widgets.minBox)
		AutoPopups.draw(latest, ui)
	end)
	widgets.maxBox.FocusLost:Connect(function()
		buy.maxPrice = readPrice(widgets.maxBox)
		AutoPopups.draw(latest, ui)
	end)

	widgets.buyBroke = ui.makeButtonRow(page, ui.nextOrder(), "Out of gold", { "Wait for gold", "Stop" }, 150)
	widgets.buyBroke[1].Activated:Connect(function()
		buy.broke = "wait"
		AutoPopups.draw(latest, ui)
	end)
	widgets.buyBroke[2].Activated:Connect(function()
		buy.broke = "stop"
		AutoPopups.draw(latest, ui)
	end)

	widgets.buySave = saveRow(ui, page, function()
		-- Read the boxes too, in case one still has focus.
		buy.minPrice = readPrice(widgets.minBox)
		buy.maxPrice = readPrice(widgets.maxBox)
		local letters = ""
		for _, slot in GameConfig.GearSlots do
			if buy.slots[slot] then
				letters ..= string.sub(slot, 1, 1)
			end
		end
		if buy.on and latest and not latest.passes.autobuy then
			ui.send("Robux", "pass:autobuy")
		end
		ui.send("AutoBuy", `save:{if buy.on then "on" else "off"}:{letters}:{buy.rarity}:{string.format("%d", buy.minPrice)}:{string.format("%d", buy.maxPrice)}:{buy.broke}`)
	end)

	function ui.openAutoBuy()
		if not latest then
			return
		end
		local rule = latest.autoBuy
		buy.on = rule.on ~= true -- starts on the opposite of now (see above)
		buy.slots = table.clone(rule.slots)
		buy.rarity = rule.minRarity
		buy.minPrice = rule.minPrice
		buy.maxPrice = rule.maxPrice
		buy.broke = rule.whenBroke
		widgets.minBox.Text = if rule.minPrice > 0 then Format.short(rule.minPrice) else ""
		widgets.maxBox.Text = if rule.maxPrice > 0 then Format.short(rule.maxPrice) else ""
		ui.openModal("AutoBuy")
	end
end

function AutoPopups.build(ui)
	buildAutoQuest(ui)
	buildAutoBuy(ui)
end

function AutoPopups.draw(state, ui)
	if not state then
		return
	end
	latest = state
	local colors = ui.colors

	if ui.isOpen("AutoQuest") or not widgets.questDrawn then
		widgets.questDrawn = true
		local owns = state.passes.autoquest == true
		local running = owns and state.autoQuestOn == true
		widgets.questStatus.Text = if running then "\u{25A0} RUNNING" elseif owns then "\u{25A0} STOPPED" else "\u{1F512} NEEDS PASS"
		widgets.questStatus.TextColor3 = if running then Color3.fromRGB(110, 210, 110) else colors.dim
		for key, tab in widgets.questTabs do
			local on = key == questTab
			tab.line.Visible = on
			tab.button.TextColor3 = if on then colors.text else colors.dim
		end
		widgets.questRule.Visible = questTab == "rule"
		widgets.questActivity.Visible = questTab == "activity"

		for index, mode in GameConfig.AutoQuestModes do
			local chosen = quest.mode == mode.id
			local piece = widgets.questModes[index]
			piece.button.BackgroundColor3 = if chosen then Color3.fromRGB(52, 42, 22) else colors.row
			piece.button.TextColor3 = if chosen then colors.gold else colors.dim
			piece.stroke.Color = if chosen then colors.gold else colors.dim
			piece.stroke.Transparency = if chosen then 0 else 0.6
			if chosen then
				widgets.questModeNote.Text = mode.note or ""
			end
		end
		local nextQuest = GameConfig.pickAutoQuest(quest.mode, state.level, state.quests, state.autoQuest)
		widgets.questPick.Text = if nextQuest then nextQuest.name else "<font color=\"#B2A690\">Do a quest once first</font>"
		widgets.questEnergyNote.Text = `It waits while energy refills ({state.energy} / {state.stats.maxEnergy} now). Refills from the Foes token shop or the Shop top it up.`

		local current = GameConfig.pickAutoQuest(state.autoQuestMode or "last", state.level, state.quests, state.autoQuest)
		widgets.questNowName.Text = if running and current then current.name elseif running then "Nothing to do" else "Not running"
		widgets.questNowInfo.Text = if current and running then `{current.energy} ENERGY   <font color="#B2A690">TIER {current.tier or 1}   {string.upper(current.region)}</font>` else ""
		local maxEnergy = math.max(1, state.stats.maxEnergy)
		widgets.questEnergyFill.Size = UDim2.fromScale(math.min(1, state.energy / maxEnergy), 1)
		widgets.questEnergyText.Text = `{state.energy} / {maxEnergy}`
		local run = state.autoRun or {}
		widgets.questRunQuests.Text = Format.short(run.quests or 0)
		widgets.questRunGold.Text = Format.short(run.gold or 0)
		widgets.questRunXp.Text = Format.short(run.xp or 0)
		widgets.questRunItems.Text = Format.short(run.items or 0)

		local changed = quest.mode ~= (state.autoQuestMode or "last")
		ui.setButton(widgets.questSave, "SAVE CHANGES", changed, colors.selected)
		if not owns then
			ui.setButton(widgets.questStart, `GET PASS {ui.robuxText(StoreConfig.getPass("autoquest").price)}`, true, colors.gold)
			widgets.questStartStroke.Color = colors.gold
		elseif running then
			ui.setButton(widgets.questStart, "STOP", true, Color3.fromRGB(40, 22, 20))
			widgets.questStart.TextColor3 = Color3.fromRGB(230, 90, 70)
			widgets.questStartStroke.Color = Color3.fromRGB(230, 90, 70)
		else
			ui.setButton(widgets.questStart, "START", true, Color3.fromRGB(22, 40, 22))
			widgets.questStart.TextColor3 = Color3.fromRGB(110, 210, 110)
			widgets.questStartStroke.Color = Color3.fromRGB(110, 210, 110)
		end
	end

	if ui.isOpen("AutoBuy") then
		local owns = state.passes.autobuy == true
		widgets.buyStatus.Text = if owns
			then `<b>Market Steward</b>: buys gear that matches these rules every restock, while you are in the game.`
			else `<b>Needs the Market Steward game pass</b> ({ui.robuxText(StoreConfig.getPass("autobuy").price)}, in the Shop). You can still set the rules.`
		pick(ui, widgets.buyOnOff[1], buy.on)
		pick(ui, widgets.buyOnOff[2], not buy.on)
		for index, slot in GameConfig.GearSlots do
			pick(ui, widgets.buySlots[index], buy.slots[slot] == true)
		end
		local chosenRank = GameConfig.getRarityRank(buy.rarity)
		for index, rarity in MARKET_RARITIES do
			local button = widgets.buyRarity[index]
			local chosen = GameConfig.getRarityRank(rarity.id) == chosenRank
			pick(ui, button, chosen)
			if not chosen then
				button.TextColor3 = rarity.color
			end
		end
		widgets.minBox.PlaceholderText = "Min: none"
		widgets.maxBox.PlaceholderText = "Max: none"
		pick(ui, widgets.buyBroke[1], buy.broke == "wait")
		pick(ui, widgets.buyBroke[2], buy.broke == "stop")
	end
	-- Colors only: keeps the Save buttons gold.
	ui.setButton(widgets.questSave, "Save", true, colors.buy)
	ui.setButton(widgets.buySave, "Save", true, colors.buy)
end

return AutoPopups
