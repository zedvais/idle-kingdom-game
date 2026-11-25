-- Who wears which piece of gear, and what that gear adds up to.
--
-- Each owned item may have `wornBy`: 0 means you, a number from 1 up means
-- the soldier in that warband slot, and nil means the item is spare.
-- Gear only counts while someone wears it. Each person wears at most one
-- weapon, one armor and one mount.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local Loadout = {}

local function itemPower(item): number
	return item.attack + item.defense
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
	for _, item in data.gear do
		if item.wornBy ~= nil then
			if Loadout.isMember(data, item.wornBy) then
				table.insert(worn, item)
			else
				item.wornBy = nil
			end
		end
	end
	table.sort(worn, function(a, b)
		return itemPower(a) > itemPower(b)
	end)
	for _, item in worn do
		local key = `{item.wornBy}:{item.slot}`
		if taken[key] then
			item.wornBy = nil
		else
			taken[key] = true
		end
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

-- Puts an item on a member. Whatever they wore in that slot becomes spare,
-- and if someone else wore this item, they now have that slot empty.
-- Returns the item that was taken off (or nil), or false and a reason.
function Loadout.equip(data, uid: string, member: number)
	local item = findItem(data, uid)
	if not item then
		return false, "That item is gone."
	end
	if not Loadout.isMember(data, member) then
		return false, "Nobody is in that slot."
	end
	local removed = nil
	for _, other in data.gear do
		if other ~= item and other.wornBy == member and other.slot == item.slot then
			other.wornBy = nil
			removed = other
		end
	end
	item.wornBy = member
	return true, removed
end

function Loadout.unequip(data, uid: string): boolean
	local item = findItem(data, uid)
	if item and item.wornBy ~= nil then
		item.wornBy = nil
		return true
	end
	return false
end

-- Takes everything off one member (when a soldier is released).
function Loadout.clearMember(data, member: number)
	for _, item in data.gear do
		if item.wornBy == member then
			item.wornBy = nil
		end
	end
end

-- Equip best: in each slot the strongest piece goes to you, the next to
-- your strongest soldier, and so on. Set bonuses are not considered, so
-- players who want sets equip those by hand.
function Loadout.autoEquip(data)
	local members = Loadout.members(data)
	for _, item in data.gear do
		item.wornBy = nil
	end
	for _, gearSlot in GameConfig.GearSlots do
		local pieces = {}
		for _, item in data.gear do
			if item.slot == gearSlot then
				table.insert(pieces, item)
			end
		end
		table.sort(pieces, function(a, b)
			return itemPower(a) > itemPower(b)
		end)
		for index, member in members do
			local piece = pieces[index]
			if piece then
				piece.wornBy = member
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
			return member
		end
	end
	return nil
end

return Loadout
