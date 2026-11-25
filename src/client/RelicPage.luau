-- Relic Hall: the collection. Every piece of gear the game has (each name
-- in each rarity) is a card, found or not. Deposit spare copies to add
-- their flat attack and defense; copies stack and reach bonus tiers
-- (x1, x10, x100...). Press a card for Deposit / Withdraw, one or X at a
-- time. Nothing goes in by itself: you choose, or use Deposit all.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local RelicConfig = require(Shared:WaitForChild("RelicConfig"))
local Format = require(Shared:WaitForChild("Format"))

local RelicPage = {}

local TABS = {
	{ id = "All", label = "ALL" },
	{ id = "Weapon", label = "WEAPONS" },
	{ id = "Armor", label = "ARMOR" },
	{ id = "Mount", label = "MOUNTS" },
	{ id = "Set", label = "SET PIECES" },
}

local page
local catalog = {} -- every collectable item: { key, name, slot, rarity, rank, set, source, obtainable }
local cards = {} -- [key] = card widgets
local header = {}
local tabButtons = {}
local chosenTab = "All"
local chosenRarity = 0 -- 0 = every rarity, else a rarity index
local search = ""
local openMenu = nil -- the card whose Deposit/Withdraw menu is open
local latest = nil

---------------------------------------------------------------------------
-- The catalog
---------------------------------------------------------------------------

local function buildCatalog()
	local rarities = {}
	for index, rarity in GameConfig.Rarities do
		-- Divine is for recruits only; gear tops out at Mythic.
		if rarity.chance > 0 then
			rarities[index] = rarity
		end
	end
	local function add(name, slot, set, source, minRank)
		for rank, rarity in rarities do
			table.insert(catalog, {
				key = `{name}|{rarity.id}`,
				name = name,
				slot = slot,
				rarity = rarity.id,
				rank = rank,
				set = set,
				source = if rank >= minRank then source else "NOT OBTAINABLE",
			})
		end
	end
	-- Market, chest and Royal Coffer items (Royal Coffers start at Rare).
	local lowest = { market = 1, chest = 1, premium = GameConfig.getRarityRank("Rare") }
	for _, poolId in GameConfig.GearPoolOrder do
		local pool = GameConfig.GearPools[poolId]
		for _, slot in GameConfig.GearSlots do
			for _, name in pool.items[slot].names do
				add(name, slot, nil, pool.label, lowest[poolId])
			end
		end
	end
	for _, set in GameConfig.GearSets do
		local house = nil
		for _, candidate in GameConfig.Houses do
			if candidate.id == set.house then
				house = candidate
			end
		end
		local minRank = math.max(1, GameConfig.getRarityRank(house and house.chest or "Common") - 1)
		local source = string.upper(house and house.name or "Foes")
		for _, slot in GameConfig.GearSlots do
			add(set.pieces[slot], slot, set.id, source, minRank)
		end
	end
	table.sort(catalog, function(a, b)
		if a.rank ~= b.rank then
			return a.rank > b.rank
		end
		return a.name < b.name
	end)
end

-- Spare (unworn) copies of each item key in the armory.
local function spareByKey(state)
	local spare = {}
	for _, item in state.gear do
		if item.wornBy == nil then
			local key = RelicConfig.getKey(item)
			spare[key] = (spare[key] or 0) + (item.count or 1)
		end
	end
	return spare
end

local function filterId(): string
	local rarity = GameConfig.Rarities[chosenRarity]
	return `{chosenTab}:{if rarity then rarity.id else "All"}`
end

local function shows(entry): boolean
	if chosenTab == "Set" then
		if not entry.set then
			return false
		end
	elseif chosenTab ~= "All" and (entry.slot ~= chosenTab or entry.set) then
		return false
	end
	if chosenRarity > 0 and entry.rank ~= chosenRarity then
		return false
	end
	if search ~= "" and not string.find(string.lower(entry.name), search, 1, true) then
		return false
	end
	return true
end

---------------------------------------------------------------------------
-- Cards
---------------------------------------------------------------------------

local function tag(ui, parent, text: string, color: Color3, position: UDim2): TextLabel
	local label = ui.makeText(parent, UDim2.fromOffset(0, 18), position, color, 11)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.BackgroundTransparency = 0
	label.BackgroundColor3 = Color3.fromRGB(28, 22, 17)
	label.Font = Enum.Font.GothamBold
	label.TextWrapped = false
	label.Text = text
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)
	padding.Parent = label
	ui.addCorner(label, 3)
	return label
