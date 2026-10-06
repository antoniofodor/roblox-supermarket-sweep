-- Owner-only test console. The allowlist is checked on the SERVER, at the
-- top of the one handler, before any argument is read: the RemoteEvent
-- exists for every player whether or not their panel was built.
-- In Studio every player counts as an admin, so local multi-client tests
-- (whose test players have made-up ids) can use the buttons too.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local Store = require(script.Parent.Store)
local Shoppers = require(script.Parent.Shoppers)
local Round = require(script.Parent.Round)

local Admin = {}

local function isAdmin(player)
	if Config.ADMINS[player.UserId] then
		return true
	end
	if RunService:IsStudio() then
		return true
	end
	return game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId
end

-- Every command the panel can send. The client sends a name, nothing else.
local COMMANDS = {
	start = function()
		Round.forceStart()
		return "Starting the match now."
	end,
	craving = function()
		return if Round.skipTo(Config.CRAVING_AT) then "Skipped to Chonk's craving." else "No round running (or already past it)."
	end,
	endmatch = function()
		return if Round.endMatch() then "The match ends after this round (then the podium)." else "No match running."
	end,
	tills = function()
		return if Round.skipTo(Config.TILLS_OPEN_AT) then "Skipped to the tills opening." else "No round running (or already past it)."
	end,
	sale = function()
		return if Round.skipTo(Config.FLASH_SALE_AT) then "Skipped to the flash sale." else "No round running (or already past it)."
	end,
	closing = function()
		return if Round.skipTo(Config.CLOSING_WARN_AT) then "Skipped to closing time." else "No round running (or already past it)."
	end,
	shutters = function()
		return if Round.skipTo(Config.SHUTTER_STARTS_AT) then "Skipped to the shutters." else "No round running (or already past it)."
	end,
	finish = function()
		return if Round.skipTo(Config.ROUND_SECONDS) then "Closing the store now." else "No round running."
	end,
	give = function(player)
		return if Shoppers.giveRandom(player, 10) then "Added up to 10 random items to your trolley." else "You're not shopping right now."
	end,
	restock = function()
		Store.restock()
		return "Shelves restocked."
	end,
}

function Admin.start()
	local remote = Remotes.get("AdminCommand")
	local announce = Remotes.get("Announce")

	remote.OnServerEvent:Connect(function(player, command)
		if not isAdmin(player) then
			warn(("[Admin] refused %s (%d)"):format(player.Name, player.UserId))
			return
		end
		local fn = if type(command) == "string" then COMMANDS[command] else nil
		if not fn then
			return
		end
		print(("[Admin] %s ran %s"):format(player.Name, command))
		local ok, result = pcall(fn, player)
		announce:FireClient(player, {
			text = if ok then tostring(result) else ("Command failed: " .. tostring(result)),
			kind = "note",
		})
	end)

	local function mark(player)
		player:SetAttribute(Config.ATTR.isAdmin, isAdmin(player))
	end
	Players.PlayerAdded:Connect(mark)
	for _, player in ipairs(Players:GetPlayers()) do
		mark(player)
	end
end

return Admin
