-- Raids, guilds and the realm map: everything that touches other players.
-- Numbers are in SocialConfig. Shared data lives in DataStores through
-- SharedStore:
--   Raid_Profiles  [userId] = what raiders see of you (published each minute)
--   Raid_Levels    ordered [userId] = level, to find targets near your level
--   Raid_Ledger    [userId] = { health, healthAt, hits = { ... } }: raids on you
--                  that your own server takes off your save
--   Guilds         [guild id] = the guild: members, experience, wall
--   Guild_Names    [lower case name] = guild id, so names are unique
--   Guild_Directory "list" = { [guild id] = summary } for browsing
--   Realm_Lands    [territory id] = who holds it, strength, garrison, forts
--                  (see the Realm map section)

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
		health = data.health,
		maxHealth = stats.maxHealth,
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
		health = GameConfig.BaseMaxHealth + 5 * level,
		maxHealth = GameConfig.BaseMaxHealth + 5 * level,
		healthAt = now(),
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
		health = profile.health or profile.maxHealth or GameConfig.BaseMaxHealth,
		maxHealth = profile.maxHealth or GameConfig.BaseMaxHealth,
		healthAt = profile.time or 0,
	}
end

-- A player's health now, from a known value at a time plus regen since.
local function healthNow(health: number, maxHealth: number, at: number): number
	local regen = math.max(0, now() - at) / GameConfig.HealthRegenSeconds
	return math.min(maxHealth, math.floor(health + regen))
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
		if userId ~= tostring(player.UserId) then
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
	if not target.npc and healthNow(target.health, target.maxHealth, target.healthAt) < GameConfig.MinHealthToFight then
		ctx.sendToast(player, `{target.name} is incapacitated: under {GameConfig.MinHealthToFight} health. Wait for them to recover.`)
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
		-- The victim's ledger decides: if they are already too wounded
		-- (other raids since you looked), the raid stops and stamina is
		-- not spent. Their health is tracked in the ledger between saves.
		local blocked = false
		local _, ok = SharedStore.update("Raid_Ledger", tostring(target.userId), function(ledger)
			ledger = if type(ledger) == "table" then ledger else { hits = {} }
			ledger.hits = ledger.hits or {}
			local health, at = target.health, target.healthAt
			if type(ledger.health) == "number" and (ledger.healthAt or 0) >= at then
				health, at = ledger.health, ledger.healthAt
			end
			local current = healthNow(health, target.maxHealth, at)
			if current < GameConfig.MinHealthToFight then
				blocked = true
				target.health, target.healthAt = current, now()
				return nil
			end
			blocked = false
			local damage = math.floor(target.maxHealth * random:NextNumber(table.unpack(if win then SocialConfig.WinDamage else SocialConfig.LossDamage)))
			ledger.health = math.max(0, current - damage)
			ledger.healthAt = now()
			target.health, target.healthAt = ledger.health, ledger.healthAt
			table.insert(ledger.hits, {
				from = player.DisplayName,
				fromId = player.UserId,
				win = win,
				gold = gold,
				stock = stock,
				attack = attackRoll,
				defense = defenseRoll,
				damage = damage,
				time = now(),
			})
			while #ledger.hits > 20 do
				table.remove(ledger.hits, 1)
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
			ctx.sendToast(player, `{target.name} is incapacitated: under {GameConfig.MinHealthToFight} health. Wait for them to recover.`)
			ctx.refresh(player)
			return
		end
	end
	mine.busy = false
	if not player.Parent then
		return
	end

	data.stamina -= SocialConfig.RaidStamina
	data.raid.cooldowns = {} -- no cooldowns: a keep can be hit until its lord is incapacitated
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
	-- an NPC keep leaves the list once raided; players stay until they
	-- are incapacitated
	if target.npc then
		for index, candidate in mine.targets do
			if candidate.id == target.id then
				table.remove(mine.targets, index)
				break
			end
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
		-- the ledger's health now follows your save again
		local damage = 0
		for _, hit in taken do
			damage += hit.damage or 0
		end
		ledger.health = math.max(0, data.health - damage)
		ledger.healthAt = now()
		return ledger
	end)
	if not player.Parent or #taken == 0 then
		return
	end
	local lostGold, held, fell = 0, 0, 0
	for _, hit in taken do
		local entry = { userId = hit.fromId, name = hit.from, time = hit.time, win = hit.win }
		table.insert(data.raid.attackers, 1, entry)
		data.health = math.max(0, data.health - (hit.damage or 0))
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
-- Realm_Lands [territory id] = {
--   holder = { id, name, tag } or nil, round (goes up whenever it changes
--   hands), since, strength + strengthAt (regen is worked out from these),
--   marked (flagged for defense), hitAt (last attacked),
--   forts = { [key] = { l = level, g = gold given, e = energy given } },
--   garrison = { [userId] = { n = name, c = soldiers, r = rarity rank sum, d = defense } },
--   residents = count, names = { [userId] = name } (the first few),
--   history = { { t, x } } newest first,
-- }
-- Attacks are added up on each server and sent every few seconds, so many
-- players can hit one territory without running into DataStore limits.

local lands = {} -- [territory id] = doc, as last read or written
local landsAt = 0
local landAt = {} -- [territory id] = os.clock() of the last read
local pending = {} -- [territory id] = { total, guilds = { [gid] = { d, name, tag, level } }, users = { [Player] = damage } }
local flushing = {}
local viewing = {} -- [Player] = territory id open in the popup

local function blankLand()
	return { round = 0, since = 0, strength = 0, strengthAt = 0, forts = {}, garrison = {}, residents = 0, names = {}, history = {}, marked = false, hitAt = 0 }
end

