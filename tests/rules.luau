-- Offline checks for Config and Rules. Run with: python tests/run.py
-- Asserts properties rather than counts, so adding an item doesn't turn it red.

local Config = require("../src/ReplicatedStorage/Shared/Config")
local Rules = require("../src/ReplicatedStorage/Shared/Rules")

local passed, failed = 0, 0
local function check(ok, message)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. message)
	end
end

local function randInt(lo, hi)
	return math.random(lo, hi)
end

-- ---------------- Config sanity ----------------
check(Config.CLOSING_WARN_AT < Config.SHUTTER_STARTS_AT, "closing warning comes before the shutters")
check(Config.SHUTTER_STARTS_AT < Config.ROUND_SECONDS, "shutters start before the store closes")
check(Config.PUSH_FULL_SPEED <= Config.PUSH_EMPTY_SPEED, "a full trolley is not faster than an empty one")
check(Config.HAND_SPEED > Config.PUSH_EMPTY_SPEED, "letting go of the trolley is faster than pushing it")
check(Config.HAND_SLOTS >= 1 and Config.HAND_SLOTS < Config.TROLLEY_CAPACITY, "hands carry less than a trolley")
check(Config.PUSH_HAND_SLOTS >= 1 and Config.PUSH_HAND_SLOTS < Config.HAND_SLOTS, "pushing takes a hand, but leaves one to throw with")
check(Config.SPRINT_MULTIPLIER > 1, "a sprint is faster")
check(Config.SPRINT_REFILL_SECONDS > Config.SPRINT_STAMINA_SECONDS, "the sprint meter refills slower than it drains")
check(Config.SPRINT_MIN_START > 0 and Config.SPRINT_MIN_START < 1, "a sprint needs some meter to start, not a full one")
check(Config.STUMBLE_SPEED_FACTOR > 0 and Config.STUMBLE_SPEED_FACTOR < 1, "off balance slows you without stopping you")
check(Config.HIT_IMMUNITY > Config.STUMBLE_SECONDS, "you can't be kept off balance back to back")
check(Config.THROW_COOLDOWN > 0, "throws have a cooldown")
check(Config.RAM_COOLDOWN > 0, "rams have a cooldown")
check(Config.RAM_MIN_SPEED < Config.PUSH_FULL_SPEED, "you can ram even with a full trolley")
check(Config.LIST_SIZE <= Config.LIST_POOL, "a list fits in the pool it is drawn from")
local staples = 0
for _, item in ipairs(Config.ITEMS) do
	if item.kind == "staple" then
		staples += 1
	end
end
check(Config.LIST_POOL <= staples, "the pool fits in the staples")
check(Config.CAMERA_DISTANCE >= 0.5 and Config.CAMERA_DISTANCE <= 400, "the camera distance is one Roblox allows")
check(Config.TILLS_OPEN_AT > 0 and Config.TILLS_OPEN_AT < Config.CLOSING_WARN_AT, "the tills open after the doors and before the closing warning")
check(Config.TILL_COUNT >= 1 and Config.TILL_COUNT <= 5, "the store has room for 1 to 5 tills")
check(Config.SHAKE_DROP_MIN >= 1 and Config.SHAKE_DROP_MIN <= Config.SHAKE_DROP_MAX, "a shake drops at least one item")
check(Config.SHAKE_MIN_SPEED > Config.PUSH_EMPTY_SPEED, "a plain push into a shelf doesn't shake it")
check(Config.SHAKE_MIN_SPEED < Config.PUSH_FULL_SPEED * Config.SPRINT_MULTIPLIER, "a sprint shakes a shelf even with a full trolley")
check(Config.SHAKE_COOLDOWN > Config.SHAKE_SECONDS, "a shelf stops wobbling before it can be shaken again")
check(Config.FLASH_SALE_AT > 0, "the flash sale starts after the doors open")
check(Config.FLASH_SALE_AT + Config.FLASH_SALE_SECONDS <= Config.ROUND_SECONDS, "the flash sale is over by closing")
check(Config.FLASH_SALE_AT >= Config.CLOSING_WARN_AT, "the flash sale is a lure back in after the closing warning")
check(Config.ITEM_BY_KEY[Config.FLASH_ITEM.key] == Config.FLASH_ITEM, "the flash item is indexed, so it can be carried and scanned")
local flashInItems = false
for _, item in ipairs(Config.ITEMS) do
	if item.key == Config.FLASH_ITEM.key then
		flashInItems = true
	end
