# RATS

A co-op first-person pest-control game for one to four players, made in Godot
4.7 (GL Compatibility, Jolt Physics) with a PS1-era look: 480×270 upscaled
nearest-neighbour, vertex snapping, unshaded surfaces and black fog.

A crew of exterminators rides a van to an infested house, gets one minute with
the lights on to read the place, and then the rats are let out. The shift pays
by the rat, and the crew books its own clock before walking in: a long, safe
hunt pays little per animal; a ninety-second one pays five times as much and
leaves whatever is still loose in the walls.

## Running the project

1. Install [Godot 4.7](https://godotengine.org/download).
2. Open Godot, click **Import** and pick this repository's `project.godot`.
3. Run with `F5`.

Steam is optional. The GodotSteam GDExtension lives in `addons/godotsteam/`
and `steam_appid.txt` borrows Valve's Spacewar (480) until the game has an app
ID of its own. With the Steam client running you get your persona, your
picture, invites and the lobby browser; without it the menu says so and `PLAY`
starts a solo shift, which is the normal development run.

`F5` opens on the **menu** (`scenes/menu.tscn`), where the crew stands in
front of the camera in hazmat suits. `PLAY` puts everybody in the back of the
van and on the road; the job is voted on during the drive. See
[The shift](#the-shift).

Two windows on one machine, with no Steam involved:

```
godot --host                # first window: opens the wire and waits
godot --join                # second window: dials 127.0.0.1
godot --join 192.168.1.7    # or a machine on the same network
```

To open a house on its own, without the shift around it:
`godot res://scenes/world.tscn`.

The main scene is `scenes/game_post_process_wrapper.tscn`, a shell that owns
the low-resolution viewport and the fade between screens; every game scene is
loaded inside it.

## Controls

| Key | Action |
| --- | --- |
| `WASD` / arrows | Move (relative to where you are looking) |
| `Shift` | Sprint (spends stamina) |
| `Ctrl` (held) | Crouch — slower, quieter, half height |
| `Space` | Jump |
| Mouse | Look around |
| Left button | Use what is in hand: grab, squeeze, swing, set down |
| Left button (stuck on glue) | Pull free, timed on the green |
| `1` `2` `3` / mouse wheel | Switch belt slot |
| `Q` | Back to your own hands |
| `E` | Use what you are looking at, or open the terminal in the van |
| `E` (held) | Slow jobs — cleaning a sprung trap |
| Right button / `Esc` | Throw away a half-laid glue strip |
| `F` | Ready — leave the van, pull off the road, let the rats out |
| `Tab` (held) | Scoreboard: crew, tallies, distance |
| `Esc` | Pause menu (the game keeps running underneath) |

With a rat struggling in your hands there is no running, no jumping and no
swapping weapons — `Q` included. Crouching is held, not toggled, and under
something too low to stand in the player stays down until he walks out.

## The shift

A shift is five phases walked in order, and the host is the clock — only he
runs a timer, only he decides a phase is over, and everybody else is told:

```
LOBBY → TRAVEL (120 s) → SURVEY (60 s) → HUNT (booked) → RESULT
```

| Phase | Scene | What happens |
| --- | --- | --- |
| `LOBBY` | `menu.tscn` | The crew assembles. No clock. |
| `TRAVEL` | `van_travel.tscn` | Seated in the moving van: vote on the house, book the hunt, shop, plan. |
| `SURVEY` | the house | Lights on, no rats. One minute to read the clues and set traps. |
| `HUNT` | the same house | Rats loose. Ends when the house is clear or the clock runs out. |
| `RESULT` | `van_travel.tscn` | The pay slip. The host's confirmation sends the van back onto the road for the next job. |

Survey and hunt are **the same scene**: the phase changes and nothing reloads,
so the traps the crew spent a minute placing stay where they are. Pressing `F`
asks the host to mark you ready; when the whole crew is ready the phase ends
early. The loop after the first shift is van → house → van: the crew only sees
the menu again by leaving the match.

Two autoloads carry it. `SessionManager` **holds** — the crew by Steam ID
(colour, bag, catches, ready flag), the team bank, the contract, the booked
hunt length, the phase and the seed the house is dressed from. `PhaseManager`
**drives** — the clock, the scene each phase is played in, and the decision to
move on.

### The hunt is a wager

The crew books the hunt's length on the vote screen, next to the sheet that
says how bad the house is (`scripts/session/hunt_time.gd`):

| Booking | Clock | Bounty per rat |
| --- | --- | --- |
| Long (default) | 5:00 | $20 |
| Medium | 3:00 | $40 |
| Short | 1:30 | $100 |

A low infestation is a three-minute job; a house with twenty-four rats in it is
not. Whatever is still loose when the clock runs out stays in the walls unpaid.

## The menu

The lobby opens itself: the menu asks Steam for one the moment it comes up, so
the crew is already on screen. Each player is a hazmat suit standing on a seat,
with their Steam name and picture floating over them; empty seats carry a `+`
that opens Steam's invite window. **PUBLIC LOBBIES** opens the browser
(`scenes/lobby.tscn`) — lobbies are stamped `game=rats` so the Spacewar crowd is
filtered out — and **SETTINGS** the options popup.

**PLAY** is the host's button and only lights once the crew is ready; on a
guest's machine the same button toggles their own ready flag. Colours are no
longer picked here — the palette moved onto the van's terminal.

## The van on the road

`PLAY` seats the crew in the back of the van (`models/rats_van.glb`, built by
`models/rats_van_builder.py`) and pulls off. Nothing in the scene actually
moves: the road texture scrolls, the poles and fences beside it are recycled
past the windows (`scripts/travel/road_scroll.gd`), and the camera carries a
small tremor that never repeats (`scripts/travel/cabin_shake.gd`).

### The vote

The job sheets go up on their own as the van pulls off, one card per contract
in `resources/contracts/`: a photograph of the house, the client, the address,
the notes, the infestation count, the breeds, a difficulty of one to five, what
the job pays and what it costs to sign. **Every man votes**, and the screen
holds the player while it is up — nobody is out of his seat until the house is
chosen. The host books the hunt length beside the cards and presses **START**;
the job with the most hands up is signed, its price leaves the team bank and
the phase machine is pointed at its house. Three jobs ship today:

| Contract | House | Rats | Difficulty | Price | Reward |
| --- | --- | --- | --- | --- | --- |
| 14 Hallow Street | `world.tscn` | 4 | 1 | $0 | $180 |
| 8 Marrow Lane | `world_2.tscn` | 12 | 3 | $200 | $420 |
| Pell House | `world.tscn` | 24 | 5 | $500 | $900 |

A new job is a new `.tres` in that folder; every machine reads the folder off
disk and a contract travels on the wire as its id alone.

### The terminal

Once the vote is settled, `E` anywhere in the van opens the CRT terminal
(`scripts/ui/terminal_screen.gd`), four pages leafed through with the arrows:

- **Store** — the racks, described below. Only sells on the road.
- **Map** — the signed house's floor plan. Left-click plants a pin, right-click
  lifts one, drag or `WASD` pans, the wheel zooms. Three pins per man, coloured
  by his overalls, and the host holds the board so all four screens agree
  (`scripts/session/map_manager.gd`).
- **Job sheet** — the contract and the booked clock, read-only.
- **Palette** — the eight crew colours, with the man himself standing beside
  them in the one he is wearing. No two men in the same colour; the host
  decides.

The terminal is also up in the house, so the map and the job sheet can be read
during the hunt. `E` or `Esc` puts it away.

## The store

| TRAPS | WEAPONS | SUPPLIES |
| --- | --- | --- |
| Mousetrap $25 (3) | Broom $15 | Rat bait $40 (2) |
| Rat glue $40 (2) | Baseball bat $35 | |
| Explosive cheese $120 (1) | | |

What is on sale is `resources/store/*.tres`, one file each, sorted the same way
on every machine. Each item carries a `kind` (`ONE_HAND`, `TWO_HANDS`, `TRAP`,
`BAIT`, `PATCH`) that puts it on a rack and tells the survey which ones to
bar. Pressing a tile puts the thing in the man's hand on the left of the
screen; **BUY** is a second press.

**The host holds the till.** A man at the store *asks* to buy
(`ShopManager.request_buy`); the host checks the team bank and either the
purchase is written on every machine or that one man is told why not.
**Money is the crew's, the bag is the man's**: there is one bank
(`SessionManager.bank_balance`, $100 per player at the start of a session, or
a purse nobody can empty in debug builds), and what each player buys goes in
his own `Stock` and onto his own belt.

### The belt

Three loops, swapped with `1`, `2`, `3` or the wheel, drawn as three squares
at the foot of the screen. No loop belongs to any one thing: what hangs from
each is read off the bag in the order it was bought, a loop comes free when the
last unit of something is spent, and a fourth purchase waits in the van until
one does. The hands are on no loop — they were never bought and `Q` puts them
back. Boxed things count what is left in the corner of their square.

On the road the belt is free; in the survey the killing weapons are barred and
the traps, bait and hands stay (`house_spawns.gd`); in the hunt everything is
allowed.

## The house

Two houses are playable, both modelled in Blender and rebuilt by script:
`world.tscn` instances `models/house.glb` (generated by
`blender/build_house.py`, two floors, the doors as `Door_*` leaves with their
origin on the hinge and their swing angles riding out as glTF extras) and
`world_2.tscn` instances `models/house_2.glb`. The van is parked on the
street outside with a ramp down, and the crew spawns at the front door.

**Doors swing over the wire.** `scripts/house/house_doors.gd` finds every
door leaf in the imported model and rigs it at load — a `HingedDoor` pivot, an
`AnimatableBody3D` so a shut door blocks and an open one does not, and an
`Interactable` for `E`. Add a door in Blender and it works in the game with
nothing written. A door moves because somebody pushed it, so the swing is
announced by whoever reached it.

**Rooms are lit by ceiling lamps** (`scenes/house/ceiling_lamp.tscn`), and the
house is dark around them: low ambient, exponential black fog closing in from
three metres, and an emission term in the level shader for the bulbs.

### The survey

Sixty seconds, lights on, no rats. What the crew reads:

- **Burrows** (`scripts/house/rat_hole.gd`) — slits in the skirting, highlighted
  during the survey and not afterwards. They come in **pairs**: the crack behind
  the pantry and the vent in the back room are two mouths of one run, and a rat
  that dives into one comes out of the other. Noticing which two are the same
  hole is what the minute is for.
- **Droppings** (`dropping_trail.gd`) — laid along the navigation path from
  each burrow to the nearest heap of rubbish, so the trail is true wherever the
  furniture ends up. Follow it and you arrive at a burrow or a bin.
- **Streaks of piss** (`rat_streak.gd`) — down the same routes, rat-sized, and
  the one clue that bites: standing on one costs flesh. Placed by the host and
  replicated; the wound is local.
- **Heaps of rubbish** (`garbage_pile.gd`) — level furniture, where the rats
  already eat and where they nest. The crew does nothing to them.
- **Litter** (`litter_scatter.gd`) — banana skins, bin bags, a doll, scattered
  over the walkable floor from the shift's seed. Not a clue; it hops and
  rustles when you walk into it.

Everything drawn from the seed (droppings, litter) is the same on every machine
without crossing the wire.

### The hunt

The host spawns the contract's `infestation` from the shift's seed, out of the
heaps the crew baited first and then the burrows furthest from the front door.
A quarter of them are **sprayers** and a sixth are **swift rats**. The screech
plays, the highlights go out, the killing weapons unlock. The phase ends when
the last rat is gone, when the booked clock runs out, or three seconds after
the last man in the crew goes down.

## The rats

Each rat is a `CharacterBody3D` on a navigation mesh baked when the map opens
from everything in the `scenery` group (`scripts/navigation.gd`). Its states
are wandering, idle, fleeing, hiding, captured, dead and spraying:

- **Wandering / idle.** Walks to points nearby, stops to sniff, and drifts
  towards food: heaps of rubbish and any tub of bait the crew put down
  (`lures` group). At the food it feeds for five to eleven seconds and takes
  much less notice of anything.
- **Fleeing.** On hearing a man closer than 6 m or seeing him closer than
  16 m — further if he is running, closer if he is crouched — it bolts, faster
  than the player for a moment and then a little slower than his walk. A
  sprung trap with a body in it is a `fear` spot the flight avoids.
- **Bolting through the walls.** A fleeing rat within 12 m of a paired burrow
  whose far mouth is further from the hunters dives in and comes out at the
  other end, then will not do it again for six seconds.
- **Hiding.** Scores a dozen blind spots behind nearby obstacles — far from
  the player, out of his line of sight, with a way out — and crouches still
  there until seen or approached within 3 m.
- **Spraying.** A sprayer cornered inside 2.6 m stops, turns, winds up for a
  third of a second and gets the man in the face: 12 damage, a lens full of
  yellow and a fresh streak on the boards. Step back during the wind-up and it
  misses. Seven seconds before it can do it again.
- **Captured / dead.** Grabbed, it is torn off the ground and struggles in the
  hand; strangled, it bursts in the fist.

A rat that has stopped moving for half a second steps sideways and looks for
another path. All of it is thought for on the host; guests draw puppets.

### The species

`resources/species/*.tres`. A new breed is a copy of one of these with the
numbers changed.

| Species | Runs at | Crouch notice | Feeding notice | Habit |
| --- | --- | --- | --- | --- |
| Common rat | 1.0× | 0.55 | 0.70 | — |
| Swift rat | 1.2× | 0.60 | 0.70 | Faster than a walk, slower than a sprint: the sprint key is the answer. |
| Sprayer rat | 1.0× | 0.80 | 0.85 | Turns and sprays whoever corners it. Works free of the glue in 20 s. |

*Crouch notice* is how much of its sight and hearing a breed keeps against a
kneeling man; *feeding notice* the same with its nose in the food. The two
multiply, which is why creeping is worth most over the bait.

### The model

`mobs/rats/Rat_Fbx.fbx`: a 13-bone skeleton with `Rat|Idle`, `Rat|Idle_Break`,
`Rat|Run`, `Rat|Death` and `Rat|Attack`, cleaned on import by
`mobs/rats/clean_import.gd`. Each rat rolls one of four furs at birth. A rat in
the sights is outlined (`materials/rat_outline.tres`) and the crosshair goes
taut on it.

## Hunting on foot

### The hands

Every weapon lives under the player's head (`scripts/weapons/`), inherits from
`Weapon` and finds its target the same way: the closest rat within 2.6 m and a
50° cone, with no wall in between. The hands **grab**. The rat rises to the
middle of the screen kicking and biting, and from then on the same click
squeezes: twelve squeezes hammered without a pause kill it, the grip drains
while you stop, and a grip that reaches zero lets the animal loose with a head
start. A rat that was already stuck on glue takes about a third of the
squeezes. The kill costs stamina (40 % of the bar, 20 % for a pinned rat) and
ends in a burst of red shards (`scripts/fx/blood_burst.gd`) rather than a body
to carry.

### Stamina

Four seconds of sprint (`hud_stamina.gd`, the thin bar over the health bar).
It drains while `Shift` and a direction are held, recovers after a second's
pause, and an emptied reserve stays red and unusable until a third of it is
back. Getting a boot caught in glue takes 30 % of it. The swift rat is the
breed that makes it matter.

### Crouching

Half height, slower than a walk, no sprint and no jump — and quieter: a rat
sees and hears a kneeling man from closer in, by its breed's own fraction.

### Melee

The **broom** and the **baseball bat** (`melee_weapon.gd`) settle a rat in one
swing. The swing happens whether or not anything is in the sights — the miss is
the game. What they leave is a crushed body (`Death.Type.CRUSHING`).

### Traps and bait

Everything left on the floor goes through `TrapManager`: the player *asks*, the
host checks the phase and the bag, and the node arrives on every machine
through a `MultiplayerSpawner` with its pose in the spawn data. A translucent
ghost follows the sights while a trap weapon is out; it never crosses the wire.

- **Mousetrap** — one click, armed, works while you are elsewhere. The first
  rat on it dies mangled (`TRAP`) and stays in it: the trap joins the `fear`
  group and the floor around it empties until somebody holds `E` over it. The
  sprung trap goes back in the bag *bent*, and setting a bent one down again
  costs a $2 spring, shown in red over the sights.
- **Rat glue** — laid like tape: the first click pins the near end, the strip
  stretches to where you point (up to 2.4 m), the second click lays it, right
  button or `Esc` throws it away. A strip lives forty seconds and holds five
  rats. It kills nothing — a stuck rat stays whatever it was, and the hand takes
  it off the glue as an ordinary capture. **The player is not exempt**: walk
  onto a strip and the boot stays put, the strip loses ten seconds, and the way
  out is a sweeping bar — three clicks inside the green, each moving the green
  and speeding the sweep. The aim is judged on the machine holding the mouse.
- **Rat bait** — a handful of food where you point. Catches nothing: it is a
  preference written on the map, and rats with nothing more urgent drift to it
  and feed. It is where the creeping pays.
- **Explosive cheese** — a bait that goes off when the first rat reaches it,
  killing everything within 4 m (`GUNSHOT`).

Traps deliberately stay out of the `scenery` group, or they would be baked into
the navigation mesh and every rat would route around them.

### Reaching for things

A short ray out of the camera (`Head/Camera/Interact`, 2.2 m) only sees the
`interactable` layer. Anything the player can put his hands on is an `Area3D`
with `scripts/interaction/interactable.gd`: it says what the prompt reads, may
ask for the key to be *held* (`hold_time`, drawn by `hud_hold.gd`), and
announces `used`.

## Flesh

A hundred points, drawn as a bar over the belt: green, amber past halfway, red
and breathing in the last quarter, whitening on every hit. What hurts: standing
on a streak, a sprayer's faceful (12), and nothing else yet. `take_damage()` on
`player.gd` is the one door in.

**Dying does not end the match.** The body falls, the view becomes a
third-person camera the dead man can turn, the HUD gives way to the death
screen, and he sits the rest of the phase out. If the whole crew goes down the
shift moves to the pay slip three seconds later, and the slip has a word for
it.

## The money

**Every rat pays the booked bounty** — $20, $40 or $100 by the hunt length — into
a **crew wallet** mirrored on every machine. The host decides every death and
broadcasts the credit; only the killer's machine counts the catch for the
scoreboard. The tables of species value (`rat_species.gd`) and death discount
(`death.gd`: strangulation 100 %, poison 85 %, trap 75 %, piercing 65 %,
gunshot 50 %, crushing 40 %) are still here and still travel with each catch
onto the slip, but they do not change the pay today.

The bank moves twice (`scripts/economy/bank.gd`): on the doorstep the team
balance is copied into `Wallet`, so what the shop closed on is what the HUD
opens on; on the pay slip what is left, plus the contract's reward, is written
back absolute — idempotent, so a phase entered twice cannot pay twice. Only
the host settles.

The **result screen** (`scripts/ui/result_screen.gd`) is drawn in the van from
`ShiftReport`, which tallies catches as they happen. Anybody can put his slip
down; the host's press sends the van back onto the road and opens the next
vote.

## On screen

`scenes/hud_game.tscn` is drawn at 480×270 in a pixel font with a hard black
outline, through `scenes/big_font_outlined_label.tscn` for every line of text.
Every piece mirrors an autoload and keeps no count of its own:

- the phase strip (`hud_phase.gd`) — clock on top, phase under it, the crew's
  ready count, a blink and a beep through the last ten seconds;
- the belt (`hud_hotbar.gd`), the health bar (`hud_health.gd`) and the stamina
  bar (`hud_stamina.gd`) over it;
- the crew wallet (`hud_money.gd`) with a passing notice of the last catch, and
  the count of rats still loose (`rat_counter.gd`);
- the crosshair, the grab prompt, the strangling prompt, the glue escape bar,
  the hold bar, the `E` prompt, the ready prompt and the splatter on the lens;
- the **minimap** (`minimap.gd`) — a round dial cut from the navigation mesh
  with the crew as coloured dots.

`Tab` holds the **scoreboard**: crew, colours, rats taken and distance. `Esc`
opens the **pause menu**, which never pauses the tree — the wire does not stop
for a menu — and carries the same crew list with a ping against each name,
plus the settings and the way out. **Settings** (`settings_manager.gd`,
`user://settings.cfg`): fullscreen, three volume buses, streamer mode (hides
Steam names and lobby IDs) and the language, English or Brazilian Portuguese
(`localization/ui_strings.csv`).

## Multiplayer

Two things are up at once. The **Steam lobby** is the guest list — Valve holds
it and the menu reads it. The **`SteamMultiplayerPeer`** is the wire — Godot's
`SceneMultiplayer` over Steam P2P, or over plain ENet with `--host`/`--join`.
`scripts/steam/lobby_manager.gd` opens and closes both together. Whoever owns
the lobby is peer 1; there is no host migration, and a host that leaves drops
everybody back to the menu (`network_guard.gd`), with the reason on the status
line.

**The pattern everywhere is ask → host decides → everybody writes.** Colours,
ready flags, votes, the hunt length, purchases, map pins, trap placement, the
phase change — a client never writes its own copy first. The autoloads that
hold state (`SessionManager`, `Stock`, `Wallet`) never touch the wire; the
managers above them do.

**Every player owns his own body.** One `PlayerAvatar` per peer — the hazmat
suit with the Steam name over it — is put up on every machine by
`player_avatars.gd`; yours is never drawn because you are inside it. Position,
yaw and state cross twenty times a second and are eased on arrival; grabs and
squeezes cross as RPCs so a click between two packets is never dropped. The
suit (`player_model.gd`) plays the legs off the state and poses the arms over
them (`player_arms.gd`) so a man strangling a rat is seen doing it.

**Rats are the host's.** Guests draw puppets off a synchroniser; a guest that
grabs, squeezes or kills asks the host, and the animal comes back over the
wire already caught or dead. The same rule holds for traps catching, glue
holding and cheese going off.

**Joining a shift.** `PLAY` on the menu, accepting an invite with the game
running, or being relaunched with `+connect_lobby <id>` all end at
`scripts/session/join_gate.gd`: the newcomer knocks, the host sends the whole
shift in one packet — crew, colours, bank, bags, contract, phase, seed — or a
refusal in a sentence. A shift past the lobby is closed; four is the van.

### Testing with two clients

Steam allows one running client per account, so real invites and the browser
need two machines. Everything else — movement, animation, colours, votes, the
shop, traps, the whole phase flow — runs on one desk with `--host` and
`--join`; those players are called `Player 1`, `Player 2` … under stand-in
account numbers.

## The look

`VISUAL.md` is the recipe. The world is drawn at 480×270 into a `SubViewport`
and upscaled nearest-neighbour; there is no screen-space filter. What makes it
retro is the renderer itself: `shaders/level.gdshader` snaps every vertex to a
grid (`common.gdshaderinc`, driven by the `vertex_resolution` project global)
and lights every face flat, `sky.gdshader` is a three-band gradient,
`viewmodel.gdshader` draws the first-person arm (`models/hazmat_hand.glb`)
with its own FOV, and `scripts/ps1_material_applier.gd` hangs the level
material on every mesh under it — spawned nodes included, which is why anything
on the floor must be opaque: the shader scissors any alpha below one.

## Tests

Headless benches, one per claim, in `tests/` and a few older ones at the root:

```
godot --headless --path . --script tests/strangle.gd
```

`strangle`, `burst`, `stamina`, `stealth`, `feeding`, `swift_rat`,
`glue_trap`, `glue_multiplayer` (two real ENet peers in one tree),
`death_screen`, `result_flow`, `screen_fade`, `map_selection`,
`minimap_navigation`, `house_model`, `house_routes`, and at the root
`_test_house`, `_test_clues`, `_test_litter`, `_test_contract_vote`,
`_test_van_vote`. `scratch/` holds preview and probe scripts that are not
tests.

## Structure

- `scenes/` — `menu.tscn` (main screen), `lobby.tscn` (the public lobby
  browser, instanced into the menu), `van_travel.tscn` (the van on the road and
  the pay slip), `world.tscn` / `world_2.tscn` (the two houses), `player.tscn`,
  `player_avatar.tscn`, `player_model.tscn` (the suit), `player_view_model.tscn`
  (the arm), `rat.tscn`, `hud_game.tscn`, `hud_phase.tscn`, `minimap.tscn`,
  `scoreboard.tscn`, `pause_menu.tscn`, `settings_menu.tscn`,
  `terminal_screen.tscn`, `store_screen.tscn`, `color_screen.tscn`,
  `difficulty_screen.tscn`, `contract_vote_screen.tscn`, `result_screen.tscn`,
  `death_screen.tscn`, `traps/` (mousetrap, glue, bait, cheese), `clues/`
  (hole, streak, litter, garbage), `house/ceiling_lamp.tscn`,
  `map/map_viewer.tscn`
- `scripts/session/` — the shift: `phase.gd`, `hunt_time.gd`, `contract.gd`,
  `session_manager.gd`, `phase_manager.gd`, `ready_manager.gd`,
  `color_manager.gd`, `contract_manager.gd`, `shop_manager.gd`, `map_manager.gd`,
  `trap_manager.gd`, `clue_manager.gd`, `join_gate.gd`, `network_guard.gd`,
  `shift_report.gd`, `van_spawns.gd`, `house_spawns.gd`
- `scripts/house/` — `house.gd`, `house_doors.gd`, `hinged_door.gd`,
  `rat_hole.gd`, `dropping_trail.gd`, `rat_streak.gd`, `garbage_pile.gd`,
  `floor_litter.gd`, `litter_scatter.gd`
- `scripts/weapons/` — `weapon.gd`, `hands.gd`, `melee_weapon.gd`,
  `trap_weapon.gd` with `mousetrap_weapon.gd`, `glue_weapon.gd`,
  `bait_weapon.gd`, `explosive_cheese_weapon.gd`, and `inventory.gd` (the belt)
- `scripts/traps/` — `trap.gd`, `mousetrap.gd`, `glue_trap.gd`, `bait_pile.gd`,
  `explosive_cheese.gd`
- `scripts/economy/` — `death.gd`, `rat_species.gd`, `store_item.gd`,
  `wallet.gd`, `stock.gd`, `bank.gd`
- `scripts/steam/` — `steam_manager.gd`, `lobby_manager.gd`, `lobby_screen.gd`,
  `steam_avatars.gd`, `player_avatars.gd`, `player_avatar.gd`
- `scripts/ui/` — the screens: menu, crew, cards, invite slots, terminal and
  its four pages, vote, result, death, scoreboard, pause, settings, crew list
- `scripts/travel/` — `van_travel.gd`, `road_scroll.gd`, `cabin_shake.gd`,
  `van_seat.gd`
- `scripts/` — `player.gd`, `player_model.gd`, `player_arms.gd`,
  `player_view_model.gd`, `rat.gd`, `navigation.gd`, the `hud_*.gd` pieces,
  `minimap.gd`, `ps1_material_applier.gd`, `game_post_process_wrapper.gd`,
  `floor_shadow.gd`, `fx/blood_burst.gd`, `audio/audio_manager.gd`,
  `settings/settings_manager.gd`, `interaction/interactable.gd`,
  `map/map_viewer.gd`
- `resources/` — `contracts/` (with `plans/` and `photos/`), `species/`,
  `store/`, `retro_environment.tres`, `seated_animations.tres`
- `shaders/`, `materials/` — the level, sky, viewmodel and death-screen shaders
- `models/` — `rats_van.glb` (+ `rats_van_builder.py`), `house.glb`,
  `house_2.glb`, `hazmat.glb`, `hazmat_hand.glb`, `van_exterior.glb` (the menu),
  the weapon and trap models
- `blender/` — `build_house.py`, `kit_casa.py`, `build_shed_scene.py`, `van/`
  and the `.blend` sources (`.gdignore`d)
- `assets/` — the house kit pieces, the shed yard, the traps and the computer
- `mobs/rats/` — the rat model, its furs and the post-import script
- `localization/` — `ui_strings.csv` and its `en` / `pt_BR` translations
- `tests/`, `scratch/` — benches and probes

The physics layers are `1: scenery`, `2: player`, `3: rats` and
`4: interactable`. Rats do not bump into the player or each other; only the
scenery stops them. `.godot/` is generated and not versioned.
