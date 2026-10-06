-- Every tunable number in Supermarket Sweep, in one place.
--
-- Config requires NOTHING, so the server, the client and the offline tests
-- (tests/run.py) can all load it. Keep Roblox types (Color3, Vector3, Enum)
-- out of this file: colours are {r, g, b} and the builders convert them.
-- Store geometry lives in Services/Store.luau, because it is layout rather
-- than tuning.

local Config = {}

Config.VERSION = "mvp-m6-greybox"

-- ============================================================
-- ROUND CLOCK. Every "AT" is seconds after the doors open.
-- ============================================================
Config.LOBBY_SECONDS = 20
-- Two minutes (was three). Three dragged in a solo test with six items on the
-- list; with a full server the shelves also empty much faster, so a round
-- fills itself. Shorten the time rather than grow the store: a bigger store
-- only adds running.
Config.ROUND_SECONDS = 120
Config.CLOSING_WARN_AT = 80 -- "store closes in 40 s" announcements start
Config.SHUTTER_STARTS_AT = 100 -- shutters start coming down; fully shut at ROUND_SECONDS
-- The tills stay shut for the first half of the round (designer, 2026-10-05),
-- so nobody grabs two things and leaves: everyone shops, and everyone heads
-- for the same three tills in the second half.
Config.TILLS_OPEN_AT = Config.ROUND_SECONDS / 2
Config.FINAL_COUNTDOWN = 10 -- the clock turns red and pulses for the last N seconds
Config.MIN_PLAYERS = 2 -- the admin "Start now" button ignores this

-- ============================================================
-- THE MATCH. Five rounds; rounds 1 to 4 each feed Big Chonk the worst
-- feeders, so exactly FINALISTS reach the last round. Round r cuts
-- (alive - FINALISTS) // (MATCH_ROUNDS - r): with 12 players 2, 2, 2, 3;
-- with 8 players 1, 1, 1, 2; with 3 or fewer nobody. Worked out from who is
-- still here each round, so a player leaving mid-match can't break it.
-- ============================================================
Config.MATCH_ROUNDS = 5
Config.FINALISTS = 3
Config.BETWEEN_ROUNDS_SECONDS = 10 -- the countdown before rounds 2 to 5
Config.PODIUM_SECONDS = 14

-- ============================================================
-- BIG CHONK (grey box: a placeholder giant outside the front window). He
-- shouts by name, wants one food extra from CRAVING_AT, is tired of one food
-- each round, and bangs on the glass once the shutters start.
-- ============================================================
Config.CRAVING_AT = 40 -- before the tills open at 1:00, so the two moments don't collide
Config.CRAVING_MULTIPLIER = 3 -- the craved food is worth this many times its yum, to everyone
Config.NOT_TODAY_YUM = -1 -- the food he's not in the mood for this round: a small minus (designer, 2026-10-05), less than yuck
Config.CHONK_NAG_EVERY = 11 -- seconds between his shouts at a player by name
Config.CHONK_REACT_GAP = 6 -- seconds between his reactions to rams and yuck grabs
Config.CHONK_BANG_EVERY = 2.5 -- seconds between bangs on the glass, during the shutters
-- His tantrum: just after the closing warning (long enough for its
-- announcement to be read) he slams the building and every shelf section
-- drops an item, into the aisles and into any trolley nearby.
Config.TANTRUM_AT = Config.CLOSING_WARN_AT + 4

-- ============================================================
-- THE FEEDING, after every round: everyone lines up in front of Chonk and
-- is revealed on his mood meter, best feeder first, so the players in
-- danger come last. Then he eats the worst feeders (a cartoon gulp: they go
-- to the stands until the next match).
-- ============================================================
Config.FEED_INTRO_SECONDS = 2
Config.FEED_SAFE_SECONDS = 1.5 -- each safe player's reveal
Config.FEED_DANGER_SECONDS = 3.5 -- each player in danger: the needle wobbles at the edge of angry
Config.FEED_EATEN_SECONDS = 4 -- the gulp, after the last reveal
Config.FEED_OUTRO_SECONDS = 3
Config.MOOD_ANGRY_TOP = 1 / 3 -- the meter's zones: angry below this, love above MOOD_LOVE_FROM
Config.MOOD_LOVE_FROM = 2 / 3

