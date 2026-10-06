-- Offline checks for the playtest scorecard. Run with: python tests/run.py

local Config = require("../src/ReplicatedStorage/Shared/Config")
local Scorecard = require("../src/ReplicatedStorage/Shared/Scorecard")

local passed, failed = 0, 0
local function check(ok, message)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. message)
	end
end

local function byKey(measures)
	local map = {}
	for _, m in ipairs(measures) do
		map[m.key] = m
	end
	return map
end

check(#Scorecard.round({}, {}) == 0, "no players, no scorecard")

-- a lively 8-player round that hits every target
local rows = {}
for i = 1, 8 do
	table.insert(rows, {
		name = "P" .. i,
		score = 40 - i * 2, -- 38 down to 24: a gap of about 1.6x
		caught = i == 8, -- 1 of 8 shut in: 12.5%
		checkoutAt = if i == 8 then nil elseif i <= 5 then Config.ROUND_SECONDS - 5 else 90,
		rams = 3,
		steals = if i <= 2 then 1 else 0,
		throws = 4,
		hitsTaken = 2,
		yuckScanned = if i == 1 then 2 else 0,
		sabotages = 1,
		plants = 0,
		digSeconds = 6,
	})
end
local good = byKey(Scorecard.round(rows, { maxQueue = 3 }))
for key, m in pairs(good) do
	check(m.verdict == "OK", ("a good round reads OK on %s (got %s %s)"):format(key, m.verdict, m.shown))
end

-- now break each one
rows[1].hitsTaken = 6
rows[1].score = 200
for _, row in ipairs(rows) do
	row.caught = true
	row.checkoutAt = nil
	row.rams = 0
end
local bad = byKey(Scorecard.round(rows, { maxQueue = 0 }))
check(bad.shutIn.verdict == "HIGH", "everyone shut in is too harsh")
check(bad.rams.verdict == "LOW", "no rams is too few")
check(bad.mostHits.verdict == "HIGH" and bad.mostHits.fix ~= nil, "one player picked on is flagged, with the fix")
check(bad.queue.verdict == "LOW", "no queue is flagged")
check(bad.late.verdict == "--", "nobody out: the late-checkout share can't be read")
check(bad.gap.verdict == "HIGH", "a snowballing winner is flagged")
for _, row in ipairs(rows) do
	row.digSeconds = 0
end
check(byKey(Scorecard.round(rows, {})).dig.verdict == "LOW", "nobody digging is flagged")

-- someone fed him nothing: the gap is infinite, not a crash
rows[8].score = 0
local zero = byKey(Scorecard.round(rows, {}))
check(zero.gap.verdict == "HIGH", "last place fed nothing: the gap reads HIGH")
check(zero.queue.verdict == "--", "no queue measured reads as unknown")

local lines = Scorecard.lines(Scorecard.round(rows, { maxQueue = 1 }), 2)
check(#lines > 0 and lines[#lines]:find("only 2 players") ~= nil, "a small round says to read it with care")

print(("scorecard: %d passed, %d failed"):format(passed, failed))
if failed > 0 then
	error("scorecard suite failed")
end
