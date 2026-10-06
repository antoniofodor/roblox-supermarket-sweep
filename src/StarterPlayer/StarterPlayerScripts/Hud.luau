-- The HUD. It draws what the server said and computes nothing that matters:
-- the clock comes from round attributes on ReplicatedStorage, everything
-- about the player from the last PlayerState push.
--
--   top centre   : stage, clock, and which round of the match
--   top right    : Big Chonk: what he just said, what he hates, the food
--                  he's not in the mood for, and his craving
--   left         : your shopping list, ticked as you grab
--   bottom centre: how full your trolley is (never what's in it: you look,
--                  or dig), your hands, and the scan bar at a till
--   bottom left  : the sprint meter
--   centre       : tannoy announcements, the feeding (Chonk's mood meter,
--                  one row per player, revealed best first) and the podium
--
-- Values shown here (list rows, prompts) go through Rules.itemValue with the
-- round's menu read from the attributes: the same function the server
-- scores with, used only for display.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Rules = require(Shared:WaitForChild("Rules"))
local Theme = require(Shared:WaitForChild("Theme"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Hud = {}

local player = Players.LocalPlayer
local ATTR = Config.ATTR
local PHASE = Config.PHASE
local STATUS = Config.MATCH_STATUS
local TICK = utf8.char(0x2713)

local ui = {}
local latest = { inRound = false }
local listKey = "" -- the list the rows were built for
local resultsEndsAt = 0

-- A phone or tablet: hints name the on-screen buttons instead of keys.
local function isTouch()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- ------------------------------------------------------------
-- building
-- ------------------------------------------------------------

local function frame(parent, props)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	for key, value in pairs(props or {}) do
		f[key] = value
	end
	f.Parent = parent
	return f
end

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function setText(label, text)
	if label.Text ~= text then
		label.Text = text
	end
end

-- Chonk's menu this round, from the attributes.
local function currentMenu()
	local craving = ReplicatedStorage:GetAttribute(ATTR.craving) or ""
	local notToday = ReplicatedStorage:GetAttribute(ATTR.notToday) or ""
	return {
		craving = if craving ~= "" then craving else nil,
		notToday = if notToday ~= "" then notToday else nil,
	}
end

local function itemName(key)
	local item = Config.ITEM_BY_KEY[key]
	return item and item.name or ""
end

local function buildClock(gui)
	local card = Theme.card(frame(gui, {
		Name = "Clock",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 66),
		Size = UDim2.fromOffset(280, 96),
	}))
	ui.clockCard = card
	ui.stage = Theme.label(card, {
		Name = "Stage",
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 15,
		Text = "",
	})
	ui.clock = Theme.label(card, {
		Name = "Time",
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, 46),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Theme.DISPLAY,
		TextSize = 40,
		Text = "",
	})
	ui.matchLabel = Theme.label(card, {
		Name = "Match",
		Position = UDim2.fromOffset(0, 72),
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 13,
		TextColor3 = Theme.MUTED,
		Text = "",
	})
	ui.clockScale = Instance.new("UIScale")
	ui.clockScale.Parent = card
end

local function buildList(gui)
	local card = Theme.card(frame(gui, {
		Name = "List",
		Position = UDim2.fromOffset(16, 160),
		Size = UDim2.fromOffset(240, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
	}))
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = card
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = card
	Theme.label(card, {
		Name = "Title",
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, 24),
		Font = Theme.DISPLAY,
		TextSize = 22,
		Text = ("YOUR LIST  x%d"):format(Config.LIST_MULTIPLIER),
	})
	ui.listCard = card
	ui.listRows = {}
end

