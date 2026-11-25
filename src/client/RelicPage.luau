-- Relic Hall page (your collection): put gear on display for flat attack
-- and defense. Copies of the same item stack, and more copies reach higher
-- tiers. Pieces can be put in or taken out one at a time or X at a time.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local RelicConfig = require(Shared:WaitForChild("RelicConfig"))
local Format = require(Shared:WaitForChild("Format"))

local RelicPage = {}

local summary, autoButton
local emptyNote
local rows = {}
local latest = nil
local page

-- Spare (unworn) copies of each item key in the armory.
local function spareByKey(state)
	local spare = {}
	for _, item in state.gear do
		if item.wornBy == nil then
			local key = RelicConfig.getKey(item)
			local entry = spare[key]
			if not entry then
				entry = { name = item.name, rarity = item.rarity, slot = item.slot, set = item.set, count = 0 }
				spare[key] = entry
			end
			entry.count += 1
		end
	end
	return spare
end

local function makeItemRow(ui)
	local colors = ui.colors
	local frame = ui.makeFrame(page, UDim2.new(1, -10, 0, 62), UDim2.fromOffset(0, 0), colors.row)
	frame.LayoutOrder = ui.nextOrder()
	ui.addCorner(frame, 6)
	ui.addStroke(frame)
	local info = ui.makeText(frame, UDim2.new(1, -210, 1, -8), UDim2.fromOffset(10, 4), colors.text, 13)
	info.RichText = true
	local row = { frame = frame, info = info, key = nil }
	local function button(text: string, x: number, y: number)
		local b = ui.makeButton(frame, UDim2.fromOffset(92, 25), UDim2.new(1, x, 0, y), colors.buy)
		b.TextSize = 12
		b.Text = text
		return b
	end
	row.deposit = button("Deposit", -196, 5)
	row.depositMany = button("Deposit X", -100, 5)
	row.withdraw = button("Withdraw", -196, 32)
	row.withdrawMany = button("Withdraw X", -100, 32)

	row.deposit.Activated:Connect(function()
		if row.key then
			ui.send("RelicDepositMany", `1:{row.key}`)
		end
	end)
	row.withdraw.Activated:Connect(function()
		if row.key then
			ui.send("RelicWithdraw", `1:{row.key}`)
		end
	end)
	row.depositMany.Activated:Connect(function()
		local key = row.key
		local spare = key and latest and spareByKey(latest)[key]
		if spare then
			ui.askAmount({
				title = "Deposit",
				note = `<b>{spare.rarity} {spare.name}</b>: {spare.count} spare in your armory.`,
				max = spare.count,
				confirm = "Deposit",
				onConfirm = function(amount)
					ui.send("RelicDepositMany", `{amount}:{key}`)
				end,
			})
		end
	end)
	row.withdrawMany.Activated:Connect(function()
		local key = row.key
		local held = key and latest and latest.relics.items[key]
		if held then
			local room = latest.maxGear - #latest.gear
			ui.askAmount({
				title = "Withdraw",
				note = `<b>{held.rarity} {held.name}</b>: {held.count} in the hall, room for {math.max(0, room)} in your armory.`,
				max = math.max(1, math.min(held.count, room)),
				confirm = "Withdraw",
				onConfirm = function(amount)
					ui.send("RelicWithdraw", `{amount}:{key}`)
				end,
			})
		end
	end)
	return row
end

function RelicPage.build(ui)
	page = ui.pages["Relic Hall"]
	summary, autoButton = ui.makeRow(page, ui.nextOrder(), 96, true)
	summary.RichText = true
	autoButton.Activated:Connect(function()
		if latest then
			ui.send("RelicAuto", if latest.relics.auto then "off" else "on")
		end
	end)

	local tiers = {}
	for index, tier in RelicConfig.Tiers do
		table.insert(tiers, `T{index}: {Format.short(tier.copies)} = x{tier.multiplier}`)
	end
	local rarities = {}
	for _, rarity in GameConfig.Rarities do
		table.insert(rarities, `{rarity.id} {RelicConfig.RarityStat[rarity.id] or 1}`)
	end
	local tierNote = ui.makeRow(page, ui.nextOrder(), 50, false)
	tierNote.TextSize = 12
	tierNote.TextColor3 = ui.colors.dim
	tierNote.Text = `Copies of one item: {table.concat(tiers, ", ")}\nBonus per item at x1: {table.concat(rarities, ", ")}`

	ui.makeHeading(page, ui.nextOrder(), "Items (rarest first)")
	emptyNote = ui.makeRow(page, ui.nextOrder(), 34, false)
	emptyNote.TextColor3 = ui.colors.dim
	emptyNote.Text = "No gear yet. Spare gear from the Market, quests and foes can be put here."
