class_name RatSpecies
extends Resource
## A breed of rat: what it is called, what fur it is born with and what it is
## worth.
##
## Each species is a file in `resources/species/`. A new rat in the game means
## duplicating one of those and changing the numbers — no code.
##
## For now the species handles looks, price, the one habit that changes a fight
## — the spraying below — and how hard the animal is to run down. The speeds
## themselves still live on the rat node (`rat.gd`) and there is still only one
## of each: what a breed owns is `swiftness`, the multiple of them it runs at.

@export var display_name := "Rat"
## The furs it can roll at birth. Empty leaves the model's own material alone.
@export var furs: Array[Texture2D] = []

@export_group("Reward")
## The price of the whole animal, before the death discount.
@export var base_value := 10
## How much bigger or smaller one individual can be compared to the rest of its
## species (0.15 = ±15%). At zero every one is worth the same.
@export_range(0.0, 0.5) var variation := 0.0

## What this animal, at this size, is worth killed this way. Never less than 1:
## a crushed rat is still a rat delivered.
func value(death_type: Death.Type, size := 1.0) -> int:
	return maxi(1, roundi(base_value * size * Death.multiplier(death_type)))

## The size of one individual, rolled when it is born.
func roll_size() -> float:
	if variation <= 0.0:
		return 1.0
	return randf_range(1.0 - variation, 1.0 + variation)

## One of the species' furs, or null if it has none.
func roll_fur() -> Texture2D:
	if furs.is_empty():
		return null
	return furs.pick_random()


@export_group("Movement")
## How fast this breed runs from a man, as a multiple of the flight speeds the
## rat node was written with (`rat.gd: flee_speed`, `burst_speed`). It touches
## the flight alone: a wandering rat of any breed pokes about the skirting at the
## same pace, and what the breed changes is the chase.
##
## The number to read it against is not another rat, it is the man: he walks at
## five metres a second and sprints at seven (`player.gd`), and the common rat
## flees at his walking pace. So anything above about 1.1 here is an animal that
## cannot be caught at a walk at all — the crew has to spend the sprint reserve
## on it — and anything at or above 1.4 is one that cannot be caught at all.
@export_range(0.5, 1.35, 0.05) var swiftness := 1.0


@export_group("Habits")
## Zero stays caught until the glue expires; positive values allow escape.
@export_range(0.0, 40.0, 1.0) var glue_escape_seconds := 0.0
## Whether this breed turns and sprays the man chasing it.
##
## It used to be `marks_territory`, and the difference is worth writing down. A
## marking rat dribbled on the boards every nine to sixteen seconds while it
## wandered, which meant the house filled up with piss nobody ever saw an animal
## make — a hazard that arrived by arithmetic. A sprayer leaves exactly as much
## behind, but every mark of it was earned: it is cornered, it stops, it turns,
## and it gets you (`rat.gd::_process_spray`). Same fluid, and the player now
## knows where it came from.
@export var sprays := false

@export_group("Perception")
## How much notice this breed takes of a man who is down on his knees, as a
## fraction of the notice it takes of one walking about. It shortens both the
## distance he is seen from and the distance he is heard from
## (`rat.gd::_alert_radius_for`), so creeping buys ground on every sense the
## animal has.
##
## Never zero, and the range says so. A breed that could not notice a crouching
## man at all would turn the whole hunt into walking up to each animal in turn
## with the key held down; what this buys is a few metres, not invisibility.
@export_range(0.25, 1.0, 0.05) var crouch_notice := 1.0
## The same fraction again, for an animal with its nose in the food. It is the
## rat's own distraction rather than anything the man does, so it multiplies with
## the line above: the creeping is worth most where the animals are eating, which
## is what makes a tub of bait a place worth walking to.
@export_range(0.25, 1.0, 0.05) var feeding_notice := 1.0
