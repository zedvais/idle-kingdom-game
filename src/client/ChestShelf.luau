-- Chest shelf at the top of the Inventory. Chests won from quests, foes,
-- the token shop and rewards wait here until the player opens them, one at
-- a time (Open 1) or ten at once (Open 10).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local ChestShelf = {}

local section = nil
local cards = {} -- [rarity id] = widgets

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

		local name = ui.makeText(card, UDim2.new(1, -84, 0, 22), UDim2.fromOffset(78, 12), rarity.color, 15)
		name.Font = Enum.Font.GothamBold
		name.Text = `{rarity.id} chest`
		local count = ui.makeText(card, UDim2.new(1, -84, 0, 20), UDim2.fromOffset(78, 34), colors.text, 18)
		count.Font = Enum.Font.GothamBlack
		local note = ui.makeText(card, UDim2.new(1, -84, 0, 18), UDim2.fromOffset(78, 54), colors.dim, 11)
		note.Text = `{rarity.id} gear or better`

		local openOne = ui.makeButton(card, UDim2.new(0.5, -10, 0, 40), UDim2.new(0, 8, 1, -48), colors.gold)
		openOne.TextSize = 14
		local openTen = ui.makeButton(card, UDim2.new(0.5, -10, 0, 40), UDim2.new(0.5, 2, 1, -48), colors.claim)
		openTen.TextSize = 14
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
