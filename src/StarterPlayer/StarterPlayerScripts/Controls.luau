-- Sprint, trolley and throw controls. Each press only asks the server; the
-- server runs the sprint meter, checks the trolley's reach, and picks what
-- a throw uses and who it hits.
--
--   Shift (held) / L3 / SPRINT button : sprint while held, until the meter runs out
--   Q            / Y  / TROLLEY button: let go of / take back the trolley
--   F            / R1 / THROW button  : throw toward the mouse (or the middle of
--                                       the screen): the item in your hand, else the top of your pile
--   R            / X  / DIG button    : dig in your trolley (Rummage.luau)
--
-- ContextActionService makes the touch buttons for phones and tablets.
-- Shift is also Roblox's shift-lock key, so default.project.json and Main
-- turn the shift-lock option off.
--
-- Also switches prompts on for this player only: "Push" on your own parked
-- trolley, "Steal" on anybody else's parked trolley with something in it.
-- While you hold yuck in your hand, that prompt reads "Plant yuck" instead
-- (and works on an empty trolley too): the server decides which it is.
-- The server keeps both disabled.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Controls = {}

local player = Players.LocalPlayer
local holdingYuck = false -- from the last PlayerState push
local refreshers = {} -- [Model] = refresh function for its prompts

local function bindTrolleyPrompts(model)
	if not model:IsA("Model") then
		return
	end
	local handle = model:WaitForChild("Handle", 5)
	local base = model:WaitForChild("Base", 5)
	local push = handle and handle:WaitForChild("Push", 5)
	local steal = base and base:WaitForChild("Steal", 5)
	if not push or not steal then
		return
	end
	local function refresh()
		local mine = model:GetAttribute(Config.ATTR.trolleyOwner) == player.UserId
		local pushed = model:GetAttribute(Config.ATTR.trolleyPushed) == true
		local items = model:GetAttribute(Config.ATTR.trolleyItems) or 0
		push.Enabled = mine and not pushed
		steal.Enabled = not mine and not pushed and (items > 0 or holdingYuck)
		steal.ActionText = if holdingYuck then "Plant yuck" else "Steal"
	end
	refreshers[model] = refresh
	model.AncestryChanged:Connect(function()
		if not model.Parent then
			refreshers[model] = nil
		end
	end)
	model:GetAttributeChangedSignal(Config.ATTR.trolleyPushed):Connect(refresh)
	model:GetAttributeChangedSignal(Config.ATTR.trolleyItems):Connect(refresh)
	refresh()
end

local function onPlayerState(payload)
	local holding = false
	for _, key in ipairs(type(payload) == "table" and payload.handItems or {}) do
		local item = Config.ITEM_BY_KEY[key]
		if item and item.kind == "yuck" then
			holding = true
		end
	end
	if holding ~= holdingYuck then
		holdingYuck = holding
		for _, refresh in pairs(refreshers) do
			refresh()
		end
	end
end

local function rootPart()
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

-- Where a throw should go. With a keyboard and mouse: toward whatever the
-- mouse is pointing at. Otherwise (touch, gamepad): where the camera faces,
-- the middle of the screen. The server clamps whatever is sent.
local function aimDirection(useMouse)
	local root = rootPart()
	local camera = Workspace.CurrentCamera
	if not root or not camera then
		return nil
	end
	local origin = root.Position + Vector3.new(0, 1.5, 0)
	local ray
	if useMouse and UserInputService.MouseEnabled then
		local mouse = UserInputService:GetMouseLocation()
		ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	else
		local size = camera.ViewportSize
		ray = camera:ViewportPointToRay(size.X / 2, size.Y / 2)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character, Workspace:FindFirstChild("ThrownItems") }
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 300, params)
	local point = if hit then hit.Position else ray.Origin + ray.Direction * 300
	local direction = point - origin
	-- pointing at your own feet or behind the camera: throw where the camera looks
	if direction.Magnitude < 4 then
		direction = camera.CFrame.LookVector
	end
	return direction.Unit
end

-- Turn the character to face the throw, so it leaves from the front.
local function faceToward(direction)
	local root = rootPart()
	local flatDir = Vector3.new(direction.X, 0, direction.Z)
	if root and flatDir.Magnitude > 0.01 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + flatDir.Unit)
	end
end

-- Nobody climbs anything in this game. The shelves are flat walls already;
-- this is the backstop for anything else ladder-shaped. A character's
-- states belong to its own client, so this runs here, not on the server.
local function noClimbing(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	end
end

function Controls.start()
	player.CharacterAdded:Connect(noClimbing)
	if player.Character then
		task.spawn(noClimbing, player.Character)
	end

	local sprintRemote = Remotes.get("Sprint")
	local trolleyRemote = Remotes.get("TrolleyToggle")
	local throwRemote = Remotes.get("Throw")

	ContextActionService:BindAction("SweepSprint", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			sprintRemote:FireServer(true)
		elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			sprintRemote:FireServer(false)
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonL3)
	ContextActionService:SetTitle("SweepSprint", "SPRINT")
	ContextActionService:SetPosition("SweepSprint", UDim2.new(1, -170, 1, -170))

	ContextActionService:BindAction("SweepTrolley", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			trolleyRemote:FireServer()
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonY)
	ContextActionService:SetTitle("SweepTrolley", "TROLLEY")
	ContextActionService:SetPosition("SweepTrolley", UDim2.new(1, -250, 1, -110))

	ContextActionService:BindAction("SweepThrow", function(_, inputState, input)
		if inputState == Enum.UserInputState.Begin then
			local aim = aimDirection(input.UserInputType == Enum.UserInputType.Keyboard)
			if aim then
				faceToward(aim)
				throwRemote:FireServer(aim)
			end
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.F, Enum.KeyCode.ButtonR1)
	ContextActionService:SetTitle("SweepThrow", "THROW")
	ContextActionService:SetPosition("SweepThrow", UDim2.new(1, -250, 1, -190))

	Remotes.get("PlayerState").OnClientEvent:Connect(onPlayerState)

	-- trolleys arrive under workspace.SweepMart.Trolleys each round
	task.spawn(function()
		local mart = workspace:WaitForChild("SweepMart")
		local trolleys = mart:WaitForChild("Trolleys")
		trolleys.ChildAdded:Connect(bindTrolleyPrompts)
		for _, model in ipairs(trolleys:GetChildren()) do
			task.spawn(bindTrolleyPrompts, model)
		end
	end)
end

return Controls
