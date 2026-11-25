-- "Train soldier" popup, opened from a warband card's TRAIN button:
-- the soldier, their rank now and after, the gold cost and how long it
-- takes. While a soldier trains, the popup shows the time left and a Stop
-- button (stopping early gives no refund).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Format = require(Shared:WaitForChild("Format"))

local TrainPopup = {}

local widgets = {}
local shownSlot = nil
local latest = nil

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local hours = seconds // 3600
	local minutes = (seconds % 3600) // 60
	if hours > 0 then
		return if minutes > 0 then `{hours} h {minutes} m` else `{hours} h`
	elseif minutes > 0 then
		return `{minutes} m {seconds % 60} s`
	end
	return `{seconds} s`
end

function TrainPopup.build(ui)
	local page = ui.pages.Train
	local colors = ui.colors
	local art = ui.art

	local top = ui.makeFrame(page, UDim2.new(1, -10, 0, 150), UDim2.fromOffset(0, 0), colors.panel)
	top.BackgroundTransparency = 1
	top.LayoutOrder = 1
	local portrait = ui.makeFrame(top, UDim2.fromOffset(90, 90), UDim2.new(0.5, -45, 0, 0), Color3.fromRGB(26, 20, 16))
	ui.addCorner(portrait, 8)
	widgets.portraitStroke = art.stroke(portrait, colors.dim, 2, 0)
	widgets.glyph = art.icon(portrait, "", 56, UDim2.fromScale(0.5, 0.5))
	widgets.glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	widgets.name = ui.makeText(top, UDim2.new(1, 0, 0, 26), UDim2.fromOffset(0, 94), colors.text, 20)
	widgets.name.Font = Enum.Font.GothamBold
	widgets.name.TextXAlignment = Enum.TextXAlignment.Center
	widgets.ranks = ui.makeText(top, UDim2.new(1, 0, 0, 28), UDim2.fromOffset(0, 120), colors.gold, 22)
	widgets.ranks.Font = Enum.Font.GothamBlack
	widgets.ranks.TextXAlignment = Enum.TextXAlignment.Center

	local boxes = ui.makeFrame(page, UDim2.new(1, -10, 0, 70), UDim2.fromOffset(0, 0), colors.panel)
	boxes.BackgroundTransparency = 1
	boxes.LayoutOrder = 2
	local function box(index: number, title: string)
		local frame = ui.makeFrame(boxes, UDim2.new(0.5, -4, 1, 0), UDim2.new((index - 1) * 0.5, (index - 1) * 4, 0, 0), Color3.fromRGB(22, 18, 14))
		ui.addCorner(frame, 6)
		local label = ui.makeText(frame, UDim2.new(1, 0, 0, 22), UDim2.fromOffset(0, 6), colors.dim, 13)
		label.Font = Enum.Font.GothamBold
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.Text = title
		local value = ui.makeText(frame, UDim2.new(1, 0, 0, 34), UDim2.fromOffset(0, 28), colors.text, 24)
		value.Font = Enum.Font.GothamBlack
		value.TextXAlignment = Enum.TextXAlignment.Center
		return value
	end
	widgets.cost = box(1, "COST")
	widgets.time = box(2, "TIME")
	widgets.time.TextColor3 = Color3.fromRGB(127, 180, 240)

	widgets.note = ui.makeText(page, UDim2.new(1, -10, 0, 24), UDim2.fromOffset(0, 0), colors.dim, 13)
	widgets.note.LayoutOrder = 3
	widgets.note.TextXAlignment = Enum.TextXAlignment.Center

	local buttons = ui.makeFrame(page, UDim2.new(1, -10, 0, 50), UDim2.fromOffset(0, 0), colors.panel)
	buttons.BackgroundTransparency = 1
	buttons.LayoutOrder = 4
	local cancel = ui.makeButton(buttons, UDim2.new(0.5, -4, 1, 0), UDim2.fromOffset(0, 0), colors.selected)
	cancel.TextSize = 18
	ui.setButton(cancel, "CANCEL", true, colors.selected)
	widgets.confirm = ui.makeButton(buttons, UDim2.new(0.5, -4, 1, 0), UDim2.new(0.5, 4, 0, 0), colors.gold)
	widgets.confirm.TextSize = 18
	cancel.Activated:Connect(function()
		ui.closeModal()
	end)
	widgets.confirm.Activated:Connect(function()
		if not shownSlot or not latest then
			return
		end
		local soldier = latest.crew[shownSlot]
		if soldier and soldier.trainLeft then
			ui.send("TrainStop", tostring(shownSlot))
		else
			ui.send("Train", tostring(shownSlot))
		end
		ui.closeModal()
	end)

	function ui.offerTrain(slot: number)
		shownSlot = slot
		TrainPopup.draw(latest, ui)
		ui.openModal("Train", "Train soldier")
	end
end

function TrainPopup.draw(state, ui)
	latest = state
	if not state or not shownSlot then
		return
	end
	local soldier = shownSlot and state.crew[shownSlot]
	if not soldier then
		return
	end
	local colors = ui.colors
	local rarity = GameConfig.getRarity(soldier.rarity)
	widgets.portraitStroke.Color = rarity.color
	widgets.glyph.Text = ({
		Militia = "\u{1F6E1}\u{FE0F}",
		Archer = "\u{1F3F9}",
		Knight = "\u{2694}\u{FE0F}",
		["Battle Mage"] = "\u{1F52E}",
		Ranger = "\u{1F332}",
	})[soldier.class] or "\u{1F482}"
	widgets.name.Text = soldier.name
	widgets.name.TextColor3 = rarity.color
	local full = soldier.train >= GameConfig.MaxTrainRank
	widgets.ranks.Text = if full then `+{soldier.train} (fully trained)` else "+" .. soldier.train .. "  \u{27A1}  +" .. (soldier.train + 1)
	widgets.cost.Text = Format.short(soldier.trainCost or 0) .. " gold"
	widgets.cost.TextColor3 = if (state.gold or 0) >= (soldier.trainCost or 0) then colors.gold else Color3.fromRGB(220, 90, 80)
	if soldier.trainLeft then
		widgets.time.Text = clock(soldier.trainLeft) .. " left"
		widgets.note.Text = "Training now. Stopping early gives no refund."
		ui.setButton(widgets.confirm, "STOP", true, colors.action)
	else
		widgets.time.Text = clock(soldier.trainSeconds or 0)
		widgets.note.Text = "Each rank adds +1% attack and defense (max +10). Stopping early gives no refund."
		local canTrain = not full and (state.gold or 0) >= (soldier.trainCost or 0)
		ui.setButton(widgets.confirm, if full then "MAXED" else "TRAIN", canTrain, colors.gold)
	end
end

return TrainPopup
