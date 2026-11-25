-- Who wears which piece of gear, and what that gear adds up to.
--
-- data.gear holds two kinds of entries:
--   * spare stacks: identical items (same name, rarity and set; stats are
--     fixed by those) kept together with a `count`, so a player can own
--     millions of pieces without the save growing
--   * worn pieces: one item each (count 1) with `wornBy`: 0 means you, a
--     number from 1 up means the soldier in that warband slot
-- Gear only counts while someone wears it. Each person wears at most one
-- weapon, one armor and one mount.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local Loadout = {}

local function itemPower(item): number
	return item.attack + item.defense
end

-- Items that stack together: same name, rarity and set.
function Loadout.stackKey(item): string
	return `{item.name}|{item.rarity}|{item.set or ""}`
end

function Loadout.newUid(data): string
	local uid = "i" .. data.nextItemId
	data.nextItemId += 1
	return uid
end

-- How many pieces an entry holds (worn pieces and old saves count 1).
function Loadout.count(item): number
	return if type(item.count) == "number" and item.count >= 1 then item.count else 1
end

-- The spare stack for an item, or nil.
function Loadout.findStack(data, item)
	local key = Loadout.stackKey(item)
	for _, other in data.gear do
		if other.wornBy == nil and Loadout.stackKey(other) == key then
			return other
		end
	end
	return nil
end

-- Adds `count` copies of `item` to the spare stacks (merging into the
-- stack for that item). The price kept is the average. Returns the stack.
function Loadout.addSpare(data, item, count: number?)
	local amount = count or 1
	local stack = Loadout.findStack(data, item)
	if stack then
		local have = Loadout.count(stack)
		stack.price = math.floor(((stack.price or 0) * have + (item.price or 0) * amount) / (have + amount))
		stack.count = have + amount
		return stack
	end
	local fresh = table.clone(item)
	fresh.wornBy = nil
	fresh.sold = nil
	fresh.uid = Loadout.newUid(data)
	fresh.count = amount
	table.insert(data.gear, fresh)
	return fresh
end

-- Takes up to `amount` copies off a spare stack (removing it when empty).
-- Returns how many were taken.
function Loadout.takeSpare(data, stack, amount: number): number
	if stack.wornBy ~= nil then
		return 0
	end
	local have = Loadout.count(stack)
	local taken = math.min(have, math.max(0, math.floor(amount)))
	if taken >= have then
		local index = table.find(data.gear, stack)
		if index then
			table.remove(data.gear, index)
		end
	else
		stack.count = have - taken
	end
	return taken
end

-- A worn piece goes back to the spare stacks.
function Loadout.unwear(data, item)
	if item.wornBy == nil then
		return
	end
	item.wornBy = nil
	local stack = Loadout.findStack(data, item)
	if stack and stack ~= item then
		local index = table.find(data.gear, item)
		if index then
			table.remove(data.gear, index)
		end
		Loadout.addSpare(data, item, 1)
	else
		item.count = 1
	end
end

-- Total pieces owned (worn and spare).
function Loadout.total(data): number
	local total = 0
	for _, item in data.gear do
		total += Loadout.count(item)
	end
	return total
end

-- Merges loose spare pieces into stacks (older saves kept one entry each).
function Loadout.restack(data)
	local spares = {}
	for index = #data.gear, 1, -1 do
		local item = data.gear[index]
		if item.wornBy == nil then
			table.remove(data.gear, index)
			table.insert(spares, item)
		else
			item.count = 1
		end
	end
	for index = #spares, 1, -1 do
		local item = spares[index]
		Loadout.addSpare(data, item, Loadout.count(item))
	end
end

-- True when `member` is you (0) or a filled warband slot.
function Loadout.isMember(data, member: number?): boolean
	if member == 0 then
		return true
	end
	return type(member) == "number" and data.crew[member] ~= nil and data.crew[member] ~= false
end

-- Everyone who can wear gear: you first, then soldiers strongest first.
function Loadout.members(data): { number }
	local soldiers = {}
	for slot, soldier in data.crew do
		if soldier then
			local attack, defense = GameConfig.getSoldierStats(soldier)
			table.insert(soldiers, { slot = slot, power = attack + defense })
		end
	end
	table.sort(soldiers, function(a, b)
		if a.power ~= b.power then
			return a.power > b.power
		end
		return a.slot < b.slot
	end)
	local list = { 0 }
	for _, entry in soldiers do
		table.insert(list, entry.slot)
	end
	return list
end

-- Clears anything that no longer makes sense: gear worn by an empty slot,
-- or two pieces in one person's slot (the stronger one stays on).
function Loadout.tidy(data)
	local taken = {}
	local worn = {}
	local loose = {}
	for _, item in data.gear do
		if item.wornBy ~= nil then
			if Loadout.isMember(data, item.wornBy) then
				table.insert(worn, item)
			else
				table.insert(loose, item)
			end
		end
	end
	table.sort(worn, function(a, b)
		return itemPower(a) > itemPower(b)
	end)
	for _, item in worn do
		local key = `{item.wornBy}:{item.slot}`
		if taken[key] then
			table.insert(loose, item)
		else
			taken[key] = true
		end
	end
	for _, item in loose do
		Loadout.unwear(data, item)
	end
end

-- wearing[member][gearSlot] = item, for every member.
function Loadout.wearing(data)
	local wearing = {}
	for _, member in Loadout.members(data) do
		wearing[member] = {}
	end
	for _, item in data.gear do
		local member = item.wornBy
		if member ~= nil and wearing[member] then
			wearing[member][item.slot] = item
		end
	end
	return wearing
end

-- How many pieces of each set one person wears: { [setId] = count }.
local function setCounts(pieces)
	local counts = {}
	for _, item in pieces do
		if item.set then
			counts[item.set] = (counts[item.set] or 0) + 1
		end
	end
	return counts