local function fixLand(doc)
	doc = if type(doc) == "table" then doc else blankLand()
	doc.round = doc.round or 0
	doc.forts = if type(doc.forts) == "table" then doc.forts else {}
	doc.garrison = if type(doc.garrison) == "table" then doc.garrison else {}
	doc.names = if type(doc.names) == "table" then doc.names else {}
	doc.history = if type(doc.history) == "table" then doc.history else {}
	doc.residents = math.max(0, doc.residents or 0)
	doc.policy = if type(doc.policy) == "table" then doc.policy else { mode = "open", level = 0, rent = 0 }
	doc.policy.rent = doc.policy.rent or 0
	doc.applicants = if type(doc.applicants) == "table" then doc.applicants else {}
	doc.approved = if type(doc.approved) == "table" then doc.approved else {}
	for _, fort in SocialConfig.Forts do
		doc.forts[fort.key] = doc.forts[fort.key] or { l = 0, g = 0, e = 0 }
	end
	return doc
end

local function resetForts(doc)
	-- a new holder starts with open residency and no applications
	doc.policy = { mode = "open", level = 0, rent = 0 }
	doc.applicants = {}
	doc.forts = {}
	for _, fort in SocialConfig.Forts do
		doc.forts[fort.key] = { l = 0, g = 0, e = 0 }
	end
end

local function fortLevel(doc, key: string): number
	return (doc.forts[key] and doc.forts[key].l) or 0
end

local function landMax(territory, doc): number
	return SocialConfig.maxStrength(territory.tier, fortLevel(doc, "walls"))
end

-- Strength now: the stored value plus regen since it was stored.
local function strengthNow(territory, doc, t: number): number
	if not doc.holder then
		return 0
	end
	local max = landMax(territory, doc)
	local rate = SocialConfig.regenRate(fortLevel(doc, "heal"))
	local elapsed = math.max(0, t - (doc.strengthAt or t))
	return math.min(max, (doc.strength or max) + max * rate * elapsed / 3600)
end

local function garrisonTotals(doc): (number, number)
	local count, ranks = 0, 0
	for _, entry in doc.garrison do
		count += entry.c or 0
		ranks += entry.r or 0
	end
	return count, ranks
end

local function landDefense(doc): number
	local _, ranks = garrisonTotals(doc)
	return SocialConfig.garrisonDefense(ranks, fortLevel(doc, "guard"))
end

local function addHistory(doc, text: string)
	table.insert(doc.history, 1, { t = now(), x = text })
	while #doc.history > SocialConfig.HistoryKept do
		table.remove(doc.history)
	end
end

local function guildLabel(guild): string
	return `[{guild.tag}] {guild.name}`
end

local function readLand(id: string)
	local doc, ok = SharedStore.get("Realm_Lands", id)
	if ok then
		lands[id] = fixLand(doc)
		landAt[id] = os.clock()
	end
end

local function refreshRealm(force: boolean?)
	if not force and os.clock() - landsAt < SocialConfig.RealmRefreshSeconds then
		return
	end
	landsAt = os.clock()
	for _, territory in SocialConfig.Territories do
		readLand(territory.id)
	end
end

local function landOf(id: string)
	return lands[id] or fixLand(nil)
end

-- Changes a territory with transform(doc) -> doc or nil (nil = no change).
-- Returns the new doc, or nil when nothing changed or the call failed.
local function changeLand(id: string, transform)
	local changed = false
	local doc, ok = SharedStore.update("Realm_Lands", id, function(old)
		changed = false
		local result = transform(fixLand(old))
		changed = result ~= nil
		return result
	end)
	if ok and changed and type(doc) == "table" then
		lands[id] = fixLand(doc)
		landAt[id] = os.clock()
		return lands[id]
	end
	return nil
end

local function heldBy(guildId: string): number
	local count = 0
	if guildId == "" then
		return 0
	end
	for _, doc in lands do
		if doc.holder and doc.holder.id == guildId then
			count += 1
		end
	end
	return count
end

local function myGuildLevel(data): number
	return data.guild.level or 1
end

local function territoryFrom(id: string)
	return SocialConfig.TerritoryById[id or ""]
end

-- Basic checks before a realm action that needs a guild and the tier's level.
local function canFight(player: Player, data, territory, what: string): boolean
	if data.guild.id == "" then
		ctx.sendToast(player, `Join or found a guild to {what} territories.`)
		return false
	end
	if what == "claim" then
		return true -- claiming has no level requirement
	end
	local tier = SocialConfig.Tiers[territory.tier]
	if data.level < tier.level then
		ctx.sendToast(player, `{tier.name} opens at level {tier.level}.`)
		return false
	end
	return true
end

-- A soldier back from the front goes into the first empty warband slot,
-- or waits (t = "") until there is one.
local function returnHome(data, entry): boolean
	for slot, soldier in data.crew do
		if soldier == false then
			data.crew[slot] = entry.s
			local index = table.find(data.realm.stationed, entry)
			if index then
				table.remove(data.realm.stationed, index)
			end
			return true
		end
	end
	entry.t = ""
	return false
end

local function placeWaiting(data)
	for _, entry in table.clone(data.realm.stationed) do
		if entry.t == "" then
			returnHome(data, entry)
		end
	end
end

