class_name BaitWeapon
extends TrapWeapon
## The tub of bait. One click leaves a handful of food on the boards wherever the
## player is pointing (`scripts/traps/bait_pile.gd`).
##
## Everything about aiming at the floor, showing the pile-to-be and asking the
## host for it belongs to `TrapWeapon` and is shared with the traps. What is left
## over is one click and no state in between, which is the whole of this file.


## Puts one down where the player is pointing.
##
## A click with nowhere to put it is an honest miss: the gesture happens, the
## click announces that nothing landed, and the tub stays in the bag. The unit
## only leaves it when the host has agreed (`TrapManager._debit`).
func _use() -> void:
	if Stock.count(stock_id) <= 0:
		return
	var spot := _ground_point()
	_animate_swing()
	var landed := spot != INVALID_POINT
	used.emit(landed)
	if not landed:
		return
	_place(spot, _facing())
