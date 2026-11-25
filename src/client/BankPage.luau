-- Bank page:
--   * a vault scene: a round vault door whose wheel turns, coin piles, and
--     the two balances (ON HAND and BANKED) as big cards that count up and
--     down when they change,
--   * an amount box with quick 25% / 50% / ALL buttons for each side,
--   * DEPOSIT / WITHDRAW. Coins fly between the cards when gold moves.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Format = require(Shared:WaitForChild("Format"))

local BankPage = {}

local GOLD = Color3.fromRGB(240, 196, 80)
local STEEL = Color3.fromRGB(120, 124, 132)
local BLUE = Color3.fromRGB(120, 170, 240)

local w = {}
local latest = nil
local shown = { gold = nil, banked = nil } -- numbers on screen (they slide)
local goal = { gold = 0, banked = 0 }

local function commas(value: number): string
	local text = tostring(math.floor(value))
	local result = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (result:gsub("^,", ""))
end

local function coin(ui, parent: Instance, size: number, position: UDim2): Frame
	local disc = ui.makeFrame(parent, UDim2.fromOffset(size, size), position, GOLD)
	ui.addCorner(disc, size)
	ui.art.gloss(disc, 1, 0.55)
	ui.art.stroke(disc, Color3.fromRGB(120, 80, 20), 1.5, 0)
	return disc
end

-- The vault door: a steel ring, a wheel with spokes that turns.
local function buildVault(ui, parent: Instance)
	local door = ui.makeFrame(parent, UDim2.fromOffset(190, 190), UDim2.new(0.5, -95, 0, 22), STEEL)
	ui.addCorner(door, 95)
	ui.art.gloss(door, 1, 0.5)
	ui.art.stroke(door, Color3.fromRGB(50, 52, 58), 6, 0)
	local inner = ui.makeFrame(door, UDim2.fromOffset(150, 150), UDim2.fromOffset(20, 20), Color3.fromRGB(84, 88, 96))
	ui.addCorner(inner, 75)
	ui.art.stroke(inner, Color3.fromRGB(40, 42, 48), 3, 0)
	-- Bolts around the rim.
	for index = 0, 11 do
		local angle = math.rad(index * 30)
		local bolt = ui.makeFrame(door, UDim2.fromOffset(10, 10), UDim2.new(0.5, math.cos(angle) * 84 - 5, 0.5, math.sin(angle) * 84 - 5), Color3.fromRGB(190, 192, 200))
		ui.addCorner(bolt, 5)
	end
	local wheel = ui.makeFrame(inner, UDim2.fromOffset(110, 110), UDim2.fromOffset(20, 20), Color3.new(0, 0, 0))
	wheel.BackgroundTransparency = 1
	for index = 0, 2 do
		local spoke = ui.makeFrame(wheel, UDim2.fromOffset(110, 12), UDim2.new(0, 0, 0.5, -6), GOLD)
		spoke.Rotation = index * 60
		ui.addCorner(spoke, 6)
		ui.art.gloss(spoke, 1, 0.6)
	end
	local hub = ui.makeFrame(wheel, UDim2.fromOffset(40, 40), UDim2.fromOffset(35, 35), GOLD)
	ui.addCorner(hub, 20)
	ui.art.gloss(hub, 1, 0.5)
	ui.art.stroke(hub, Color3.fromRGB(120, 80, 20), 2, 0)
	w.wheel = wheel
	w.door = door

	-- Coin piles either side.
	for side = 0, 1 do
		for row = 0, 3 do
			for col = 0, 3 - row do
				local x = (if side == 0 then 0.5 - 0.36 else 0.5 + 0.2)
				coin(ui, parent, 26, UDim2.new(x, col * 22 + row * 11, 0, 182 - row * 14))
			end
		end
	end
end

local function balanceCard(ui, parent: Instance, x: number, title: string, color: Color3, glyph: string)
	local card = ui.makeFrame(parent, UDim2.new(0.3, 0, 0, 110), UDim2.new(x, 0, 0, 236), Color3.fromRGB(22, 18, 14))
	card.BackgroundTransparency = 0.05
	ui.addCorner(card, 10)
	ui.art.stroke(card, color, 2, 0.1)
	local icon = ui.makeText(card, UDim2.fromOffset(56, 110), UDim2.fromOffset(8, 0), Color3.new(1, 1, 1), 36)
	icon.TextXAlignment = Enum.TextXAlignment.Center
	icon.Text = glyph
	local label = ui.makeText(card, UDim2.new(1, -76, 0, 20), UDim2.fromOffset(68, 18), color, 15)
	label.Font = Enum.Font.GothamBlack
	label.Text = title
	local value = ui.makeText(card, UDim2.new(1, -76, 0, 40), UDim2.fromOffset(68, 38), Color3.new(1, 1, 1), 30)
	value.Font = Enum.Font.GothamBlack
	value.TextScaled = true
	local sub = ui.makeText(card, UDim2.new(1, -76, 0, 18), UDim2.fromOffset(68, 80), ui.colors.dim, 12)
	sub.Font = Enum.Font.GothamBold
	return { card = card, value = value, sub = sub }