end

local function askAmount(ui, entry, depositing: boolean)
	local state = latest
	if not state then
		return
	end
	local held = state.relics.items[entry.key]
	local heldCount = if held then held.count else 0
	local spare = spareByKey(state)[entry.key] or 0
	local most = if depositing then spare else heldCount
	if most <= 0 then
		return
	end
	ui.askAmount({
		title = if depositing then "Deposit to the hall" else "Withdraw from the hall",
		note = `<b>{entry.rarity} {entry.name}</b>: {if depositing then `{spare} spare in your armory` else `{heldCount} in the hall`}.`,
		max = most,
		confirm = if depositing then "Deposit" else "Withdraw",
		preview = function(amount)
			local after = if depositing then heldCount + amount else heldCount - amount
			local bonus = RelicConfig.getItemBonus(entry.rarity, after)
			return `Hall after: x{after} (+{Format.short(bonus)} attack and defense)`
		end,
		onConfirm = function(amount)
			ui.send(if depositing then "RelicDepositMany" else "RelicWithdraw", `{amount}:{entry.key}`)
		end,
	})
end

local function makeCard(ui, grid, entry, order: number)
	local colors = ui.colors
	local art = ui.art
	local rarity = GameConfig.Rarities[entry.rank]

	local card = Instance.new("TextButton")
	card.AutoButtonColor = false
	card.Text = ""
	card.Size = UDim2.fromOffset(100, 100)
	card.BackgroundColor3 = colors.row
	card.LayoutOrder = order
	card.Parent = grid
	ui.addCorner(card, 8)
	art.card(card)
	local edge = art.stroke(card, colors.dim, 1.5, 0.6)

	-- Picture: the slot's icon on the rarity color.
	local picture = ui.makeFrame(card, UDim2.fromOffset(84, 84), UDim2.fromOffset(8, 8), Color3.fromRGB(30, 24, 20))
	ui.addCorner(picture, 6)
	art.gloss(picture, 0.55, 0.2)
	art.stroke(picture, rarity.color, 1.5, 0.2)
	local icon = ui.makeFrame(picture, UDim2.new(1, -6, 1, -6), UDim2.fromOffset(3, 3), rarity.color)
	icon.BackgroundTransparency = 1
	local unknown = ui.makeText(picture, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1), 40)
	unknown.Font = Enum.Font.GothamBlack
	unknown.TextXAlignment = Enum.TextXAlignment.Center
	unknown.Text = "?"
	unknown.ZIndex = picture.ZIndex + 100 -- above the item's silhouette
	unknown.TextStrokeTransparency = 0.4
	local count = ui.makeText(picture, UDim2.fromOffset(0, 20), UDim2.new(1, 4, 1, 4), Color3.new(1, 1, 1), 14)
	count.AnchorPoint = Vector2.new(1, 1)
	count.AutomaticSize = Enum.AutomaticSize.X
	count.Font = Enum.Font.GothamBlack
	count.TextStrokeTransparency = 0.2
	count.TextWrapped = false
	count.ZIndex = picture.ZIndex + 100

	local name = ui.makeText(card, UDim2.new(1, -108, 0, 20), UDim2.fromOffset(100, 8), colors.text, 15)
	name.Font = Enum.Font.GothamBold
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.TextWrapped = false
	name.Text = entry.name
	tag(ui, card, string.upper(if entry.set then entry.slot .. " \u{00B7} set" else entry.slot), colors.dim, UDim2.fromOffset(100, 31))
	local bonusText = ui.makeText(card, UDim2.new(1, -108, 0, 28), UDim2.fromOffset(100, 52), colors.dim, 11)
	bonusText.RichText = true
	local status = ui.makeText(card, UDim2.new(1, -108, 0, 16), UDim2.fromOffset(100, 80), colors.dim, 12)
	status.RichText = true
	status.TextWrapped = false
	status.TextTruncate = Enum.TextTruncate.AtEnd

	-- Progress to the next bonus tier.
	local tierBack = ui.makeFrame(card, UDim2.new(1, -108, 0, 6), UDim2.fromOffset(100, 100), Color3.fromRGB(14, 10, 8))
	ui.addCorner(tierBack, 3)
	local tierFill = ui.makeFrame(tierBack, UDim2.fromScale(0, 1), UDim2.fromOffset(0, 0), rarity.color)
	ui.addCorner(tierFill, 3)
	art.bar(tierBack, tierFill)

	-- The item's own fixed stats and how they are split.
	local attack, defense = GameConfig.getGearStats(entry.slot, entry.name, rarity)
	local share = math.floor(GameConfig.getGearSplit(entry.slot, entry.name) * 100 + 0.5)
	local itemStats = ui.makeText(card, UDim2.new(1, -16, 0, 18), UDim2.fromOffset(8, 112), colors.text, 12)
	itemStats.RichText = true
	itemStats.TextWrapped = false
	itemStats.Text = `<font color="#F08A6A"><b>{attack}</b> ATK</font>   <font color="#7FB4F0"><b>{defense}</b> DEF</font>   <font color="#9A8C7A">({share}% / {100 - share}%)</font>`

	local rarityTag = tag(ui, card, string.upper(rarity.id), rarity.color, UDim2.new(0, 8, 1, -46))
	rarityTag.TextColor3 = rarity.color
	tag(ui, card, entry.source, colors.text, UDim2.new(0, 8, 1, -24))

	-- The menu that opens when the card is pressed.
	local menu = ui.makeFrame(card, UDim2.new(1, -12, 0, 68), UDim2.new(0, 6, 1, -74), Color3.fromRGB(22, 17, 12))
	menu.Visible = false
	menu.ZIndex = 5
	ui.addCorner(menu, 6)
	art.stroke(menu, colors.gold, 1.5, 0)
	local menuButtons = {}
	for index, spec in { { "Deposit", true, false }, { "Deposit X", true, true }, { "Withdraw", false, false }, { "Withdraw X", false, true } } do
		local column = (index - 1) % 2
		local line = math.floor((index - 1) / 2)
		local b = ui.makeButton(menu, UDim2.new(0.5, -6, 0, 28), UDim2.new(column * 0.5, 4, 0, 4 + line * 32), colors.buy)
		b.ZIndex = 6
		b.TextSize = 13
		menuButtons[index] = b
		b.Activated:Connect(function()
			menu.Visible = false
			openMenu = nil
			if spec[3] then
				askAmount(ui, entry, spec[2])
			else
				ui.send(if spec[2] then "RelicDepositMany" else "RelicWithdraw", `1:{entry.key}`)
			end
		end)
	end
	card.Activated:Connect(function()
		if openMenu and openMenu ~= menu then
			openMenu.Visible = false
		end
		menu.Visible = not menu.Visible
		openMenu = if menu.Visible then menu else nil
	end)

	cards[entry.key] = {
		frame = card,
		edge = edge,
		icon = icon,
		unknown = unknown,
		count = count,
		bonusText = bonusText,
		status = status,
		menuButtons = menuButtons,
		rarityColor = rarity.color,
		tierBack = tierBack,
		tierFill = tierFill,
		picture = picture,
	}
