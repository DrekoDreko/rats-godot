class_name Inventory
extends Node
## The player's belt: the weapons he carries and which one is in his hands.
##
## Three slots, swapped with `1`, `2` and `3`, and the hands, which are not one
## of them. A slot is bought: it stands for a weapon off the shelf's catalogue,
## and until the first box of it arrives the loop on the belt hangs there empty
## — an empty slot is a player with nothing in his hands, who still walks and
## looks around, but whose click finds nothing to do.
##
## **No loop belongs to any one thing.** The belt is set up with a number of
## loops (`slot_capacity`) and nothing else: what hangs from each is worked out
## from the bag (`scripts/economy/stock.gd`), in the order the things were
## bought. The first purchase of the shift takes loop one whatever it was, the
## second takes loop two, and a shelf that grows a ninth item needs nothing
## changed here — only a weapon node under the head with the name its catalogue
## entry asks for (`StoreItem.weapon_node`).
##
## A loop is given up again when the last unit of what hangs from it is spent,
## so that the next thing bought has somewhere to go. Picking a bent trap back
## off the floor puts it on the belt again, on whichever loop is free by then —
## not necessarily the one it had.
##
## Buying past the last free loop credits the bag like any other purchase and
## hangs nothing: the goods are in the van, and they reach the belt as soon as
## something else runs out.
##
## The hands take no slot because they were never bought. They are always there,
## and `Q` is what puts them back (`hands_path`): whatever the belt is showing,
## the player is one key away from having his own two hands out again. While
## they are the ones out, `index()` reads `HANDS_INDEX` and no square on the
## hotbar is framed — there is no square for them to frame.
##
## The belt does not own the weapons. Every weapon goes on hanging off the
## player's head, where it can reach the camera and the capture point
## (`scripts/weapons/weapon.gd`); this node only points at them and decides
## which one is out. What it takes care of is the *swap*: putting the last one
## away — the swing halfway through, the shake left in the camera — before the
## next one comes out.
##
## The one rule of the belt is that a busy weapon does not go away. With a rat
## kicking in your hand there is no reaching for anything else, and no reaching
## for the hands either — they are already full.
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

## The equipped slot changed. `weapon` comes in null on an empty slot, and
## `slot` comes in `HANDS_INDEX` when what is out is the hands.
##
## Named `slot` and not `index` because `index()` is a method on this class, and
## a parameter wearing a method's name shadows it for every closure that takes
## the signal.
signal equipped(slot: int, weapon: Weapon)

## A slot was asked for and the belt would not give it. It is what a station or
## a HUD plays a buzzer off — the belt itself makes no noise.
signal refused(slot: int)

## What `index()` reads while the hands are out. It is no slot at all: it sits
## before the first one on purpose, so everything that walks the belt by index
## skips it.
const HANDS_INDEX := -1

## How many loops the belt has. It is the number of keys that swap to it (`1`,
## `2` and `3`) and the number of squares the hotbar draws, and it is the whole
## of what the belt is set up with: which weapon hangs from which loop is not
## dressed in the scene, it is whatever the player bought.
@export var slot_capacity := 3

## Where the weapons hang. Every `Weapon` under this node is one the belt can
## put on a loop, found by the name the catalogue asks for
## (`StoreItem.weapon_node`). The default is the player's head, which is where
## every weapon in the game already lives — camera, reach and capture point are
## all measured from there (`scripts/weapons/weapon.gd`).
@export var weapons_root: NodePath = ^".."

## One weapon per loop, in order. An empty path is an empty loop. The hands do
## not belong here — they are not on the belt.
##
## It is filled at runtime off the bag (`_take_stock`) and not in the editor: a
## loop belongs to whatever was bought for it. It is left public because a bench
## sometimes hangs a weapon on the belt by hand, without any shop to buy it from
## (`_test_survey_house.gd`).
var slots: Array[NodePath] = []
## The hands: the weapon `Q` always brings back, and the one the shift starts
## with. An empty path is a player who has none, and `Q` then does nothing.
@export var hands_path: NodePath

## Slots the belt will not give out, whatever is hanging on them. Empty is a
## belt that works normally, which is what it is for most of a shift.
##
## It is here rather than in whatever phase wants the lock because the belt is
## the one thing that already knows how to put a weapon away and bring the hands
## back — a station reaching in to unequip things itself would be a second place
## that has to get the swap right. The van in the lobby bars every slot (nothing
## is carried in there but a pair of hands), and the survey will bar only the
## ones that kill.
##
## The hands are never barred. They were never bought, they are what `Q` brings
## back, and a player with no hands is a player who cannot do anything at all.
var _barred: Array[int] = []

