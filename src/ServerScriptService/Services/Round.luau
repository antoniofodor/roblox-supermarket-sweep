-- The match loop: lobby -> five rounds of (shopping -> feeding) -> podium.
--
--   lobby     wait for MIN_PLAYERS (or the admin start); everyone ready joins
--             the match
--   shopping  the two-minute round, with Big Chonk's menu: a food he's not
--             in the mood for (from the doors), a craving (CRAVING_AT), his
--             shouts by name, and banging on the glass during the shutters
--   feeding   everyone lines up in front of Chonk and is revealed on his
--             mood meter, best first; then he eats the worst feeders
--             (Rules.cutsThisRound), who go to the stands
--   podium    after round MATCH_ROUNDS: 1st, 2nd, 3rd, and the winner is
--             crowned and carried on his head
--
-- Round state is published as attributes on ReplicatedStorage (names in
-- Config.ATTR), in server time, so every client draws the same clock from
-- workspace:GetServerTimeNow(). Each player's place in the match is an
-- attribute on the Player. The admin skips work by moving the round's start
-- time, so every threshold below fires the same way it would have.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Rules = require(Shared.Rules)
local Remotes = require(Shared.Remotes)
local Theme = require(Shared.Theme)
local Scorecard = require(Shared.Scorecard)

local Store = require(script.Parent.Store)
local Shoppers = require(script.Parent.Shoppers)
local Checkout = require(script.Parent.Checkout)
local Fights = require(script.Parent.Fights)
local Fx = require(script.Parent.Fx)
local Chonk = require(script.Parent.Chonk)

local Round = {}

local ATTR = Config.ATTR
local PHASE = Config.PHASE
local STATUS = Config.MATCH_STATUS

