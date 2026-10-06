-- Everything about one player's round: their list, their trolley, what's in
-- their hands, what's been scanned, their sprint meter, whether they're off
-- balance, and whether they made it out. The server owns all of it; the
-- client only draws the last PlayerState push.
--
-- Carrying: everyone starts the round pushing a trolley (TROLLEY_CAPACITY).
-- Letting go parks it; you then move at HAND_SPEED and grabs go into your
-- hands (HAND_SLOTS, one per hand). Pushing takes one hand, so while you
-- push you can hold PUSH_HAND_SLOTS (your throw). Taking the trolley back tips your hands
-- into it. The till scans your hands, and your trolley only while you push it.
--
-- Sprint: holding the key drains a meter (Rules.staminaAt); letting go
-- refills it after a short delay. The server keeps a snapshot
-- {stamina, staminaAt, sprinting, regenAt} and the client predicts from it.
--
-- The trolley is a PILE (Config.PILE_LAYER): the client is never sent a list
-- of what's in it. You see it on the model, or dig: R stops you dead and
-- shows the basket from above, and you pull out what's on top
-- (Rules.reachable) into a free hand; with both hands full you can't pull
-- out any more until you throw something or put one back (on top). A throw
-- with empty hands throws the top of the pile, whatever it is.
--
-- Values: every item is valued through Rules.itemValue with the round's
-- MENU (Chonk's craving and the food he's not in the mood for), which Round
-- sets with Shoppers.setMenu.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Rules = require(Shared.Rules)
local Remotes = require(Shared.Remotes)
local Theme = require(Shared.Theme)

local Store = require(script.Parent.Store)
local Trolley = require(script.Parent.Trolley)
local Fx = require(script.Parent.Fx)
local Chonk = require(script.Parent.Chonk)

local Shoppers = {}

local state = {} -- [Player] = shopper record (only for players in the current round)
local active = false -- a round is running and the store is open
local menu = {} -- { craving = key?, notToday = key? } for this round
local playerStateRemote
local announceRemote

local function now()
	return Workspace:GetServerTimeNow()
end

local function rootOf(player)
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end
Shoppers.rootOf = rootOf

local function humanoidOf(player)
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

function Shoppers.note(player, text, kind)
	announceRemote:FireClient(player, { text = text, kind = kind or "note" })
end

local function shopping(s)
	return s ~= nil and active and not s.done and not s.caught
end

-- How many items your hands hold right now: one hand is on the trolley
-- while you push it.
local function handSlots(s)
	return if s.pushing then Config.PUSH_HAND_SLOTS else Config.HAND_SLOTS
end

local function stumbling(s)
	return s.stumbleUntil > now()
end

-- ------------------------------------------------------------
-- what the player can see of their own state
-- ------------------------------------------------------------

local function haveSet(s)
	local have = {}
	for _, key in ipairs(s.trolley) do
		have[key] = true
	end
	for _, key in ipairs(s.hands) do
		have[key] = true
	end
	for key in pairs(s.bankedKeys) do
		have[key] = true
	end
	return have
end

-- Items the till can reach right now: hands, plus the trolley if pushed.
function Shoppers.scannableCount(player)
	local s = state[player]
	if not s then
		return 0
	end
	return #s.hands + (if s.pushing then #s.trolley else 0)
end

-- Items sitting in a parked trolley, out of the till's reach.
function Shoppers.parkedCount(player)
	local s = state[player]
	if not s or s.pushing then
		return 0
	end
	return #s.trolley
end

