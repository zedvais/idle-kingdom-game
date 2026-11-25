-- Estate page: resources, building upgrades on a timer, defenses and extra
-- castles. Each castle has its own builder and the same set of buildings.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local EstateConfig = require(Shared:WaitForChild("EstateConfig"))
local ResearchConfig = require(Shared:WaitForChild("ResearchConfig"))
local Format = require(Shared:WaitForChild("Format"))

local EstatePage = {}

local castleTabs
local stockInfo
local castleInfo, castleButton
local cards = {}
local selected = "home"
local latest = nil -- the last state drawn

local function percent(value: number): string
	return `{math.floor(value * 1000 + 0.5) / 10}%`
end

-- What a building does at a level, as short words.
local function effect(building, level: number): string
	if building.kind == "produce" then
		return `{Format.short(EstateConfig.getRate(building, level))} {building.resource}/h`
	elseif building.kind == "storage" then
		return `+{Format.short(EstateConfig.getCapBonus(building, level))} storage`
	elseif building.kind == "cellar" then
		return `{percent(building.percent * level)} hidden`
	end
	return `+{percent(building.percent * level)} defense`
end

function EstatePage.build(ui)
	local page = ui.pages.Estate
	local names = {}
	for index, castle in EstateConfig.Castles do
		names[index] = castle.name
	end
	castleTabs = ui.makeButtonRow(page, ui.nextOrder(), "", names)
	for index, castle in EstateConfig.Castles do
		castleTabs[index].Activated:Connect(function()
			selected = castle.key
			ui.redraw()
		end)
	end

	stockInfo = ui.makeRow(page, ui.nextOrder(), 74, false)
	stockInfo.RichText = true

	castleInfo, castleButton = ui.makeRow(page, ui.nextOrder(), 56, true)
	castleInfo.RichText = true
	castleButton.Activated:Connect(function()
		local state = latest
		if not state then
			return
		end
		local castle = state.estate.castles[selected]
		if not castle then
			ui.send("CastleBuy", selected)
		elseif castle.build.key ~= "" then
			ui.send("EstateFinish", selected)
		end
	end)

	ui.makeHeading(page, ui.nextOrder(), "Buildings")
	local grid = ui.makeGrid(page, ui.nextOrder(), 150, 3)
	for _, building in EstateConfig.Buildings do
		local info, button = ui.makeCard(grid)
		info.RichText = true
		info.TextSize = 12
		cards[building.key] = { info = info, button = button }
		button.Activated:Connect(function()
			ui.send("EstateBuild", `{selected}:{building.key}`)
		end)
	end
end

function EstatePage.draw(state, ui)
	latest = state
	local colors = ui.colors
	local estate = state.estate
	local summary = state.estateSummary
	local stock = estate.stock

	for index, castle in EstateConfig.Castles do
		local owned = estate.castles[castle.key] ~= nil
		local tab = castleTabs[index]
		tab.Text = if owned then castle.name else `{castle.name} (lvl {castle.level})`
		tab.TextSize = 12
		tab.BackgroundColor3 = if castle.key == selected then colors.selected else colors.row
		tab.TextColor3 = if castle.key == selected then colors.gold else (if owned then colors.text else colors.dim)
	end

	local parts = {}
	for _, resource in EstateConfig.Resources do
		local have = stock[resource.key] or 0
		local cap = summary.caps[resource.key]
		local full = if have >= cap then " <b>FULL</b>" else ""
		table.insert(parts, `<font color="{resource.color}"><b>{resource.name}</b></font> {Format.short(have)} / {Format.short(cap)}  (+{Format.short(summary.rates[resource.key])}/h){full}`)
	end
	stockInfo.Text = `{parts[1]}     {parts[2]}\n{parts[3]}     {parts[4]}\n`
		.. `<font color="#B2A690">Hidden Cellar keeps {percent(summary.cellar)} safe from raids. Walls and towers: +{percent(summary.defense)} defense.</font>`

	local castleDef = EstateConfig.getCastle(selected)
	local castle = estate.castles[selected]
	local busy = false
	if not castle then
		local cost = castleDef.cost or {}
		castleInfo.Text = `<b>{castleDef.name}</b> is not yours yet.\nClaim it for {EstateConfig.describeCost(cost, Format.short)}. It comes with its own builder and buildings.`
		if state.level < castleDef.level then
			ui.setButton(castleButton, `Level {castleDef.level}`, false, colors.buy)
		else
			ui.setButton(castleButton, "Claim", EstateConfig.canPay(cost, state.gold, stock), colors.buy)
		end
	elseif castle.build.key ~= "" then
		busy = true
		local building = EstateConfig.getBuilding(castle.build.key)
		local left = state.estateLeft[selected] or 0
		local cost = ResearchConfig.getFinishCost(left)
		castleInfo.Text = `<b>Builder:</b> {building and building.name or castle.build.key} to level {castle.build.level}, ready in {ui.formatLong(left)}.\n`
			.. "One upgrade at a time per castle. It keeps going while you are away."
		ui.setButton(castleButton, `Finish now\n{cost} Crowns`, state.crowns >= cost, colors.selected)
	else
		castleInfo.Text = `<b>Builder: free</b> at {castleDef.name}.\nPick a building below to upgrade. Each castle has its own builder.`
		ui.setButton(castleButton, "Idle", false, colors.selected)
	end

	for _, building in EstateConfig.Buildings do
		local card = cards[building.key]
		local level = if castle then castle.levels[building.key] or 0 else 0
		local header = `<b>{building.name}</b>   Lv {level}\n<font color="#B2A690">{building.note}</font>\n`
		if level >= EstateConfig.MaxLevel then
			card.info.Text = header .. `Now: {effect(building, level)}\nTop level.`
			ui.setButton(card.button, "Max level", false, colors.buy)
			continue
		end
		local cost = EstateConfig.getCost(building, level)
		card.info.Text = header
			.. `{effect(building, level)} -> {effect(building, level + 1)}\n`
			.. `{EstateConfig.describeCost(cost, Format.short)}, {ui.formatLong(EstateConfig.getSeconds(building, level))}`
		if not castle then
			ui.setButton(card.button, "Claim castle first", false, colors.buy)
		elseif state.level < building.level then
			ui.setButton(card.button, `Level {building.level}`, false, colors.buy)
		elseif busy then
			ui.setButton(card.button, if castle.build.key == building.key then "Building..." else "Builder busy", false, colors.buy)
		else
			ui.setButton(card.button, if level == 0 then "Build" else "Upgrade", EstateConfig.canPay(cost, state.gold, stock), colors.buy)
		end
	end
end

return EstatePage
