-- Guild page (Arena).
-- Without a guild: a FOUND A GUILD card (name, tag, cost) and the list of
-- guilds to join.
-- In a guild: a banner with the guild's tag, name, level and experience
-- bar, the bonuses every member gets, a donate panel, the member list
-- (leaders can promote and remove), the guild wall, and Leave.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local SocialConfig = require(Shared:WaitForChild("SocialConfig"))
local Format = require(Shared:WaitForChild("Format"))
local Kit = require(script.Parent:WaitForChild("Kit"))
local Fx = require(script.Parent:WaitForChild("Fx"))

local GuildPage = {}

local MAX_MEMBERS = SocialConfig.BaseMembers + SocialConfig.MembersPerLevel * (#SocialConfig.Levels - 1)
local ROLE_GLYPHS = { leader = "\u{1F451}", officer = "\u{2B50}", member = "\u{1F6E1}\u{FE0F}" }

local w = {}
local listCards = {}
local memberRows = {}
local wallRows = {}
local lastState = nil
local leaveArmed = 0
local lastWallCount = -1

-- Makes player text safe inside rich text.
local function escape(text: string): string
	text = string.gsub(text, "&", "&amp;")
	text = string.gsub(text, "<", "&lt;")
	text = string.gsub(text, ">", "&gt;")
	return text
end

local function textBox(ui, parent: Instance, size: UDim2, position: UDim2, placeholder: string, max: number): TextBox
	local box = Instance.new("TextBox")
	box.Size = size
	box.Position = position
	box.BackgroundColor3 = Color3.fromRGB(18, 15, 12)
	box.TextColor3 = ui.colors.text
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = Color3.fromRGB(120, 110, 96)
	box.Font = Enum.Font.GothamBold
	box.TextSize = 15
	box.Text = ""
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Parent = parent
	ui.addCorner(box, 6)
	ui.art.stroke(box, ui.colors.dim, 1, 0.5)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.Parent = box
	box:GetPropertyChangedSignal("Text"):Connect(function()
		if #box.Text > max then
			box.Text = string.sub(box.Text, 1, max)
		end
	end)
	return box
end

local function section(ui, page: Instance, order: number): Frame
	local frame = ui.makeFrame(page, UDim2.new(1, -10, 0, 0), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	frame.BackgroundTransparency = 1
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.LayoutOrder = order
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame
	return frame
end

---------------------------------------------------------------------------
-- No guild: found one or join one
---------------------------------------------------------------------------

local function buildNoGuild(ui, page: Instance)
	local holder = section(ui, page, 2)
	w.noGuild = holder
	local found = ui.makeFrame(holder, UDim2.new(1, 0, 0, 150), UDim2.fromOffset(0, 0), Kit.CARD)
	found.LayoutOrder = 1
	ui.addCorner(found, 10)
	ui.art.stroke(found, ui.colors.gold, 2, 0.2)
	Kit.badge(ui, found, "\u{1F3F0}", 70, UDim2.fromOffset(16, 16), Color3.fromRGB(110, 80, 40))
	local title = ui.makeText(found, UDim2.new(1, -120, 0, 28), UDim2.fromOffset(100, 12), ui.colors.gold, 22)
	title.Font = ui.art.Fonts.heading
	title.Text = "Found a guild"
	local note = ui.makeText(found, UDim2.new(1, -120, 0, 18), UDim2.fromOffset(100, 40), ui.colors.dim, 12)
	note.Font = Enum.Font.GothamBold
	note.Text = `Level {SocialConfig.GuildMinLevel}+. Costs {Format.short(SocialConfig.GuildCost)} gold on hand. Names are checked by Roblox's filter.`
	w.nameBox = textBox(ui, found, UDim2.new(0.5, -110, 0, 40), UDim2.fromOffset(100, 70), `Guild name ({SocialConfig.GuildNameMin}-{SocialConfig.GuildNameMax})`, SocialConfig.GuildNameMax)
	w.tagBox = textBox(ui, found, UDim2.new(0.18, 0, 0, 40), UDim2.new(0.5, 0, 0, 70), `Tag ({SocialConfig.GuildTagMin}-{SocialConfig.GuildTagMax})`, SocialConfig.GuildTagMax)
	local create = ui.makeButton(found, UDim2.new(0.32, -24, 0, 40), UDim2.new(0.68, 10, 0, 70), ui.colors.claim)
	create.Font = Enum.Font.GothamBlack
	create.TextSize = 15
	create.Activated:Connect(function()
		local name = w.nameBox.Text
		local tag = w.tagBox.Text
		if #name > 0 and #tag > 0 then
			ui.send("GuildCreate", `{string.gsub(name, "|", "")}|{string.gsub(tag, "|", "")}`)
		end
	end)
	w.create = create
	local foundNote = ui.makeText(found, UDim2.new(1, -120, 0, 18), UDim2.fromOffset(100, 118), ui.colors.dim, 11)
	foundNote.Font = Enum.Font.GothamBold
	foundNote.Text = "Every guild level gives all members +2% income, +1% attack and +1% defense."

	local head = ui.makeFrame(holder, UDim2.new(1, 0, 0, 44), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	head.BackgroundTransparency = 1
	head.LayoutOrder = 2
	local label = ui.makeText(head, UDim2.new(1, -200, 1, 0), UDim2.fromOffset(4, 0), ui.colors.gold, 20)
	label.Font = ui.art.Fonts.heading
	label.Text = "Guilds of the realm"
	local refresh = ui.makeButton(head, UDim2.fromOffset(170, 36), UDim2.new(1, -170, 0, 4), ui.colors.action)
	refresh.Text = "\u{1F504} REFRESH"
	refresh.Font = Enum.Font.GothamBlack
	refresh.Activated:Connect(function()
		ui.send("GuildBrowse")
	end)
	local grid = ui.makeFrame(holder, UDim2.new(1, 0, 0, 0), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	grid.BackgroundTransparency = 1
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.LayoutOrder = 3
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(1 / 3, -10, 0, 128)
	layout.CellPadding = UDim2.fromOffset(12, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	for index = 1, SocialConfig.BrowseSize do
		local card, stroke = Kit.card(ui, grid, index, ui.colors.gold)
		card.Visible = false
		local tag = ui.makeText(card, UDim2.fromOffset(60, 60), UDim2.fromOffset(10, 10), Color3.new(1, 1, 1), 18)
		tag.BackgroundTransparency = 0
		tag.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
		tag.Font = Enum.Font.GothamBlack
		tag.TextXAlignment = Enum.TextXAlignment.Center
		ui.addCorner(tag, 30)
		ui.art.gloss(tag, 1, 0.6)
		local name = ui.makeText(card, UDim2.new(1, -86, 0, 22), UDim2.fromOffset(78, 12), ui.colors.text, 16)
		name.Font = Enum.Font.GothamBlack
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local sub = ui.makeText(card, UDim2.new(1, -86, 0, 36), UDim2.fromOffset(78, 36), ui.colors.dim, 12)
		sub.Font = Enum.Font.GothamBold
		sub.RichText = true
		local join = ui.makeButton(card, UDim2.new(1, -20, 0, 34), UDim2.new(0, 10, 1, -42), ui.colors.claim)
		join.Font = Enum.Font.GothamBlack
		local part = { card = card, stroke = stroke, tag = tag, name = name, sub = sub, join = join, id = nil }
		join.Activated:Connect(function()
			if part.id then
				Kit.pop(card, 1.06)
				ui.send("GuildJoin", part.id)
			end
		end)
		listCards[index] = part
	end
	w.listEmpty = ui.makeText(holder, UDim2.new(1, 0, 0, 40), UDim2.fromOffset(0, 0), ui.colors.dim, 14)
	w.listEmpty.LayoutOrder = 4
	w.listEmpty.TextXAlignment = Enum.TextXAlignment.Center
	w.listEmpty.Text = "No guilds yet. Found the first one!"
end

---------------------------------------------------------------------------
-- In a guild
---------------------------------------------------------------------------

local function buildInGuild(ui, page: Instance)
	local holder = section(ui, page, 3)
	w.inGuild = holder

	-- bonuses + donate
	local row = ui.makeFrame(holder, UDim2.new(1, 0, 0, 150), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	row.BackgroundTransparency = 1
	row.LayoutOrder = 1
	local perks = ui.makeFrame(row, UDim2.new(0.5, -6, 1, 0), UDim2.fromOffset(0, 0), Kit.CARD)
	ui.addCorner(perks, 10)
	ui.art.stroke(perks, Kit.GREEN, 1.5, 0.3)
	local perksTitle = ui.makeText(perks, UDim2.new(1, -24, 0, 26), UDim2.fromOffset(14, 8), Kit.GREEN, 18)
	perksTitle.Font = ui.art.Fonts.heading
	perksTitle.Text = "Every member gets"
	w.perks = ui.makeText(perks, UDim2.new(1, -24, 1, -42), UDim2.fromOffset(14, 36), ui.colors.text, 14)
	w.perks.Font = Enum.Font.GothamBold
	w.perks.RichText = true
	w.perks.TextYAlignment = Enum.TextYAlignment.Top

	local donate = ui.makeFrame(row, UDim2.new(0.5, -6, 1, 0), UDim2.new(0.5, 6, 0, 0), Kit.CARD)
	ui.addCorner(donate, 10)
	ui.art.stroke(donate, ui.colors.gold, 1.5, 0.3)
	local donateTitle = ui.makeText(donate, UDim2.new(1, -24, 0, 26), UDim2.fromOffset(14, 8), ui.colors.gold, 18)
	donateTitle.Font = ui.art.Fonts.heading
	donateTitle.Text = "Donate gold"
	local donateNote = ui.makeText(donate, UDim2.new(1, -24, 0, 18), UDim2.fromOffset(14, 34), ui.colors.dim, 12)
	donateNote.Font = Enum.Font.GothamBold
	donateNote.Text = `Every {SocialConfig.DonateXpPer} gold is 1 guild experience.`
	w.donateBox = textBox(ui, donate, UDim2.new(1, -28, 0, 36), UDim2.fromOffset(14, 56), "Amount of gold", 16)
	w.donateBox:GetPropertyChangedSignal("Text"):Connect(function()
		local digits = string.gsub(w.donateBox.Text, "%D", "")
		if digits ~= w.donateBox.Text then
			w.donateBox.Text = digits
		end
	end)
	local quick = { { "10%", 0.1 }, { "50%", 0.5 }, { "ALL", 1 } }
	for index, entry in quick do
		local button = ui.makeButton(donate, UDim2.new(0.2, -8, 0, 36), UDim2.new(0.2 * (index - 1), 14, 0, 100), ui.colors.row)
		button.Text = entry[1]
		button.Font = Enum.Font.GothamBlack
		button.Activated:Connect(function()
			if lastState then
				w.donateBox.Text = tostring(math.floor(lastState.gold * entry[2]))
			end
		end)
	end
	local give = ui.makeButton(donate, UDim2.new(0.4, -24, 0, 36), UDim2.new(0.6, 10, 0, 100), ui.colors.claim)
	give.Text = "\u{1F4B0} DONATE"
	give.Font = Enum.Font.GothamBlack
	give.Activated:Connect(function()
		local amount = tonumber(w.donateBox.Text)
		if amount and amount >= SocialConfig.DonateXpPer then
			Kit.pop(donate, 1.04)
			Kit.float(ui, donate, `+{Format.short(amount // SocialConfig.DonateXpPer)} XP`, Kit.GOLD)
			ui.send("GuildDonate", tostring(math.floor(amount)))
			w.donateBox.Text = ""
		end
	end)

	-- members
	local _, _, membersRight = Kit.heading(ui, holder, 2, "\u{1F465}  Members", ui.colors.gold)
	w.membersRight = membersRight
	local members = ui.makeFrame(holder, UDim2.new(1, 0, 0, 0), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	members.BackgroundTransparency = 1
	members.AutomaticSize = Enum.AutomaticSize.Y
	members.LayoutOrder = 3
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.5, -6, 0, 48)
	grid.CellPadding = UDim2.fromOffset(10, 6)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = members
	for index = 1, MAX_MEMBERS do
		local rowFrame = ui.makeFrame(members, UDim2.fromOffset(100, 48), UDim2.fromOffset(0, 0), Kit.CARD)
		rowFrame.LayoutOrder = index
		rowFrame.Visible = false
		ui.addCorner(rowFrame, 8)
		local stroke = ui.art.stroke(rowFrame, ui.colors.dim, 1, 0.5)
		local role = ui.makeText(rowFrame, UDim2.fromOffset(36, 48), UDim2.fromOffset(6, 0), Color3.new(1, 1, 1), 20)
		role.TextXAlignment = Enum.TextXAlignment.Center
		local name = ui.makeText(rowFrame, UDim2.new(1, -200, 0, 22), UDim2.fromOffset(44, 4), ui.colors.text, 14)
		name.Font = Enum.Font.GothamBlack
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local sub = ui.makeText(rowFrame, UDim2.new(1, -200, 0, 18), UDim2.fromOffset(44, 25), ui.colors.dim, 11)
		sub.Font = Enum.Font.GothamBold
		local promote = ui.makeButton(rowFrame, UDim2.fromOffset(70, 30), UDim2.new(1, -152, 0.5, -15), ui.colors.selected)
		promote.TextSize = 11
		promote.Font = Enum.Font.GothamBlack
		local kick = ui.makeButton(rowFrame, UDim2.fromOffset(70, 30), UDim2.new(1, -76, 0.5, -15), Kit.RED)
		kick.TextSize = 11
		kick.Font = Enum.Font.GothamBlack
		kick.Text = "REMOVE"
		local part = { row = rowFrame, stroke = stroke, role = role, name = name, sub = sub, promote = promote, kick = kick, userId = nil, armed = 0 }
		promote.Activated:Connect(function()
			if part.userId then
				ui.send("GuildRole", tostring(part.userId))
			end
		end)
		kick.Activated:Connect(function()
			if not part.userId then
				return
			end
			-- press twice to remove
			if os.clock() - part.armed < 3 then
				part.armed = 0
				ui.send("GuildKick", tostring(part.userId))
			else
				part.armed = os.clock()
				kick.Text = "SURE?"
				task.delay(3, function()
					kick.Text = "REMOVE"
				end)
			end
		end)
		memberRows[index] = part
	end

	-- wall
	Kit.heading(ui, holder, 4, "\u{1F4DC}  Guild wall", Color3.fromRGB(200, 160, 100))
	local wall = ui.makeFrame(holder, UDim2.new(1, 0, 0, 300), UDim2.fromOffset(0, 0), Color3.fromRGB(40, 32, 22))
	wall.LayoutOrder = 5
	ui.addCorner(wall, 10)
	ui.art.stroke(wall, Color3.fromRGB(150, 110, 60), 1.5, 0.3)
	ui.art.grain(wall)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -20, 1, -64)
	scroll.Position = UDim2.fromOffset(10, 10)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 5
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = wall
	local wallLayout = Instance.new("UIListLayout")
	wallLayout.Padding = UDim.new(0, 4)
	wallLayout.SortOrder = Enum.SortOrder.LayoutOrder
	wallLayout.Parent = scroll
	for index = 1, SocialConfig.WallKept do
		local line = ui.makeText(scroll, UDim2.new(1, -8, 0, 0), UDim2.fromOffset(0, 0), ui.colors.text, 14)
		line.AutomaticSize = Enum.AutomaticSize.Y
		line.RichText = true
		line.LayoutOrder = index
		line.Visible = false
		wallRows[index] = line
	end
	w.wallScroll = scroll
	w.wallEmpty = ui.makeText(wall, UDim2.new(1, -20, 0, 30), UDim2.fromOffset(10, 20), ui.colors.dim, 13)
	w.wallEmpty.TextXAlignment = Enum.TextXAlignment.Center
	w.wallEmpty.Text = "No messages yet. Say hello to your guild!"
	w.postBox = textBox(ui, wall, UDim2.new(1, -150, 0, 40), UDim2.new(0, 10, 1, -50), "Write to your guild...", SocialConfig.WallMax)
	local post = ui.makeButton(wall, UDim2.fromOffset(120, 40), UDim2.new(1, -130, 1, -50), ui.colors.action)
	post.Text = "POST"
	post.Font = Enum.Font.GothamBlack
	local function sendPost()
		local text = w.postBox.Text
		if #text > 0 then
			ui.send("GuildPost", text)
			w.postBox.Text = ""
		end
	end
	post.Activated:Connect(sendPost)
	w.postBox.FocusLost:Connect(function(enter)
		if enter then
			sendPost()
		end
	end)

	-- settings
	local bottom = ui.makeFrame(holder, UDim2.new(1, 0, 0, 44), UDim2.fromOffset(0, 0), Color3.new(0, 0, 0))
	bottom.BackgroundTransparency = 1
	bottom.LayoutOrder = 6
	local open = ui.makeButton(bottom, UDim2.fromOffset(220, 40), UDim2.fromOffset(0, 2), ui.colors.selected)
	open.Font = Enum.Font.GothamBlack
	open.Activated:Connect(function()
		ui.send("GuildOpen")
	end)
	w.open = open
	local leave = ui.makeButton(bottom, UDim2.fromOffset(200, 40), UDim2.new(1, -200, 0, 2), Kit.RED)
	leave.Font = Enum.Font.GothamBlack
	leave.Text = "LEAVE GUILD"
	leave.Activated:Connect(function()
		if os.clock() - leaveArmed < 3 then
			leaveArmed = 0
			ui.send("GuildLeave")
		else
			leaveArmed = os.clock()
			leave.Text = "PRESS AGAIN TO LEAVE"
			task.delay(3, function()
				leave.Text = "LEAVE GUILD"
			end)
		end
	end)
end

local function levelUpFx(ui, info)
	if not w.bannerFrame then
		return
	end
	Kit.pop(w.bannerFrame, 1.06)
	if info.level then
		Kit.float(ui, w.bannerFrame, `GUILD LEVEL {info.level}!`, Kit.GOLD)
	else
		Kit.float(ui, w.bannerFrame, `[{info.tag}] {info.name} FOUNDED!`, Kit.GOLD)
	end
end

function GuildPage.build(ui)
	local page = ui.pages.Guild
	local banner, title, icon = Kit.banner(ui, page, 1, 130, Color3.fromRGB(70, 60, 130), Color3.fromRGB(24, 20, 50), "Guild Hall", "\u{1F465}")
	w.bannerFrame = banner
	w.bannerTitle = title
	w.bannerIcon = icon
	w.bannerLine = Kit.line(ui, banner, 118, 64, UDim.new(0.5, -120), 15, Color3.new(1, 1, 1))
	w.bannerLine.Font = Enum.Font.GothamBlack
	w.xpBar = Kit.bar(ui, banner, UDim2.new(0.5, -130, 0, 20), UDim2.fromOffset(118, 94), Kit.GOLD)
	w.xpBar.back.ZIndex = 410
	w.xpBar.fill.ZIndex = 411
	w.xpBar.text.ZIndex = 412
	w.bannerNote = Kit.line(ui, banner, 0, 0, UDim.new(0.4, 0), 13, Color3.fromRGB(220, 215, 255))
	w.bannerNote.Position = UDim2.new(0.58, 0, 0, 36)
	w.bannerNote.Size = UDim2.new(0.4, -10, 0, 60)
	w.bannerNote.TextWrapped = true
	buildNoGuild(ui, page)
	buildInGuild(ui, page)
	Fx.handlers.guild = function(info)
		levelUpFx(ui, info)
	end
	page:GetPropertyChangedSignal("Visible"):Connect(function()
		if page.Visible then
			Kit.popAll(page)
			if lastState and not lastState.guild then
				ui.send("GuildBrowse")
			end
		end
	end)
end

function GuildPage.draw(state, ui)
	if not state or not state.raid then
		return
	end
	lastState = state
	local colors = ui.colors
	local guild = state.guild
	w.noGuild.Visible = guild == nil
	w.inGuild.Visible = guild ~= nil
	w.xpBar.back.Visible = guild ~= nil

	if not guild then
		w.bannerTitle.Text = "Guild Hall"
		w.bannerLine.Text = "You are not in a guild yet."
		w.bannerNote.Text = "Join a guild to share bonuses, chat on the guild wall and fight over the realm map together."
		local canFound = state.level >= SocialConfig.GuildMinLevel and state.gold >= SocialConfig.GuildCost
		ui.setButton(w.create, if state.level < SocialConfig.GuildMinLevel then `LEVEL {SocialConfig.GuildMinLevel}` else `FOUND  \u{1F4B0} {Format.short(SocialConfig.GuildCost)}`, canFound, colors.claim)
		local list = state.guildList or {}
		w.listEmpty.Visible = #list == 0
		for index, part in listCards do
			local entry = list[index]
			part.card.Visible = entry ~= nil
			if entry then
				part.id = entry.id
				part.tag.Text = entry.tag or "?"
				part.name.Text = entry.name or "Guild"
				local max = SocialConfig.maxMembers(entry.level or 1)
				part.sub.Text = `LEVEL <font color="#F0C450">{entry.level or 1}</font>  \u{2022}  {entry.members or 0} / {max} MEMBERS\n{if entry.open then "<font color=\"#6ED26E\">OPEN</font>" else "<font color=\"#E66A5A\">CLOSED</font>"}`
				local full = (entry.members or 0) >= max
				ui.setButton(part.join, if not entry.open then "CLOSED" elseif full then "FULL" else "JOIN", entry.open and not full, colors.claim)
			end
		end
		return
	end

	-- In a guild
	w.bannerTitle.Text = `[{guild.tag}] {guild.name}`
	local level = guild.level
	local nextNeed = SocialConfig.Levels[level + 1]
	w.bannerLine.Text = `LEVEL <font color="#F0C450">{level}</font>   \u{2022}   {#guild.members} / {guild.maxMembers} MEMBERS   \u{2022}   {if guild.open then "OPEN" else "CLOSED"}`
	if nextNeed then
		local base = SocialConfig.Levels[level]
		Kit.setBar(w.xpBar, guild.xp - base, nextNeed - base, `{Format.short(guild.xp)} / {Format.short(nextNeed)} XP`)
	else
		Kit.setBar(w.xpBar, 1, 1, "MAX LEVEL")
	end
	w.bannerNote.Text = `You are the guild's {guild.myRole}. Donate gold to level the guild and fight for the realm map together.`

	local bonus = state.socialBonus or {}
	local lines = {}
	for _, key in { "income", "attack", "defense", "xp", "questGold" } do
		local amount = bonus[key] or 0
		if amount > 0 then
			table.insert(lines, `<font color="#6ED26E">+{math.floor(amount * 1000 + 0.5) / 10}%</font> {SocialConfig.BonusNames[key]}`)
		end
	end
	if #lines == 0 then
		table.insert(lines, "Nothing yet. Level 2 gives +2% income, +1% attack and defense.")
	end
	table.insert(lines, `<font color="#B2A690">Includes territories your guild holds on the realm map.</font>`)
	w.perks.Text = table.concat(lines, "\n")

	w.membersRight.Text = `{#guild.members} / {guild.maxMembers}`
	local me = ui.player.UserId
	for index, part in memberRows do
		local member = guild.members[index]
		part.row.Visible = member ~= nil
		if member then
			part.userId = member.userId
			part.role.Text = ROLE_GLYPHS[member.role] or ""
			part.name.Text = if member.userId == me then `{member.name} (you)` else (member.name or "?")
			part.sub.Text = `{string.upper(member.role)}  \u{2022}  DONATED {Format.short(member.donated)}`
			part.stroke.Color = if member.userId == me then colors.gold else colors.dim
			local canManage = member.userId ~= me
				and member.role ~= "leader"
				and (guild.myRole == "leader" or (guild.myRole == "officer" and member.role == "member"))
			part.kick.Visible = canManage
			part.promote.Visible = canManage and guild.myRole == "leader"
			if part.promote.Visible then
				ui.setButton(part.promote, if member.role == "officer" then "DEMOTE" else "PROMOTE", true, colors.selected)
			end
		end
	end

	local wall = guild.wall or {}
	w.wallEmpty.Visible = #wall == 0
	for index, line in wallRows do
		local message = wall[index]
		line.Visible = message ~= nil
		if message then
			local stamp = os.date("!%H:%M", message.time or 0)
			line.Text = `<font color="#B2A690">{stamp}</font>  <font color="#F0C450"><b>{escape(message.name or "")}</b></font>  {escape(message.text or "")}`
		end
	end
	if #wall ~= lastWallCount then
		lastWallCount = #wall
		task.defer(function()
			w.wallScroll.CanvasPosition = Vector2.new(0, math.max(0, w.wallScroll.AbsoluteCanvasSize.Y))
		end)
	end
	w.open.Visible = guild.myRole == "leader"
	ui.setButton(w.open, if guild.open then "\u{1F513} OPEN TO ALL" else "\u{1F512} CLOSED", true, colors.selected)
end

return GuildPage
