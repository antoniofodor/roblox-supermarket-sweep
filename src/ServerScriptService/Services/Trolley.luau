-- The shopping trolley: the model, and moving it between "pushed" (welded in
-- front of its owner) and "parked" (anchored on the floor where they let go).
--
-- Every part is welded to one invisible Base part, so the server only ever
-- moves Base: anchored when parked, welded to the owner's root when pushed.
-- While pushed nothing collides (a collider welded to a character fights the
-- character's own physics); parked, Base collides so other shoppers bump it.
--
-- Built facing -Z (a character's LookVector), with the origin on the floor
-- at the middle of the trolley. The handle is at +Z, nearest the pusher.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Theme = require(Shared.Theme)
local Rules = require(Shared.Rules)

local Store = require(script.Parent.Store)

local Trolley = {}

local BASE_HEIGHT = 1.6 -- Base's centre above the floor
local HOLD_DISTANCE = 3.4 -- trolley centre ahead of the pusher's root
local WIRE = Color3.fromRGB(150, 160, 172)
local PLASTIC = Color3.fromRGB(226, 72, 60)
local TYRE = Color3.fromRGB(40, 40, 46)

local folder

local function piece(model, base, name, size, offset, color, shape)
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = base.CFrame * CFrame.new(0, -BASE_HEIGHT, 0) * offset
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Parent = model
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = base
	weld.Part1 = p
	weld.Parent = p
	return p
end

function Trolley.folder()
	if not folder or not folder.Parent then
		folder = Instance.new("Folder")
		folder.Name = "Trolleys"
		folder.Parent = workspace:WaitForChild("SweepMart")
	end
	return folder
end

-- A new trolley standing on the floor at `origin` (a floor-level CFrame).
function Trolley.build(player, origin)
	local model = Instance.new("Model")
	model.Name = "Trolley_" .. player.UserId
	model:SetAttribute(Config.ATTR.trolleyOwner, player.UserId)
	model:SetAttribute(Config.ATTR.trolleyPushed, false)

	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = Vector3.new(2.8, 3.0, 4.4)
	base.CFrame = origin * CFrame.new(0, BASE_HEIGHT, 0)
	base.Transparency = 1
	base.Anchored = true
	base.CanCollide = true
	base.CanTouch = false
	base.Massless = true
	base.Parent = model
	model.PrimaryPart = base

	-- basket: floor and four low walls
	piece(model, base, "BasketFloor", Vector3.new(2.6, 0.15, 3.6), CFrame.new(0, 1.4, -0.2), WIRE)
	piece(model, base, "BasketFront", Vector3.new(2.6, 1.6, 0.12), CFrame.new(0, 2.2, -2.0), WIRE)
	piece(model, base, "BasketBack", Vector3.new(2.6, 1.6, 0.12), CFrame.new(0, 2.2, 1.6), WIRE)
	piece(model, base, "BasketLeft", Vector3.new(0.12, 1.6, 3.6), CFrame.new(-1.3, 2.2, -0.2), WIRE)
	piece(model, base, "BasketRight", Vector3.new(0.12, 1.6, 3.6), CFrame.new(1.3, 2.2, -0.2), WIRE)
	-- red rim along the top, so the trolley reads from across the store
	piece(model, base, "Rim", Vector3.new(2.8, 0.18, 0.2), CFrame.new(0, 3.05, -2.0), PLASTIC)
	-- handle
	local handle = piece(model, base, "Handle", Vector3.new(2.8, 0.25, 0.25), CFrame.new(0, 3.4, 2.2), PLASTIC)
	piece(model, base, "HandlePostL", Vector3.new(0.12, 1.0, 0.12), CFrame.new(-1.3, 2.95, 1.95), WIRE)
	piece(model, base, "HandlePostR", Vector3.new(0.12, 1.0, 0.12), CFrame.new(1.3, 2.95, 1.95), WIRE)
	-- frame and wheels
	for _, x in ipairs({ -1.0, 1.0 }) do
		for _, z in ipairs({ -1.6, 1.4 }) do
			piece(model, base, "Leg", Vector3.new(0.12, 1.0, 0.12), CFrame.new(x, 0.95, z), WIRE)
			piece(model, base, "Wheel", Vector3.new(0.5, 0.5, 0.5), CFrame.new(x, 0.25, z), TYRE, Enum.PartType.Ball)
		end
	end

	-- The owner takes a parked trolley back with this. The server keeps it
	-- disabled; the owner's client switches it on for their own trolley only.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Push"
	prompt.ActionText = "Push"
	prompt.ObjectText = "Your trolley"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Config.TROLLEY_REACH - 1
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = handle

	-- Anybody else can steal from a parked trolley. Also disabled on the
	-- server; every other client switches it on while the trolley is parked
	-- and has something in it.
	local steal = Instance.new("ProximityPrompt")
	steal.Name = "Steal"
	steal.ActionText = "Steal"
	steal.ObjectText = player.DisplayName .. "'s trolley"
	steal.KeyboardKeyCode = Enum.KeyCode.E
	steal.HoldDuration = Config.STEAL_HOLD
	steal.MaxActivationDistance = Config.STEAL_REACH - 1
	steal.RequiresLineOfSight = false
	steal.Enabled = false
	steal.Parent = base

	model:SetAttribute(Config.ATTR.trolleyItems, 0)
	model:SetAttribute(Config.ATTR.trolleyOwnerName, player.DisplayName)

	local items = Instance.new("Folder")
	items.Name = "Items"
	items.Parent = model

	model.Parent = Trolley.folder()
	return model
end

-- The basket's pile: 3 across and 4 deep per layer (Config.PILE_LAYER), in
-- the order things went in, so later items lie on top of earlier ones. Each
-- part carries its place in the pile (Slot) and its item key, which is what
-- the dig view clicks. A little fixed jitter per slot makes it read as a
-- heap rather than a grid; the same slot always lies the same way.
local PILE_COLS = 3
local CELL_X, CELL_Z = 0.8, 0.85
local LAYER_H = 0.72
local PIECE = 0.72

local function jitter(slot, salt)
	local v = math.sin(slot * 12.9898 + salt * 78.233) * 43758.5453
	return (v - math.floor(v)) * 2 - 1 -- -1 .. 1, the same every time for this slot
end

function Trolley.setItems(model, keys)
	local base = model.PrimaryPart
	local items = model:FindFirstChild("Items")
	if not base or not items then
		return
	end
	model:SetAttribute(Config.ATTR.trolleyItems, #keys)
	items:ClearAllChildren()
	local floor = base.CFrame * CFrame.new(0, -BASE_HEIGHT + 1.48, -0.2)
	for i, key in ipairs(keys) do
		local item = Config.ITEM_BY_KEY[key]
		local layer, cell = Rules.pileCell(i)
		local col, row = cell % PILE_COLS, cell // PILE_COLS
		local offset = CFrame.new(
			(col - 1) * CELL_X + jitter(i, 1) * 0.08,
			PIECE / 2 + layer * LAYER_H,
			-1.3 + row * CELL_Z + jitter(i, 2) * 0.08
		) * CFrame.Angles(0, jitter(i, 3) * 0.35, jitter(i, 4) * 0.15)
		local p
		if item.shape == "ball" then
			p = Instance.new("Part")
			p.Shape = Enum.PartType.Ball
		elseif item.shape == "cylinder" then
			p = Instance.new("Part")
			p.Shape = Enum.PartType.Cylinder
		elseif item.shape == "wedge" then
			p = Instance.new("WedgePart")
		else
			p = Instance.new("Part")
		end
		p.Name = key
		p.Size = Vector3.new(PIECE, PIECE, PIECE)
		p.CFrame = floor * offset
		p.Color = Theme.rgb(item.color)
		p.Material = Enum.Material.SmoothPlastic
		p:SetAttribute("Slot", i)
		p:SetAttribute(Config.ATTR.itemKey, key)
		p.Anchored = false
		p.CanCollide = false
		p.CanQuery = true -- the dig view's click finds it; throws only test the store's structure
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = base
		weld.Part1 = p
		weld.Parent = p
		p.Parent = items
	end
end

local function groundOffset(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		return 3
	end
	return humanoid.HipHeight + root.Size.Y / 2
end

-- Weld the trolley in front of its owner.
function Trolley.attach(model, character)
	local base = model.PrimaryPart
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not base or not root then
		return false
	end
	local old = base:FindFirstChild("PushWeld")
	if old then
		old:Destroy()
	end
	base.Anchored = true
	base.CanCollide = false
	local origin = root.CFrame * CFrame.new(0, -groundOffset(character), -HOLD_DISTANCE)
	base.CFrame = origin * CFrame.new(0, BASE_HEIGHT, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Name = "PushWeld"
	weld.Part0 = root
	weld.Part1 = base
	weld.Parent = base
	base.Anchored = false
	model:SetAttribute(Config.ATTR.trolleyPushed, true)
	return true
end

-- Leave the trolley standing where it is, upright, on the floor.
function Trolley.park(model)
	local base = model.PrimaryPart
	if not base then
		return
	end
	local weld = base:FindFirstChild("PushWeld")
	if weld then
		weld:Destroy()
	end
	local cf = base.CFrame
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	end
	local position = Vector3.new(cf.X, Store.FLOOR_Y + BASE_HEIGHT, cf.Z)
	base.Anchored = true
	-- CFrame.lookAt aims -Z at the target, and the trolley is built facing -Z
	base.CFrame = CFrame.lookAt(position, position + look.Unit)
	base.CanCollide = true
	model:SetAttribute(Config.ATTR.trolleyPushed, false)
end

-- The middle of the trolley's front edge, which is what rams things.
function Trolley.nose(model)
	local base = model.PrimaryPart
	if not base then
		return nil
	end
	return (base.CFrame * CFrame.new(0, 0, -2.4)).Position
end

function Trolley.centre(model)
	local base = model.PrimaryPart
	return base and base.Position
end

function Trolley.distanceTo(model, position)
	local base = model.PrimaryPart
	if not base then
		return math.huge
	end
	local a = Vector3.new(base.Position.X, 0, base.Position.Z)
	return (a - Vector3.new(position.X, 0, position.Z)).Magnitude
end

function Trolley.clearAll()
	Trolley.folder():ClearAllChildren()
end

return Trolley
