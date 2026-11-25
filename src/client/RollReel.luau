-- Roll display on each warband slot. Every recruit roll for a slot (a
-- single roll or auto roll) shows the soldier rolled on that slot's row:
-- rarity, class, name, attack and defense, and whether it was kept. Auto
-- roll rolls once a second, so each soldier stays up for a second. While
-- auto roll works on a slot, STOP keeps the soldier shown right now in
-- that slot, and auto roll carries on with the other slots.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local RollReel = {}

local reels = {} -- [slot] = widgets
local spinId = {} -- [slot] = number, so a new roll cancels the last spin
local SHOW_TIME = 4 -- how long a result stays when nothing else rolls

local function hex(color: Color3): string
	return string.format("#%02X%02X%02X", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
end

local function build(ui, slot: number, row)
	local colors = ui.colors
	local art = ui.art
	-- The reel sits over the middle of the row (where the gear text is).
	local panel = ui.makeFrame(row.frame, UDim2.new(0.7, -300, 1, -8), UDim2.new(0.3, -6, 0, 4), Color3.fromRGB(18, 14, 11))
	panel.Visible = false
	panel.ZIndex = 5
	ui.addCorner(panel, 6)
	local stroke = art.stroke(panel, colors.dim, 2, 0)
	local window = ui.makeFrame(panel, UDim2.new(1, -70, 1, -8), UDim2.fromOffset(4, 4), Color3.fromRGB(30, 24, 20))
	window.ZIndex = 6
	window.ClipsDescendants = true
	ui.addCorner(window, 4)
	local text = ui.makeText(window, UDim2.new(1, -12, 1, 0), UDim2.fromOffset(8, 0), colors.text, 13)
	text.ZIndex = 7
	text.RichText = true
	text.TextYAlignment = Enum.TextYAlignment.Center
	local tag = ui.makeText(panel, UDim2.fromOffset(62, 20), UDim2.new(1, -66, 0, 4), colors.dim, 11)
	tag.ZIndex = 7
	tag.Font = Enum.Font.GothamBold
	tag.TextXAlignment = Enum.TextXAlignment.Center
	local stop = ui.makeButton(panel, UDim2.fromOffset(60, 34), UDim2.new(1, -64, 1, -38), colors.action)
	stop.ZIndex = 7
	stop.TextSize = 13
	stop.Visible = false
	ui.setButton(stop, "STOP\n<font size=\"10\">keep this</font>", true, colors.action)
	stop.RichText = true
	stop.Activated:Connect(function()
		ui.send("AutoRollSkip", tostring(slot))
	end)
	reels[slot] = { panel = panel, stroke = stroke, text = text, tag = tag, stop = stop, lastRoll = 0, auto = false }
end

-- Plays one roll on a slot's reel.
local function play(ui, info)
	local slot = tonumber(info.slot)
	local reel = slot and reels[slot]
	if not reel then
		return
	end
	spinId[slot] = (spinId[slot] or 0) + 1
	local id = spinId[slot]
	reel.lastRoll = os.clock()
	reel.panel.Visible = true
	-- No spin: the rolled soldier shows right away and stays until the
	-- next roll a second later, so the player can STOP and keep it.
	local rarity = GameConfig.getRarity(info.rarity or "Common")
	reel.stroke.Color = rarity.color
	reel.text.Text = `<font color="{hex(rarity.color)}"><b>{string.upper(rarity.id)} {info.class or ""}</b></font>  {info.name or ""}\n`
		.. `<font color="#F08A6A">{info.attack or 0} ATK</font>   <font color="#7FB4F0">{info.defense or 0} DEF</font>`
	if info.kept then
		reel.tag.Text = "KEPT!"
		reel.tag.TextColor3 = Color3.fromRGB(120, 220, 120)
	else
		reel.tag.Text = `need {info.target or ""}`
		reel.tag.TextColor3 = Color3.fromRGB(200, 120, 110)
	end
	-- Hide after a while, unless auto roll keeps working on this slot.
	task.delay(SHOW_TIME, function()
		if spinId[slot] == id and not reel.auto then
			reel.panel.Visible = false
		end
	end)
end

function RollReel.build(ui)
	for slot, row in ui.crewRows do
		build(ui, slot, row)
	end
	local Fx = require(script.Parent:WaitForChild("Fx"))
	Fx.onRoll = function(info)
		play(ui, info)
	end
end

-- Shows STOP on every slot auto roll is working on.
function RollReel.draw(state, ui)
	local auto = state.autoRoll or {}
	local skip = auto.skip or {}
	local targetRank = GameConfig.getRarityRank(auto.rarity or "Common")
	for slot, reel in reels do
		local soldier = state.crew[slot]
		local working = false
		if auto.on and soldier ~= nil and not skip[tostring(slot)] then
			if auto.scope == "this" then
				working = auto.slot == slot
			elseif auto.scope == "empty" then
				working = soldier == false
			elseif auto.scope == "below" then
				working = soldier == false or GameConfig.getRarityRank(soldier.rarity) < targetRank
			end
		end
		reel.auto = working
		reel.stop.Visible = working
		if working then
			reel.panel.Visible = true
			if reel.lastRoll == 0 then
				reel.text.Text = "<font color=\"#B2A690\">Auto roll will roll this slot.</font>"
				reel.stroke.Color = ui.colors.dim
			end
			if reel.lastRoll > 0 and os.clock() - reel.lastRoll > 3 then
				reel.tag.Text = "WAITING"
				reel.tag.TextColor3 = ui.colors.dim
			end
		elseif os.clock() - reel.lastRoll > SHOW_TIME and reel.panel.Visible then
			reel.panel.Visible = false
		end
	end
end

return RollReel
