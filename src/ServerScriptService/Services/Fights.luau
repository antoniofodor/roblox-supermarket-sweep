-- Ramming, stealing and throwing. Three ways to mess with another shopper,
-- each doing a different job:
--
--   RAM    up close, needs speed, TAKES an item: run your trolley's nose into
--          another trolley (pushed or parked) and its top item flies out onto
--          the floor. Ram a shopper on foot and the item in their hand drops.
--   STEAL  hold E on someone's parked trolley to take its top item for
--          yourself. Pushing your trolley is what keeps it safe.
--   PLANT  the same prompt, while you hold yuck in your hand: the yuck goes
--          INTO their parked trolley, so their till scans it against them.
--   THROW  F throws an item along a real arc toward where you aim: the item
--          in your hand, or else your least-yum one. Whoever it passes close
--          to is knocked off balance (Shoppers.stumble). If it passes close
--          to someone else's trolley basket first, it drops IN (sabotage).
--          Otherwise it lands on the floor for anyone.
--   SHAKE  sprint your trolley into a shelf face, a fridge or the fruit table: 1-3 of
--          its items fall into the aisle (Store.shake), or into any trolley
--          basket underneath (catchFalling).
--   SCRAPE push your trolley against a shelf: now and then one of its items
--          tumbles into your OWN basket. Yuck sits beside the good food.
--
-- Anything that lands in someone's trolley tells them only that SOMETHING
-- landed: they have to dig (R) to find out what.
--
-- Nobody standing on a till pad can be rammed or hit. The server decides
-- every outcome from its own positions; a throw request carries only an aim
-- direction, which the server clamps.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local Store = require(script.Parent.Store)
local Shoppers = require(script.Parent.Shoppers)
local Trolley = require(script.Parent.Trolley)
local Fx = require(script.Parent.Fx)
local Chonk = require(script.Parent.Chonk)

local Fights = {}

local rng = Random.new()

local function now()
	return Workspace:GetServerTimeNow()
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function itemName(key)
	local item = Config.ITEM_BY_KEY[key]
	return item and item.name or key
end

local function onPad(player)
	local root = Shoppers.rootOf(player)
	return root ~= nil and Store.onAnyPad(root.Position)
end

