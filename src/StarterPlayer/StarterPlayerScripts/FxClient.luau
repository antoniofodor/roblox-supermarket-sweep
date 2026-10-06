-- Draws what Services/Fx decides: sounds, a shelf wobbling, dizzy stars and
-- a camera jolt. Nothing here changes the game; it only shows it.
--
-- A sound is kept alive once loaded (a silent copy in SoundService), because
-- a fresh Sound only starts at once while another with the same id exists.
-- Positional sounds play from a throwaway part at the spot.
--
-- Everything moves on Heartbeat, not RenderStepped, which stops when a
-- Studio viewport isn't drawing.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local FxClient = {}

local player = Players.LocalPlayer
local cache -- SoundService folder of loaded copies, one per sound
local holder -- Workspace folder for positional emitters and stars
local wobbling = {} -- [BasePart] = { base = CFrame, until = number, out = Vector3 }
local stars = {} -- { { character, parts, until } }
local joltUntil = 0

local function makeSound(name)
	local spec = Config.SOUNDS[name]
	if not spec or spec.id == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = spec.id
	sound.Volume = spec.volume or 0.5
	sound.PlaybackSpeed = spec.pitch or 1
	return sound
end

local function play(name, at)
	local spec = Config.SOUNDS[name]
	local sound = makeSound(name)
	if not sound then
		return
	end
	if typeof(at) == "Vector3" then
		local emitter = Instance.new("Part")
		emitter.Anchored = true
		emitter.CanCollide = false
		emitter.CanQuery = false
		emitter.CanTouch = false
		emitter.Transparency = 1
		emitter.Size = Vector3.new(0.2, 0.2, 0.2)
		emitter.CFrame = CFrame.new(at)
		emitter.Parent = holder
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = 12
		sound.RollOffMaxDistance = 220
		sound.Parent = emitter
		Debris:AddItem(emitter, 6)
	else
		sound.Parent = SoundService
		Debris:AddItem(sound, 6)
	end
	if spec.start then
		sound.TimePosition = spec.start
	end
	sound:Play()
end

-- ------------------------------------------------------------
-- shelf wobble
-- ------------------------------------------------------------

local function shake(parts, out)
	if type(parts) ~= "table" then
		return
	end
	local direction = if typeof(out) == "Vector3" then out else Vector3.new(1, 0, 0)
	local stopAt = os.clock() + Config.SHAKE_SECONDS
	for _, part in ipairs(parts) do
		if typeof(part) == "Instance" and part:IsA("BasePart") then
			local entry = wobbling[part]
			if entry then
				entry.stopAt = stopAt -- already wobbling: keep its true resting place
			else
				wobbling[part] = { base = part.CFrame, stopAt = stopAt, out = direction }
			end
		end
	end
end

local function stepWobble()
	local t = os.clock()
	for part, entry in pairs(wobbling) do
		if not part.Parent or t >= entry.stopAt then
			if part.Parent then
				part.CFrame = entry.base
			end
			wobbling[part] = nil
		else
			local left = (entry.stopAt - t) / Config.SHAKE_SECONDS -- 1 -> 0
			local swing = math.sin(t * 55) * 0.35 * left
			-- tip about the base: lean toward the aisle and back
			local axis = Vector3.new(entry.out.Z, 0, -entry.out.X)
			part.CFrame = CFrame.new(entry.out * swing * 0.6) * entry.base * CFrame.fromAxisAngle(entry.base:VectorToObjectSpace(axis), swing * 0.08)
		end
	end
end

-- ------------------------------------------------------------
-- dizzy stars
-- ------------------------------------------------------------

local STAR_COUNT = 3

local function addStars(character, seconds)
	if typeof(character) ~= "Instance" then
		return
	end
	local parts = {}
	for i = 1, STAR_COUNT do
		local star = Instance.new("Part")
		star.Name = "DizzyStar"
		star.Shape = Enum.PartType.Ball
		star.Size = Vector3.new(0.45, 0.45, 0.45)
		star.Material = Enum.Material.Neon
		star.Color = Theme.GOLD
		star.Anchored = true
		star.CanCollide = false
		star.CanQuery = false
		star.CanTouch = false
		star.CastShadow = false
		star.Parent = holder
		parts[i] = star
	end
	table.insert(stars, { character = character, parts = parts, stopAt = os.clock() + (tonumber(seconds) or 1.5) })
end

local function stepStars()
	local t = os.clock()
	for i = #stars, 1, -1 do
		local entry = stars[i]
		local head = entry.character.Parent and entry.character:FindFirstChild("Head")
		if not head or t >= entry.stopAt then
			for _, part in ipairs(entry.parts) do
				part:Destroy()
			end
			table.remove(stars, i)
		else
			local centre = head.Position + Vector3.new(0, 1.3, 0)
			for k, part in ipairs(entry.parts) do
				local angle = t * 6 + (k - 1) * (math.pi * 2 / STAR_COUNT)
				part.Position = centre + Vector3.new(math.cos(angle) * 1.2, math.sin(t * 9 + k) * 0.15, math.sin(angle) * 1.2)
			end
		end
	end
end

-- ------------------------------------------------------------
-- camera jolt (the local player only)
-- ------------------------------------------------------------

local JOLT_SECONDS = 0.25

local function stepJolt()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local left = joltUntil - os.clock()
	if left > 0 then
		local k = left / JOLT_SECONDS * 0.45
		humanoid.CameraOffset = Vector3.new((math.random() * 2 - 1) * k, (math.random() * 2 - 1) * k, 0)
	elseif humanoid.CameraOffset ~= Vector3.zero then
		humanoid.CameraOffset = Vector3.zero
	end
end

-- ------------------------------------------------------------

local function onFx(payload)
	if type(payload) ~= "table" then
		return
	end
	if payload.sound then
		play(payload.sound, payload.at)
	end
	if payload.shake then
		shake(payload.shake, payload.out)
	end
	if payload.stars then
		addStars(payload.stars, payload.seconds)
	end
	if payload.jolt then
		joltUntil = os.clock() + JOLT_SECONDS
	end
end

function FxClient.start()
	holder = Instance.new("Folder")
	holder.Name = "LocalFx"
	holder.Parent = Workspace

	-- keep one silent copy of each sound loaded, so every play starts at once
	cache = Instance.new("Folder")
	cache.Name = "SweepSoundCache"
	cache.Parent = SoundService
	for name in pairs(Config.SOUNDS) do
		local sound = makeSound(name)
		if sound then
			sound.Volume = 0
			sound.Parent = cache
		end
	end

	Remotes.get("Fx").OnClientEvent:Connect(onFx)
	RunService.Heartbeat:Connect(function()
		stepWobble()
		stepStars()
		stepJolt()
	end)
end

return FxClient
