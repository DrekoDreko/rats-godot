class_name Interactable
extends Area3D
## Something in the world the player can put his hands on: he looks at it, the
## prompt shows up on screen and `E` does whatever it is that the thing does.
##
## The player carries a short `RayCast3D` out of his camera
## (`Head/Camera/Interact`) that only sees these areas — layer 4, and nothing
## else is on it, so aiming at an interactable costs one ray and never trips over
## the scenery or over a rat.
##
## The area is not the object's body: it is the *reachable face* of it, the
## screen and the keyboard of the computer and not the desk they sit on. Whatever
## has to stop the player from walking through it is a static body of its own,
## on the scenery layer, like every other solid thing in the map.
##
## What the thing does when used is nobody's business here: it announces `used`
## and whoever cares listens (see `scripts/shop/shop_computer.gd`).

## Somebody used it. `by` is the player who did.
signal used(by: Node3D)

## What the on-screen prompt reads, after the key: "E — use the computer".
@export var prompt := "use"
## How long the key has to be held down before it counts. Zero is a thing that
## answers to a tap, which is what most of them are — the computer opens the
## instant it is asked. Anything above zero is work: the player stands there with
## his finger down and a bar on screen, and letting go throws it away.
@export var hold_time := 0.0

## Whether this is one of the slow ones. The player asks before deciding what a
## press of the key even means (`player.gd: _update_hold`).
func is_held_work() -> bool:
	return hold_time > 0.0

## Hands on. It is the only door in: the player calls it, and the thing itself
## decides what that means.
func use(by: Node3D) -> void:
	used.emit(by)
