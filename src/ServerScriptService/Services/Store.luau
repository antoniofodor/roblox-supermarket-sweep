-- Builds Sweep Mart in code: the store, its shelves, the tills, the shutters
-- and the lobby outside. Also stocks the shelves each round and moves the
-- shutters. A fresh empty place plus this repo gives the identical world.
--
-- Layout (studs). The store is a box x -80..80, z -102..50 with its front on
-- +Z. Outside the front is the lobby, where players wait between rounds.
--
--   back wall  z -102: fridges (milk, cheese, eggs, steak)
--   z -84 .. -50     : back block of six parallel aisles
--   z -50 .. -30     : cross aisle
--   z -30 .. 4       : front block of six parallel aisles
--   x -66            : produce island (bananas, apples), beside the front block
--   z 18 .. 32       : till lanes, centred x 20, 30, 40 ...
--   z 33             : the counter line; nobody gets past it but by the tills
--   x -58 .. -44     : entrance door in the front wall (players are teleported
--                      in at doors open; it stays shut)
--   x -40 .. 40      : front window, which the shutter comes down over
--   x 69, z -40      : the flash sale stand, right-hand end of the cross aisle
--
-- Yuck food (zone "beside") has no shelf of its own: each round it goes into
-- spare slots of the kinds it names (sprouts among the fruit, peas among the
-- snacks, spinach among the steak and cheese), so it sits right next to the
-- food players want.
--
-- Every shelf face, fridge kind and half of the fruit table is a SECTION:
-- ramming one shakes 1-3 of its items onto the floor (Store.shelfHit and
-- Store.shake). An item knows its section by attribute, so only stock still
-- on a shelf can fall.
--
-- Everything a player can touch is anchored. Shelf items are CanCollide off:
-- they are prompts with a shape, not obstacles. Ledges are CanCollide off
-- too: each shelf and the fridge run has one invisible flat wall over its
-- whole footprint instead. Solid ledges every 3 studs read to Roblox as a
-- ladder (players started climbing the shelves) and made steps to jump up
-- onto the shelf tops.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Theme = require(Shared.Theme)
local Rules = require(Shared.Rules)

local Fx = require(script.Parent.Fx)

local Store = {}

local HALF_X = 80
-- The front wall (entrance, window, tills, lobby) stays put at FRONT_Z; the
-- store grows backwards from it.
local FRONT_Z, BACK_Z = 50, -102
local MID_Z = (FRONT_Z + BACK_Z) / 2
local WALL_H, WALL_T = 22, 2
local FLOOR_Y = 0.2 -- top of the store floor
Store.FLOOR_Y = FLOOR_Y
Store.FRONT_Z = FRONT_Z

-- Aisles fit two trolleys side by side: shelves sit 19 apart, and a shelf
-- with a ledge on each side is 6.2 across, which leaves 12.8 studs of floor.
local SHELF_XS = { -40, -21, -2, 17, 36, 55 }
-- Three levels (designer, 2026-10-05; was two): a 10-stud shelf can't be
-- seen or jumped over, so each aisle is its own space and rams come round
-- corners. The top level's items are still in grab reach from the floor.
local SHELF_LEVELS = 3
local LEVEL_GAP = 3
local FIRST_LEVEL = 1.5 -- the bottom ledge's top, above the floor
local SHELF_H = FIRST_LEVEL + (SHELF_LEVELS - 1) * LEVEL_GAP + 2.5
-- Two blocks of the same parallel aisles, with a cross aisle between them.
local SHELF_BLOCKS = {
	{ name = "Front", z0 = -30, z1 = 4 },
	{ name = "Back", z0 = -84, z1 = -50 },
}
local LANE_W = 10
local LANE_X0 = 20 -- centre of till lane 1
local LANE_Z0, LANE_Z1 = 18, 32
local COUNTER_Z = 33
local WINDOW_X = 40 -- the window spans -WINDOW_X..WINDOW_X
local WINDOW_TOP = 12

local W = Theme.WORLD

local root -- Folder "SweepMart" in Workspace
local stockFolder
local slotsByKind = {} -- [itemKey] = { { cf, section } }: the base of each slot, facing out
local sections = {} -- [id] = { id, x0, x1, z0, z1, out, parts, centre, lastShake }
local SALE_X, SALE_Z = 69, -40
local SALE_TOP = FLOOR_Y + 2.4
local sale = nil -- { item, beam } while a flash sale is on
local shutters = {} -- { part, x, z, width, depth, top, bottom, tween }
local grabHandler = nil
local catchHandler = nil -- fn(key, landing, from) -> true if a trolley caught it (Fights)
local rng = Random.new()
local marks = {} -- [itemKey] = { text, color }: a tag over every item of that kind

Store.tills = {} -- [i] = { index, padCenter, halfX, zMin, zMax, pad, light, label }

-- ------------------------------------------------------------
-- builders
-- ------------------------------------------------------------

local function block(parent, name, size, cf, color, opts)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if opts then
		for key, value in pairs(opts) do
			p[key] = value
		end
	end
	p.Parent = parent
	return p