local function claim(player: Player, data, id: string)
	local territory = territoryFrom(id)
	if not territory or not canFight(player, data, territory, "claim") then
		return
	end
	local tier = SocialConfig.Tiers[territory.tier]
	local doc = landOf(territory.id)
	if doc.holder then
		ctx.sendToast(player, `{territory.name} is held by {guildLabel(doc.holder)}. Attack it instead.`)
		return
	end
	local max = SocialConfig.maxHeld(myGuildLevel(data))
	if heldBy(data.guild.id) >= max then
		ctx.sendToast(player, `Your guild already holds {max} territories, its most at guild level {myGuildLevel(data)}.`)
		return
	end
	if not ctx.canAfford(data, tier.claim) then
		ctx.sendToast(player, `Claiming costs {Format.short(tier.claim)} gold.`)
		return
	end
	local mine = info(player)
	if mine.busy then
		return
	end
	mine.busy = true
	data.gold -= tier.claim -- taken first, given back if the claim fails
	local guild = { id = data.guild.id, name = data.guild.name, tag = data.guild.tag }
	local reason = ""
	local result = changeLand(territory.id, function(land)
		if land.holder then
			reason = "taken"
			return nil
		end
		land.holder = guild
		land.round += 1
		land.since = now()
		land.strength = SocialConfig.maxStrength(territory.tier, 0)
		land.strengthAt = now()
		land.garrison = {}
		land.marked = false
		resetForts(land)
		addHistory(land, `{guildLabel(guild)} claimed it ({player.DisplayName}).`)
		return land
	end)
	mine.busy = false
	if not result then
		data.gold += tier.claim
		ctx.sendToast(player, if reason == "taken" then `Someone claimed {territory.name} first.` else "The claim could not be sent right now. Try again.")
		ctx.refresh(player)
		return
	end
	data.realm.claims += 1
	ctx.sendFx(player, "realm", { territory = territory.id, kind = "claim" })
	ctx.sendToast(player, `{territory.name} is now held by {guildLabel(guild)}!`)
	ctx.refresh(player)
end

-- Damage one attack or siege does.
local function hitDamage(stats, doc, power: number): number
	local roll = random:NextNumber(SocialConfig.RollMin, SocialConfig.RollMax)
	return math.max(1, math.floor(stats.attack * power * roll / (1 + landDefense(doc))))
end

local flushLand -- below

local function attackLand(player: Player, data, id: string)
	local landId, kind = string.match(id or "", "^([%w]+):(%a+)$")
	local territory = territoryFrom(landId)
	if not territory or (kind ~= "attack" and kind ~= "siege") then
		return
	end
	if not canFight(player, data, territory, "attack") then
		return
	end
	local doc = landOf(territory.id)
	if not doc.holder then
		ctx.sendToast(player, `Nobody holds {territory.name}. Claim it instead.`)
		return
	end
	if doc.holder.id == data.guild.id then
		ctx.sendToast(player, "Your guild holds this territory.")
		return
	end
	if data.health < GameConfig.MinHealthToFight then
		ctx.sendToast(player, `You are too wounded to fight. You need {GameConfig.MinHealthToFight} health.`)
		return
	end
	local isSiege = kind == "siege"
	if isSiege and data.energy < SocialConfig.SiegeEnergy then
		ctx.sendToast(player, `A siege needs {SocialConfig.SiegeEnergy} energy.`)
		return
	elseif not isSiege and data.stamina < SocialConfig.AttackStamina then
		ctx.sendToast(player, "Not enough stamina. It refills over time.")
		return
	end
	local queued = pending[territory.id]
	local left = strengthNow(territory, doc, now()) - (if queued then queued.total else 0)
	if left <= 0 then
		ctx.sendToast(player, `{territory.name} is falling. Wait a moment.`)
		return
	end
	if isSiege then
		data.energy -= SocialConfig.SiegeEnergy
	else
		data.stamina -= SocialConfig.AttackStamina
	end
	local stats = ctx.getStats(data)
	local damage = hitDamage(stats, doc, if isSiege then SocialConfig.SiegePower else SocialConfig.AttackPower)
	queued = queued or { total = 0, guilds = {}, users = {} }
	pending[territory.id] = queued
	queued.total += damage
	local entry = queued.guilds[data.guild.id] or { d = 0, name = data.guild.name, tag = data.guild.tag, level = myGuildLevel(data) }
	entry.d += damage
	queued.guilds[data.guild.id] = entry
	queued.users[player] = (queued.users[player] or 0) + damage
	data.realm.attacks += 1
	data.raid.sieges += 1
	ctx.countLifetime(data, "sieges", 1)
	ctx.sendFx(player, "realm", { territory = territory.id, kind = kind, damage = damage, left = math.max(0, left - damage) })
	if left - damage <= 0 then
		task.spawn(flushLand, territory.id)
	end
	ctx.refresh(player)
end

