-- Rebirth page: start over from level 1 for Stars with lasting bonuses.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local RebirthConfig = require(Shared:WaitForChild("RebirthConfig"))
local Format = require(Shared:WaitForChild("Format"))

local RebirthPage = {}

local CONFIRM_SECONDS = 5

local status
local bonusText
local rulesText
local button
local armedUntil = 0

local function bonusLine(stars: number): string
	local per = RebirthConfig.PerStar
	local function pct(amount: number): string
		return `+{math.floor(amount * stars * 100 + 0.5)}%`
	end
	return `{pct(per.income)} holding income, {pct(per.questGold)} quest gold, {pct(per.xp)} quest XP, `
		.. `{pct(per.attack)} attack, {pct(per.defense)} defense`
end

function RebirthPage.build(ui)
	local page = ui.pages.Rebirth
	status, button = ui.makeRow(page, ui.nextOrder(), 74, true)
	status.RichText = true
	button.Activated:Connect(function()
		if os.clock() < armedUntil then
			armedUntil = 0
			ui.send("Rebirth", "confirm")
		else
			armedUntil = os.clock() + CONFIRM_SECONDS
			ui.redraw()
			task.delay(CONFIRM_SECONDS, ui.redraw)
		end
	end)
	bonusText = ui.makeRow(page, ui.nextOrder(), 56, false)
	bonusText.RichText = true

	ui.makeHeading(page, ui.nextOrder(), "What a rebirth does")
	rulesText = ui.makeRow(page, ui.nextOrder(), 120, false)
	rulesText.RichText = true
	rulesText.TextYAlignment = Enum.TextYAlignment.Top
	rulesText.Text = "<b>Starts over:</b> level, experience, skills and skill points, gold on hand and in the bank, holdings, the Keep, quest mastery and foe stages.\n"
		.. "<b>Comes with you:</b> your warband, all gear, trophies, research, the Relic Hall, game passes, Crowns, boss tokens, Seals and titles.\n"
		.. `<b>You get:</b> Stars that never go away, a "Reborn" title, and {Format.short(RebirthConfig.StartGoldPerStar)} extra starting gold per Star. `
		.. `First clear bonuses on foes are paid only once, ever.`
end

function RebirthPage.draw(state, ui)
	local colors = ui.colors
	local rebirth = state.rebirth
	local starsNow = state.rebirthStars
	local nextStarLevel = if state.level < RebirthConfig.MinLevel
		then RebirthConfig.MinLevel
		else RebirthConfig.MinLevel + (starsNow) * RebirthConfig.LevelsPerStar
	if starsNow > 0 then
		status.Text = `<b>Reborn {rebirth.count} times, {rebirth.stars} Stars</b>\n`
			.. `Rebirth now for <font color="#F0C450"><b>{starsNow} Stars</b></font>. At level {nextStarLevel} it would be {starsNow + 1}.`
	else
		status.Text = `<b>Reborn {rebirth.count} times, {rebirth.stars} Stars</b>\n`
			.. `Rebirth opens at level {RebirthConfig.MinLevel}. You are level {state.level}.`
	end
	bonusText.Text = `Your Stars give: <font color="#9FD49A">{if rebirth.stars > 0 then bonusLine(rebirth.stars) else "nothing yet"}</font>\n`
		.. `Each Star adds: {bonusLine(1)}`

	if starsNow <= 0 then
		ui.setButton(button, `Level {RebirthConfig.MinLevel}`, false, colors.action)
	elseif os.clock() < armedUntil then
		ui.setButton(button, "Press again\nto confirm", true, colors.gold)
	else
		ui.setButton(button, `Rebirth\n+{starsNow} Stars`, true, colors.action)
	end
end

return RebirthPage
