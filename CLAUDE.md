# Supermarket Sweep

A Roblox round game for an under-12 audience. 8 to 12 players shop for Big
Chonk, a giant waiting outside: grab what's on your list, ram and steal from
each other's trolleys, sabotage rivals with yuck food, and check out before
the shutters close. Anyone still inside at closing loses everything they
haven't scanned. After each round Chonk eats the worst feeders; five rounds,
one winner.

**Status: MVP, M1 to M6 built in grey box and tested in Studio by the designer (solo and 4 test clients): yum scoring, tills at 1:00, toilet roll streamers, Big Chonk (yuck foods, sabotage, craving, not-in-the-mood, shouts, mood-meter feeding) and the 5-round elimination match (the stands; pests not built). Built since, not yet played: M6b, the trolley as a pile you dig through, and junk landing in trolleys. Next: play M6b, then the real playtest (M7) with 6 to 10 players, scored from the `[Scorecard]` log lines.** Nothing saves, nothing is sold, there is one store, and every model is a placeholder: the designer is making the 3D assets later.

General rules for every Roblox game on this machine live in
`C:\Users\anton\roblox-shared\` (read its README). This file holds only what is
specific to this game.

## Documents

- `CLAUDE.md` (this file): WHY. Rules and what breaks if you change them.
- `docs/MASTER-PLAN.md`: WHEN. Milestones, scope, the playtest scorecard.
- MVP build sheet (published page): https://claude.ai/artifact/Lmqyi2QU6YofZvrT9YjS9d

## Getting set up

1. Rojo 7.7+.
2. `rojo serve default.project.json` -- this project serves on **port 34873**
   (Rob a Piggy Bank uses the default 34872, so both can run at once). In the
   Rojo plugin, set the port to 34873 before pressing Connect.
3. Press Play. With fewer than 2 players the round waits; press **ADMIN**
   (bottom right, or F2) and **Start round now** to play solo.

`rojo build default.project.json -o SupermarketSweep.rbxlx` makes a complete
place file. A fresh baseplate works too: `Store.build` removes its Baseplate
and SpawnLocation at boot (the spawn would sit inside the store), but a
baseplate has StreamingEnabled on, which Main warns about. Turn it off in
Workspace properties.

The whole world is built in code (`Services/Store.luau`), so the place file is
disposable and this repo is the project.

## Layout

```
src/
  ReplicatedStorage/Shared/
    Config.luau      every tunable number; requires nothing (tests load it)
    Rules.luau       pure round rules: dealing, values, scoring, speed, clock, cuts, the meter
    Scorecard.luau   the playtest scorecard, worked out from a round's results
    Remotes.luau     every RemoteEvent, declared once
    Theme.luau       every colour and font
  ServerScriptService/
    Main.server.luau boot, timed per step
    Services/
      Store          builds the store, stocks shelves, moves shutters, till pads
      Shoppers       each player's list, trolley, hands, sprint, scanned value, finish / shut in
      Trolley        the trolley model; pushed (welded to its owner) or parked (anchored)
      Fights         ramming, stealing from parked trolleys, throwing
      Checkout       the tills: who is on a pad, scanning, finishing
      Round          lobby -> 5 x (shopping -> feeding) -> podium; flash sale, Chonk's menu, round log
      Chonk          Big Chonk (placeholder), his lines, the feed line, stands and podium; a leaf
      Fx             sounds and effects decided on the server; a leaf any service may require
      Admin          server-checked test console
  StarterPlayer/StarterPlayerScripts/
    ClientMain       starts the HUD (and the admin panel for admins)
    Hud              clock, list, basket, scan bar, announcements, results
    AdminPanel       the test buttons
    Controls         Shift (held) sprint, Q trolley, F throw, touch buttons, Push/Steal prompts
    Projectiles      draws every thrown item's arc
    Rummage          the dig view: top-down into your basket, click what's on top
    Spectate         anyone not in the store watches someone who is
    FxClient         plays sounds, wobbles shaken shelves, dizzy stars, camera jolt
tests/
  run.py             compiles every .luau, scans for control bytes, runs suites
  rules.luau         Config and Rules checks
  scorecard.luau     the scorecard's verdicts
