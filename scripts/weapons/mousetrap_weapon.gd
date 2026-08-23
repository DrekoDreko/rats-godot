class_name MousetrapWeapon
extends TrapWeapon
## The box of mousetraps. One click sets one down on the floor in front of the
## player, armed, and that is the whole of it — from there the trap does its own
## waiting (`scripts/traps/mousetrap.gd`).
##
## It is the simplest thing a trap weapon can be, and it is here mostly to show
## where the line falls: everything about *finding the floor* and *showing what
## would land there* belongs to `TrapWeapon` and is shared with the glue. What is
## left over — one click, one trap, no state in between — is the whole of this
## file.

## Puts one down where the player is pointing.
##
## A click with nowhere to put it is an honest miss: the gesture happens, the
## click announces that it caught nothing, and the box keeps its trap. Nobody
## loses a mousetrap to a wall.
##
## A click he cannot pay for is the same kind of miss. A trap that came back off
## the floor wants a new spring before it will hold anything, and the price has
## been hanging over the sights in red for as long as he has been pointing at
## the boards — the click changes nothing, and the bent trap stays in the bag.
func _use() -> void:
	if Stock.count(stock_id) <= 0:
		return
	var spot := _ground_point()
	_animate_swing()
	var landed := spot != INVALID_POINT and _can_afford()
	used.emit(landed)
	if not landed:
		return
	# The money first: it is the one thing here that can still say no, and it
	# says so before anything is on the floor.
	if not _charge():
		return
	_place(spot, _facing())
	# Last, and on purpose: see the note on the box in `trap_weapon.gd`.
	Stock.spend_one(stock_id)
