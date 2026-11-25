-- Profile page: who you are, your all-time numbers, your titles and the
-- promo code box. Built once by Main with the shared helpers in `ui`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local RebirthConfig = require(Shared:WaitForChild("RebirthConfig"))
local Format = require(Shared:WaitForChild("Format"))

local ProfilePage = {}

local MAX_TITLES = 24

-- The numbers shown as tiles: { label, function(state) -> text }.
local function count(key: string)
	return function(state)
		return Format.short(math.floor(state.lifetime[key] or 0))
	end
end
local TILES = {
	{ "Quests done", count("quests") },
	{ "Foes beaten", count("foes") },
	{ "Attacks made", count("attacks") },
	{ "Times knocked down", count("knockdowns") },
	{ "Recruits rolled", count("rolls") },
	{ "Gear bought", count("market") },
	{ "Gold earned", count("goldEarned") },
	{
		"Time played",
		function(state)
			local seconds = math.floor(state.lifetime.playSeconds or 0)
			return `{math.floor(seconds / 3600)}h {math.floor(seconds / 60) % 60}m`
		end,
	},
	{
		"Trophies",
		function(state)
			local earned = 0
			for _ in state.trophies do
				earned += 1
			end
			return `{earned} / {#GameConfig.Trophies}`
		end,
	},
	{
		"Relic points",
		function(state)
			return Format.short(state.relics.points)
		end,
	},
	{
		"Rebirths",
		function(state)
			return tostring(state.rebirth.count)
		end,
	},
	{
		"Codes used",
		count("codes"),
	},
}

local header
local tileValues = {}
local titleCards = {}
local noTitleInfo, noTitleButton

function ProfilePage.build(ui)
	local page = ui.pages.Profile
	local colors = ui.colors

	header = ui.makeRow(page, ui.nextOrder(), 92, false)
	header.RichText = true
	header.TextSize = 15

	ui.makeHeading(page, ui.nextOrder(), "All-time record")
	local grid = ui.makeGrid(page, ui.nextOrder(), 58, 4)
	for index, tile in TILES do
		local card = ui.makeFrame(grid, UDim2.fromOffset(100, 58), UDim2.fromOffset(0, 0), colors.row)
		card.LayoutOrder = index
		ui.addCorner(card, 8)
		ui.addStroke(card)
		local label = ui.makeText(card, UDim2.new(1, -16, 0, 16), UDim2.fromOffset(8, 6), colors.dim, 11)
		label.Font = Enum.Font.GothamBold
		label.Text = string.upper(tile[1])
		local value = ui.makeText(card, UDim2.new(1, -16, 0, 26), UDim2.fromOffset(8, 24), colors.text, 20)
		value.Font = Enum.Font.GothamBold
		tileValues[index] = value
	end

	ui.makeHeading(page, ui.nextOrder(), "Titles")
	noTitleInfo, noTitleButton = ui.makeRow(page, ui.nextOrder(), 44, true)
	noTitleInfo.TextSize = 13
	noTitleButton.Activated:Connect(function()
		ui.send("Title", "")
	end)
	local titleGrid = ui.makeGrid(page, ui.nextOrder(), 84, 4)
	for index = 1, MAX_TITLES do
		local info, button = ui.makeCard(titleGrid)
		info.RichText = true
		local entry = { info = info, button = button, title = nil }
		titleCards[index] = entry
		button.Activated:Connect(function()
			if entry.title then
				ui.send("Title", entry.title)
			end
		end)
	end

	ui.makeHeading(page, ui.nextOrder(), "Promo code")
	local codeRow = ui.makeFrame(page, UDim2.new(1, -10, 0, 52), UDim2.fromOffset(0, 0), colors.row)
	codeRow.LayoutOrder = ui.nextOrder()
	ui.addCorner(codeRow, 6)
	local codeBox = ui.makeAmountBox(codeRow, UDim2.new(1, -140, 1, -12), UDim2.fromOffset(8, 6), "Type a code, then press Redeem")
	local redeem = ui.makeButton(codeRow, UDim2.fromOffset(112, 40), UDim2.new(1, -6, 0.5, 0), colors.buy)
	redeem.AnchorPoint = Vector2.new(1, 0.5)
	ui.setButton(redeem, "Redeem", true, colors.buy)
	redeem.Activated:Connect(function()
		local text = string.sub(codeBox.Text, 1, 40)
		if text ~= "" then
			ui.send("Code", text)
			codeBox.Text = ""
		end
	end)
end

function ProfilePage.draw(state, ui)
	local colors = ui.colors
	local stats = state.stats
	local title = if state.title ~= "" then state.title .. " " else ""
	local since = if state.firstSeen > 0 then os.date("!%d %b %Y", state.firstSeen) else "today"
	local stars = state.rebirth.stars
	local starText = if stars > 0 then `   |   <font color="#F0C450">{stars} rebirth Stars</font>` else ""
	header.Text = `<b>{title}{ui.player.DisplayName}</b>   @{ui.player.Name}\n`
		.. `Level {state.level}{starText}   |   Power {Format.short(stats.attack + stats.defense)}   |   Renown {Format.short(state.renown)}\n`
		.. `In the realm since {since}   |   Highest foe stage this life: {state.highestStage}`

	for index, tile in TILES do
		tileValues[index].Text = tile[2](state)
	end

	ui.setButton(noTitleButton, if state.title == "" then "No title (now)" else "No title", state.title ~= "", colors.selected)
	local owned = {}
	for text in state.titles do
		table.insert(owned, text)
	end
	table.sort(owned)
	for index, card in titleCards do
		local text = owned[index]
		card.title = text
		card.info.Parent.Visible = text ~= nil
		if text then
			card.info.Text = `<b>{text}</b>\n{text} {ui.player.DisplayName}`
			if state.title == text then
				ui.setButton(card.button, "In use", false, colors.claim)
			else
				ui.setButton(card.button, "Use", true, colors.buy)
			end
		end
	end
	if #owned == 0 then
		ui.setButton(noTitleButton, "None yet", false, colors.selected)
		noTitleInfo.Text = `No titles yet. Your first rebirth gives "{RebirthConfig.getTitle(1)}"; the Relic Hall, packs and codes give others.`
	else
		noTitleInfo.Text = "Titles come from packs, rebirths, the Relic Hall and codes. The one you pick shows before your name."
	end
end

return ProfilePage