local function rebuildListRows(list)
	for _, row in ipairs(ui.listRows) do
		row.frame:Destroy()
	end
	ui.listRows = {}
	for i, key in ipairs(list) do
		local item = Config.ITEM_BY_KEY[key]
		local row = frame(ui.listCard, {
			Name = "Row_" .. key,
			LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundColor3 = Theme.PAPER_DEEP,
		})
		corner(row, 8)
		local swatch = frame(row, {
			Position = UDim2.fromOffset(6, 6),
			Size = UDim2.fromOffset(18, 18),
			BackgroundColor3 = Theme.rgb(item.color),
		})
		corner(swatch, 5)
		local stroke = Instance.new("UIStroke")
		stroke.Color = Theme.INK
		stroke.Thickness = 1.5
		stroke.Parent = swatch
		Theme.label(row, {
			Position = UDim2.fromOffset(32, 0),
			Size = UDim2.new(1, -100, 1, 0),
			Text = item.name,
			TextSize = 15,
		})
		local value = Theme.label(row, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -34, 0, 0),
			Size = UDim2.fromOffset(56, 30),
			Text = Rules.formatYum(item.yum * Config.LIST_MULTIPLIER),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = Theme.GOLD_INK,
			TextSize = 14,
		})
		local tick = Theme.label(row, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -6, 0, 0),
			Size = UDim2.fromOffset(24, 30),
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = Theme.GOOD_INK,
			Font = Theme.DISPLAY,
			TextSize = 22,
		})
		table.insert(ui.listRows, { key = key, frame = row, tick = tick, value = value })
	end
end

-- What each list row is worth right now (Chonk's craving can raise one).
local function refreshListValues()
	local listSet = Rules.listSet(latest.list or {})
	local menu = currentMenu()
	for _, row in ipairs(ui.listRows) do
		setText(row.value, Rules.formatYum(Rules.itemValue(row.key, listSet, menu)))
		row.value.TextColor3 = if menu.craving == row.key then Theme.CHONK_INK else Theme.GOLD_INK
	end
end

-- Top right: Big Chonk.
local function buildChonk(gui)
	local card = Theme.card(frame(gui, {
		Name = "Chonk",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 66),
		Size = UDim2.fromOffset(250, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
	}))
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = card
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = card
	Theme.label(card, {
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, 22),
		Font = Theme.DISPLAY,
		TextSize = 20,
		TextColor3 = Theme.CHONK_INK,
		Text = "BIG CHONK",
	})
	local function line(order, size, color)
		return Theme.label(card, {
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			TextSize = size,
			TextColor3 = color,
			Text = "",
		})
	end
	ui.chonkLine = line(1, 17, Theme.INK)
	ui.chonkLine.Font = Theme.DISPLAY
	local hates, yuckYum = {}, 0
	for _, item in ipairs(Config.ITEMS) do
		if item.kind == "yuck" then
			table.insert(hates, item.name)
			yuckYum = item.yum
		end
	end
	ui.chonkHates = line(2, 13, Theme.STOP_INK)
	ui.chonkHates.Text = ("HATES (%s each): %s"):format(Rules.formatYum(yuckYum), table.concat(hates, ", "))
	ui.chonkNotToday = line(3, 13, Theme.MUTED)
	ui.chonkCraving = line(4, 14, Theme.CHONK_INK)
	ui.chonkCard = card
	ui.chonkScale = Instance.new("UIScale")
	ui.chonkScale.Parent = card
end

local function updateChonk(phase)
	local show = phase == PHASE.shopping or phase == PHASE.results or phase == PHASE.podium
		or (phase == PHASE.lobby and (ReplicatedStorage:GetAttribute(ATTR.matchRound) or 0) > 0)
	if ui.chonkCard.Visible ~= show then
		ui.chonkCard.Visible = show
	end
	if not show then
		return
	end
	local menu = currentMenu()
	setText(ui.chonkNotToday, if menu.notToday then ("NOT TODAY (%s): %s"):format(Rules.formatYum(Config.NOT_TODAY_YUM), itemName(menu.notToday)) else "")
	ui.chonkNotToday.Visible = menu.notToday ~= nil
	setText(ui.chonkCraving, if menu.craving then ("CRAVING (x%d): %s"):format(Config.CRAVING_MULTIPLIER, itemName(menu.craving)) else "")
	ui.chonkCraving.Visible = menu.craving ~= nil
end

