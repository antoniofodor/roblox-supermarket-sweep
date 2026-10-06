# Master plan

The MVP exists to answer one question: **is the core round fun?** Nothing
else gets built until a playtest says yes. Full build sheet:
https://claude.ai/artifact/Lmqyi2QU6YofZvrT9YjS9d
(source: `docs/build-sheet.html`; edit it there and republish to that link).

## What the playtest has to prove

1. Players gamble on the shutters: some stay for one more item and get caught.
2. Ramming is fun on both ends.
3. The closing rush happens: queues, last-second dashes, someone shut in.
4. Players start the next round without being asked.
5. A new player understands it in one round, with no explaining.
6. Big Chonk makes the list matter: players read his shouts and fight over his cravings.

## Milestones

| | Milestone | Status |
|---|---|---|
| M1 | Shop and leave: store, lists, grabbing, tills, shutters, results, admin console | **Played solo, works** |
| M2 | The trolley: pushing, 20 slots, slows as it fills, let go and carry 2 by hand (one per hand). Plus a held sprint with a meter (designer's addition) | **Played solo, feels fine** |
| M3 | Trolley fights: ramming knocks an item out, stealing from parked trolleys, throwing an item to knock a shopper off balance (1.5 s, 5 s hit immunity for the target, safe on till pads) | **Built; needs 2+ players to play** |
| M4 | The moment: one flash sale (a $300 golden turkey for the last 30 s of the round, 1:30 to closing), shaking shelves (sprint into a shelf, 1 to 3 of its items fall, one shake per section every 6 s), sounds, dizzy stars, items hopping out on a ram, a 2-minute round | **Played solo: sounds load, shelves shake** |
| M4b | Yum: scores in yum (staples 2, x2 on your list; snacks 3; toilet roll -2, thrown first, leaves a paper streamer draped over whatever it flies across); lists are staples only; the tills open at 1:00 | **Built, not yet played** |
| M5 | Big Chonk (grey box): the giant outside the window, yuck foods (sprouts, peas, spinach) stocked beside the good food, thrown items landing in trolleys, planting yuck in parked trolleys, the not-in-the-mood food, the craving at 0:40, his shouting by name, banging on the glass, the feeding after each round with his mood meter as the score | **Built, not yet played** |
| M6 | The elimination match: 5 rounds, cuts sized so 3 reach the final, Chonk eats the eliminated, the stands (pests not built), podium with one winner carried on his head | **Built, tested in Studio** |
| M6b | Chaos and the rummage: the trolley is a pile you dig through (no contents list; dig stands you still with a top-down view, pull out what's on top), throws take the top of the pile, junk lands in trolleys from shakes, rams, scrapes and Chonk's tantrum | **Built, not yet played** |
| M7 | Real playtest with 6 to 10 players, at least 2 full matches, scorecard, tune, decide | |

Test each milestone before starting the next.

## In the MVP

One store; a round loop that repeats; shopping lists (list items x2); grabbing;
carrying with slowdown; letting go of the trolley and carrying 2 by hand (M2);
ramming and stealing (M3); 3 tills with scan time; shutters; early-exit bonus;
one flash sale (M4); Big Chonk and the feeding (M5); the 5-round elimination
match (M6); HUD; admin console; a round log in the server output.

## Big Chonk and the elimination match (designer, 2026-10-05)

Players shop for a huge hungry giant, **Big Chonk**, waiting outside the
store. Each player's list is what he wants to eat. After every round he eats
what everyone brought and whoever fed him worst gets eaten. Five rounds, one
winner. Underneath, the round is unchanged: the list is his cravings, the till
is how food gets out to him, and the results become his mood meter.

**Scoring a round, in yum** (designer, 2026-10-05; built in M4b). Staples
(milk, eggs, bread, fruit...) are what he needs: 2 yum, 4 on your list, and
the only food on lists. Snacks are what he loves: 3 yum, never on a list.
Yuck food (toilet roll now; Brussels sprouts, canned peas and spinach with
Chonk) is -2 yum. Shut in brings him nothing. The early checkout bonus stays. Ties go to
whoever checked out first.

**The match.** 5 rounds. Rounds 1 to 4 cut the lowest scorers so exactly 3
reach round 5, spreading the players above 3 across the four rounds with the
remainder in the later ones: round r cuts `floor(e*r/4) - floor(e*(r-1)/4)`,
where `e = players - 3`. 12 players: 2, 2, 2, 3. 8: 1, 1, 1, 2. 4: 0, 0, 0, 1.
3 or fewer: nobody is cut. Round 5 ranks the survivors 1st, 2nd and 3rd; only
1st is the winner (crowned, carried by Chonk). Late joiners wait for the next
match. A match runs about 13 to 14 minutes.

**During a round:**
- **Yuck food is what he hates** (designer, 2026-10-05): Brussels sprouts,
  canned peas, spinach and toilet roll, always the same, -2 yum each, never
  on a list. This replaces the earlier "2 new hated foods every round": a
  fixed set is learned once. Each yuck food is stocked right beside food
  players want (sprouts by the fruit, peas by the snacks, spinach in the
  fridges by the steak), so everyone picks up ammunition on the way.
  Sabotage, two ways: a thrown item that lands in a trolley goes into it,
  and holding E on a rival's parked trolley with yuck in hand plants it (the
  reverse of stealing). The till scans it against them; the counter is
  taking items out of your trolley before the till. He gags and spits it.
- **Not in the mood** (designer, 2026-10-05): each round he's tired of one
  food he normally likes ("NO PIZZA TODAY!"), announced at the doors and on
  the HUD. On nobody's list that round; counts -1 yum (designer: a small
  minus, less than yuck's -2).
- **Cravings change at 0:40** (moved from 1:00 so it doesn't land on the
  tills opening): one food is worth triple to everyone for the rest of the
  round. Order of the round's moments: craving 0:40, tills open 1:00,
  closing warning 1:20, flash sale 1:30, shutters 1:40.
- **He shouts:** visible through the front window, speech bubbles and HUD
  lines by name ("SAM! WHERE'S MY CHEESE?"), angrier as the clock runs down,
  banging on the glass in the last 20 seconds.

**The feeding, after every round.** Everyone lines up on a stage in front of
him with their bag. He grabs each bag, dumps it in his mouth, and reacts
(belly drum, shrug, or gag and spit). Safe players go fast, about 1.5 s each;
the players in danger go last. Then he gulps the eliminated and spits them
into the stands. A cartoon joke: nothing is lost. After round 5, the podium.

**His mood meter is the score display** (designer, 2026-10-05). Each player's
result is a meter from **angry** through **content** to **love**, shown as
they're fed. The needle moves item by item (up for wanted food, more for list
food, down with a gag for hated food) and stops where they landed; the exact
value shows small beside it. Where it stops: their round score against the
best feeder's. The best feeder fills it; shut in or net negative sits at the
far end of angry; anyone being eaten always lands in angry, so a child can
see why. Survivors can still land in angry ("phew"). In M5 nobody is eaten
yet, so the meter is only the comparison. For players in danger the needle
wobbles at the edge of angry before it settles.

