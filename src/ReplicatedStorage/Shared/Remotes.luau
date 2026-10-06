-- Every client/server channel, declared once. The server creates them in
-- Remotes.setup(); both sides fetch them with Remotes.get(name).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

Remotes.EVENTS = {
	PlayerState = "server -> one client: list, trolley, hands, scanned value, checkout progress, sprint clock",
	Announce = "server -> clients: a tannoy line { text, kind }",
	Results = "server -> all clients: the feeding (rows revealed on Chonk's mood meter, with revealAt in server time) or the podium { podium = true }",
	AdminCommand = "client -> server: a command name (checked against the allowlist on the server)",
	TrolleyToggle = "client -> server: let go of the trolley, or take it back if it's in reach (no arguments)",
	Sprint = "client -> server: sprint key held (true) or released (false); the server runs the meter",
	Throw = "client -> server: throw toward an aim direction (Vector3); the server validates and clamps it, picks the item, and flies it",
	ThrowFx = "server -> all clients: a throw left a hand { id, key, origin, velocity, startedAt } so every client draws the flight",
	ThrowEnd = "server -> all clients: { id } the flight is over (it hit someone or landed)",
	Dig = "client -> server: start (true) or stop (false) rummaging in your own trolley; the server stands you still",
	TakeOut = "client -> server: (slot, key) pull that item off the top of your pile while digging, into a free hand",
	PutBack = "client -> server: (handIndex, key) while digging, put what's in that hand back on top of your pile",
	ChonkSay = "server -> all clients: Big Chonk said something { text, mood }",
	Fx = "server -> clients: a sound { sound, at? }, a shelf wobble { shake = parts, out }, dizzy stars { stars = character, seconds }, or a camera jolt { jolt }",
}

local FOLDER_NAME = "Remotes"

function Remotes.setup()
	assert(RunService:IsServer(), "Remotes.setup runs on the server")
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
	end
	for name in pairs(Remotes.EVENTS) do
		if not folder:FindFirstChild(name) then
			local event = Instance.new("RemoteEvent")
			event.Name = name
			event.Parent = folder
		end
	end
	folder.Parent = ReplicatedStorage
end

function Remotes.get(name)
	assert(Remotes.EVENTS[name], "unknown remote " .. tostring(name))
	if RunService:IsServer() then
		return ReplicatedStorage[FOLDER_NAME][name]
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME):WaitForChild(name)
end

return Remotes