```

Run the offline checks with `python tests/run.py`. It needs the Luau CLI
(set `LUAU_DIR`, or it looks in `tools/luau/` and `%TEMP%/codex-luau-*`).

## Rules that are load-bearing

**The server owns every number.** Lists, baskets, scanned value, scores and
the clock live on the server. The HUD draws the last `PlayerState` push and
the round attributes on ReplicatedStorage, and computes nothing that matters.

**The clock is attributes in server time.** `RoundStartedAt` and
`PhaseEndsAt` are `workspace:GetServerTimeNow()` values, so every client
draws the same clock. Admin skips move `RoundStartedAt`, so every threshold
(closing warning, shutters, close) fires exactly as it would have.

**Whatever has scanned is safe; the basket is not.** That is the whole stress
of the game. At closing, `Shoppers.shutIn` drops the unscanned basket and keeps
the scanned value. Don't soften this without a playtest saying so: it is the
first thing the MVP is testing.

**Pushing takes one hand** (designer, 2026-10-05). On foot (trolley
parked) you hold `HAND_SLOTS` (2); while pushing, `PUSH_HAND_SLOTS` (1),
which is your throw. Taking the trolley back with more in hand keeps the
newest and puts the rest in the basket (`settleHands`), so the item you
were saving to throw isn't lost. Applies to grabs, steals, digging and a
reset mid-round.

**The till scans your hands, and your trolley only while you push it.**
Everyone starts the round pushing a trolley (`TROLLEY_CAPACITY`, slower as it
fills). Q parks it: you move at `HAND_SPEED` and carry `HAND_SLOTS` by hand.
Taking it back tips your hands into it. A till will not finish you while your
parked trolley still holds items; it tells you to bring it. Without that rule a
player could stand at the till and scan a trolley parked across the store.

**No jumping while you push a trolley.** `Shoppers` sets JumpHeight and
JumpPower to 0 whenever it sets walk speed and you're pushing, and puts the
StarterPlayer defaults back when you let go, check out or the round ends.
Let go of the trolley (Q) and you can jump again.

**A pushed trolley is welded to its owner's root and collides with nothing.**
A collider welded to a character fights the character's own physics. Parked,
its invisible Base collides, so other shoppers bump into it. Every part hangs
off Base, so the server only ever anchors, welds or moves Base.

**Sprint is a meter you spend by holding the key.** Holding drains it over
`SPRINT_STAMINA_SECONDS`, letting go refills it after a short delay, and
running it dry costs a longer delay. The server keeps a snapshot
`{stamina, staminaAt, sprinting, regenAt}` and both ends compute the meter with
`Rules.staminaAt`, so the bar and the speed can't disagree. Sprint multiplies
whatever speed you have. Shift is also Roblox's shift-lock key, so the
project turns `EnableMouseLockOption` off and Main sets `DevEnableMouseLock`
false per player (a running Rojo serve doesn't apply project properties).

**The camera is locked at `CAMERA_DISTANCE`, third person** (designer,
2026-10-05). No zooming out to scout the store, no first person: the
trolley, rams and being knocked over all read from behind the shopper, and
the planned shopper cosmetics need players to see themselves. The camera is
in Follow mode on computer and touch: it eases back behind you as you push,
like a kart game's chase camera, and a drag still looks around (to aim a
throw sideways or see who's behind). Fully locked rotation was rejected:
you couldn't see a ram coming. Main sets the zoom and mode per player (like the shift-lock setting, because a running
Rojo serve doesn't apply project properties).

**Shelves are flat walls, and nobody climbs.** Ledges are visual only
(CanCollide off); each shelf and the fridge run has one invisible wall over
its whole footprint (CanQuery off, so throws and aim still hit the real
shelf parts). Solid ledges 3 studs apart read to Roblox as a ladder: players
started climbing the shelves, and the ledges were steps onto the tops.
Controls also disables the Climbing state on the local character, as a
backstop. Aisle shelves are three levels, 10 studs tall (`SHELF_LEVELS` in
Store), too tall to see or jump over; the fridges stay two levels.

**The only way out is a till.** The counter line has an invisible wall to the
roof, and lane dividers have invisible walls so nobody hops lanes to jump a
queue. Checking out teleports you outside to the window.

**Three fights, three different jobs** (`Services/Fights`). Ramming is up
close, needs `RAM_MIN_SPEED`, and TAKES the top item onto the floor. Stealing
(hold E on a parked trolley) takes its top item for yourself. Throwing (F)
costs you an item (the one in your hand, else the TOP of your pile) and knocks
whoever it hits off balance. If one of them starts making another pointless, that's the thing to
tune first.

**The off-balance guardrails are the point, not tuning.** After a stumble ends,
the target is immune for `HIT_IMMUNITY`, keyed to the TARGET, so a crowd taking
turns can't keep one child down; a thrower cooldown alone wouldn't stop that.
Nobody on a till pad can be rammed or hit, so a queue can't be wrecked at
closing.

**A throw is a real arc, flown by the server and drawn by every client.** The
client sends only an aim direction (the mouse, or the screen centre on touch);
`Fights.sanitiseAim` clamps its pitch and falls back to the facing for anything
malformed. The server steps the flight on Heartbeat and hits whoever the
segment passes within `THROW_HIT_RADIUS` of; `ThrowFx` gives every client the
launch so each draws the same arc from `THROW_GRAVITY` (`Projectiles`), and
`ThrowEnd` removes it. A light aim assist steers a throw at a shopper within
`THROW_ASSIST_CONE` of the aim, leading their run. The first version locked on
with no aim and dropped the item at the thrower's feet; it read as broken.

**The trolley is a pile you dig through, not a list** (designer,
2026-10-05; M6b). The client is never sent what's in your trolley: the HUD
shows only how full it is, and no value until the till. Items lie in the
basket in layers of `PILE_LAYER` in the order they went in, so later ones
bury earlier ones (`Rules.reachable`, `Rules.pileCell`, `Trolley.setItems`).
Dig (R / DIG) stands you still (WalkSpeed 0: open to rams and steals; a ram
or a hit ends it) and the camera looks straight down into the basket
(`Rummage`); a click sends (slot, key) and the server pulls it out only if
it's on top, into a free hand. Hands are the limit: with both full, nothing
more comes out until you throw or put one back (the first version dumped
extras on the floor, which let a player empty the whole trolley). While
digging, your own hands show at the bottom of the dig view (one while
pushing, two when parked) holding what
you pulled out, highlighted (`Rummage`: grey-box hands in the character's
skin colour, client-only, under the camera); tap a held item (or 1 / 2)
to put it back on top of the pile: how a player undoes a pick. A throw with
empty hands throws the top of the pile, whatever it is: to throw something
on purpose, dig it out first. The old HUD chip list and "throw your
cheapest" both did the sorting for the player, which made junk harmless.

**Junk lands in trolleys on purpose** (M6b): the choice between digging it
out and grabbing more is the point. Sources: throws into a basket; items
shaken off a shelf (`Store.fall` asks `catchHandler`, which Fights registers,
for a basket within `FALL_CATCH_RADIUS` of the landing); items knocked out
by a ram (never into the rammer's or victim's own); scraping a shelf with
your trolley (`SCRAPE_*`: now and then an item off that section tumbles
into your own basket); and Chonk's tantrum at `TANTRUM_AT`, when every
section drops one item (`Store.shakeAll`, one sound for the store). Every
landing says only "SOMETHING" landed: you dig to find out what.

**Scores are yum, and the order is the whole rule** (designer, 2026-10-05).
On your list (a staple x `LIST_MULTIPLIER`, 4) > a snack (3) > any other
staple (2) > toilet roll (-2). Lists are dealt ONLY from `kind = "staple"`
(the food Big Chonk needs); snacks are what he loves and are never on a list.
The suite checks that order, because it is what a child learns in one round.
There is no money anywhere: every value goes through `Rules.formatYum`. A
score at or below zero gets no early bonus, so the bonus never deepens a
loss. Item art (3D models for every item, the store and the shoppers) is the
designer's job and comes later; keep items as simple shapes until then.

**Toilet roll counts against you, so it's ammunition.** -2 yum, `kind =
"yuck"`. Dig it out and throw it, or it scans against you. A thrown roll
unrolls a paper streamer (`Projectiles`, client-only, the same on every
screen because the arc is); when it lands, each bend drops onto the first
visible surface below, so paper drapes over shelf tops and the floor.
Streamers last until the round ends, `STREAMER_MAX` at once.

**Yuck food is ammunition, and it sits beside what you want.** Sprouts,
canned peas, spinach and toilet roll (`kind = "yuck"`, -2 yum each, always
the same so a child learns them once). Sprouts, peas and spinach have
`zone = "beside"`: `Store.restock` stocks every other kind first, then puts
yuck in the SPARE slots of the kinds it names (fruit, snacks, steak and
cheese). Sabotage is two verbs: a throw that passes within
`TROLLEY_CATCH_RADIUS` of someone else's basket drops in (whichever the
flight reaches first, a body or a basket, wins), and the steal prompt on a
parked trolley becomes "Plant yuck" while you hold yuck (the client switches
the text; the server decides from your hands). A trolley on a till pad
catches nothing, for the same reason nobody there can be hit.

**Big Chonk's menu changes values, so every value takes it.** A round's menu
is `{ craving, notToday }`. `notToday` is picked at the doors from staples
and snacks, kept out of the list pool, and is worth `NOT_TODAY_YUM`. It is
NOT tagged on the items (designer: the Chonk card says it, and remembering
is part of the game); its prompt still shows its true value. The
craving is picked at `CRAVING_AT` (0:40, so it doesn't collide with the
tills opening at 1:00) and is worth `CRAVING_MULTIPLIER` to everyone.
Multipliers don't stack (the bigger applies) and yuck is never multiplied.
`Rules.itemValue(key, listSet, menu)` is the one place this lives: the
server scores with it and the HUD displays with it (menu from attributes).

**A match is five rounds and the cut is worked out from who's still here.**
`Rules.cutsThisRound(alive, r)` = `(alive - FINALISTS) // (MATCH_ROUNDS - r)`,
which reproduces the build sheet's table (12: 2,2,2,3) and still ends with
three finalists when someone leaves mid-match. Ties go to whoever checked
out first (`Rules.rankRows`). Each player's place is the `MatchStatus`
attribute: Waiting (no match yet, or joined late), Alive, Out (eaten: in the
stands until the next match). Eaten players spectate; the pests idea is not
built.