end

-- Coins fly from one card to the other.
local function flyCoins(ui, from: GuiObject, to: GuiObject)
	local scene = w.scene
	local origin = from.AbsolutePosition - scene.AbsolutePosition + from.AbsoluteSize / 2
	local target = to.AbsolutePosition - scene.AbsolutePosition + to.AbsoluteSize / 2
	for index = 1, 14 do
		task.delay(index * 0.04, function()
			local piece = coin(ui, scene, 22, UDim2.fromOffset(origin.X - 11, origin.Y - 11))
			piece.ZIndex = 500
			local lift = math.random(-90, -40)
			local mid = UDim2.fromOffset((origin.X + target.X) / 2 - 11 + math.random(-30, 30), math.min(origin.Y, target.Y) + lift)
			local first = TweenService:Create(piece, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = mid })
			first:Play()
			first.Completed:Wait()
			local second = TweenService:Create(piece, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.fromOffset(target.X - 11, target.Y - 11),
				Size = UDim2.fromOffset(14, 14),
			})
			second:Play()
			second.Completed:Wait()
			piece:Destroy()
		end)
	end
	-- Spin the wheel a bit faster for a moment.
	w.spinBoost = 1.2
end

local function buildControls(ui, page: Instance)
	local colors = ui.colors
	local panel = ui.makeFrame(page, UDim2.new(1, -10, 0, 196), UDim2.fromOffset(0, 0), Color3.fromRGB(34, 29, 24))
	panel.LayoutOrder = 2
	ui.addCorner(panel, 10)
	ui.art.stroke(panel, colors.gold, 1.5, 0.4)

	local box = Instance.new("TextBox")
	box.Size = UDim2.new(1, -32, 0, 52)
	box.Position = UDim2.fromOffset(16, 14)
	box.BackgroundColor3 = Color3.fromRGB(20, 17, 14)
	box.TextColor3 = colors.text
	box.PlaceholderText = "Amount, like 5000 or 2.5m"
	box.PlaceholderColor3 = colors.dim
	box.Font = Enum.Font.GothamBlack
	box.TextSize = 24
	box.ClearTextOnFocus = false
	box.Text = ""
	box.Parent = panel
	ui.addCorner(box, 8)
	ui.art.stroke(box, colors.gold, 1.5, 0.4)
	w.box = box

	local function quick(text: string, x: UDim, y: number, width: number, source: string, share: number)
		local button = ui.makeButton(panel, UDim2.new(0, width, 0, 34), UDim2.new(x.Scale, x.Offset, 0, y), Color3.fromRGB(50, 42, 34))
		button.Text = text
		button.TextSize = 14
		button.Font = Enum.Font.GothamBlack
		button.Activated:Connect(function()
			local state = latest
			if state then
				local amount = math.floor((if source == "gold" then state.gold else state.banked) * share)
				box.Text = tostring(amount)
			end
		end)
	end
	-- Left half: deposit (from on hand). Right half: withdraw (from bank).
	quick("25%", UDim.new(0, 16), 78, 70, "gold", 0.25)
	quick("50%", UDim.new(0, 92), 78, 70, "gold", 0.5)
	quick("MAX", UDim.new(0, 168), 78, 70, "gold", 1)
	quick("25%", UDim.new(0.5, 8), 78, 70, "banked", 0.25)
	quick("50%", UDim.new(0.5, 84), 78, 70, "banked", 0.5)
	quick("MAX", UDim.new(0.5, 160), 78, 70, "banked", 1)

	local function big(text: string, x: number, color: Color3, action: string, all: boolean)
		local button = ui.makeButton(panel, UDim2.new(if all then 0.2 else 0.3, -16, 0, 56), UDim2.new(x, 16, 0, 124), color)
		button.Text = text
		button.TextSize = if all then 15 else 20
		button.Font = Enum.Font.GothamBlack
		button.Activated:Connect(function()
			local value = if all then "all" else box.Text
			if value ~= "" then
				ui.send(action, value)
				if not all then
					box.Text = ""
				end
			end
		end)
		return button
	end
	w.deposit = big("\u{2B07}\u{FE0F} DEPOSIT", 0, GOLD, "Deposit", false)
	w.depositAll = big("DEPOSIT ALL", 0.3, Color3.fromRGB(150, 120, 50), "Deposit", true)
	w.withdraw = big("\u{2B06}\u{FE0F} WITHDRAW", 0.5, Color3.fromRGB(70, 120, 190), "Withdraw", false)
	w.withdrawAll = big("WITHDRAW ALL", 0.8, Color3.fromRGB(60, 90, 140), "Withdraw", true)
