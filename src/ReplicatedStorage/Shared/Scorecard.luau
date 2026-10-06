-- The playtest scorecard (docs/MASTER-PLAN.md), worked out from a round's
-- results so the M7 playtest is read off the server log instead of counted
-- by hand. Round prints these as "[Scorecard]" lines after every feeding.
--
-- Pure functions over the rows Shoppers.results() returns, so the offline
-- tests can run it. The targets are the scorecard's; when a playtest moves
-- one, move it here and in the plan.

local Config = if typeof(script) == "Instance" then require(script.Parent.Config) else require("./Config")

local Scorecard = {}

-- Each measure: a target range (min and/or max), and what to try when it's off.
Scorecard.TARGETS = {
	shutIn = { min = 10, max = 30, low = "start the shutters earlier or slow scanning", high = "give more warning" },
	rams = { min = 2, max = 6, low = "smaller store, more list overlap", high = "longer RAM_COOLDOWN" },
	steals = { min = 1, max = 6, low = "trolleys need leaving alone more (faster HAND_SPEED)", high = "longer STEAL_HOLD" },
	throws = { min = 3, max = 8, low = "longer range or shorter THROW_COOLDOWN", high = "longer THROW_COOLDOWN" },
	mostHits = { max = 3, high = "one player is being picked on: lengthen HIT_IMMUNITY" },
	queue = { min = 2, low = "no queue at closing: remove a till" },
	late = { min = 50, low = "everyone leaves early: lower the early bonus" },
	gap = { max = 3, high = "the winner is snowballing: cap the trolley or add items" },
	yuck = { min = 1, max = 6, low = "sabotage is too hard: more yuck stock, easier throws in", high = "yuck is hard to spot in your own trolley" },
	dig = { min = 2, max = 20, low = "nobody needs to dig: more junk landing in trolleys (SCRAPE_CHANCE, FALL_CATCH_RADIUS)", high = "digging eats the round: less junk (SCRAPE_CHANCE)" },
}

local function verdict(target, value)
	if value == nil then
		return "--", nil
	end
	if target.min and value < target.min then
		return "LOW", target.low
	end
	if target.max and value > target.max then
		return "HIGH", target.high
	end
	return "OK", nil
end

local function range(target, unit)
	unit = unit or ""
	if target.min and target.max then
		return ("%s to %s%s"):format(target.min, target.max, unit)
	elseif target.min then
		return ("%s%s or more"):format(target.min, unit)
	end
	return ("%s%s or less"):format(target.max, unit)
end

local function sum(rows, field)
	local total = 0
	for _, row in ipairs(rows) do
		total += row[field] or 0
	end
	return total
end

-- The measures for one round. `rows` are ranked (best first); `extra` holds
-- what the rows can't: { maxQueue = players waiting in the till lanes at
-- the busiest moment of closing }.
function Scorecard.round(rows, extra)
	local n = #rows
	if n == 0 then
		return {}
	end
	extra = extra or {}
	local T = Scorecard.TARGETS
	local measures = {}
	local function add(label, key, value, shown, unit)
		local word, fix = verdict(T[key], value)
		table.insert(measures, {
			key = key,
			label = label,
			value = value,
			shown = shown or (if value then ("%.1f"):format(value) else "n/a"),
			target = range(T[key], unit),
			verdict = word,
			fix = fix,
		})
	end

	local caught = 0
	local mostHits = 0
	for _, row in ipairs(rows) do
		if row.caught then
			caught += 1
		end
		mostHits = math.max(mostHits, row.hitsTaken or 0)
	end
	add("players shut in", "shutIn", caught / n * 100, ("%d%% (%d of %d)"):format(math.floor(caught / n * 100 + 0.5), caught, n), "%")
	add("rams per player", "rams", sum(rows, "rams") / n)
	add("steals this round", "steals", sum(rows, "steals"), tostring(sum(rows, "steals")))
	add("throws per player", "throws", sum(rows, "throws") / n)
	add("most hits on one player", "mostHits", mostHits, tostring(mostHits))
	add("queue at closing", "queue", extra.maxQueue, if extra.maxQueue then ("%d waiting"):format(extra.maxQueue) else nil)

	local out, late = 0, 0
	for _, row in ipairs(rows) do
		if row.checkoutAt then
			out += 1
			if row.checkoutAt >= Config.ROUND_SECONDS - 20 then
				late += 1
			end
		end
	end
	if out > 0 then
		add("checkouts in the last 20 s", "late", late / out * 100, ("%d%% (%d of %d out)"):format(math.floor(late / out * 100 + 0.5), late, out), "%")
	else
		add("checkouts in the last 20 s", "late", nil, "nobody got out", "%")
	end

	local best, worst = rows[1].score, rows[n].score
	if n < 2 or best <= 0 then
		add("score gap, 1st to last", "gap", nil, "n/a", "x")
	elseif worst <= 0 then
		add("score gap, 1st to last", "gap", math.huge, ("%d to %d (last fed nothing)"):format(best, worst), "x")
	else
		add("score gap, 1st to last", "gap", best / worst, ("%.1fx"):format(best / worst), "x")
	end

	local dig = sum(rows, "digSeconds") / n
	add("digging per player", "dig", dig, ("%.1f s"):format(dig), " s")

	local yuck = sum(rows, "yuckScanned")
	local sabotage = sum(rows, "sabotages") + sum(rows, "plants")
	add("yuck fed to Chonk", "yuck", yuck, ("%d (%d sabotage throws/plants)"):format(yuck, sabotage))
	return measures
end

-- The measures as log lines.
function Scorecard.lines(measures, playerCount)
	local lines = {}
	for _, m in ipairs(measures) do
		local line = ("  %-4s %-28s %-30s target %s"):format(m.verdict, m.label, m.shown, m.target)
		if m.fix then
			line ..= "  -> " .. m.fix
		end
		table.insert(lines, line)
	end
	if playerCount and playerCount < 4 then
		table.insert(lines, ("  (only %d players: the targets are for a full server, read with care)"):format(playerCount))
	end
	return lines
end

return Scorecard
