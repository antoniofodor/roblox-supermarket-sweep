-- Spectator mode. While a round is on and you're not in the store (eaten,
-- joined mid-match, checked out or shut in), the camera follows someone who
-- is still shopping. Arrows (or the on-screen buttons) switch between them;
-- BACK TO ME returns the camera to your own character until the next round.
--
-- Who's shopping comes from the `Shopping` attribute the server keeps on
-- every Player (Shoppers.push). Watching only moves this client's camera
-- (CameraSubject): it changes nothing in the game, so it needs no server.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))

local Spectate = {}

local ATTR = Config.ATTR
local PHASE = Config.PHASE
local player = Players.LocalPlayer

local watching = nil -- the Player the camera follows, or nil
local optedOut = false -- pressed BACK TO ME this round
local lastRound = 0
local ui = {}

-- Everyone still in the store, in a fixed order so the arrows feel stable.
local function shoppers()
	local list = {}
	for _, other in ipairs(Players:GetPlayers()) do
		local character = other.Character
		if other ~= player and other:GetAttribute(ATTR.shopping) == true and character and character:FindFirstChildOfClass("Humanoid") then
			table.insert(list, other)
		end
	end
	table.sort(list, function(a, b)
		return a.UserId < b.UserId
	end)
	return list
end

local function canWatch()
	return ReplicatedStorage:GetAttribute(ATTR.phase) == PHASE.shopping and player:GetAttribute(ATTR.shopping) ~= true
end

-- Point the camera at `target`'s character, or back at your own (nil).
local function follow(target)
	local camera = Workspace.CurrentCamera
	local who = target or player
	local character = who.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if camera and humanoid and camera.CameraSubject ~= humanoid then
		camera.CameraSubject = humanoid
	end
end

local function cycle(step)
	local list = shoppers()
	if #list == 0 then
		return
	end
	local index = table.find(list, watching) or 1
	watching = list[((index - 1 + step) % #list) + 1]
end

local function stopWatching()
	if watching then
		watching = nil
		follow(nil)
	end
end

local function update()
	-- a new round: watching is on again by default
	local round = ReplicatedStorage:GetAttribute(ATTR.roundNumber) or 0
	if round ~= lastRound then
		lastRound = round
		optedOut = false
	end

	local list = if canWatch() then shoppers() else {}
	if #list == 0 then
		stopWatching()
		ui.bar.Visible = false
		ui.watchButton.Visible = false
		return
	end
	if optedOut then
		stopWatching()
		ui.bar.Visible = false
		ui.watchButton.Visible = true
		return
	end
	if not table.find(list, watching) then
		watching = list[1]
	end
	follow(watching)
	ui.name.Text = watching.DisplayName
	ui.count.Text = ("%d of %d still shopping"):format(table.find(list, watching) or 1, #list)
	ui.bar.Visible = true
	ui.watchButton.Visible = false
end

local function button(parent, text, size, position)
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = position
	b.BackgroundColor3 = Theme.PAPER_DEEP
	b.BorderSizePixel = 0
	b.Font = Theme.DISPLAY
	b.TextSize = 20
	b.TextColor3 = Theme.INK
	b.Text = text
	b.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = b
	return b
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Spectate"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	-- bottom centre, above the trolley card (still shown to anyone who
	-- checked out or got shut in this round)
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -130)
	bar.Size = UDim2.fromOffset(340, 96)
	bar.Visible = false
	bar.Parent = gui
	Theme.card(bar)
	Theme.label(bar, {
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.new(1, 0, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 13,
		TextColor3 = Theme.MUTED,
		Text = "WATCHING",
	})
	ui.name = Theme.label(bar, {
		Position = UDim2.fromOffset(56, 20),
		Size = UDim2.new(1, -112, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Theme.DISPLAY,
		TextSize = 24,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
	})
	ui.count = Theme.label(bar, {
		Position = UDim2.fromOffset(56, 48),
		Size = UDim2.new(1, -112, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 12,
		TextColor3 = Theme.MUTED,
		Text = "",
	})
	local prev = button(bar, "<", UDim2.fromOffset(40, 40), UDim2.fromOffset(10, 18))
	local nextButton = button(bar, ">", UDim2.fromOffset(40, 40), UDim2.new(1, -50, 0, 18))
	local back = button(bar, "BACK TO ME", UDim2.new(1, -20, 0, 24), UDim2.fromOffset(10, 66))
	back.TextSize = 15
	prev.Activated:Connect(function()
		cycle(-1)
	end)
	nextButton.Activated:Connect(function()
		cycle(1)
	end)
	back.Activated:Connect(function()
		optedOut = true
	end)
	ui.bar = bar

	-- after BACK TO ME: a small button to start watching again
	local watch = button(gui, "WATCH THE ROUND", UDim2.fromOffset(200, 36), UDim2.new(0.5, -100, 1, -166))
	watch.TextSize = 16
	Theme.card(watch, Theme.PAPER)
	watch.Visible = false
	watch.Activated:Connect(function()
		optedOut = false
	end)
	ui.watchButton = watch
end

function Spectate.start()
	build()
	-- arrows switch who you watch, only while watching
	ContextActionService:BindAction("SweepSpectate", function(_, inputState, input)
		if not watching then
			return Enum.ContextActionResult.Pass
		end
		if inputState == Enum.UserInputState.Begin then
			cycle(if input.KeyCode == Enum.KeyCode.Left then -1 else 1)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Left, Enum.KeyCode.Right)
	RunService.Heartbeat:Connect(update)
end

return Spectate