-- Sends the attacks queued on this server for one territory.
flushLand = function(id: string)
	local queued = pending[id]
	if not queued or flushing[id] then
		return
	end
	flushing[id] = true
	pending[id] = nil
	local territory = territoryFrom(id)
	local captured, lostBy = nil, nil
	local result = changeLand(id, function(land)
		captured, lostBy = nil, nil
		if not land.holder then
			return nil -- it was given up meanwhile
		end
		local t = now()
		local total = 0
		local best, bestId = nil, nil
		for gid, entry in queued.guilds do
			if gid ~= land.holder.id then
				total += entry.d
				local room = heldBy(gid) < SocialConfig.maxHeld(entry.level or 1)
				if room and (not best or entry.d > best.d) then
					best = entry
					bestId = gid
				end
			end
		end
		if total <= 0 then
			return nil
		end
		local strength = strengthNow(territory, land, t) - total
		land.hitAt = t
		if strength > 0 then
			land.strength = strength
			land.strengthAt = t
			return land
		end
		lostBy = land.holder
		if best then
			captured = { id = bestId, name = best.name, tag = best.tag }
			land.holder = captured
			land.strength = SocialConfig.maxStrength(territory.tier, 0) * SocialConfig.CaptureStrength
			addHistory(land, `{guildLabel(captured)} captured it from {guildLabel(lostBy)}.`)
		else
			-- every attacking guild already holds its most: it falls empty
			land.holder = nil
			land.strength = 0
			addHistory(land, `{guildLabel(lostBy)} lost it. Nobody holds it now.`)
		end
		land.round += 1
		land.since = t
		land.strengthAt = t
		land.garrison = {}
		land.marked = false
		resetForts(land)
		return land
	end)
	flushing[id] = false
	if result == nil and lands[id] and lands[id].holder then
		-- the write failed: try again next time
		local again = pending[id] or { total = 0, guilds = {}, users = {} }
		again.total += queued.total
		for gid, entry in queued.guilds do
			local into = again.guilds[gid] or { d = 0, name = entry.name, tag = entry.tag, level = entry.level }
			into.d += entry.d
			again.guilds[gid] = into
		end
		for user, damage in queued.users do
			again.users[user] = (again.users[user] or 0) + damage
		end
		pending[id] = again
		return
	end
	if result and lostBy then
		for player, session in ctx.sessions do
			local data = session.data
			if captured and data.guild.id == captured.id then
				ctx.sendFx(player, "realm", { territory = id, kind = "capture" })
				ctx.sendToast(player, `Your guild captured {territory.name}!`)
				if queued.users[player] then
					data.realm.captures += 1
					ctx.addReport(data, {
						title = `Captured {territory.name}`,
						text = `Your guild took {territory.name} from {guildLabel(lostBy)}. You dealt {Format.short(queued.users[player])} damage in the final assault.`,
						win = true,
					})
				end
			elseif data.guild.id == lostBy.id then
				ctx.sendToast(player, `Your guild lost {territory.name}.`)
			end
			ctx.refresh(player)
		end
	end
end

local function flushAll()
	for id in pending do
		task.spawn(flushLand, id)
	end
end

local function station(player: Player, data, id: string)
	local landId, slotText = string.match(id or "", "^([%w]+):(%d+)$")
	local territory = territoryFrom(landId)
	local slot = tonumber(slotText)
	local soldier = slot and data.crew[slot]
	if not territory or not soldier then
		return
	end
	local doc = landOf(territory.id)
	if not doc.holder or doc.holder.id ~= data.guild.id then
		ctx.sendToast(player, "You can only station soldiers in your guild's territories.")
		return
	end
	local tier = SocialConfig.Tiers[territory.tier]
	if (garrisonTotals(doc)) >= tier.garrison then
		ctx.sendToast(player, `The garrison is full ({tier.garrison} soldiers).`)
		return
	end
	local mine = info(player)
	if mine.busy then
		return
	end
	mine.busy = true
	-- The soldier leaves the warband first so nothing else can use them.
	ctx.clearMember(data, slot)
	data.crew[slot] = false
	local _, defense = GameConfig.getSoldierStats(soldier)
	local rank = GameConfig.getRarityRank(soldier.rarity)
	local key = tostring(player.UserId)
	local round = doc.round
	local reason = ""
	local result = changeLand(territory.id, function(land)
		if not land.holder or land.holder.id ~= data.guild.id or land.round ~= round then
			reason = "lost"
			return nil
		end
		if (garrisonTotals(land)) >= tier.garrison then
			reason = "full"
			return nil
		end
		local entry = land.garrison[key] or { n = player.DisplayName, c = 0, r = 0, d = 0 }
		entry.n = player.DisplayName
		entry.c += 1
		entry.r += rank
		entry.d += defense
		land.garrison[key] = entry
		return land
	end)
	mine.busy = false
	if not result then
		local entry = { t = "", round = 0, s = soldier }
		table.insert(data.realm.stationed, entry)
		returnHome(data, entry)
		ctx.sendToast(player, if reason == "full" then "The garrison is full." elseif reason == "lost" then "Your guild no longer holds this territory." else "Could not station the soldier right now. Try again.")
		ctx.refresh(player)
		return
	end
	table.insert(data.realm.stationed, { t = territory.id, round = result.round, s = soldier })
	ctx.sendToast(player, `{soldier.name} now guards {territory.name}. Their gear is back in your armory.`)
	ctx.sendFx(player, "realm", { territory = territory.id, kind = "station" })
	ctx.refresh(player)
end

-- Takes your soldiers out of a garrison: all of them in a territory, or one.
local function removeFromGarrison(player: Player, data, id: string, entries): boolean
	local key = tostring(player.UserId)
	local rank, defense, count = 0, 0, 0
	for _, entry in entries do
		local _, soldierDefense = GameConfig.getSoldierStats(entry.s)
		rank += GameConfig.getRarityRank(entry.s.rarity)
		defense += soldierDefense
		count += 1
	end
	local result = changeLand(id, function(land)
		local entry = land.garrison[key]
		if not entry then
			return land -- already gone (captured): write nothing new
		end
		entry.c -= count
		entry.r -= rank
		entry.d -= defense
		if entry.c <= 0 then
			land.garrison[key] = nil
		end
		return land
	end)
	return result ~= nil
end

local function recall(player: Player, data, id: string)
	local landId, which = string.match(id or "", "^([%w]+):(%w+)$")
	local territory = territoryFrom(landId)
	if not territory then
		return
	end
	local entries = {}
	for index, entry in data.realm.stationed do
		if entry.t == territory.id and (which == "all" or tostring(index) == which) then
			table.insert(entries, entry)
		end
	end
	if #entries == 0 then
		return
	end
	local mine = info(player)
	if mine.busy then
		return
	end
	mine.busy = true
	local ok = removeFromGarrison(player, data, territory.id, entries)
	mine.busy = false
	if not ok then
		ctx.sendToast(player, "Could not recall right now. Try again.")
		return
	end
	local home, waiting = 0, 0
	for _, entry in entries do
		if returnHome(data, entry) then
			home += 1
		else
			waiting += 1
		end
	end
	ctx.sendToast(player, if waiting > 0 then `{home} back in the warband. {waiting} wait for a free warband slot.` else `{home} soldier{if home == 1 then "" else "s"} back in the warband.`)
	ctx.refresh(player)
