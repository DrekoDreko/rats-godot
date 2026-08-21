# RATS

3D game made in Godot 4.7 (Forward Plus, Jolt Physics).

## Running the project

1. Install [Godot 4.7](https://godotengine.org/download).
2. Open Godot, click **Import** and pick this repository's `project.godot`.
3. Run with `F5`.

`F5` opens on the **lobby screen** (`scenes/lobby.tscn`), not on the map. With no
Steam client running it says so and **PLAY SOLO** goes straight to the hunt, which
is the normal development run. See [The lobby](#the-lobby).

## Controls

| Key | Action |
| --- | --- |
| `WASD` / arrows | Move (relative to where you are looking) |
| `Shift` | Run |
| `Space` | Jump |
| Mouse | Look around |
| Left button | Grab the rat |
| Left button (with a rat in hand) | Strangle |
| `1` `2` `3` | Switch weapon |
| `E` | Use what you are looking at (the computer in the van) |
| `Esc` | Release/recapture the mouse — and close the shop |

With your hands full the same click that grabbed starts strangling, and the
player walks slowly: with a rat struggling in your hands there is no running and
no jumping.

## The rats

Ten rats live loose about the map. Each one has four behaviours:

- **Wandering** — walks slowly to any point nearby and sometimes stops to sniff.
- **Fleeing** — on hearing the player closer than 6 m, or seeing him closer than
  16 m (further still if he is running), it bolts. The burst is faster than the
  player's run, but then it tires and settles into something a little slower than
  that — you can catch up.
- **Hiding** — while fleeing, it looks at the obstacles around it and runs for the
  blind spot behind one of them, out of the player's line of sight. Once there it
  crouches and keeps still: it only bolts again if it is seen or if the player
  comes closer than 3 m.
- **Captured** — grabbed, it is torn off the ground and ends up in the player's hand.
- **Dead** — strangled in the hand, or dropped on the ground already lifeless.

The hunt, then, is about turning the corner: while the rat believes it is hidden
it does not move, and that is when you can take it.

## Killing a rat

The game will have several weapons, and the first of them are your own hands.
Every weapon lives under the player's head (`scripts/weapons/`), inherits from
`Weapon` and looks for its target the same way: the closest rat within 2.6 m and
within a 50° cone around the sights, as long as there is no wall in the way. What
changes from one to the next is what it does with the rat it found.

Hands do not kill: they **grab**. The rat hunches on the ground, is torn off in
an arc, turns a somersault in the air and stops in the middle of the screen,
held, struggling and trying to bite. From then on the same click is what kills:
each one squeezes its neck a little harder, and the grip drains on its own while
the player does not click again. Hammering without stopping takes about thirteen
squeezes. Hammering slowly takes more — and if the bar reaches zero and stays
there, the rat gets loose from the hand, leaps away and bolts with a few seconds'
head start in which it cannot be re-grabbed.

Hands are the only way to kill a rat for now. A weapon that settles it in a
single blow just needs to inherit from `Weapon` and override `_use()`.

### The belt

The player carries three slots, swapped with `1`, `2` and `3`. At the foot of the
screen they are three squares, in the shape everybody already knows from
Minecraft: a dark cell each, and a bright frame around whichever one is in hand.
There is no number written under them — the keys are `1`, `2` and `3` from left
to right, and that is the whole of it.

The hands are in the first square. The other two carry the traps bought at the
computer, and until a box has been bought they behave exactly like an empty
square: a loop on the belt with nothing hanging from it. An empty slot is a
player with nothing in his hands — he walks and looks around the same way, and
the click finds nothing to do.

A weapon that comes out of a box counts what is left of it in the corner of its
square, and the square goes dim when that count reaches zero. The belt follows
the count while the player is standing there: buying with that slot already
picked puts the weapon in his hand on the spot, and using the last one takes it
away the same way, without anybody swapping anything.

A weapon shows its `icon` in the square. While it has none, the belt writes its
name there instead, which is what the hands do today.

**With a rat kicking in your hand nothing gets swapped.** The same `is_busy()`
that already takes away the running and the jumping locks the belt too, and the
hotbar leaves the screen along with the crosshair while the strangling prompt is
open.

The belt is `scripts/weapons/inventory.gd`, and it does not own the weapons:
every one of them goes on hanging off the player's head, where it can reach the
camera and the capture point. What the belt takes care of is the *swap* — putting
the last weapon away, with the swing halfway through and the shake it left in the
camera, before the next one comes out. Hanging a new weapon on it means adding
the node under `Head` and pointing a slot at it in `player.tscn`; no code.

### What the player has to lose

Over the three squares there is a bar, spanning exactly the width of them: the
hundred points of flesh the player starts the shift with, and no number written
anywhere — how far it has drained is the whole of what he is told. Like every
other piece of this HUD it only mirrors what the player already knows — the
count lives in `player.gd` and `take_damage()` is the one door into it, so a
wound, a bandage or a respawn cannot leave the screen showing a health nobody
has.

The bar says how the beating is going by its colour: green while he is whole,
the strangling prompt's own amber past the halfway mark, and its red down at the
last quarter, where it also starts to breathe. Every fresh wound whitens it for
a quarter of a second — with no number beside it, that whitening is what makes a
hit read as a hit, and not as a bar that quietly got shorter.

With a rat in hand it leaves the screen along with the hotbar and the crosshair,
and for the same reason: it sits over the belt, and the belt is where the
strangling prompt opens.

**Nothing on the map bites yet.** The rats only run, so for now the bar is there
waiting: whatever comes to hurt the player knocks on `take_damage()`, and the
HUD hears of it by signal (`health_changed`, `damaged`). Running out of flesh is
what falling off the map already was — `died` goes out for whoever wants to put
an end-of-shift screen in the way, and then the player wakes up back where the
shift started, whole, with everything he earned still in the wallet.

## The reward

A dead rat is merchandise, and whoever buys it wants the whole animal. The price
comes from two things: **what the species is worth** and **what death it died of**.

```
reward = species value × what was left of it after that death
```

Strangulation is the ceiling of the table: strangled, the rat arrives without a
hole in its fur, and that is why the hands pay in full — no weapon will ever earn
more than they do. Every weapon from here on damages the goods a little and takes
it off the price, from poison (which only rots the meat) to crushing (which
leaves barely a rat at all). The table of discounts is in
`scripts/economy/death.gd`, with the types that have no weapon yet already
written and waiting for them: poison, trap, piercing, gunshot and crushing.

**The money lands when that rat's hunt comes to an end**, not when it dies.
Strangled, that means at the waist: between the last squeeze and the body being
stowed away a second still passes, and in it the player has nothing. Killing and
losing the body pays nothing. Killed from a distance, the hunt ends where it
falls, and that is where the account is settled. A rat that gets loose and
escapes, of course, pays nothing at all.

The one that holds the money is the `Wallet`, the project's only autoload — the
map starts over, what was earned on it does not. It announces by signal
(`money_changed`, `catch_recorded`), and who listens is `hud_money.gd`: the
total in the top-right corner, and under it a passing notice with what the last
animal paid and the death it died of.

### The computer in the van

At the back of the van there is a desk with a CRT, and it is the only place where
the money turns back into something. The rear doors are swung wide open and a
ramp runs up to the floor of the cargo bay; inside, looking at the machine puts
`E — use the computer` on screen, and `E` opens the shop. `Esc` or **CLOSE** puts
it away.

While the shop is up the player is out of the map: the mouse comes loose to reach
the buttons and the body stops answering to anything (`set_ui_open` in
`player.gd`). That is not a nicety — the click that buys is the same left click
that grabs a rat, and without the guard it would be spent snatching the camera
back instead of pressing the button under the cursor. Esc is handled by the shop
itself, so it never reaches the player's own mouse toggle.

What is on the shelf is `resources/store/*.tres`, listed on the computer node in
`scenes/shop_computer.tscn`: a name, a line of description, a price and how many
units the money buys. Today it sells the **mousetrap** (three to a box, $25) and
the **rat glue** (two trays, $40). A third thing on the shelf means duplicating a
`.tres` and adding it to the list; no code, and the row shows up on screen on its
own.

The price leaves the `Wallet` (`spend()`) and the units land in the `Stock`, the
project's second autoload, and for the same reason as the first: a box bought on
one shift is still a box on the next. Money and stock are kept apart on purpose —
the wallet counts what was earned, and nothing else.

**The traps do not catch anything yet.** Bought, they hang on the belt, count
down and empty out; what is missing is the object left on the floor that closes
on the rat, with its `Death.Type.TRAP`, and it is built inside `TrapWeapon._use()`
(`scripts/weapons/trap_weapon.gd`).

### How the player reaches for things

The player carries a short ray out of his camera (`Head/Camera/Interact`, 2.2 m)
that only sees the *interactable* layer, so aiming at something costs one ray and
never trips over the scenery or over a rat. Whatever he can put his hands on is
an `Area3D` with `scripts/interaction/interactable.gd`: it says what the prompt
reads and announces `used` when `E` comes, and what that means is the thing's own
business. With a rat kicking in his hands there is nothing to reach for, and the
prompt leaves the screen the same way the crosshair does.

The area is not the object's body — it is the reachable face of it, the screen
and the keyboard and not the desk they sit on. What stops the player walking
through the desk is a static body of its own, on the scenery layer, like
everything else solid in the map.

### The species

Each breed of rat is a file in `resources/species/`: what it is called, what furs
it is born with, what it is worth whole and how much bigger or smaller an animal
can be than the rest of its litter. Today only the **common rat** exists — the
four furs from the pack and ten to the head. A new rat, rarer and pricier, means
duplicating the `.tres` and changing the numbers; no code.

### Where they walk

The rats walk on a navigation mesh baked when the map opens, from the static
bodies in the `scenery` group (`scripts/navigation.gd`). It is what solves the
problem of a rat stuck against a wall: instead of running in the direction of its
hideout and bumping into whatever appears, each one follows a path that already
comes routed around the crates.

Picking the hideout means scoring a dozen candidates — the blind spots behind
nearby obstacles, plus a fan of points behind it. Points go to whatever is far
from the player, whatever vanishes from his line of sight and whatever has a way
out to run afterwards; points are lost by whatever is too far away and, above
all, by whatever can only be reached by grazing past the one doing the hunting. A
candidate inside a crate or on top of a platform that cannot be climbed does not
even enter the reckoning — the path to it does not exist.

There is still one way for the rat to get stuck all the same (pushed off the
mesh, squeezed into a corner): if it spends half a second wanting to walk without
going anywhere, it takes a step sideways and looks for another path.

### The model

The rat is the model in `mobs/rats/`, with a 13-bone skeleton and the animations
that came in the pack: `Rat|Idle`, `Rat|Idle_Break` (the pause in which it sniffs
the air), `Rat|Run`, `Rat|Death` and `Rat|Attack`. The chosen animation follows
the rat's speed, and the run cycle speeds up along with it — wandering it trots,
fleeing it bolts, and held in the hand the same cycle becomes the kicking of its
legs in the air. The bite is the one thing this fearful rat never does loose
about the map: it only shows up once it is already being strangled and has
nothing left to lose.

Each rat rolls one of the four furs from the pack (`Rat.png` to `Rat_4.png`) when
it is born, so the pack comes out mottled with grey, brown and white.

The FBX was exported with the whole Blender scene — the author's light and camera
came along with it, and every animation has tracks pointing at them. What cleans
this up on import is `mobs/rats/clean_import.gd`, a post-import script that also
discards the duplicate animations and marks the idle and the run as looping.

`Rat.blend` is kept as the source file, but what the project imports is
`Rat_Fbx.fbx`. That is why `filesystem/import/blender/enabled` is off in the
project settings: without it Godot tries to open the `.blend` and demands a
Blender installation just to run the game.

## The lobby

The game opens on a waiting room. **CREATE LOBBY** opens one on Steam and makes
you its host; **REFRESH LIST** shows what is open and clicking a row fills in its
ID; **JOIN** walks into whatever ID is in the box, pasted from a friend or picked
off the list. Whoever is in the lobby shows up in the panel on the right, the
host with a `*` against their name, and the list moves as people come and go.
**PLAY** is the host's to press, and everybody goes into the map at once.

Two things are up at the same time and it helps to keep them apart. The **Steam
lobby** is the guest list — Valve holds it, it survives the map loading, and it
is what the panel reads. The **`SteamMultiplayerPeer`** is the wire: Godot's own
`SceneMultiplayer`, running over Steam's peer-to-peer, and what the player
synchronisation will speak over. `scripts/steam/lobby_manager.gd` opens both at
the same moment and closes both at the same moment, so nothing else in the game
has to wonder which of the two is up.

Who hosts is not decided in our code: it is whoever Steam says owns the lobby.
The owner calls `host_with_lobby()` and comes out as peer 1 — the network
authority — and everybody else calls `connect_to_lobby()` and dials them. There
is no host migration, and on purpose: Steam hands a lobby to whoever is left when
the owner walks out, but the connection does not follow, so the honest answer is
to drop everyone back to this screen.

Lobbies are **public**, which is what lets two accounts that have never met find
each other in the list. The catch is the app ID: until RATS has one of its own
the game borrows Valve's Spacewar (480), and a plain search on 480 comes back
full of strangers testing their own games — ten of them, on the first try. So
every lobby is stamped `game=rats` on creation and the browser filters on it. A
lobby just created takes Steam a few seconds to reach the index, so an empty list
right after **CREATE LOBBY** is Steam catching up, not a fault.

Nothing Steam is asked here is answered on the spot. `create_lobby()` and
`join_lobby()` returning true only means the request went out; the answer lands
later on `lobby_entered` or, if it went wrong, on `lobby_failed` — one sentence,
which the screen puts straight on its bottom line in red. A lobby that is full, a
lobby that is gone, an ID that is not a lobby at all, a host that stops answering
and Steam not being there in the first place all come out that way.

### The others, in the map

Press **PLAY** and everybody in the lobby lands in the same map — and everybody
who is not you is walking around it as a red capsule with their Steam name
floating over it. It is the very capsule you are wearing yourself, the one you
never see because you are looking out of it, so the placeholder reads as *a
player* rather than as a prop, and the yellow nub on its chest says which way he
is facing and doubles as the arm he swings.

What crosses the wire is three things, twenty times a second: where he is
standing, which way he is facing and what he is doing. The facing is the yaw
only — where his head is pointing is his own camera's business and nothing on
your screen is drawn from it — and what he is doing is one of five states
(*idle*, *walking*, *running*, *airborne*, *holding a rat*), which the character
reads off his own body rather than off his keyboard: a player walking into a
wall is standing still, whatever he is pressing, and that is what you should see.

On top of that there is the click. Using whatever is in his hands — a grab, a
trap going down — is not a state, it is a thing that happens and is over, so it
goes across as an RPC (`PlayerAvatar.act`) rather than as a value that gets
sampled: one click is one arm going out, on every screen at once, and a click
that lands between two packets is never quietly dropped.

**Nobody is smoothed by teleporting.** What arrives is a target and not a place:
the capsule eases towards the last position that landed rather than jumping to
it, at a rate that leaves it about a third of a metre behind a running player and
lets it catch up the moment he stops. The one thing that is *not* eased is the
long jump — anything further than four metres is a respawn or a hole in the wire,
and sliding across the map to it would read as flying. A capsule is not drawn at
all until the first packet says where its player is, because an undrawn one
stands at the origin, which is a lie the moment somebody looks at it.

The animation is the one part that is honestly a placeholder: a capsule has
nothing to animate, so the body bobs as he walks, harder and faster as he runs,
sits low while he has a rat in his hands and rides high while he is off the
ground. When the real character model arrives, `_animate` is the one method to
throw away — the state itself is already crossing.

Everybody presses **PLAY** on the same starting point, which used to be fine
because nobody moved and the capsules were parked in a ring around it. Now that
the positions are real, each machine steps *its own* character onto a spot in
that same ring on the way in — the peers sorted, ours found among them, the spot
that falls to it taken — and the other screens see him walk out of the van from
there like they see everything else about him. It is also where a respawn brings
him back to, which is why it goes through `player.set_spawn()` and not through a
bare move.

#### Who owns what

Every player owns his own body and nobody else's. The host is peer 1 and holds
the lobby open, and that is all he holds: he has no more say over where you are
standing than you have over where he is. That is what
`set_multiplayer_authority(peer_id)` on each avatar says, and the
`MultiplayerSynchronizer` under it obeys it in both directions — the machine that
owns an avatar writes to it, everybody else reads.

The consequence worth knowing is that there is one avatar per player *including
you*. Godot replicates a node onto the node at the same path on the other
machine, so the only way your position reaches anybody is for there to be a node
on your machine that stands for you — the same node they have for you. So one
goes up for every peer, named `Player<peer id>` on every machine, and yours is
simply never drawn: you are already in the map as the character, and you are
inside that capsule looking out of it. It reads `player.gd` every physics frame
and never touches a packet by hand.

Who puts them up is `scripts/steam/player_avatars.gd`, a node in `world.tscn`,
and it is deliberately not in `LobbyManager`: the manager is an autoload that
outlives the map and is up on the waiting-room screen too, where there is no
world to put a capsule in. So the map is what listens, and the capsules die with
it.

What it listens to is the *wire* and not the guest list — `multiplayer.get_peers()`
rather than `members_changed`. They are nearly the same list, and the wire is the
truthful one: a player who is in the Steam lobby but not on the wire is a body
nothing could ever move.

Names come from the peers themselves. Every peer introduces itself to every other
one the moment they are connected (`LobbyManager._introduce`), which happens on
the waiting-room screen, long before the map opens; a name that lands after the
capsule is already up lands *on* it, through `peer_identified`, without the
capsule being taken down and put back up. It is asked of nobody — not of Steam,
not of the transport — so a name can never come back as `[unknown]`, and nothing
above the wire has to know what the wire is made of.

Solo is untouched by all of it. With no lobby there is no peer, and with no peer
this node puts nothing up and does nothing at all.

### Testing it with two clients

One machine cannot do it: Steam allows one running client per account. Two
accounts on two machines, both with the game open:

1. Both run the game and land on the lobby screen; the bottom line names the
   account each one is signed in as.
2. One presses **CREATE LOBBY**, then **COPY LOBBY ID** and sends the number
   over — or **INVITE FRIENDS**, if they are on each other's lists.
3. The other pastes it and presses **JOIN**, or waits a few seconds and presses
   **REFRESH LIST** to find the row.
4. Both panels should read `PLAYERS 2/4` with the same two names, the host's
   marked. Closing one game takes that name off the other's list.
5. The host presses **PLAY**. Both land in the map, and each sees one capsule
   with the other's name on it, standing by the van.
6. Walk. The capsule on the other screen walks with you — a little behind, never
   in jumps — turns when you turn, bobs when you run and drops low while you have
   a rat in your hands. Click, and its arm goes out on both screens at once.
   Jump, and it leaves the ground.
7. Closing one game takes that capsule off the other's map.

`_test_lobby.gd` covers everything one account can reach on its own — the lobby
opening, the stamp landing, coming out of it as peer 1 with the authority, the
screen drawing the name, the browser finding it through the filter, and the three
ways of getting it wrong. It needs the Steam client signed in:

```
godot --headless --script _test_lobby.gd
```

`_test_sync.gd` covers the half that comes after — the bodies in the map and
everything that crosses the wire to move them — and needs no Steam and no second
machine. It runs the thing one layer down: two `SceneMultiplayer`s over ENet on
the loopback, each rooted at its own subtree, which is as close to two clients as
one process gets. Steam is only ever the transport underneath, and the
replication on top of it is the same either way.

It checks that both sides put up one capsule per player under the same name and
with the authority on the peer it stands for, that your own is never drawn and
somebody else's is not drawn until the first packet lands, that a player walking
on one side is a body walking — *following*, never teleporting, and catching up
when he stops — on the other, that the state crosses and is played, that one
click crosses as exactly one arm going out, that a late name lands on the capsule
already standing there, and that somebody closing their game takes their capsule
away. The last two steps drop the wire entirely and open the real map to check
the solo case: nobody standing about, and the real character answering for
himself.

```
godot --headless --script _test_sync.gd
```

## Structure

- `scenes/` — the game's scenes (`lobby.tscn` is the main scene, the waiting room
  the game opens on, `world.tscn` is the map, `player.tscn` is the character,
  `player_avatar.tscn` is the capsule a player stands as on the other players'
  screens and `rat.tscn` is the mob)
- `scripts/` — GDScript scripts (`player.gd` handles first-person movement,
  `rat.gd` the rats' AI and the capture, `navigation.gd` bakes the mesh they walk
  on, `rat_counter.gd` the HUD scoreboard, `hud_money.gd` the wallet on screen,
  `hud_strangle.gd` the strangling prompt, `hud_hotbar.gd` the belt's three
  slots, `hud_health.gd` the health bar over them, `hud_prompt.gd` the line that
  says what `E` would do and `hud_shop.gd` the computer's screen)
- `scripts/weapons/` — the player's weapons: `weapon.gd` is the base of them all,
  `hands.gd` is the first one, the one that grabs and strangles, `trap_weapon.gd`
  is the one that comes out of a box and runs out, and `inventory.gd` is the belt
  that decides which one is out
- `scripts/interaction/` — `interactable.gd`, the reachable face of anything the
  player can put his hands on
- `scripts/shop/` — `shop_computer.gd`, the machine in the van that carries the
  catalogue
- `scripts/steam/` — everything that talks to Steam: `steam_manager.gd` is the
  autoload that brings the API up and keeps its callbacks flowing, and
  `lobby_manager.gd` the autoload that holds the lobby, the multiplayer peer and
  who each peer on it is; `lobby_screen.gd` is the waiting room drawn on
  `scenes/lobby.tscn`, `player_avatars.gd` is the node in the map that puts up
  one body per player on the wire and `player_avatar.gd` is one of those bodies,
  the piece that reads the character on the machine it belongs to and follows the
  wire on everybody else's
- `scripts/economy/` — the money from the hunt: `death.gd` is the table of death
  types, `rat_species.gd` is the mould of a breed of rat, `store_item.gd` is a
  line on the computer's catalogue, `wallet.gd` is the autoload that holds what
  was earned and `stock.gd` the one that holds what was bought
- `resources/species/` — the breeds of rat, one per file (`common_rat.tres`)
- `resources/store/` — what the computer sells, one per file (`mousetrap.tres`,
  `rat_glue.tres`)
- `assets/computer/` — the desk, the CRT, the tower, the keyboard and the rest of
  the machine in the van
- `models/` — 3D models (`.glb`) and their import files
- `mobs/rats/` — the rat model: `Rat_Fbx.fbx` (mesh, skeleton and animations), the
  four fur textures, the source `Rat.blend` and the post-import script
- `icon.svg` — the project icon

The map is a grey 60x60-unit square, walled in and filled with blocks, crates,
columns, ramps and platforms made of simple geometric shapes — which are also the
rats' hiding places.

Parked on it is the van, which has an interior now: a collision shell around the
cargo bay (floor, sides, roof and a wall closing off the cab), the rear doors
swung wide open and a ramp up to the floor, since the bay stands half a metre off
the ground and the character does not climb a step on its own. The shell is in
the `scenery` group like everything else solid, so the rats' navigation mesh
knows about the van too.

The physics layers are `1: scenery`, `2: player`, `3: rats` and
`4: interactable`. The rats do not bump into the player or into each other; only
the scenery stops them.

The `.godot/` folder is generated by the engine and is not versioned.
