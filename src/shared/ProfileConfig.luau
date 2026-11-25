-- Profile, promo codes, rankings and mail.
-- Rewards use the same kinds as StoreConfig (crowns, gold, chest, xpBoost,
-- skill, tokens, energy, stamina, health, title, seals).

local ProfileConfig = {}

---------------------------------------------------------------------------
-- Promo codes
---------------------------------------------------------------------------
-- Players type a code on the Profile page. Each code works once per player.
-- Codes are not case sensitive. `ends` is a UTC time (os.time) after which
-- the code stops working, or 0 for never. Anyone who learns a code can use
-- it, so keep the rewards modest and give codes an end date.
ProfileConfig.Codes = {
	{
		code = "WELCOME",
		ends = 0,
		rewards = { { kind = "crowns", amount = 25 }, { kind = "energy" } },
	},
	{
		code = "LONGLIVETHEKING",
		ends = 0,
		rewards = { { kind = "tokens", amount = 15 }, { kind = "seals", amount = 5 } },
	},
}

-- Gives the code's settings, or nil. `text` is what the player typed.
function ProfileConfig.getCode(text: string)
	local wanted = string.upper((string.gsub(text, "%s", "")))
	for _, entry in ProfileConfig.Codes do
		if string.upper(entry.code) == wanted then
			return entry
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- Rankings: all-time boards shared by every server
---------------------------------------------------------------------------
-- stat is worked out on the server: power (attack + defense), level,
-- renown, rebirths. Each board keeps one score per player.
ProfileConfig.Boards = {
	{ key = "power", name = "Mightiest", note = "Attack plus defense" },
	{ key = "level", name = "Most experienced", note = "Highest level this life" },
	{ key = "renown", name = "Most renowned", note = "Renown from foes, all time" },
	{ key = "rebirths", name = "Most reborn", note = "Times reborn" },
}
ProfileConfig.BoardSize = 10
-- How often scores are written and boards are read, in seconds.
ProfileConfig.BoardSeconds = 120

---------------------------------------------------------------------------
-- Mail
---------------------------------------------------------------------------
-- Letters are kept newest first. Past this many, the oldest letter with
-- nothing left to claim is thrown away.
ProfileConfig.MailKept = 40

-- News letters reach every player once, the next time they join. Add one
-- to announce an update or hand out a gift. Never reuse an id.
ProfileConfig.News = {
	{
		id = "welcome",
		title = "A letter from the Royal Court",
		text = "Welcome to the realm, my liege. Quests earn gold, holdings earn while you rest, and foes guard the road to the Hollow Crown. Here is a little something to begin with.",
		rewards = { { kind = "gold", minutes = 30 }, { kind = "tokens", amount = 5 } },
	},
}

return ProfileConfig
