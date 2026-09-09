class_name BaitPile
extends Node3D
## A handful of food the crew leaves on the boards to bring the rats to it.
##
## It is the mirror of a sprung mousetrap. A trap that has gone off with a body
## in it joins the `fear` group and the rats give that patch of floor a wide
## berth for the rest of the shift (`scripts/traps/mousetrap.gd`); this joins
## `lures`, and a rat with nothing more urgent on its mind drifts back towards it
## instead (`rat.gd::_nearest_lure`).
##
## **It catches nothing and it is not a `Trap`.** There is no `Area3D` here, no
## body watching, nothing to spring: a pile of food is a *preference* written on
## the map, and every rule about it lives in the rat that smells it. What that
## buys is that the pile can be dropped anywhere the player can point at without
## having to be right about anything — a bait in the middle of a room is exactly
## as valid as one tucked against a burrow, and where the good spots are is the
## player's problem and not this file's.
##
## **It is put down the way a trap is**, because that part is the same problem:
## the player asks, the host checks the phase and the bag, and the node arrives
## on every machine through the `MultiplayerSpawner` over `Traps`
## (`scripts/session/trap_manager.gd`). A pile that existed on one screen and not
## on another would be rats walking towards nothing on three machines out of four.
##
## It is not used up. The food sits there for the rest of the shift, and what the
## player spent was the tub — dropping bait is choosing where the hunt happens,
## which is a decision he should be able to see the consequences of for longer
## than one animal.

## Who put it down. Written by the host before the pile enters the tree
## (`TrapManager._build_trap`), so it crosses with the node. Zero for one that
## nobody placed — a pile dropped straight into a scene by a test bench.
@export var placed_by := 0

## Which box in the van this came out of. The same string the catalogue item
## carries in its `id` and the weapon carries in its `stock_id`, written on the
## scene so the three never drift apart in three files.
@export var stock_id := ""

## How far the smell carries, in metres across the floor. It is generous on
## purpose: the point of putting food down is that the animals come to it from
## the next room, not that one walks into it by accident.
@export var lure_reach := 22.0


func _ready() -> void:
	add_to_group("lures")


## How far a rat feels this pile from. It is the one thing the `lures` group asks
## of whatever joins it (`rat.gd::_nearest_lure`), and it is the mirror of
## `fear_radius` on a sprung trap.
func lure_radius() -> float:
	return lure_reach