var _index := HANDS_INDEX
var _current: Weapon
var _refusal_audio: AudioStreamPlayer

func _ready() -> void:
	# The loops come first: empty ones, as many as the belt was built with. What
	# hangs from them is read off the bag below — a shift starting with goods
	# already in the van is a belt that starts with them on it.
	slots.resize(maxi(0, slot_capacity))
	slots.fill(NodePath())

	# Everything goes away first, so the belt does not start with three weapons
	# processing at once, and then the hands come out — nothing has been bought
	# yet, and they are all the player has.
	for weapon in weapons():
		weapon.unequip()
	_take_stock()
	_index = HANDS_INDEX
	_current = hands()
	if _current != null:
		_current.equip()
	Stock.changed.connect(_on_stock_changed)
	_refusal_audio = AudioStreamPlayer.new()
	_refusal_audio.name = "RefusalAudio"
	_refusal_audio.stream = _build_refusal_beep()
	_refusal_audio.volume_db = -12.0
	add_child(_refusal_audio)
	equipped.emit(_index, _current)

## Swaps to a slot. Returns false when it could not be done: there is no such
## slot, it is the one already out, the weapon in hand is busy, or the phase has
## barred it.
func equip(slot: int) -> bool:
	if slot < 0 or slot >= slot_count() or slot == _index:
		return false
	if holds_belt():
		return false
	if is_barred(slot):
		if _refusal_audio != null:
			_refusal_audio.play()
		refused.emit(slot)
		return false
	_swap_to(slot, _pick(slot))
	return true


## Bars all attack weapons (weapons that damage or kill rats), keeping traps,
## bait, patches, map, and flashlight free. Used during the SURVEY phase.
func bar_attack_weapons() -> void:
	var barred: Array[int] = []
	for i in slot_count():
		var weapon := weapon_in(i)
		if weapon != null and weapon.is_attack_weapon():
			barred.append(i)
	bar_slots(barred)


## Bars a set of slots and puts the hands back if what was out is now barred.
## Passing an empty array is what lifts the lock again.
##
## The whole set is handed over at once rather than one slot at a time on
## purpose: a phase knows what may be carried in it, and reading that off one
## call means there is never a moment where half the lock is on.
func bar_slots(indices: Array[int]) -> void:
	_barred = indices.duplicate()
	if _index != HANDS_INDEX and is_barred(_index):
		# Not `equip_hands()`: that refuses while the hands are full, and a belt
		# being locked with a rat in them should still end up on the hands once
		# the rat is gone. It is the same swap, without the guard that does not
		# apply here.
		_swap_to(HANDS_INDEX, hands())


## Whether the phase has barred a slot.
func is_barred(slot: int) -> bool:
	return _barred.has(slot)


## Whether anything at all is barred — what a hotbar asks before it greys itself
## out.
func has_bars() -> bool:
	return not _barred.is_empty()

## Puts the hands back, whatever the belt was showing. Returns false when they
## were already out, when the player has none, or when they are full — a rat in
## the hand is the hands already being used.
func equip_hands() -> bool:
	if _index == HANDS_INDEX or holds_belt():
		return false
	var weapon := hands()
	if weapon == null:
		return false
	_swap_to(HANDS_INDEX, weapon)
	return true

## The weapon in hand, or null with an empty slot out.
func current() -> Weapon:
	return _current

## Which slot is out, or `HANDS_INDEX` for the hands.
func index() -> int:
	return _index

## Whether what is out is the hands and not a slot.
func hands_out() -> bool:
	return _index == HANDS_INDEX

func slot_count() -> int:
	return slots.size()

## The hands, or null if the player has none.
func hands() -> Weapon:
	if hands_path.is_empty():
		return null
	return get_node_or_null(hands_path) as Weapon

## The weapon in a slot, or null if the slot is empty or does not exist.
func weapon_in(slot: int) -> Node:
	if slot < 0 or slot >= slots.size():
		return null
	var path := slots[slot]
	if path.is_empty():
		return null
	var node := get_node_or_null(path)
	if node != null and node.has_method("try_use"):
		return node
	return node as Weapon

## The weapon a slot actually puts in the hand: the one it points at, unless it
## has not been bought yet or has run out — an empty box is an empty loop.
func _pick(slot: int) -> Weapon:
	var weapon := weapon_in(slot)
	if weapon == null or not weapon.available():
		return null
	return weapon

## Puts one weapon away and the next one out, and says so. It is the only place
## that moves the belt: whoever calls it has already decided the swap is allowed.
func _swap_to(slot: int, weapon: Weapon) -> void:
	if _current != null:
		_current.unequip()
	_index = slot
	_current = weapon
	if _current != null:
		_current.equip()
	equipped.emit(_index, _current)

