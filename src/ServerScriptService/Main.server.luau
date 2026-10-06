-- Entry point. Builds the store, starts every service and the round loop,
-- and times each boot step in the log.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local Services = script.Parent:WaitForChild("Services")
local Store = require(Services.Store)
local Chonk = require(Services.Chonk)
local Shoppers = require(Services.Shoppers)
local Fights = require(Services.Fights)
local Round = require(Services.Round)
local Admin = require(Services.Admin)

local bootStarted = os.clock()

local function step(name, fn)
	local started = os.clock()
	local ok, err = pcall(fn)
	print(("[Main] boot: %s took %.2fs"):format(name, os.clock() - started))
	if not ok then
		warn(("[Main] boot: %s FAILED: %s"):format(name, tostring(err)))
	end
	return ok
end

-- Place settings that live in the place file rather than in this repo drift
-- without anyone noticing, so say so when they disagree with the project.
local okStreaming, streaming = pcall(function()
	return Workspace.StreamingEnabled
end)
if okStreaming and streaming then
	warn("[Main] Workspace.StreamingEnabled is on. This game expects it off (see default.project.json).")
end

-- Shift is the sprint key, and it is also Roblox's shift-lock key. The
-- project turns the option off for fresh builds; this covers a place file
-- that still has it on, since Rojo applies project properties only on a
-- fresh serve.
local Players = game:GetService("Players")
-- The camera is locked at one distance: no zooming out, no first person.
-- Max first, so the min is never set above the old max. Follow mode swings
-- the camera back behind you as you move (like a kart game's chase camera),
-- while a drag still looks around.
local function setupCamera(player)
	player.DevEnableMouseLock = false
	player.DevComputerCameraMode = Enum.DevComputerCameraMovementMode.Follow
	player.DevTouchCameraMode = Enum.DevTouchCameraMovementMode.Follow
	player.CameraMaxZoomDistance = Config.CAMERA_DISTANCE
	player.CameraMinZoomDistance = Config.CAMERA_DISTANCE
end
Players.PlayerAdded:Connect(setupCamera)
for _, player in ipairs(Players:GetPlayers()) do
	setupCamera(player)
end

step("remotes", Remotes.setup)
step("store", Store.build)
step("chonk", Chonk.build)
step("shoppers", Shoppers.start)
step("fights", Fights.start)
step("admin", Admin.start)
step("round loop", Round.start)

print(("[Main] Ready (%s) in %.2fs"):format(Config.VERSION, os.clock() - bootStarted))
