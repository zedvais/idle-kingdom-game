-- Barracks page: train troops for expeditions. Each troop type is strong
-- against one kind of enemy.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArmyConfig = require(Shared:WaitForChild("ArmyConfig"))
local ResearchConfig = require(Shared:WaitForChild("ResearchConfig"))
local Format = require(Shared:WaitForChild("Format"))

local BarracksPage = {}

local summary, finishButton
local cards = {}
local latest = nil -- the last state drawn, for the Train X popup

-- How many of a troop you could train right now.
local function canTrain(state, troop): number
	local total = ArmyConfig.countTroops(state.troops) + ArmyConfig.countTroops(state.expedition.sent) + state.training.count
	local room = state.armyCap - total
	return math.max(0, math.min(room, math.floor(state.gold / troop.cost)))
end

function BarracksPage.build(ui)
	local page = ui.pages.Barracks
	summary, finishButton = ui.makeRow(page, ui.nextOrder(), 74, true)
	summary.RichText = true
	finishButton.Activated:Connect(function()
		ui.send("TroopFinish")
	end)

	ui.makeHeading(page, ui.nextOrder(), "Troops")
	local grid = ui.makeGrid(page, ui.nextOrder(), 132, 3)
	for _, troop in ArmyConfig.Troops do
		local info, button = ui.makeCard(grid)
		info.RichText = true
		info.TextSize = 12
		-- Two buttons side by side: Train 1 and Train X (asks how many).
		button.Size = UDim2.new(0.5, -12, 0, 36)
		local many = ui.makeButton(button.Parent, UDim2.new(0.5, -12, 0, 36), UDim2.new(0.5, 4, 1, -42), ui.colors.buy)
		many.TextSize = 13
		cards[troop.key] = { info = info, button = button, many = many }
		button.Activated:Connect(function()
			ui.send("TroopTrain", `{troop.key}:1`)
		end)
		many.Activated:Connect(function()
			if not latest then
				return
			end
			local most = canTrain(latest, troop)
			if most < 1 then
				return
			end
			ui.askAmount({
				title = `Train {troop.name}`,
				note = `<b>{troop.name}</b>: {Format.short(troop.cost)} gold and {troop.seconds}s each.`,
				max = most,
				confirm = "Train",
				onConfirm = function(amount)
					ui.send("TroopTrain", `{troop.key}:{amount}`)
				end,
			})
		end)
	end
end

function BarracksPage.draw(state, ui)
	latest = state
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
		local most = canTrain(state, troop)
		if state.level < troop.level then
			ui.setButton(card.button, `Level {troop.level}`, false, colors.buy)
			ui.setButton(card.many, "Locked", false, colors.buy)
		elseif busy then
			ui.setButton(card.button, "Busy", false, colors.buy)
			ui.setButton(card.many, "Busy", false, colors.buy)
		elseif room <= 0 then
			ui.setButton(card.button, "Army full", false, colors.buy)
			ui.setButton(card.many, "Army full", false, colors.buy)
		else
			ui.setButton(card.button, "Train 1", state.gold >= troop.cost, colors.buy)
			ui.setButton(card.many, "Train X", most >= 1, colors.buy)
		end
	end
end

return BarracksPage