local function onChonkSay(payload)
	if type(payload) ~= "table" or type(payload.text) ~= "string" then
		return
	end
	setText(ui.chonkLine, payload.text)
	ui.chonkScale.Scale = 1.08
	TweenService:Create(ui.chonkScale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end

local function buildBasket(gui)
	local card = Theme.card(frame(gui, {
		Name = "Basket",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -20),
		Size = UDim2.fromOffset(320, 100),
		Visible = false,
	}))
	ui.basketCard = card
	ui.handsText = Theme.label(card, {
		Position = UDim2.fromOffset(14, 66),
		Size = UDim2.new(1, -28, 0, 24),
		TextSize = 15,
		TextColor3 = Theme.MUTED,
		Text = "",
	})
	ui.basketCount = Theme.label(card, {
		Position = UDim2.fromOffset(14, 6),
		Size = UDim2.new(0.6, -14, 0, 34),
		Font = Theme.DISPLAY,
		TextSize = 24,
		Text = "",
	})
	ui.basketValue = Theme.label(card, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 6),
		Size = UDim2.new(0.4, 0, 0, 34),
		Font = Theme.DISPLAY,
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.GOLD_INK,
		Text = "",
	})
	local track = frame(card, {
		Position = UDim2.fromOffset(14, 46),
		Size = UDim2.new(1, -28, 0, 14),
		BackgroundColor3 = Theme.PAPER_DEEP,
	})
	corner(track, 7)
	ui.basketFill = frame(track, {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.GOLD,
	})
	corner(ui.basketFill, 7)

	-- scan bar, shown above the basket card while standing at a till
	local scan = Theme.card(frame(gui, {
		Name = "Scan",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -130),
		Size = UDim2.fromOffset(320, 56),
		Visible = false,
	}))
	ui.scanCard = scan
	ui.scanText = Theme.label(scan, {
		Position = UDim2.fromOffset(14, 4),
		Size = UDim2.new(1, -28, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 16,
		Text = "",
	})
	local scanTrack = frame(scan, {
		Position = UDim2.fromOffset(14, 32),
		Size = UDim2.new(1, -28, 0, 12),
		BackgroundColor3 = Theme.PAPER_DEEP,
	})
	corner(scanTrack, 6)
	ui.scanFill = frame(scanTrack, {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.GOOD,
	})
	corner(ui.scanFill, 6)
end

-- Sprint meter and throw readiness, left of the trolley card. The meter is
-- predicted from the server's last snapshot with the same arithmetic the
-- server enforces (Rules.staminaAt).
local function buildSprint(gui)
	local card = Theme.card(frame(gui, {
		Name = "Sprint",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(0.5, -172, 1, -20),
		Size = UDim2.fromOffset(176, 100),
		Visible = false,
	}))
	ui.sprintCard = card
	Theme.label(card, {
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(0.5, -12, 0, 28),
		Font = Theme.DISPLAY,
		TextSize = 22,
		Text = "SPRINT",
	})
	ui.sprintState = Theme.label(card, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 6),
		Size = UDim2.new(0.5, 0, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 14,
		Text = "",
	})
	local track = frame(card, {
		Position = UDim2.fromOffset(12, 38),
		Size = UDim2.new(1, -24, 0, 14),
		BackgroundColor3 = Theme.PAPER_DEEP,
	})
	corner(track, 7)
	ui.sprintFill = frame(track, {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.GOOD,
	})
	corner(ui.sprintFill, 7)
	ui.throwState = Theme.label(card, {
		Position = UDim2.fromOffset(12, 60),
		Size = UDim2.new(1, -24, 0, 28),
		TextSize = 15,
		Text = "",
	})
end