-- A falling item lands in the nearest trolley basket within
-- FALL_CATCH_RADIUS of where it would have hit the floor (not those in
-- `except`, and not anyone's on a till pad). True if one caught it.
local function catchFalling(key, landing, _from, except)
	local best, bestDistance = nil, Config.FALL_CATCH_RADIUS
	for _, player in ipairs(Shoppers.participants()) do
		local s = Shoppers.get(player)
		if Shoppers.isShopping(player) and s.trolleyModel and not (except and except[player]) and not onPad(player) then
			local centre = Trolley.centre(s.trolleyModel)
			local distance = flat(centre - landing).Magnitude
			if distance <= bestDistance then
				best, bestDistance = player, distance
			end
		end
	end
	if not best or not Shoppers.addToTrolley(best, key) then
		return false
	end
	Fx.play("grab", landing)
	Shoppers.note(best, "SOMETHING FELL INTO YOUR TROLLEY! Dig (R) to see what.", "warn")
	return true
end

-- Knock an item out of something at `from`: it hops out and lands a few
-- studs away, or in a bystander's trolley (never the two in the ram).
local function spill(key, from, except)
	local angle = rng:NextNumber(0, math.pi * 2)
	local distance = rng:NextNumber(3, 5)
	local landing = from + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
	if catchFalling(key, landing, from, except) then
		return
	end
	Store.dropItem(key, landing, from + Vector3.new(0, 2, 0))
end

-- ------------------------------------------------------------
-- RAM (checked by Round about ten times a second)
-- ------------------------------------------------------------

local function tryRam(attacker, victim)
	local a, v = Shoppers.get(attacker), Shoppers.get(victim)
	if not a.pushing or not a.trolleyModel or onPad(victim) then
		return
	end
	local t = now()
	if t < v.ramSafeUntil then
		return
	end
	local root = Shoppers.rootOf(attacker)
	local nose = Trolley.nose(a.trolleyModel)
	local centre = Trolley.centre(a.trolleyModel)
	if not root or not nose or not centre then
		return
	end
	local velocity = flat(root.AssemblyLinearVelocity)
	if velocity.Magnitude < Config.RAM_MIN_SPEED then
		return
	end

	-- what of the victim's can be hit: their trolley (pushed or parked) and
	-- them on foot with something in hand
	local candidates = {}
	if v.trolleyModel and #v.trolley > 0 then
		table.insert(candidates, { point = Trolley.centre(v.trolleyModel), reach = Config.RAM_REACH, trolley = true })
	end
	local victimRoot = Shoppers.rootOf(victim)
	if victimRoot and #v.hands > 0 then
		table.insert(candidates, { point = victimRoot.Position, reach = Config.RAM_REACH_PERSON, trolley = false })
	end
	local hit = nil
	for _, c in ipairs(candidates) do
		local toTarget = flat(c.point - centre)
		-- in reach of the nose, and moving into it rather than sliding past
		if flat(nose - c.point).Magnitude <= c.reach and toTarget.Magnitude > 0.01 and velocity.Unit:Dot(toTarget.Unit) >= 0.5 then
			hit = c
			break
		end
	end
	if not hit then
		return
	end
	local target = hit.point

	local key = if hit.trolley then Shoppers.takeTopOfTrolley(victim) else Shoppers.takeFromHands(victim)
	if not key then
		return
	end
	v.ramSafeUntil = t + Config.RAM_COOLDOWN
	a.rams += 1
	v.rammed += 1
	Shoppers.stopDigging(victim) -- a ram knocks you out of your rummage
	spill(key, target, { [attacker] = true, [victim] = true })
	Fx.play("ram", target)
	Fx.jolt(attacker)
	Fx.jolt(victim)
	Shoppers.note(attacker, ("RAMMED %s! %s is on the floor."):format(victim.DisplayName:upper(), itemName(key)), "go")
	Shoppers.note(victim, ("%s RAMMED YOU! Your %s fell out."):format(attacker.DisplayName:upper(), itemName(key)), "warn")
	Chonk.react("ram")
end

-- Pushing against a shelf: the trolley's nose or a front corner is in a
-- shelf section. Now and then, one of its items tumbles into your basket.
local function tryScrape(player, s, velocity)
	local t = now()
	if velocity.Magnitude < Config.SCRAPE_MIN_SPEED or t - s.lastScrape < Config.SCRAPE_COOLDOWN then
		return
	end
	local base = s.trolleyModel.PrimaryPart
	if not base then
		return
	end
	local section = nil
	for _, dx in ipairs({ 0, -1.4, 1.4 }) do
		section = Store.sectionAt((base.CFrame * CFrame.new(dx, 0, -2.4)).Position)
		if section then
			break
		end
	end
	if not section then
		return
	end
	s.lastScrape = t
	if rng:NextNumber() >= Config.SCRAPE_CHANCE then
		return
	end
	local key = Store.knockOne(section)
	if not key then
		return
	end
	if Shoppers.addToTrolley(player, key) then
		Shoppers.note(player, "SOMETHING FELL INTO YOUR TROLLEY! Dig (R) to see what.", "warn")
	else
		Store.dropItem(key, Trolley.nose(s.trolleyModel), base.Position + Vector3.new(0, 3, 0))
	end
end

-- A pushed trolley sprinting into a shelf face shakes it; pushed against a
-- shelf more gently, it scrapes.
local function tryShake(player)
	local s = Shoppers.get(player)
	if not s.pushing or not s.trolleyModel then
		return
	end
	local root = Shoppers.rootOf(player)
	local nose = Trolley.nose(s.trolleyModel)
	if not root or not nose then
		return
	end
	local velocity = flat(root.AssemblyLinearVelocity)
	if velocity.Magnitude < Config.SHAKE_MIN_SPEED then
		tryScrape(player, s, velocity)
		return
	end
	local section = Store.shelfHit(nose, velocity)
	if not section then
		return
	end
	local fell = Store.shake(section)
	if fell then
		s.shakes += 1
		Fx.jolt(player)
	end
end

function Fights.step()
	if not Shoppers.isOpen() then
		return
	end
	local players = Shoppers.participants()
	for _, attacker in ipairs(players) do
		if Shoppers.isShopping(attacker) then
			tryShake(attacker)
			for _, victim in ipairs(players) do
				if victim ~= attacker and Shoppers.isShopping(victim) then
					tryRam(attacker, victim)
				end
			end
		end
	end
end

-- ------------------------------------------------------------
-- STEAL (the "Steal" prompt on a parked trolley)
-- ------------------------------------------------------------

local function ownerOf(model)
	local userId = model:GetAttribute(Config.ATTR.trolleyOwner)
	return userId and Players:GetPlayerByUserId(userId)
end

-- Holding yuck: it goes into their parked trolley instead of taking from it.
local function plant(thief, victim)
	local s, v = Shoppers.get(thief), Shoppers.get(victim)
	local key = Shoppers.takeYuckFromHands(thief)
	if not key then
		return
	end
	if not Shoppers.addToTrolley(victim, key) then
		Shoppers.addCarried(thief, key)
		return Shoppers.note(thief, ("%s's trolley is full!"):format(victim.DisplayName), "warn")
	end
	s.plants += 1
	v.sabotaged += 1
	Fx.playFor(thief, "grab")
	Fx.playFor(victim, "stolen")
	Shoppers.note(thief, ("PLANTED %s in %s's trolley!"):format(itemName(key):upper(), victim.DisplayName), "go")
	Shoppers.note(victim, ("%s PUT SOMETHING IN YOUR TROLLEY! Dig (R) to see what."):format(thief.DisplayName:upper()), "urgent")
	Chonk.react("sabotage")
end

local function trySteal(thief, model)
	local s = Shoppers.get(thief)
	local victim = ownerOf(model)
	if not victim or victim == thief or not Shoppers.isShopping(thief) or not Shoppers.isShopping(victim) then
		return
	end
	local v = Shoppers.get(victim)
	if v.pushing or v.trolleyModel ~= model then
		return -- only a parked trolley
	end
	if Shoppers.isStumbling(thief) then
		return Shoppers.note(thief, "You're off balance! Wait a moment.", "warn")
	end
	local root = Shoppers.rootOf(thief)
	if not root or Trolley.distanceTo(model, root.Position) > Config.STEAL_REACH + 2 then
		return
	end
	if Shoppers.holdsYuck(thief) then
		return plant(thief, victim)
	end
	if #v.trolley == 0 then
		return
	end
	local key = Shoppers.takeTopOfTrolley(victim)
	if not key then
		return
	end
	if not Shoppers.addCarried(thief, key) then
		-- nowhere to put it: it goes back
		table.insert(v.trolley, key)
		Shoppers.changed(victim, true)
		return Shoppers.note(thief, "No room! Your hands or trolley are full.", "warn")
	end
	s.steals += 1
	v.stolenFrom += 1
	Fx.playFor(thief, "grab")
	Fx.playFor(victim, "stolen")
	Shoppers.note(thief, ("STOLE %s from %s's trolley!"):format(itemName(key):upper(), victim.DisplayName), "go")
	Shoppers.note(victim, ("%s IS STEALING FROM YOUR TROLLEY! They took your %s."):format(thief.DisplayName:upper(), itemName(key)), "urgent")
end

-- ------------------------------------------------------------
-- THROW
-- A real arc. The client sends only an aim direction; the server clamps it,
-- picks the item, steers it a little toward a shopper close to the aim, and
-- flies it step by step. Every client draws the same arc from ThrowFx, so
-- the flight is smooth everywhere without the server moving a part.
-- ------------------------------------------------------------

local GRAVITY = Vector3.new(0, -Config.THROW_GRAVITY, 0)
local flights = {} -- [id] = flight
local nextId = 0
local throwFx, throwEnd

local function structureParams()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Store.structure() }
	return params