-- ============================================================
-- CAMERA. Locked at one third-person distance (designer, 2026-10-05): no
-- zooming out to scout the store from above, and no scrolling into first
-- person. Close enough to judge your trolley's nose for a ram, far enough to
-- see the aisle ahead and yourself get knocked over. Main applies it to
-- every player.
-- ============================================================
Config.CAMERA_DISTANCE = 16

-- ============================================================
-- SHOPPING LISTS
-- ============================================================
Config.LIST_SIZE = 6 -- item kinds on each player's list
-- Lists hold only STAPLES (see ITEMS). Each round, lists are drawn from only
-- this many staple kinds, so lists overlap and players fight over the same
-- shelves. Raise it to spread players out; lower it for more contention.
Config.LIST_POOL = 7
Config.LIST_MULTIPLIER = 2 -- an item whose kind is on your list is worth this many times its yum

-- ============================================================
-- CARRYING
-- Everyone starts the round pushing a trolley. Let go of it (Q) to run
-- faster with only your hands free; it stays parked where you left it.
-- The till scans your hands, and your trolley only if you're pushing it.
-- ============================================================
Config.TROLLEY_CAPACITY = 20
-- A trolley is a PILE, not a list (designer, 2026-10-05). Items lie in layers
-- of PILE_LAYER (3 x 4 in the basket); an item is buried while there's one
-- PILE_LAYER further up the pile on top of it. Nobody sees a list of what's
-- in their trolley: they look at it, or dig (R) for a top-down view and pull
-- out what's on top. A throw with empty hands throws the top of the pile.
Config.PILE_LAYER = 12
Config.HAND_SLOTS = 2 -- one in each hand, with the trolley parked
-- Pushing takes one hand (designer, 2026-10-05): you can hold this many
-- while you push, which is your throw. Taking the trolley back with more
-- in hand puts the older ones in the basket and keeps the newest.
Config.PUSH_HAND_SLOTS = 1
Config.LOBBY_SPEED = 16
Config.PUSH_EMPTY_SPEED = 16 -- pushing an empty trolley
Config.PUSH_FULL_SPEED = 12 -- pushing a full one; linear in between
Config.HAND_SPEED = 20 -- trolley parked: faster, but only HAND_SLOTS items
Config.GRAB_RANGE = 8 -- studs from the item (the prompt's reach)
Config.TROLLEY_REACH = 9 -- how close you must be to take your trolley back

-- ============================================================
-- SPRINT: hold Shift (or the SPRINT button). Holding drains a meter and
-- letting go refills it, so a sprint can be spent in short bursts.
-- It multiplies whatever speed you have, so a sprint while pushing a full
-- trolley is still slower than a sprint with empty hands.
-- ============================================================
Config.SPRINT_MULTIPLIER = 1.5
Config.SPRINT_STAMINA_SECONDS = 3 -- a full meter lasts this long held down
Config.SPRINT_REFILL_SECONDS = 6 -- empty to full
Config.SPRINT_REFILL_DELAY = 0.8 -- after letting go, before it starts refilling
Config.SPRINT_EXHAUSTED_DELAY = 2 -- after running it dry
Config.SPRINT_MIN_START = 0.15 -- the meter needed to start a sprint (stops flicker)

-- ============================================================
-- FIGHTS. Ramming takes an item, stealing takes an item, throwing costs you
-- an item and slows someone down. Nobody standing on a till pad can be
-- rammed or hit, so a queue can't be wrecked at closing.
-- ============================================================
Config.RAM_MIN_SPEED = 10 -- studs/s you must be moving to ram
Config.RAM_REACH = 3.2 -- your trolley's nose to the centre of theirs
Config.RAM_REACH_PERSON = 2.4 -- your trolley's nose to a shopper on foot
Config.RAM_COOLDOWN = 3 -- seconds before the same shopper can lose another item to a ram
Config.STEAL_HOLD = 0.5 -- hold E on a parked trolley to take its top item
Config.STEAL_REACH = 8
-- A throw is a real arc: it flies where you aim (the mouse, or the middle of
-- the screen on a phone) and hits whoever it passes close to. The item you
-- hold in a hand goes first; otherwise your cheapest item in the trolley.
Config.THROW_SPEED = 75 -- studs/s at launch
Config.THROW_GRAVITY = 40 -- studs/s^2 pulling it down (much less than the world's, so it carries)
Config.THROW_HIT_RADIUS = 2.6 -- how close the item has to pass to a shopper's body
Config.THROW_MAX_SECONDS = 2 -- flight time before it just drops
Config.THROW_PITCH_MIN = -25 -- degrees: how far down you can aim
Config.THROW_PITCH_MAX = 35 -- degrees: how far up
-- Aim assist: a shopper within this many degrees of your aim (and in range,
-- with no shelf in between) gets the throw steered at them, with a lead for
-- where they're running. Aiming a moving target on a phone is hard.
Config.THROW_ASSIST_CONE = 12
Config.THROW_RANGE = 40 -- aim assist reach
Config.THROW_COOLDOWN = 2
Config.STUMBLE_SECONDS = 1.5 -- off balance after a hit: slowed, no grabbing, no sprint
Config.STUMBLE_SPEED_FACTOR = 0.4
Config.HIT_IMMUNITY = 5 -- after a stumble ends, nobody can knock you over again for this long

-- ============================================================
-- SHAKING SHELVES. Run your trolley into a shelf face (or a fridge, or the
-- fruit table) at ramming speed and 1 to 3 of the items still on it fall
-- into the aisle, for anybody to grab. Only real stock falls, and each
-- section can only be shaken once every SHAKE_COOLDOWN seconds.
-- ============================================================
-- Faster than any plain push (PUSH_EMPTY_SPEED), so only a SPRINT into a
-- shelf shakes it. Without that, driving up to a shelf to grab something
-- would knock its stock onto the floor every time.
Config.SHAKE_MIN_SPEED = 17
Config.SHAKE_DROP_MIN = 1
Config.SHAKE_DROP_MAX = 3
Config.SHAKE_COOLDOWN = 6
Config.SHAKE_SECONDS = 0.5 -- how long the shelf wobbles on screen

-- ============================================================
-- FLASH SALE. Once a round a single golden turkey appears at the right-hand
-- end of the cross aisle. It's on nobody's list and worth its yum to
-- whoever gets it out through a till. Gone if nobody grabs it in time.
-- It runs over the last 30 s of shopping (designer, 2026-10-05), after the
-- closing warning and through the shutters: a $300 lure back into a store
-- that is about to shut, so grabbing it is the gamble the round is about.
-- A turkey grabbed late still has to scan before closing like anything else.
-- ============================================================
Config.FLASH_SALE_SECONDS = 30
Config.FLASH_SALE_AT = Config.ROUND_SECONDS - Config.FLASH_SALE_SECONDS
Config.FLASH_ITEM = {
	key = "turkey",
	name = "Golden Turkey",
	kind = "special",
	yum = 10,
	stock = 0, -- never on the shelves; the sale puts out exactly one
	zone = "sale",
	shape = "block",
	size = { 1.8, 1.2, 1.4 },
	color = { 255, 196, 48 },
	flash = true, -- sparkles and a glow wherever it lies
}

-- ============================================================
-- CHECKOUT
-- ============================================================
Config.TILL_COUNT = 3 -- Store lays out this many lanes (fits up to 5)
Config.SCAN_SECONDS = 0.4 -- per item: a full trolley takes 8 s at the till
-- checking out with 60 s left = +60%; the tills open at TILLS_OPEN_AT, so
-- that is also the most anyone can get. Only a score above zero earns it.
Config.EARLY_BONUS_PER_SECOND = 0.01

-- ============================================================
-- ITEMS. Scores are YUM: how much Big Chonk likes what you bring him.
-- kind: staple | snack | yuck (the flash item is "special")
--   staple: the food he NEEDS. The only kind dealt onto lists, where it
--           counts LIST_MULTIPLIER times. Off your list, the least yum.
--   snack:  the food he LOVES. Never on a list, always worth a lot.
--   yuck:   what he HATES, always the same few. Negative yum: a till scans
--           it against you, so it's ammunition (a throw uses your least-yum
--           item first; a throw into a trolley lands in it; you can plant it
--           in a parked trolley). Toilet roll also unrolls a paper streamer.
-- So, per item: on your list (4) > snack (3) > any other staple (2) > yuck (-2).
-- zone: where the store puts it (produce island, aisle shelves, back fridges),
--       or "beside": in spare slots of the kinds named in `beside`, so yuck
--       sits right next to food players want
-- stock: how many go on the shelves each round. Shelves never restock.
-- shape: block | ball | cylinder (stood upright) | wedge
-- size: studs {x, y, z}; a cylinder's FIRST number is its length (its height
--       once stood up), because a Roblox cylinder's axis is X.
-- ============================================================
Config.ITEMS = {
	{ key = "bananas", name = "Bananas", kind = "staple", yum = 2, stock = 6, zone = "produce", shape = "block", size = { 1.6, 0.7, 1.0 }, color = { 250, 214, 60 } },
	{ key = "apples", name = "Apples", kind = "staple", yum = 2, stock = 6, zone = "produce", shape = "ball", size = { 1.1, 1.1, 1.1 }, color = { 214, 52, 52 } },
	{ key = "bread", name = "Bread", kind = "staple", yum = 2, stock = 6, zone = "aisle", shape = "block", size = { 1.6, 1.0, 1.0 }, color = { 205, 150, 90 } },
	{ key = "crisps", name = "Crisps", kind = "snack", yum = 3, stock = 6, zone = "aisle", shape = "block", size = { 1.2, 1.5, 0.5 }, color = { 245, 140, 40 } },
	{ key = "cereal", name = "Cereal", kind = "staple", yum = 2, stock = 5, zone = "aisle", shape = "block", size = { 1.2, 1.8, 0.5 }, color = { 70, 130, 220 } },
	{ key = "cookies", name = "Cookies", kind = "snack", yum = 3, stock = 5, zone = "aisle", shape = "block", size = { 1.4, 0.6, 1.0 }, color = { 130, 80, 45 } },
	{ key = "soda", name = "Soda", kind = "snack", yum = 3, stock = 5, zone = "aisle", shape = "cylinder", size = { 1.6, 0.8, 0.8 }, color = { 200, 30, 60 } },
	{ key = "toiletroll", name = "Toilet Roll", kind = "yuck", yum = -2, stock = 6, zone = "aisle", shape = "cylinder", size = { 1.2, 1.1, 1.1 }, color = { 245, 245, 245 }, streamer = true },
	{ key = "milk", name = "Milk", kind = "staple", yum = 2, stock = 4, zone = "fridge", shape = "block", size = { 0.9, 1.6, 0.9 }, color = { 235, 240, 250 } },
	{ key = "cheese", name = "Cheese", kind = "staple", yum = 2, stock = 4, zone = "fridge", shape = "wedge", size = { 1.0, 0.8, 1.4 }, color = { 255, 200, 40 } },
	{ key = "eggs", name = "Eggs", kind = "staple", yum = 2, stock = 4, zone = "fridge", shape = "block", size = { 1.4, 0.6, 0.8 }, color = { 225, 200, 160 } },
	{ key = "steak", name = "Steak", kind = "staple", yum = 2, stock = 4, zone = "fridge", shape = "block", size = { 1.4, 0.4, 1.0 }, color = { 170, 40, 40 } },
	{ key = "sprouts", name = "Brussels Sprouts", kind = "yuck", yum = -2, stock = 6, zone = "beside", beside = { "bananas", "apples" }, shape = "ball", size = { 0.8, 0.8, 0.8 }, color = { 110, 160, 60 } },
	{ key = "peas", name = "Canned Peas", kind = "yuck", yum = -2, stock = 6, zone = "beside", beside = { "crisps", "cookies" }, shape = "cylinder", size = { 1.1, 0.8, 0.8 }, color = { 120, 150, 90 } },
	{ key = "spinach", name = "Spinach", kind = "yuck", yum = -2, stock = 5, zone = "beside", beside = { "steak", "cheese" }, shape = "block", size = { 1.3, 0.5, 1.0 }, color = { 40, 100, 50 } },
}