end

function BankPage.build(ui)
	local page = ui.pages.Bank
	local colors = ui.colors
	local scene = ui.makeFrame(page, UDim2.new(1, -10, 0, 362), UDim2.fromOffset(0, 0), Color3.new(1, 1, 1))
	scene.LayoutOrder = 1
	scene.ClipsDescendants = true
	ui.addCorner(scene, 10)
	ui.art.stroke(scene, colors.gold, 2, 0.2)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.fromRGB(70, 56, 40), Color3.fromRGB(26, 20, 14))
	gradient.Parent = scene
	ui.art.grain(scene)
	w.scene = scene
	buildVault(ui, scene)
	w.hand = balanceCard(ui, scene, 0.04, "ON HAND", GOLD, "\u{1F4B0}")
	w.bank = balanceCard(ui, scene, 0.66, "BANKED (SAFE)", BLUE, "\u{1F3E6}")
	w.fee = ui.makeText(scene, UDim2.new(0.3, 0, 0, 26), UDim2.new(0.35, 0, 0, 300), colors.text, 14)
	w.fee.BackgroundTransparency = 0.1
	w.fee.BackgroundColor3 = Color3.fromRGB(22, 18, 14)
	w.fee.Font = Enum.Font.GothamBlack
	w.fee.TextXAlignment = Enum.TextXAlignment.Center
	w.fee.RichText = true
	ui.addCorner(w.fee, 13)

	buildControls(ui, page)
	local note = ui.makeText(page, UDim2.new(1, -10, 0, 40), UDim2.fromOffset(0, 0), colors.dim, 13)
	note.LayoutOrder = 3
	note.Text = "You spend gold on hand, so withdraw before buying. Once raids arrive, only gold on hand can be stolen."

	-- The wheel turns; the numbers slide toward their new values.
	local angle = 0
	w.spinBoost = 0
	RunService.RenderStepped:Connect(function(dt)
		if not page.Visible then
			return
		end
		w.spinBoost = math.max(0, (w.spinBoost or 0) - dt)
		angle += dt * (12 + w.spinBoost * 260)
		w.wheel.Rotation = angle
		for key, part in { gold = w.hand, banked = w.bank } do
			local now = shown[key]
			if now then
				local target = goal[key]
				if math.abs(target - now) < 1 then
					now = target
				else
					now += (target - now) * math.min(1, dt * 8)
				end
				shown[key] = now
				part.value.Text = commas(now)
			end
		end
	end)
end

function BankPage.draw(state, ui)
	if not state then
		return
	end
	local before = latest
	latest = state
	goal.gold = math.floor(state.gold)
	goal.banked = math.floor(state.banked)
	if shown.gold == nil then
		shown.gold = goal.gold
		shown.banked = goal.banked
	end
	local page = ui.pages.Bank
	if before and page.Visible then
		local delta = math.floor(state.banked) - math.floor(before.banked)
		if delta > 0 then
			flyCoins(ui, w.hand.card, w.bank.card)
		elseif delta < 0 then
			flyCoins(ui, w.bank.card, w.hand.card)
		end
	end
	w.hand.sub.Text = `{Format.short(state.gold)} gold you can spend`
	w.bank.sub.Text = `{Format.short(state.banked)} gold kept safe`
	local free = state.passes and state.passes.treasury
	w.fee.Text = if free
		then `<font color="#7FE08A">\u{2714} NO FEE</font> (Royal Treasury)`
		else `DEPOSIT FEE <font color="#F0C450">{math.floor(GameConfig.BankFee * 100)}%</font>`
	local typed = Format.parse(w.box.Text)
	local feeNote = if typed and typed > 0 and not free then `  (-{Format.short(math.ceil(typed * GameConfig.BankFee))} fee)` else ""
	ui.setButton(w.deposit, `\u{2B07}\u{FE0F} DEPOSIT{feeNote}`, state.gold >= 1, GOLD)
	ui.setButton(w.depositAll, "DEPOSIT ALL", state.gold >= 1, Color3.fromRGB(150, 120, 50))
	ui.setButton(w.withdraw, "\u{2B06}\u{FE0F} WITHDRAW", state.banked >= 1, Color3.fromRGB(70, 120, 190))
	ui.setButton(w.withdrawAll, "WITHDRAW ALL", state.banked >= 1, Color3.fromRGB(60, 90, 140))
	w.hand.value.TextColor3 = Color3.new(1, 1, 1)
	w.bank.value.TextColor3 = Color3.new(1, 1, 1)
end

return BankPage