**Anyone not in the store watches someone who is** (`Spectate`). Eaten,
joined mid-match, checked out or shut in: during shopping the camera
follows a shopper (arrows or the on-screen buttons switch; BACK TO ME
returns to your own character until the next round). The server only keeps
a `Shopping` attribute on each Player (set in `Shoppers.push`); watching is
this client's CameraSubject and changes nothing in the game. Built so the
scorecard's "eaten players still here next match" isn't measuring boredom.

**The feeding is the score screen.** Everyone lines up in front of Chonk; the
HUD reveals one row per player, best first, so the players in danger come
last. Needle = `Rules.meterFor`: score against the round's best, 0 for
nothing or less, and anyone eaten is forced into angry so a child always
sees why. Rows carry `revealAt` in server time, so every screen animates the
same needle at the same moment; Chonk says his verdict on each as it settles.

**Big Chonk is a leaf and a placeholder.** `Services/Chonk` requires only
Shared, Store and Fx, so Shoppers (yuck grabs), Fights (rams, sabotage) and
Round can call it. He's a ball with eyes; everything he does is words
(`Chonk.say` to his bubble and the HUD's Chonk card via `ChonkSay`).
Reactions are rate-limited (`CHONK_REACT_GAP`). Replace the model, keep the API.

**The tills open halfway** (`TILLS_OPEN_AT`, `ROUND_SECONDS / 2`). Before
that, till signs say when and anyone on a pad is told to keep shopping.
Without it, a player could grab two things and leave with a big early bonus;
with it, the most anyone can earn is +60%, and everybody's checkout lands in
the same minute, which is what makes the queue.

**Shelves never restock during a round.** Popular items get fought over and
the store empties. `Store.restock` runs once, at doors open.

**A round is two minutes, on purpose** (designer, 2026-10-05: three minutes
dragged in a solo test with six items on the list). The answer was a shorter
clock, not a bigger store: a bigger store only adds running, and a full server
empties the shelves much faster than a solo test does. The closing warning
and the shutters moved with it (80 s and 100 s). If a full server finds two
minutes too short, raise `ROUND_SECONDS` and move those two with it.

**Shaking a shelf needs a sprint** (`SHAKE_MIN_SPEED` 17, above any plain
push). Every shelf face, fridge kind and half of the fruit table is a
SECTION (`Store.addSection`); an item on a shelf carries its section as an
attribute, so only real stock can fall and a fallen item can't be shaken
again. At walking speed, driving up to a shelf to grab something would have
knocked its stock onto the floor every time. One shake per section per
`SHAKE_COOLDOWN`.

**The flash sale's turkey is in `ITEM_BY_KEY` and NOT in `ITEMS`.** Indexed,
it can be carried, scanned, thrown, stolen and drawn like any item; kept out
of `ITEMS`, it is never stocked or dealt onto a list, so it's worth its
price to whoever gets it out. The sale runs inside the round loop
(`FLASH_SALE_AT` for `FLASH_SALE_SECONDS`).

**The flash sale is the last 30 seconds of shopping** (designer, 2026-10-05;
it was at 0:40). It starts after the closing warning and runs through the
shutters, so the turkey is a $300 lure back into a store that is about to
shut: the shutter gamble, made bigger. `FLASH_SALE_AT` is derived from
`ROUND_SECONDS`, so it stays the last 30 s if the round changes. A grabbed
turkey must still scan before closing; a sale ending at closing makes no
"sale over" announcement, because "STORE CLOSED!" says it. If every shopper
checks out before 1:30 the round ends and the turkey never appears; with a
full server that should be rare, but it is worth watching.

**Effects are decided on the server and drawn on clients** (`Fx` ->
`FxClient`, one `Fx` remote). A shelf wobble is a client-local CFrame on the
shelf's parts, put back exactly where it was; a knocked-out item hops on the
server for under half a second (`Store.dropItem` with a `from`). Sounds keep a
silent loaded copy alive, because a fresh Sound only starts at once while
another with the same id exists.

**The sounds are borrowed from Rob a Piggy Bank** (`Config.SOUNDS`, same
owner). The 9...-numbered ones are Pro Sound Effects and safe; the rest are
third-party uploads that can be moderated away. Every sound tolerates a
missing id. Loudness is UNMEASURED.

## What has been tested

- Milestone 1 played solo in Studio by the designer: two rounds, checked out
  at 96 s (+83%) and 175 s (+4%).
- M2 to M4 played solo (2026-10-05): feels fine, the borrowed sounds load and
  play, a sprint into a shelf shakes it.
- Everything through M6 tested by the designer in Studio, solo and with 4
  test clients (2026-10-05), and "working solid as expected": the solo admin
  run through all five rounds and the podium; fights, sabotage (throws into
  trolleys, planting) and elimination to the stands with 4 clients; edge
  cases (leaving mid-round, mid-feeding and mid-podium, a reset mid-round,
  joining mid-match, shut in holding only yuck, everyone out before 1:30);
  and the phone layout in the device emulator.

## Not yet verified

- Nothing has been played by real players. Everything above is Studio test
  clients driven by one person, so fun, fairness and pacing are unmeasured:
  that is the M7 playtest, scored with the `[Scorecard]` lines in the log.
- Unseen with real players: till queues, parked trolleys blocking lanes,
  whether anyone goes for the turkey after the closing warning, whether yuck
  is easy to tell apart on the shelves, whether a throw into a trolley feels
  fair, and whether eaten players stay for the next match.
- Loudness of the borrowed sounds is unmeasured.
- M6b, the rummage and the chaos (2026-10-05), has not been played: the
  dig view (does the top-down camera frame the basket, do clicks and taps
  pick the right item, does walking end it), junk landing from shakes,
  rams, scrapes and the tantrum, and whether the dig-or-shop choice is fun
  or just annoying. SCRAPE_CHANCE and FALL_CATCH_RADIUS are first guesses.
- Spectator mode (2026-10-05) has not been played: the camera following a
  shopper, switching, BACK TO ME, and handing the camera back at the feeding.
- No jumping while pushing (2026-10-05) has not been played. Check the
  jump button disappears on touch while pushing and comes back on letting go.
- The flat shelf walls, the third shelf level and the climbing switch-off
  (2026-10-05) have not been played. Check: walking into a shelf no longer
  climbs it, the top-level items can be grabbed from the aisle floor, and
  the camera copes with 10-stud shelves.