end

local function moveOut(player: Player, old: string)
	if old ~= "" and territoryFrom(old) then
		local key = tostring(player.UserId)
		changeLand(old, function(land)
			land.residents = math.max(0, land.residents - 1)
			land.names[key] = nil
			return land
		end)
	end
end

local function addResident(land, key: string, name: string)
	land.residents += 1
	local named = 0
	for _ in land.names do
		named += 1
	end
	if named < SocialConfig.ResidentNamesKept then
		land.names[key] = name
	end
end

-- Territories that take residents by application: you apply, the
-- holder's leader or officers accept or turn you down.
local function applyToLive(player: Player, data, territory)
	if data.realm.applied == territory.id then
		ctx.sendToast(player, "Your application is waiting for an answer.")
		return
	end
	local key = tostring(player.UserId)
	local reason = ""
	local result = changeLand(territory.id, function(land)
		local count = 0
		for _ in land.applicants do
			count += 1
		end
		if count >= SocialConfig.ApplicantsKept then
			reason = "full"
			return nil
		end
		land.applicants[key] = { n = player.DisplayName, l = data.level, t = now() }
		return land
	end)
	if not result then
		ctx.sendToast(player, if reason == "full" then "Too many applications are waiting there. Try later." else "Could not apply right now. Try again.")
		return
	end
	data.realm.applied = territory.id
	ctx.sendToast(player, `You applied to live in {territory.name}. The holders will answer.`)
	ctx.refresh(player)
end

local function live(player: Player, data, id: string)
	local territory = territoryFrom(id)
	local old = data.realm.home
	if id ~= "" and not territory then
		return
	end
	if id == old then
		return
	end
	local key = tostring(player.UserId)
	if territory then
		local policy = landOf(territory.id).policy
		if policy.mode == "closed" then
			ctx.sendToast(player, `{territory.name} is closed to new residents.`)
			return
		end
		if data.level < (policy.level or 0) then
			ctx.sendToast(player, `{territory.name} takes residents from level {policy.level}.`)
			return
		end
		if policy.mode == "apply" then
			applyToLive(player, data, territory)
			return
		end
	end
	local mine = info(player)
	if mine.busy then
		return
	end
	mine.busy = true
	local full = false
	local ok = true
	if territory then
		ok = changeLand(territory.id, function(land)
			if land.residents >= SocialConfig.ResidentsMax then
				full = true
				return nil
			end
			land.residents += 1
			local named = 0
			for _ in land.names do
				named += 1
			end
			if named < SocialConfig.ResidentNamesKept then
				land.names[key] = player.DisplayName
			end
			return land
		end) ~= nil
	end
	if ok and old ~= "" and territoryFrom(old) then
		changeLand(old, function(land)
			land.residents = math.max(0, land.residents - 1)
			land.names[key] = nil
			return land
		end)
	end
	mine.busy = false
	if not ok then
		ctx.sendToast(player, if full then `{territory.name} is full ({SocialConfig.ResidentsMax} residents).` else "Could not move right now. Try again.")
		return
	end
	data.realm.home = id
	data.realm.rentPaid = 0
	ctx.sendToast(player, if territory then `You now live in {territory.name}.` else "You moved out.")
	ctx.refresh(player)
end

local function donate(player: Player, data, id: string)
	local landId, fortKey, what, amountText = string.match(id or "", "^([%w]+):(%a+):(%a+):(%d+)$")
	local territory = territoryFrom(landId)
	local amount = tonumber(amountText)
	local fortIndex = nil
	for index, fort in SocialConfig.Forts do
		if fort.key == fortKey then
			fortIndex = index
		end
	end
	if not territory or not fortIndex or not amount or amount < 1 or (what ~= "gold" and what ~= "energy") then
		return
	end
	local doc = landOf(territory.id)
	if not doc.holder or doc.holder.id ~= data.guild.id then
		ctx.sendToast(player, "Only your guild's territories can be fortified.")
		return
	end
	local fort = doc.forts[fortKey]
	if fort.l >= SocialConfig.FortMax then
		ctx.sendToast(player, "Fully built.")
		return
	end
	local needGold, needEnergy = SocialConfig.fortCost(territory.tier, fort.l)
	local room = if what == "gold" then needGold - fort.g else needEnergy - fort.e
	local have = if what == "gold" then math.floor(data.gold) else math.floor(data.energy)
	amount = math.min(amount, room, have)
	if amount <= 0 then
		ctx.sendToast(player, if room <= 0 then `This level has all the {what} it needs.` else `You have no {what} to give.`)
		return
	end
	local mine = info(player)
	if mine.busy then
		return
	end
	mine.busy = true
	if what == "gold" then
		data.gold -= amount
	else
		data.energy -= amount
	end
	local round = doc.round
	local leveled = false
	local given = 0
	local result = changeLand(territory.id, function(land)
		leveled = false
		given = 0
		if not land.holder or land.holder.id ~= data.guild.id or land.round ~= round then
			return nil
		end
		local target = land.forts[fortKey]
		if target.l >= SocialConfig.FortMax then
			return nil
		end
		local gold, energy = SocialConfig.fortCost(territory.tier, target.l)
		if what == "gold" then
			given = math.min(amount, gold - target.g)
			target.g += given
		else
			given = math.min(amount, energy - target.e)
			target.e += given
		end
		if given <= 0 then
			return nil
		end
		if target.g >= gold and target.e >= energy then
			target.l += 1
			target.g = 0
			target.e = 0
			leveled = true
			local name = SocialConfig.Tiers[territory.tier].forts[fortIndex]
			addHistory(land, `{name} reached level {target.l}.`)
		end
		return land
	end)
	mine.busy = false
	local refund = amount - (if result then given else 0)
	if what == "gold" then
		data.gold += refund
	else
		data.energy += refund
	end
	if not result then
		ctx.sendToast(player, "Could not donate right now. Try again.")
		ctx.refresh(player)
		return
	end
	data.realm.donated += if what == "gold" then given else 0
	local name = SocialConfig.Tiers[territory.tier].forts[fortIndex]
	ctx.sendFx(player, "realm", { territory = territory.id, kind = if leveled then "fortLevel" else "donate", fort = fortKey })
	ctx.sendToast(player, if leveled then `{name} is now level {result.forts[fortKey].l}!` else `Gave {Format.short(given)} {what} to the {name}.`)
	ctx.refresh(player)
