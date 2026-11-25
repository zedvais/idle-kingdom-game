-- "Get this pass" popup. Locked auto buttons call ui.offerPass(key) to show
-- what the game pass does, its price, and a Buy button that opens the Roblox
-- purchase prompt (in Studio, test passes are given for free).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local StoreConfig = require(Shared:WaitForChild("StoreConfig"))

local PassPopup = {}

local ICONS = {
	autoquest = "\u{1F4EF}", -- postal horn
	autoroll = "\u{1F482}", -- guard
	autobuy = "\u{2696}\u{FE0F}", -- scales
}

local shown = nil -- the pass key the popup shows
local widgets = {}

function PassPopup.build(ui)
	local page = ui.pages.Pass
	local colors = ui.colors
	local art = ui.art

	local card = ui.makeFrame(page, UDim2.new(1, -10, 0, 150), UDim2.fromOffset(0, 0), colors.row)
	card.LayoutOrder = 1
	ui.addCorner(card, 8)
	art.card(card)
	art.stroke(card, colors.gold, 1.5, 0.3)
	local emblem, glyph = art.emblem(card, "", 64, UDim2.fromOffset(14, 14), colors.selected)
	widgets.glyph = glyph
	local name = ui.makeText(card, UDim2.new(1, -100, 0, 30), UDim2.fromOffset(92, 14), colors.gold, 26)
	name.Font = art.Fonts.title
	widgets.name = name
	local note = ui.makeText(card, UDim2.new(1, -104, 0, 60), UDim2.fromOffset(92, 46), colors.text, 14)
	note.TextYAlignment = Enum.TextYAlignment.Top
	widgets.note = note
	local forever = ui.makeText(card, UDim2.new(1, -24, 0, 18), UDim2.new(0, 14, 1, -28), colors.dim, 12)
	forever.Text = "Game passes are yours forever, on every server."
	emblem.ZIndex = card.ZIndex

	local buttons = ui.makeFrame(page, UDim2.new(1, -10, 0, 54), UDim2.fromOffset(0, 0), colors.panel)
	buttons.BackgroundTransparency = 1
	buttons.LayoutOrder = 2
	local later = ui.makeButton(buttons, UDim2.new(0.4, -4, 1, -8), UDim2.fromOffset(0, 6), colors.selected)
	later.TextSize = 16
	ui.setButton(later, "Maybe later", true, colors.selected)
	local buy = ui.makeButton(buttons, UDim2.new(0.6, -4, 1, -8), UDim2.new(0.4, 4, 0, 6), colors.gold)
	buy.TextSize = 18
	widgets.buy = buy
	art.shine(buy, 2.5)

	later.Activated:Connect(function()
		ui.closeModal()
	end)
	buy.Activated:Connect(function()
		if shown then
			ui.send("Robux", `pass:{shown}`)
			ui.closeModal()
		end
	end)

	function ui.offerPass(key: string)
		local pass = StoreConfig.getPass(key)
		if not pass then
			return
		end
		shown = key
		widgets.glyph.Text = ICONS[key] or art.Icons.Shop
		widgets.name.Text = pass.name
		widgets.note.Text = pass.note
		ui.setButton(widgets.buy, `Buy  {ui.robuxText(pass.price)}`, true, colors.gold)
		ui.openModal("Pass", "Game pass")
	end
end

function PassPopup.draw(_state, _ui) end

return PassPopup