end

-- An invisible wall: keeps players out of places without being seen.
local function blocker(parent, name, size, cf)
	return block(parent, name, size, cf, Color3.new(1, 1, 1), {
		Transparency = 1,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	})
end

-- Text on one face of a part. `face` is the NormalId the text faces:
-- Front is -Z, Back is +Z.
local function sign(part, face, text, textColor)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Theme.DISPLAY
	label.TextScaled = true
	label.TextColor3 = textColor or W.signText
	label.Text = text
	label.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.1, 0)
	pad.PaddingBottom = UDim.new(0.1, 0)
	pad.PaddingLeft = UDim.new(0.04, 0)
	pad.PaddingRight = UDim.new(0.04, 0)
	pad.Parent = label
	return label
end

local function addSlot(key, cf, section)
	slotsByKind[key] = slotsByKind[key] or {}
	table.insert(slotsByKind[key], { cf = cf, section = section })
end

-- A shakeable box of floor (x0..x1, z0..z1). `out` points from it into the
-- aisle, which is where its items fall and the side a ram must come from.
local function addSection(id, x0, x1, z0, z1, out, parts)
	sections[id] = {
		id = id,
		x0 = x0,
		x1 = x1,
		z0 = z0,
		z1 = z1,
		out = out,
		parts = parts,
		centre = Vector3.new((x0 + x1) / 2, FLOOR_Y + 3, (z0 + z1) / 2),
		lastShake = -math.huge,
	}
end

local function kindsInZone(zone)
	local keys = {}
	for _, item in ipairs(Config.ITEMS) do
		if item.zone == zone then
			table.insert(keys, item.key)
		end
	end
	return keys
end

local function frontSegment(parent, name, x0, x1, y0, y1, color, opts)
	return block(
		parent,
		name,
		Vector3.new(x1 - x0, y1 - y0, WALL_T),
		CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, FRONT_Z + WALL_T / 2),
		color,
		opts
	)
end

local function buildShell(parent)
	block(parent, "Ground", Vector3.new(420, 2, 420), CFrame.new(0, -1, 20), W.ground, { Material = Enum.Material.Grass })
	block(parent, "Floor", Vector3.new(HALF_X * 2, 0.2, FRONT_Z - BACK_Z), CFrame.new(0, FLOOR_Y - 0.1, MID_Z), W.floor)

	local sideLen = FRONT_Z - BACK_Z + WALL_T * 2
	block(parent, "WallLeft", Vector3.new(WALL_T, WALL_H, sideLen), CFrame.new(-HALF_X - WALL_T / 2, WALL_H / 2, MID_Z), W.wall)
	block(parent, "WallRight", Vector3.new(WALL_T, WALL_H, sideLen), CFrame.new(HALF_X + WALL_T / 2, WALL_H / 2, MID_Z), W.wall)
	block(parent, "WallBack", Vector3.new(HALF_X * 2, WALL_H, WALL_T), CFrame.new(0, WALL_H / 2, BACK_Z - WALL_T / 2), W.wall)
	-- red trim band along the top of the walls, so the store reads as a shop
	block(parent, "TrimBack", Vector3.new(HALF_X * 2, 1.5, 0.4), CFrame.new(0, WALL_H - 2, BACK_Z + 0.2), W.trim)

	-- front wall: solid, entrance door, solid, window, solid
	local outer = HALF_X + WALL_T
	frontSegment(parent, "FrontLeft", -outer, -58, 0, WALL_H, W.wall)
	frontSegment(parent, "FrontOverDoor", -58, -44, 12, WALL_H, W.wall)
	frontSegment(parent, "FrontMid", -44, -WINDOW_X, 0, WALL_H, W.wall)
	frontSegment(parent, "FrontOverWindow", -WINDOW_X, WINDOW_X, WINDOW_TOP, WALL_H, W.wall)
	frontSegment(parent, "FrontRight", WINDOW_X, outer, 0, WALL_H, W.wall)
	frontSegment(parent, "Window", -WINDOW_X, WINDOW_X, 0, WINDOW_TOP, W.glass, {
		Material = Enum.Material.Glass,
		Transparency = 0.55,
		CastShadow = false,
	})
	frontSegment(parent, "EntranceDoor", -58, -44, 0, 12, W.glass, {
		Material = Enum.Material.Glass,
		Transparency = 0.35,
	})

	-- store sign over the front, facing the lobby
	local storeSign = block(parent, "StoreSign", Vector3.new(60, 7, 1), CFrame.new(0, WALL_H + 3, FRONT_Z + 1.5), W.sign)
	sign(storeSign, Enum.NormalId.Back, "SWEEP MART")
	local entranceSign = block(parent, "EntranceSign", Vector3.new(14, 2.4, 0.4), CFrame.new(-51, 13.6, FRONT_Z + WALL_T + 0.2), W.sign)
	sign(entranceSign, Enum.NormalId.Back, "ENTRANCE")

	-- exit door, inside the store behind the counter line (decoration: checking
	-- out is what takes you outside)
	block(parent, "ExitDoor", Vector3.new(8, 11, 0.2), CFrame.new(56, FLOOR_Y + 5.5, FRONT_Z - 0.15), W.exitDoor)
	local exitSign = block(parent, "ExitSign", Vector3.new(8, 2, 0.3), CFrame.new(56, FLOOR_Y + 14.5, FRONT_Z - 0.2), W.sign)
	sign(exitSign, Enum.NormalId.Front, "EXIT")