end
check(not flashInItems, "the flash item is never stocked or dealt onto a list")
check(Rules.itemValue(Config.FLASH_ITEM.key, {}) == Config.FLASH_ITEM.yum, "the flash item is worth its yum to anybody")
for name, spec in pairs(Config.SOUNDS) do
	check(type(spec.id) == "string" and (spec.id == "" or spec.id:match("^rbxassetid://%d+$") ~= nil), "sound id is well formed: " .. name)
	check(type(spec.volume) == "number" and spec.volume > 0 and spec.volume <= 1, "sound volume is sane: " .. name)
end

local keys, totalStock = {}, 0
for _, item in ipairs(Config.ITEMS) do
	check(not keys[item.key], "item key is unique: " .. item.key)
	keys[item.key] = true
	check(item.kind == "staple" or item.kind == "snack" or item.kind == "yuck", item.key .. " has a known kind")
	check(type(item.yum) == "number" and item.yum ~= 0, item.key .. " has a yum")
	check((item.yum < 0) == (item.kind == "yuck"), item.key .. ": only yuck is worth less than nothing")
	if item.zone == "beside" then
		check(type(item.beside) == "table" and #item.beside > 0, item.key .. " says what it sits beside")
		for _, other in ipairs(item.beside or {}) do
			local next = Config.ITEM_BY_KEY[other]
			check(next ~= nil and next.zone ~= "beside" and next.kind ~= "yuck", item.key .. " sits beside real food: " .. tostring(other))
		end
	end
	check(item.stock > 0, item.key .. " has stock")
	check(item.zone == "produce" or item.zone == "aisle" or item.zone == "fridge" or item.zone == "beside", item.key .. " has a known zone")
	check(Config.ITEM_BY_KEY[item.key] == item, item.key .. " is indexed")
	totalStock += item.stock
end
check(totalStock >= Config.TROLLEY_CAPACITY * 2, "the shelves hold more than two full trolleys")

-- ---------------- dealing ----------------
for _ = 1, 200 do
	local pool = Rules.dealPool(randInt)
	check(#pool == Config.LIST_POOL, "pool has LIST_POOL kinds")
	local seen = {}
	for _, key in ipairs(pool) do
		check(Config.ITEM_BY_KEY[key] ~= nil, "pool key exists: " .. tostring(key))
		check(Config.ITEM_BY_KEY[key].kind == "staple", "only staples go on lists: " .. tostring(key))
		check(not seen[key], "pool has no repeats")
		seen[key] = true
	end
	local list = Rules.dealList(pool, randInt)
	check(#list == Config.LIST_SIZE, "list has LIST_SIZE kinds")
	local inList = {}
	for _, key in ipairs(list) do
		check(seen[key], "list is drawn from the pool")
		check(not inList[key], "list has no repeats")
		inList[key] = true
	end
end

-- ---------------- values and scoring ----------------
local cheap = Config.ITEMS[1]
local listSet = Rules.listSet({ cheap.key })
check(Rules.itemValue(cheap.key, listSet) == cheap.yum * Config.LIST_MULTIPLIER, "a list item is worth the multiplier")
check(Rules.itemValue(cheap.key, {}) == cheap.yum, "an off-list item is worth its yum")
check(Rules.itemValue("nope", {}) == 0, "an unknown item is worth nothing")
check(Rules.valueOf({ cheap.key, cheap.key }, {}) == cheap.yum * 2, "valueOf adds up")

-- the order a child has to learn: your list > snacks > other staples > toilet roll
local bestSnack, worstSnack, bestStaple, worstListed = -math.huge, math.huge, -math.huge, math.huge
for _, item in ipairs(Config.ITEMS) do
	if item.kind == "snack" then
		bestSnack = math.max(bestSnack, item.yum)
		worstSnack = math.min(worstSnack, item.yum)
	elseif item.kind == "staple" then
		bestStaple = math.max(bestStaple, item.yum)
		worstListed = math.min(worstListed, Rules.itemValue(item.key, Rules.listSet({ item.key })))
	else
		check(item.yum < 0, "a prank counts against you")
	end
end
check(worstSnack > bestStaple, "any snack beats any staple off your list")
check(worstListed > bestSnack, "anything on your list beats any snack")

check(Rules.finalScore(-4, 60) == -4, "the early bonus never makes a bad bag worse")
check(Rules.finalScore(0, 60) == 0, "nothing scanned, nothing earned")

check(Rules.finalScore(100, nil) == 100, "not finishing gets no bonus")
check(Rules.finalScore(100, 0) == 100, "finishing at the bell gets no bonus")
check(Rules.finalScore(100, 60) == math.floor(100 * (1 + 60 * Config.EARLY_BONUS_PER_SECOND) + 0.5), "60 s early gets the per-second bonus")
check(Rules.finalScore(100, 30) > Rules.finalScore(100, 10), "earlier is worth more")

check(Rules.speedFor(0, true, false) == Config.PUSH_EMPTY_SPEED, "an empty trolley pushes at PUSH_EMPTY_SPEED")
check(math.abs(Rules.speedFor(Config.TROLLEY_CAPACITY, true, false) - Config.PUSH_FULL_SPEED) < 1e-9, "a full trolley pushes at PUSH_FULL_SPEED")
check(Rules.speedFor(Config.TROLLEY_CAPACITY * 2, true, false) == Rules.speedFor(Config.TROLLEY_CAPACITY, true, false), "speed is clamped past capacity")
check(Rules.speedFor(Config.TROLLEY_CAPACITY, false, false) == Config.HAND_SPEED, "a parked trolley's load doesn't slow you")
check(math.abs(Rules.speedFor(0, false, true) - Config.HAND_SPEED * Config.SPRINT_MULTIPLIER) < 1e-9, "sprint multiplies hand speed")
check(Rules.speedFor(Config.TROLLEY_CAPACITY, true, true) < Rules.speedFor(0, false, true), "a sprint with a full trolley is slower than one with empty hands")

check(Rules.speedFor(0, false, true, true) == Config.HAND_SPEED * Config.STUMBLE_SPEED_FACTOR, "off balance cancels the sprint and slows you")

-- ---------------- sprint meter ----------------
local S, R, D = Config.SPRINT_STAMINA_SECONDS, Config.SPRINT_REFILL_SECONDS, Config.SPRINT_REFILL_DELAY
check(Rules.staminaAt(1, 0, true, 0, 0) == 1, "meter starts full")
check(math.abs(Rules.staminaAt(1, 0, true, 0, S / 2) - 0.5) < 1e-9, "holding drains it")
check(Rules.staminaAt(1, 0, true, 0, S * 2) == 0, "it never goes below empty")
check(Rules.staminaAt(0.2, 10, false, 10 + D, 10 + D / 2) == 0.2, "no refill during the delay")
check(math.abs(Rules.staminaAt(0, 10, false, 10, 10 + R / 2) - 0.5) < 1e-9, "letting go refills it")
check(Rules.staminaAt(0.9, 0, false, 0, R * 2) == 1, "it never goes above full")
-- short bursts: tap-hold-release-hold spends it gradually, not all at once
local m = Rules.staminaAt(1, 0, true, 0, 0.5)
check(m > 0.8 and m < 0.9, "half a second of sprint spends only part of the meter")

-- ---------------- the trolley pile ----------------
check(Config.PILE_LAYER >= 1 and Config.PILE_LAYER < Config.TROLLEY_CAPACITY, "a full trolley is more than one layer deep, so things get buried")
check(Rules.reachable(1, 1), "a lone item is on top")
check(Rules.reachable(5, 5) and Rules.reachable(1, 5), "one layer: everything is reachable")
check(not Rules.reachable(1, Config.PILE_LAYER + 1), "the first item is buried once something lies on it")
check(Rules.reachable(2, Config.PILE_LAYER + 1), "an item with nothing on top is reachable")
check(Rules.reachable(Config.TROLLEY_CAPACITY, Config.TROLLEY_CAPACITY), "the last one in is always on top")
check(not Rules.reachable(0, 3) and not Rules.reachable(4, 3), "out of range is never reachable")
do
	local layer, cell = Rules.pileCell(Config.PILE_LAYER + 1)
	check(layer == 1 and cell == 0, "the item after a full layer starts the next layer")
	local below = { Rules.pileCell(1) }
	check(below[1] == 0 and below[2] == 0, "the first item is at the bottom")
end
local yuckKey
for _, item in ipairs(Config.ITEMS) do
	if item.kind == "yuck" then
		yuckKey = item.key
	end
end
check(yuckKey ~= nil, "there is yuck to dig out")

-- ---------------- Chonk's menu ----------------
local staple, snack, yuck
for _, item in ipairs(Config.ITEMS) do
	if item.kind == "staple" and not staple then
		staple = item
	elseif item.kind == "snack" and not snack then
		snack = item
	elseif item.kind == "yuck" and not yuck then
		yuck = item
	end
end
local onList = Rules.listSet({ staple.key })
check(Rules.itemValue(snack.key, {}, { craving = snack.key }) == snack.yum * Config.CRAVING_MULTIPLIER, "the craved food is worth the craving multiplier")
check(Rules.itemValue(staple.key, onList, { craving = staple.key }) == staple.yum * math.max(Config.LIST_MULTIPLIER, Config.CRAVING_MULTIPLIER), "list and craving don't stack")
check(Rules.itemValue(snack.key, {}, { notToday = snack.key }) == Config.NOT_TODAY_YUM, "the not-today food is worth NOT_TODAY_YUM")
check(Config.NOT_TODAY_YUM < 0 and Config.NOT_TODAY_YUM > yuck.yum, "the not-today food counts against you, but less than yuck")
check(Rules.itemValue(yuck.key, {}, { craving = yuck.key }) == yuck.yum, "yuck is never multiplied")
check(Rules.itemValue(staple.key, onList, nil) == staple.yum * Config.LIST_MULTIPLIER, "no menu is a plain round")
for _ = 1, 200 do
	local notToday = Rules.pickNotToday(randInt)
	local item = Config.ITEM_BY_KEY[notToday]
	check(item.kind == "staple" or item.kind == "snack", "he's only tired of food he likes")
	local craving = Rules.pickCraving(randInt, notToday)
	check(craving ~= notToday, "he never craves the food he's tired of")
	check(Config.ITEM_BY_KEY[craving].kind ~= "yuck", "he never craves yuck")
	local pool = Rules.dealPool(randInt, notToday)
	for _, key in ipairs(pool) do
		check(key ~= notToday, "the not-today food is on nobody's list")
	end
	check(#pool >= Config.LIST_SIZE, "a pool without the not-today food still fills a list")
end
check(Config.TANTRUM_AT >= Config.CLOSING_WARN_AT and Config.TANTRUM_AT < Config.SHUTTER_STARTS_AT, "Chonk's tantrum comes between the closing warning and the shutters")
check(Config.CRAVING_AT > 0 and Config.CRAVING_AT < Config.TILLS_OPEN_AT, "the craving comes before the tills open, so the moments don't collide")

-- ---------------- the match ----------------
local function cutsFor(players)
	local alive, cuts = players, {}
	for r = 1, Config.MATCH_ROUNDS do
		local cut = Rules.cutsThisRound(alive, r)
		table.insert(cuts, cut)
		alive -= cut
	end
	return cuts, alive
end
local function same(a, b)
	for i = 1, math.max(#a, #b) do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end
-- the build sheet's table
check(same(cutsFor(12), { 2, 2, 2, 3, 0 }), "12 players: 2, 2, 2, 3")
check(same(cutsFor(10), { 1, 2, 2, 2, 0 }), "10 players: 1, 2, 2, 2")
check(same(cutsFor(8), { 1, 1, 1, 2, 0 }), "8 players: 1, 1, 1, 2")
check(same(cutsFor(6), { 0, 1, 1, 1, 0 }), "6 players: 0, 1, 1, 1")
check(same(cutsFor(4), { 0, 0, 0, 1, 0 }), "4 players: 0, 0, 0, 1")
for players = 1, 3 do
	check(same(cutsFor(players), { 0, 0, 0, 0, 0 }), players .. " players: nobody is eaten")
end
for players = 3, 20 do
	local _, final = cutsFor(players)
	check(final == Config.FINALISTS, players .. " players: exactly FINALISTS reach the final")
end
-- someone leaving mid-match still ends with FINALISTS
do
	local alive = 9
	for r = 1, Config.MATCH_ROUNDS do
		if r == 3 then
			alive -= 2
		end
		alive -= Rules.cutsThisRound(alive, r)
	end
	check(alive == Config.FINALISTS, "leavers don't break the final")
end

local ranked = Rules.rankRows({
	{ name = "Late", score = 10, checkoutAt = 110 },
	{ name = "Early", score = 10, checkoutAt = 70 },
	{ name = "ShutIn", score = 10, checkoutAt = nil },
	{ name = "Best", score = 30, checkoutAt = 100 },
})
check(ranked[1].name == "Best", "best score first")
check(ranked[2].name == "Early" and ranked[3].name == "Late", "ties go to whoever checked out first")
check(ranked[4].name == "ShutIn", "shut in loses a tie to anyone who got out")

check(Rules.meterFor(30, 30, false) == 1, "the best feeder fills the meter")
check(Rules.meterFor(0, 30, false) == 0, "nothing sits at the far end of angry")
check(Rules.meterFor(-4, 30, false) == 0, "less than nothing sits at the far end of angry")
check(Rules.moodAt(Rules.meterFor(29, 30, true)) == "angry", "anyone eaten lands in angry")
check(Rules.moodAt(Rules.meterFor(15, 30, false)) == "content", "half the best is content")
check(Rules.moodAt(1) == "love" and Rules.moodAt(0) == "angry", "the meter's ends")
check(Rules.meterFor(5, 0, false) == 0, "a round where nobody fed him leaves everyone angry")

-- ---------------- clock ----------------
check(Rules.stageAt(0) == "early", "doors open: the tills are shut")
check(not Rules.tillsOpen(Config.TILLS_OPEN_AT - 0.1), "tills shut just before TILLS_OPEN_AT")
check(Rules.tillsOpen(Config.TILLS_OPEN_AT), "tills open at TILLS_OPEN_AT")
check(Rules.stageAt(Config.TILLS_OPEN_AT) == "shopping", "shopping with the tills open")
check(Rules.stageAt(Config.CLOSING_WARN_AT) == "closing", "closing at CLOSING_WARN_AT")
check(Rules.stageAt(Config.SHUTTER_STARTS_AT) == "shutters", "shutters at SHUTTER_STARTS_AT")
check(Rules.stageAt(Config.ROUND_SECONDS) == "closed", "closed at ROUND_SECONDS")

check(Rules.formatClock(0) == "0:00", "clock 0:00")
check(Rules.formatClock(59.2) == "1:00", "clock rounds up")
check(Rules.formatClock(180) == "3:00", "clock 3:00")
check(Rules.formatYum(5) == "5 yum", "yum")
check(Rules.formatYum(-2) == "-2 yum", "negative yum")

print(("rules: %d passed, %d failed"):format(passed, failed))
if failed > 0 then
	error("rules suite failed")
end
