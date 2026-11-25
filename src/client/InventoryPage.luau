-- Inventory page (like Idle Mafia's):
--   * a header: INVENTORY, a search box, a Warband button and the item count,
--   * tabs ALL / WEAPONS / ARMOR / MOUNTS / CHESTS / SETS / TROPHIES and an
--     ALL RARITIES drop-down,
--   * a grid of item cards: slot, picture with "xN", name, attack and
--     defense, and a rarity bar. Pressing a card opens the Item popup
--     (sell 1 / some / all, put in the Relic Hall, go equip it).
--   * an empty message when nothing matches.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local RelicConfig = require(Shared:WaitForChild("RelicConfig"))
local Format = require(Shared:WaitForChild("Format"))

local InventoryPage = {}

local TABS = {
	{ "All", "ALL" },
	{ "Weapon", "WEAPONS" },
	{ "Armor", "ARMOR" },
	{ "Mount", "MOUNTS" },
	{ "Chests", "CHESTS" },
	{ "Sets", "SETS" },
	{ "Trophies", "TROPHIES" },
}
local EMPTY_WORDS = { All = "items", Weapon = "weapons", Armor = "armor", Mount = "mounts", Chests = "chests", Sets = "sets", Trophies = "trophies" }
local MAX_CARDS = 240 -- cards drawn at once; search narrows the rest
local GREEN = Color3.fromRGB(120, 220, 120)

local tab = "All"
local rarityRank = 0 -- 0 = every rarity, else only this rarity
local search = ""
local latest = nil
local w = {}
local cards = {} -- pooled item cards
local trophyCards = {}
local setCards = {}
local chosenUid = nil -- the item the Item popup shows

local function memberName(state, member: number?): string
	if member == 0 then
		return "You"
	end
	local soldier = member and state.crew[member]
	return if soldier then soldier.name else "someone"
end

local function perkText(perk): string
	local parts = {}
	for _, pair in GameConfig.TrophyBonusNames do
		local amount = perk[pair[1]]
		if amount then
			table.insert(parts, `+{math.floor(amount * 100 + 0.5)}% {pair[2]}`)
		end
	end
	return table.concat(parts, ", ")
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

local function buildHeader(ui, page: Instance)
	local colors = ui.colors
	local bar = ui.makeFrame(page, UDim2.new(1, -10, 0, 64), UDim2.fromOffset(0, 0), Color3.fromRGB(44, 36, 22))
	bar.LayoutOrder = -20
	ui.addCorner(bar, 6)
	ui.art.stroke(bar, colors.gold, 1.5, 0.3)
	local title = ui.makeText(bar, UDim2.fromOffset(200, 64), UDim2.fromOffset(18, 0), colors.gold, 36)
	title.Font = ui.art.Fonts.title
	title.Text = "Inventory"

	local box = Instance.new("TextBox")
	box.Size = UDim2.new(0.4, -120, 0, 44)
	box.Position = UDim2.fromOffset(210, 10)
	box.BackgroundColor3 = Color3.fromRGB(24, 20, 16)
	box.TextColor3 = colors.text
	box.PlaceholderText = "Search items"
	box.PlaceholderColor3 = colors.dim
	box.Font = Enum.Font.GothamMedium
	box.TextSize = 18
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.ClearTextOnFocus = false
	box.Text = ""
	box.Parent = bar
	ui.addCorner(box, 6)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 44)
	pad.Parent = box
	-- A drawn magnifying glass (emoji do not show inside text boxes).
	local lens = ui.makeFrame(bar, UDim2.fromOffset(18, 18), UDim2.fromOffset(222, 20), Color3.new(0, 0, 0))
	lens.BackgroundTransparency = 1
	lens.ZIndex = box.ZIndex + 2
	ui.addCorner(lens, 9)
	ui.art.stroke(lens, colors.gold, 3, 0)
	local handle = ui.makeFrame(bar, UDim2.fromOffset(10, 4), UDim2.fromOffset(236, 39), colors.gold)
	handle.Rotation = 45
	handle.ZIndex = box.ZIndex + 2
	ui.addCorner(handle, 2)
	box:GetPropertyChangedSignal("Text"):Connect(function()
		search = string.lower(box.Text)
		InventoryPage.draw(latest, ui)
	end)

	w.warband = ui.makeButton(bar, UDim2.new(0.3, -20, 0, 44), UDim2.new(0.4, 100, 0, 10), Color3.fromRGB(30, 24, 16))
	w.warband.TextSize = 18
	w.warband.Font = Enum.Font.GothamBlack
	w.warband.TextColor3 = colors.gold
	ui.art.stroke(w.warband, colors.gold, 2, 0)
	w.warband.Activated:Connect(function()
		ui.showPage("Warband")
	end)
	w.count = ui.makeText(bar, UDim2.new(0.3, -100, 0, 44), UDim2.new(0.7, 90, 0, 10), colors.text, 18)
	w.count.BackgroundTransparency = 0
	w.count.BackgroundColor3 = Color3.fromRGB(24, 20, 16)
	w.count.Font = Enum.Font.GothamBlack
	w.count.TextXAlignment = Enum.TextXAlignment.Center
	ui.addCorner(w.count, 6)
