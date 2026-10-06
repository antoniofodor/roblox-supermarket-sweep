-- Test console for admins (and everyone in Studio). Toggle with F2 or the
-- ADMIN button. Each button sends a command name; the server checks the
-- allowlist and does the work.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local AdminPanel = {}

local BUTTONS = {
	{ command = "start", text = "Start match now" },
	{ command = "craving", text = "Skip to craving" },
	{ command = "tills", text = "Skip to tills open" },
	{ command = "sale", text = "Skip to flash sale" },
	{ command = "closing", text = "Skip to closing" },
	{ command = "shutters", text = "Skip to shutters" },
	{ command = "finish", text = "Close the store" },
	{ command = "give", text = "Give me 10 items" },
	{ command = "restock", text = "Restock shelves" },
	{ command = "endmatch", text = "End match after this round" },
}

local built = false

function AdminPanel.start()
	if built then
		return
	end
	built = true
	local player = Players.LocalPlayer
	local remote = Remotes.get("AdminCommand")

	local gui = Instance.new("ScreenGui")
	gui.Name = "SweepAdmin"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	gui.Parent = player:WaitForChild("PlayerGui")

	local toggle = Instance.new("TextButton")
	toggle.Name = "AdminToggle"
	toggle.AnchorPoint = Vector2.new(1, 1)
	toggle.Position = UDim2.new(1, -16, 1, -16)
	toggle.Size = UDim2.fromOffset(90, 36)
	toggle.Font = Theme.BODY
	toggle.TextSize = 15
	toggle.TextColor3 = Theme.INK
	toggle.Text = "ADMIN"
	toggle.Parent = gui
	Theme.card(toggle)

	local panel = Instance.new("Frame")
	panel.Name = "AdminPanel"
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Position = UDim2.new(1, -16, 1, -62)
	panel.Size = UDim2.fromOffset(210, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.Visible = false
	panel.Parent = gui
	Theme.card(panel)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = panel

	for i, spec in ipairs(BUTTONS) do
		local button = Instance.new("TextButton")
		button.Name = "Cmd_" .. spec.command
		button.LayoutOrder = i
		button.Size = UDim2.new(1, 0, 0, 28)
		button.BackgroundColor3 = Theme.PAPER_DEEP
		button.BorderSizePixel = 0
		button.Font = Theme.BODY
		button.TextSize = 14
		button.TextColor3 = Theme.INK
		button.Text = spec.text
		button.Parent = panel
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 8)
		c.Parent = button
		button.Activated:Connect(function()
			remote:FireServer(spec.command)
		end)
	end

	local function flip()
		panel.Visible = not panel.Visible
	end
	toggle.Activated:Connect(flip)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.F2 then
			flip()
		end
	end)
end

return AdminPanel
