class_name Trap
extends Area3D
## Something the player leaves on the floor for the rats to walk into.
##
## A trap is an `Area3D` and nothing more: it does not move, it does not think,
## and it has no body to be bumped into. It watches the rats' layer, and the
## first rat to step inside it is the one it does something to — what, is
## `_catch_rat()`'s business, and it is the only thing that changes from one trap
## to the next.
##
## What every trap has in common is that it is *used up*. It catches one rat and
## it is over: the mousetrap goes off, the glue holds what it caught until
## somebody comes for it, and neither of them is ever going to catch a second
## one.
##
## A trap is deliberately **not** in the `scenery` group. The navigation mesh is
## baked from that group (`scripts/navigation.gd`), and a trap that joined it
## would be baked into the floor as an obstacle — the rats would route politely
## around every trap the player ever set, which is exactly the opposite of the
## point of setting one.
##
## What a trap may do, once it has caught something and is holding on to it, is
## join the `fear` group: the rats then give that patch of floor a wide berth
## until somebody comes and clears it (`scripts/traps/mousetrap.gd`). That is a
## preference and not geometry, which is the whole difference — the flight can
## still cross bad ground when there is nowhere else to go.
##
## None of this is replicated. Traps are put down locally, the rats think locally,
## and so what one player cleans up, only his own rats ever find out about.

## Caught something. `rat` is whatever walked in.
signal caught(rat: Node3D)

## Which box in the van this came out of (`scripts/economy/stock.gd`), so a trap
## that ends up back in the player's hands knows where to put itself. It is the
## same string the weapon that sets it carries in its `stock_id`, and it is set
## on the scene rather than written into the script so the two never drift apart
## in two files.
@export var stock_id := ""

## Only the rats set a trap off (layer 3).
const RAT_MASK := 4

## Still waiting for something. A trap that has caught its rat is furniture.
var _armed := true
## What it caught, for as long as it still holds it.
var _prey: Node3D

func _ready() -> void:
	add_to_group("traps")
	# Nothing collides *with* a trap: it is a patch of floor that notices things,
	# and the player walks over it without feeling it.
	collision_layer = 0
	collision_mask = RAT_MASK
	monitoring = true
	body_entered.connect(_on_body_entered)

## Whether this trap is still waiting for a rat.
func is_armed() -> bool:
	return _armed

## What it is holding, or null. Only the traps that *hold* anything ever have one.
func prey() -> Node3D:
	return _prey

func _on_body_entered(body: Node3D) -> void:
	if not _armed or not body.is_in_group("rats"):
		return
	# A body already spoken for is nobody's catch: one that died on its way here,
	# and one being carried over the trap in somebody's hand.
	if body.has_method("is_dead") and body.is_dead():
		return
	if body.has_method("is_captured") and body.is_captured():
		return
	_armed = false
	_prey = body
	_catch_rat(body)
	caught.emit(body)

## What this trap does to what it caught. Every trap overrides this.
func _catch_rat(_rat: Node3D) -> void:
	pass

## The rat this trap was holding is gone — killed on it, or torn off it by hand.
## It is the door `rat.gd: unpin()` knocks on, and only a trap that *holds*
## something has anything to do about it.
func released(_rat: Node3D) -> void:
	pass
