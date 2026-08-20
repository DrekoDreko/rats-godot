extends Node
## What the player has bought and not yet spent: how many of each supply is left
## in the van.
##
## The second autoload, and for the same reason as the first (`wallet.gd`): a
## box of traps bought on one shift is still a box of traps on the next, and the
## map starting over does not empty it. Money and stock are kept apart on
## purpose — the wallet counts what was earned, and nothing else.
##
## Everything here is keyed by the item's `id` (see
## `scripts/economy/store_item.gd`), the same string the weapon on the belt
## carries in its `stock_id`. Whoever credits is the shop
## (`scripts/hud_shop.gd`); whoever spends is the weapon, one unit at a time.

## An item's count changed. It goes out on the purchase and on the use alike,
## and it is what the belt and the hotbar follow.
signal changed(id: String, count: int)

## How much of each item is left. An id that was never bought is simply absent,
## and reads as zero.
var _counts: Dictionary[String, int] = {}

## How many are left of an item.
func count(id: String) -> int:
	return _counts.get(id, 0)

## Credits a purchase. A count that does not go up announces nothing.
func add(id: String, amount: int) -> void:
	if id.is_empty() or amount <= 0:
		return
	_counts[id] = count(id) + amount
	changed.emit(id, _counts[id])

## Takes one unit out. Returns false with the box already empty, and in that case
## nothing is spent.
func spend_one(id: String) -> bool:
	var left := count(id)
	if left <= 0:
		return false
	_counts[id] = left - 1
	changed.emit(id, _counts[id])
	return true

## Wipes everything, the way `Wallet.reset()` does: the start of a shift, and the
## start of every test bench. Each id that had something announces its zero, so
## nothing on screen is left showing a stock that no longer exists.
func reset() -> void:
	var ids := _counts.keys()
	_counts.clear()
	for id in ids:
		changed.emit(id, 0)
