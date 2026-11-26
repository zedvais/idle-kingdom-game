-- Real art goes here. Every slot is "" for now, which means "keep using
-- the picture drawn in code". To use your own art:
--
--   1. Upload the image in Studio (Asset Manager > Images, or the
--      Toolbox), right click it and Copy Asset ID.
--   2. Paste it into a slot below, like  [1] = "rbxassetid://1234567890",
--
-- An animated picture is a sprite sheet: one image with every frame laid
-- out in a grid, left to right then top to bottom. Give it as a table:
--
--   [1] = { image = "rbxassetid://1234567890", frames = 8, columns = 4, fps = 10, width = 1024, height = 512 },
--
-- (frames = how many frames, columns = frames per row, fps = speed,
-- width / height = the whole sheet's size in pixels).
-- Roblox images are at most 1024 x 1024, so keep sheets inside that.
--
-- Sizes that fit well: Pictures 3:1 or wider (for example 900 x 300; the
-- Keep picture is cropped to fill its box), Icons and Items square
-- (256 x 256, transparent background).

local RunService = game:GetService("RunService")

local Assets = {}

-- Big animated scenes.
Assets.Pictures = {
	-- Keep levels 1 to 8 (Keep page, Estate banner).
	keep = {
		[1] = "", -- Timber Hall
		[2] = "", -- Palisade Fort
		[3] = "", -- Stone Tower
		[4] = "", -- Motte Castle
		[5] = "", -- Curtain-Wall Keep
		[6] = "", -- Fortress of the Vale
		[7] = "", -- Highcrown Citadel
		[8] = "", -- Sunspire Palace
	},
	-- Estate buildings.
	building = {
		lumbercamp = "",
		quarry = "",
		farm = "",
		mine = "",
		storehouse = "",
		granary = "",
		cellar = "",
		walls = "",
		towers = "",
	},
	-- Holdings.
	holding = {
		field = "",
		mill = "",
		tavern = "",
		smithy = "",
		quarry = "",
		tollbridge = "",
		markethall = "",
		glassworks = "",
		mint = "",
	},
}

-- Icons: menu, page headers, popup titles, top bar chips. Same names as
-- the emoji list in Art.luau (Art.Icons).
Assets.Icons = {
	Keep = "",
	Estate = "",
	Holdings = "",
	Research = "",
	Bank = "",
	Bounties = "",
	Festival = "",
	Quests = "",
	Foes = "",
	Expeditions = "",
	Rankings = "",
	Raids = "",
	["Realm Map"] = "",
	Guild = "",
	["War Chronicle"] = "",
	Warband = "",
	Barracks = "",
	Inventory = "",
	["Relic Hall"] = "",
	Market = "",
	["Royal Pass"] = "",
	Shop = "",
	Profile = "",
	Rebirth = "",
	Mail = "",
	Skills = "",
	Pass = "",
	gold = "",
	crowns = "",
	energy = "",
	stamina = "",
	health = "",
	xp = "",
}

-- Gear pictures by item name (Inventory, Market, Warband, Relic Hall,
-- drops). Any name from GameConfig works, for example:
--   ["Bastard Sword"] = "rbxassetid://1234567890",
Assets.Items = {}

-- Chest pictures, by rarity (won chests) or chest id (Market and Royal
-- Coffer chests: sack, strongbox, warchest, and the coffer keys).
Assets.Chests = {
	Common = "",
	Uncommon = "",
	Rare = "",
	Epic = "",
	Legendary = "",
	Mythic = "",
	Divine = "",
}

---------------------------------------------------------------------------
-- Helpers used by the drawing code. Nothing to edit below.
---------------------------------------------------------------------------

-- The slot's art, or nil when it is empty.
function Assets.get(group: string, key: any, subgroup: string?): any
	local list = Assets[group]
	if subgroup and list then
		list = list[subgroup]
	end
	local entry = list and list[key]
	if entry == nil or entry == "" then
		return nil
	end
	return entry
end

local sheets = {} -- animated ImageLabels
local sheetLoop = false

local function startSheets()
	if sheetLoop then
		return
	end
	sheetLoop = true
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		for index = #sheets, 1, -1 do
			local sheet = sheets[index]
			local label = sheet.label
			if not label.Parent then
				table.remove(sheets, index)
			elseif label.Visible then
				local frame = math.floor(t * sheet.fps) % sheet.frames
				local size = label.ImageRectSize
				label.ImageRectOffset = Vector2.new((frame % sheet.columns) * size.X, (frame // sheet.columns) * size.Y)
			end
		end
	end)
end

-- Puts the art in `parent`, filling it. crop = true fills the whole box
-- (cutting the edges off if the shape differs); otherwise it fits inside.
function Assets.show(parent: GuiObject, entry, crop: boolean?, name: string?): ImageLabel
	local label = Instance.new("ImageLabel")
	label.Name = name or "AssetArt"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.ScaleType = if crop then Enum.ScaleType.Crop else Enum.ScaleType.Fit
	label.ZIndex = parent.ZIndex + 1
	if type(entry) == "table" then
		label.Image = entry.image
		local frames = math.max(1, entry.frames or 1)
		local columns = math.max(1, entry.columns or frames)
		local rows = math.ceil(frames / columns)
		-- one frame's size in image pixels: the sheet size split by the grid
		local width = entry.width or 1024
		local height = entry.height or width
		label.ImageRectSize = Vector2.new(width / columns, height / rows)
		table.insert(sheets, { label = label, frames = frames, columns = columns, fps = entry.fps or 10 })
		startSheets()
	else
		label.Image = entry
	end
	label.Parent = parent
	return label
end

-- An emoji TextLabel that shows the icon art instead when the slot is set.
function Assets.icon(label: TextLabel, key: string, emoji: string)
	local old = label:FindFirstChild("AssetIcon")
	local entry = Assets.get("Icons", key)
	if not entry then
		if old then
			old:Destroy()
		end
		label.Text = emoji
		return
	end
	label.Text = ""
	if old and old:GetAttribute("Key") == key then
		return
	end
	if old then
		old:Destroy()
	end
	local art = Assets.show(label, entry, false, "AssetIcon")
	art:SetAttribute("Key", key)
end

return Assets
