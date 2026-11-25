-- Bounties page:
--   * a banner with your Seals and the reset clocks,
--   * the 7 day login streak as reward cards along a path (today glows),
--   * daily and weekly bounty cards with bars; finished ones pulse,
--   * the Seal shop as picture cards with "x left" tags.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local StoreConfig = require(Shared:WaitForChild("StoreConfig"))
local BountyConfig = require(Shared:WaitForChild("BountyConfig"))
local Format = require(Shared:WaitForChild("Format"))
local Kit = require(script.Parent:WaitForChild("Kit"))

local BountiesPage = {}

local SEAL = "\u{1F4DC}"
local TASK_GLYPHS = {
	quests = "\u{1F5FA}\u{FE0F}",
	foes = "\u{1F409}",
	holdings = "\u{1F33E}",
	rolls = "\u{1F482}",
	claims = "\u{1F381}",
	train = "\u{1F3CB}\u{FE0F}",
	market = "\u{2696}\u{FE0F}",
}

local w = {}
local streak = {}
local tasks = {}
local shop = {}
local latest = nil

local function buildStreak(ui, page: Instance)
	local _, _, right = Kit.heading(ui, page, 2, "Login streak", Kit.GOLD)
	w.streakNote = right
	local grid = Kit.grid(ui, page, 3, 170, #BountyConfig.Streak)
	for day, reward in BountyConfig.Streak do
		local card, stroke = Kit.card(ui, grid, day, Kit.rewardColor(reward))
		local label = Kit.centered(ui, card, 8, 20, 14, ui.colors.dim)
		label.Font = Enum.Font.GothamBlack
		label.Text = `DAY {day}`
		local art = ui.makeFrame(card, UDim2.fromOffset(64, 64), UDim2.new(0.5, -32, 0, 32), Color3.new(0, 0, 0))
		art.BackgroundTransparency = 1
		Kit.rewardArt(ui, art, reward)
		local text = Kit.centered(ui, card, 98, 30, 12, ui.colors.text)
		text.Font = Enum.Font.GothamBold
		text.Text = StoreConfig.describe(reward)
		local button = ui.makeButton(card, UDim2.new(1, -16, 0, 30), UDim2.new(0, 8, 1, -36), ui.colors.claim)
		button.TextSize = 13
		button.Font = Enum.Font.GothamBlack
		local check = ui.makeText(card, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Kit.GREEN, 50)
		check.BackgroundTransparency = 0.45
		check.BackgroundColor3 = Color3.new(0, 0, 0)
		check.Font = Enum.Font.GothamBlack
		check.TextXAlignment = Enum.TextXAlignment.Center
		check.Text = "\u{2714}"
		check.ZIndex = 450
		button.Activated:Connect(function()
			Kit.pop(card, 1.15)
			Kit.float(ui, card, `+{StoreConfig.describe(reward)}`, Kit.GOLD)
			ui.send("StreakClaim")
		end)
		streak[day] = { card = card, stroke = stroke, button = button, check = check }
	end
end

local function buildTasks(ui, page: Instance, order: number, list, key: string)
	local _, label, right = Kit.heading(ui, page, order, if key == "daily" then "Daily bounties" else "Weekly bounties", if key == "daily" then Kit.GREEN else Color3.fromRGB(120, 160, 240))
	w[key .. "Clock"] = right
	local _ = label
	local grid = Kit.grid(ui, page, order + 1, 96, 2)
	for index, task in list do
		local card, stroke = Kit.card(ui, grid, index)
		Kit.badge(ui, card, TASK_GLYPHS[task.stat] or "\u{2B50}", 60, UDim2.fromOffset(14, 18), Color3.fromRGB(70, 56, 40))
		local name = ui.makeText(card, UDim2.new(1, -230, 0, 24), UDim2.fromOffset(86, 12), ui.colors.text, 16)
		name.Font = Enum.Font.GothamBold
		name.Text = task.name
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local seals = ui.makeText(card, UDim2.fromOffset(110, 24), UDim2.new(1, -124, 0, 12), Color3.fromRGB(40, 24, 6), 13)
		seals.BackgroundTransparency = 0
		seals.BackgroundColor3 = Kit.GOLD
		seals.Font = Enum.Font.GothamBlack
		seals.TextXAlignment = Enum.TextXAlignment.Center
		seals.Text = `{SEAL} +{task.seals} SEALS`
		ui.addCorner(seals, 6)
		local bar = Kit.bar(ui, card, UDim2.new(1, -230, 0, 24), UDim2.fromOffset(86, 50), Kit.GREEN)
		local button = ui.makeButton(card, UDim2.fromOffset(110, 34), UDim2.new(1, -124, 0, 46), ui.colors.claim)
		button.TextSize = 14
		button.Font = Enum.Font.GothamBlack
		button.Activated:Connect(function()
			Kit.pop(card, 1.06)
			Kit.float(ui, card, `+{task.seals} Seals`, Kit.GOLD)
			ui.send("BountyClaim", task.key)
		end)
		tasks[task.key] = { card = card, stroke = stroke, bar = bar, button = button, task = task, list = key }
	end
end

local function buildShop(ui, page: Instance)
	local _, _, right = Kit.heading(ui, page, 8, "Seal shop", Kit.GOLD)
	right.Text = "STOCK REFILLS EVERY MONDAY"
	local grid = Kit.grid(ui, page, 9, 220, 3)
	for index, item in BountyConfig.Shop do
		local card, stroke = Kit.card(ui, grid, index, Kit.rewardColor(item.reward))
		local art = ui.makeFrame(card, UDim2.fromOffset(84, 84), UDim2.new(0.5, -42, 0, 14), Color3.new(0, 0, 0))
		art.BackgroundTransparency = 1
		Kit.rewardArt(ui, art, item.reward)
		local name = Kit.centered(ui, card, 102, 24, 17, ui.colors.text)
		name.Font = Enum.Font.GothamBlack
		name.Text = item.name
		local note = Kit.centered(ui, card, 126, 20, 13, ui.colors.dim)
		note.Text = StoreConfig.describe(item.reward)
		local left = ui.makeText(card, UDim2.fromOffset(84, 22), UDim2.fromOffset(8, 8), ui.colors.text, 11)
		left.BackgroundTransparency = 0
		left.BackgroundColor3 = Color3.fromRGB(16, 14, 12)
		left.Font = Enum.Font.GothamBlack
		left.TextXAlignment = Enum.TextXAlignment.Center
		ui.addCorner(left, 4)
		local button = ui.makeButton(card, UDim2.new(1, -24, 0, 44), UDim2.new(0, 12, 1, -54), ui.colors.buy)
		button.TextSize = 16
		button.Font = Enum.Font.GothamBlack
		button.Activated:Connect(function()
			Kit.pop(card, 1.08)
			ui.send("SealBuy", item.key)
		end)
		shop[item.key] = { card = card, stroke = stroke, left = left, button = button, item = item }
	end
end

function BountiesPage.build(ui)
	local page = ui.pages.Bounties
	local banner = Kit.banner(ui, page, 1, 120, Color3.fromRGB(150, 90, 40), Color3.fromRGB(60, 34, 16), "Bounty Board", SEAL)
	w.seals = Kit.line(ui, banner, 120, 66, UDim.new(0.5, -120), 22, Color3.new(1, 1, 1))
	w.seals.Font = Enum.Font.GothamBlack
	local note = Kit.line(ui, banner, 0, 0, UDim.new(0.4, 0), 13, Color3.fromRGB(255, 230, 200))
	note.Position = UDim2.new(0.58, 0, 0, 40)
	note.Size = UDim2.new(0.4, -10, 0, 44)
	note.TextWrapped = true
	note.Text = "Finish bounties for Seals, then spend them in the Seal shop. Log in every day to keep your streak."
	buildStreak(ui, page)
	buildTasks(ui, page, 4, BountyConfig.Daily, "daily")
	buildTasks(ui, page, 6, BountyConfig.Weekly, "weekly")
	buildShop(ui, page)
	page:GetPropertyChangedSignal("Visible"):Connect(function()
		if page.Visible then
			Kit.popAll(page)
		end
	end)
end

function BountiesPage.draw(state, ui)
	if not state then
		return
	end
	latest = state
	local colors = ui.colors
	local bounty = state.bounty
	local ready = 0
	w.seals.Text = `{SEAL}  <font color="#F0C450">{Format.short(state.seals)}</font> SEALS`

	for day, part in streak do
		local claimable = state.streakReady and day == state.streakDay
		local done = day < state.streakDay or (not state.streakReady and day == state.streakDay)
		if claimable then
			ready += 1
		end
		part.check.Visible = done
		Kit.setPulse(part.stroke, claimable, colors.dim)
		ui.setButton(part.button, if claimable then "CLAIM!" elseif done then "CLAIMED" else `DAY {day}`, claimable, colors.claim)
	end
	w.streakNote.Text = if state.streakReady then "TODAY'S REWARD IS READY" else `DAY {state.streakDay} OF {#BountyConfig.Streak}`

	local dayLeft = 86400 - os.time() % 86400
	w.dailyClock.Text = `NEW IN {string.upper(Kit.clock(dayLeft))}`
	w.weeklyClock.Text = `NEW IN {string.upper(Kit.clock(state.weekSecondsLeft or 0))}`
	for key, part in tasks do
		local task = part.task
		local counts = if part.list == "daily" then bounty.daily else bounty.weekly
		local value = math.min(task.goal, counts[task.stat] or 0)
		Kit.setBar(part.bar, value, task.goal, `{Format.short(value)} / {Format.short(task.goal)}`)
		local done = bounty.claimed[key] == true
		local canClaim = not done and value >= task.goal
		if canClaim then
			ready += 1
		end
		Kit.setPulse(part.stroke, canClaim, colors.dim)
		ui.setButton(part.button, if done then "\u{2714} DONE" elseif canClaim then "CLAIM" else "IN PROGRESS", canClaim, colors.claim)
		part.card.BackgroundTransparency = if done then 0.4 else 0
	end

	for key, part in shop do
		local item = part.item
		local left = item.limit - (bounty.bought[key] or 0)
		part.left.Text = `{math.max(0, left)} / {item.limit} LEFT`
		if left <= 0 then
			ui.setButton(part.button, "SOLD OUT", false, colors.buy)
		else
			ui.setButton(part.button, `{SEAL} {item.cost} SEALS`, state.seals >= item.cost, colors.buy)
		end
	end
	ui.setBadge("Bounties", ready)
end

return BountiesPage
