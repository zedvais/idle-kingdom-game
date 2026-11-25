-- War Chronicle page: reports of foe fights and expeditions, newest first.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArmyConfig = require(Shared:WaitForChild("ArmyConfig"))
local Format = require(Shared:WaitForChild("Format"))

local ChroniclePage = {}

local emptyNote
local rows = {}

local function ago(seconds: number): string
	if seconds < 60 then
		return "just now"
	elseif seconds < 3600 then
		return `{math.floor(seconds / 60)}m ago`
	elseif seconds < 86400 then
		return `{math.floor(seconds / 3600)}h ago`
	end
	return `{math.floor(seconds / 86400)}d ago`
end

function ChroniclePage.build(ui)
	local page = ui.pages.Chronicle
	emptyNote = ui.makeRow(page, ui.nextOrder(), 34, false)
	emptyNote.TextColor3 = ui.colors.dim
	emptyNote.Text = "No battles yet. Beat a foe or send an expedition and the report shows up here."
	for index = 1, ArmyConfig.ChronicleKept do
		local info = ui.makeRow(page, ui.nextOrder(), 60, false)
		info.RichText = true
		info.TextSize = 13
		info.TextYAlignment = Enum.TextYAlignment.Top
		rows[index] = info
	end
end

function ChroniclePage.draw(state, ui)
	local now = os.time()
	emptyNote.Parent.Visible = #state.chronicle == 0
	for index, info in rows do
		local report = state.chronicle[index]
		local frame = info.Parent
		frame.Visible = report ~= nil
		if not report then
			continue
		end
		local tag = ""
		if report.win == true then
			tag = `<font color="#9FD49A"><b>VICTORY</b></font>  `
		elseif report.win == false then
			tag = `<font color="#E08A7A"><b>DEFEAT</b></font>  `
		end
		local lines = { `{tag}<b>{report.title}</b>   <font color="#B2A690">{ago(now - report.time)}</font>`, report.text }
		if report.rounds then
			for round, entry in report.rounds do
				local left = if report.enemyHealth and report.enemyHealth > 0
					then math.floor(entry.enemyLeft / report.enemyHealth * 100 + 0.5)
					else 0
				table.insert(lines, `Round {round}: you dealt {Format.short(entry.dealt)}, took {Format.short(entry.taken)}. Enemy at {left}%.`)
			end
		end
		info.Text = table.concat(lines, "\n")
		frame.Size = UDim2.new(1, -10, 0, 30 + 20 * #lines)
	end
end

return ChroniclePage
