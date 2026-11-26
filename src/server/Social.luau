-- Raids, guilds and the realm map: everything that touches other players.
-- Numbers are in SocialConfig. Shared data lives in DataStores through
-- SharedStore:
--   Raid_Profiles  [userId] = what raiders see of you (published each minute)
--   Raid_Levels    ordered [userId] = level, to find targets near your level
--   Raid_Ledger    [userId] = { shieldUntil, hits = { ... } }: raids on you
--                  that your own server takes off your save
--   Guilds         [guild id] = the guild: members, experience, wall
--   Guild_Names    [lower case name] = guild id, so names are unique
--   Guild_Directory "list" = { [guild id] = summary } for browsing
--   Realm_<week>   [territory id] = { scores = { [guild id] = { p, name, tag } } }

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local SocialConfig = require(Shared:WaitForChild("SocialConfig"))
local EstateConfig = require(Shared:WaitForChild("EstateConfig"))
local Format = require(Shared:WaitForChild("Format"))
local SharedStore = require(script.Parent:WaitForChild("SharedStore"))

local Social = {}

local ctx = nil -- helpers from Main (see Social.init)
local random = Random.new()
local perPlayer = {} -- [Player] = { targets, lookedAt, busy, guild (cached doc) }

local function now(): number
	return os.time()
end

local function info(player: Player)
	perPlayer[player] = perPlayer[player] or { targets = {}, lookedAt = 0, busy = false }
	return perPlayer[player]
end

-- Runs Roblox's text filter. Returns the filtered text, or nil if the
-- filter could not run (then the text is not used).
local function filterText(text: string, userId: number): string?
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(text, userId)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if ok then
		return result
	end
	if RunService:IsStudio() then
		return text -- the filter does not run in Studio
	end
	return nil
end