end

local function isOfficer(player: Player, data): boolean
	local cached = guildCache[data.guild.id]
	local role = roleOf(cached and cached.doc, player.UserId)
	return role == "leader" or role == "officer"
end

-- Holder's leader or officers set who may live there:
-- "<territory>:<open|apply|closed>:<level>:<rent>". Rent is gold each
-- resident pays every two hours (members of the holding guild pay none).
local function setPolicy(player: Player, data, id: string)
	local landId, mode, levelText, rentText = string.match(id or "", "^([%w]+):(%a+):(%d+):(%d+)$")
	local territory = territoryFrom(landId)
	local level = tonumber(levelText)
	local rent = tonumber(rentText)
	if not territory or not level or not rent or (mode ~= "open" and mode ~= "apply" and mode ~= "closed") then
		return
	end
	if not isOfficer(player, data) then
		ctx.sendToast(player, "Only the guild leader and officers can set who lives here.")
		return
	end
	level = math.clamp(math.floor(level), 0, SocialConfig.ResidentLevelMax)
	rent = math.clamp(math.floor(rent), 0, SocialConfig.rentMax(territory.tier))
	local result = changeLand(territory.id, function(land)
		if not land.holder or land.holder.id ~= data.guild.id then
			return nil
		end
		land.policy = { mode = mode, level = level, rent = rent }
		if mode ~= "apply" then
			land.applicants = {}
		end
		return land
	end)
	if result then
		ctx.refresh(player)
	end
end

-- "<territory>:<userId>:yes|no" on an application.
local function answerApplicant(player: Player, data, id: string)
	local landId, userId, answer = string.match(id or "", "^([%w]+):(%d+):(%a+)$")
	local territory = territoryFrom(landId)
	if not territory or (answer ~= "yes" and answer ~= "no") then
		return
	end
	if not isOfficer(player, data) then
		return
	end
	local reason = ""
	local name = ""
	local result = changeLand(territory.id, function(land)
		reason = ""
		if not land.holder or land.holder.id ~= data.guild.id then
			return nil
		end
		local applicant = land.applicants[userId]
		if not applicant then
			return nil
		end
		name = applicant.n or "Someone"
		land.applicants[userId] = nil
		if answer == "yes" then
			if land.residents >= SocialConfig.ResidentsMax then
				reason = "full"
				return nil
			end
			addResident(land, userId, name)
			land.approved[userId] = true
		end
		return land
	end)
	if result then
		ctx.sendToast(player, if answer == "yes" then `{name} now lives in {territory.name}.` else `Turned down {name}.`)
		ctx.refresh(player)
	elseif reason == "full" then
		ctx.sendToast(player, `{territory.name} is full ({SocialConfig.ResidentsMax} residents).`)
	end
end

local function surrender(player: Player, data, id: string)
	local territory = territoryFrom(id)
	if not territory or data.guild.id == "" then
		return
	end
	if not isOfficer(player, data) then
		ctx.sendToast(player, "Only the guild leader and officers can give up a territory.")
		return
	end
	local guild = { id = data.guild.id, name = data.guild.name, tag = data.guild.tag }
	local result = changeLand(territory.id, function(land)
		if not land.holder or land.holder.id ~= guild.id then
			return nil
		end
		land.holder = nil
		land.round += 1
		land.since = now()
		land.strength = 0
		land.strengthAt = now()
		land.garrison = {}
		land.marked = false
		resetForts(land)
		addHistory(land, `{guildLabel(guild)} gave it up.`)
		return land
	end)
	if result then
		ctx.sendToast(player, `Your guild gave up {territory.name}.`)
		ctx.refresh(player)
	end
end

local function mark(player: Player, data, id: string)
	local territory = territoryFrom(id)
	if not territory or data.guild.id == "" then
		return
	end
	if not isOfficer(player, data) then
		ctx.sendToast(player, "Only the guild leader and officers can mark territories.")
		return
	end
	local result = changeLand(territory.id, function(land)
		if not land.holder or land.holder.id ~= data.guild.id then
			return nil
		end
		land.marked = not land.marked
		return land
	end)
	if result then
		ctx.sendToast(player, if result.marked then `{territory.name} is marked for defense.` else `{territory.name} is no longer marked.`)
		ctx.refresh(player)
	end
end

