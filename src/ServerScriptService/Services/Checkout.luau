-- The tills. A player checks out by standing on a till's pad: items scan one
-- at a time, and whatever has scanned is theirs. Each till serves one player
-- at a time, so queues form in the lanes at closing.
--
-- Stepping off the pad pauses the scan (what's scanned stays scanned).
-- Scanning everything (hands, and the trolley, which must be pushed to the
-- till) ends the player's round with the early-exit bonus. The tills stay
-- shut until TILLS_OPEN_AT.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Rules = require(Shared.Rules)

local Store = require(script.Parent.Store)
local Shoppers = require(script.Parent.Shoppers)
local Fx = require(script.Parent.Fx)

local Checkout = {}

local tills = {} -- [i] = { occupant = Player?, accum = number }
local emptyWarned = {} -- [Player] = true while they stand on a pad with nothing to scan
local shutWarned = {} -- [Player] = true while they stand on a pad before the tills open
local SHUT_TEXT = ("OPENS AT %s"):format(Rules.formatClock(Config.TILLS_OPEN_AT))

local function rootOf(player)
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function canCheckOut(player)
	local s = Shoppers.get(player)
	return s ~= nil and not s.done and not s.caught
end

function Checkout.reset()
	for i = 1, #Store.tills do
		tills[i] = { occupant = nil, accum = 0 }
		Store.setTillStatus(i, SHUT_TEXT, true)
	end
	emptyWarned = {}
	shutWarned = {}
end

-- Before the tills open: signs say when, and anyone on a pad is told.
local function stepShut()
	local onAnyPad = {}
	for i in ipairs(tills) do
		Store.setTillStatus(i, SHUT_TEXT, true)
	end
	for _, player in ipairs(Shoppers.participants()) do
		local root = rootOf(player)
		if root and Store.onAnyPad(root.Position) then
			onAnyPad[player] = true
			if not shutWarned[player] then
				shutWarned[player] = true
				Shoppers.note(player, ("The tills open at %s! Keep shopping."):format(Rules.formatClock(Config.TILLS_OPEN_AT)), "warn")
			end
		end
	end
	for player in pairs(shutWarned) do
		if not onAnyPad[player] then
			shutWarned[player] = nil
		end
	end
end

-- Called by Round about ten times a second while the store is open.
function Checkout.step(dt, elapsed)
	if not Rules.tillsOpen(elapsed) then
		stepShut()
		return
	end
	local busy = {}
	for i, till in ipairs(tills) do
		if till.occupant then
			local root = rootOf(till.occupant)
			if not (root and canCheckOut(till.occupant) and Store.onPad(i, root.Position)) then
				Shoppers.setAtTill(till.occupant, nil)
				till.occupant = nil
				till.accum = 0
			else
				busy[till.occupant] = true
			end
		end
	end

	local onAnyPad = {}
	for i, till in ipairs(tills) do
		if not till.occupant then
			-- the nearest eligible player on the pad who isn't at another till
			local best, bestDist = nil, math.huge
			for _, player in ipairs(Shoppers.participants()) do
				local root = rootOf(player)
				if root and not busy[player] and canCheckOut(player) and Store.onPad(i, root.Position) then
					local d = (root.Position - Store.tills[i].padCenter).Magnitude
					if d < bestDist then
						best, bestDist = player, d
					end
				end
			end
			if best then
				till.occupant = best
				till.accum = 0
				busy[best] = true
				Shoppers.setAtTill(best, i)
			end
		end

		local player = till.occupant
		if player then
			onAnyPad[player] = true
			local s = Shoppers.get(player)
			if Shoppers.scannableCount(player) == 0 then
				local parked = Shoppers.parkedCount(player)
				if parked > 0 then
					-- the till only scans a trolley you're pushing
					if not emptyWarned[player] then
						emptyWarned[player] = true
						Shoppers.note(player, ("Your trolley is parked with %d items in it! Bring it to the till."):format(parked), "warn")
					end
				elseif s.scanned > 0 then
					Shoppers.finish(player, elapsed)
					till.occupant = nil
				elseif not emptyWarned[player] then
					emptyWarned[player] = true
					Shoppers.note(player, "Nothing to scan! Grab items first.", "warn")
				end
			else
				till.accum += dt
				while till.accum >= Config.SCAN_SECONDS and Shoppers.scannableCount(player) > 0 do
					till.accum -= Config.SCAN_SECONDS
					Shoppers.scanOne(player)
					Fx.play("scan", Store.tills[i].padCenter)
				end
				if Shoppers.scannableCount(player) == 0 and Shoppers.parkedCount(player) == 0 then
					Shoppers.finish(player, elapsed)
					till.occupant = nil
				end
			end
		end

		if till.occupant then
			Store.setTillStatus(i, ("SCANNING %d LEFT"):format(Shoppers.scannableCount(till.occupant)), true)
		else
			Store.setTillStatus(i, "OPEN", false)
		end
	end

	for player in pairs(emptyWarned) do
		if not onAnyPad[player] then
			emptyWarned[player] = nil
		end
	end
end

-- The store closed: every till stops.
function Checkout.stopAll()
	for i, till in ipairs(tills) do
		if till.occupant then
			Shoppers.setAtTill(till.occupant, nil)
		end
		till.occupant = nil
		till.accum = 0
		Store.setTillStatus(i, "CLOSED", true)
	end
end

return Checkout
