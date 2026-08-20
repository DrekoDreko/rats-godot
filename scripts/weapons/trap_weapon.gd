class_name TrapWeapon
extends Weapon
## A weapon that runs out: it comes out of a box bought at the computer, and
## every use takes one out of the box.
##
## What it has that the hands do not is a *count*. The box lives in the `Stock`
## autoload under `stock_id`, the same string the catalogue item carries
## (`scripts/economy/store_item.gd`), so buying and spending never have to know
## about each other: the shop credits the id, this spends it, and the belt and
## the hotbar follow the signal. Empty, the weapon says it is not available and
## its slot goes back to being an empty loop on the belt.
##
## What it does *not* do yet is catch anything. Using one spends the unit and
## makes the gesture, and that is the whole of it — the trap that stays behind on
## the floor, with its `Death.Type.TRAP`, is the next thing to be built, and it
## is built inside `_use()`.

## The key of the box this weapon comes out of.
@export var stock_id := ""

## There is a weapon here for as long as there is one left in the box.
func available() -> bool:
	return not stock_id.is_empty() and Stock.count(stock_id) > 0

## Takes one out of the box and puts it down.
##
## The box is emptied last, and on purpose: taking the final one out makes the
## belt put the weapon away on the spot (`Inventory._on_stock_changed`), and a
## gesture started after that would be a tween left running on a weapon nobody is
## holding any more.
func _use() -> void:
	if Stock.count(stock_id) <= 0:
		return
	_animate_swing()
	# No trap on the floor yet, so nothing was caught — the click is honest about
	# it, and the HUD hears the same thing it hears from a swing that missed.
	used.emit(false)
	Stock.spend_one(stock_id)