-- Keeps your stationed soldiers, home and stipend in line with the map.
local function syncRealm(player: Player, data)
	if landsAt == 0 then
		return
	end
	local came = {}
	local leave = {}
	for _, entry in table.clone(data.realm.stationed) do
		local doc = entry.t ~= "" and lands[entry.t]
		if doc then
			if doc.round ~= entry.round or not doc.holder then
				-- the territory changed hands: the garrison came home
				came[entry.t] = (came[entry.t] or 0) + 1
				entry.t = ""
			elseif doc.holder.id ~= data.guild.id then
				-- you left the guild that holds it
				leave[entry.t] = leave[entry.t] or {}
				table.insert(leave[entry.t], entry)
			end
		end
	end
	for id, entries in leave do
		if removeFromGarrison(player, data, id, entries) then
			for _, entry in entries do
				entry.t = ""
			end
		end
	end
	placeWaiting(data)
	-- An application answered on another server.
	local applied = data.realm.applied
	local appliedLand = applied ~= "" and lands[applied]
	if appliedLand then
		local key = tostring(player.UserId)
		local territory = territoryFrom(applied)
		if appliedLand.approved[key] then
			local old = data.realm.home
			data.realm.home = applied
			data.realm.applied = ""
			data.realm.rentPaid = 0
			changeLand(applied, function(land)
				land.approved[key] = nil
				return land
			end)
			if old ~= applied then
				moveOut(player, old)
			end
			ctx.sendToast(player, `Your application was accepted: you now live in {territory.name}.`)
		elseif not appliedLand.applicants[key] then
			data.realm.applied = ""
			ctx.sendToast(player, `Your application to live in {territory.name} was turned down.`)
		end
	elseif applied ~= "" and not territoryFrom(applied) then
		data.realm.applied = ""
	end
	for id, count in came do
		local territory = territoryFrom(id)
		ctx.sendToast(player, `{count} soldier{if count == 1 then "" else "s"} came home from {territory.name}: your guild lost it.`)
	end
	-- Rent: residents pay the holder's rent once every two hours while
	-- they play; it goes to the holding guild as guild experience. No gold
	-- for rent means moving out.
	local home = data.realm.home
	local homeLand = home ~= "" and lands[home]
	local rentPeriod = SocialConfig.stipendPeriod(now())
	if homeLand and data.realm.rentPaid < rentPeriod then
		data.realm.rentPaid = rentPeriod
		local holder = homeLand.holder
		local rent = homeLand.policy.rent or 0
		if holder and rent > 0 and holder.id ~= data.guild.id then
			local territory = territoryFrom(home)
			if data.gold >= rent then
				data.gold -= rent
				changeGuild(holder.id, function(guild)
					guild.xp = (guild.xp or 0) + rent // SocialConfig.DonateXpPer
					guild.rent = (guild.rent or 0) + rent
					return guild
				end)
				ctx.sendToast(player, `Paid {Format.short(rent)} gold rent for {territory.name}.`)
			else
				data.realm.home = ""
				moveOut(player, home)
				ctx.sendToast(player, `You could not pay the {Format.short(rent)} gold rent, so you moved out of {territory.name}.`)
			end
		end
	end
	-- Stipend: once every two hours while you play, for each territory
	-- your guild holds.
	local period = SocialConfig.stipendPeriod(now())
	if data.realm.stipendPaid < period then
		data.realm.stipendPaid = period
		local minutes, count = 0, 0
		for _, territory in SocialConfig.Territories do
			local doc = lands[territory.id]
			if doc and doc.holder and doc.holder.id == data.guild.id and data.guild.id ~= "" then
				minutes += SocialConfig.Tiers[territory.tier].stipendMinutes
				count += 1
			end
		end
		if minutes > 0 then
			local stats = ctx.getStats(data)
			local gold = math.floor(stats.incomePerHour * minutes / 60)
			if gold > 0 then
				data.gold += gold
				ctx.sendToast(player, `Realm stipend: +{Format.short(gold)} gold from {count} territor{if count == 1 then "y" else "ies"}.`)
			end
		end
	end
end

