extends HBoxContainer
## The belt on screen: three squares at the foot of the screen, in the shape
## everybody already knows from Minecraft — a dark cell each, and a bright frame
## around whichever one is in hand.
##
## It only mirrors the player's `Inventory`. A square is empty until the weapon
## whose place it is has been *bought*: no name, no icon and no number, because
## a weapon the player does not own is not his to be told about. What he has
## bought shows its icon, or its name while no art has arrived for it yet, with
## how many are left in the corner (`scripts/weapons/trap_weapon.gd`) — and
## spending the last one empties the square again, which is the same square it
## was before the first purchase.
##
## The hands are on no square. They were never bought, they cannot run out, and
## `Q` is what brings them back (`scripts/weapons/inventory.gd`); with them out
## the belt simply has nothing framed.
##
## The two frames are built here instead of being dressed in `world.tscn`
## because they are a pair: the picked one has to grow *outwards*
## (`expand_margin`) by exactly what its border gained, or whatever sits inside
## the square would shift a pixel every time the player swapped slots.

## The cell: dark and see-through, the way it has to sit over any scene.
const SLOT_COLOR := Color(0, 0, 0, 0.55)
## The edge of a cell waiting its turn, and of the one in hand.
const BORDER_COLOR := Color(0.55, 0.55, 0.55, 0.75)
const PICKED_BORDER_COLOR := Color(1, 1, 1, 1)
const BORDER := 1
const PICKED_BORDER := 2

## The cells, in the order they sit on the belt.
@onready var _slots: Array[PanelContainer] = _gather_slots()

var _normal: StyleBoxFlat
var _picked: StyleBoxFlat
## The belt being mirrored. Null until the player is found.
var _inventory: Inventory

func _ready() -> void:
	_build_frames()
	# Wait one frame so the player is already in the tree.
	await get_tree().process_frame
	# A phase can end on the frame this HUD is waiting through — the board in the
	# van does exactly that — and a node that wakes up under a freed scene has no
	# tree left to look a player up in. There is nobody to wire to in that case,
	# and the HUD is on its way out with the rest of the scene anyway.
	if not is_inside_tree():
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	player.weapon_changed.connect(_on_weapon_changed)
	player.capture_started.connect(_on_capture_started)
	player.capture_finished.connect(_on_capture_finished)
	# The counts change without anybody swapping slots: buying at the computer
	# fills a box, and using one empties it.
	_inventory = player.inventory
	Stock.changed.connect(_on_stock_changed)
	# The belt equipped its first slot before anyone could be listening, so the
	# starting state is read straight from it instead of waited for.
	_fill(_inventory)
	_highlight(_inventory.index())

func _build_frames() -> void:
	_normal = StyleBoxFlat.new()
	_normal.bg_color = SLOT_COLOR
	_normal.border_color = BORDER_COLOR
	_normal.set_border_width_all(BORDER)
	_picked = _normal.duplicate()
	_picked.border_color = PICKED_BORDER_COLOR
	_picked.set_border_width_all(PICKED_BORDER)
	# What the thicker border took from the inside, the expansion gives back
	# from the outside: the square keeps the same room in it either way.
	_picked.set_expand_margin_all(PICKED_BORDER - BORDER)

## Puts in each square what its slot is carrying, once.
func _fill(inventory: Inventory) -> void:
	for i in _slots.size():
		var slot := _slots[i]
		if i >= inventory.slot_count():
			slot.hide()
			continue
		# What has not been bought — or has run out — is not on the belt as far
		# as the screen is concerned: the square goes back to being a square.
		var weapon := inventory.weapon_in(i)
		if weapon != null and not weapon.available():
			weapon = null
		var icon: TextureRect = slot.get_node("Icon")
		var label: Label = slot.get_node("Name")
		var count: Label = slot.get_node("Count")
		icon.texture = null if weapon == null else weapon.icon
		icon.visible = icon.texture != null
		# No picture for this weapon yet: its name stands in for one. An empty
		# square gets neither — being empty is the whole of what it has to say.
		label.text = "" if weapon == null else weapon.display_name
		label.visible = weapon != null and icon.texture == null
		_fill_count(count, weapon)
		slot.show()

## The corner number of a square. Only a weapon that comes out of a box has one,
## and only while there is something in the box — the square of a weapon the
## player does not own says nothing at all, zero included.
func _fill_count(label: Label, weapon: Weapon) -> void:
	var trap := weapon as TrapWeapon
	if trap == null or trap.stock_id.is_empty():
		label.text = ""
		label.hide()
		return
	label.text = str(Stock.count(trap.stock_id))
	label.show()

## Frames the square in hand. With the hands out the index is no slot
## (`Inventory.HANDS_INDEX`) and nothing gets framed, which is exactly right:
## what the player is holding is not on the belt.
func _highlight(index: int) -> void:
	for i in _slots.size():
		_slots[i].add_theme_stylebox_override("panel", _picked if i == index else _normal)

func _gather_slots() -> Array[PanelContainer]:
	var found: Array[PanelContainer] = []
	for child in get_children():
		var slot := child as PanelContainer
		if slot != null:
			found.append(slot)
	return found

func _on_weapon_changed(index: int, _weapon: Weapon) -> void:
	_highlight(index)

func _on_stock_changed(_id: String, _count: int) -> void:
	if _inventory == null:
		return
	_fill(_inventory)

func _on_capture_started(_rat: Node3D) -> void:
	hide()

func _on_capture_finished(_killed: bool) -> void:
	show()
