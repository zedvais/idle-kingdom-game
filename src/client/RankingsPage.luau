-- Rankings page: all-time boards shared by every server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ProfileConfig = require(Shared:WaitForChild("ProfileConfig"))
local Format = require(Shared:WaitForChild("Format"))

local RankingsPage = {}

local intro
local boardText = {}

-- Your own score on a board, worked out from the state.
local function myScore(state, key: string): number
	if key == "power" then
		return state.stats.attack + state.stats.defense
	elseif key == "level" then
		return state.level
	elseif key == "renown" then
		return state.renown
	elseif key == "rebirths" then
		return state.rebirth.count
	end
	return 0
end

function RankingsPage.build(ui)
	local page = ui.pages.Rankings
	intro = ui.makeRow(page, ui.nextOrder(), 40, false)
	intro.TextColor3 = ui.colors.dim
	intro.Text = `Boards cover every server and update about every {math.floor(ProfileConfig.BoardSeconds / 60)} minutes. Your score is sent while you play.`
	local grid = ui.makeGrid(page, ui.nextOrder(), 22 * ProfileConfig.BoardSize + 56, 2)
	for index, board in ProfileConfig.Boards do
		local card = ui.makeFrame(grid, UDim2.fromOffset(100, 100), UDim2.fromOffset(0, 0), ui.colors.row)
		card.LayoutOrder = index
		ui.addCorner(card, 8)
		ui.addStroke(card)
		local text = ui.makeText(card, UDim2.new(1, -16, 1, -12), UDim2.fromOffset(8, 6), ui.colors.text, 13)
		text.RichText = true
		text.TextYAlignment = Enum.TextYAlignment.Top
		boardText[board.key] = text
	end
end

function RankingsPage.draw(state, ui)
	for _, board in ProfileConfig.Boards do
		local list = state.rankings[board.key] or {}
		local lines = {
			`<b>{string.upper(board.name)}</b>   <font color="#B2A690">{board.note}</font>`,
			`You: <b>{Format.short(myScore(state, board.key))}</b>`,
		}
		for index, entry in list do
			local name = entry[1]
			if name == ui.player.Name then
				name = `<font color="#F0C450"><b>{name} (you)</b></font>`
			end
			table.insert(lines, `#{index}   {name}   {Format.short(entry[2])}`)
		end
		if #list == 0 then
			table.insert(lines, "No scores yet. Boards fill in once the game is published and players have saved.")
		end
		boardText[board.key].Text = table.concat(lines, "\n")
	end
end

return RankingsPage
