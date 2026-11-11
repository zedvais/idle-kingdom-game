--!strict
-- Shared settings that both the server and the client read.
-- Numbers here come from the game design doc and are meant to be tuned.

local GameConfig = {}

GameConfig.GameName = "Idle Kingdom"

-- Temporary: gold every player earns per second until buildings exist.
GameConfig.StarterGoldPerSecond = 1

return GameConfig
