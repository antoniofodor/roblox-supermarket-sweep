-- Client entry point: the HUD for everyone, the test console for admins.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Hud = require(script.Parent:WaitForChild("Hud"))
local AdminPanel = require(script.Parent:WaitForChild("AdminPanel"))
local Controls = require(script.Parent:WaitForChild("Controls"))
local Projectiles = require(script.Parent:WaitForChild("Projectiles"))
local FxClient = require(script.Parent:WaitForChild("FxClient"))
local Rummage = require(script.Parent:WaitForChild("Rummage"))
local Spectate = require(script.Parent:WaitForChild("Spectate"))

local player = Players.LocalPlayer

Hud.start()
Controls.start()
Projectiles.start()
FxClient.start()
Rummage.start()
Spectate.start()

local function checkAdmin()
	if player:GetAttribute(Config.ATTR.isAdmin) then
		AdminPanel.start()
	end
end
player:GetAttributeChangedSignal(Config.ATTR.isAdmin):Connect(checkAdmin)
checkAdmin()