end

-- Turn whatever the client sent into a legal aim: a unit vector, pitch
-- clamped. Anything else falls back to where the thrower is facing.
local function sanitiseAim(raw, root)
	local facing = flat(root.CFrame.LookVector)
	facing = if facing.Magnitude > 0.01 then facing.Unit else Vector3.new(0, 0, -1)
	if typeof(raw) ~= "Vector3" or raw ~= raw or raw.Magnitude < 0.01 or raw.Magnitude > 1e4 then
		return facing
	end
	local dir = raw.Unit
	local horizontal = flat(dir)
	if horizontal.Magnitude < 0.05 then
		horizontal = facing
	else
		horizontal = horizontal.Unit
	end
	local pitch = math.deg(math.asin(math.clamp(dir.Y, -1, 1)))
	pitch = math.clamp(pitch, Config.THROW_PITCH_MIN, Config.THROW_PITCH_MAX)
	local r = math.rad(pitch)
	return horizontal * math.cos(r) + Vector3.new(0, math.sin(r), 0)
end

-- A shopper close to the aim line gets the throw steered at them, aimed
-- where they'll be when it arrives.
local function assistVelocity(thrower, origin, aim)
	local cosCone = math.cos(math.rad(Config.THROW_ASSIST_CONE))
	local params = structureParams()
	local t = now()
	local best, bestDot = nil, cosCone
	for _, other in ipairs(Shoppers.participants()) do
		local s = Shoppers.get(other)
		local root = Shoppers.rootOf(other)
		if other ~= thrower and root and Shoppers.isShopping(other) and t >= s.immuneUntil and not Store.onAnyPad(root.Position) then
			local offset = root.Position - origin
			local distance = offset.Magnitude
			if distance > 1 and distance <= Config.THROW_RANGE then
				-- compare on the flat: the aim's pitch shouldn't stop it locking on
				local dot = flat(aim).Unit:Dot(flat(offset).Unit)
				if dot >= bestDot and not Workspace:Raycast(origin, offset, params) then
					best, bestDot = other, dot
				end
			end
		end
	end
	if not best then
		return nil
	end
	local root = Shoppers.rootOf(best)
	local distance = (root.Position - origin).Magnitude
	local flight = distance / Config.THROW_SPEED
	local lead = flat(root.AssemblyLinearVelocity) * flight
	local aimPoint = root.Position + lead
	flight = (aimPoint - origin).Magnitude / Config.THROW_SPEED
	-- solve the launch velocity that passes through aimPoint after `flight` under gravity
	return (aimPoint - origin) / flight - GRAVITY * (flight / 2)