local function push(player)
	local s = state[player]
	-- who's still in the store, for everyone else's spectator camera
	player:SetAttribute(Config.ATTR.shopping, shopping(s))
	if not s then
		playerStateRemote:FireClient(player, { inRound = false })
		return
	end
	playerStateRemote:FireClient(player, {
		inRound = true,
		list = s.list,
		have = haveSet(s),
		pushing = s.pushing,
		handItems = s.hands,
		trolleyCount = #s.trolley,
		trolleyCapacity = Config.TROLLEY_CAPACITY,
		handsCount = #s.hands,
		handSlots = handSlots(s),
		digging = s.digging,
		scannable = Shoppers.scannableCount(player),
		banked = s.banked,
		scanned = s.scanned,
		atTill = s.atTill,
		done = s.done,
		caught = s.caught,
		score = s.score,
		lost = s.lost,
		bonusPct = s.bonusPct,
		-- sprint meter snapshot, in server time
		stamina = s.stamina,
		staminaAt = s.staminaAt,
		sprinting = s.sprinting,
		regenAt = s.regenAt,
		throwReadyAt = s.throwReadyAt,
		stumbleUntil = s.stumbleUntil,
	})
end
Shoppers.push = push

-- ------------------------------------------------------------
-- what other players can see: items in hand, and an off-balance label
-- ------------------------------------------------------------

local HANDS_NAME = "HandItems"

local function buildHands(player)
	local character = player.Character
	if not character then
		return
	end
	local old = character:FindFirstChild(HANDS_NAME)
	if old then
		old:Destroy()
	end
	local s = state[player]
	if not s or #s.hands == 0 then
		return
	end
	local model = Instance.new("Model")
	model.Name = HANDS_NAME
	-- one item in each hand; fall back to the root if the rig has no hands
	local handNames = { "LeftHand", "RightHand" }
	local root = rootOf(player)
	for i, key in ipairs(s.hands) do
		local item = Config.ITEM_BY_KEY[key]
		local hand = character:FindFirstChild(handNames[i] or "") or root
		if not hand or not item then
			continue
		end
		local p = Instance.new("Part")
		p.Name = key
		p.Size = Vector3.new(0.75, 0.75, 0.75)
		if hand == root then
			p.CFrame = root.CFrame * CFrame.new(if i == 1 then -0.9 else 0.9, -0.6, -0.6)
		else
			p.CFrame = hand.CFrame * CFrame.new(0, -0.45, 0)
		end
		p.Color = Theme.rgb(item.color)
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = false
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hand
		weld.Part1 = p
		weld.Parent = p
		p.Parent = model
	end
	model.Parent = character
end

local DIZZY_NAME = "OffBalance"

local function showDizzy(player, on)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end
	local old = head:FindFirstChild(DIZZY_NAME)
	if not on then
		if old then
			old:Destroy()
		end
		return
	end
	if old then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = DIZZY_NAME
	gui.Size = UDim2.fromScale(5, 1.4) -- studs, so it shrinks with distance
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.MaxDistance = 90
	gui.Parent = head
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Theme.DISPLAY
	label.TextScaled = true
	label.Text = "WHOA!"
	label.TextColor3 = Theme.GOLD
	label.TextStrokeColor3 = Theme.INK
	label.TextStrokeTransparency = 0
	label.Parent = gui
end

