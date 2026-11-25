-- Rebirth: start over from level 1 for Stars that give lasting bonuses.
--
-- What a rebirth resets: level, experience, skill points and skills, gold on
-- hand and in the bank, holdings, the Keep, quest mastery and foe stages.
-- What it keeps: warband, gear, trophies, research, relics, game passes,
-- Crowns, boss tokens, Seals, titles and everything bought with Robux.

local RebirthConfig = {}

-- Level needed for a rebirth.
RebirthConfig.MinLevel = 40

-- Stars for one rebirth: 1 at MinLevel, +1 for every LevelsPerStar above it.
RebirthConfig.LevelsPerStar = 5

-- What each Star adds, for good.
RebirthConfig.PerStar = {
	income = 0.1, -- holding income
	questGold = 0.1,
	xp = 0.05, -- quest XP
	attack = 0.03,
	defense = 0.03,
}

-- Extra gold to start each new life with, per Star.
RebirthConfig.StartGoldPerStar = 2000

function RebirthConfig.getStars(level: number): number
	if level < RebirthConfig.MinLevel then
		return 0
	end
	return 1 + math.floor((level - RebirthConfig.MinLevel) / RebirthConfig.LevelsPerStar)
end

-- Title earned for a number of rebirths, e.g. "Reborn III".
local NUMERALS = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }
function RebirthConfig.getTitle(count: number): string
	return "Reborn " .. (NUMERALS[count] or tostring(count))
end

return RebirthConfig
