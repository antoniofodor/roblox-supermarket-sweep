-- Draws thrown items. The server flies each throw and decides what it hits;
-- this only shows the same arc on every screen, worked out from the launch
-- the server announced (ThrowFx) and Config.THROW_GRAVITY. It disappears when
-- the server says the flight is over (ThrowEnd), or after the longest flight.
--
-- A toilet roll (an item with `streamer`) unrolls a paper streamer along its
-- flight. When it lands, every bend of the streamer drops onto whatever is
-- under it, so a throw over the aisles leaves paper draped across the shelf
-- tops and the floor. Purely visual, and the same on every screen because
-- the arc is. Streamers stay until the round ends (oldest first past
-- STREAMER_MAX).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Projectiles = {}

local GRAVITY = Vector3.new(0, -Config.THROW_GRAVITY, 0)
local ATTR, PHASE = Config.ATTR, Config.PHASE
local PAPER = Color3.fromRGB(250, 250, 244)
local DROP_SECONDS = 0.35
local live = {} -- [id] = { part, origin, velocity, startedAt, spin, streamer? }
local streamers = {} -- oldest first: { points, strips, from?, to?, dropAt? }
local folder, paperFolder

-- ---------------- toilet roll streamers ----------------

local function newStrip()
	local strip = Instance.new("Part")
	strip.Name = "Paper"
	strip.Color = PAPER
	strip.Material = Enum.Material.SmoothPlastic
	strip.Anchored = true
	strip.CanCollide = false
	strip.CanQuery = false
	strip.CanTouch = false
	strip.CastShadow = false
	strip.Parent = paperFolder
	return strip
end