end

local function buildShutter(parent, name, x, width, top)
	local depth = 0.4
	local z = FRONT_Z - 0.7
	local bottom = FLOOR_Y - 0.05
	local s = { x = x, z = z, width = width, depth = depth, top = top, bottom = bottom, tween = nil }
	s.part = block(parent, name, Vector3.new(width, 0.4, depth), CFrame.new(x, top - 0.2, z), W.shutter, {
		Material = Enum.Material.Metal,
	})
	-- housing the shutter rolls into
	block(parent, name .. "Housing", Vector3.new(width + 1, 1.4, 1.2), CFrame.new(x, top + 0.7, z - 0.2), W.register)
	table.insert(shutters, s)
end

local function shutterGoal(s, bottomY)
	local height = math.max(s.top - bottomY, 0.4)
	return Vector3.new(s.width, height, s.depth), CFrame.new(s.x, s.top - height / 2, s.z)
end

local function buildFridges(parent)
	local width = HALF_X * 2 - 20
	local z = BACK_Z + 2
	block(parent, "Fridges", Vector3.new(width, 9, 4), CFrame.new(0, FLOOR_Y + 4.5, z), W.fridge)
	local frontZ = z + 2
	local ledgeZ = frontZ + 0.8
	local levels = { FLOOR_Y + 1.6, FLOOR_Y + 4.8 }
	for i, top in ipairs(levels) do
		block(parent, "FridgeLedge" .. i, Vector3.new(width, 0.3, 1.6), CFrame.new(0, top - 0.15, ledgeZ), W.fridgeLedge, { CanCollide = false })
	end
	-- one flat wall over the fridges and their ledges: nothing to climb
	local wallDepth = ledgeZ + 0.8 - BACK_Z
	blocker(parent, "FridgeWall", Vector3.new(width, 9, wallDepth), CFrame.new(0, FLOOR_Y + 4.5, BACK_Z + wallDepth / 2))

	local kinds = kindsInZone("fridge")
	local segment = width / #kinds
	local x0 = -width / 2
	for k, key in ipairs(kinds) do
		local left = x0 + (k - 1) * segment
		local centre = left + segment / 2
		local id = "Fridge_" .. key
		local x = left + 1.6
		while x <= left + segment - 1.6 do
			for _, top in ipairs(levels) do
				-- facing +Z, into the store
				addSlot(key, CFrame.new(x, top, ledgeZ) * CFrame.Angles(0, math.pi, 0), id)
			end
			x += 2.6
		end
		local header = block(parent, "FridgeSign_" .. key, Vector3.new(segment - 2, 1.6, 0.4), CFrame.new(centre, FLOOR_Y + 10, frontZ - 0.1), W.sign)
		sign(header, Enum.NormalId.Back, Config.ITEM_BY_KEY[key].name)
		addSection(id, left, left + segment, BACK_Z, ledgeZ + 0.8, Vector3.new(0, 0, 1), { header })
	end
end

