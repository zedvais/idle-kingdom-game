-- Mail page: letters from the court (news, festival rewards, trophies,
-- rebirths). Letters can carry rewards to claim.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local StoreConfig = require(Shared:WaitForChild("StoreConfig"))
local ProfileConfig = require(Shared:WaitForChild("ProfileConfig"))

local MailPage = {}

local summary
local buttons
local rows = {}
local readSentAt = 0

local function ago(seconds: number): string
	if seconds < 60 then
		return "just now"
	elseif seconds < 3600 then
		return `{math.floor(seconds / 60)}m ago`
	elseif seconds < 86400 then
		return `{math.floor(seconds / 3600)}h ago`
	end
	return `{math.floor(seconds / 86400)}d ago`
end

function MailPage.build(ui)
	local page = ui.pages.Mail
	summary = ui.makeRow(page, ui.nextOrder(), 40, false)
	summary.RichText = true
	buttons = ui.makeButtonRow(page, ui.nextOrder(), "", { "Claim all", "Delete read letters" })
	buttons[1].Activated:Connect(function()
		ui.send("MailClaim", "all")
	end)
	buttons[2].Activated:Connect(function()
		ui.send("MailDelete", "read")
	end)

	for index = 1, ProfileConfig.MailKept do
		local info, button = ui.makeRow(page, ui.nextOrder(), 78, true)
		info.RichText = true
		info.TextSize = 13
		info.TextYAlignment = Enum.TextYAlignment.Top
		local entry = { info = info, button = button, id = nil, claimable = false }
		rows[index] = entry
		button.Activated:Connect(function()
			if not entry.id then
				return
			end
			ui.send(if entry.claimable then "MailClaim" else "MailDelete", entry.id)
		end)
	end
end

function MailPage.draw(state, ui)
	local colors = ui.colors
	local now = os.time()
	local unread, claimable = 0, 0
	local waiting = 0 -- letters that are unread or still have rewards; each counts once
	for _, letter in state.mail do
		if not letter.read then
			unread += 1
		end
		if not letter.claimed then
			claimable += 1
		end
		if not letter.read or not letter.claimed then
			waiting += 1
		end
	end
	summary.Text = `<b>{#state.mail} letters</b>   |   {unread} unread   |   {claimable} with rewards to claim`
	ui.setButton(buttons[1], if claimable > 0 then `Claim all ({claimable})` else "Claim all", claimable > 0, colors.claim)
	ui.setButton(buttons[2], "Delete read letters", #state.mail > 0, colors.selected)

	for index, row in rows do
		local letter = state.mail[index]
		row.id = if letter then letter.id else nil
		row.info.Parent.Visible = letter ~= nil
		if not letter then
			continue
		end
		local new = if letter.read then "" else `  <font color="#F0C450">NEW</font>`
		local rewards = ""
		if letter.rewards then
			local list = StoreConfig.describeList(letter.rewards)
			rewards = if letter.claimed
				then `\n<font color="#9FD49A">Claimed: {list}</font>`
				else `\n<font color="#F0C450">Attached: {list}</font>`
		end
		row.info.Text = `<b>{letter.title}</b>{new}   <font color="#B2A690">{ago(now - letter.time)}</font>\n{letter.text}{rewards}`
		row.claimable = not letter.claimed
		if row.claimable then
			ui.setButton(row.button, "Claim", true, colors.claim)
		else
			ui.setButton(row.button, "Delete", true, colors.disabled)
		end
	end

	-- Opening the page marks everything as read (at most every few seconds).
	if ui.isOpen("Mail") and unread > 0 and now - readSentAt > 3 then
		readSentAt = now
		ui.send("MailRead", "all")
	end
	ui.setBadge("Mail", if ui.isOpen("Mail") then claimable else waiting)
end

return MailPage