-- Walk speed, and no jumping while you push a trolley (designer,
-- 2026-10-05): a trolley is welded to you and doesn't collide, so a jump
-- lifted it into the air with you. Both JumpHeight and JumpPower are set,
-- because the place's UseJumpPower decides which one the engine reads.
-- With both at 0 the touch jump button hides itself.
local function refreshSpeed(player)
	local humanoid = humanoidOf(player)
	if not humanoid then
		return
	end
	local s = state[player]
	if shopping(s) and s.digging then
		humanoid.WalkSpeed = 0 -- rummaging: stood still, open to rams and steals
	elseif shopping(s) then
		humanoid.WalkSpeed = Rules.speedFor(#s.trolley, s.pushing, s.sprinting, stumbling(s))
	else
		humanoid.WalkSpeed = Config.LOBBY_SPEED
	end
	local canJump = not (shopping(s) and (s.pushing or s.digging))
	humanoid.JumpHeight = if canJump then StarterPlayer.CharacterJumpHeight else 0
	humanoid.JumpPower = if canJump then StarterPlayer.CharacterJumpPower else 0
end

local function changed(player, carriedChanged)
	local s = state[player]
	if carriedChanged then
		if s and s.trolleyModel and s.trolleyModel.Parent then
			Trolley.setItems(s.trolleyModel, s.trolley)
		end
		buildHands(player)
		refreshSpeed(player)
	end
	push(player)
end
Shoppers.changed = changed

local function removeTrolley(s)
	if s and s.trolleyModel then
		s.trolleyModel:Destroy()
		s.trolleyModel = nil
	end
	if s then
		s.pushing = false
	end
end

-- ------------------------------------------------------------
-- sprint meter
-- ------------------------------------------------------------

-- Fold the time since the last snapshot into the meter.
local function settleStamina(s, t)
	s.stamina = Rules.staminaAt(s.stamina, s.staminaAt, s.sprinting, s.regenAt, t)
	s.staminaAt = t
end

local function stopSprint(player, s, delay)
	if not s.sprinting then
		return
	end
	local t = now()
	settleStamina(s, t)
	s.sprinting = false
	s.regenAt = t + delay
	refreshSpeed(player)
	push(player)
end

-- Held down: sprint while the meter lasts. Released: stop and refill.
function Shoppers.setSprint(player, held)
	local s = state[player]
	if not shopping(s) then
		return
	end
	if not held then
		stopSprint(player, s, Config.SPRINT_REFILL_DELAY)
		return
	end
	if s.sprinting or stumbling(s) then
		return
	end
	local t = now()
	settleStamina(s, t)
	if s.stamina < Config.SPRINT_MIN_START then
		return
	end
	s.sprinting = true
	s.sprints += 1
	refreshSpeed(player)
	push(player)
end

-- ------------------------------------------------------------
-- round lifecycle (called by Round)
-- ------------------------------------------------------------

-- Chonk's menu changed (a new round, or his craving): every value with it.
function Shoppers.setMenu(newMenu)
	menu = newMenu or {}
	for player in pairs(state) do
		if player.Parent then
			push(player)
		end
	end
end

function Shoppers.menu()
	return menu
end

function Shoppers.beginRound(players, pool, randInt)
	state = {}
	active = true
	Trolley.clearAll()
	local t = now()
	for _, player in ipairs(players) do
		local list = Rules.dealList(pool, randInt)
		local s = {
			list = list,
			listSet = Rules.listSet(list),
			trolley = {},
			hands = {},
			pushing = false,
			trolleyModel = nil,
			bankedKeys = {},
			banked = 0,
			scanned = 0,
			atTill = nil,
			done = false,
			caught = false,
			score = 0,
			lost = 0,
			bonusPct = 0,
			checkoutAt = nil, -- seconds into the round
			-- sprint meter
			stamina = 1,
			staminaAt = t,
			sprinting = false,
			regenAt = 0,
			-- fights
			throwReadyAt = 0,
			stumbleUntil = 0,
			immuneUntil = 0, -- can't be knocked off balance again before this
			ramSafeUntil = 0, -- can't lose another item to a ram before this
			-- round log
			grabbed = 0,
			listGrabbed = 0,
			sprints = 0,
			letGo = 0,
			rams = 0,
			rammed = 0,
			steals = 0,
			stolenFrom = 0,
			throws = 0,
			hits = 0,
			hitsTaken = 0,
			shakes = 0,
			sabotages = 0, -- items this player threw into someone else's trolley
			plants = 0, -- yuck this player planted in a parked trolley
			sabotaged = 0, -- items that landed in this player's trolley from someone else
			yuckScanned = 0, -- yuck that went through a till: fed to Chonk
			digging = false,
			digStartedAt = 0,
			digSeconds = 0,
			picks = 0, -- items pulled out of their own pile
			lastScrape = 0,
		}
		state[player] = s
		local character = player.Character
		local root = rootOf(player)
		if character and root then
			s.trolleyModel = Trolley.build(player, root.CFrame)
			s.pushing = Trolley.attach(s.trolleyModel, character)
		end
		changed(player, true)
	end
end

-- Doors shut: shopping and scanning stop.
function Shoppers.closeStore()
	active = false
	for player, s in pairs(state) do
		Shoppers.stopDigging(player)
		if s.trolleyModel and s.pushing then
			Trolley.park(s.trolleyModel)
		end
		s.pushing = false
		s.sprinting = false
		s.stumbleUntil = 0
		showDizzy(player, false)
		refreshSpeed(player)
	end
end

function Shoppers.isOpen()
	return active
end

-- Back to the lobby: forget the round.
function Shoppers.resetAll()
	active = false
	local old = state
	state = {}
	Trolley.clearAll()
	for player in pairs(old) do
		if player.Parent then
			buildHands(player)
			showDizzy(player, false)
			refreshSpeed(player)
			push(player)
		end
	end
end

function Shoppers.get(player)
	return state[player]
end

-- Still shopping: in the round, not checked out, not shut in.
function Shoppers.isShopping(player)
	return shopping(state[player])
end

function Shoppers.participants()
	local list = {}
	for player in pairs(state) do
		if player.Parent then
			table.insert(list, player)
		end
	end
	return list
end

-- True when nobody in the round is still shopping.
function Shoppers.allFinished()
	for player, s in pairs(state) do
		if player.Parent and not s.done and not s.caught then
			return false
		end
	end
	return true
end

-- ------------------------------------------------------------
-- moving items (the fights use these)
-- ------------------------------------------------------------

-- Put an item wherever the player can carry it: the trolley if they're
-- pushing it and it has room, otherwise a free hand. False if neither.
function Shoppers.addCarried(player, key)
	local s = state[player]
	if not shopping(s) then
		return false
	end
	if s.pushing and #s.trolley < Config.TROLLEY_CAPACITY then
		table.insert(s.trolley, key)
	elseif #s.hands < handSlots(s) then
		table.insert(s.hands, key)
	else
		return false
	end
	changed(player, true)
	return true
end

-- Put an item into someone's trolley from outside: a throw that lands in it,
-- or yuck planted in it. Pushed or parked, as long as it has room.
function Shoppers.addToTrolley(player, key)
	local s = state[player]
	if not shopping(s) or not s.trolleyModel or #s.trolley >= Config.TROLLEY_CAPACITY then
		return false
	end
	table.insert(s.trolley, key)
	changed(player, true)
	return true
end

-- Take a yuck item out of the player's hands (for planting). nil if they
-- aren't holding one.
function Shoppers.takeYuckFromHands(player)
	local s = state[player]
	if not s then
		return nil
	end
	for i = #s.hands, 1, -1 do
		local item = Config.ITEM_BY_KEY[s.hands[i]]
		if item and item.kind == "yuck" then
			local key = table.remove(s.hands, i)
			changed(player, true)
			return key
		end
	end
	return nil
end

function Shoppers.holdsYuck(player)
	local s = state[player]
	if not s then
		return false
	end
	for _, key in ipairs(s.hands) do
		local item = Config.ITEM_BY_KEY[key]
		if item and item.kind == "yuck" then
			return true
		end
	end
	return false
end

-- The kinds on the player's list they haven't got yet (carried or scanned).
function Shoppers.missingFromList(player)
	local s = state[player]
	if not s then
		return {}
	end
	local have = haveSet(s)
	local missing = {}
	for _, key in ipairs(s.list) do
		if not have[key] then
			table.insert(missing, key)
		end
	end
	return missing
end

-- The top item of the player's trolley (the last one in), or nil.
function Shoppers.takeTopOfTrolley(player)
	local s = state[player]
	if not s or #s.trolley == 0 then
		return nil
	end
	local key = table.remove(s.trolley)
	changed(player, true)
	return key
end

-- The last item into the player's hands, or nil.
function Shoppers.takeFromHands(player)
	local s = state[player]
	if not s or #s.hands == 0 then
		return nil
	end
	local key = table.remove(s.hands)
	changed(player, true)
	return key
end

-- What a throw uses: the item in your hand if you're holding one (dig it
-- out first to choose), otherwise the TOP of the pile in the trolley you're
-- pushing, whatever that is. Returns the key, or nil.
function Shoppers.takeForThrow(player)
	local s = state[player]
	if not s then
		return nil
	end
	if #s.hands > 0 then
		local key = table.remove(s.hands)
		changed(player, true)
		return key
	end
	if not s.pushing or #s.trolley == 0 then
		return nil
	end
	local key = table.remove(s.trolley)
	changed(player, true)
	return key