local function updateSprint()
	local card = ui.sprintCard
	local show = latest.inRound == true and not latest.done and not latest.caught
	if card.Visible ~= show then
		card.Visible = show
	end
	if not show then
		return
	end
	local t = Workspace:GetServerTimeNow()
	local stamina = Rules.staminaAt(latest.stamina or 1, latest.staminaAt or t, latest.sprinting == true, latest.regenAt or 0, t)
	ui.sprintFill.Size = UDim2.fromScale(stamina, 1)

	if (latest.stumbleUntil or 0) > t then
		setText(ui.sprintState, "OFF BALANCE")
		ui.sprintState.TextColor3 = Theme.STOP_INK
		ui.sprintFill.BackgroundColor3 = Theme.MUTED
	elseif latest.sprinting then
		setText(ui.sprintState, "GO GO GO!")
		ui.sprintState.TextColor3 = Theme.GOOD_INK
		ui.sprintFill.BackgroundColor3 = Theme.WARN
	elseif stamina < Config.SPRINT_MIN_START then
		setText(ui.sprintState, "TIRED")
		ui.sprintState.TextColor3 = Theme.MUTED
		ui.sprintFill.BackgroundColor3 = Theme.MUTED
	else
		setText(ui.sprintState, if isTouch() then "hold" else "hold Shift")
		ui.sprintState.TextColor3 = Theme.GOOD_INK
		ui.sprintFill.BackgroundColor3 = Theme.GOOD
	end

	local throwKey = if isTouch() then "" else " (F)"
	local wait = (latest.throwReadyAt or 0) - t
	if wait > 0 then
		setText(ui.throwState, ("THROW in %.1fs"):format(wait))
		ui.throwState.TextColor3 = Theme.MUTED
	elseif (latest.scannable or 0) == 0 then
		-- a throw uses your hands, or the trolley you're pushing
		setText(ui.throwState, "THROW: nothing to throw")
		ui.throwState.TextColor3 = Theme.MUTED
	else
		setText(ui.throwState, "THROW ready" .. throwKey)
		ui.throwState.TextColor3 = Theme.GOOD_INK
	end
end

local function buildAnnounce(gui)
	-- A plain Frame rather than a CanvasGroup: a CanvasGroup clips the
	-- outline stroke, which draws outside the frame.
	local group = Instance.new("Frame")
	group.Name = "Announce"
	group.AnchorPoint = Vector2.new(0.5, 0)
	group.Position = UDim2.new(0.5, 0, 0, 174)
	group.Size = UDim2.fromOffset(0, 54)
	group.AutomaticSize = Enum.AutomaticSize.X
	group.Visible = false
	group.Parent = gui
	Theme.card(group)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 26)
	pad.PaddingRight = UDim.new(0, 18)
	pad.Parent = group
	ui.announceStripe = frame(group, {
		Position = UDim2.new(0, -20, 0, 8),
		Size = UDim2.new(0, 8, 1, -16),
		BackgroundColor3 = Theme.COOL,
	})
	corner(ui.announceStripe, 4)
	ui.announceText = Theme.label(group, {
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Theme.DISPLAY,
		TextSize = 26,
		Text = "",
	})
	ui.announce = group
	ui.announceScale = Instance.new("UIScale")
	ui.announceScale.Parent = group
end

local function buildResults(gui)
	local card = Theme.card(frame(gui, {
		Name = "Results",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromOffset(460, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
	}))
	ui.resultsScale = Instance.new("UIScale")
	ui.resultsScale.Parent = card
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 14)
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = card
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = card
	ui.resultsTitle = Theme.label(card, {
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, 34),
		Font = Theme.DISPLAY,
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "RESULTS",
	})
	ui.resultsCard = card
	ui.resultRows = {}
	ui.feed = nil -- { rows = { { data, needle, score, name } }, gulpAt }
end

-- ------------------------------------------------------------
-- updating
-- ------------------------------------------------------------