end

---------------------------------------------------------------------------
-- Building the page
---------------------------------------------------------------------------

function RelicPage.build(ui)
	page = ui.pages["Relic Hall"]
	local colors = ui.colors
	local art = ui.art
	buildCatalog()

	-- Top strip: search, collected count and the hall's total bonus.
	local top = ui.makeFrame(page, UDim2.new(1, -10, 0, 46), UDim2.fromOffset(0, 0), Color3.fromRGB(30, 23, 17))
	top.LayoutOrder = ui.nextOrder()
	ui.addCorner(top, 6)
	art.stroke(top, colors.gold, 1, 0.5)
	local box = ui.makeAmountBox(top, UDim2.new(0.3, -12, 0, 32), UDim2.fromOffset(8, 7), "\u{1F50D} Search items")
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextSize = 14
	local boxPadding = Instance.new("UIPadding")
	boxPadding.PaddingLeft = UDim.new(0, 8)
	boxPadding.Parent = box
	box:GetPropertyChangedSignal("Text"):Connect(function()
		search = string.lower(box.Text)
		RelicPage.filter()
	end)
	local collected = ui.makeText(top, UDim2.new(0.18, 0, 1, 0), UDim2.new(0.3, 4, 0, 0), colors.text, 13)
	collected.Font = Enum.Font.GothamBold
	collected.Text = "\u{2B50} COLLECTED"
	local barBack = ui.makeFrame(top, UDim2.new(0.12, 0, 0, 10), UDim2.new(0.46, 0, 0.5, -5), Color3.fromRGB(14, 10, 8))
	ui.addCorner(barBack, 4)
	local barFill = ui.makeFrame(barBack, UDim2.fromScale(0, 1), UDim2.fromOffset(0, 0), colors.gold)
	ui.addCorner(barFill, 4)
	art.bar(barBack, barFill)
	header.barFill = barFill
	local collectedCount = ui.makeText(top, UDim2.new(0.1, 0, 1, 0), UDim2.new(0.59, 0, 0, 0), colors.text, 14)
	collectedCount.Font = Enum.Font.GothamBold
	header.count = collectedCount
	local bonus = ui.makeText(top, UDim2.new(0.31, -10, 1, 0), UDim2.new(0.69, 0, 0, 0), colors.text, 13)
	bonus.Font = Enum.Font.GothamBold
	bonus.RichText = true
	bonus.TextXAlignment = Enum.TextXAlignment.Right
	header.bonus = bonus

	-- Filter strip: type tabs, rarity, deposit all and withdraw all.
	local strip = ui.makeFrame(page, UDim2.new(1, -10, 0, 38), UDim2.fromOffset(0, 0), colors.panel)
	strip.LayoutOrder = ui.nextOrder()
	strip.BackgroundTransparency = 1
	local tabWidth = 0.1
	for index, tab in TABS do
		local b = ui.makeButton(strip, UDim2.new(tabWidth, -4, 1, -4), UDim2.new(tabWidth * (index - 1), 0, 0, 2), colors.row)
		b.TextSize = 12
		tabButtons[tab.id] = b
		b.Activated:Connect(function()
			chosenTab = tab.id
			RelicPage.filter()
		end)
	end
	local rarityButton = ui.makeButton(strip, UDim2.new(0.16, -4, 1, -4), UDim2.new(0.5, 0, 0, 2), colors.row)
	rarityButton.TextSize = 13
	header.rarityButton = rarityButton
	rarityButton.Activated:Connect(function()
		chosenRarity = (chosenRarity + 1) % #GameConfig.Rarities -- skips Divine
		RelicPage.filter()
	end)
	local depositAll = ui.makeButton(strip, UDim2.new(0.17, -4, 1, -4), UDim2.new(0.66, 0, 0, 2), colors.gold)
	depositAll.TextSize = 12
	ui.setButton(depositAll, "DEPOSIT ALL", true, colors.gold)
	depositAll.Activated:Connect(function()
		ui.send("RelicDepositAll", filterId())
	end)
	local withdrawAll = ui.makeButton(strip, UDim2.new(0.17, -4, 1, -4), UDim2.new(0.83, 0, 0, 2), colors.row)
	withdrawAll.TextSize = 12
	art.stroke(withdrawAll, colors.gold, 1.5, 0)
	ui.setButton(withdrawAll, "WITHDRAW ALL", true, colors.row)
	withdrawAll.Activated:Connect(function()
		ui.send("RelicWithdrawAll", filterId())
	end)

	local note = ui.makeText(page, UDim2.new(1, -10, 0, 30), UDim2.fromOffset(0, 0), colors.dim, 12)
	note.LayoutOrder = ui.nextOrder()
	local tiers = {}
	for _, tier in RelicConfig.Tiers do
		table.insert(tiers, `{Format.short(tier.copies)} copies = x{tier.multiplier}`)
	end
	note.Text = `Deposit spare gear for lasting attack and defense. Bonus tiers: {table.concat(tiers, ", ")}. Press a card to deposit or withdraw.`

	local grid = ui.makeGrid(page, ui.nextOrder(), 190, 3)
	for index, entry in catalog do
		makeCard(ui, grid, entry, index)
	end
	RelicPage.filter()
