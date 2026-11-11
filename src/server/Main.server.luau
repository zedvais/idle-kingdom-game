--!strict
-- Server entry point. For now this only proves the project is wired up:
-- every player gets a Gold counter on the leaderboard that ticks up.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local function onPlayerAdded(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local gold = Instance.new("IntValue")
	gold.Name = "Gold"
	gold.Value = 0
	gold.Parent = leaderstats

	leaderstats.Parent = player
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

task.spawn(function()
	while true do
		task.wait(1)
		for _, player in Players:GetPlayers() do
			local leaderstats = player:FindFirstChild("leaderstats")
			local gold = leaderstats and leaderstats:FindFirstChild("Gold")
			if gold and gold:IsA("IntValue") then
				gold.Value += GameConfig.StarterGoldPerSecond
			end
		end
	end
end)

print(`[{GameConfig.GameName}] server started`)
