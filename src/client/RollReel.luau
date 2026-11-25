-- Rolls shown right on the warband card. Every recruit roll for a slot (a
-- single roll or auto roll) puts the rolled soldier on that slot's card:
-- portrait, name, rarity, class, attack and defense, and whether it was
-- kept. Auto roll rolls once a second, so each soldier stays up for a
-- second. While auto roll works on a slot, STOP on the card keeps the
-- soldier shown right now, and auto roll carries on with the other slots.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Format = require(Shared:WaitForChild("Format"))

local RollReel = {}

local reels = {} -- [slot] = { row, stop, last, lastRoll, auto }
local SHOW_TIME = 4 -- how long a result stays when nothing else rolls

local function hex(color: Color3): string
	return string.format("#%02X%02X%02X", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
end

local function showing(reel): boolean
	return reel.auto or (reel.last ~= nil and os.clock() - reel.lastRoll <= SHOW_TIME)
end

-- Paints the card with the last roll (or a waiting note for auto roll).
local function apply(ui, slot: number)
	local reel = reels[slot]
	if not reel then
		return
	end
	local row = reel.row
	reel.stop.Visible = reel.auto
	if not showing(reel) then
		return
	end
	local info = reel.last
	if not info then
		row.info.Text = `<font size="17"><b>Auto roll</b></font>\n<font color="#B2A690">Rolling this slot every second...</font>`
		return
	end
	local rarity = GameConfig.getRarity(info.rarity or "Common")
	local color = hex(rarity.color)
	row.glyph.Text = ui.classGlyphs[info.class or ""] or ui.art.Icons.soldier
	row.portrait.Color = rarity.color
	row.edge.Color = rarity.color
	local status
	if info.kept then
		status = `<font color="#78DC78"><b>KEPT!</b></font>`
	elseif reel.auto and os.clock() - reel.lastRoll > 3 then
		status = `<font color="#B2A690">Waiting for gold... need {info.target or ""}</font>`
	else
		status = `<font color="#C8786E">Rolling... need {info.target or ""}</font>`
	end
	row.info.Text = `<font color="{color}" size="17"><b>{info.name or ""}</b></font>\n`
		.. `<font color="{color}"><b>{string.upper(rarity.id)}</b></font> {info.class or ""}\n{status}`
	row.statsText.Text = `<font color="#F08A6A">+{Format.short(info.attack or 0)} ATTACK</font>\n<font color="#7FB4F0">+{Format.short(info.defense or 0)} DEFENSE</font>`
end

local function play(ui, info)
	local slot = tonumber(info.slot)
	local reel = slot and reels[slot]
	if not reel then
		return
	end
	reel.last = info
	reel.lastRoll = os.clock()
	local stamp = reel.lastRoll
	apply(ui, slot)
	-- Afterwards the card goes back to the real soldier on the next update.
	task.delay(SHOW_TIME + 0.1, function()
		if reel.lastRoll == stamp and not reel.auto then
			reel.last = nil
		end
	end)
end

function RollReel.build(ui)
	for slot, row in ui.crewRows do
		-- STOP sits left of the card's buttons and shows only while auto
		-- roll works on this slot.
		local stop = ui.makeButton(row.frame, UDim2.fromOffset(84, 60), UDim2.new(1, -252, 0, 8), ui.colors.action)
		stop.AnchorPoint = Vector2.new(1, 0)
		stop.ZIndex = row.frame.ZIndex + 5
		stop.TextSize = 14
		stop.RichText = true
		stop.Visible = false
		ui.setButton(stop, "STOP\n<font size=\"10\">keep this</font>", true, ui.colors.action)
		stop.Activated:Connect(function()
			ui.send("AutoRollSkip", tostring(slot))
		end)
		reels[slot] = { row = row, stop = stop, last = nil, lastRoll = 0, auto = false }
	end
	function ui.showRoll(slot: number)
		apply(ui, slot)
	end
	local Fx = require(script.Parent:WaitForChild("Fx"))
	Fx.onRoll = function(info)
		play(ui, info)
	end
end

-- Works out which slots auto roll is working on.
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
	end
end

return RollReel