Config.ITEM_BY_KEY = {}
for _, item in ipairs(Config.ITEMS) do
	Config.ITEM_BY_KEY[item.key] = item
end
-- indexed so it can be carried, scanned, thrown and drawn, but kept out of
-- ITEMS so it is never dealt onto a list or stocked
Config.ITEM_BY_KEY[Config.FLASH_ITEM.key] = Config.FLASH_ITEM

-- A thrown toilet roll leaves a paper streamer along its flight; when it
-- lands, the streamer drops onto whatever is under it (shelf tops, the
-- floor, a till), so throws over the aisles leave paper draped across them.
-- Drawn on each client, cleared when the round ends.
Config.STREAMER_WIDTH = 0.8
Config.STREAMER_SPACING = 2 -- studs between the streamer's bends
Config.STREAMER_MAX = 12 -- streamers left lying around at once; the oldest goes first

-- A thrown item that passes this close to the middle of someone else's
-- trolley basket drops into it (generous: hitting a moving basket on a
-- phone is hard). Nobody's trolley catches anything while they're on a till pad.
Config.TROLLEY_CATCH_RADIUS = 2.2

-- ============================================================
-- CHAOS: things landing in trolleys that nobody asked for (designer,
-- 2026-10-05). The point is the choice it forces: stop and dig out the junk
-- (standing still, open to rams and steals), or keep grabbing good food.
-- ============================================================
-- An item falling to the floor (shaken off a shelf, knocked out by a ram)
-- lands IN a trolley whose basket is within this many studs of where it
-- would have landed. Rams never drop into the rammer's or the victim's own.
Config.FALL_CATCH_RADIUS = 2.4
-- Pushing your trolley against a shelf (nose or a side corner in it) at
-- this speed or more can knock one of its items into your own basket, once
-- per SCRAPE_COOLDOWN, with SCRAPE_CHANCE. Yuck sits beside the good food,
-- so shopping tight to the shelves is a gamble.
Config.SCRAPE_MIN_SPEED = 8
Config.SCRAPE_COOLDOWN = 4
Config.SCRAPE_CHANCE = 0.4
-- Digging: you stand still while you rummage, so you can be rammed or
-- robbed, and a ram or a hit knocks you out of it. What you pull out goes
-- into your hands (HAND_SLOTS): with both full, throw before you dig more.

