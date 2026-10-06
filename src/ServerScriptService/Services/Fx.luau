-- Sounds and effects, decided on the server and drawn on every client
-- (StarterPlayerScripts/FxClient). A leaf: it requires only Shared, so any
-- service can call it without a cycle.
--
--   Fx.play(name, at)       a sound at a world position, heard by everyone
--   Fx.playAll(name)        a sound heard flat by everyone (alarms, the sale)
--   Fx.playFor(player, name) a sound heard flat by one player (grab, checkout)
--   Fx.shake(parts, out, at, silent) a shelf wobbling, plus its rattle (unless silent)
--   Fx.stars(player, secs)  dizzy stars round a player's head
--   Fx.jolt(player)         a short camera shake for one player

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local Fx = {}

local remote

local function ready()
	remote = remote or Remotes.get("Fx")
	return remote
end

function Fx.play(name, at)
	if Config.SOUNDS[name] and typeof(at) == "Vector3" then
		ready():FireAllClients({ sound = name, at = at })
	end
end

function Fx.playAll(name)
	if Config.SOUNDS[name] then
		ready():FireAllClients({ sound = name })
	end
end

function Fx.playFor(player, name)
	if Config.SOUNDS[name] and player and player.Parent then
		ready():FireClient(player, { sound = name })
	end
end

function Fx.shake(parts, out, at, silent)
	ready():FireAllClients({ shake = parts, out = out, sound = if silent then nil else "shelf", at = at })
end

function Fx.stars(player, seconds)
	local character = player and player.Character
	if character then
		ready():FireAllClients({ stars = character, seconds = seconds })
	end
end

function Fx.jolt(player)
	if player and player.Parent then
		ready():FireClient(player, { jolt = true })
	end
end

return Fx
