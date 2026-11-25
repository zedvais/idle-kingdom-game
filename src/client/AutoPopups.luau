-- Settings popups for the auto features. Each page has one button that
-- opens its popup; changes are only sent when you press Save, and Cancel
-- (or X) throws them away.
--   ui.openAutoQuest()  auto quests: on or off, and which quest to do
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

local function buildAutoQuest(ui)
	local page = ui.pages.AutoQuest
	widgets.questStatus = ui.makeRow(page, ui.nextOrder(), 50, false)
	widgets.questStatus.RichText = true
	widgets.questOnOff = onOffRow(ui, page, "Auto quests")
	widgets.questOnOff[1].Activated:Connect(function()
		quest.on = true
		AutoPopups.draw(latest, ui)
	end)
	widgets.questOnOff[2].Activated:Connect(function()
		quest.on = false
		AutoPopups.draw(latest, ui)
	end)
	local names = {}
	for index, mode in GameConfig.AutoQuestModes do
		names[index] = mode.name
	end
	ui.makeHeading(page, ui.nextOrder(), "Which quest")
	widgets.questModes = ui.makeButtonRow(page, ui.nextOrder(), "", names)
	for index, mode in GameConfig.AutoQuestModes do
		widgets.questModes[index].TextSize = 12
		widgets.questModes[index].Activated:Connect(function()
			quest.mode = mode.id
			AutoPopups.draw(latest, ui)
		end)
	end
	widgets.questPreview = ui.makeRow(page, ui.nextOrder(), 50, false)
	widgets.questPreview.RichText = true
	widgets.questSave = saveRow(ui, page, function()
		ui.send("AutoQuest", `save:{if quest.on then "on" else "off"}:{quest.mode}`)
		if quest.on and latest and not latest.passes.autoquest then
			ui.send("Robux", "pass:autoquest")
		end
	end)

	function ui.openAutoQuest()
		if not latest then
			return
		end
		quest.on = latest.autoQuestOn == true
		quest.mode = latest.autoQuestMode or "last"
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
		buy.on = rule.on == true
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

	if ui.isOpen("AutoQuest") then
		local owns = state.passes.autoquest == true
		widgets.questStatus.Text = if owns
			then `<b>Quest Herald</b>: does quests for you whenever you have the energy, while you are in the game.`
			else `<b>Needs the Quest Herald game pass</b> ({ui.robuxText(StoreConfig.getPass("autoquest").price)}, in the Shop). You can still pick a mode.`
		pick(ui, widgets.questOnOff[1], quest.on)
		pick(ui, widgets.questOnOff[2], not quest.on)
		for index, mode in GameConfig.AutoQuestModes do
			pick(ui, widgets.questModes[index], quest.mode == mode.id)
		end
		local nextQuest = GameConfig.pickAutoQuest(quest.mode, state.level, state.quests, state.autoQuest)
		local explain = if quest.mode == "mastery"
			then "Works through open quests in order until each has gold mastery, then does the one with the most XP."
			elseif quest.mode == "xp" then "Does the open quest that gives the most XP for its energy."
			else "Repeats the last quest you did."
		widgets.questPreview.Text = `{explain}\nNext: <b>{if nextQuest then nextQuest.name else "do a quest once first"}</b>`
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