end

-- ------------------------------------------------------------
-- digging (the rummage)
-- ------------------------------------------------------------

local function trolleyInReach(s, root)
	return s.trolleyModel ~= nil
		and (s.pushing or Trolley.distanceTo(s.trolleyModel, root.Position) <= Config.TROLLEY_REACH)
end

function Shoppers.stopDigging(player)
	local s = state[player]
	if not s or not s.digging then
		return
	end
	s.digging = false
	s.digSeconds += now() - s.digStartedAt
	refreshSpeed(player)
	push(player)
end

-- R: start rummaging in your own trolley (stood still), or stop.
function Shoppers.setDigging(player, on)
	local s = state[player]
	if not on then
		return Shoppers.stopDigging(player)
	end
	local root = rootOf(player)
	if not shopping(s) or not root or s.digging then
		return
	end
	if stumbling(s) then
		return Shoppers.note(player, "You're off balance! Wait a moment.", "warn")
	end
	if not trolleyInReach(s, root) then
		return Shoppers.note(player, "Your trolley is too far away. Walk back to it.", "note")
	end
	if #s.trolley == 0 then
		return Shoppers.note(player, "Your trolley is empty!", "note")
	end
	s.digging = true
	s.digStartedAt = now()
	if s.sprinting then
		settleStamina(s, now())
		s.sprinting = false
		s.regenAt = now() + Config.SPRINT_REFILL_DELAY
	end
	refreshSpeed(player)
	push(player)
