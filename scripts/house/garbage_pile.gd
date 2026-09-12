class_name GarbagePile
extends Node3D
## A heap of rubbish the rats have been living off since long before the van
## pulled up.
##
## Piles are part of the level and nobody puts them there: the bin bags behind
## the kitchen counter, the sacks out in the alley. **The crew does nothing to
## them.** They are worth walking past for two reasons instead:
##
## - **They are where the trails go.** The droppings on the boards are laid along
##   the navigation path from each burrow to the nearest heap
##   (`scripts/house/dropping_trail.gd`), because that is the walk the animals
##   have been making every night. Following the mess gets the crew to a burrow at
##   one end and a bin at the other, and both are worth knowing.
## - **They are nests.** At the top of the hunt the host puts the animals out of
##   the heaps as well as the burrows (`scripts/house/house.gd::_nests`). Rats
##   live where the food is, and a heap of rubbish is where the food already was
##   before anybody bought a tub of bait.
##
## The bait the crew buys is a separate thing and goes wherever the player points
## (`scripts/traps/bait_pile.gd`). It used to be something poured *into* these
## heaps, and that was a worse design for one plain reason: it made the only good
## place to put food a place the level designer had already chosen, so the tub
## bought no decision. Now the rubbish is the reading and the bait is the move.
##
## **It is drawn out of the same rubbish as the floor.** The heap was a black
## crate with three spheres on it, modelled here in the scene, and it was the one
## thing in the house that looked like a placeholder: the boards around it are
## strewn with drawn rubbish (`scripts/house/floor_litter.gd`) and the heap they
## all lead to was geometry. It is built now out of those same pieces, stacked,
## so a heap is what it says it is — more of the rubbish, in one place.

## How far a rat feels a heap of rubbish from. Shorter than a fresh tub of bait
## (`BaitPile.lure_reach`): week-old rubbish is where they already go, not
## something that pulls them off what they were doing.
const LURE_RADIUS := 12.0

## How many pieces of rubbish make a heap, how wide it spreads on the floor and
## how high it stacks, in metres.
##
## Enough pieces and tight enough that it reads as one thing from across a room:
## the scattering outside puts a piece every five square metres, so a dozen of
## them inside half a metre is a density nothing else in the house has, and that
## contrast is the whole of what makes a heap findable.
const PIECES := 12
const HEAP_RADIUS := 0.42
const HEAP_HEIGHT := 0.45

## The pieces on top sit nearer the middle, which is what makes a heap a heap and
## not a column: this is how far in the topmost one is pulled. Below one the
## stack would lean out and read as rubbish glued to a pole.
const HEAP_TAPER := 0.8


func _ready() -> void:
	add_to_group("garbage")
	# Rubbish pulls, like food pulls, and for the same reason — it *is* food, only
	# older. What it is not is a decision anybody made this shift.
	add_to_group("lures")
	_build()


## How far this heap pulls from. It is the one thing the `lures` group asks of
## whatever joins it (`rat.gd::_nearest_lure`).
func lure_radius() -> float:
	return LURE_RADIUS


## Stacks the heap, once, when the level opens.
##
## **The rolls are seeded off where the heap stands and not off the shift.** A
## heap is level furniture: a designer put it in that corner and it should look
## the same to everybody in the house and the same again next week, exactly as
## the crate it replaces did. Seeding it off `SessionManager.random_seed` would
## have reshuffled the bin bags every contract for no reading, and seeding it off
## nothing would have given the two machines in a co-op game two different heaps
## in the same corner.
##
## The pieces do not react to a passing boot (`trigger_radius`). One piece of
## rubbish hopping as a man walks by is the house being alive; a dozen of them
## going off together in one corner is a noise, and the heap never had a hop to
## lose.
func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(global_position)
	for _piece in PIECES:
		var sprite := FloorLitter.piece(rng)
		if sprite == null:
			return
		sprite.trigger_radius = 0.0
		# Up the heap first, then out from the middle by whatever is left: the
		# square root spreads the low pieces over the floor evenly instead of
		# crowding them at the centre, and the taper brings the high ones in.
		var up := rng.randf()
		var out := HEAP_RADIUS * sqrt(rng.randf()) * (1.0 - up * HEAP_TAPER)
		var around := rng.randf_range(0.0, TAU)
		sprite.position = Vector3(
			cos(around) * out,
			up * HEAP_HEIGHT + sprite.drawn_height() * 0.5,
			sin(around) * out)
		add_child(sprite)