**What eliminated players do.** Built first: they spectate (the simplest
version, to test the match): during each round the camera follows a
survivor, and they can switch between them. Players who join mid-match
watch the same way. Still recommended for later: they
come back into the store as pests who can't shop but can throw yuck food at
the survivors, because kids won't sit through ten minutes of watching. The
scorecard row "eliminated players still here next match" decides it.

**Later, not now:** other customers (a dragon, a giant baby, an alien), your
own pet to raise across sessions, team mode with two giants.

## After the playtest: art direction

Chaotic, goofy, low poly, with custom shopper characters instead of Roblox
avatars (granny, toddler, bodybuilder, dad in sandals), which become the
cosmetic shop. Build them on the R15 skeleton so default animations and emotes
work, keep the collision body standard-sized so fight tuning holds, show the
player's name, and let players pick and dress their shopper. Store and items
go low poly first, characters second. Full reasoning on the build sheet.

## Chaos and the rummage (designer, 2026-10-05; M6b)

The feeling to get: food flying everywhere, junk landing in your trolley
when you didn't want it, and a constant choice between stopping to dig it
out and carrying on grabbing good food.

- **Your trolley is a pile, not a list.** The HUD shows how full it is, not
  what's in it, and no value until the till. Items pile up in layers in the
  basket, so what went in first gets buried. Anything landing in it tells
  you only that SOMETHING landed.