end

-- A click in the dig view: pull item `slot` (it must be `key`, and on top)
-- out of your pile into a free hand. Your hands are the limit: with both
-- full, nothing more comes out until you throw (F) something.
function Shoppers.pick(player, slot, key)
	local s = state[player]
	local root = rootOf(player)
	if not shopping(s) or not root or not s.digging then
		return
	end
	if type(slot) ~= "number" or slot ~= math.floor(slot) or type(key) ~= "string" then
		return
	end
	if s.trolley[slot] ~= key or not trolleyInReach(s, root) then
		return -- the pile changed under them (a ram, a steal): the next click will be right
	end
	if #s.hands >= handSlots(s) then
		if s.pushing then
			return Shoppers.note(player, "One hand's on the trolley! Throw (F) what you're holding, or put it back.", "warn")
		end
		return Shoppers.note(player, "Your hands are full! Throw something (F) or put one back.", "warn")
	end
	if not Rules.reachable(slot, #s.trolley) then
		return Shoppers.note(player, "That's buried! Dig out what's on top first.", "note")
	end
	table.remove(s.trolley, slot)
	s.picks += 1
	table.insert(s.hands, key)
	Fx.playFor(player, "grab")
	changed(player, true)
	if #s.trolley == 0 then
		Shoppers.stopDigging(player)
	end
end

-- Put what's in hand `handIndex` (it must be `key`) back on top of your
-- pile, while digging.
function Shoppers.putBack(player, handIndex, key)
	local s = state[player]
	local root = rootOf(player)
	if not shopping(s) or not root or not s.digging then
		return
	end
	if type(handIndex) ~= "number" or s.hands[handIndex] ~= key or not trolleyInReach(s, root) then
		return
	end
	if #s.trolley >= Config.TROLLEY_CAPACITY then
		return Shoppers.note(player, "Your trolley is full!", "warn")
	end
	table.remove(s.hands, handIndex)
	table.insert(s.trolley, key)
	Fx.playFor(player, "grab")
	changed(player, true)
end

-- Knocked off balance: slowed, can't grab or sprint, for STUMBLE_SECONDS.
-- Afterwards nobody can do it again for HIT_IMMUNITY. Returns false if the
-- player can't be hit right now (immune, at a till, or not shopping).
function Shoppers.stumble(player)
	local s = state[player]
	local root = rootOf(player)
	if not shopping(s) or not root then
		return false
	end
	local t = now()
	if t < s.immuneUntil or Store.onAnyPad(root.Position) then
		return false
	end
	if s.sprinting then
		settleStamina(s, t)
		s.sprinting = false
		s.regenAt = t + Config.SPRINT_REFILL_DELAY
	end
	s.stumbleUntil = t + Config.STUMBLE_SECONDS
	s.immuneUntil = s.stumbleUntil + Config.HIT_IMMUNITY
	if s.digging then
		s.digging = false
		s.digSeconds += t - s.digStartedAt
	end
	s.hitsTaken += 1
	showDizzy(player, true)
	Fx.play("hit", root.Position)
	Fx.stars(player, Config.STUMBLE_SECONDS)
	Fx.jolt(player)
	refreshSpeed(player)
	push(player)
	local token = s.stumbleUntil
	task.delay(Config.STUMBLE_SECONDS, function()
		if state[player] == s and s.stumbleUntil == token then
			showDizzy(player, false)
			refreshSpeed(player)
			push(player)
		end
	end)
	return true
end

function Shoppers.isStumbling(player)
	local s = state[player]
	return s ~= nil and stumbling(s)
end

-- ------------------------------------------------------------
-- actions
-- ------------------------------------------------------------

function Shoppers.tryGrab(player, itemPart)
	local s = state[player]
	if not s then
		return Shoppers.note(player, "Wait for the next round to start shopping.", "note")
	end
	if not shopping(s) then
		return
	end
	if stumbling(s) then
		return Shoppers.note(player, "You're off balance! Wait a moment.", "warn")
	end
	if not itemPart.Parent then
		return -- somebody grabbed it first
	end
	local key = itemPart:GetAttribute(Config.ATTR.itemKey)
	if not Config.ITEM_BY_KEY[key] then
		return
	end
	local root = rootOf(player)
	if not root or (root.Position - itemPart.Position).Magnitude > Config.GRAB_RANGE + 3 then
		return
	end
	if s.pushing then
		if #s.trolley >= Config.TROLLEY_CAPACITY then
			return Shoppers.note(player, "Your trolley is full! Throw something out (F) or head to a till.", "warn")
		end
		table.insert(s.trolley, key)
	else
		if #s.hands >= handSlots(s) then
			return Shoppers.note(player, "Your hands are full! Go back to your trolley or a till.", "warn")
		end
		table.insert(s.hands, key)
	end
	itemPart:Destroy()
	s.grabbed += 1
	if s.listSet[key] then
		s.listGrabbed += 1
	end
	Fx.playFor(player, "grab")
	if key == Config.FLASH_ITEM.key then
		announceRemote:FireAllClients({
			text = ("%s GRABBED THE %s!"):format(player.DisplayName:upper(), Config.FLASH_ITEM.name:upper()),
			kind = "urgent",
		})
	elseif Config.ITEM_BY_KEY[key].kind == "yuck" then
		Chonk.react("yuck", player.DisplayName, Config.ITEM_BY_KEY[key].name)
	end
	changed(player, true)
end

-- Q: let go of the trolley, or take it back when it's in reach.
function Shoppers.toggleTrolley(player)
	local s = state[player]
	if not shopping(s) or not s.trolleyModel then
		return
	end
	Shoppers.stopDigging(player)
	if s.pushing then
		Trolley.park(s.trolleyModel)
		s.pushing = false
		s.letGo += 1
		changed(player, true)
		return
	end
	Shoppers.takeTrolley(player)
end

-- One hand goes on the handle: keep the newest item in your free hand, and
-- the rest go into the basket (onto the floor beside you if it's full).
local function settleHands(s, root)
	while #s.hands > Config.PUSH_HAND_SLOTS do
		local key = table.remove(s.hands, 1)
		if #s.trolley < Config.TROLLEY_CAPACITY then
			table.insert(s.trolley, key)
		else
			Store.dropItem(key, root.Position + root.CFrame.RightVector * 3)
		end
	end
end

function Shoppers.takeTrolley(player)
	local s = state[player]
	if not shopping(s) or s.pushing or not s.trolleyModel then
		return
	end
	local root = rootOf(player)
	if not root then
		return
	end
	if Trolley.distanceTo(s.trolleyModel, root.Position) > Config.TROLLEY_REACH then
		return Shoppers.note(player, "Your trolley is too far away. Walk back to it.", "note")
	end
	if not Trolley.attach(s.trolleyModel, player.Character) then
		return
	end
	s.pushing = true
	settleHands(s, root)
	changed(player, true)
end

-- Admin: drop random items straight into the trolley.
function Shoppers.giveRandom(player, count)
	local s = state[player]
	if not shopping(s) then
		return false
	end
	for _ = 1, count do
		if #s.trolley >= Config.TROLLEY_CAPACITY then
			break
		end
		local item = Config.ITEMS[math.random(1, #Config.ITEMS)]
		table.insert(s.trolley, item.key)
	end
	changed(player, true)
	return true
end

function Shoppers.setAtTill(player, tillIndex)
	local s = state[player]
	if s and s.atTill ~= tillIndex then
		s.atTill = tillIndex
		push(player)
	end
end

-- The till scans one item: hands first, then the trolley if it's pushed.
function Shoppers.scanOne(player)
	local s = state[player]
	if not s then
		return
	end
	local key
	if #s.hands > 0 then
		key = table.remove(s.hands, 1)
	elseif s.pushing and #s.trolley > 0 then
		key = table.remove(s.trolley, 1)
	else
		return
	end
	s.banked += Rules.itemValue(key, s.listSet, menu)
	s.bankedKeys[key] = true
	if Config.ITEM_BY_KEY[key].kind == "yuck" then
		s.yuckScanned += 1
	end
	s.scanned += 1
	changed(player, true)
end

-- Everything scanned: the player is out of the store with their bonus.
function Shoppers.finish(player, elapsed)
	local s = state[player]
	if not s or s.done then
		return
	end
	local secondsLeft = math.max(0, Config.ROUND_SECONDS - elapsed)
	Shoppers.stopDigging(player)
	s.done = true
	s.atTill = nil
	s.sprinting = false
	s.checkoutAt = elapsed
	s.score = Rules.finalScore(s.banked, secondsLeft)
	s.bonusPct = math.floor((Rules.earlyMultiplier(secondsLeft) - 1) * 100 + 0.5)
	removeTrolley(s)
	showDizzy(player, false)
	changed(player, true)
	Fx.playFor(player, "checkout")
	Shoppers.note(
		player,
		("CHECKED OUT! %s (+%d%% early bonus)"):format(Rules.formatYum(s.score), s.bonusPct),
		"good"
	)
	task.delay(1.2, function()
		local character = player.Character
		if player.Parent and character then
			character:PivotTo(Store.windowSpot())
		end
	end)
end

-- The shutters closed with this player still inside.
function Shoppers.shutIn(player)
	local s = state[player]
	if not s or s.done or s.caught then
		return
	end
	Shoppers.stopDigging(player)
	s.caught = true
	s.atTill = nil
	s.lost = Rules.valueOf(s.trolley, s.listSet, menu) + Rules.valueOf(s.hands, s.listSet, menu)
	s.trolley = {}
	s.hands = {}
	s.score = s.banked
	changed(player, true)
	if s.lost > 0 then
		Shoppers.note(player, ("SHUT IN! You lost %s"):format(Rules.formatYum(s.lost)), "bad")
	else
		Shoppers.note(player, "SHUT IN! The store closed with you inside.", "bad")
	end
end

-- One row per participant, best score first.
function Shoppers.results()
	local rows = {}
	for player, s in pairs(state) do
		if player.Parent then
			table.insert(rows, {
				name = player.DisplayName,
				userId = player.UserId,
				score = s.score,
				banked = s.banked,
				bonusPct = s.bonusPct,
				caught = s.caught,
				lost = s.lost,
				grabbed = s.grabbed,
				listGrabbed = s.listGrabbed,
				checkoutAt = s.checkoutAt,
				sprints = s.sprints,
				letGo = s.letGo,
				rams = s.rams,
				rammed = s.rammed,
				steals = s.steals,
				stolenFrom = s.stolenFrom,
				throws = s.throws,
				hits = s.hits,
				hitsTaken = s.hitsTaken,
				shakes = s.shakes,
				sabotages = s.sabotages,
				plants = s.plants,
				sabotaged = s.sabotaged,
				yuckScanned = s.yuckScanned,
				digSeconds = s.digSeconds,
				picks = s.picks,
				player = player,
			})
		end
	end
	return Rules.rankRows(rows)
end

-- ------------------------------------------------------------
-- start
-- ------------------------------------------------------------

function Shoppers.start()
	playerStateRemote = Remotes.get("PlayerState")
	announceRemote = Remotes.get("Announce")
	Store.setGrabHandler(Shoppers.tryGrab)

	Remotes.get("TrolleyToggle").OnServerEvent:Connect(function(player)
		Shoppers.toggleTrolley(player)
	end)
	Remotes.get("Sprint").OnServerEvent:Connect(function(player, held)
		Shoppers.setSprint(player, held == true)
	end)
	Remotes.get("Dig").OnServerEvent:Connect(function(player, on)
		Shoppers.setDigging(player, on == true)
	end)
	Remotes.get("TakeOut").OnServerEvent:Connect(function(player, slot, key)
		if Config.ITEM_BY_KEY[key] then
			Shoppers.pick(player, slot, key)
		end
	end)
	Remotes.get("PutBack").OnServerEvent:Connect(function(player, handIndex, key)
		if Config.ITEM_BY_KEY[key] then
			Shoppers.putBack(player, handIndex, key)
		end
	end)

	-- the meter running dry ends a sprint
	RunService.Heartbeat:Connect(function()
		local t = now()
		for player, s in pairs(state) do
			if s.sprinting and Rules.staminaAt(s.stamina, s.staminaAt, true, s.regenAt, t) <= 0 then
				stopSprint(player, s, Config.SPRINT_EXHAUSTED_DELAY)
			end
		end
	end)

	-- The owner's "Push" prompt on a parked trolley.
	Trolley.folder().DescendantAdded:Connect(function(inst)
		if inst:IsA("ProximityPrompt") and inst.Name == "Push" then
			inst.Triggered:Connect(function(player)
				local s = state[player]
				if s and s.trolleyModel and inst:IsDescendantOf(s.trolleyModel) then
					Shoppers.takeTrolley(player)
				end
			end)
		end
	end)

	local function onCharacter(player, character)
		character:WaitForChild("HumanoidRootPart", 10)
		-- The engine places a new character after CharacterAdded fires, so
		-- anything that moves it waits a beat.
		task.delay(0.3, function()
			if player.Character ~= character then
				return
			end
			local s = state[player]
			if shopping(s) then
				-- reset mid-round: back into the store; the trolley comes too
				character:PivotTo(Store.entranceSpots(1)[1])
				if s.trolleyModel then
					s.pushing = Trolley.attach(s.trolleyModel, character)
					local root = rootOf(player)
					if s.pushing and root then
						settleHands(s, root)
					end
				end
			end
			changed(player, true)
		end)
	end

	local function onPlayer(player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		player.CharacterRemoving:Connect(function()
			-- don't let a pushed trolley fall over with the old character
			local s = state[player]
			if s and s.trolleyModel and s.pushing then
				Trolley.park(s.trolleyModel)
				s.pushing = false
			end
		end)
		if player.Character then
			onCharacter(player, player.Character)
		end
		task.defer(push, player)
	end

	Players.PlayerAdded:Connect(onPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		removeTrolley(state[player])
		state[player] = nil
	end)
end

return Shoppers