## The stock moved. The hands do not come out of any box, so with them out
## there is nothing to re-read; otherwise only the slot the player is standing
## on is affected — the others will be read when he swaps to them. With a rat in
## hand nothing changes either: the belt is locked, and it is read again on the
## way out.
func _on_stock_changed(_id: String, _count: int) -> void:
	# The loops are worked out before anything is put in a hand: a purchase can
	# be the first of its kind, and the weapon it belongs to has nowhere to be
	# picked from until it hangs somewhere.
	_take_stock()
	if hands_out() or is_busy():
		return
	var weapon := _pick(_index)
	if weapon == _current:
		return
	_swap_to(_index, weapon)


## Hangs on the belt whatever the van has goods for, and takes off whatever it
## has run out of. It is the whole of how a loop is filled: read off the bag and
## the shelf's catalogue, never dressed in the scene.
##
## Order is the catalogue's on the way up — a shift that starts with three
## things already bought hangs them the way the shelf lists them — and the
## purchase's after that, since a new id is the only one with nowhere to be.
func _take_stock() -> void:
	for item in ShopManager.catalogue():
		_hang(item, Stock.count(item.id) > 0)


## Puts one item on a free loop, or takes it off the one it had. Anything the
## player scene has no weapon dressed for is skipped: a shelf may sell a thing
## before there is anything to hold.
func _hang(item: StoreItem, owned: bool) -> void:
	var weapon := _weapon_named(item.weapon_node)
	if weapon == null:
		return
	var path := get_path_to(weapon)
	var at := slots.find(path)
	if owned:
		if at != -1:
			return
		var free := _free_slot()
		# Every loop is taken. The goods stay in the van and reach the belt when
		# something else runs out — see the note at the top.
		if free != -1:
			slots[free] = path
	elif at != -1:
		slots[at] = NodePath()


## The first loop with nothing on it, or -1 on a full belt.
func _free_slot() -> int:
	for i in slots.size():
		if slots[i].is_empty():
			return i
	return -1


## The weapon dressed under the head with a given name, or null when the scene
## has none — which is what an item nobody can hold yet reads as.
func _weapon_named(node_name: String) -> Weapon:
	if node_name.is_empty():
		return null
	for weapon in _hanging():
		if weapon.name == node_name:
			return weapon
	return null

## Every weapon the player could carry: the hands and everything hanging under
## `weapons_root`, whether or not it is on a loop right now. It is what the
## player uses to wire up their signals, once, at the start — and it is read off
## the head rather than off the belt because the belt is filled as things are
## bought, and a weapon wired only when it reached a loop would be one nobody
## was listening to on the shift it was bought.
func weapons() -> Array[Weapon]:
	var found: Array[Weapon] = []
	var own_hands := hands()
	if own_hands != null:
		found.append(own_hands)
	for weapon in _hanging():
		if weapon != own_hands:
			found.append(weapon)
	return found


## The weapons dressed under the head, in scene order. The belt owns none of
## them — it only points at them (see the note at the top).
func _hanging() -> Array[Weapon]:
	var root := get_node_or_null(weapons_root)
	if root == null:
		return []
	var found: Array[Weapon] = []
	for child in root.get_children():
		var weapon := child as Weapon
		if weapon != null:
			found.append(weapon)
	return found

# --- Relays to the weapon in hand ------------------------------------------
# With an empty slot out there is nothing to relay to, and every one of these
# quietly does nothing.

func is_busy() -> bool:
	return _current != null and _current.is_busy()

## Whether the weapon in hand refuses to be put away. It is what every swap asks,
## and it is a wider question than `is_busy()`: a strip of glue being laid holds
## the belt without holding the player (`scripts/weapons/glue_weapon.gd`).
func holds_belt() -> bool:
	return _current != null and _current.holds_belt()

## Calls off whatever the weapon in hand had started and not finished. Returns
## whether anything was actually called off, so the key that asked can go on and
## mean whatever else it usually means.
func cancel() -> bool:
	return _current != null and _current.cancel()

func try_use() -> void:
	if _current != null:
		_current.try_use()

func press_secondary() -> void:
	if _current != null:
		_current.press_secondary()


## Builds an 8-bit PSX denial buzzer for refused weapon equips.
func _build_refusal_beep() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.1
	var hz := 220.0
	var frames := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(frames)
	for i in frames:
		var cycle := fmod(float(i) * hz / float(sample_rate), 1.0)
		var fade := 1.0 - float(i) / float(frames)
		data[i] = int(roundf((60.0 if cycle < 0.5 else -60.0) * fade)) & 0xff
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_8_BITS
	wave.mix_rate = sample_rate
	wave.stereo = false
	wave.data = data
	return wave
