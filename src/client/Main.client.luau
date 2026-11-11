--!strict
-- Client entry point. Game UI will be started from here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

print(`[{GameConfig.GameName}] client started`)
