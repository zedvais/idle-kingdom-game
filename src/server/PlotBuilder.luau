-- Builds the physical village for one player out of simple block parts.
-- Art can replace these blocks later without touching the game rules.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local PlotBuilder = {}

local function makePart(parent: Instance, name: string, size: Vector3, position: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- A floating text sign above a part.
local function makeLabel(part: BasePart, height: number): TextLabel
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.fromOffset(170, 44)
	billboard.StudsOffset = Vector3.new(0, height, 0)
	billboard.MaxDistance = 400
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
	label.BackgroundTransparency = 0.3
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextWrapped = true
	label.Text = ""
	label.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 3)
	padding.PaddingBottom = UDim.new(0, 3)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = label

	return label
end

-- origin is the center of the plot at ground level.
function PlotBuilder.build(origin: Vector3, ownerName: string)
	local model = Instance.new("Model")
	model.Name = ownerName .. "Kingdom"

	local ground = makePart(model, "Ground", Vector3.new(100, 1, 110), origin + Vector3.new(0, 0.5, 0), Color3.fromRGB(196, 178, 128))
	ground.Material = Enum.Material.Sand

	local sign = makePart(model, "Sign", Vector3.new(24, 6, 1), origin + Vector3.new(0, 9, -50), Color3.fromRGB(110, 75, 45))
	sign.Material = Enum.Material.Wood
	local signLabel = makeLabel(sign, 6)
	signLabel.Text = ownerName .. "'s Kingdom"

	local plot = {
		model = model,
		origin = origin,
		buildings = {},
		units = {},
		war = nil,
	}

	-- Buildings: two rows of three.
	for index, building in GameConfig.Buildings do
		local column = (index - 1) % 3
		local row = math.floor((index - 1) / 3)
		local position = origin + Vector3.new((column - 1) * 30, 0, -34 + row * 26)

		local pad = makePart(model, building.id .. "Pad", Vector3.new(18, 1, 18), position + Vector3.new(0, 1.5, 0), Color3.fromRGB(120, 120, 120))
		local block = makePart(model, building.id, Vector3.new(9, 8, 9), position + Vector3.new(0, 6, 0), building.color)
		block.Material = Enum.Material.Wood

		plot.buildings[building.id] = {
			pad = pad,
			block = block,
			label = makeLabel(block, 7),
		}
	end

	-- Barracks: one small stand per unit type.
	for index, unit in GameConfig.Units do
		local position = origin + Vector3.new((index - 2.5) * 22, 0, 28)
		local stand = makePart(model, unit.id .. "Stand", Vector3.new(6, 6, 6), position + Vector3.new(0, 4, 0), unit.color)

		plot.units[unit.id] = {
			part = stand,
			label = makeLabel(stand, 6),
		}
	end

	-- War banner: where the player attacks the next land.
	local banner = makePart(model, "WarBanner", Vector3.new(4, 14, 4), origin + Vector3.new(0, 8, 46), Color3.fromRGB(170, 40, 40))
	plot.war = {
		part = banner,
		label = makeLabel(banner, 10),
	}

	model.Parent = workspace
	return plot
end

return PlotBuilder