-- ============================================================
-- SOUNDS. Borrowed from Rob a Piggy Bank's list (same owner). The Pro Sound
-- Effects ones (ids starting 9...) are Roblox-licensed and safe; the others
-- are third-party uploads and can be moderated away. Every sound tolerates
-- an empty or failed id: it is silence, never an error. Loudness UNMEASURED.
-- start: seconds of silence at the front of the recording to skip.
-- ============================================================
Config.SOUNDS = {
	grab = { id = "rbxassetid://10128760939", volume = 0.5, pitch = 1.25 }, -- RBLX UI Select 01 (Roblox)
	ram = { id = "rbxassetid://9119912427", volume = 0.8 }, -- Table Impact Drop Leg 1 (PSE)
	shelf = { id = "rbxassetid://87679579947858", volume = 0.6, pitch = 0.8, start = 0.13 }, -- metal smack
	throw = { id = "rbxassetid://9120742716", volume = 0.6 }, -- Whoosh Thick Quick 2 (PSE)
	hit = { id = "rbxassetid://12222124", volume = 0.7 }, -- short spring boing
	scan = { id = "rbxassetid://9116363186", volume = 0.45, pitch = 1.7 }, -- light switch click, pitched into a beep
	checkout = { id = "rbxassetid://341542294", volume = 0.6 }, -- Level Up
	alarm = { id = "rbxassetid://9118805665", volume = 0.55 }, -- Sci Fi Klaxon 2, single note (PSE)
	shutter = { id = "rbxassetid://9117911726", volume = 0.9 }, -- Prison Door 2, latch and rattle (PSE)
	flash = { id = "rbxassetid://1926608277", volume = 0.6 }, -- Legendary Drop
	stolen = { id = "rbxassetid://1470797856", volume = 0.45 }, -- alarm, for the player being robbed
}

