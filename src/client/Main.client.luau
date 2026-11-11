-- Client entry point: draws the on-screen display (gold, income, army power),
-- short pop-up messages, and the welcome back window.
-- The server sends everything through attributes on the player.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Format = require(Shared:WaitForChild("Format"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "KingdomHud"
gui.ResetOnSpawn = false
gui.Parent = playerGui

local function addCorner(instance: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local function makeText(parent: Instance, size: UDim2, position: UDim2, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = size
	label.Position = position
	label.BackgroundTransparency = 1
	label.TextColor3 = color
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = ""
	label.Parent = parent
	return label
end

---------------------------------------------------------------------------
-- Top bar: gold, income and army power
---------------------------------------------------------------------------

local bar = Instance.new("Frame")
bar.AnchorPoint = Vector2.new(0.5, 0)
bar.Position = UDim2.new(0.5, 0, 0, 8)
bar.Size = UDim2.fromOffset(340, 76)
bar.BackgroundColor3 = Color3.fromRGB(25, 22, 30)
bar.BackgroundTransparency = 0.2
bar.Parent = gui
addCorner(bar, 12)

local goldLabel = makeText(bar, UDim2.new(1, -20, 0, 36), UDim2.fromOffset(10, 6), Color3.fromRGB(255, 214, 90))
local detailLabel = makeText(bar, UDim2.new(1, -20, 0, 22), UDim2.fromOffset(10, 46), Color3.fromRGB(230, 230, 235))

local function updateBar()
	local gold = player:GetAttribute("Gold") or 0
	local perSecond = player:GetAttribute("GoldPerSecond") or 0
	local power = player:GetAttribute("ArmyPower") or 0
	goldLabel.Text = `{Format.short(gold)} gold`
	detailLabel.Text = `+{Format.short(perSecond)} per second   |   Army power {Format.short(power)}`
end

for _, name in { "Gold", "GoldPerSecond", "ArmyPower" } do
	player:GetAttributeChangedSignal(name):Connect(updateBar)
end
updateBar()

---------------------------------------------------------------------------
-- Toasts: short messages from the server
---------------------------------------------------------------------------

local toast = makeText(gui, UDim2.fromOffset(520, 44), UDim2.new(0.5, 0, 1, -150), Color3.new(1, 1, 1))
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.BackgroundColor3 = Color3.fromRGB(25, 22, 30)
toast.BackgroundTransparency = 0.2
toast.Visible = false
addCorner(toast, 10)

local toastCount = 0
player:GetAttributeChangedSignal("ToastId"):Connect(function()
	toastCount += 1
	local thisToast = toastCount
	toast.Text = player:GetAttribute("ToastText") or ""
	toast.Visible = true
	task.delay(3.5, function()
		if toastCount == thisToast then
			toast.Visible = false
		end
	end)
end)

---------------------------------------------------------------------------
-- Welcome back window: gold earned while away
---------------------------------------------------------------------------

local function showWelcomeBack(amount: number)
	local window = Instance.new("Frame")
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.45)
	window.Size = UDim2.fromOffset(380, 200)
	window.BackgroundColor3 = Color3.fromRGB(25, 22, 30)
	window.Parent = gui
	addCorner(window, 14)

	local title = makeText(window, UDim2.new(1, -30, 0, 36), UDim2.fromOffset(15, 14), Color3.new(1, 1, 1))
	title.Text = "Welcome back, my liege!"

	local body = makeText(window, UDim2.new(1, -30, 0, 60), UDim2.fromOffset(15, 58), Color3.fromRGB(255, 214, 90))
	body.Text = `Your stewards collected {Format.short(amount)} gold while you were away.`
	body.TextWrapped = true

	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(0.5, 0, 1, -14)
	button.Size = UDim2.fromOffset(160, 44)
	button.BackgroundColor3 = Color3.fromRGB(80, 160, 90)
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Font = Enum.Font.GothamBold
	button.TextScaled = true
	button.Text = "Splendid"
	button.Parent = window
	addCorner(button, 10)

	button.Activated:Connect(function()
		window:Destroy()
	end)
end

local shownWelcome = false
local function checkWelcomeBack()
	local amount = player:GetAttribute("OfflineGold")
	if not shownWelcome and typeof(amount) == "number" and amount > 0 then
		shownWelcome = true
		showWelcomeBack(amount)
	end
end

player:GetAttributeChangedSignal("OfflineGold"):Connect(checkWelcomeBack)
checkWelcomeBack()

print(`[{GameConfig.GameName}] client started`)