end

-- An item's attack and defense on its wearer, with any set bonus.
function Loadout.itemStats(item, counts): (number, number)
	local bonus = if item.set then (GameConfig.SetPieceBonus[counts[item.set] or 0] or 0) else 0
	return math.floor(item.attack * (1 + bonus) + 0.5), math.floor(item.defense * (1 + bonus) + 0.5)
end

-- Everything gear adds up to:
--   attack, defense  total from worn gear, set bonuses included
--   wearing          see Loadout.wearing
--   sets             { ["0"] = { { set = "briar", count = 2 } } } per member,
--                    keyed by text so it can be sent to the client
--   perks            realm bonuses from full sets, once per set
--   fullSets         { [setId] = true } for every set someone wears in full
function Loadout.compute(data)
	local wearing = Loadout.wearing(data)
	local attack, defense = 0, 0
	local sets = {}
	local fullSets = {}
	for member, pieces in wearing do
		local counts = setCounts(pieces)
		for _, item in pieces do
			local itemAttack, itemDefense = Loadout.itemStats(item, counts)
			attack += itemAttack
			defense += itemDefense
		end
		local list = {}
		for setId, count in counts do
			table.insert(list, { set = setId, count = count })
			if count >= GameConfig.SetPieceCount then
				fullSets[setId] = true
			end
		end
		sets[tostring(member)] = list
	end

	local perks = { attack = 0, defense = 0, income = 0, xp = 0, questGold = 0 }
	for setId in fullSets do
		local set = GameConfig.getGearSet(setId)
		if set then
			for key, amount in set.perk do
				perks[key] = (perks[key] or 0) + amount
			end
		end
	end

	return {
		attack = attack,
		defense = defense,
		wearing = wearing,
		sets = sets,
		perks = perks,
		fullSets = fullSets,
	}
end

local function findItem(data, uid: string)
	for _, item in data.gear do
		if item.uid == uid then
			return item
		end
	end
	return nil
end
Loadout.findItem = findItem

-- Puts an item on a member. `uid` may be a spare stack (one copy is taken
-- off it) or a piece someone else wears (it moves). Whatever the member
-- wore in that slot goes back to the spare stacks.
-- Returns true and the item that was taken off (or nil), or false and a
-- reason, plus the piece now worn.
function Loadout.equip(data, uid: string, member: number)
	local item = findItem(data, uid)
	if not item then
		return false, "That item is gone."
	end
	if not Loadout.isMember(data, member) then
		return false, "Nobody is in that slot."
	end
	local removed = nil
	for _, other in table.clone(data.gear) do
		if other ~= item and other.wornBy == member and other.slot == item.slot then
			removed = other
			Loadout.unwear(data, other)
		end
	end
	local piece = item
	if item.wornBy == nil and Loadout.count(item) > 1 then
		item.count = Loadout.count(item) - 1
		piece = table.clone(item)
		piece.uid = Loadout.newUid(data)
		table.insert(data.gear, piece)
	end
	piece.count = 1
	piece.wornBy = member
	return true, removed, piece
end

function Loadout.unequip(data, uid: string): boolean
	local item = findItem(data, uid)
	if item and item.wornBy ~= nil then
		Loadout.unwear(data, item)
		return true
	end
	return false
end

-- Takes everything off one member (when a soldier is released).
function Loadout.clearMember(data, member: number)
	for _, item in table.clone(data.gear) do
		if item.wornBy == member then
			Loadout.unwear(data, item)
		end
	end
end

-- Takes everything off everyone; all of it goes back to the spare stacks.
function Loadout.unequipAll(data)
	for _, item in table.clone(data.gear) do
		Loadout.unwear(data, item)
	end
end

-- Swaps two warband slots: the soldiers and the gear they wear.
function Loadout.swapSlots(data, a: number, b: number)
	if a == b or data.crew[a] == nil or data.crew[b] == nil then
		return
	end
	data.crew[a], data.crew[b] = data.crew[b], data.crew[a]
	for _, item in data.gear do
		if item.wornBy == a then
			item.wornBy = b
		elseif item.wornBy == b then
			item.wornBy = a
		end
	end
end

-- Equip best: in each slot the strongest piece goes to you, the next to
-- your strongest soldier, and so on. Set bonuses are not considered, so
-- players who want sets equip those by hand.
function Loadout.autoEquip(data)
	local members = Loadout.members(data)
	for _, item in table.clone(data.gear) do
		Loadout.unwear(data, item)
	end
	for _, gearSlot in GameConfig.GearSlots do
		local stacks = {}
		for _, item in data.gear do
			if item.slot == gearSlot and item.wornBy == nil then
				table.insert(stacks, item)
			end
		end
		table.sort(stacks, function(a, b)
			return itemPower(a) > itemPower(b)
		end)
		local index = 1
		for _, member in members do
			local stack = stacks[index]
			while stack and Loadout.count(stack) <= 0 do
				index += 1
				stack = stacks[index]
			end
			if not stack then
				break
			end
			if stack.uid and findItem(data, stack.uid) == stack then
				local ok, _, piece = Loadout.equip(data, stack.uid, member)
				if ok and piece == stack then
					-- The last copy was worn; move on to the next stack.
					index += 1
				end
			end
		end
	end
end

-- A new item goes to the first person with that slot empty, so new gear
-- is never wasted. Returns who got it, or nil.
function Loadout.fillEmpty(data, item): number?
	local wearing = Loadout.wearing(data)
	for _, member in Loadout.members(data) do
		if not wearing[member][item.slot] then
			item.wornBy = member
			item.count = 1
			return member
		end
	end
	return nil
end

return Loadout
