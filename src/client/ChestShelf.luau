-- Chest shelf at the top of the Inventory. Chests won from quests, foes,
-- the token shop and rewards wait here until the player opens them, one at
-- a time (Open 1) or ten at once (Open 10).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local ChestShelf = {}

local section = nil
local cards = {} -- [rarity id] = widgets
local odds = {} -- the odds popup's widgets
local oddsShown = nil -- the chest rarity the odds popup was built for

-- Everything a chest of this rarity can give, with the chance of each.
-- A chest picks a slot (even odds), then a chest item in that slot (even odds),
-- then a rarity at or above the chest's own, by the Market odds.
local function dropTable(rarityId: string)
	local minRank = GameConfig.getRarityRank(rarityId)
	local total = 0
	for index, rarity in GameConfig.Rarities do
		if index >= minRank then
			total += rarity.chance
		end
	end
	local rows, byRarity = {}, {}
	if total <= 0 then
		return rows, byRarity
	end
	for index, rarity in GameConfig.Rarities do
		if index >= minRank and rarity.chance > 0 then
			local rarityChance = rarity.chance / total
			table.insert(byRarity, { rarity = rarity, chance = rarityChance })
			for _, slot in GameConfig.GearSlots do
				local names = GameConfig.GearPools.chest.items[slot].names
				for _, name in names do
					table.insert(rows, {
						slot = slot,
						name = name,
						rarity = rarity.id,
						rank = index,
						chance = rarityChance / #GameConfig.GearSlots / #names,
					})
				end
			end
		end
	end
	table.sort(rows, function(a, b)
		if a.chance ~= b.chance then
			return a.chance > b.chance
		end
		return a.name < b.name
	end)
	return rows, byRarity
end

local function percent(chance: number): string
	local value = chance * 100
	if value < 0.1 then
		return "<0.1%"
	elseif value < 10 then
		return string.format("%.2f%%", value)
	end
	return string.format("%.1f%%", value)
end

local function buildOdds(ui)
	local page = ui.pages.ChestOdds
	local colors = ui.colors
	local summary = ui.makeText(page, UDim2.new(1, -10, 0, 40), UDim2.fromOffset(0, 0), colors.text, 13)
	summary.LayoutOrder = 1
	summary.RichText = true
	summary.Font = Enum.Font.GothamBold
	summary.TextXAlignment = Enum.TextXAlignment.Center
	odds.summary = summary
	local note = ui.makeText(page, UDim2.new(1, -10, 0, 20), UDim2.fromOffset(0, 0), colors.dim, 12)
	note.LayoutOrder = 100000
	note.TextXAlignment = Enum.TextXAlignment.Center
	note.Text = "Stats are fixed for each item. Chances shown are rounded."
	odds.rows = {}
	odds.page = page
end

local function oddsRow(ui, index: number)
	local row = odds.rows[index]
	if row then
		return row
	end
	local colors = ui.colors
	local frame = ui.makeFrame(odds.page, UDim2.new(1, -10, 0, 40), UDim2.fromOffset(0, 0), colors.row)
	frame.LayoutOrder = 10 + index
	ui.addCorner(frame, 6)
	local picture = ui.makeFrame(frame, UDim2.fromOffset(34, 34), UDim2.fromOffset(6, 3), colors.panel)
	picture.BackgroundTransparency = 1
	local name = ui.makeText(frame, UDim2.new(1, -150, 0, 20), UDim2.fromOffset(48, 2), colors.text, 14)
	name.Font = Enum.Font.GothamBold
	name.TextWrapped = false
	name.TextTruncate = Enum.TextTruncate.AtEnd
	local stats = ui.makeText(frame, UDim2.new(1, -150, 0, 16), UDim2.fromOffset(48, 21), colors.dim, 11)
	stats.RichText = true
	stats.TextWrapped = false
	local chance = ui.makeText(frame, UDim2.fromOffset(80, 40), UDim2.new(1, -90, 0, 0), colors.gold, 15)
	chance.Font = Enum.Font.GothamBold
	chance.TextXAlignment = Enum.TextXAlignment.Right
	row = { frame = frame, picture = picture, name = name, stats = stats, chance = chance }
	odds.rows[index] = row
	return row
end

