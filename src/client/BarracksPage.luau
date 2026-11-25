-- Barracks page: train troops for expeditions. Each troop type is strong
-- against one kind of enemy.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArmyConfig = require(Shared:WaitForChild("ArmyConfig"))
local ResearchConfig = require(Shared:WaitForChild("ResearchConfig"))
local Format = require(Shared:WaitForChild("Format"))

local BarracksPage = {}

local summary, finishButton
local amountBox
local cards = {}

function BarracksPage.build(ui)
	local page = ui.pages.Barracks
	summary, finishButton = ui.makeRow(page, ui.nextOrder(), 74, true)
	summary.RichText = true
	finishButton.Activated:Connect(function()
		ui.send("TroopFinish")
	end)

	local amountRow = ui.makeFrame(page, UDim2.new(1, -10, 0, 48), UDim2.fromOffset(0, 0), ui.colors.row)
	amountRow.LayoutOrder = ui.nextOrder()
	ui.addCorner(amountRow, 6)
	local label = ui.makeText(amountRow, UDim2.new(0, 170, 1, 0), UDim2.fromOffset(10, 0), ui.colors.text, 13)
	label.Text = "How many to train"
	amountBox = ui.makeAmountBox(amountRow, UDim2.new(1, -190, 1, -12), UDim2.fromOffset(180, 6), "Leave empty to train as many as you can afford")

	ui.makeHeading(page, ui.nextOrder(), "Troops")
	local grid = ui.makeGrid(page, ui.nextOrder(), 132, 3)
	for _, troop in ArmyConfig.Troops do
		local info, button = ui.makeCard(grid)
		info.RichText = true
		info.TextSize = 12
		cards[troop.key] = { info = info, button = button }
		button.Activated:Connect(function()
			local text = string.gsub(amountBox.Text, "%D", "")
			ui.send("TroopTrain", `{troop.key}:{if text == "" then "max" else string.sub(text, 1, 6)}`)
		end)
	end
end

function BarracksPage.draw(state, ui)
	local colors = ui.colors
	local home = ArmyConfig.countTroops(state.troops)
	local away = ArmyConfig.countTroops(state.expedition.sent)
	local training = state.training
	local total = home + away + training.count
	local busy = training.count > 0

	local lines = { `<b>Army {total} / {state.armyCap}</b>   |   {home} at home, {away} away, {training.count} in training` }
	if busy then
		local troop = ArmyConfig.getTroop(training.kind)
		table.insert(lines, `Training {training.count} {troop and troop.name or training.kind}: ready in {ui.formatLong(state.trainingLeft)}.`)
		local cost = ResearchConfig.getFinishCost(state.trainingLeft)
		ui.setButton(finishButton, `Finish now\n{cost} Crowns`, state.crowns >= cost, colors.selected)
	else
		table.insert(lines, "The Barracks are free. One batch trains at a time and keeps going while you are away.")
		ui.setButton(finishButton, "Idle", false, colors.selected)
	end
	table.insert(lines, `Upgrade the Keep for a bigger army (+{ArmyConfig.CapPerKeep} per level).`)
	summary.Text = table.concat(lines, "\n")

	local room = state.armyCap - total
	for _, troop in ArmyConfig.Troops do
		local card = cards[troop.key]
		local have = state.troops[troop.key] or 0
		card.info.Text = `<b>{troop.name}</b>   you have {have}\n{troop.note}\n`
			.. `Attack {troop.attack}, defense {troop.defense}\n{Format.short(troop.cost)} gold, {troop.seconds}s each`
		if state.level < troop.level then
			ui.setButton(card.button, `Level {troop.level}`, false, colors.buy)
		elseif busy then
			ui.setButton(card.button, "Barracks busy", false, colors.buy)
		elseif room <= 0 then
			ui.setButton(card.button, "Army full", false, colors.buy)
		else
			ui.setButton(card.button, "Train", state.gold >= troop.cost, colors.buy)
		end
	end
end

return BarracksPage