end

-- Shows only the cards that match the tab, rarity and search.
function RelicPage.filter()
	local ui = RelicPage.ui
	for _, tab in TABS do
		local b = tabButtons[tab.id]
		local on = tab.id == chosenTab
		if ui then
			ui.setButton(b, tab.label, true, if on then ui.colors.gold else ui.colors.row)
		else
			b.Text = tab.label
		end
	end
	local rarity = GameConfig.Rarities[chosenRarity]
	header.rarityButton.Text = (if rarity then string.upper(rarity.id) else "ALL RARITIES") .. "  \u{25BE}"
	if rarity then
		header.rarityButton.TextColor3 = rarity.color
	end
	for _, entry in catalog do
		cards[entry.key].frame.Visible = shows(entry)
	end
	-- Pictures are drawn only for shown cards, so draw the newly shown ones.
	if latest and RelicPage.ui then
		task.defer(RelicPage.draw, latest, RelicPage.ui)
	end
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

function RelicPage.draw(state, ui)
	latest = state
	if not RelicPage.ui then
		RelicPage.ui = ui
		RelicPage.filter()
	end
	-- 180+ cards: only redraw them while the page is open.
	if not page.Visible then
		return
	end
	local colors = ui.colors
	local relics = state.relics
	local seen = relics.seen or {}
	local spare = spareByKey(state)
	local room = math.huge -- the armory has no limit

	local collectedCount = 0
	for _, entry in catalog do
		local held = relics.items[entry.key]
		local heldCount = if held then held.count else 0
		if heldCount > 0 then
			collectedCount += 1
		end
		local spareCount = spare[entry.key] or 0
		local found = heldCount > 0 or spareCount > 0 or seen[entry.key] == true
		local card = cards[entry.key]

		-- Drawn on first view (and again once discovered), as a dark
		-- silhouette until the item has been found.
		if card.frame.Visible then
			ui.itemArt.set(card.icon, { slot = entry.slot, name = entry.name, rarity = entry.rarity, set = entry.set }, not found)
		end
		card.unknown.Visible = not found
		card.count.Text = if heldCount > 0 then `x{Format.short(heldCount)}` else ""
		card.edge.Color = if heldCount > 0 then card.rarityColor else colors.dim
		card.edge.Transparency = if heldCount > 0 then 0.1 else 0.6

		local tier = RelicConfig.getTier(heldCount)
		local nextTier = RelicConfig.Tiers[tier + 1]
		if heldCount > 0 then
			local now = RelicConfig.getItemBonus(entry.rarity, heldCount)
			card.bonusText.Text = `<font color="#9FD49A">+{Format.short(now)} Attack and Defense</font>`
				.. (if nextTier then `\nNext bonus at x{Format.short(nextTier.copies)}` else "\nTop tier")
		else
			card.bonusText.Text = `Deposit for +{Format.short(RelicConfig.getItemBonus(entry.rarity, 1))} Attack and Defense`
		end
		if not found then
			card.status.Text = "Not discovered"
		elseif spareCount > 0 then
			card.status.Text = `<font color="#F0C450">{spareCount} spare to deposit</font>`
		elseif heldCount > 0 then
			card.status.Text = "In the hall"
		else
			card.status.Text = "Discovered"
		end
		card.tierBack.Visible = heldCount > 0
		if heldCount > 0 then
			local share = 1
			if nextTier then
				local from = RelicConfig.Tiers[tier].copies
				share = (heldCount - from) / (nextTier.copies - from)
			end
			card.tierFill.Size = UDim2.fromScale(math.clamp(share, 0, 1), 1)
		end

		local buttons = card.menuButtons
		ui.setButton(buttons[1], "Deposit", spareCount > 0, colors.buy)
		ui.setButton(buttons[2], "Deposit X", spareCount > 0, colors.buy)
		ui.setButton(buttons[3], "Withdraw", heldCount > 0 and room > 0, colors.selected)
		ui.setButton(buttons[4], "Withdraw X", heldCount > 0 and room > 0, colors.selected)
	end

	header.count.Text = `{collectedCount} / {#catalog}`
	header.barFill.Size = UDim2.fromScale(collectedCount / math.max(1, #catalog), 1)
	local total = state.relicBonus
	header.bonus.Text = "\u{2694}\u{FE0F} ATTACK " .. `<font color="#9FD49A">+{Format.short(total)}</font>     ` .. "\u{1F6E1}\u{FE0F} DEFENSE " .. `<font color="#9FD49A">+{Format.short(total)}</font>`
end

return RelicPage