end

function RelicPage.draw(state, ui)
	latest = state
	local colors = ui.colors
	local relics = state.relics
	local bonus = state.relicBonus
	summary.Text = `<b>{Format.short(relics.count)} pieces in the hall</b>   |   `
		.. `<font color="#9FD49A">+{Format.short(bonus)} attack and +{Format.short(bonus)} defense</font>\n`
		.. "Copies of the same item (same name and rarity) stack. More copies reach higher tiers, and each tier multiplies that item's bonus. You can take pieces back out any time.\n"
		.. (if relics.auto then "<b>Auto deposit is on:</b> new gear nobody puts on goes straight here." else "Auto deposit puts every spare piece here, and new gear nobody puts on.")
	ui.setButton(autoButton, if relics.auto then "Auto deposit\nON" else "Auto deposit\nOFF", true, if relics.auto then colors.claim else colors.selected)

	-- Every item that is spare in the armory or held in the hall.
	local spare = spareByKey(state)
	local keys = {}
	local seen = {}
	for key in spare do
		table.insert(keys, key)
		seen[key] = true
	end
	for key in relics.items do
		if not seen[key] then
			table.insert(keys, key)
		end
	end
	local function describe(key)
		return relics.items[key] or spare[key]
	end
	table.sort(keys, function(a, b)
		local itemA, itemB = describe(a), describe(b)
		local rankA, rankB = GameConfig.getRarityRank(itemA.rarity), GameConfig.getRarityRank(itemB.rarity)
		if rankA ~= rankB then
			return rankA > rankB
		end
		return itemA.name < itemB.name
	end)

	emptyNote.Parent.Visible = #keys == 0
	local room = state.maxGear - #state.gear
	for index, key in keys do
		local row = rows[index]
		if not row then
			row = makeItemRow(ui)
			rows[index] = row
		end
		row.key = key
		row.frame.Visible = true
		local item = describe(key)
		local held = relics.items[key]
		local heldCount = if held then held.count else 0
		local spareCount = if spare[key] then spare[key].count else 0
		local tier = RelicConfig.getTier(heldCount)
		local nextTier = RelicConfig.Tiers[tier + 1]
		local itemBonus = RelicConfig.getItemBonus(item.rarity, heldCount)
		local tierText = if tier > 0 then `Tier {tier}: +{Format.short(itemBonus)} atk/def` else "Not in the hall yet"
		local nextText = if nextTier then `   |   next tier at {Format.short(nextTier.copies)}` else "   |   top tier"
		local setText = if item.set then `  <font color="#9FD49A">[set]</font>` else ""
		row.info.Text = `{ui.rarityName(item)}  ({string.lower(item.slot)}){setText}\n`
			.. `In hall {Format.short(heldCount)}, spare {spareCount}\n<font color="#B2A690">{tierText}{nextText}</font>`
		ui.setButton(row.deposit, "Deposit", spareCount > 0, colors.buy)
		ui.setButton(row.depositMany, "Deposit X", spareCount > 0, colors.buy)
		ui.setButton(row.withdraw, "Withdraw", heldCount > 0 and room > 0, colors.selected)
		ui.setButton(row.withdrawMany, "Withdraw X", heldCount > 0 and room > 0, colors.selected)
	end
	for index = #keys + 1, #rows do
		rows[index].frame.Visible = false
		rows[index].key = nil
	end
end

return RelicPage
