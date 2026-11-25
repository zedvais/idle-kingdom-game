-- Relic Hall page: give spare gear away for good, for lasting attack and
-- defense.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local StoreConfig = require(Shared:WaitForChild("StoreConfig"))
local RelicConfig = require(Shared:WaitForChild("RelicConfig"))
local Format = require(Shared:WaitForChild("Format"))

local RelicPage = {}

local BULK = { "Common", "Uncommon", "Rare", "Epic" }

local summary
local bulkButtons
local emptyNote
local rows = {}

function RelicPage.build(ui)
	local page = ui.pages["Relic Hall"]
	summary = ui.makeRow(page, ui.nextOrder(), 74, false)
	summary.RichText = true

	local labels = {}
	for index, rarity in BULK do
		labels[index] = rarity
	end
	bulkButtons = ui.makeButtonRow(page, ui.nextOrder(), "Give all spare", labels, 120)
	for index, rarity in BULK do
		bulkButtons[index].Activated:Connect(function()
			ui.send("RelicBulk", rarity)
		end)
	end

	ui.makeHeading(page, ui.nextOrder(), "Spare gear (weakest first)")
	emptyNote = ui.makeRow(page, ui.nextOrder(), 34, false)
	emptyNote.TextColor3 = ui.colors.dim
	emptyNote.Text = "No spare gear. Only pieces nobody is wearing can be given."
	for index = 1, GameConfig.MaxGearOwned + StoreConfig.ArmoryExtra do
		local info, button = ui.makeRow(page, ui.nextOrder(), 50, true)
		info.RichText = true
		local entry = { info = info, button = button, uid = nil }
		rows[index] = entry
		button.Activated:Connect(function()
			if entry.uid then
				ui.send("Relic", entry.uid)
			end
		end)
	end
end

function RelicPage.draw(state, ui)
	local colors = ui.colors
	local points = state.relics.points
	local bonus = state.relicBonus
	local capPoints = math.ceil(RelicConfig.MaxBonus / RelicConfig.BonusPerPoint)
	local nextMilestone = nil
	for _, milestone in RelicConfig.Milestones do
		if points < milestone.points then
			nextMilestone = milestone
			break
		end
	end
	local milestoneText = if nextMilestone
		then `Next title: "{nextMilestone.title}" at {nextMilestone.points} points.`
		else "Every Relic Hall title earned."
	local capText = if bonus >= RelicConfig.MaxBonus then " (the most it can give)" else ` (most is +{math.floor(RelicConfig.MaxBonus * 100)}% at {capPoints} points)`
	summary.Text = `<b>{Format.short(points)} relic points</b> from {state.relics.count} pieces   |   `
		.. `<font color="#9FD49A">+{string.format("%.1f", bonus * 100)}% attack and defense</font>{capText}\n`
		.. `Each point adds {RelicConfig.BonusPerPoint * 100}%. Rarer pieces give more points and set pieces count double. Given gear is gone for good.\n`
		.. milestoneText

	local spare = {}
	local spareByRarity = {}
	for _, item in state.gear do
		if item.wornBy == nil then
			table.insert(spare, item)
			if not item.set then
				spareByRarity[item.rarity] = (spareByRarity[item.rarity] or 0) + 1
			end
		end
	end
	for index, rarity in BULK do
		local count = spareByRarity[rarity] or 0
		ui.setButton(bulkButtons[index], `{rarity} ({count})`, count > 0, colors.selected)
	end
	table.sort(spare, function(a, b)
		local aRank, bRank = GameConfig.getRarityRank(a.rarity), GameConfig.getRarityRank(b.rarity)
		if aRank ~= bRank then
			return aRank < bRank
		end
		return a.attack + a.defense < b.attack + b.defense
	end)
	emptyNote.Parent.Visible = #spare == 0
	for index, row in rows do
		local item = spare[index]
		row.uid = if item then item.uid else nil
		row.info.Parent.Visible = item ~= nil
		if item then
			local setText = if item.set then `  <font color="#9FD49A">[set piece]</font>` else ""
			row.info.Text = `{ui.rarityName(item)}  Lv {item.level}  ({string.lower(item.slot)}){setText}\n{ui.statText(item.attack, item.defense)}`
			ui.setButton(row.button, `Give\n+{RelicConfig.getPoints(item)} points`, true, colors.buy)
		end
	end
end

return RelicPage