local function clean(text: string): string
	text = string.gsub(text, "[%c]", "")
	text = string.gsub(text, "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	text = string.gsub(text, "%s%s+", " ")
	return text
end

---------------------------------------------------------------------------
-- Raids
---------------------------------------------------------------------------

-- What raiders see of a player, published every minute and on leaving.
local function publishProfile(player: Player, data)
	if data.level < SocialConfig.RaidMinLevel then
		return
	end
	local stats = ctx.getStats(data)
	local summary = EstateConfig.summarize(data.estate.castles)
	SharedStore.set("Raid_Profiles", tostring(player.UserId), {
		name = player.DisplayName,
		user = player.Name,
		level = data.level,
		attack = stats.attack,
		defense = stats.defense,
		gold = math.floor(data.gold),
		stock = table.clone(data.estate.stock),
		cellar = summary.cellar,
		tag = data.guild.tag,
		time = now(),
	})
	SharedStore.setOrdered("Raid_Levels", tostring(player.UserId), data.level)
end

-- A computer-run keep near your level.
local function makeNpc(data, stats, index: number)
	local level = math.max(1, data.level + random:NextInteger(-2, 2))
	local power = SocialConfig.expectedPower(level)
	local defense = math.floor(power * random:NextNumber(0.7, 1.15))
	local gold = math.floor(math.max(500 * level, stats.incomePerHour * SocialConfig.NpcGoldMinutes / 60) * random:NextNumber(0.7, 1.3))
	local stock = {}
	for _, resource in EstateConfig.Resources do
		stock[resource.key] = math.floor(level * 60 * random:NextNumber(0.5, 1.5))
	end
	return {
		id = `npc{index}_{random:NextInteger(1, 1e6)}`,
		npc = true,
		name = SocialConfig.NpcNames[random:NextInteger(1, #SocialConfig.NpcNames)],
		level = level,
		attack = math.floor(power * random:NextNumber(0.7, 1.1)),
		defense = defense,
		gold = gold,
		stock = stock,
		cellar = 0,
		tag = "",
	}
end

local function targetFromProfile(userId: string, profile)
	return {
		id = "u" .. userId,
		userId = tonumber(userId),
		npc = false,
		name = profile.name or "Someone",
		user = profile.user,
		level = profile.level or 1,
		attack = profile.attack or 0,
		defense = profile.defense or 0,
		gold = math.max(0, profile.gold or 0),
		stock = profile.stock or {},
		cellar = profile.cellar or 0,
		tag = profile.tag or "",
		seen = profile.time or 0,
	}
end

-- Looks for players near your level, then fills up with NPC keeps.
local function lookForTargets(player: Player, data)
	local mine = info(player)
	local stats = ctx.getStats(data)
	local list = {}
	local range = SocialConfig.RaidLevelRange
	local found = SharedStore.range("Raid_Levels", 60, math.max(SocialConfig.RaidMinLevel, data.level - range), data.level + range)
	-- shuffle so everyone does not see the same few players
	for index = #found, 2, -1 do
		local other = random:NextInteger(1, index)
		found[index], found[other] = found[other], found[index]
	end
	local reads = 0
	for _, entry in found do
		if #list >= SocialConfig.RaidTargets or reads >= SocialConfig.RaidTargets + 4 then
			break
		end
		local userId = entry[1]
		if userId ~= tostring(player.UserId) and (data.raid.cooldowns["u" .. userId] or 0) <= now() then
			reads += 1
			local profile = SharedStore.get("Raid_Profiles", userId)
			if type(profile) == "table" and now() - (profile.time or 0) < 14 * 86400 then
				table.insert(list, targetFromProfile(userId, profile))
			end
		end
	end
	local index = 0
	while #list < SocialConfig.RaidTargets do
		index += 1
		table.insert(list, makeNpc(data, stats, index))
	end
	mine.targets = list
	mine.lookedAt = now()
end

-- Rolls one raid. Returns win, attack roll, defense roll.
local function rollRaid(attack: number, defense: number): (boolean, number, number)
	local attackRoll = math.floor(attack * random:NextNumber(SocialConfig.RollMin, SocialConfig.RollMax))
	local defenseRoll = math.floor(defense * random:NextNumber(SocialConfig.RollMin, SocialConfig.RollMax))
	return attackRoll > defenseRoll, attackRoll, defenseRoll
end

local function lootFor(target)
	local gold = math.floor(target.gold * SocialConfig.StealGold)
	local stock = {}
	local keep = math.clamp(target.cellar or 0, 0, 1)
	for _, resource in EstateConfig.Resources do
		local have = (target.stock or {})[resource.key] or 0
		stock[resource.key] = math.floor(math.max(0, have) * (1 - keep) * SocialConfig.StealResources)
	end
	return gold, stock
end

local function stockText(stock): string
	local parts = {}
	for _, resource in EstateConfig.Resources do
		local amount = stock[resource.key] or 0
		if amount > 0 then
			table.insert(parts, `{Format.short(amount)} {string.lower(resource.name)}`)
		end
	end
	return table.concat(parts, ", ")
end

local function raid(player: Player, data, targetId: string)
	local mine = info(player)
	if mine.busy then
		return
	end
	local target = nil
	for _, candidate in mine.targets do
		if candidate.id == targetId then
			target = candidate
		end
	end
	if not target then
		ctx.sendToast(player, "That target is gone. Look for new targets.")
		return
	end
	if data.level < SocialConfig.RaidMinLevel then
		ctx.sendToast(player, `Raids open at level {SocialConfig.RaidMinLevel}.`)
		return
	end
	if (data.raid.cooldowns[target.id] or 0) > now() then
		ctx.sendToast(player, `You raided {target.name} recently. Try someone else.`)
		return
	end
	if data.stamina < SocialConfig.RaidStamina then
		ctx.sendToast(player, "Not enough stamina. It refills over time.")
		return
	end
	if data.health < GameConfig.MinHealthToFight then
		ctx.sendToast(player, `You are too wounded. Rest until you have {GameConfig.MinHealthToFight} health.`)
		return
	end
	local stats = ctx.getStats(data)
	local win, attackRoll, defenseRoll = rollRaid(stats.attack, target.defense)
	local gold, stock = 0, {}
	if win then
		gold, stock = lootFor(target)
	end

	mine.busy = true
	if not target.npc then
		-- The victim's ledger decides: a shield that went up after you
		-- looked stops the raid, and stamina is not spent.
		local blocked = false
		local _, ok = SharedStore.update("Raid_Ledger", tostring(target.userId), function(ledger)
			ledger = if type(ledger) == "table" then ledger else { shieldUntil = 0, hits = {} }
			ledger.hits = ledger.hits or {}
			if (ledger.shieldUntil or 0) > now() then
				blocked = true
				return nil
			end
			blocked = false
			table.insert(ledger.hits, {
				from = player.DisplayName,
				fromId = player.UserId,
				win = win,
				gold = gold,
				stock = stock,
				attack = attackRoll,
				defense = defenseRoll,
				time = now(),
			})
			while #ledger.hits > 20 do
				table.remove(ledger.hits, 1)
			end
			if win then
				ledger.shieldUntil = now() + SocialConfig.ShieldSeconds
			end
			return ledger
		end)
		if not ok then
			mine.busy = false
			ctx.sendToast(player, "The raid could not reach that keep right now. Try again in a moment.")
			return
		end
		if blocked then
			mine.busy = false
			target.shielded = true
			ctx.sendToast(player, `{target.name} is under a shield after another raid. Try someone else.`)
			ctx.refresh(player)
			return
		end
	end
	mine.busy = false
	if not player.Parent then
		return
	end

	data.stamina -= SocialConfig.RaidStamina
	data.raid.cooldowns[target.id] = now() + SocialConfig.RaidCooldownSeconds
	for key, untilTime in data.raid.cooldowns do
		if untilTime <= now() then
			data.raid.cooldowns[key] = nil
		end
	end
	local maxHealth = stats.maxHealth
	data.health = math.max(0, data.health - math.floor(maxHealth * (if win then SocialConfig.WinHealthCost else SocialConfig.LossHealthCost)))
	ctx.countLifetime(data, "raids", 1)
	if win then
		data.raid.wins += 1
		data.raid.stolen += gold
		data.gold += gold
		ctx.countLifetime(data, "goldEarned", gold)
		data.renown += SocialConfig.WinRenown
		ctx.addStock(data, stock)
	else
		data.raid.losses += 1
	end
	-- the target leaves the list once raided
	for index, candidate in mine.targets do
		if candidate.id == target.id then
			table.remove(mine.targets, index)
			break
		end
	end
	local loot = stockText(stock)
	ctx.addReport(data, {
		title = if win then `Raid: you plundered {target.name}` else `Raid: {target.name} drove you off`,
		text = if win
			then `Your attack roll of {Format.short(attackRoll)} broke their defense of {Format.short(defenseRoll)}. You took {Format.short(gold)} gold{if loot ~= "" then ", " .. loot else ""}.`
			else `Your attack roll of {Format.short(attackRoll)} could not beat their defense of {Format.short(defenseRoll)}. You lost some health.`,
		win = win,
	})
	ctx.sendFx(player, "raid", {
		name = target.name,
		npc = target.npc,
		userId = target.userId,
		win = win,
		attack = attackRoll,
		defense = defenseRoll,
		gold = gold,
		loot = loot,
	})
end

-- Takes raids that happened to you off your save (from any server).
local function collectRaids(player: Player, data)
	local key = tostring(player.UserId)
	local peek = SharedStore.get("Raid_Ledger", key)
	if type(peek) ~= "table" then
		return
	end
	data.raid.shieldUntil = math.max(data.raid.shieldUntil, peek.shieldUntil or 0)
	if type(peek.hits) ~= "table" or #peek.hits == 0 then
		return
	end
	local taken = {}
	SharedStore.update("Raid_Ledger", key, function(ledger)
		if type(ledger) ~= "table" then
			return nil
		end
		taken = ledger.hits or {}
		ledger.hits = {}
		return ledger
	end)
	if not player.Parent or #taken == 0 then
		return
	end
	local lostGold, held, fell = 0, 0, 0
	for _, hit in taken do
		local entry = { userId = hit.fromId, name = hit.from, time = hit.time, win = hit.win }
		table.insert(data.raid.attackers, 1, entry)
		if hit.win then
			fell += 1
			local gold = math.min(math.max(0, data.gold), math.max(0, hit.gold or 0))
			data.gold -= gold
			lostGold += gold
			for resource, amount in hit.stock or {} do
				local have = data.estate.stock[resource]
				if type(have) == "number" and type(amount) == "number" then
					data.estate.stock[resource] = math.max(0, have - amount)
				end
			end
			ctx.addReport(data, {
				title = `Raided by {hit.from}`,
				text = `Their attack of {Format.short(hit.attack or 0)} beat your defense of {Format.short(hit.defense or 0)}. They took {Format.short(gold)} gold{if stockText(hit.stock or {}) ~= "" then ", " .. stockText(hit.stock) else ""}. Bank gold is always safe.`,
				win = false,
			})
		else
			held += 1
			ctx.addReport(data, {
				title = `You held off {hit.from}`,
				text = `Their attack of {Format.short(hit.attack or 0)} broke on your defense of {Format.short(hit.defense or 0)}.`,
				win = true,
			})
		end
	end
	while #data.raid.attackers > SocialConfig.AttackersKept do
		table.remove(data.raid.attackers)
	end
	data.raid.lost += lostGold
	data.raid.held += held
	data.raid.fell += fell
	if fell > 0 then
		ctx.sendToast(player, `You were raided {fell} time{if fell == 1 then "" else "s"} and lost {Format.short(lostGold)} gold. Bank your gold to keep it safe. Take revenge on the Raids page.`)
	end
	if held > 0 then
		ctx.sendToast(player, `Your walls held off {held} raid{if held == 1 then "" else "s"}!`)
	end
	ctx.refresh(player)
end

-- Puts a recent attacker at the top of your target list.
local function revenge(player: Player, data, userIdText: string)
	local userId = tonumber(userIdText)
	if not userId then
		return
	end
	local known = false
	for _, attacker in data.raid.attackers do
		if attacker.userId == userId then
			known = true
		end
	end
	if not known then
		return
	end
	local profile = SharedStore.get("Raid_Profiles", tostring(userId))
	if type(profile) ~= "table" then
		ctx.sendToast(player, "Their keep could not be found right now.")
		return
	end
	local mine = info(player)
	local target = targetFromProfile(tostring(userId), profile)
	target.revenge = true
	for index = #mine.targets, 1, -1 do
		if mine.targets[index].id == target.id then
			table.remove(mine.targets, index)
		end
	end
	table.insert(mine.targets, 1, target)
	ctx.sendToast(player, `{target.name} is at the top of your targets. Revenge is yours to take.`)
end

---------------------------------------------------------------------------
-- Guilds
---------------------------------------------------------------------------

local guildCache = {} -- [id] = { doc, at }
local directory = { list = {}, at = 0 }

local function memberCount(doc): number
	local count = 0
	for _ in doc.members or {} do
		count += 1
	end
	return count
end

local function summaryOf(doc)
	return {
		name = doc.name,
		tag = doc.tag,
		level = SocialConfig.getLevel(doc.xp or 0),
		xp = doc.xp or 0,
		members = memberCount(doc),
		open = doc.open ~= false,
	}
end

local function updateDirectory(id: string, doc)
	SharedStore.update("Guild_Directory", "list", function(list)
		list = if type(list) == "table" then list else {}
		list[id] = if doc then summaryOf(doc) else nil
		return list
	end)
	directory.at = 0
end

local function getGuild(id: string, fresh: boolean?)
	if id == "" then
		return nil
	end
	local cached = guildCache[id]
	if cached and not fresh and os.clock() - cached.at < SocialConfig.GuildRefreshSeconds then
		return cached.doc
	end
	local doc, ok = SharedStore.get("Guilds", id)
	if not ok then
		return if cached then cached.doc else nil
	end
	guildCache[id] = { doc = if type(doc) == "table" then doc else false, at = os.clock() }
	return guildCache[id].doc or nil
end

-- Changes a guild with transform(doc) -> doc or nil. Returns the new doc.
local function changeGuild(id: string, transform)
	local result, ok = SharedStore.update("Guilds", id, function(doc)
		if type(doc) ~= "table" then
			return nil
		end
		return transform(doc)
	end)
	if ok and type(result) == "table" then
		guildCache[id] = { doc = result, at = os.clock() }
		return result
	end
	return nil
end

local function setMembership(data, doc, id: string)
	if doc then
		data.guild.id = id
		data.guild.name = doc.name
		data.guild.tag = doc.tag
		data.guild.level = SocialConfig.getLevel(doc.xp or 0)
	else
		data.guild.id = ""
		data.guild.name = ""
		data.guild.tag = ""
		data.guild.level = 1
	end
end

-- Checks you are still in your guild (you may have been removed).
local function syncGuild(player: Player, data)
	local id = data.guild.id
	if id == "" then
		return
	end
	local doc = getGuild(id)
	if doc == nil and guildCache[id] and guildCache[id].doc == false then
		setMembership(data, nil, "")
		ctx.sendToast(player, "Your guild was disbanded.")
		return
	end
	if doc then
		if not (doc.members or {})[tostring(player.UserId)] then
			setMembership(data, nil, "")
			ctx.sendToast(player, "You are no longer in your guild.")
		else
			setMembership(data, doc, id)
		end
	end
end

local function validName(text: string, min: number, max: number, pattern: string): boolean
	return #text >= min and #text <= max and string.match(text, pattern) ~= nil
end

local function guildCreate(player: Player, data, id: string)
	local name, tag = string.match(id, "^(.-)|(.-)$")
	if not name then
		return
	end
	name = clean(name)
	tag = string.upper(clean(tag))
	if data.guild.id ~= "" then
		ctx.sendToast(player, "Leave your guild first.")
		return
	end
	if data.level < SocialConfig.GuildMinLevel then
		ctx.sendToast(player, `You can found a guild from level {SocialConfig.GuildMinLevel}.`)
		return
	end
	if not validName(name, SocialConfig.GuildNameMin, SocialConfig.GuildNameMax, "^[%w ']+$") then
		ctx.sendToast(player, `Guild names are {SocialConfig.GuildNameMin} to {SocialConfig.GuildNameMax} letters, numbers or spaces.`)
		return
	end
	if not validName(tag, SocialConfig.GuildTagMin, SocialConfig.GuildTagMax, "^%w+$") then
		ctx.sendToast(player, `Tags are {SocialConfig.GuildTagMin} to {SocialConfig.GuildTagMax} letters or numbers.`)
		return
	end
	if not ctx.canAfford(data, SocialConfig.GuildCost) then
		ctx.sendToast(player, `Founding a guild costs {Format.short(SocialConfig.GuildCost)} gold on hand.`)
		return
	end
	local mine = info(player)
	if mine.busy then
		return
	end
	mine.busy = true
	local filteredName = filterText(name, player.UserId)
	local filteredTag = filterText(tag, player.UserId)
	if filteredName ~= name or filteredTag ~= tag then
		mine.busy = false
		ctx.sendToast(player, "That name or tag is not allowed. Try another.")
		return
	end
	local guildId = `g{player.UserId}_{now()}`
	local taken = false
	local _, ok = SharedStore.update("Guild_Names", string.lower(name), function(owner)
		if type(owner) == "string" and owner ~= "" then
			taken = true
			return nil
		end
		taken = false
		return guildId
	end)
	if not ok or taken then
		mine.busy = false
		ctx.sendToast(player, if taken then "Another guild already has that name." else "Could not found the guild right now. Try again.")
		return
	end
	if not ctx.canAfford(data, SocialConfig.GuildCost) or data.guild.id ~= "" then
		SharedStore.remove("Guild_Names", string.lower(name))
		mine.busy = false
		return
	end
	local doc = {
		name = name,
		tag = tag,
		owner = player.UserId,
		created = now(),
		xp = 0,
		open = true,
		members = {
			[tostring(player.UserId)] = { name = player.DisplayName, role = "leader", joined = now(), donated = 0 },
		},
		wall = {},
	}
	if not SharedStore.set("Guilds", guildId, doc) then
		SharedStore.remove("Guild_Names", string.lower(name))
		mine.busy = false
		ctx.sendToast(player, "Could not found the guild right now. Try again.")
		return
	end
	data.gold -= SocialConfig.GuildCost
	guildCache[guildId] = { doc = doc, at = os.clock() }
	setMembership(data, doc, guildId)
	updateDirectory(guildId, doc)
	mine.busy = false
	ctx.sendToast(player, `[{tag}] {name} is founded! Invite friends to join from the guild list.`)
	ctx.sendFx(player, "guild", { name = name, tag = tag })
	ctx.refresh(player)
end

local function guildJoin(player: Player, data, id: string)
	if data.guild.id ~= "" then
		ctx.sendToast(player, "Leave your guild first.")
		return
	end
	local mine = info(player)
	if mine.busy then
		return
	end
	mine.busy = true
	local reason = nil
	local doc = changeGuild(id, function(guild)
		local level = SocialConfig.getLevel(guild.xp or 0)
		if guild.open == false then
			reason = "That guild is closed to new members."
			return nil
		end
		if memberCount(guild) >= SocialConfig.maxMembers(level) then
			reason = "That guild is full."
			return nil
		end
		reason = nil
		guild.members[tostring(player.UserId)] = { name = player.DisplayName, role = "member", joined = now(), donated = 0 }
		return guild
	end)
	mine.busy = false
	if not doc then
		ctx.sendToast(player, reason or "Could not join that guild right now.")
		return
	end
	setMembership(data, doc, id)
	updateDirectory(id, doc)
	ctx.sendToast(player, `Welcome to [{doc.tag}] {doc.name}!`)
	ctx.refresh(player)
end

local function guildLeave(player: Player, data)
	local id = data.guild.id
	if id == "" then
		return
	end
	local me = tostring(player.UserId)
	local empty = false
	local doc = changeGuild(id, function(guild)
		local wasLeader = guild.members[me] and guild.members[me].role == "leader"
		guild.members[me] = nil
		empty = next(guild.members) == nil
		if wasLeader and not empty then
			-- the longest serving officer, or member, leads now
			local best, bestKey = nil, nil
			for key, member in guild.members do
				local rank = if member.role == "officer" then 0 else 1
				if not best or rank < best[1] or (rank == best[1] and (member.joined or 0) < best[2]) then
					best = { rank, member.joined or 0 }
					bestKey = key
				end
			end
			if bestKey then
				guild.members[bestKey].role = "leader"
				guild.owner = tonumber(bestKey)
			end
		end
		return guild
	end)
	local name = data.guild.name
	setMembership(data, nil, "")
	if doc and empty then
		SharedStore.remove("Guilds", id)
		SharedStore.remove("Guild_Names", string.lower(doc.name))
		guildCache[id] = { doc = false, at = os.clock() }
		updateDirectory(id, nil)
	elseif doc then
		updateDirectory(id, doc)
	end
	ctx.sendToast(player, `You left {name}.`)
	ctx.refresh(player)
end

local function roleOf(doc, userId: number): string
	local member = doc and doc.members[tostring(userId)]
	return member and member.role or ""
end

local function guildKick(player: Player, data, id: string)
	local guildId = data.guild.id
	if guildId == "" or id == tostring(player.UserId) then
		return
	end
	local allowed = false
	local doc = changeGuild(guildId, function(guild)
		local myRole = roleOf(guild, player.UserId)
		local target = guild.members[id]
		allowed = target ~= nil and (myRole == "leader" or (myRole == "officer" and target.role == "member"))
		if not allowed then
			return nil
		end
		guild.members[id] = nil
		return guild
	end)
	if doc and allowed then
		updateDirectory(guildId, doc)
		ctx.sendToast(player, "Removed from the guild.")
	else
		ctx.sendToast(player, "You can not remove that member.")
	end
	ctx.refresh(player)
end

local function guildRole(player: Player, data, id: string)
	local guildId = data.guild.id
	if guildId == "" then
		return
	end
	changeGuild(guildId, function(guild)
		local target = guild.members[id]
		if roleOf(guild, player.UserId) ~= "leader" or not target or target.role == "leader" then
			return nil
		end
		target.role = if target.role == "officer" then "member" else "officer"
		return guild
	end)
	ctx.refresh(player)
end

local function guildOpen(player: Player, data)
	local guildId = data.guild.id
	if guildId == "" then
		return
	end
	local doc = changeGuild(guildId, function(guild)
		if roleOf(guild, player.UserId) ~= "leader" then
			return nil
		end
		guild.open = guild.open == false
		return guild
	end)
	if doc then
		updateDirectory(guildId, doc)
	end
	ctx.refresh(player)
end

local function guildDonate(player: Player, data, id: string)
	local guildId = data.guild.id
	local amount = math.floor(tonumber(id) or 0)
	if guildId == "" or amount < SocialConfig.DonateXpPer then
		return
	end
	if not ctx.canAfford(data, amount) then
		ctx.sendToast(player, "Not enough gold on hand.")
		return
	end
	local mine = info(player)
	if mine.busy then
		return
	end
	mine.busy = true
	local xp = amount // SocialConfig.DonateXpPer
	local me = tostring(player.UserId)
	local before = data.guild.level
	local doc = changeGuild(guildId, function(guild)
		if not guild.members[me] then
			return nil
		end
		guild.xp = (guild.xp or 0) + xp
		guild.members[me].donated = (guild.members[me].donated or 0) + amount
		return guild
	end)
	mine.busy = false
	if not doc then
		ctx.sendToast(player, "Could not donate right now.")
		return
	end
	if not ctx.canAfford(data, amount) then
		return -- spent meanwhile; the guild keeps the experience
	end
	data.gold -= amount
	setMembership(data, doc, guildId)
	updateDirectory(guildId, doc)
	ctx.sendToast(player, `Donated {Format.short(amount)} gold: +{Format.short(xp)} guild experience.`)
	if data.guild.level > before then
		ctx.sendFx(player, "guild", { name = doc.name, tag = doc.tag, level = data.guild.level })
	end
	ctx.refresh(player)
end

local function guildPost(player: Player, data, id: string)
	local guildId = data.guild.id
	local text = clean(id)
	if guildId == "" or #text == 0 then
		return
	end
	if #text > SocialConfig.WallMax then
		text = string.sub(text, 1, SocialConfig.WallMax)
	end
	if now() - data.guild.lastPost < SocialConfig.WallSeconds then
		ctx.sendToast(player, "Wait a few seconds before posting again.")
		return
	end
	data.guild.lastPost = now()
	local filtered = filterText(text, player.UserId)
	if not filtered then
		ctx.sendToast(player, "Your message could not be posted right now.")
		return
	end
	local me = tostring(player.UserId)
	changeGuild(guildId, function(guild)
		if not guild.members[me] then
			return nil
		end
		guild.wall = guild.wall or {}
		table.insert(guild.wall, { name = player.DisplayName, text = filtered, time = now() })
		while #guild.wall > SocialConfig.WallKept do
			table.remove(guild.wall, 1)
		end
		return guild
	end)
	ctx.refresh(player)
end

local function refreshDirectory(force: boolean?)
	if not force and os.clock() - directory.at < SocialConfig.GuildRefreshSeconds then
		return
	end
	local list, ok = SharedStore.get("Guild_Directory", "list")
	if not ok then
		return
	end
	local sorted = {}
	for id, summary in if type(list) == "table" then list else {} do
		local entry = table.clone(summary)
		entry.id = id
		table.insert(sorted, entry)
	end
	table.sort(sorted, function(a, b)
		return (a.xp or 0) > (b.xp or 0)
	end)
	while #sorted > SocialConfig.BrowseSize do
		table.remove(sorted)
	end
	directory.list = sorted
	directory.at = os.clock()
end

---------------------------------------------------------------------------
-- Realm map
---------------------------------------------------------------------------

local realm = { week = -1, current = {}, last = {}, at = 0 }

local function topOf(doc)
	local best, bestId = nil, nil
	for gid, score in (doc and doc.scores) or {} do
		if not best or score.p > best.p then
			best = score
			bestId = gid
		end
	end
	return bestId, best
end

local function refreshRealm(force: boolean?)
	local week = SocialConfig.getWeek(now())
	if not force and week == realm.week and os.clock() - realm.at < SocialConfig.RealmRefreshSeconds then
		return
	end
	local current, last = {}, {}
	for _, territory in SocialConfig.Territories do
		local doc = SharedStore.get(`Realm_{week}`, territory.id)
		current[territory.id] = if type(doc) == "table" then doc else { scores = {} }
		if week ~= realm.week or not realm.last[territory.id] then
			local old = SharedStore.get(`Realm_{week - 1}`, territory.id)
			last[territory.id] = if type(old) == "table" then old else { scores = {} }
		else
			last[territory.id] = realm.last[territory.id]
		end
	end
	realm = { week = week, current = current, last = last, at = os.clock() }
end

-- Bonuses your guild gets from the territories it holds this week.
local function realmBonus(guildId: string)
	local bonus = {}
	if guildId == "" then
		return bonus
	end
	for _, territory in SocialConfig.Territories do
		local holder = topOf(realm.last[territory.id])
		if holder == guildId then
			bonus[territory.bonus] = (bonus[territory.bonus] or 0) + territory.amount
		end
	end
	return bonus
end

local function siege(player: Player, data, territoryId: string)
	local territory = nil
	for _, candidate in SocialConfig.Territories do
		if candidate.id == territoryId then
			territory = candidate
		end
	end
	if not territory then
		return
	end
	if data.guild.id == "" then
		ctx.sendToast(player, "Join or found a guild to siege the realm.")
		return
	end
	if data.level < SocialConfig.SiegeMinLevel then
		ctx.sendToast(player, `Sieges open at level {SocialConfig.SiegeMinLevel}.`)
		return
	end
	if data.stamina < SocialConfig.SiegeStamina then
		ctx.sendToast(player, "Not enough stamina. It refills over time.")
		return
	end
	local mine = info(player)
	if mine.busy then
		return
	end
	mine.busy = true
	local stats = ctx.getStats(data)
	local points = SocialConfig.siegePoints(data.level, stats.attack)
	local guildId, name, tag = data.guild.id, data.guild.name, data.guild.tag
	local week = SocialConfig.getWeek(now())
	local doc, ok = SharedStore.update(`Realm_{week}`, territory.id, function(old)
		old = if type(old) == "table" then old else { scores = {} }
		old.scores = old.scores or {}
		local score = old.scores[guildId] or { p = 0, name = name, tag = tag }
		score.p += points
		score.name = name
		score.tag = tag
		old.scores[guildId] = score
		return old
	end)
	mine.busy = false
	if not ok then
		ctx.sendToast(player, "The siege could not be sent right now. Try again.")
		return
	end
	if not player.Parent then
		return
	end
	data.stamina -= SocialConfig.SiegeStamina
	data.raid.sieges += 1
	ctx.countLifetime(data, "sieges", 1)
	if realm.week == week and type(doc) == "table" then
		realm.current[territory.id] = doc
	end
	ctx.sendFx(player, "siege", { territory = territory.id, points = points })
	ctx.refresh(player)
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

-- ctx: getStats, sendToast, sendFx, addReport, refresh, countLifetime,
-- canAfford, track, addStock(data, stock), sessions.
function Social.init(context)
	ctx = context
	-- Raids on you, your guild and the realm, kept up to date.
	task.spawn(function()
		refreshRealm(true)
		refreshDirectory(true)
		local tick = 0
		while true do
			task.wait(SocialConfig.ProfileSeconds / 2)
			tick += 1
			for player, session in ctx.sessions do
				task.spawn(function()
					collectRaids(player, session.data)
					syncGuild(player, session.data)
					if tick % 2 == 0 then
						publishProfile(player, session.data)
					end
				end)
			end
			task.spawn(refreshRealm)
			task.spawn(refreshDirectory)
		end
	end)
end

function Social.register(actions)
	actions.RaidLook = function(player: Player, data)
		local mine = info(player)
		if now() - mine.lookedAt < SocialConfig.RaidRefreshSeconds and #mine.targets > 0 then
			ctx.sendToast(player, "Scouts are still out. New targets in a few seconds.")
			return
		end
		if mine.busy then
			return
		end
		mine.busy = true
		lookForTargets(player, data)
		mine.busy = false
	end
	actions.Raid = raid
	actions.RaidRevenge = revenge
	actions.GuildCreate = guildCreate
	actions.GuildJoin = guildJoin
	actions.GuildLeave = function(player: Player, data)
		guildLeave(player, data)
	end
	actions.GuildKick = guildKick
	actions.GuildRole = guildRole
	actions.GuildOpen = function(player: Player, data)
		guildOpen(player, data)
	end
	actions.GuildDonate = guildDonate
	actions.GuildPost = guildPost
	actions.GuildBrowse = function()
		refreshDirectory(true)
	end
	actions.Siege = siege
	actions.RealmRefresh = function()
		refreshRealm(true)
	end
end

function Social.onJoin(player: Player, data)
	info(player)
	task.spawn(function()
		collectRaids(player, data)
		syncGuild(player, data)
		if #info(player).targets == 0 and data.level >= SocialConfig.RaidMinLevel then
			lookForTargets(player, data)
		end
		publishProfile(player, data)
		ctx.refresh(player)
	end)
end

function Social.onLeave(player: Player, data)
	perPlayer[player] = nil
	publishProfile(player, data)
end

-- Bonuses from your guild's level and its territories, added to research
-- and gear set bonuses ({ income, attack, defense, xp, questGold }).
function Social.bonus(data)
	local bonus = {}
	if data.guild and data.guild.id ~= "" then
		for key, amount in SocialConfig.guildBonus(data.guild.level or 1) do
			bonus[key] = (bonus[key] or 0) + amount
		end
		for key, amount in realmBonus(data.guild.id) do
			bonus[key] = (bonus[key] or 0) + amount
		end
	end
	return bonus
end

-- What the Raids, Guild and Realm pages need.
function Social.state(player: Player, data)
	local mine = info(player)
	local t = now()
	local targets = {}
	for _, target in mine.targets do
		table.insert(targets, {
			id = target.id,
			userId = target.userId,
			npc = target.npc,
			name = target.name,
			level = target.level,
			defense = target.defense,
			gold = target.gold,
			tag = target.tag,
			shielded = target.shielded == true,
			revenge = target.revenge == true,
			cooldown = math.max(0, (data.raid.cooldowns[target.id] or 0) - t),
		})
	end

	local guild = nil
	if data.guild.id ~= "" then
		-- cache only: state is built often and must not wait on DataStores
		local cached = guildCache[data.guild.id]
		local doc = cached and cached.doc
		if doc then
			local members = {}
			for key, member in doc.members or {} do
				table.insert(members, {
					userId = tonumber(key),
					name = member.name,
					role = member.role,
					donated = member.donated or 0,
					joined = member.joined or 0,
				})
			end
			table.sort(members, function(a, b)
				local order = { leader = 0, officer = 1, member = 2 }
				if order[a.role] ~= order[b.role] then
					return (order[a.role] or 3) < (order[b.role] or 3)
				end
				return a.donated > b.donated
			end)
			local level = SocialConfig.getLevel(doc.xp or 0)
			guild = {
				id = data.guild.id,
				name = doc.name,
				tag = doc.tag,
				xp = doc.xp or 0,
				level = level,
				open = doc.open ~= false,
				members = members,
				maxMembers = SocialConfig.maxMembers(level),
				wall = doc.wall or {},
				myRole = roleOf(doc, player.UserId),
			}
		end
	end

	local territories = {}
	for _, territory in SocialConfig.Territories do
		local holderId, holder = topOf(realm.last[territory.id])
		local scores = {}
		for gid, score in (realm.current[territory.id] or {}).scores or {} do
			table.insert(scores, { id = gid, name = score.name, tag = score.tag, p = score.p })
		end
		table.sort(scores, function(a, b)
			return a.p > b.p
		end)
		local mineScore = 0
		for _, score in scores do
			if score.id == data.guild.id then
				mineScore = score.p
			end
		end
		while #scores > 3 do
			table.remove(scores)
		end
		territories[territory.id] = {
			holder = if holder then { id = holderId, name = holder.name, tag = holder.tag } else nil,
			leaders = scores,
			mine = mineScore,
		}
	end

	local stats = ctx.getStats(data)
	return {
		raid = {
			targets = targets,
			lookIn = math.max(0, SocialConfig.RaidRefreshSeconds - (t - mine.lookedAt)),
			shieldLeft = math.max(0, data.raid.shieldUntil - t),
			wins = data.raid.wins,
			losses = data.raid.losses,
			held = data.raid.held,
			fell = data.raid.fell,
			stolen = data.raid.stolen,
			lost = data.raid.lost,
			attackers = data.raid.attackers,
			online = not SharedStore.isMemory(),
		},
		guild = guild,
		guildList = directory.list,
		realm = {
			week = realm.week,
			secondsLeft = SocialConfig.getWeekSecondsLeft(t),
			territories = territories,
			points = SocialConfig.siegePoints(data.level, stats.attack),
			sieges = data.raid.sieges,
		},
		socialBonus = Social.bonus(data),
	}
end

return Social