local announceToken = 0
local function showAnnounce(payload)
	if type(payload) ~= "table" or type(payload.text) ~= "string" then
		return
	end
	announceToken += 1
	local token = announceToken
	ui.announceText.Text = payload.text
	ui.announceStripe.BackgroundColor3 = Theme.KIND[payload.kind] or Theme.COOL
	ui.announce.Visible = true
	ui.announceScale.Scale = 1.15
	TweenService:Create(ui.announceScale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	-- hold scales with how much there is to read
	local _, words = payload.text:gsub("%S+", "")
	local hold = math.clamp(1.6 + 0.3 * words, 2.2, 6)
	task.delay(hold, function()
		if token == announceToken then
			ui.announce.Visible = false
		end
	end)
end

local function clearResults()
	for _, row in ipairs(ui.resultRows) do
		row:Destroy()
	end
	ui.resultRows = {}
	ui.feed = nil
end

-- Shrink the card to fit the screen (a phone held sideways is ~390 tall).
local function fitResults(rowCount, rowHeight)
	local camera = Workspace.CurrentCamera
	local height = 70 + rowCount * (rowHeight + 6)
	local room = (if camera then camera.ViewportSize.Y else 720) - 150
	ui.resultsScale.Scale = math.clamp(room / height, 0.4, 1)
end

-- One row of the feeding: name and score on top, Chonk's mood meter under.
local function feedRow(rank, data)
	local mine = data.userId == player.UserId
	local row = frame(ui.resultsCard, {
		LayoutOrder = rank,
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = if mine then Theme.GOLD:Lerp(Theme.PAPER, 0.5) else Theme.PAPER_DEEP,
	})
	corner(row, 8)
	local name = Theme.label(row, {
		Position = UDim2.fromOffset(10, 2),
		Size = UDim2.new(1, -140, 0, 20),
		Font = Theme.DISPLAY,
		TextSize = 17,
		Text = ("%d. %s"):format(rank, data.name),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local score = Theme.label(row, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 2),
		Size = UDim2.fromOffset(130, 20),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 14,
		TextColor3 = Theme.MUTED,
		Text = "...",
	})
	local track = frame(row, {
		Position = UDim2.fromOffset(10, 25),
		Size = UDim2.new(1, -20, 0, 12),
		BackgroundTransparency = 1,
	})
	local zones = {
		{ Theme.MOOD.angry, 0, Config.MOOD_ANGRY_TOP },
		{ Theme.MOOD.content, Config.MOOD_ANGRY_TOP, Config.MOOD_LOVE_FROM },
		{ Theme.MOOD.love, Config.MOOD_LOVE_FROM, 1 },
	}
	for _, zone in ipairs(zones) do
		local z = frame(track, {
			Position = UDim2.fromScale(zone[2], 0),
			Size = UDim2.fromScale(zone[3] - zone[2], 1),
			BackgroundColor3 = zone[1].fill:Lerp(Theme.PAPER, 0.35),
		})
		corner(z, 4)
	end
	local needle = frame(track, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(0, 5, 1, 10),
		BackgroundColor3 = Theme.INK,
		Visible = false,
		ZIndex = 2,
	})
	corner(needle, 2)
	table.insert(ui.resultRows, row)
	return { data = data, needle = needle, score = score, name = name, rank = rank }
end

