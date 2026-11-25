-- "How many?" popup: type an amount or use the - and + buttons, then
-- Confirm or Cancel. Used by the Barracks (Train X) and the Relic Hall
-- (deposit X, withdraw X). Other modules call ui.askAmount(options):
--   title      popup title
--   note       a line about what the amount is for
--   max        the most allowed (at least 1)
--   confirm    text on the Confirm button, e.g. "Train"
--   onConfirm  function(amount) called with the chosen amount

local AmountPopup = {}

local note, box
local current = { max = 1, amount = 1, onConfirm = nil }

local function clamp(value: number): number
	return math.clamp(math.floor(value), 1, math.max(1, current.max))
end

local function show()
	box.Text = tostring(current.amount)
end

function AmountPopup.build(ui)
	local page = ui.pages.Amount
	local colors = ui.colors

	note = ui.makeRow(page, ui.nextOrder(), 54, false)
	note.RichText = true

	local controls = ui.makeFrame(page, UDim2.new(1, -10, 0, 50), UDim2.fromOffset(0, 0), colors.row)
	controls.LayoutOrder = ui.nextOrder()
	ui.addCorner(controls, 6)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 5)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = controls

	local function stepButton(order: number, text: string, change: number?)
		local button = ui.makeButton(controls, UDim2.fromOffset(if change then 44 else 56, 38), UDim2.fromOffset(0, 0), colors.selected)
		button.LayoutOrder = order
		ui.setButton(button, text, true, colors.selected)
		button.Activated:Connect(function()
			current.amount = if change then clamp(current.amount + change) else current.max
			show()
		end)
	end
	stepButton(1, "-10", -10)
	stepButton(2, "-1", -1)
	box = ui.makeAmountBox(controls, UDim2.fromOffset(110, 38), UDim2.fromOffset(0, 0), "Amount")
	box.LayoutOrder = 3
	box.FocusLost:Connect(function()
		local digits = string.gsub(box.Text, "%D", "")
		current.amount = clamp(tonumber(string.sub(digits, 1, 7)) or 1)
		show()
	end)
	stepButton(4, "+1", 1)
	stepButton(5, "+10", 10)
	stepButton(6, "Max", nil)

	local actions = ui.makeFrame(page, UDim2.new(1, -10, 0, 46), UDim2.fromOffset(0, 0), colors.panel)
	actions.LayoutOrder = ui.nextOrder()
	actions.BackgroundTransparency = 1
	local cancel = ui.makeButton(actions, UDim2.new(0.5, -4, 1, 0), UDim2.fromOffset(0, 0), colors.selected)
	ui.setButton(cancel, "Cancel", true, colors.selected)
	cancel.Activated:Connect(function()
		ui.closeModal()
	end)
	local confirm = ui.makeButton(actions, UDim2.new(0.5, -4, 1, 0), UDim2.new(0.5, 4, 0, 0), colors.buy)
	current.confirmButton = confirm
	confirm.Activated:Connect(function()
		-- Read the box too, in case it still has focus.
		local digits = string.gsub(box.Text, "%D", "")
		current.amount = clamp(tonumber(string.sub(digits, 1, 7)) or current.amount)
		local callback = current.onConfirm
		ui.closeModal()
		if callback then
			callback(current.amount)
		end
	end)

	function ui.askAmount(options)
		current.max = math.max(1, math.floor(options.max or 1))
		current.amount = 1
		current.onConfirm = options.onConfirm
		note.Text = `{options.note or ""}\n<font color="#B2A690">Up to {current.max}.</font>`
		ui.setButton(confirm, options.confirm or "Confirm", true, colors.buy)
		show()
		ui.openModal("Amount", options.title)
	end
end

function AmountPopup.draw() end

return AmountPopup
