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

## Hands on. It is the only door in: the player calls it, and the thing itself
## decides what that means.
func use(by: Node3D) -> void:
	used.emit(by)