local function showResults(payload)
	if type(payload) ~= "table" then
		return
	end
	clearResults()
	resultsEndsAt = payload.endsAt or 0
	local rows = payload.rows or {}

	if payload.podium then
		local winner = rows[1]
		ui.resultsTitle.Text = if winner then ("%s WINS!"):format(winner.name:upper()) else "THE MATCH IS OVER"
		local places = { "1st", "2nd", "3rd" }
		for rank, data in ipairs(rows) do
			local mine = data.userId == player.UserId
			local row = frame(ui.resultsCard, {
				LayoutOrder = rank,
				Size = UDim2.new(1, 0, 0, 38),
				BackgroundColor3 = if rank == 1 then Theme.GOLD elseif mine then Theme.GOLD:Lerp(Theme.PAPER, 0.5) else Theme.PAPER_DEEP,
			})
			corner(row, 8)
			Theme.label(row, {
				Position = UDim2.fromOffset(12, 0),
				Size = UDim2.new(1, -120, 1, 0),
				Font = Theme.DISPLAY,
				TextSize = 20,
				Text = ("%s  %s"):format(places[rank], data.name),
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
			Theme.label(row, {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -12, 0, 0),
				Size = UDim2.fromOffset(100, 38),
				TextXAlignment = Enum.TextXAlignment.Right,
				Font = Theme.DISPLAY,
				TextSize = 18,
				Text = Rules.formatYum(data.score or 0),
			})
			table.insert(ui.resultRows, row)
		end
		fitResults(#rows, 38)
		ui.resultsCard.Visible = true
		return
	end

	local title = ("ROUND %d OF %d · FEEDING TIME"):format(payload.round or 0, payload.rounds or Config.MATCH_ROUNDS)
	if payload.final then
		title = "THE FINAL · FEEDING TIME"
	end
	ui.resultsTitle.Text = title
	local feed = { rows = {}, gulpAt = payload.gulpAt or math.huge }
	for rank, data in ipairs(rows) do
		table.insert(feed.rows, feedRow(rank, data))
	end
	if #rows == 0 then
		local row = Theme.label(ui.resultsCard, {
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 30),
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = "Nobody fed Big Chonk this round.",
		})
		table.insert(ui.resultRows, row)
	end
	ui.feed = feed
	fitResults(#rows, 44)
	ui.resultsCard.Visible = true
end

-- The needles: each sweeps to where that player landed when their turn
-- comes. A player in danger climbs to the edge of angry and wobbles there
-- before it settles.
local function updateFeeding()
	local feed = ui.feed
	if not feed or not ui.resultsCard.Visible then
		return
	end
	local t = Workspace:GetServerTimeNow()
	local edge = Config.MOOD_ANGRY_TOP
	for _, r in ipairs(feed.rows) do
		local d = r.data
		if t >= d.revealAt then
			local a = math.clamp((t - d.revealAt) / math.max(d.revealSeconds, 0.1), 0, 1)
			local position
			if d.danger then
				if a < 0.35 then
					position = edge * (a / 0.35)
				elseif a < 0.8 then
					position = edge + math.sin((a - 0.35) * 40) * 0.06
				else
					position = edge + (d.meter - edge) * ((a - 0.8) / 0.2)
				end
			else
				position = d.meter * (1 - (1 - a) ^ 3)
			end
			r.needle.Visible = true
			r.needle.Position = UDim2.fromScale(math.clamp(position, 0, 1), 0.5)
			if a >= 1 then
				local mood = Theme.MOOD[d.mood] or Theme.MOOD.content
				setText(r.score, ("%s · %s"):format(Rules.formatYum(d.score or 0), mood.word))
				r.score.TextColor3 = mood.ink
			end
		end
		if d.eaten and t >= feed.gulpAt then
			setText(r.name, ("%d. %s  EATEN!"):format(r.rank, d.name))
			r.name.TextColor3 = Theme.STOP_INK
		end
	end
end

local function applyState(payload)
	latest = payload or { inRound = false }
	local inRound = latest.inRound == true
	ui.listCard.Visible = inRound
	ui.basketCard.Visible = inRound

	if not inRound then
		ui.scanCard.Visible = false
		listKey = ""
		return
	end

	local key = table.concat(latest.list or {}, ",")
	if key ~= listKey then
		listKey = key
		rebuildListRows(latest.list or {})
	end
	local have = latest.have or {}
	for _, row in ipairs(ui.listRows) do
		local got = have[row.key] == true
		setText(row.tick, if got then TICK else "")
		row.frame.BackgroundColor3 = if got then Theme.GOOD:Lerp(Theme.PAPER, 0.6) else Theme.PAPER_DEEP
	end
	refreshListValues()

	if latest.done then
		setText(ui.basketCount, "CHECKED OUT")
		setText(ui.basketValue, Rules.formatYum(latest.score or 0))
		ui.basketFill.Size = UDim2.fromScale(1, 1)
		ui.basketFill.BackgroundColor3 = Theme.GOOD
	elseif latest.caught then
		setText(ui.basketCount, "SHUT IN")
		setText(ui.basketValue, if (latest.lost or 0) > 0 then "-" .. Rules.formatYum(latest.lost) else Rules.formatYum(0))
		ui.basketFill.Size = UDim2.fromScale(0, 1)
	else
		local count, capacity = latest.trolleyCount or 0, latest.trolleyCapacity or Config.TROLLEY_CAPACITY
		setText(ui.basketCount, ("TROLLEY %d / %d"):format(count, capacity))
		-- no value while shopping: the trolley is a pile you have to look in
		setText(ui.basketValue, "")
		ui.basketFill.Size = UDim2.fromScale(math.clamp(count / capacity, 0, 1), 1)
		ui.basketFill.BackgroundColor3 = if count >= capacity then Theme.STOP else Theme.GOLD
	end

	local hands = ("HANDS %d / %d"):format(latest.handsCount or 0, latest.handSlots or Config.HAND_SLOTS)
	if latest.done or latest.caught then
		setText(ui.handsText, "")
	elseif latest.digging then
		local full = (latest.handsCount or 0) >= (latest.handSlots or Config.HAND_SLOTS)
		if full then
			if latest.pushing then
				setText(ui.handsText, if isTouch() then "HAND FULL: THROW it or put it back" else "HAND FULL: F to throw it, or put it back")
			else
				setText(ui.handsText, if isTouch() then "HANDS FULL: THROW one or put one back" else "HANDS FULL: F to throw one, or put one back")
			end
		else
			setText(ui.handsText, if isTouch() then "DIGGING: tap an item on top  ·  DIG: stop" else "DIGGING: click an item on top  ·  R: stop")
		end
		ui.handsText.TextColor3 = Theme.WARN_INK
	elseif latest.pushing then
		setText(ui.handsText, hands .. "  ·  " .. (if isTouch() then "DIG  ·  TROLLEY: let go  ·  THROW" else "R: dig  ·  Q: let go  ·  F: throw"))
		ui.handsText.TextColor3 = Theme.MUTED
	else
		setText(ui.handsText, hands .. "  ·  TROLLEY PARKED: go back for it")
		ui.handsText.TextColor3 = Theme.WARN_INK
	end

	local atTill = latest.atTill
	if atTill and not latest.done and not latest.caught then
		local scanned = latest.scanned or 0
		local total = scanned + (latest.scannable or 0)
		setText(ui.scanText, ("TILL %d  SCANNING %d / %d  ·  SAFE %s"):format(atTill, scanned, total, Rules.formatYum(latest.banked or 0)))
		ui.scanFill.Size = UDim2.fromScale(if total > 0 then scanned / total else 0, 1)
		ui.scanCard.Visible = true
	else
		ui.scanCard.Visible = false
	end

end

local STAGE = {
	early = { text = ("SHOPPING · tills open at %s"):format(Rules.formatClock(Config.TILLS_OPEN_AT)), color = Theme.GOOD_INK },
	shopping = { text = "TILLS OPEN", color = Theme.GOOD_INK },
	closing = { text = "STORE CLOSING!", color = Theme.WARN_INK },
	shutters = { text = "SHUTTERS COMING DOWN!", color = Theme.STOP_INK },
	closed = { text = "STORE CLOSED", color = Theme.STOP_INK },
}

local function updateClock()
	local phase = ReplicatedStorage:GetAttribute(ATTR.phase)
	local endsAt = ReplicatedStorage:GetAttribute(ATTR.phaseEndsAt) or 0
	local now = Workspace:GetServerTimeNow()
	local left = endsAt - now
	local pulse = 1

	local matchRound = ReplicatedStorage:GetAttribute(ATTR.matchRound) or 0
	local status = player:GetAttribute(ATTR.matchStatus)
	if matchRound > 0 then
		local place = if status == STATUS.out then "  ·  you were eaten" elseif status == STATUS.waiting then "  ·  you're in the next match" else ""
		setText(ui.matchLabel, ("ROUND %d OF %d%s"):format(matchRound, Config.MATCH_ROUNDS, place))
	else
		setText(ui.matchLabel, ("A MATCH IS %d ROUNDS"):format(Config.MATCH_ROUNDS))
	end

	if phase == PHASE.shopping then
		local startedAt = ReplicatedStorage:GetAttribute(ATTR.roundStartedAt) or now
		local stage = STAGE[Rules.stageAt(now - startedAt)] or STAGE.shopping
		if latest.inRound then
			setText(ui.stage, stage.text)
			ui.stage.TextColor3 = stage.color
		elseif status == STATUS.out then
			setText(ui.stage, "EATEN · watching the survivors")
			ui.stage.TextColor3 = Theme.MUTED
		else
			setText(ui.stage, "MATCH IN PROGRESS · you're in the next one")
			ui.stage.TextColor3 = Theme.MUTED
		end
		setText(ui.clock, Rules.formatClock(left))
		local final = left <= Config.FINAL_COUNTDOWN and left > 0
		ui.clock.TextColor3 = if final then Theme.STOP_INK else Theme.INK
		if final then
			pulse = 1 + 0.08 * math.max(0, math.cos((left % 1) * math.pi * 2))
		end
	elseif phase == PHASE.lobby then
		setText(ui.stage, if matchRound > 0 then ("ROUND %d STARTS IN"):format(matchRound) else "MATCH STARTS IN")
		ui.stage.TextColor3 = Theme.MUTED
		setText(ui.clock, Rules.formatClock(left))
		ui.clock.TextColor3 = Theme.INK
	elseif phase == PHASE.results then
		setText(ui.stage, "BIG CHONK IS EATING...")
		ui.stage.TextColor3 = Theme.CHONK_INK
		setText(ui.clock, Rules.formatClock(left))
		ui.clock.TextColor3 = Theme.INK
	elseif phase == PHASE.podium then
		setText(ui.stage, "THE WINNER!")
		ui.stage.TextColor3 = Theme.GOLD_INK
		setText(ui.clock, Rules.formatClock(left))
		ui.clock.TextColor3 = Theme.INK
	else
		local ready = ReplicatedStorage:GetAttribute(ATTR.playersReady) or 0
		setText(ui.stage, "WAITING FOR PLAYERS")
		ui.stage.TextColor3 = Theme.MUTED
		setText(ui.clock, ("%d / %d"):format(ready, Config.MIN_PLAYERS))
		ui.clock.TextColor3 = Theme.INK
	end

	if ui.clockScale.Scale ~= pulse then
		ui.clockScale.Scale = pulse
	end
	if ui.resultsCard.Visible and ((phase ~= PHASE.results and phase ~= PHASE.podium) or now > resultsEndsAt) then
		ui.resultsCard.Visible = false
	end
	updateChonk(phase)
end

-- Items on your list say so in their own prompt. A client-side write to a
-- prompt only changes this player's copy, which is exactly what we want.
local function onPromptShown(prompt)
	if prompt.Name ~= "Grab" or not prompt.Parent then
		return
	end
	local item = Config.ITEM_BY_KEY[prompt.Parent:GetAttribute(ATTR.itemKey)]
	if not item then
		return
	end
	local listSet = if latest.inRound then Rules.listSet(latest.list or {}) else {}
	local menu = currentMenu()
	local tag
	-- no tag for the food he's not in the mood for: the Chonk card says it,
	-- and remembering is part of the game (designer, 2026-10-05)
	if item.kind == "yuck" then
		tag = "YUCK! THROW IT"
	elseif menu.craving == item.key then
		tag = "CRAVING!"
	elseif listSet[item.key] then
		tag = "ON YOUR LIST"
	elseif item.kind == "snack" then
		tag = "SNACK"
	end
	local value = Rules.formatYum(Rules.itemValue(item.key, listSet, menu))
	prompt.ObjectText = if tag then ("%s  %s  %s"):format(item.name, value, tag) else ("%s  %s"):format(item.name, value)
end

function Hud.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "SweepHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	buildClock(gui)
	buildChonk(gui)
	buildList(gui)
	buildBasket(gui)
	buildSprint(gui)
	buildAnnounce(gui)
	buildResults(gui)

	Remotes.get("PlayerState").OnClientEvent:Connect(applyState)
	Remotes.get("Announce").OnClientEvent:Connect(showAnnounce)
	Remotes.get("Results").OnClientEvent:Connect(showResults)
	Remotes.get("ChonkSay").OnClientEvent:Connect(onChonkSay)
	ReplicatedStorage:GetAttributeChangedSignal(ATTR.craving):Connect(refreshListValues)
	ReplicatedStorage:GetAttributeChangedSignal(ATTR.notToday):Connect(refreshListValues)
	ProximityPromptService.PromptShown:Connect(onPromptShown)
	RunService.Heartbeat:Connect(function()
		updateClock()
		updateSprint()
		updateFeeding()
	end)
end

return Hud
