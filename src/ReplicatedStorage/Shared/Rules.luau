-- The rules of a round and a match as pure functions: dealing lists, valuing
-- items, scoring, walk speed, which stage of the clock we're in, how many
-- Big Chonk eats each round, and where a player lands on his mood meter.
--
-- A round's MENU is { craving = key?, notToday = key? }: the food Chonk
-- craves (from CRAVING_AT) and the one he's not in the mood for. Every
-- value goes through Rules.itemValue with it.
--
-- No Roblox APIs in here, so tests/rules.luau can run it offline. Randomness
-- comes in as a `randInt(lo, hi)` function: the server passes one built on
-- Random.new(), the tests pass math.random.

local Config = if typeof(script) == "Instance" then require(script.Parent.Config) else require("./Config")

local Rules = {}

local function shuffle(list, randInt)
	for i = #list, 2, -1 do
		local j = randInt(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

-- The item kinds lists are drawn from this round: staples only, never the
-- food Chonk is not in the mood for.
function Rules.dealPool(randInt, notToday)
	local keys = {}
	for _, item in ipairs(Config.ITEMS) do
		if item.kind == "staple" and item.key ~= notToday then
			table.insert(keys, item.key)
		end
	end
	shuffle(keys, randInt)
	local pool = {}
	for i = 1, math.min(Config.LIST_POOL, #keys) do
		pool[i] = keys[i]
	end
	return pool
end

-- One player's list: LIST_SIZE distinct kinds from the pool.
function Rules.dealList(pool, randInt)
	local copy = table.clone(pool)
	shuffle(copy, randInt)
	local list = {}
	for i = 1, math.min(Config.LIST_SIZE, #copy) do
		list[i] = copy[i]
	end
	return list
end

function Rules.listSet(list)
	local set = {}
	for _, key in ipairs(list) do
		set[key] = true
	end
	return set
end

-- Food Chonk can crave or be tired of: anything he normally likes.
local function likedKeys(except)
	local keys = {}
	for _, item in ipairs(Config.ITEMS) do
		if (item.kind == "staple" or item.kind == "snack") and item.key ~= except then
			table.insert(keys, item.key)
		end
	end
	return keys
end

function Rules.pickNotToday(randInt)
	local keys = likedKeys(nil)
	return keys[randInt(1, #keys)]
end

function Rules.pickCraving(randInt, notToday)
	local keys = likedKeys(notToday)
	return keys[randInt(1, #keys)]
end

-- What one item is worth to a player with this list, in yum. Multipliers
-- don't stack: the bigger of the list's and the craving's applies. Yuck is
-- never multiplied, and the not-today food is worth NOT_TODAY_YUM to all.
function Rules.itemValue(key, listSet, menu)
	local item = Config.ITEM_BY_KEY[key]
	if not item then
		return 0
	end
	if menu and menu.notToday == key then
		return Config.NOT_TODAY_YUM
	end
	if item.yum < 0 then
		return item.yum
	end
	local multiplier = 1
	if listSet[key] then
		multiplier = Config.LIST_MULTIPLIER
	end
	if menu and menu.craving == key then
		multiplier = math.max(multiplier, Config.CRAVING_MULTIPLIER)
	end
	return item.yum * multiplier
end

function Rules.valueOf(keys, listSet, menu)
	local total = 0
	for _, key in ipairs(keys) do
		total += Rules.itemValue(key, listSet, menu)
	end
	return total
end

function Rules.earlyMultiplier(secondsLeft)
	return 1 + Config.EARLY_BONUS_PER_SECOND * math.max(0, secondsLeft)
end

-- secondsLeft is nil for a player who never finished checking out: they keep
-- what was scanned and get no bonus.
function Rules.finalScore(banked, secondsLeft)
	if secondsLeft == nil or banked <= 0 then
		return banked -- a bonus never makes a bad bag worse
	end
	return math.floor(banked * Rules.earlyMultiplier(secondsLeft) + 0.5)
end

-- Walk speed. Pushing a trolley is slower the fuller it is; with the trolley
-- parked you move at HAND_SPEED. A sprint multiplies either. Off balance, you
-- can't sprint and move at a fraction of your speed.
function Rules.speedFor(trolleyCount, pushing, sprinting, stumbling)
	local speed
	if pushing then
		local fill = math.clamp(trolleyCount / Config.TROLLEY_CAPACITY, 0, 1)
		speed = Config.PUSH_EMPTY_SPEED + (Config.PUSH_FULL_SPEED - Config.PUSH_EMPTY_SPEED) * fill
	else
		speed = Config.HAND_SPEED
	end
	if stumbling then
		return speed * Config.STUMBLE_SPEED_FACTOR
	end
	if sprinting then
		speed *= Config.SPRINT_MULTIPLIER
	end
	return speed
end

-- The sprint meter (0..1) at time t, from the last snapshot. Shared by the
-- server, which enforces it, and the client, which draws it, so the two
-- can't disagree about the arithmetic.
function Rules.staminaAt(stamina, at, sprinting, regenAt, t)
	if sprinting then
		return math.max(0, stamina - (t - at) / Config.SPRINT_STAMINA_SECONDS)
	end
	local from = math.max(at, regenAt)
	if t <= from then
		return stamina
	end
	return math.min(1, stamina + (t - from) / Config.SPRINT_REFILL_SECONDS)
end

-- Whether the item at `index` (1 = the bottom, first in) of a trolley pile
-- of `count` can be reached from above: nothing lies on top of it. The pile
-- fills PILE_LAYER cells per layer, so the item PILE_LAYER further up the
-- pile sits right on top of this one.
function Rules.reachable(index, count)
	return index >= 1 and index <= count and index + Config.PILE_LAYER > count
end

-- Where item `index` lies in the pile: its layer (0 = the floor of the
-- basket) and its cell in that layer (0 .. PILE_LAYER - 1).
function Rules.pileCell(index)
	local n = index - 1
	return n // Config.PILE_LAYER, n % Config.PILE_LAYER
end

function Rules.tillsOpen(elapsed)
	return elapsed >= Config.TILLS_OPEN_AT
end

-- "early" (tills shut) | "shopping" | "closing" | "shutters" | "closed"
function Rules.stageAt(elapsed)
	if elapsed >= Config.ROUND_SECONDS then
		return "closed"
	elseif elapsed >= Config.SHUTTER_STARTS_AT then
		return "shutters"
	elseif elapsed >= Config.CLOSING_WARN_AT then
		return "closing"
	elseif not Rules.tillsOpen(elapsed) then
		return "early"
	end
	return "shopping"
end

-- ---------------- the match ----------------

-- How many Chonk eats after this round (1-based), given how many players
-- are still in. Spread evenly over the rounds left before the final, with
-- the remainder in the later rounds, so exactly FINALISTS reach the last.
function Rules.cutsThisRound(alive, matchRound)
	local roundsLeft = Config.MATCH_ROUNDS - matchRound
	if roundsLeft <= 0 then
		return 0
	end
	return math.max(0, alive - Config.FINALISTS) // roundsLeft
end

-- Best feeder first. Ties go to whoever checked out first; anyone who never
-- checked out (shut in) comes after everyone who did.
function Rules.rankRows(rows)
	table.sort(rows, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		local ta, tb = a.checkoutAt or math.huge, b.checkoutAt or math.huge
		if ta ~= tb then
			return ta < tb
		end
		return a.name < b.name
	end)
	return rows
end

-- Where the needle stops on Chonk's mood meter (0 = far end of angry,
-- 1 = far end of love): your score against the round's best. Nothing or
-- less than nothing sits at 0, and anyone being eaten always lands in angry.
function Rules.meterFor(score, best, eaten)
	local position = 0
	if score > 0 and best > 0 then
		position = math.clamp(score / best, 0, 1)
	end
	if eaten then
		position = math.min(position, Config.MOOD_ANGRY_TOP - 0.05)
	end
	return position
end

-- "angry" | "content" | "love"
function Rules.moodAt(position)
	if position < Config.MOOD_ANGRY_TOP then
		return "angry"
	elseif position < Config.MOOD_LOVE_FROM then
		return "content"
	end
	return "love"
end

-- One score formatter for the whole game: "12 yum", "-2 yum".
function Rules.formatYum(n)
	return ("%d yum"):format(math.floor(n + 0.5))
end

function Rules.formatClock(seconds)
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

return Rules
