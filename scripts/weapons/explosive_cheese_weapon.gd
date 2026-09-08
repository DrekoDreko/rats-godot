class_name ExplosiveCheeseWeapon
extends TrapWeapon
## A box of explosive cheese. One click puts a bait on the floor; the host owns
## the placement and the blast when a rat reaches it.


## Places one bait where the player is pointing. The unit stays in the box until
## the host accepts the request, just like the other floor traps.
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