local function buildProduce(parent)
	local cx, cz = -66, -10
	local length = 26
	local tableTop = block(parent, "ProduceTable", Vector3.new(10, 3, length), CFrame.new(cx, FLOOR_Y + 1.5, cz), W.produce)
	local top = FLOOR_Y + 3
	local kinds = kindsInZone("produce")
	local columns = { { -3.5, -1.5 }, { 1.5, 3.5 } }
	for k, key in ipairs(kinds) do
		-- each kind has one half of the table, and falls off that side
		local side = if k % 2 == 1 then -1 else 1
		local id = "Produce_" .. key
		for _, dx in ipairs(columns[((k - 1) % #columns) + 1]) do
			for z = cz - length / 2 + 2, cz + length / 2 - 2, 4 do
				addSlot(key, CFrame.new(cx + dx, top, z), id)
			end
		end
		addSection(id, math.min(cx, cx + side * 5), math.max(cx, cx + side * 5), cz - length / 2, cz + length / 2, Vector3.new(side, 0, 0), { tableTop })
	end
	local header = block(parent, "ProduceSign", Vector3.new(10, 2, 0.4), CFrame.new(cx, FLOOR_Y + 6, cz + length / 2 + 0.2), W.sign)
	sign(header, Enum.NormalId.Back, "FRUIT")
end

local function buildAisles(parent)
	local kinds = kindsInZone("aisle")
	local levels = {}
	for i = 1, SHELF_LEVELS do
		levels[i] = FLOOR_Y + FIRST_LEVEL + (i - 1) * LEVEL_GAP
	end
	local face = 0 -- counts every shelf face in the store, so each kind gets faces in both blocks
	for _, blk in ipairs(SHELF_BLOCKS) do
		local length = blk.z1 - blk.z0
		local cz = (blk.z0 + blk.z1) / 2
		for s, sx in ipairs(SHELF_XS) do
			local id = blk.name .. s
			local shelf = block(parent, "Shelf" .. id, Vector3.new(3, SHELF_H, length), CFrame.new(sx, FLOOR_Y + SHELF_H / 2, cz), W.shelf)
			-- one flat wall over the shelf and both rows of ledges: nothing to climb
			blocker(parent, "ShelfWall" .. id, Vector3.new(6.2, SHELF_H, length), CFrame.new(sx, FLOOR_Y + SHELF_H / 2, cz))
			local faceKinds = {}
			for _, side in ipairs({ -1, 1 }) do
				face += 1
				local key = kinds[((face - 1) % #kinds) + 1]
				table.insert(faceKinds, Config.ITEM_BY_KEY[key].name)
				local lx = sx + side * 2.3
				local sectionId = ("%s_%d"):format(id, side)
				local parts = { shelf }
				for i, top in ipairs(levels) do
					local ledge = block(parent, ("Ledge%s_%d_%d"):format(id, side, i), Vector3.new(1.6, 0.3, length), CFrame.new(lx, top - 0.15, cz), W.ledge, { CanCollide = false })
					table.insert(parts, ledge)
					for z = blk.z0 + 2, blk.z1 - 2, 4 do
						-- facing out into the aisle
						addSlot(key, CFrame.new(lx, top, z) * CFrame.Angles(0, -side * math.pi / 2, 0), sectionId)
					end
				end
				-- this face is the half of the shelf on its own side
				local outer = sx + side * 3.1
				addSection(sectionId, math.min(sx, outer), math.max(sx, outer), blk.z0, blk.z1, Vector3.new(side, 0, 0), parts)
			end
			-- a sign on each end of the shelf, naming both faces
			local text = faceKinds[1] .. string.char(10) .. faceKinds[2]
			local front = block(parent, "ShelfSignFront" .. id, Vector3.new(3.2, 2.4, 0.3), CFrame.new(sx, FLOOR_Y + SHELF_H + 1.4, blk.z1 + 0.2), W.sign)
			sign(front, Enum.NormalId.Back, text)
			local back = block(parent, "ShelfSignBack" .. id, Vector3.new(3.2, 2.4, 0.3), CFrame.new(sx, FLOOR_Y + SHELF_H + 1.4, blk.z0 - 0.2), W.sign)
			sign(back, Enum.NormalId.Front, text)
		end
	end
end

local function laneCentre(i)
	return LANE_X0 + (i - 1) * LANE_W
end

local function buildTills(parent)
	local laneLen = LANE_Z1 - LANE_Z0
	local laneMid = (LANE_Z0 + LANE_Z1) / 2
	for k = 0, Config.TILL_COUNT do
		local x = laneCentre(1) - LANE_W / 2 + k * LANE_W
		block(parent, "LaneDivider" .. k, Vector3.new(1.2, 3.5, laneLen), CFrame.new(x, FLOOR_Y + 1.75, laneMid), W.counter)
		-- no hopping between lanes to jump the queue
		blocker(parent, "LaneBlocker" .. k, Vector3.new(1.2, 14, laneLen), CFrame.new(x, FLOOR_Y + 3.5 + 7, laneMid))
	end

	-- the counter line: the only way past it is checking out
	local x0, x1 = -20, HALF_X
	local cx = (x0 + x1) / 2
	block(parent, "CounterLine", Vector3.new(x1 - x0, 3.5, 2), CFrame.new(cx, FLOOR_Y + 1.75, COUNTER_Z), W.counter)
	blocker(parent, "CounterBlocker", Vector3.new(x1 - x0, WALL_H, 2), CFrame.new(cx, FLOOR_Y + 3.5 + WALL_H / 2, COUNTER_Z))

	for i = 1, Config.TILL_COUNT do
		local c = laneCentre(i)
		local padCenter = Vector3.new(c - 1.2, FLOOR_Y, 29.5)
		local pad = block(parent, "TillPad" .. i, Vector3.new(6, 0.1, 5), CFrame.new(padCenter.X, FLOOR_Y + 0.05, padCenter.Z), W.pad, {
			Material = Enum.Material.Neon,
			CanCollide = false,
		})
		block(parent, "Register" .. i, Vector3.new(2.2, 3.5, 4), CFrame.new(c + 3.3, FLOOR_Y + 1.75, 29.5), W.register)
		local light = block(parent, "TillSign" .. i, Vector3.new(8, 2.6, 0.3), CFrame.new(c, FLOOR_Y + 11, LANE_Z0 - 0.5), W.register)
		local label = sign(light, Enum.NormalId.Front, ("TILL %d\nOPEN"):format(i), W.pad)
		Store.tills[i] = {
			index = i,
			padCenter = padCenter,
			halfX = 3.4,
			zMin = 26.8,
			zMax = COUNTER_Z,
			pad = pad,
			label = label,
		}
	end

	buildShutter(parent, "WindowShutter", 0, WINDOW_X * 2, FLOOR_Y + WINDOW_TOP)
	buildShutter(parent, "ExitShutter", 56, 9, FLOOR_Y + 11)
end

local function buildSaleStand(parent)
	-- a round pedestal (a cylinder's axis is X, so it is turned upright)
	block(parent, "SaleStand", Vector3.new(SALE_TOP - FLOOR_Y, 4, 4), CFrame.new(SALE_X, (FLOOR_Y + SALE_TOP) / 2, SALE_Z) * CFrame.Angles(0, 0, math.pi / 2), W.sign, {
		Shape = Enum.PartType.Cylinder,
	})
	-- a board on the right-hand wall, facing back down the cross aisle (-X)
	local board = block(parent, "SaleBoard", Vector3.new(0.4, 3, 14), CFrame.new(HALF_X - 0.4, 13, SALE_Z), W.sign)
	sign(board, Enum.NormalId.Left, "FLASH SALE")
end

local function buildLobby(parent)
	local z0, z1 = FRONT_Z + WALL_T, FRONT_Z + 48
	local cz = (z0 + z1) / 2
	block(parent, "LobbyFloor", Vector3.new(HALF_X * 2, 0.2, z1 - z0), CFrame.new(0, 0.1, cz), W.lobby)
	block(parent, "FenceFront", Vector3.new(HALF_X * 2, 3, 1), CFrame.new(0, 1.5, z1), W.fence)
	block(parent, "FenceLeft", Vector3.new(1, 3, z1 - z0), CFrame.new(-HALF_X, 1.5, cz), W.fence)
	block(parent, "FenceRight", Vector3.new(1, 3, z1 - z0), CFrame.new(HALF_X, 1.5, cz), W.fence)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(16, 0.4, 10)
	spawn.CFrame = CFrame.new(0, 0.3, z1 - 14)
	spawn.Color = W.spawn
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = parent
end

-- ------------------------------------------------------------
-- public
-- ------------------------------------------------------------

function Store.build()
	-- A fresh baseplate place brings its own Baseplate and SpawnLocation. The
	-- spawn sits inside the store and the baseplate's top is coplanar with our
	-- ground, so both go (this only changes the running game, not the file).
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("SpawnLocation") or (child:IsA("BasePart") and child.Name == "Baseplate") then
			warn(("[Store] removed the place's own %s; this game builds its own world"):format(child.Name))
			child:Destroy()
		end
	end

	root = Instance.new("Folder")
	root.Name = "SweepMart"
	local structure = Instance.new("Folder")
	structure.Name = "Structure"
	structure.Parent = root

	buildShell(structure)
	buildFridges(structure)
	buildProduce(structure)
	buildAisles(structure)
	buildTills(structure)
	buildSaleStand(structure)
	buildLobby(structure)

	stockFolder = Instance.new("Folder")
	stockFolder.Name = "Stock"
	stockFolder.Parent = root
	root.Parent = Workspace

	for _, item in ipairs(Config.ITEMS) do
		local count = 0
		if item.zone == "beside" then
			-- the spare slots of the kinds it sits beside
			for _, key in ipairs(item.beside) do
				count += #(slotsByKind[key] or {}) - Config.ITEM_BY_KEY[key].stock
			end
		else
			count = #(slotsByKind[item.key] or {})
		end
		if count < item.stock then
			warn(("[Store] %s has %d slots for %d stock"):format(item.key, count, item.stock))
		end
	end
end

function Store.setGrabHandler(fn)
	grabHandler = fn
end

-- Who gets a falling item before it hits the floor: Fights registers a
-- function that drops it into a trolley basket underneath, if there is one.
-- (A registry, because Fights requires Store.)
function Store.setCatchHandler(fn)
	catchHandler = fn
end

-- A small tag over an item ("x3 CRAVING"), sized in studs.
local function addMark(part, mark)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Mark"
	gui.Size = UDim2.fromScale(4.2, 1.2) -- studs
	gui.StudsOffset = Vector3.new(0, 1.6, 0)
	gui.MaxDistance = 70
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Theme.DISPLAY
	label.TextScaled = true
	label.Text = mark.text
	label.TextColor3 = mark.color
	label.TextStrokeColor3 = Theme.INK
	label.TextStrokeTransparency = 0
	label.Parent = gui
end

local function makeItem(item, slotCF, section)
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
	p.Name = item.key
	p.Size = Vector3.new(item.size[1], item.size[2], item.size[3])
	local height = if item.shape == "cylinder" then item.size[1] else item.size[2]
	local cf = slotCF * CFrame.new(0, height / 2 + 0.02, 0)
	if item.shape == "cylinder" then
		cf = cf * CFrame.Angles(0, 0, math.pi / 2)
	end
	p.CFrame = cf
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.Color = Theme.rgb(item.color)
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p:SetAttribute(Config.ATTR.itemKey, item.key)
	if section then
		p:SetAttribute(Config.ATTR.section, section)
	end
	if item.flash then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = Theme.GOLD
		sparkles.Parent = p
		local light = Instance.new("PointLight")
		light.Color = Theme.GOLD
		light.Brightness = 2
		light.Range = 10
		light.Parent = p
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Grab"
	prompt.ActionText = "Grab"
	prompt.ObjectText = ("%s  %s"):format(item.name, Rules.formatYum(item.yum))
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Config.GRAB_RANGE
	prompt.RequiresLineOfSight = false
	prompt.Parent = p
	prompt.Triggered:Connect(function(player)
		if grabHandler then
			grabHandler(player, p)
		end
	end)

	if marks[item.key] then
		addMark(p, marks[item.key])
	end
	p.Parent = stockFolder
	return p
end

local function shuffled(list)
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = rng:NextInteger(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

-- Clears the shelves and puts out a fresh round's stock in random slots:
-- every kind on its own shelves first, then yuck in the spare slots beside
-- the kinds it names.
function Store.restock()
	Store.endFlashSale()
	Store.clearMarks()
	stockFolder:ClearAllChildren()
	for _, section in pairs(sections) do
		section.lastShake = -math.huge
	end
	local spare = {} -- [itemKey] = the slots of that kind left empty
	for _, item in ipairs(Config.ITEMS) do
		if item.zone ~= "beside" then
			local slots = shuffled(slotsByKind[item.key] or {})
			for i = 1, math.min(item.stock, #slots) do
				makeItem(item, slots[i].cf, slots[i].section)
			end
			spare[item.key] = { table.unpack(slots, item.stock + 1) }
		end
	end
	for _, item in ipairs(Config.ITEMS) do
		if item.zone == "beside" then
			local slots = {}
			for _, key in ipairs(item.beside) do
				for _, slot in ipairs(spare[key] or {}) do
					table.insert(slots, slot)
				end
			end
			slots = shuffled(slots)
			local used = {}
			for i = 1, math.min(item.stock, #slots) do
				makeItem(item, slots[i].cf, slots[i].section)
				used[slots[i]] = true
			end
			-- a slot used here is no longer spare for the next yuck kind
			for _, key in ipairs(item.beside) do
				local left = {}
				for _, slot in ipairs(spare[key] or {}) do
					if not used[slot] then
						table.insert(left, slot)
					end
				end
				spare[key] = left
			end
		end
	end
end

-- Tag every item of a kind, on the shelves and on the floor, and anything of
-- that kind put out later this round (a knocked-out or thrown one).
function Store.markKind(key, text, color)
	marks[key] = { text = text, color = color }
	for _, part in ipairs(stockFolder:GetChildren()) do
		if part:GetAttribute(Config.ATTR.itemKey) == key and not part:FindFirstChild("Mark") then
			addMark(part, marks[key])
		end
	end
end

function Store.clearMarks()
	marks = {}
	for _, part in ipairs(stockFolder:GetChildren()) do
		local mark = part:FindFirstChild("Mark")
		if mark then
			mark:Destroy()
		end
	end
end

function Store.stockCount()
	return #stockFolder:GetChildren()
end

-- Shutters: lowered over `seconds` so everybody can watch them come down.
local function moveShutters(seconds, toBottom)
	for _, s in ipairs(shutters) do
		if s.tween then
			s.tween:Cancel()
		end
		local size, cf = shutterGoal(s, if toBottom then s.bottom else s.top - 0.4)
		if seconds <= 0 then
			s.part.Size = size
			s.part.CFrame = cf
		else
			s.tween = TweenService:Create(s.part, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Size = size, CFrame = cf })
			s.tween:Play()
		end
	end
end

function Store.lowerShutters(seconds)
	moveShutters(seconds, true)
end

function Store.raiseShutters(seconds)
	moveShutters(seconds, false)
end

function Store.setTillStatus(i, text, busy)
	local till = Store.tills[i]
	if not till then
		return
	end
	local line = ("TILL %d\n%s"):format(i, text)
	if till.label.Text ~= line then
		till.label.Text = line
	end
	local color = if busy then W.padBusy else W.pad
	if till.pad.Color ~= color then
		till.pad.Color = color
		till.label.TextColor3 = color
	end
end

-- Whether a root position is standing on till i's pad.
function Store.onPad(i, position)
	local till = Store.tills[i]
	return math.abs(position.X - till.padCenter.X) <= till.halfX
		and position.Z >= till.zMin
		and position.Z <= till.zMax
		and position.Y < FLOOR_Y + 8
end

-- Whether a position is in the till lanes or just in front of them: where
-- a queue stands (the scorecard counts it at closing).
function Store.inTillLanes(position)
	local x0 = laneCentre(1) - LANE_W / 2
	local x1 = laneCentre(Config.TILL_COUNT) + LANE_W / 2
	return position.X >= x0 and position.X <= x1 and position.Z >= LANE_Z0 - 6 and position.Z <= COUNTER_Z
end

function Store.onAnyPad(position)
	for i in ipairs(Store.tills) do
		if Store.onPad(i, position) then
			return true
		end
	end
	return false
end

-- The walls, shelves and counters: what a thrown item can't pass through.
function Store.structure()
	return root and root:FindFirstChild("Structure")
end

function Store.root()
	return root
end

-- The front window's glass: what Chonk bangs on.
function Store.window()
	local structure = Store.structure()
	return structure and structure:FindFirstChild("Window")
end

-- A point on the shop floor a player can reach: inside the walls and in
-- front of the counter line.
function Store.clampToFloor(position)
	return Vector3.new(
		math.clamp(position.X, -HALF_X + 3, HALF_X - 3),
		FLOOR_Y,
		math.clamp(position.Z, BACK_Z + 6, COUNTER_Z - 3)
	)
end

-- An item flying from `from` to where it was placed, in a short hop, so a
-- ram or a shake is seen knocking it out. Moved on the server: a few parts
-- for under half a second.
local HOP_SECONDS = 0.45
local function hop(part, from)
	local target = part.CFrame
	local spin = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * 9
	local started = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local a = math.min(1, (os.clock() - started) / HOP_SECONDS)
		if not part.Parent or a >= 1 then
			connection:Disconnect()
			if part.Parent then
				part.CFrame = target
			end
			return
		end
		-- a straight line from where it left to where it lands, bowed 1.5 studs up
		local position = from:Lerp(target.Position, a) + Vector3.new(0, 6 * a * (1 - a), 0)
		local r = spin * (1 - a)
		part.CFrame = CFrame.new(position) * CFrame.Angles(r.X, r.Y, r.Z) * target.Rotation
	end)
end

-- An item lying on the floor (knocked out, thrown, or dropped). Grabbed with
-- the same prompt as a shelf item, by anybody. Cleared at the next restock.
-- With `from`, it hops there from that point instead of just appearing.
function Store.dropItem(key, position, from)
	local item = Config.ITEM_BY_KEY[key]
	if not item then
		return nil
	end
	local spot = Store.clampToFloor(position)
	local part = makeItem(item, CFrame.new(spot) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
	if typeof(from) == "Vector3" then
		hop(part, from)
	end
	return part
end

-- ------------------------------------------------------------
-- shaking shelves
-- ------------------------------------------------------------

-- The section a trolley nose at `point`, moving at `velocity`, has just
-- rammed: the nose is in it, and it's moving into its face rather than
-- along it. nil if none.
function Store.shelfHit(point, velocity)
	local flatVel = Vector3.new(velocity.X, 0, velocity.Z)
	if flatVel.Magnitude < 0.01 then
		return nil
	end
	local dir = flatVel.Unit
	for id, section in pairs(sections) do
		if
			point.X >= section.x0 - 0.4
			and point.X <= section.x1 + 0.4
			and point.Z >= section.z0 - 0.4
			and point.Z <= section.z1 + 0.4
			and dir:Dot(-section.out) >= 0.5
		then
			return id
		end
	end
	return nil
end

-- Shake a section: 1 to 3 of the items still on it fall into the aisle.
-- Returns how many fell, or nil if it was shaken too recently.
function Store.shake(id)
	local section = sections[id]
	if not section then
		return nil
	end
	local t = os.clock()
	if t - section.lastShake < Config.SHAKE_COOLDOWN then
		return nil
	end
	section.lastShake = t

	local onShelf = {}
	for _, part in ipairs(stockFolder:GetChildren()) do
		if part:GetAttribute(Config.ATTR.section) == id then
			table.insert(onShelf, part)
		end
	end
	for i = #onShelf, 2, -1 do
		local j = rng:NextInteger(1, i)
		onShelf[i], onShelf[j] = onShelf[j], onShelf[i]
	end
	local count = math.min(#onShelf, rng:NextInteger(Config.SHAKE_DROP_MIN, Config.SHAKE_DROP_MAX))
	for i = 1, count do
		Store.fall(onShelf[i], section)
	end
	Fx.shake(section.parts, section.out, section.centre)
	return count
end

-- One item comes off its shelf into the aisle: into a trolley basket
-- underneath if there is one (catchHandler), otherwise onto the floor.
function Store.fall(part, section)
	local key = part:GetAttribute(Config.ATTR.itemKey)
	local from = part.Position
	part:Destroy()
	local out = section.out
	local across = Vector3.new(-out.Z, 0, out.X)
	local landing = Vector3.new(from.X, FLOOR_Y, from.Z) + out * rng:NextNumber(2.5, 4.5) + across * rng:NextNumber(-1.5, 1.5)
	if catchHandler and catchHandler(key, landing, from) then
		return
	end
	Store.dropItem(key, landing, from)
end

-- The section (if any) whose footprint holds `point`, whatever direction
-- anything is moving: for a trolley scraping along a shelf.
function Store.sectionAt(point)
	for id, section in pairs(sections) do
		if point.X >= section.x0 and point.X <= section.x1 and point.Z >= section.z0 and point.Z <= section.z1 then
			return id
		end
	end
	return nil
end

-- A scrape knocks one item off a section, straight into the scraper's
-- trolley: returns its key (the part is gone), or nil if the section is bare.
function Store.knockOne(id)
	local section = sections[id]
	if not section then
		return nil
	end
	local onShelf = {}
	for _, part in ipairs(stockFolder:GetChildren()) do
		if part:GetAttribute(Config.ATTR.section) == id then
			table.insert(onShelf, part)
		end
	end
	if #onShelf == 0 then
		return nil
	end
	local part = onShelf[rng:NextInteger(1, #onShelf)]
	local key = part:GetAttribute(Config.ATTR.itemKey)
	part:Destroy()
	Fx.shake(section.parts, section.out, section.centre)
	return key
end

-- Big Chonk's tantrum: every section in the store drops one item at once.
-- One sound for the whole store (the caller plays it), not one per shelf.
function Store.shakeAll()
	local t = os.clock()
	local fell = 0
	for id, section in pairs(sections) do
		section.lastShake = t
		local onShelf = {}
		for _, part in ipairs(stockFolder:GetChildren()) do
			if part:GetAttribute(Config.ATTR.section) == id then
				table.insert(onShelf, part)
			end
		end
		if #onShelf > 0 then
			Store.fall(onShelf[rng:NextInteger(1, #onShelf)], section)
			fell += 1
		end
		Fx.shake(section.parts, section.out, section.centre, true)
	end
	return fell
end

-- ------------------------------------------------------------
-- flash sale
-- ------------------------------------------------------------

Store.SALE_SPOT = Vector3.new(SALE_X, SALE_TOP, SALE_Z)

function Store.startFlashSale()
	Store.endFlashSale()
	local item = makeItem(Config.FLASH_ITEM, CFrame.new(SALE_X, SALE_TOP, SALE_Z))
	local gui = Instance.new("BillboardGui")
	gui.Name = "SaleTag"
	gui.Size = UDim2.fromScale(9, 2.2) -- studs
	gui.StudsOffset = Vector3.new(0, 3, 0)
	gui.AlwaysOnTop = true -- the point is that you can find it through the shelves
	gui.MaxDistance = 400
	gui.Parent = item
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Theme.DISPLAY
	label.TextScaled = true
	label.Text = ("FLASH SALE %s"):format(Rules.formatYum(Config.FLASH_ITEM.yum):upper())
	label.TextColor3 = Theme.GOLD
	label.TextStrokeColor3 = Theme.INK
	label.TextStrokeTransparency = 0
	label.Parent = gui
	-- a beam of light over the stand, seen from anywhere in the store
	local beam = block(root, "SaleBeam", Vector3.new(40, 1.4, 1.4), CFrame.new(SALE_X, SALE_TOP + 20, SALE_Z) * CFrame.Angles(0, 0, math.pi / 2), Theme.GOLD, {
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Neon,
		Transparency = 0.55,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	})
	sale = { item = item, beam = beam }
	Fx.playAll("flash")
end

-- Whether the turkey is still sitting on its stand, ungrabbed.
function Store.flashSaleLive()
	return sale ~= nil and sale.item.Parent ~= nil
end

-- Whether a sale's beam is still up (it comes down when the turkey is
-- grabbed or the sale runs out).
function Store.saleRunning()
	return sale ~= nil
end

-- Take the beam down, and the turkey too if nobody grabbed it. Returns
-- whether the turkey was still there.
function Store.endFlashSale()
	if not sale then
		return false
	end
	local wasThere = sale.item.Parent ~= nil
	if wasThere then
		sale.item:Destroy()
	end
	sale.beam:Destroy()
	sale = nil
	return wasThere
end

-- Spots, as root CFrames facing -Z (into the store from the front).
local function spot(x, z)
	return CFrame.new(x, FLOOR_Y + 3, z)
end

function Store.entranceSpots(count)
	local spots = {}
	for _, z in ipairs({ 38, 42, 46 }) do
		for x = -64, -26, 9.5 do
			table.insert(spots, spot(x, z))
		end
	end
	for i = #spots, 2, -1 do
		local j = rng:NextInteger(1, i)
		spots[i], spots[j] = spots[j], spots[i]
	end
	local out = {}
	for i = 1, count do
		local base = spots[((i - 1) % #spots) + 1]
		local lap = (i - 1) // #spots
		out[i] = base + Vector3.new(lap * 2, 0, 0)
	end
	return out
end

function Store.lobbySpot()
	return spot(rng:NextNumber(-40, 40), rng:NextNumber(FRONT_Z + 16, FRONT_Z + 36))
end

-- Where a player who has checked out stands: outside, at the window.
function Store.windowSpot()
	return spot(rng:NextNumber(-30, 30), FRONT_Z + 6)
end

return Store