-- Bonuses from the realm: full for territories your guild holds, a share
-- for the one you live in (when someone else's guild holds it).
local function realmBonus(data)
	local bonus = {}
	local guildId = data.guild.id
	for _, territory in SocialConfig.Territories do
		local doc = lands[territory.id]
		if doc and doc.holder then
			local amount = 0
			if guildId ~= "" and doc.holder.id == guildId then
				amount = territory.amount
			elseif data.realm.home == territory.id then
				amount = territory.amount * SocialConfig.residentShare(fortLevel(doc, "homes"))
			end
			if amount > 0 then
				bonus[territory.bonus] = (bonus[territory.bonus] or 0) + amount
			end
		end
	end
	return bonus
end

-- What the Realm Map page needs.
local function realmState(player: Player, data)
	local t = now()
	local out = {}
	local scores = {}
	for _, territory in SocialConfig.Territories do
		local doc = landOf(territory.id)
		local queued = pending[territory.id]
		local count, ranks = garrisonTotals(doc)
		local forts = {}
		for _, fort in SocialConfig.Forts do
			forts[fort.key] = fortLevel(doc, fort.key)
		end
		local strength = strengthNow(territory, doc, t) - (if queued then queued.total else 0)
		out[territory.id] = {
			holder = doc.holder,
			strength = math.max(0, math.floor(strength)),
			max = landMax(territory, doc),
			regen = SocialConfig.regenRate(fortLevel(doc, "heal")),
			garrison = count,
			defense = SocialConfig.garrisonDefense(ranks, fortLevel(doc, "guard")),
			residents = doc.residents,
			marked = doc.marked == true,
			hot = t - (doc.hitAt or 0) < 300,
			since = doc.since or 0,
			forts = forts,
			policy = doc.policy,
		}
		if doc.holder then
			local score = scores[doc.holder.id] or { id = doc.holder.id, name = doc.holder.name, tag = doc.holder.tag, score = 0, held = 0 }
			score.score += SocialConfig.Tiers[territory.tier].points
			score.held += 1
			scores[doc.holder.id] = score
		end
	end
	local top = {}
	for _, score in scores do
		table.insert(top, score)
	end
	table.sort(top, function(a, b)
		return a.score > b.score
	end)
	while #top > 3 do
		table.remove(top)
	end
	-- Details of the territory open in the popup.
	local view = nil
	local viewId = viewing[player]
	if viewId and territoryFrom(viewId) then
		local doc = landOf(viewId)
		local garrison = {}
		for userId, entry in doc.garrison do
			table.insert(garrison, { userId = tonumber(userId), name = entry.n, count = entry.c, defense = entry.d })
		end
		table.sort(garrison, function(a, b)
			return a.defense > b.defense
		end)
		while #garrison > 12 do
			table.remove(garrison)
		end
		local names = {}
		for _, name in doc.names do
			table.insert(names, name)
		end
		table.sort(names)
		local forts = {}
		for _, fort in SocialConfig.Forts do
			local entry = doc.forts[fort.key]
			forts[fort.key] = { l = entry.l, g = entry.g, e = entry.e }
		end
		local applicants = {}
		for userId, entry in doc.applicants do
			table.insert(applicants, { userId = userId, name = entry.n, level = entry.l or 1, time = entry.t or 0 })
		end
		table.sort(applicants, function(a, b)
			return a.time < b.time
		end)
		view = { id = viewId, garrison = garrison, names = names, history = doc.history, forts = forts, round = doc.round, applicants = applicants }
	end
	local stationed = {}
	for index, entry in data.realm.stationed do
		local _, defense = GameConfig.getSoldierStats(entry.s)
		table.insert(stationed, { index = index, t = entry.t, name = entry.s.name, class = entry.s.class, rarity = entry.s.rarity, defense = defense })
	end
	local stats = ctx.getStats(data)
	local minutes = 0
	for _, territory in SocialConfig.Territories do
		local doc = lands[territory.id]
		if doc and doc.holder and data.guild.id ~= "" and doc.holder.id == data.guild.id then
			minutes += SocialConfig.Tiers[territory.tier].stipendMinutes
		end
	end
	return {
		lands = out,
		top = top,
		view = view,
		held = heldBy(data.guild.id),
		maxHeld = SocialConfig.maxHeld(myGuildLevel(data)),
		home = data.realm.home,
		applied = data.realm.applied,
		stationed = stationed,
		stipendIn = SocialConfig.StipendSeconds - t % SocialConfig.StipendSeconds,
		stipendNext = math.floor(stats.incomePerHour * minutes / 60),
		income = stats.incomePerHour,
		attackDamage = math.floor(stats.attack * SocialConfig.AttackPower),
		siegeDamage = math.floor(stats.attack * SocialConfig.SiegePower),
		guildId = data.guild.id,
		officer = data.guild.id ~= "" and isOfficer(player, data),
		attacks = data.realm.attacks,
		captures = data.realm.captures,
		loaded = landsAt > 0,
	}
end

local function viewLand(player: Player, data, id: string)
	if id == "" then
		viewing[player] = nil
		return
	end
	if not territoryFrom(id) then
		return
	end
	viewing[player] = id
	if os.clock() - (landAt[id] or 0) > SocialConfig.RealmViewSeconds then
		readLand(id)
	end
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
	-- Realm: send queued attacks, keep open territories fresh, and line up
	-- garrisons, homes and stipends with the map.
	task.spawn(function()
		local tick = 0
		while true do
			task.wait(SocialConfig.RealmFlushSeconds)
			tick += 1
			flushAll()
			local open = {}
			for player, id in viewing do
				if player.Parent then
					open[id] = open[id] or {}
					table.insert(open[id], player)
				else
					viewing[player] = nil
				end
			end
			for id, players in open do
				if os.clock() - (landAt[id] or 0) >= SocialConfig.RealmViewSeconds then
					task.spawn(function()
						readLand(id)
						for _, player in players do
							ctx.refresh(player)
						end
					end)
				end
			end
			if tick % 4 == 0 then
				for player, session in ctx.sessions do
					task.spawn(syncRealm, player, session.data)
				end
			end
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
	actions.RealmClaim = claim
	actions.RealmAttack = attackLand
	actions.RealmStation = station
	actions.RealmRecall = recall
	actions.RealmLive = live
	actions.RealmDonate = donate
	actions.RealmSurrender = surrender
	actions.RealmMark = mark
	actions.RealmPolicy = setPolicy
	actions.RealmAnswer = answerApplicant
	actions.RealmView = viewLand
	actions.RealmRefresh = function(player: Player, data)
		refreshRealm()
		syncRealm(player, data)
	end
end

function Social.onJoin(player: Player, data)
	info(player)
	task.spawn(function()
		collectRaids(player, data)
		syncGuild(player, data)
		syncRealm(player, data)
		if #info(player).targets == 0 and data.level >= SocialConfig.RaidMinLevel then
			lookForTargets(player, data)
		end
		publishProfile(player, data)
		ctx.refresh(player)
	end)
end

function Social.onLeave(player: Player, data)
	perPlayer[player] = nil
	viewing[player] = nil
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
	end
	for key, amount in realmBonus(data) do
		bonus[key] = (bonus[key] or 0) + amount
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
			revenge = target.revenge == true,
			health = healthNow(target.health, target.maxHealth, target.healthAt),
			maxHealth = target.maxHealth,
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

	return {
		raid = {
			targets = targets,
			lookIn = math.max(0, SocialConfig.RaidRefreshSeconds - (t - mine.lookedAt)),
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
		realm = realmState(player, data),
		socialBonus = Social.bonus(data),
	}
end

return Social
