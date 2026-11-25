-- Chest shelf at the top of the Inventory. Chests won, found in the Market
-- or bought in the Shop wait here until the player opens them, one at a
-- time (Open 1) or ten at once (Open 10). Every chest has an Odds button
-- listing what it can give.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local ChestConfig = require(Shared:WaitForChild("ChestConfig"))

local ChestShelf = {}

local section = nil
local cards = {} -- [chest id] = shelf widgets
local odds = {} -- the odds popup's widgets
local oddsShown = nil -- the chest rarity the odds popup was built for

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

-- Fills the odds popup for a chest and opens it.
local function showOdds(ui, chestId: string)
	local chest = ChestConfig.get(chestId)
	if not chest then
		return
	end
	if oddsShown ~= chestId then
		oddsShown = chestId
		local rows, byRarity = ChestConfig.dropTable(chest)
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
	ui.openModal("ChestOdds", `{chest.name} odds`)
end

local function chestPicture(ui, parent: Instance, chest, size: number)
	local picture = ui.makeFrame(parent, UDim2.fromOffset(size, size), UDim2.fromOffset(8, 8), ui.colors.panel)
	picture.BackgroundTransparency = 1
	ui.itemArt.chest(picture, ChestConfig.rarityOf(chest), if chest.rarity then nil else chest.color, chest.pool == "premium")
	return picture
end

local function oddsButton(ui, parent: Instance, chestId: string)
	local button = ui.makeButton(parent, UDim2.fromOffset(52, 22), UDim2.new(1, -60, 0, 8), ui.colors.info)
	button.TextSize = 11
	ui.setButton(button, "% ODDS", true, ui.colors.info)
	button.Activated:Connect(function()
		showOdds(ui, chestId)
	end)
	return button
end

local function makeSection(ui, page: Instance, order: number, title: string)
	local colors = ui.colors
	local holder = ui.makeFrame(page, UDim2.new(1, -10, 0, 0), UDim2.fromOffset(0, 0), colors.panel)
	holder.BackgroundTransparency = 1
	holder.AutomaticSize = Enum.AutomaticSize.Y
	holder.LayoutOrder = order
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 6)
	list.Parent = holder
	ui.makeHeading(holder, 1, title)
	local grid = ui.makeFrame(holder, UDim2.new(1, 0, 0, 0), UDim2.fromOffset(0, 0), colors.panel)
	grid.BackgroundTransparency = 1
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.LayoutOrder = 2
	local layout = Instance.new("UIGridLayout")
	layout.CellPadding = UDim2.fromOffset(6, 6)
	layout.CellSize = UDim2.fromOffset(176, 150)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	return holder, grid
end

function ChestShelf.build(ui)
	local colors = ui.colors
	local art = ui.art
	buildOdds(ui)

	local grid
	section, grid = makeSection(ui, ui.pages.Inventory, -5, "Chests")
	ChestShelf.section = section
	section.Visible = false
	for order, chest in ChestConfig.all() do
		local card = ui.makeFrame(grid, UDim2.fromOffset(100, 100), UDim2.fromOffset(0, 0), colors.row)
		card.LayoutOrder = order
		card.Visible = false
		ui.addCorner(card, 8)
		art.card(card)
		art.stroke(card, chest.color, 1.5, 0.2)
		chestPicture(ui, card, chest, 64)
		oddsButton(ui, card, chest.id)

		local count = ui.makeText(card, UDim2.new(1, -140, 0, 20), UDim2.fromOffset(78, 9), colors.text, 18)
		count.Font = Enum.Font.GothamBlack
		local name = ui.makeText(card, UDim2.new(1, -84, 0, 34), UDim2.fromOffset(78, 32), chest.color, 14)
		name.Font = Enum.Font.GothamBold
		name.Text = chest.name
		local note = ui.makeText(card, UDim2.new(1, -16, 0, 28), UDim2.fromOffset(8, 74), colors.dim, 11)
		note.Text = chest.note

		local openOne = ui.makeButton(card, UDim2.new(0.5, -10, 0, 40), UDim2.new(0, 8, 1, -46), colors.gold)
		openOne.TextSize = 14
		local openTen = ui.makeButton(card, UDim2.new(0.5, -10, 0, 40), UDim2.new(0.5, 2, 1, -46), colors.claim)
		openTen.TextSize = 14
		openOne.Activated:Connect(function()
			ui.send("ChestOpen", `{chest.id}:1`)
		end)
		openTen.Activated:Connect(function()
			ui.send("ChestOpen", `{chest.id}:10`)
		end)
		cards[chest.id] = { frame = card, count = count, openOne = openOne, openTen = openTen }
	end
end

function ChestShelf.draw(state, ui)
	local colors = ui.colors
	local chests = state.chests or {}
	local room = math.huge -- the armory has no limit
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
	ChestShelf.total = total
	ui.setBadge("Inventory", total)
end

return ChestShelf
