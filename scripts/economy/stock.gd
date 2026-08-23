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
##
## Not everything in the bag was bought, though. A mousetrap scraped off the
## floor comes back through `salvage()` and is counted twice — once as a unit
## like any other, and once as one that is bent and will want parts before it
## works again. Nothing on the belt or the hotbar cares about the difference;
## the only one who asks is whoever charges for setting it back down.

## An item's count changed. It goes out on the purchase and on the use alike,
## and it is what the belt and the hotbar follow.
signal changed(id: String, count: int)

## How much of each item is left. An id that was never bought is simply absent,
## and reads as zero.
var _counts: Dictionary[String, int] = {}

## How many of what is left came back off the floor rather than out of a box. It
## is a subset of `_counts` and never larger than it: a salvaged unit is a unit
## like any other as far as the belt and the hotbar are concerned, and the only
## thing that ever asks is whoever charges for putting it back down.
##
## They are spent first (`spend_one`). Two reasons, and the second is the real
## one: the bent trap in the player's bag is the one he ought to be using up, and
## a player looking at a price on his sights should be able to make it go away by
## spending it, not have it hang there behind three good traps he bought.
var _salvaged: Dictionary[String, int] = {}

## How many are left of an item.
func count(id: String) -> int:
	return _counts.get(id, 0)

## How many of those came back off the floor, bent and needing parts.
func salvaged(id: String) -> int:
	return _salvaged.get(id, 0)

## Whether the next one out of the bag is a salvaged one, and so whether putting
## it down is going to cost anything.
func next_is_salvaged(id: String) -> bool:
	return salvaged(id) > 0

## Credits a purchase. A count that does not go up announces nothing.
func add(id: String, amount: int) -> void:
	if id.is_empty() or amount <= 0:
		return
	_counts[id] = count(id) + amount
	changed.emit(id, _counts[id])

## Credits one that came back off the floor. It joins the count like anything
## else and is marked as the salvage it is.
func salvage(id: String) -> void:
	if id.is_empty():
		return
	_salvaged[id] = salvaged(id) + 1
	add(id, 1)

## Takes one unit out, the salvaged ones first. Returns false with the box
## already empty, and in that case nothing is spent.
func spend_one(id: String) -> bool:
	var left := count(id)
	if left <= 0:
		return false
	_counts[id] = left - 1
	var bent := salvaged(id)
	if bent > 0:
		_salvaged[id] = bent - 1
	changed.emit(id, _counts[id])
	return true

## Wipes everything, the way `Wallet.reset()` does: the start of a shift, and the
## start of every test bench. Each id that had something announces its zero, so
## nothing on screen is left showing a stock that no longer exists.
func reset() -> void:
	var ids := _counts.keys()
	_counts.clear()
	_salvaged.clear()
	for id in ids:
		changed.emit(id, 0)