end

local function buildTabs(ui, page: Instance)
	local colors = ui.colors
	local row = ui.makeFrame(page, UDim2.new(1, -10, 0, 44), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	row.BackgroundTransparency = 1
	row.LayoutOrder = -19
	row.ZIndex = 5
	local share = 1 / (#TABS + 1.4)
	w.tabs = {}
	for index, info in TABS do
		local button = ui.makeButton(row, UDim2.new(share, -6, 1, 0), UDim2.new(share * (index - 1), 0, 0, 0), Color3.fromRGB(40, 34, 28))
		button.TextSize = 14
		button.Font = Enum.Font.GothamBlack
		button.Text = info[2]
		local stroke = ui.art.stroke(button, colors.gold, 2, 1)
		w.tabs[info[1]] = { button = button, stroke = stroke }
		button.Activated:Connect(function()
			tab = info[1]
			InventoryPage.draw(latest, ui)
		end)
	end
	-- Rarity drop-down.
	local drop = ui.makeButton(row, UDim2.new(share * 1.4, -4, 1, 0), UDim2.new(share * #TABS, 0, 0, 0), Color3.fromRGB(30, 24, 16))
	drop.TextSize = 14
	drop.Font = Enum.Font.GothamBlack
	drop.TextColor3 = colors.text
	ui.art.stroke(drop, colors.gold, 1.5, 0.3)
	w.drop = drop
	-- A drawn "v" at the right (the font has no arrow glyph).
	for side = 0, 1 do
		local arm = ui.makeFrame(drop, UDim2.fromOffset(10, 3), UDim2.new(1, -24 + side * 6, 0.5, -1), colors.gold)
		arm.Rotation = if side == 0 then 45 else -45
		ui.addCorner(arm, 2)
	end
	local list = ui.makeFrame(drop, UDim2.new(1, 0, 0, 0), UDim2.new(0, 0, 1, 6), Color3.fromRGB(26, 22, 18))
	list.AutomaticSize = Enum.AutomaticSize.Y
	list.Visible = false
	list.ZIndex = 700
	ui.addCorner(list, 6)
	ui.art.stroke(list, colors.gold, 2, 0)
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	for rank = 0, #GameConfig.Rarities do
		local rarity = GameConfig.Rarities[rank]
		local option = ui.makeButton(list, UDim2.new(1, 0, 0, 40), UDim2.fromOffset(0, 0), Color3.fromRGB(26, 22, 18))
		option.BackgroundTransparency = 1
		option.LayoutOrder = rank
		option.ZIndex = 701
		option.TextSize = 17
		option.Font = Enum.Font.GothamBlack
		option.Text = if rarity then string.upper(rarity.id) else "ALL RARITIES"
		option.TextColor3 = if rarity then rarity.color else colors.text
		option.Activated:Connect(function()
			rarityRank = rank
			list.Visible = false
			InventoryPage.draw(latest, ui)
		end)
	end
	drop.Activated:Connect(function()
		list.Visible = not list.Visible
	end)
	w.dropList = list
end

local function grid(ui, page: Instance, order: number, height: number, columns: number): Frame
	local frame = ui.makeFrame(page, UDim2.new(1, -10, 0, 0), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	frame.BackgroundTransparency = 1
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.LayoutOrder = order
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(1 / columns, -10, 0, height)
	layout.CellPadding = UDim2.fromOffset(12, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame
	return frame
end

local function makeCard(ui, index: number)
	local colors = ui.colors
	local card = ui.makeFrame(w.grid, UDim2.fromOffset(100, 100), UDim2.fromOffset(0, 0), Color3.fromRGB(30, 27, 24))
	card.LayoutOrder = index
	ui.addCorner(card, 6)
	local stroke = ui.art.stroke(card, colors.gold, 2.5, 0)
	local slot = ui.makeText(card, UDim2.new(1, -24, 0, 22), UDim2.fromOffset(16, 10), colors.dim, 14)
	slot.Font = Enum.Font.GothamBlack
	local pictureBack = ui.makeFrame(card, UDim2.new(1, -24, 0, 140), UDim2.fromOffset(12, 34), Color3.fromRGB(22, 20, 18))
	ui.addCorner(pictureBack, 4)
	local picture = ui.makeFrame(pictureBack, UDim2.fromOffset(130, 130), UDim2.new(0.5, -65, 0, 5), Color3.new(0, 0, 0))
	picture.BackgroundTransparency = 1
	local count = ui.makeText(pictureBack, UDim2.fromOffset(90, 40), UDim2.new(1, -96, 0.5, -20), Color3.new(1, 1, 1), 30)
	count.Font = Enum.Font.GothamBlack
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.TextStrokeTransparency = 0.2
	count.ZIndex = 420
	local worn = ui.makeText(pictureBack, UDim2.fromOffset(110, 22), UDim2.fromOffset(6, 6), Color3.fromRGB(30, 20, 6), 11)
	worn.BackgroundTransparency = 0
	worn.BackgroundColor3 = colors.gold
	worn.Font = Enum.Font.GothamBlack
	worn.TextXAlignment = Enum.TextXAlignment.Center
	worn.TextTruncate = Enum.TextTruncate.AtEnd
	worn.ZIndex = 420
	ui.addCorner(worn, 4)
	local name = ui.makeText(card, UDim2.new(1, -20, 0, 48), UDim2.fromOffset(10, 178), colors.text, 18)
	name.Font = Enum.Font.GothamBlack
	name.TextXAlignment = Enum.TextXAlignment.Center
	local stats = ui.makeText(card, UDim2.new(1, -20, 0, 22), UDim2.fromOffset(10, 228), GREEN, 15)
	stats.Font = Enum.Font.GothamBold
	stats.TextXAlignment = Enum.TextXAlignment.Center
	local band = ui.makeText(card, UDim2.new(1, -24, 0, 32), UDim2.new(0, 12, 1, -42), Color3.fromRGB(30, 20, 10), 16)
	band.BackgroundTransparency = 0
	band.Font = Enum.Font.GothamBlack
	band.TextXAlignment = Enum.TextXAlignment.Center
	ui.addCorner(band, 3)
	local hit = ui.makeButton(card, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.ZIndex = 450
	local part = { card = card, stroke = stroke, slot = slot, picture = picture, count = count, worn = worn, name = name, stats = stats, band = band, uid = nil }
	hit.Activated:Connect(function()
		if part.uid then
			chosenUid = part.uid
			ui.openModal("Item", "Item")
		end
	end)
	cards[index] = part
	return part
end

local function buildSets(ui, page: Instance)
	local colors = ui.colors
	w.sets = grid(ui, page, 2, 150, 2)
	for index, set in GameConfig.GearSets do
		local card = ui.makeFrame(w.sets, UDim2.fromOffset(100, 100), UDim2.fromOffset(0, 0), Color3.fromRGB(30, 27, 24))
		card.LayoutOrder = index
		ui.addCorner(card, 6)
		local stroke = ui.art.stroke(card, colors.dim, 2, 0.2)
		local name = ui.makeText(card, UDim2.new(1, -24, 0, 28), UDim2.fromOffset(14, 8), colors.gold, 20)
		name.Font = ui.art.Fonts.heading
		name.Text = `{set.name} set`
		local note = ui.makeText(card, UDim2.new(1, -24, 0, 18), UDim2.fromOffset(14, 36), GREEN, 13)
		note.Font = Enum.Font.GothamBold
		note.Text = `Full set: {perkText(set.perk)}`
		local pieces = {}
		for slotIndex, slot in GameConfig.GearSlots do
			local tile = ui.makeFrame(card, UDim2.fromOffset(76, 76), UDim2.fromOffset(14 + (slotIndex - 1) * 84, 60), Color3.fromRGB(22, 20, 18))
			ui.addCorner(tile, 6)
			local art = ui.makeFrame(tile, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
			art.BackgroundTransparency = 1
			pieces[slot] = { tile = tile, art = art }
		end
		local status = ui.makeText(card, UDim2.new(1, -280, 0, 76), UDim2.fromOffset(270, 60), colors.text, 15)
		status.Font = Enum.Font.GothamBlack
		status.TextXAlignment = Enum.TextXAlignment.Right
		setCards[set.id] = { stroke = stroke, pieces = pieces, status = status, set = set }
	end
end

local function buildTrophies(ui, page: Instance)
	local colors = ui.colors
	w.trophies = grid(ui, page, 3, 130, 3)
	for index, trophy in GameConfig.Trophies do
		local card = ui.makeFrame(w.trophies, UDim2.fromOffset(100, 100), UDim2.fromOffset(0, 0), Color3.fromRGB(30, 27, 24))
		card.LayoutOrder = index
		ui.addCorner(card, 6)
		local stroke = ui.art.stroke(card, colors.dim, 2, 0.2)
		local glyph = ui.makeText(card, UDim2.fromOffset(60, 60), UDim2.fromOffset(10, 10), Color3.new(1, 1, 1), 40)
		glyph.TextXAlignment = Enum.TextXAlignment.Center
		glyph.Text = "\u{1F3C6}"
		local name = ui.makeText(card, UDim2.new(1, -84, 0, 24), UDim2.fromOffset(76, 10), colors.text, 16)
		name.Font = Enum.Font.GothamBlack
		name.Text = trophy.name
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local note = ui.makeText(card, UDim2.new(1, -84, 0, 34), UDim2.fromOffset(76, 34), colors.dim, 12)
		note.Text = trophy.note
		local bonus = ui.makeText(card, UDim2.new(1, -20, 0, 18), UDim2.fromOffset(10, 76), GREEN, 13)
		bonus.Font = Enum.Font.GothamBold
		bonus.Text = perkText(trophy)
		local back = ui.makeFrame(card, UDim2.new(1, -20, 0, 18), UDim2.new(0, 10, 1, -26), Color3.fromRGB(18, 16, 14))
		ui.addCorner(back, 5)
		local fill = ui.makeFrame(back, UDim2.fromScale(0, 1), UDim2.fromOffset(0, 0), colors.gold)
		ui.addCorner(fill, 5)
		local value = ui.makeText(back, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1), 11)
		value.Font = Enum.Font.GothamBlack
		value.TextXAlignment = Enum.TextXAlignment.Center
		value.ZIndex = fill.ZIndex + 1
		trophyCards[trophy.id] = { stroke = stroke, glyph = glyph, fill = fill, value = value, trophy = trophy }
	end
end

local function buildItemPopup(ui)
	local page = ui.pages.Item
	local colors = ui.colors
	local box = ui.makeFrame(page, UDim2.new(1, -10, 0, 440), UDim2.fromOffset(0, 0), Color3.fromRGB(30, 27, 24))
	box.LayoutOrder = 1
	ui.addCorner(box, 8)
	w.itemStroke = ui.art.stroke(box, colors.gold, 2.5, 0)
	local back = ui.makeFrame(box, UDim2.fromOffset(170, 170), UDim2.fromOffset(16, 16), Color3.fromRGB(22, 20, 18))
	ui.addCorner(back, 6)
	w.itemPicture = ui.makeFrame(back, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	w.itemPicture.BackgroundTransparency = 1
	w.itemRarity = ui.makeText(box, UDim2.new(1, -220, 0, 22), UDim2.fromOffset(204, 18), colors.text, 16)
	w.itemRarity.Font = Enum.Font.GothamBlack
	w.itemName = ui.makeText(box, UDim2.new(1, -220, 0, 60), UDim2.fromOffset(204, 40), colors.text, 24)
	w.itemName.Font = Enum.Font.GothamBlack
	w.itemStats = ui.makeText(box, UDim2.new(1, -220, 0, 24), UDim2.fromOffset(204, 104), GREEN, 18)
	w.itemStats.Font = Enum.Font.GothamBold
	w.itemInfo = ui.makeText(box, UDim2.new(1, -220, 0, 60), UDim2.fromOffset(204, 132), colors.dim, 14)
	w.itemInfo.RichText = true

	local function button(text: string, x: number, y: number, width: number, color: Color3, onPress)
		local b = ui.makeButton(box, UDim2.new(width, -16, 0, 50), UDim2.new(x, 8, 0, y), color)
		b.TextSize = 16
		b.Font = Enum.Font.GothamBlack
		b.Text = text
		b.Activated:Connect(onPress)
		return b
	end
	local function item()
		local state = latest
		if not state or not chosenUid then
			return nil
		end
		for _, entry in state.gear do
			if entry.uid == chosenUid then
				return entry
			end
		end
		return nil
	end
	w.sellOne = button("SELL 1", 0, 210, 1 / 3, colors.action, function()
		local entry = item()
		if entry then
			ui.send("Sell", `{entry.uid}:1`)
		end
	end)
	w.sellSome = button("SELL SOME", 1 / 3, 210, 1 / 3, colors.action, function()
		local entry = item()
		if entry and ui.askAmount then
			ui.askAmount({
				title = "Sell how many?",
				note = `<b>{entry.rarity} {entry.name}</b>: {entry.count or 1} spare.`,
				max = entry.count or 1,
				confirm = "Sell",
				preview = function(amount: number)
					return `+{Format.short(math.floor((entry.price or 0) * GameConfig.SellShare) * amount)} gold`
				end,
				onConfirm = function(amount: number)
					ui.send("Sell", `{entry.uid}:{amount}`)
				end,
			})
		end
	end)
	w.sellAll = button("SELL ALL", 2 / 3, 210, 1 / 3, colors.action, function()
		local entry = item()
		if entry then
			ui.send("Sell", `{entry.uid}:all`)
		end
	end)
	w.relic = button("\u{1F3FA} PUT ALL IN RELIC HALL", 0, 272, 1, colors.selected, function()
		local entry = item()
		if entry then
			ui.send("RelicDepositMany", `{entry.count or 1}:{RelicConfig.getKey(entry)}`)
		end
	end)
	w.equip = button("\u{2694}\u{FE0F} EQUIP IT ON THE WARBAND PAGE", 0, 334, 1, colors.buy, function()
		ui.closeModal()
		ui.showPage("Warband")
	end)
	w.itemGone = ui.makeText(box, UDim2.new(1, -32, 0, 30), UDim2.fromOffset(16, 396), colors.dim, 14)
end

function InventoryPage.build(ui)
	local page = ui.pages.Inventory
	buildHeader(ui, page)
	buildTabs(ui, page)
	w.grid = grid(ui, page, 1, 300, 4)
	buildSets(ui, page)
	buildTrophies(ui, page)
	w.empty = ui.makeText(page, UDim2.new(1, -10, 0, 260), UDim2.fromOffset(0, 0), ui.colors.dim, 30)
	w.empty.LayoutOrder = 4
	w.empty.TextXAlignment = Enum.TextXAlignment.Center
	w.more = ui.makeText(page, UDim2.new(1, -10, 0, 30), UDim2.fromOffset(0, 0), ui.colors.dim, 14)
	w.more.LayoutOrder = 5
	w.more.TextXAlignment = Enum.TextXAlignment.Center
	buildItemPopup(ui)
	page:GetPropertyChangedSignal("Visible"):Connect(function()
		if page.Visible then
			InventoryPage.draw(latest, ui)
		else
			w.dropList.Visible = false
		end
	end)
	ui.openInventory = function(which: string)
		tab = which
		ui.showPage("Inventory")
		InventoryPage.draw(latest, ui)
	end
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function drawItems(state, ui)
	local colors = ui.colors
	local list = {}
	for _, item in state.gear do
		local slotMatches = tab == "All" or item.slot == tab
		local rarityMatches = rarityRank == 0 or GameConfig.getRarityRank(item.rarity) == rarityRank
		local searchMatches = search == "" or string.find(string.lower(item.name), search, 1, true) ~= nil
		if slotMatches and rarityMatches and searchMatches then
			table.insert(list, item)
		end
	end
	table.sort(list, function(a, b)
		local ra, rb = GameConfig.getRarityRank(a.rarity), GameConfig.getRarityRank(b.rarity)
		if ra ~= rb then
			return ra > rb
		end
		if a.attack + a.defense ~= b.attack + b.defense then
			return a.attack + a.defense > b.attack + b.defense
		end
		return a.name < b.name
	end)
	local shown = math.min(#list, MAX_CARDS)
	for index = 1, math.max(shown, #cards) do
		local item = if index <= shown then list[index] else nil
		local part = cards[index] or (item and makeCard(ui, index))
		if part then
			part.card.Visible = item ~= nil
			part.uid = item and item.uid
			if item then
				local rarity = GameConfig.getRarity(item.rarity)
				part.stroke.Color = rarity.color
				part.slot.Text = string.upper(item.slot)
				ui.itemArt.set(part.picture, item)
				part.count.Text = `x{Format.short(item.count or 1)}`
				part.worn.Visible = item.wornBy ~= nil
				part.worn.Text = if item.wornBy ~= nil then `WORN: {string.upper(memberName(state, item.wornBy))}` else ""
				part.name.Text = item.name
				part.stats.Text = `+{item.attack} Attack   +{item.defense} Defense`
				part.band.Text = string.upper(rarity.id)
				part.band.BackgroundColor3 = rarity.color
			end
		end
	end
	w.grid.Visible = shown > 0
	w.more.Visible = #list > MAX_CARDS
	w.more.Text = `Showing {MAX_CARDS} of {#list} stacks. Search or pick a rarity to find the rest.`
	return #list
end

local function drawSets(state, ui)
	local colors = ui.colors
	local owned = {}
	for _, item in state.gear do
		if item.set then
			local best = owned[item.name]
			if not best or GameConfig.getRarityRank(item.rarity) > GameConfig.getRarityRank(best.rarity) then
				owned[item.name] = item
			end
		end
	end
	for _, part in setCards do
		local set = part.set
		local have = 0
		for _, slot in GameConfig.GearSlots do
			local item = owned[set.pieces[slot]]
			local piece = part.pieces[slot]
			if item then
				have += 1
				ui.itemArt.set(piece.art, item)
			else
				ui.itemArt.set(piece.art, { slot = slot, name = set.pieces[slot], rarity = "Common", set = set.id }, true)
			end
		end
		local full = state.fullSets and state.fullSets[set.id] == true
		part.status.Text = if full then "\u{2714} WORN IN FULL" else `{have} / {GameConfig.SetPieceCount} OWNED`
		part.status.TextColor3 = if full then GREEN elseif have == GameConfig.SetPieceCount then colors.gold else colors.dim
		part.stroke.Color = if full then GREEN elseif have > 0 then colors.gold else colors.dim
	end
end

local function drawTrophies(state, ui)
	local colors = ui.colors
	local earned = 0
	for _, part in trophyCards do
		local trophy = part.trophy
		local done = state.trophies[trophy.id] == true
		if done then
			earned += 1
		end
		local progress = if done then trophy.value else math.min(trophy.value, state.trophyProgress[trophy.id] or 0)
		part.fill.Size = UDim2.fromScale(progress / trophy.value, 1)
		part.value.Text = if done then "EARNED" else `{Format.short(progress)} / {Format.short(trophy.value)}`
		part.stroke.Color = if done then colors.gold else colors.dim
		part.glyph.TextTransparency = if done then 0 else 0.6
	end
	return earned
end

local function drawItemPopup(state, ui)
	local colors = ui.colors
	local item = nil
	for _, entry in state.gear do
		if entry.uid == chosenUid then
			item = entry
		end
	end
	local exists = item ~= nil
	w.itemGone.Text = if exists then "" else "This item is gone (sold or moved)."
	if not item then
		for _, b in { w.sellOne, w.sellSome, w.sellAll, w.relic } do
			ui.setButton(b, b.Text, false, colors.action)
		end
		return
	end
	local rarity = GameConfig.getRarity(item.rarity)
	w.itemStroke.Color = rarity.color
	ui.itemArt.set(w.itemPicture, item)
	w.itemRarity.Text = `{string.upper(rarity.id)} {string.upper(item.slot)}`
	w.itemRarity.TextColor3 = rarity.color
	w.itemName.Text = item.name
	w.itemStats.Text = `+{item.attack} Attack   +{item.defense} Defense`
	local count = item.count or 1
	local each = math.floor((item.price or 0) * GameConfig.SellShare)
	local set = item.set and GameConfig.getGearSet(item.set)
	w.itemInfo.Text = `You have <b>x{Format.short(count)}</b>   \u{00B7}   sells for <b>{Format.short(each)}</b> gold each`
		.. (if item.wornBy ~= nil then `\n<font color="#F0C450">Worn by {memberName(state, item.wornBy)}</font>` else "\nSpare")
		.. (if set then `\nPart of the {set.name} set` else "")
	local spare = item.wornBy == nil
	ui.setButton(w.sellOne, `SELL 1\n+{Format.short(each)}`, spare, colors.action)
	ui.setButton(w.sellSome, "SELL SOME", spare and count > 1, colors.action)
	ui.setButton(w.sellAll, `SELL ALL\n+{Format.short(each * count)}`, spare, colors.action)
	ui.setButton(w.relic, `\u{1F3FA} PUT {if count > 1 then "ALL" else "IT"} IN THE RELIC HALL`, spare, colors.selected)
	ui.setButton(w.equip, if spare then "\u{2694}\u{FE0F} EQUIP IT ON THE WARBAND PAGE" else "\u{2694}\u{FE0F} CHANGE GEAR ON THE WARBAND PAGE", true, colors.buy)
end

function InventoryPage.draw(state, ui)
	if not state then
		return
	end
	latest = state
	if ui.isOpen("Item") then
		drawItemPopup(state, ui)
	end
	local page = ui.pages.Inventory
	if not page.Visible and w.drawnOnce then
		return
	end
	w.drawnOnce = true
	local colors = ui.colors

	-- Header.
	local pieces = 0
	for _, item in state.gear do
		pieces += item.count or 1
	end
	w.count.Text = `\u{1F392}  Items {Format.short(pieces)}`
	w.warband.Text = `\u{1F465}  Warband {state.stats.crewSize}  >`

	-- Tabs and drop-down.
	for key, part in w.tabs do
		local on = key == tab
		part.button.BackgroundColor3 = if on then Color3.fromRGB(70, 56, 24) else Color3.fromRGB(40, 34, 28)
		part.button.TextColor3 = if on then colors.gold else colors.dim
		part.stroke.Transparency = if on then 0 else 1
	end
	local rarity = GameConfig.Rarities[rarityRank]
	w.drop.Text = if rarity then `{string.upper(rarity.id)}    ` else "ALL RARITIES    "
	w.drop.TextColor3 = if rarity then rarity.color else colors.text
	local itemTab = tab == "All" or tab == "Weapon" or tab == "Armor" or tab == "Mount"
	w.drop.Visible = itemTab

	-- Sections.
	local ChestShelf = require(script.Parent:WaitForChild("ChestShelf"))
	local shelf = ChestShelf.section
	local found = 0
	w.sets.Visible = tab == "Sets"
	w.trophies.Visible = tab == "Trophies"
	if itemTab then
		found = drawItems(state, ui)
	else
		w.grid.Visible = false
		w.more.Visible = false
	end
	if shelf then
		shelf.Visible = tab == "Chests" and (ChestShelf.total or 0) > 0
	end
	if tab == "Chests" then
		found = ChestShelf.total or 0
	elseif tab == "Sets" then
		drawSets(state, ui)
		found = #GameConfig.GearSets
	elseif tab == "Trophies" then
		drawTrophies(state, ui)
		found = #GameConfig.Trophies
	end
	w.empty.Visible = found == 0
	local word = EMPTY_WORDS[tab] or "items"
	w.empty.Text = if search ~= "" and itemTab
		then `Nothing matches "{search}"`
		elseif rarityRank > 0 and itemTab then `You have no {rarity and rarity.id or ""} {word} in your inventory`
		else `You have no {word} in your inventory`
end

return InventoryPage