end

-- Distance from p to the segment a..b, and how far along it (0..1) the
-- closest point is.
local function pointToSegment(p, a, b)
	local ab = b - a
	local lengthSq = ab:Dot(ab)
	if lengthSq < 1e-6 then
		return (p - a).Magnitude, 0
	end
	local t = math.clamp((p - a):Dot(ab) / lengthSq, 0, 1)
	return (p - (a + ab * t)).Magnitude, t
end

-- Closest distance from a flight segment to a shopper's body (feet to head).
local function distanceToBody(root, a, b)
	local d, along = math.huge, 0
	for _, dy in ipairs({ -1.5, 0, 1.5 }) do
		local di, ti = pointToSegment(root.Position + Vector3.new(0, dy, 0), a, b)
		if di < d then
			d, along = di, ti
		end
	end
	return d, along
end

-- The middle of a trolley's basket.
local function basketCentre(model)
	local centre = Trolley.centre(model)
	return centre and centre + Vector3.new(0, 0.6, 0)
end

local function endFlight(id)
	flights[id] = nil
	throwEnd:FireAllClients({ id = id })
end

local function land(flight, position)
	Store.dropItem(flight.key, position)
end

-- The flight passed close to `other`'s trolley: the item drops in.
local function catchInTrolley(flight, other, at)
	local key, thrower = flight.key, flight.thrower
	if not Shoppers.addToTrolley(other, key) then
		land(flight, at) -- full: it bounces off onto the floor
		return
	end
	local s, v = Shoppers.get(thrower), Shoppers.get(other)
	if s then
		s.sabotages += 1
	end
	v.sabotaged += 1
	Fx.play("grab", at)
	local yuck = Config.ITEM_BY_KEY[key].kind == "yuck"
	if thrower.Parent then
		Shoppers.note(thrower, ("IN! %s landed in %s's trolley!"):format(itemName(key):upper(), other.DisplayName), "go")
	end
	Shoppers.note(other, ("%s THREW SOMETHING INTO YOUR TROLLEY! Dig (R) to see what."):format(thrower.DisplayName:upper()), "urgent")
	if yuck then
		Chonk.react("sabotage")
	end
end

