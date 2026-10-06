-- The dig view. R (or the DIG button) asks the server to start rummaging in
-- your own trolley; the server stands you still and says so in PlayerState
-- (`digging`). While it does, the camera looks straight down into your
-- basket, and a click or tap on an item asks the server to pull it out
-- (slot + key: the server checks it's on top of the pile, Rules.reachable).
-- R again, or trying to walk, stops it.
--
-- While digging, your own hands show at the bottom of the view (one while
-- you push the trolley, since the other is on the handle; two when it's
-- parked), as if
-- you're looking down into the trolley, holding what you've pulled out
-- (highlighted). Tap or click a held item (or press 1 or 2) to put it back
-- on top of the pile: how you undo a pick, or swap what you're holding.
-- Grey box: the hands are blocks in your character's own skin colour,
-- built on this client only, under the camera; real hand models come with
-- the art.
--
-- The items are the trolley model's own parts (Trolley.setItems), each with
-- its Slot and ItemKey attributes, so what you see is what the server has.
-- Hovering shows a box: green if it's on top, grey if it's buried.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Rules = require(Shared:WaitForChild("Rules"))
local Theme = require(Shared:WaitForChild("Theme"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Rummage = {}

local player = Players.LocalPlayer
local CAMERA_HEIGHT = 5.5 -- studs above the middle of the basket
local digging = false
local cameraTaken = false
local lastAsk = 0
local digRemote, takeRemote, putRemote
local hover -- SelectionBox on the item under the pointer
local held = {} -- item keys in your hands, from the last PlayerState
local slots = Config.HAND_SLOTS -- how many hands are free, from the last PlayerState
local handsFolder -- this client's hands in the dig view, under the camera
local handModels = {} -- [handIndex] = { model, spot }, pivoted to the view every frame
-- Where each hand sits, in the dig view's own space: 4 studs below the
-- camera, low on the screen, left and right. +Y is the top of the screen.
local HAND_SPOTS = { CFrame.new(-1.5, -2.0, -4), CFrame.new(1.5, -2.0, -4) }

local function myTrolley()
	local mart = Workspace:FindFirstChild("SweepMart")
	local trolleys = mart and mart:FindFirstChild("Trolleys")
	if not trolleys then
		return nil
	end
	for _, model in ipairs(trolleys:GetChildren()) do
		if model:GetAttribute(Config.ATTR.trolleyOwner) == player.UserId then
			return model
		end
	end
	return nil
end

-- Straight down into the basket, its front at the top of the screen and the
-- handle (your end) at the bottom.
local function basketView(model)
	local base = model.PrimaryPart
	if not base then
		return nil
	end
	local centre = (base.CFrame * CFrame.new(0, 0.6, -0.2)).Position
	return CFrame.lookAt(centre + Vector3.new(0, CAMERA_HEIGHT, 0), centre, base.CFrame.LookVector)
end

-- Back to the normal camera, put behind the shopper first: Roblox's camera
-- carries on from whatever angle it's left at, which after the dig view is
-- straight down from above.
local RETURN_PITCH = math.rad(20) -- looking a little down, like the normal follow view

local function releaseCamera()
	if cameraTaken then
		cameraTaken = false
		local camera = Workspace.CurrentCamera
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if camera and root then
			local facing = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
			facing = if facing.Magnitude > 0.01 then facing.Unit else Vector3.new(0, 0, -1)
			local focus = root.Position + Vector3.new(0, 1.5, 0)
			local eye = focus
				- facing * (Config.CAMERA_DISTANCE * math.cos(RETURN_PITCH))
				+ Vector3.new(0, Config.CAMERA_DISTANCE * math.sin(RETURN_PITCH), 0)
			camera.CFrame = CFrame.lookAt(eye, focus)
		end
		if camera then
			camera.CameraType = Enum.CameraType.Custom
		end
	end
	hover.Adornee = nil
end

-- The trolley item under a screen point, or nil.
local function itemAt(model, ray)
	local items = model:FindFirstChild("Items")
	if not items then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { items }
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 40, params)
	return hit and hit.Instance
end

-- ---------------- your hands in the dig view ----------------

local function putBack(handIndex)
	local key = held[handIndex]
	if digging and key then
		putRemote:FireServer(handIndex, key)
	end
end

-- The colour of the character's hand and sleeve, R15 or R6.
local function bodyColours(side)
	local character = player.Character
	local hand = character and (character:FindFirstChild(side .. "Hand") or character:FindFirstChild(side .. " Arm"))
	local arm = character and (character:FindFirstChild(side .. "LowerArm") or character:FindFirstChild(side .. " Arm"))
	local skin = if hand and hand:IsA("BasePart") then hand.Color else Color3.fromRGB(234, 184, 146)
	local sleeve = if arm and arm:IsA("BasePart") then arm.Color else skin
	return skin, sleeve
end

local function piece(model, name, size, cf, color, shape)
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = true -- a click on your hand puts back what it holds
	p.CastShadow = false
	p.Parent = model
	return p
end

-- One open hand, palm towards the camera, built around the origin and then
-- pivoted into the view each frame. `spot` 1 is the left hand, 2 the right.
-- Holding `key`, if anything; a click on it puts back hand `handIndex`.
local function buildHand(handIndex, spot, key)
	local side = if spot == 1 then "Left" else "Right"
	local inward = if spot == 1 then 1 else -1 -- the thumb points to the middle of the screen
	local skin, sleeve = bodyColours(side)
	local model = Instance.new("Model")
	model.Name = side .. "Hand"
	model:SetAttribute("Hand", handIndex)
	local palm = piece(model, "Palm", Vector3.new(1.0, 1.1, 0.3), CFrame.new(), skin)
	model.PrimaryPart = palm
	for f = 0, 3 do
		piece(model, "Finger", Vector3.new(0.2, 0.6, 0.25), CFrame.new(-0.36 + f * 0.24, 0.82, 0), skin)
	end
	piece(model, "Thumb", Vector3.new(0.25, 0.55, 0.25), CFrame.new(inward * 0.6, 0.15, 0) * CFrame.Angles(0, 0, -inward * 0.6), skin)
	piece(model, "Arm", Vector3.new(0.75, 1.6, 0.45), CFrame.new(0, -1.3, -0.05), sleeve)

	local item = Config.ITEM_BY_KEY[key or ""]
	if item then
		local shape = if item.shape == "ball" then Enum.PartType.Ball elseif item.shape == "cylinder" then Enum.PartType.Cylinder else nil
		local holding = piece(model, "Held", Vector3.new(0.85, 0.85, 0.85), CFrame.new(0, 0.15, 0.6), Theme.rgb(item.color), shape)
		holding:SetAttribute(Config.ATTR.itemKey, item.key)
		local glow = Instance.new("Highlight")
		glow.FillColor = Theme.GOLD
		glow.FillTransparency = 0.55
		glow.OutlineColor = Theme.PAPER
		glow.DepthMode = Enum.HighlightDepthMode.Occluded
		glow.Adornee = holding
		glow.Parent = holding
	end
	model.Parent = handsFolder
	return model
end

-- Rebuild both hands when what you're holding changes, or the view opens.
local function refreshHands()
	for _, hand in pairs(handModels) do
		hand.model:Destroy()
	end
	handModels = {}
	if not digging then
		return
	end
	for i = 1, slots do
		-- one free hand while pushing: the right one
		local spot = if slots == 1 then 2 else i
		handModels[i] = { model = buildHand(i, spot, held[i]), spot = spot }
	end
end

-- The hand (index) under a ray in the dig view, and the part hit, or nil.
local function handAt(ray)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { handsFolder }
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 10, params)
	local model = hit and hit.Instance:FindFirstAncestorOfClass("Model")
	return model and model:GetAttribute("Hand"), hit and hit.Instance
end

local function ask(on)
	if os.clock() - lastAsk < 0.25 then
		return
	end
	lastAsk = os.clock()
	digRemote:FireServer(on)
end

local function step()
	local model = digging and myTrolley()
	if not model then
		releaseCamera()
		return
	end
	local camera = Workspace.CurrentCamera
	local view = basketView(model)
	if not camera or not view then
		releaseCamera()
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = view
	cameraTaken = true
	if handsFolder.Parent ~= camera then
		handsFolder.Parent = camera -- parts under the camera are this client's only
	end
	for _, hand in pairs(handModels) do
		hand.model:PivotTo(view * HAND_SPOTS[hand.spot])
	end

	-- trying to walk away stops the rummage
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.MoveDirection.Magnitude > 0.1 then
		ask(false)
	end

	-- what's under the mouse: green on top (or in your hand), grey buried
	if UserInputService.MouseEnabled then
		local mouse = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		local handIndex, handPart = handAt(ray)
		if handIndex and held[handIndex] then
			local hand = handModels[handIndex]
			hover.Adornee = if hand then hand.model:FindFirstChild("Held") or handPart else handPart
			hover.Color3 = Theme.GOOD
			return
		end
		local part = itemAt(model, ray)
		hover.Adornee = part
		if part then
			local items = model:FindFirstChild("Items")
			local count = items and #items:GetChildren() or 0
			hover.Color3 = if Rules.reachable(part:GetAttribute("Slot") or 0, count) then Theme.GOOD else Theme.MUTED
		end
	end
end

local function onInput(input, processed)
	if processed or not digging then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local model = myTrolley()
	local camera = Workspace.CurrentCamera
	if not model or not camera then
		return
	end
	-- InputObject positions leave out the top bar; ScreenPointToRay allows for it
	local ray = camera:ScreenPointToRay(input.Position.X, input.Position.Y)
	local handIndex = handAt(ray)
	if handIndex then
		putBack(handIndex) -- your hands are in front of the basket: they come first
		return
	end
	local part = itemAt(model, ray)
	if part then
		takeRemote:FireServer(part:GetAttribute("Slot"), part:GetAttribute(Config.ATTR.itemKey))
	end
end

function Rummage.start()
	digRemote = Remotes.get("Dig")
	takeRemote = Remotes.get("TakeOut")
	putRemote = Remotes.get("PutBack")
	handsFolder = Instance.new("Folder")
	handsFolder.Name = "DigHandsView"

	hover = Instance.new("SelectionBox")
	hover.Name = "DigHover"
	hover.LineThickness = 0.05
	hover.Parent = Workspace

	Remotes.get("PlayerState").OnClientEvent:Connect(function(payload)
		local now = type(payload) == "table" and payload.inRound == true and payload.digging == true
		local nowHeld = if type(payload) == "table" and type(payload.handItems) == "table" then payload.handItems else {}
		local nowSlots = if type(payload) == "table" and type(payload.handSlots) == "number" then payload.handSlots else Config.HAND_SLOTS
		local changed = now ~= digging or nowSlots ~= slots or table.concat(nowHeld, ",") ~= table.concat(held, ",")
		held = nowHeld
		slots = nowSlots
		if now ~= digging then
			digging = now
			if not digging then
				releaseCamera()
			end
		end
		if changed then
			refreshHands()
		end
	end)

	-- 1 and 2 put a hand back while digging; otherwise they do whatever else they do
	ContextActionService:BindAction("SweepPutBack", function(_, inputState, input)
		if not digging then
			return Enum.ContextActionResult.Pass
		end
		if inputState == Enum.UserInputState.Begin then
			putBack(if input.KeyCode == Enum.KeyCode.One then 1 else 2)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.One, Enum.KeyCode.Two)

	ContextActionService:BindAction("SweepDig", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			ask(not digging)
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.R, Enum.KeyCode.ButtonX)
	ContextActionService:SetTitle("SweepDig", "DIG")
	ContextActionService:SetPosition("SweepDig", UDim2.new(1, -330, 1, -110))

	UserInputService.InputBegan:Connect(onInput)
	-- Heartbeat, not RenderStepped: RenderStepped stops when a Studio
	-- viewport isn't drawing.
	RunService.Heartbeat:Connect(step)
end

return Rummage