local forceStart = false
local endMatchEarly = false
local roundStartedAt = 0
local roundNumber = 0 -- every round played since the server started (the log's numbering)
local matchRound = 0 -- 1..MATCH_ROUNDS while a match runs
local inShopping = false
local maxQueue = 0 -- the scorecard's queue at closing, this round
local matchesPlayed = {} -- [userId] = matches started, for "matches before leaving"
local eatenLastMatch = {} -- [userId] = true: for "eliminated players still here next match"
local rng = Random.new()
local announceRemote
local resultsRemote

local function now()
	return Workspace:GetServerTimeNow()
end

local function randInt(lo, hi)
	return rng:NextInteger(lo, hi)
end

local function setPhase(phase, endsAt)
	ReplicatedStorage:SetAttribute(ATTR.phase, phase)
	ReplicatedStorage:SetAttribute(ATTR.phaseEndsAt, endsAt or 0)
end

local function announceAll(text, kind)
	announceRemote:FireAllClients({ text = text, kind = kind or "info" })
end

local function itemName(key)
	local item = Config.ITEM_BY_KEY[key]
	return item and item.name or tostring(key)
end

local function setStatus(player, status)
	player:SetAttribute(ATTR.matchStatus, status)
end

local function hasCharacter(player)
	local character = player.Character
	return character ~= nil and character:FindFirstChild("HumanoidRootPart") ~= nil
end

local function readyPlayers()
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if hasCharacter(player) then
			table.insert(list, player)
		end
	end
	return list
end

-- Still in the match, and here with a character.
local function alivePlayers()
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute(ATTR.matchStatus) == STATUS.alive and hasCharacter(player) then
			table.insert(list, player)
		end
	end
	return list
end

local function moveTo(player, cf)
	local character = player.Character
	if character then
		character:PivotTo(cf)
	end
end

local function sendToLobby(players)
	for _, player in ipairs(players) do
		moveTo(player, Store.lobbySpot())
	end
end

-- Clear the store between rounds: no trolleys, tills reset, shutters up.
local function tidyStore()
	Shoppers.resetAll()
	Checkout.reset()
	Store.raiseShutters(2)
	ReplicatedStorage:SetAttribute(ATTR.craving, "")
	ReplicatedStorage:SetAttribute(ATTR.notToday, "")
end

-- ------------------------------------------------------------
-- phases
-- ------------------------------------------------------------

-- Before a match: wait for enough players, then everyone ready is in.
local function runLobby()
	tidyStore()
	Chonk.quiet()
	matchRound = 0
	endMatchEarly = false
	ReplicatedStorage:SetAttribute(ATTR.matchRound, 0)
	for _, player in ipairs(Players:GetPlayers()) do
		setStatus(player, STATUS.waiting)
	end
	setPhase(PHASE.waiting, nil)
	local endsAt = nil
	while true do
		local count = #readyPlayers()
		ReplicatedStorage:SetAttribute(ATTR.playersReady, count)
		if forceStart and count >= 1 then
			break
		end
		if count >= Config.MIN_PLAYERS then
			if not endsAt then
				endsAt = now() + Config.LOBBY_SECONDS
				setPhase(PHASE.lobby, endsAt)
			end
			if now() >= endsAt then
				break
			end
		elseif endsAt then
			endsAt = nil
			setPhase(PHASE.waiting, nil)
		end
		task.wait(0.2)
	end
	forceStart = false
	for _, player in ipairs(readyPlayers()) do
		setStatus(player, STATUS.alive)
		matchesPlayed[player.UserId] = (matchesPlayed[player.UserId] or 0) + 1
	end
	print(("[Match] starting with %d players"):format(#alivePlayers()))
	local eaten, stayed = 0, 0
	for userId in pairs(eatenLastMatch) do
		eaten += 1
		if Players:GetPlayerByUserId(userId) then
			stayed += 1
		end
	end
	if eaten > 0 then
		print(("[Scorecard] eaten last match and still here: %d of %d (target: most)"):format(stayed, eaten))
	end
	eatenLastMatch = {}
end

-- The short countdown before rounds 2 to 5.
local function runBetween()
	tidyStore()
	local endsAt = now() + Config.BETWEEN_ROUNDS_SECONDS
	setPhase(PHASE.lobby, endsAt)
	Chonk.say(("ROUND %d! I'M STILL HUNGRY!"):format(matchRound), "calm")
	task.wait(Config.BETWEEN_ROUNDS_SECONDS)
end

-- Big Chonk shouts at someone still shopping, by name: what's missing from
-- their list, or to hurry up.
local function nag(elapsed)
	local shopping = {}
	for _, player in ipairs(Shoppers.participants()) do
		if Shoppers.isShopping(player) then
			table.insert(shopping, player)
		end
	end
	if #shopping == 0 then
		return
	end
	local target = shopping[rng:NextInteger(1, #shopping)]
	local name = target.DisplayName:upper()
	local missing = Shoppers.missingFromList(target)
	if #missing > 0 and elapsed < Config.CLOSING_WARN_AT then
		Chonk.say(Chonk.line("missing", name, itemName(missing[rng:NextInteger(1, #missing)]):upper()))
	elseif elapsed >= Config.SHUTTER_STARTS_AT then
		Chonk.say(Chonk.line("furious"))
	else
		Chonk.say(Chonk.line("listDone", name))
	end
end

local function runShopping(players)
	roundNumber += 1
	Store.restock()

	-- Chonk's menu: a food he's tired of from the doors, a craving later
	local notToday = Rules.pickNotToday(randInt)
	local menu = { notToday = notToday }
	Shoppers.setMenu(menu)
	local pool = Rules.dealPool(randInt, notToday)
	ReplicatedStorage:SetAttribute(ATTR.notToday, notToday)
	ReplicatedStorage:SetAttribute(ATTR.craving, "")
	-- not marked on the items: the Chonk card and his shout say it, and
	-- remembering is part of the game (designer, 2026-10-05)

	-- move everyone in first: each trolley is built in front of its owner
	local spots = Store.entranceSpots(#players)
	for i, player in ipairs(players) do
		player.Character:PivotTo(spots[i])
	end
	Shoppers.beginRound(players, pool, randInt)

	roundStartedAt = now()
	inShopping = true
	ReplicatedStorage:SetAttribute(ATTR.roundNumber, roundNumber)
	ReplicatedStorage:SetAttribute(ATTR.roundStartedAt, roundStartedAt)
	setPhase(PHASE.shopping, roundStartedAt + Config.ROUND_SECONDS)
	announceAll(("ROUND %d OF %d! DOORS OPEN! Grab your list!"):format(matchRound, Config.MATCH_ROUNDS), "go")
	Chonk.say(Chonk.line("notToday", itemName(notToday):upper()), "calm")
	print(
		("[Round %d] match round %d/%d, doors open: %d players, %d items on the shelves, not today: %s"):format(
			roundNumber,
			matchRound,
			Config.MATCH_ROUNDS,
			#players,
			Store.stockCount(),
			notToday
		)
	)

	local fired = {}
	local function once(key, fn)
		if not fired[key] then
			fired[key] = true
			fn()
		end
	end

	local last = os.clock()
	local endedEarly = false
	local nextNagAt = 8
	local nextBangAt = 0
	maxQueue = 0
	while true do
		task.wait(0.1)
		local clock = os.clock()
		local dt = math.min(clock - last, 0.5)
		last = clock
		local elapsed = now() - roundStartedAt

		-- Chonk's craving: one food is worth CRAVING_MULTIPLIER for the rest of the round
		if elapsed >= Config.CRAVING_AT then
			once("craving", function()
				local craving = Rules.pickCraving(randInt, notToday)
				menu.craving = craving
				Shoppers.setMenu(menu)
				ReplicatedStorage:SetAttribute(ATTR.craving, craving)
				Store.markKind(craving, ("x%d CRAVING"):format(Config.CRAVING_MULTIPLIER), Theme.GOLD)
				local name = itemName(craving):upper()
				Chonk.say(Chonk.line("craving", name, name), "grumpy")
				announceAll(("BIG CHONK WANTS %s! It's worth x%d for everyone!"):format(name, Config.CRAVING_MULTIPLIER), "chonk")
				Fx.playAll("flash")
			end)
		end

		-- the flash sale: one golden turkey, gone if nobody grabs it in time
		local saleEnds = Config.FLASH_SALE_AT + Config.FLASH_SALE_SECONDS
		if elapsed >= Config.FLASH_SALE_AT and elapsed < saleEnds then
			once("sale", function()
				Store.startFlashSale()
				announceAll(
					("FLASH SALE! A %s worth %s at the end of the middle aisle! %d SECONDS!"):format(
						Config.FLASH_ITEM.name:upper(),
						Rules.formatYum(Config.FLASH_ITEM.yum):upper(),
						Config.FLASH_SALE_SECONDS
					),
					"urgent"
				)
			end)
		end
		if Store.saleRunning() and not Store.flashSaleLive() then
			Store.endFlashSale() -- somebody grabbed it: the beam comes down
		end
		if elapsed >= saleEnds - 10 and elapsed < saleEnds and Store.flashSaleLive() then
			once("saleWarn", function()
				announceAll(("10 SECONDS LEFT ON THE %s!"):format(Config.FLASH_ITEM.name:upper()), "warn")
			end)
		end
		-- a sale that runs to closing just ends with the store; "STORE CLOSED!" says it
		if elapsed >= saleEnds and elapsed < Config.ROUND_SECONDS then
			once("saleOver", function()
				if Store.endFlashSale() then
					announceAll("FLASH SALE OVER! Nobody got the turkey.", "info")
				end
			end)
		end

		if Rules.tillsOpen(elapsed) then
			once("tillsOpen", function()
				announceAll("THE TILLS ARE OPEN! Check out to keep what you've got.", "go")
				Fx.playAll("checkout")
			end)
		end
		if elapsed >= Config.CLOSING_WARN_AT then
			once("closing", function()
				announceAll(
					("STORE CLOSES IN %d SECONDS! Head to the tills!"):format(Config.ROUND_SECONDS - Config.CLOSING_WARN_AT),
					"warn"
				)
				Fx.playAll("alarm")
				Chonk.setMood("grumpy")
			end)
		end
		-- his tantrum: he slams the building and every shelf drops something
		if elapsed >= Config.TANTRUM_AT then
			once("tantrum", function()
				local fell = Store.shakeAll()
				Chonk.say(Chonk.line("tantrum"), "furious")
				Chonk.bang()
				Fx.playAll("shelf")
				announceAll("BIG CHONK SLAMMED THE STORE! Food is falling everywhere!", "chonk")
				print(("[Round %d] Chonk's tantrum: %d items fell"):format(roundNumber, fell))
			end)
		end
		if elapsed >= Config.SHUTTER_STARTS_AT then
			once("shutters", function()
				Store.lowerShutters(math.max(0.5, Config.ROUND_SECONDS - elapsed))
				announceAll("SHUTTERS COMING DOWN! Check out or lose it all!", "urgent")
				Fx.playAll("alarm")
				Fx.play("shutter", Vector3.new(0, Store.FLOOR_Y + 6, 48))
				Chonk.say(Chonk.line("furious"), "furious")
			end)
			-- he bangs on the glass until the store closes
			if elapsed >= nextBangAt then
				nextBangAt = elapsed + Config.CHONK_BANG_EVERY
				Chonk.bang()
			end
		end

		-- his shouts by name
		if elapsed >= nextNagAt then
			nextNagAt = elapsed + Config.CHONK_NAG_EVERY
			if elapsed > Config.CRAVING_AT + 3 or elapsed < Config.CRAVING_AT - 3 then
				nag(elapsed)
			end
		end

		Checkout.step(dt, elapsed)
		Fights.step()

		-- the scorecard's queue: shoppers waiting in the till lanes, not yet at a till
		if elapsed >= Config.CLOSING_WARN_AT then
			local waiting = 0
			for _, player in ipairs(Shoppers.participants()) do
				local root = Shoppers.rootOf(player)
				local s = Shoppers.get(player)
				if root and Shoppers.isShopping(player) and not s.atTill and Store.inTillLanes(root.Position) then
					waiting += 1
				end
			end
			maxQueue = math.max(maxQueue, waiting)
		end

		if elapsed >= Config.ROUND_SECONDS then
			break
		end
		if #Shoppers.participants() == 0 or Shoppers.allFinished() then
			endedEarly = true
			break
		end
	end

	inShopping = false
	Store.endFlashSale()
	Fights.clearFlights()
	Shoppers.closeStore()
	Checkout.stopAll()
	Store.lowerShutters(if endedEarly then 1.5 else 0.3)
	Fx.play("shutter", Vector3.new(0, Store.FLOOR_Y + 6, 48))
	for _, player in ipairs(Shoppers.participants()) do
		Shoppers.shutIn(player)
	end
	announceAll(if endedEarly then "EVERYONE'S OUT! Store closed." else "STORE CLOSED!", "info")
end

local function logScorecard(rows)
	print(("[Scorecard] round %d (match round %d/%d)"):format(roundNumber, matchRound, Config.MATCH_ROUNDS))
	for _, line in ipairs(Scorecard.lines(Scorecard.round(rows, { maxQueue = maxQueue }), #rows)) do
		print(line)
	end
end

local function logRound(rows)
	local caught = 0
	for _, row in ipairs(rows) do
		if row.caught then
			caught += 1
		end
	end
	print(("[Round %d] results (match round %d/%d): %d players, %d shut in"):format(roundNumber, matchRound, Config.MATCH_ROUNDS, #rows, caught))
	for rank, row in ipairs(rows) do
		print(
			("  %d. %-16s score %-8s banked %-8s bonus %3d%%  grabbed %2d (list %2d)  sprints %d  let go %d  %s%s%s"):format(
				rank,
				row.name,
				Rules.formatYum(row.score),
				Rules.formatYum(row.banked),
				row.bonusPct,
				row.grabbed,
				row.listGrabbed,
				row.sprints or 0,
				row.letGo or 0,
				if row.checkoutAt then ("out at %ds"):format(math.floor(row.checkoutAt)) else "",
				if row.caught then ("SHUT IN, lost %s"):format(Rules.formatYum(row.lost)) else "",
				if row.eaten then "  EATEN" else ""
			)
		)
		print(
			("     rams %d (rammed %d)  steals %d (stolen from %d)  throws %d  hits %d (hit %d)  shelves shaken %d  sabotage: threw in %d, planted %d, got %d"):format(
				row.rams or 0,
				row.rammed or 0,
				row.steals or 0,
				row.stolenFrom or 0,
				row.throws or 0,
				row.hits or 0,
				row.hitsTaken or 0,
				row.shakes or 0,
				row.sabotages or 0,
				row.plants or 0,
				row.sabotaged or 0
			)
		)
	end
end

-- Chonk's verdict on one player, for his bubble.
local function verdict(row)
	if row.score <= 0 then
		return Chonk.line("nothing", row.name:upper())
	end
	return Chonk.line(row.mood, row.name:upper())
end

-- After every round: the line-up, the mood meter, the gulp. Returns the
-- ranked rows.
local function runFeeding()
	local rows = Shoppers.results() -- ranked, best first; only players still here
	local cut = math.min(Rules.cutsThisRound(#rows, matchRound), #rows)
	local best = if #rows > 0 then rows[1].score else 0
	-- the players in danger are revealed slowly: the eaten, and the one just above
	local danger = if cut > 0 then cut + 1 elseif #rows > 1 then 1 else 0

	local t = now() + Config.FEED_INTRO_SECONDS
	local payloadRows = {}
	for rank, row in ipairs(rows) do
		row.eaten = rank > #rows - cut
		row.danger = rank > #rows - danger
		row.meter = Rules.meterFor(row.score, best, row.eaten)
		row.mood = Rules.moodAt(row.meter)
		row.revealSeconds = if row.danger then Config.FEED_DANGER_SECONDS else Config.FEED_SAFE_SECONDS
		row.revealAt = t
		t += row.revealSeconds
		table.insert(payloadRows, {
			name = row.name,
			userId = row.userId,
			score = row.score,
			meter = row.meter,
			mood = row.mood,
			eaten = row.eaten,
			danger = row.danger,
			caught = row.caught,
			revealAt = row.revealAt,
			revealSeconds = row.revealSeconds,
		})
	end
	local gulpAt = t
	local endsAt = gulpAt + (if cut > 0 then Config.FEED_EATEN_SECONDS else 0) + Config.FEED_OUTRO_SECONDS

	setPhase(PHASE.results, endsAt)
	resultsRemote:FireAllClients({
		round = matchRound,
		rounds = Config.MATCH_ROUNDS,
		final = matchRound >= Config.MATCH_ROUNDS,
		cut = cut,
		rows = payloadRows,
		gulpAt = gulpAt,
		endsAt = endsAt,
	})
	logRound(rows)
	logScorecard(rows)

	-- everyone lines up in front of him, in reveal order
	local spots = Chonk.lineSpots(#rows)
	for i, row in ipairs(rows) do
		if row.player.Parent then
			moveTo(row.player, spots[i])
		end
	end
	Chonk.say("FEEDING TIME!", "calm")

	-- his verdict on each, as the meter settles
	for _, row in ipairs(rows) do
		local wait = row.revealAt + row.revealSeconds * 0.85 - now()
		if wait > 0 then
			task.wait(wait)
		end
		Chonk.say(verdict(row), if row.mood == "love" then "happy" elseif row.mood == "angry" then "furious" else "calm")
	end
	local wait = gulpAt - now()
	if wait > 0 then
		task.wait(wait)
	end

	if cut > 0 then
		local names = {}
		for _, row in ipairs(rows) do
			if row.eaten then
				table.insert(names, row.name)
				eatenLastMatch[row.userId] = true
				if row.player.Parent then
					setStatus(row.player, STATUS.out)
				end
			end
		end
		local list = table.concat(names, " and ")
		Chonk.say(Chonk.line("gulp", list:upper()), "happy")
		announceAll(("GULP! Big Chonk ate %s!"):format(list), "chonk")
		Fx.playAll("hit")
		task.wait(1.5)
		for _, row in ipairs(rows) do
			if row.eaten and row.player.Parent then
				moveTo(row.player, Chonk.standsSpot())
			end
		end
	end
	local left = endsAt - now()
	if left > 0 then
		task.wait(left)
	end
	return rows
end

-- After the last round: 3rd, 2nd, then the winner, who Chonk carries.
local function runPodium(rows)
	local endsAt = now() + Config.PODIUM_SECONDS
	setPhase(PHASE.podium, endsAt)
	local top = {}
	for rank = 1, math.min(3, #rows) do
		local row = rows[rank]
		table.insert(top, { name = row.name, userId = row.userId, score = row.score })
		if row.player.Parent then
			moveTo(row.player, Chonk.podiumSpot(rank))
		end
	end
	resultsRemote:FireAllClients({ podium = true, rows = top, endsAt = endsAt })
	local winner = rows[1]
	if winner then
		print(("[Match] winner: %s with %s"):format(winner.name, Rules.formatYum(winner.score)))
		Chonk.crown(winner.player, true)
		Chonk.say(Chonk.line("winner", winner.name:upper()), "happy")
		announceAll(("%s WINS THE MATCH!"):format(winner.name:upper()), "chonk")
		Fx.playAll("checkout")
		task.wait(3)
		if winner.player.Parent then
			moveTo(winner.player, Chonk.headSpot()) -- carried on his head
		end
	end
	local left = endsAt - now()
	if left > 0 then
		task.wait(left)
	end
	if winner then
		Chonk.crown(winner.player, false)
	end
	sendToLobby(readyPlayers())
end

local function runMatch()
	local lastRows = {}
	for r = 1, Config.MATCH_ROUNDS do
		matchRound = r
		ReplicatedStorage:SetAttribute(ATTR.matchRound, r)
		if r > 1 then
			runBetween()
		end
		local players = alivePlayers()
		if #players == 0 then
			print("[Match] nobody left in the match")
			return
		end
		runShopping(players)
		lastRows = runFeeding()
		if endMatchEarly then
			print("[Match] ended early by admin")
			break
		end
	end
	if #lastRows > 0 then
		runPodium(lastRows)
	end
end

-- ------------------------------------------------------------
-- admin hooks
-- ------------------------------------------------------------

-- Start the match from the lobby now, even alone.
function Round.forceStart()
	forceStart = true
end

-- Finish the match after the round being played (goes to the podium).
function Round.endMatch()
	if matchRound == 0 then
		return false
	end
	endMatchEarly = true
	return true
end

-- Jump the running round's clock to `seconds` after doors open.
function Round.skipTo(seconds)
	if not inShopping then
		return false
	end
	local elapsed = now() - roundStartedAt
	if seconds <= elapsed then
		return false
	end
	roundStartedAt = now() - seconds
	ReplicatedStorage:SetAttribute(ATTR.roundStartedAt, roundStartedAt)
	setPhase(PHASE.shopping, roundStartedAt + Config.ROUND_SECONDS)
	return true
end

function Round.start()
	announceRemote = Remotes.get("Announce")
	resultsRemote = Remotes.get("Results")
	ReplicatedStorage:SetAttribute(ATTR.roundNumber, 0)
	ReplicatedStorage:SetAttribute(ATTR.roundStartedAt, 0)
	ReplicatedStorage:SetAttribute(ATTR.matchRound, 0)
	ReplicatedStorage:SetAttribute(ATTR.craving, "")
	ReplicatedStorage:SetAttribute(ATTR.notToday, "")
	-- anyone arriving mid-match waits for the next one
	Players.PlayerAdded:Connect(function(player)
		setStatus(player, STATUS.waiting)
	end)
	-- the scorecard's "matches before leaving" (target 2+)
	Players.PlayerRemoving:Connect(function(player)
		print(("[Scorecard] %s left after %d match(es) (target: 2+)"):format(player.Name, matchesPlayed[player.UserId] or 0))
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		setStatus(player, STATUS.waiting)
	end
	task.spawn(function()
		while true do
			local ok, err = pcall(function()
				runLobby()
				runMatch()
			end)
			if not ok then
				-- never leave the game stuck: log it and go back to the lobby
				warn("[Round] loop error: " .. tostring(err))
				inShopping = false
				sendToLobby(readyPlayers())
				task.wait(2)
			end
		end
	end)
end

return Round