-- ============================================================
-- PHASES AND ATTRIBUTE NAMES
-- A name is an interface with no compiler, so every attribute name lives here.
-- Round state is published as attributes on ReplicatedStorage.
-- ============================================================
Config.PHASE = {
	waiting = "Waiting", -- not enough players
	lobby = "Lobby", -- counting down to doors open (and between a match's rounds)
	shopping = "Shopping", -- doors open until the store closes
	results = "Results", -- the feeding: Chonk's mood meter, then the gulp
	podium = "Podium", -- after the last round: 1st, 2nd, 3rd and the winner
}

-- A player's place in the match, as an attribute on the Player.
Config.MATCH_STATUS = {
	waiting = "Waiting", -- no match yet, or joined mid-match: waits for the next one
	alive = "Alive", -- still in the match
	out = "Out", -- eaten: in the stands until the next match
}

Config.ATTR = {
	phase = "RoundPhase",
	phaseEndsAt = "PhaseEndsAt", -- server time (workspace:GetServerTimeNow), 0 when open-ended
	roundStartedAt = "RoundStartedAt", -- server time the doors opened
	roundNumber = "RoundNumber",
	playersReady = "PlayersReady",
	itemKey = "ItemKey", -- on every shelf item part
	isAdmin = "IsAdmin", -- on the Player, set by the server
	trolleyOwner = "OwnerUserId", -- on each trolley model
	trolleyPushed = "Pushed", -- on each trolley model: true while its owner pushes it
	trolleyItems = "ItemCount", -- on each trolley model: how many items are in it
	trolleyOwnerName = "OwnerName", -- on each trolley model: the owner's display name
	section = "Section", -- on a shelf item: the shelf section it stands on (none once it's on the floor)
	matchRound = "MatchRound", -- 1..MATCH_ROUNDS while a match runs, 0 between matches
	matchStatus = "MatchStatus", -- on the Player: a Config.MATCH_STATUS value
	shopping = "Shopping", -- on the Player: true while they're in the store this round (spectators watch these)
	craving = "ChonkCraving", -- item key Chonk craves this round ("" until CRAVING_AT)
	notToday = "ChonkNotToday", -- item key he's not in the mood for this round ("" outside a round)
}

-- ============================================================
-- ADMINS. Checked on the server; the client panel is only a convenience.
-- In Studio every player is treated as an admin (see Admin.luau).
-- ============================================================
Config.ADMINS = {
	[1403296598] = true,
	[3637561075] = true, -- second account, for testing with two players
}

return Config