-- One flat strip of paper from a to b.
local function lay(strip, a, b)
	local along = b - a
	local length = along.Magnitude
	if length < 0.05 then
		strip.Transparency = 1
		return
	end
	strip.Transparency = 0
	strip.Size = Vector3.new(Config.STREAMER_WIDTH, 0.05, length)
	local up = if math.abs(along.Unit.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
	strip.CFrame = CFrame.lookAt((a + b) / 2, b, up)
end

-- Lay strips along points, adding strips as needed.
local function drawStreamer(streamer, points)
	for i = 1, #points - 1 do
		local strip = streamer.strips[i]
		if not strip then
			strip = newStrip()
			streamer.strips[i] = strip
		end
		lay(strip, points[i], points[i + 1])
	end
end

local function clearStreamer(streamer)
	streamer.gone = true -- a roll still in flight stops drawing it
	for _, strip in ipairs(streamer.strips) do
		strip:Destroy()
	end
	table.clear(streamer.strips)
end

local function clearAllStreamers()
	for _, streamer in ipairs(streamers) do
		clearStreamer(streamer)
	end
	table.clear(streamers)
end

-- Where paper above this point comes to rest: the first visible surface of
-- the store below it (invisible walls are skipped).
local function restingPoint(point)
	local store = Workspace:FindFirstChild("SweepMart")
	local structure = store and store:FindFirstChild("Structure")
	if not structure then
		return point
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { structure }
	local from = point
	for _ = 1, 6 do
		local hit = Workspace:Raycast(from, Vector3.new(0, -200, 0), params)
		if not hit then
			return point
		end
		if hit.Instance.Transparency < 1 then
			return hit.Position + Vector3.new(0, 0.06, 0)
		end
		from = hit.Position - Vector3.new(0, 0.05, 0)
	end
	return point
end

local function startStreamer(origin)
	local streamer = { points = { origin }, strips = {} }
	table.insert(streamers, streamer)
	while #streamers > Config.STREAMER_MAX do
		clearStreamer(table.remove(streamers, 1))
	end
	return streamer
end

-- The roll is in flight at `position`: unroll paper behind it.
local function unroll(streamer, position)
	if streamer.gone then
		return
	end
	local points = streamer.points
	if (position - points[#points]).Magnitude >= Config.STREAMER_SPACING then
		table.insert(points, position)
	end
	local drawn = table.clone(points)
	table.insert(drawn, position)
	drawStreamer(streamer, drawn)
end

-- The roll has landed at `position`: the paper falls onto what's under it.
local function settle(streamer, position)
	if streamer.gone then
		return
	end
	table.insert(streamer.points, position)
	streamer.from = streamer.points
	streamer.to = {}
	for i, point in ipairs(streamer.points) do
		streamer.to[i] = restingPoint(point)
	end
	streamer.dropAt = os.clock()
end

local function stepStreamers()
	for _, streamer in ipairs(streamers) do
		if streamer.dropAt then
			local t = math.clamp((os.clock() - streamer.dropAt) / DROP_SECONDS, 0, 1)
			local eased = t * t -- falls, rather than glides
			local points = {}
			for i, from in ipairs(streamer.from) do
				points[i] = from:Lerp(streamer.to[i], eased)
			end
			drawStreamer(streamer, points)
			if t >= 1 then
				streamer.dropAt = nil -- at rest; nothing more to draw
			end
		end
	end
end

-- ---------------- flights ----------------

local function onThrow(payload)
	if type(payload) ~= "table" or typeof(payload.origin) ~= "Vector3" or typeof(payload.velocity) ~= "Vector3" then
		return
	end
	local item = Config.ITEM_BY_KEY[payload.key]
	if not item then
		return
	end
	local part
	if item.shape == "ball" then
		part = Instance.new("Part")
		part.Shape = Enum.PartType.Ball
	elseif item.shape == "cylinder" then
		part = Instance.new("Part")
		part.Shape = Enum.PartType.Cylinder
	elseif item.shape == "wedge" then
		part = Instance.new("WedgePart")
	else
		part = Instance.new("Part")
	end
	part.Name = "Thrown_" .. item.key
	part.Size = Vector3.new(item.size[1], item.size[2], item.size[3])
	part.Color = Theme.rgb(item.color)
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CFrame = CFrame.new(payload.origin)
	part.Parent = folder
	live[payload.id] = {
		part = part,
		origin = payload.origin,
		velocity = payload.velocity,
		startedAt = payload.startedAt or Workspace:GetServerTimeNow(),
		spin = Vector3.new(math.random() * 2 - 1, math.random() * 2 - 1, math.random() * 2 - 1).Unit * 14,
		streamer = if item.streamer then startStreamer(payload.origin) else nil,
	}
end

local function land(id, flight)
	if flight.streamer then
		settle(flight.streamer, flight.part.Position)
	end
	flight.part:Destroy()
	live[id] = nil
end

local function onEnd(payload)
	local id = type(payload) == "table" and payload.id
	local flight = id and live[id]
	if flight then
		land(id, flight)
	end
end

local function step()
	local t = Workspace:GetServerTimeNow()
	for id, flight in pairs(live) do
		local age = math.max(0, t - flight.startedAt)
		if age > Config.THROW_MAX_SECONDS + 0.5 then
			land(id, flight)
		else
			local position = flight.origin + flight.velocity * age + GRAVITY * (age * age / 2)
			local s = flight.spin * age
			flight.part.CFrame = CFrame.new(position) * CFrame.Angles(s.X, s.Y, s.Z)
			if flight.streamer then
				unroll(flight.streamer, position)
			end
		end
	end
	stepStreamers()
end

function Projectiles.start()
	folder = Instance.new("Folder")
	folder.Name = "ThrownItems"
	folder.Parent = Workspace
	paperFolder = Instance.new("Folder")
	paperFolder.Name = "PaperStreamers"
	paperFolder.Parent = Workspace
	-- the store is tidied between rounds
	ReplicatedStorage:GetAttributeChangedSignal(ATTR.phase):Connect(function()
		if ReplicatedStorage:GetAttribute(ATTR.phase) ~= PHASE.shopping then
			clearAllStreamers()
		end
	end)
	Remotes.get("ThrowFx").OnClientEvent:Connect(onThrow)
	Remotes.get("ThrowEnd").OnClientEvent:Connect(onEnd)
	-- Heartbeat, not RenderStepped: RenderStepped stops when a Studio viewport
	-- isn't drawing, which would freeze thrown items mid-air in tests.
	RunService.Heartbeat:Connect(step)
end

return Projectiles
