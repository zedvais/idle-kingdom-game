-- Expeditions page: send your army on timed raids for loot.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArmyConfig = require(Shared:WaitForChild("ArmyConfig"))
local Format = require(Shared:WaitForChild("Format"))

local ExpeditionsPage = {}

local status
local cards = {}

function ExpeditionsPage.build(ui)
	local page = ui.pages.Expeditions
	status = ui.makeRow(page, ui.nextOrder(), 74, false)
	status.RichText = true
	local grid = ui.makeGrid(page, ui.nextOrder(), 170, 2)
	for _, expedition in ArmyConfig.Expeditions do
		local info, button = ui.makeCard(grid)
		info.RichText = true
		info.TextSize = 12
		cards[expedition.key] = { info = info, button = button }
		button.Activated:Connect(function()
			ui.send("Expedition", expedition.key)
		end)
	end
end

function ExpeditionsPage.draw(state, ui)
	local colors = ui.colors
	local away = state.expedition
	local isAway = away.target ~= ""
	local home = ArmyConfig.countTroops(state.troops)
	if isAway then
		local target = ArmyConfig.getExpedition(away.target)
		status.Text = `<b>Your army is away at {target and target.name or away.target}</b>\n`
			.. `Back in {ui.formatLong(state.expeditionLeft)} with {ArmyConfig.countTroops(away.sent)} troops. The battle is fought when they arrive.\n`
			.. "The report will be in the War Chronicle (Arena section)."
	else
		status.Text = `<b>{home} troops at home</b>\n`
			.. "Sending an expedition marches your whole army. Train troops that counter the enemy for more power.\n"
			.. `Your power must beat the enemy's to win. Losses grow the closer the fight is.`
	end

	for _, expedition in ArmyConfig.Expeditions do
		local card = cards[expedition.key]
		local attack = ArmyConfig.getPower(state.troops, expedition.enemy)
		local strong = attack >= expedition.power
		local powerColor = if strong then "#9FD49A" else "#E08A7A"
		local extras = {}
		if expedition.chest then
			table.insert(extras, `{math.floor(expedition.chestChance * 100)}% {expedition.chest} chest`)
		end
		for resource, amount in expedition.plunder or {} do
			table.insert(extras, 1, `{Format.short(amount)} {resource}`)
		end
		if expedition.crowns then
			table.insert(extras, `{math.floor(expedition.crownChance * 100)}% {expedition.crowns} Crowns`)
		end
		card.info.Text = `<b>{expedition.name}</b>   Level {expedition.level}, {expedition.minutes} min\n`
			.. `Enemy: {ArmyConfig.EnemyNames[expedition.enemy]}, power {Format.short(expedition.power)}\n`
			.. `Your power here: <font color="{powerColor}">{Format.short(attack)}</font>\n`
			.. `Loot: {expedition.goldMinutes}m of income, {expedition.tokens} tokens\n{table.concat(extras, ", ")}`
		if state.level < expedition.level then
			ui.setButton(card.button, `Level {expedition.level}`, false, colors.action)
		elseif isAway then
			ui.setButton(card.button, if away.target == expedition.key then "Army here" else "Army away", false, colors.action)
		elseif home == 0 then
			ui.setButton(card.button, "No troops", false, colors.action)
		else
			ui.setButton(card.button, if strong then "Send army" else "Send army (risky)", true, colors.action)
		end
	end
end

return ExpeditionsPage
