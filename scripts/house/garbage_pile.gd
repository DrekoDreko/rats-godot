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

## How far a rat feels a heap of rubbish from. Shorter than a fresh tub of bait
## (`BaitPile.lure_reach`): week-old rubbish is where they already go, not
## something that pulls them off what they were doing.
const LURE_RADIUS := 12.0


func _ready() -> void:
	add_to_group("garbage")
	# Rubbish pulls, like food pulls, and for the same reason — it *is* food, only
	# older. What it is not is a decision anybody made this shift.
	add_to_group("lures")


## How far this heap pulls from. It is the one thing the `lures` group asks of
## whatever joins it (`rat.gd::_nearest_lure`).
func lure_radius() -> float:
	return LURE_RADIUS