- **Digging (R, or DIG on a phone).** The camera looks straight down into
  your basket; click or tap what's on top to pull it into a hand. Pushing
  takes one hand, so while you push you hold one item (your throw); with
  the trolley parked you hold two. With your hands full, throw something
  or put it back before you dig more. Taking the trolley back with two in
  hand keeps the newest and puts the other in the basket. While you dig, your own hands show at the bottom of
  the view holding what you've pulled out, highlighted: tap a held item to
  put it back on top of the pile.
  While you dig you stand still, so you can be rammed or robbed, and a ram
  or a hit ends it.
- **Later, once the item models exist: hands-on digging.** Press and hold
  an item to grab it, and drag it around the pile: shove things aside to
  reach what's underneath, or lift it out into your hand. With real models
  the trolleys look properly full, which is what makes this work; with grey
  boxes a click is enough.
- **Throwing** throws what's in your hand, else the top of the pile,
  whatever it is. To throw something on purpose, dig it out first.
- **Junk lands in trolleys** from throws, shaken shelves, rams (into a
  bystander's trolley), scraping your trolley along a shelf (yuck sits next
  to the good food), and **Chonk's tantrum** just after the closing warning,
  when every shelf in the store drops an item at once.
- Tradeoff accepted: hiding the contents works against "make risks
  readable", but the model shows the pile and digging shows everything. If
  kids find it frustrating, the first fix is a HUD hint that yuck is inside.

## Out until a playtest earns it

Saving, coins, levels, unlocks. Shop, passes, crates, any Robux. More stores
(they will not be gated behind levels; one map first). Basket and flatbed
choice. Frozen and fragile items, the manager, wet floors, power cuts. NPC
shoppers. Self-checkout and express lanes. Real item models and polish.

## Playtest scorecard

| Measure | Target | If it's off |
|---|---|---|
| Players shut in each round | 10 to 30% | None: start shutters earlier or slow scanning. Most: more warning. |
| Rams per player per round | 2 to 6 | Few: smaller store, more list overlap. Lots: longer cooldown. |
| Queue at closing | 2+ waiting | No queue: remove a till. |
| Checkouts in the last 20 s | over half | Everyone leaves early: lower the early bonus. |
| Score gap, 1st to last | under 3x | Bigger: cap the trolley or add items. |
| Matches before leaving | 2+ | Fewer: fix the core, don't add features. |
| Yuck food fed to Chonk per round | a few, by sabotage | None: sabotage too hard. Most players: yuck is hard to spot in your own trolley. |
| Digging per player per round | 2 to 20 s | None: not enough junk lands (raise SCRAPE_CHANCE, FALL_CATCH_RADIUS). Lots: digging eats the round. |
| Eliminated players still here next match | most | They leave: try the pests, or a shorter match. |
| Players can say where they landed on the meter | yes | Slow the danger reveals, make the zone labels bigger. |
| New players get it in round 1 | yes | Simplify the HUD or the rules first. |

After every feeding the server prints the round log (`[Round N] results`,
one line per player) and the scorecard itself: a `[Scorecard]` block with
each measure, its target, OK / LOW / HIGH, and what to try when it's off
(`Shared/Scorecard.luau`). Match-level lines: `[Scorecard] NAME left after N
match(es)` when anyone leaves, and `[Scorecard] eaten last match and still
here: x of y` at each match start. The meter question and "new players get
it" are for watching faces, not the log.