local function stepFlight(id, flight, dt)
	local from = flight.position
	local to = from + flight.velocity * dt
	flight.velocity += GRAVITY * dt
	flight.age += dt

	-- a shopper, or somebody else's trolley, in the way? Whichever the
	-- flight reaches first this step.
	local first, firstAlong, firstIsTrolley = nil, math.huge, false
	for _, other in ipairs(Shoppers.participants()) do
		if other ~= flight.thrower and Shoppers.isShopping(other) then
			local root = Shoppers.rootOf(other)
			if root then
				local d, along = distanceToBody(root, from, to)
				if d <= Config.THROW_HIT_RADIUS and along < firstAlong then
					first, firstAlong, firstIsTrolley = other, along, false
				end
			end
			local s = Shoppers.get(other)
			local basket = s.trolleyModel and basketCentre(s.trolleyModel)
			if basket and not onPad(other) then
				local d, along = pointToSegment(basket, from, to)
				if d <= Config.TROLLEY_CATCH_RADIUS and along < firstAlong then
					first, firstAlong, firstIsTrolley = other, along, true
				end
			end
		end
	end
	if first and firstIsTrolley then
		endFlight(id)
		catchInTrolley(flight, first, from:Lerp(to, firstAlong))
		return
	end
	if first then
		local other = first
		local root = Shoppers.rootOf(other)
		local away = flat(flight.velocity)
		away = if away.Magnitude > 0.01 then away.Unit else Vector3.new(0, 0, 1)
		land(flight, root.Position + away * 2)
		endFlight(id)
		local key = flight.key
		local thrower = flight.thrower
		local s = Shoppers.get(thrower)
		if Shoppers.stumble(other) then
			if s then
				s.hits += 1
			end
			if thrower.Parent then
				Shoppers.note(thrower, ("HIT %s with %s!"):format(other.DisplayName:upper(), itemName(key)), "go")
			end
			Shoppers.note(other, ("WHOA! %s hit you with %s!"):format(thrower.DisplayName, itemName(key)), "warn")
		end
		return
	end

	-- a wall, a shelf, the floor?
	local hit = Workspace:Raycast(from, to - from, flight.params)
	if hit then
		land(flight, hit.Position - (to - from).Unit * 1)
		endFlight(id)
		return
	end
	flight.position = to
	if flight.age >= Config.THROW_MAX_SECONDS or to.Y < Store.FLOOR_Y - 5 then
		land(flight, to)
		endFlight(id)
	end
end

local function tryThrow(thrower, rawAim)
	local s = Shoppers.get(thrower)
	if not Shoppers.isShopping(thrower) then
		return
	end
	local t = now()
	if t < s.throwReadyAt or Shoppers.isStumbling(thrower) then
		return
	end
	local root = Shoppers.rootOf(thrower)
	if not root then
		return
	end
	local key = Shoppers.takeForThrow(thrower)
	if not key then
		return Shoppers.note(thrower, "Nothing to throw! Grab some items first.", "note")
	end
	s.throwReadyAt = t + Config.THROW_COOLDOWN
	s.throws += 1
	Shoppers.push(thrower)

	local aim = sanitiseAim(rawAim, root)
	local origin = root.Position + Vector3.new(0, 1.5, 0) + flat(aim).Unit * 1.5
	local velocity = assistVelocity(thrower, origin, aim) or aim * Config.THROW_SPEED

	nextId += 1
	local id = nextId
	flights[id] = {
		thrower = thrower,
		key = key,
		position = origin,
		velocity = velocity,
		age = 0,
		params = structureParams(),
	}
	throwFx:FireAllClients({ id = id, key = key, origin = origin, velocity = velocity, startedAt = t })
	Fx.play("throw", origin)
end

-- Drop anything still in the air (round over).
function Fights.clearFlights()
	for id, flight in pairs(flights) do
		land(flight, flight.position)
		endFlight(id)
	end
end

-- ------------------------------------------------------------
-- start
-- ------------------------------------------------------------

function Fights.start()
	Store.setCatchHandler(catchFalling)
	throwFx = Remotes.get("ThrowFx")
	throwEnd = Remotes.get("ThrowEnd")
	Remotes.get("Throw").OnServerEvent:Connect(function(player, aim)
		tryThrow(player, aim)
	end)
	RunService.Heartbeat:Connect(function(dt)
		for id, flight in pairs(flights) do
			stepFlight(id, flight, dt)
		end
	end)
	Trolley.folder().DescendantAdded:Connect(function(inst)
		if inst:IsA("ProximityPrompt") and inst.Name == "Steal" then
			local model = inst:FindFirstAncestorOfClass("Model")
			inst.Triggered:Connect(function(player)
				if model then
					trySteal(player, model)
				end
			end)
		end
	end)
end

return Fights
