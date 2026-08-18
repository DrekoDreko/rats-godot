# RATS

3D game made in Godot 4.7 (Forward Plus, Jolt Physics).

## Running the project

1. Install [Godot 4.7](https://godotengine.org/download).
2. Open Godot, click **Import** and pick this repository's `project.godot`.
3. Run with `F5`.

## Controls

| Key | Action |
| --- | --- |
| `WASD` / arrows | Move (relative to where you are looking) |
| `Shift` | Run |
| `Space` | Jump |
| Mouse | Look around |
| Left button | Grab the rat |
| Left button (with a rat in hand) | Strangle |
| `Esc` | Release/recapture the mouse |

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
(`money_changed`, `catch_recorded`) to whoever wants to show it on screen.

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

## Structure

- `scenes/` — the game's scenes (`world.tscn` is the main scene, `player.tscn` is
  the character and `rat.tscn` is the mob)
- `scripts/` — GDScript scripts (`player.gd` handles first-person movement,
  `rat.gd` the rats' AI and the capture, `navigation.gd` bakes the mesh they walk
  on, `rat_counter.gd` the HUD scoreboard and `hud_strangle.gd` the strangling
  prompt)
- `scripts/weapons/` — the player's weapons: `weapon.gd` is the base of them all
  and `hands.gd` is the first one, the one that grabs and strangles
- `scripts/economy/` — the money from the hunt: `death.gd` is the table of death
  types, `rat_species.gd` is the mould of a breed of rat and `wallet.gd` is the
  autoload that holds what was earned
- `resources/species/` — the breeds of rat, one per file (`common_rat.tres`)
- `models/` — 3D models (`.glb`) and their import files
- `mobs/rats/` — the rat model: `Rat_Fbx.fbx` (mesh, skeleton and animations), the
  four fur textures, the source `Rat.blend` and the post-import script
- `icon.svg` — the project icon

The map is a grey 60x60-unit square, walled in and filled with blocks, crates,
columns, ramps and platforms made of simple geometric shapes — which are also the
rats' hiding places.

The physics layers are `1: scenery`, `2: player` and `3: rats`. The rats do not
bump into the player or into each other; only the scenery stops them.

The `.godot/` folder is generated by the engine and is not versioned.
