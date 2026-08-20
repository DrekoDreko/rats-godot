class_name Inventory
extends Node
## The player's belt: the weapons he carries and which one is in his hands.
##
## Three slots, swapped with `1`, `2` and `3`. A slot can be empty — the loop on
## the belt is already there, the weapon just has not arrived yet — and an empty
## slot is a player with nothing in his hands: he still walks and looks around,
## but the click finds nothing to do.
##
## The belt does not own the weapons. Every weapon goes on hanging off the
## player's head, where it can reach the camera and the capture point
## (`scripts/weapons/weapon.gd`); this node only points at them and decides
## which one is out. What it takes care of is the *swap*: putting the last one
## away — the swing halfway through, the shake left in the camera — before the
## next one comes out.
##
## The one rule of the belt is that a busy weapon does not go away. With a rat
## kicking in your hand there is no reaching for anything else.
##
## A slot can also *run out*: a weapon that comes out of a box says it is not
## available once the box is empty (`Weapon.available()`), and from then on its
## loop on the belt is as empty as one that never had anything on it. The belt
## follows the stock while the player is standing there — buying at the computer
## with that slot already picked puts the weapon in his hand on the spot, and
## spending the last one takes it away the same way.
##
## In the scene this node comes *after* every weapon it points at: it puts them
## all away as soon as it is ready, and a weapon that has not run its own
## `_ready` yet has no camera to give back and no resting rotation to return to.

## The equipped slot changed. `weapon` comes in null on an empty slot.
signal equipped(index: int, weapon: Weapon)

## One weapon per slot, in order. An empty path is an empty slot.
@export var slots: Array[NodePath] = []

var _index := 0
var _current: Weapon

func _ready() -> void:
	# Everything goes away first, so the belt does not start with three weapons
	# processing at once, and then the first slot comes out.
	for weapon in weapons():
		weapon.unequip()
	_index = 0
	_current = _pick(0)
	if _current != null:
		_current.equip()
	Stock.changed.connect(_on_stock_changed)
	equipped.emit(_index, _current)

## Swaps to a slot. Returns false when it could not be done: there is no such
## slot, it is the one already out, or the weapon in hand is busy.
func equip(index: int) -> bool:
	if index < 0 or index >= slot_count() or index == _index:
		return false
	if is_busy():
		return false
	if _current != null:
		_current.unequip()
	_index = index
	_current = _pick(index)
	if _current != null:
		_current.equip()
	equipped.emit(_index, _current)
	return true

## The weapon in hand, or null with an empty slot out.
func current() -> Weapon:
	return _current

## Which slot is out.
func index() -> int:
	return _index

func slot_count() -> int:
	return slots.size()

## The weapon in a slot, or null if the slot is empty or does not exist.
func weapon_in(index: int) -> Weapon:
	if index < 0 or index >= slots.size():
		return null
	var path := slots[index]
	if path.is_empty():
		return null
	return get_node_or_null(path) as Weapon

## The weapon a slot actually puts in the hand: the one it points at, unless that
## one has run out — an empty box is an empty loop.
func _pick(index: int) -> Weapon:
	var weapon := weapon_in(index)
	if weapon == null or not weapon.available():
		return null
	return weapon

## The stock moved. Only the slot the player is standing on is affected: the
## others will be read when he swaps to them. With a rat in hand nothing changes
## either — the belt is locked, and it is read again on the way out.
func _on_stock_changed(_id: String, _count: int) -> void:
	if is_busy():
		return
	var weapon := _pick(_index)
	if weapon == _current:
		return
	if _current != null:
		_current.unequip()
	_current = weapon
	if _current != null:
		_current.equip()
	equipped.emit(_index, _current)

## Every weapon on the belt, skipping the empty slots. It is what the player
## uses to wire up their signals, once, at the start — a weapon that has run out
## is still on the belt, and still has to be listened to for when it comes back.
func weapons() -> Array[Weapon]:
	var found: Array[Weapon] = []
	for i in slots.size():
		var weapon := weapon_in(i)
		if weapon != null:
			found.append(weapon)
	return found

# --- Relays to the weapon in hand ------------------------------------------
# With an empty slot out there is nothing to relay to, and every one of these
# quietly does nothing.

func is_busy() -> bool:
	return _current != null and _current.is_busy()

func try_use() -> void:
	if _current != null:
		_current.try_use()

func press_secondary() -> void:
	if _current != null:
		_current.press_secondary()