-- Fills the odds popup for a chest rarity and opens it.
local function showOdds(ui, rarityId: string)
	if oddsShown ~= rarityId then
		oddsShown = rarityId
		local rows, byRarity = dropTable(rarityId)
		local parts = {}
		for _, entry in byRarity do
			local color = entry.rarity.color
			local hex = string.format("#%02X%02X%02X", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
			table.insert(parts, `<font color="{hex}">{percent(entry.chance)} {string.upper(entry.rarity.id)}</font>`)
		end
		odds.summary.Text = table.concat(parts, ",  ")
		for index, entry in rows do
			local row = oddsRow(ui, index)
			local rarity = GameConfig.getRarity(entry.rarity)
			row.frame.Visible = true
			ui.itemArt.set(row.picture, entry)
			row.name.Text = `{entry.rarity} {entry.name}`
			row.name.TextColor3 = rarity.color
			local attack, defense = GameConfig.getGearStats(entry.slot, entry.name, rarity)
			row.stats.Text = `{string.lower(entry.slot)}   <font color="#F08A6A">{attack} ATK</font>  <font color="#7FB4F0">{defense} DEF</font>`
			row.chance.Text = percent(entry.chance)
		end
		for index = #rows + 1, #odds.rows do
			odds.rows[index].frame.Visible = false
		end
	end
	ui.openModal("ChestOdds", `{rarityId} chest odds`)
end

function ChestShelf.build(ui)
	local page = ui.pages.Inventory
	local colors = ui.colors
	local art = ui.art

	section = ui.makeFrame(page, UDim2.new(1, -10, 0, 0), UDim2.fromOffset(0, 0), colors.panel)
	section.BackgroundTransparency = 1
	section.AutomaticSize = Enum.AutomaticSize.Y
	section.LayoutOrder = -5
	section.Visible = false
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 6)
	list.Parent = section

	ui.makeHeading(section, 1, "Chests")
	buildOdds(ui)

	local grid = ui.makeFrame(section, UDim2.new(1, 0, 0, 0), UDim2.fromOffset(0, 0), colors.panel)
	grid.BackgroundTransparency = 1
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.LayoutOrder = 2
	local layout = Instance.new("UIGridLayout")
	layout.CellPadding = UDim2.fromOffset(6, 6)
	layout.CellSize = UDim2.fromOffset(176, 150)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	for rank, rarity in GameConfig.Rarities do
		if rarity.chance <= 0 then
			continue -- Divine is for recruits only
		end
		local card = ui.makeFrame(grid, UDim2.fromOffset(100, 100), UDim2.fromOffset(0, 0), colors.row)
		card.LayoutOrder = -rank -- rarest first
		card.Visible = false
		ui.addCorner(card, 8)
		art.card(card)
		art.stroke(card, rarity.color, 1.5, 0.2)

		local picture = ui.makeFrame(card, UDim2.fromOffset(64, 64), UDim2.fromOffset(8, 8), colors.panel)
		picture.BackgroundTransparency = 1
		ui.itemArt.chest(picture, rarity.id)

		local name = ui.makeText(card, UDim2.new(1, -84, 0, 22), UDim2.fromOffset(78, 32), rarity.color, 15)
		name.Font = Enum.Font.GothamBold
		name.Text = `{rarity.id} chest`
		local count = ui.makeText(card, UDim2.new(1, -140, 0, 20), UDim2.fromOffset(78, 9), colors.text, 18)
		count.Font = Enum.Font.GothamBlack
		local note = ui.makeText(card, UDim2.new(1, -84, 0, 30), UDim2.fromOffset(78, 54), colors.dim, 11)
		note.Text = `{rarity.id} gear or better`

		local openOne = ui.makeButton(card, UDim2.new(0.5, -10, 0, 40), UDim2.new(0, 8, 1, -48), colors.gold)
		openOne.TextSize = 14
		local openTen = ui.makeButton(card, UDim2.new(0.5, -10, 0, 40), UDim2.new(0.5, 2, 1, -48), colors.claim)
		openTen.TextSize = 14
		-- Odds: everything this chest can give and the chance of each.
		local oddsButton = ui.makeButton(card, UDim2.fromOffset(52, 22), UDim2.new(1, -60, 0, 8), colors.info)
		oddsButton.TextSize = 11
		ui.setButton(oddsButton, "% ODDS", true, colors.info)
		oddsButton.Activated:Connect(function()
			showOdds(ui, rarity.id)
		end)
		openOne.Activated:Connect(function()
			ui.send("ChestOpen", `{rarity.id}:1`)
		end)
		openTen.Activated:Connect(function()
			ui.send("ChestOpen", `{rarity.id}:10`)
		end)

		cards[rarity.id] = { frame = card, count = count, openOne = openOne, openTen = openTen }
	end
end

function ChestShelf.draw(state, ui)
	local colors = ui.colors
	local chests = state.chests or {}
	local room = state.maxGear - #state.gear
	local total = 0
	for id, card in cards do
		local have = tonumber(chests[id]) or 0
		total += have
		card.frame.Visible = have > 0
		if have > 0 then
			card.count.Text = `x{have}`
			local canOpen = room > 0
			ui.setButton(card.openOne, if canOpen then "Open 1" else "Armory full", canOpen, colors.gold)
			local ten = math.min(10, have, math.max(room, 0))
			ui.setButton(card.openTen, if ten > 1 then `Open {ten}` else "Open 10", ten > 1, colors.claim)
		end
	end
	section.Visible = total > 0
	ui.setBadge("Inventory", total)
end

return ChestShelf
