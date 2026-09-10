extends HBoxContainer
## The belt on screen: three squares at the foot of the screen, in the shape
## everybody already knows from Minecraft — a dark cell each, and a bright frame
## around whichever one is in hand.
##
## It only mirrors the player's `Inventory`. A square is empty until something
## has been *bought* to hang on it: no name, no icon and no number, because a
## weapon the player does not own is not his to be told about. Which square a
## thing lands on is the belt's business and not this screen's — no square is
## any one item's (`scripts/weapons/inventory.gd`). What he has
## bought shows its icon, or its name while no art has arrived for it yet, with
## how many are left in the corner (`scripts/weapons/trap_weapon.gd`) — and
## spending the last one empties the square again, which is the same square it
## was before the first purchase.
##
## The hands sit on a square of their own, ahead of the bought ones and set
## apart from them by a gap. They are still on no *slot* — they were never
## bought, they cannot run out and the belt reads `Inventory.HANDS_INDEX` while
## they are out — so their square is dressed once in the scene and never filled
## from the inventory. It is framed like any other when they are the ones in
## hand, which is the whole reason it is drawn: `Q` is a key the player has to
## be told about (`scripts/weapons/inventory.gd`).
##
## A square on the belt is a `Cell` with its key written under it, so what the
## screen shows is the box *and* the key that reaches it. The cell is what gets
## framed and filled; the letter below it never changes.
##
## The two frames are built here instead of being dressed in the HUD scene
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

## The square the hands are drawn on, and the one node under a square that the
## frame and the contents go on.
const HANDS_SLOT := "SlotHands"
const CELL := "Cell"

## The bought squares, in the order they sit on the belt. The hands' square is
## not among them: nothing on the inventory is ever put into it.
@onready var _slots: Array[Control] = _gather_slots()
## The hands' square, or null in a belt drawn without one.
@onready var _hands_cell: PanelContainer = get_node_or_null(
	"%s/%s" % [HANDS_SLOT, CELL]) as PanelContainer

var _normal: StyleBoxFlat
var _picked: StyleBoxFlat
## The belt being mirrored. Null until the player is found.
var _inventory: Inventory
## Static model thumbnails keyed by the weapon that owns them. The viewports
## stay alive with the HUD, so a stock change only repaints the slot instead of
## building the same model again.
var _model_icons: Dictionary = {}

func _ready() -> void:
	_build_frames()
	# Wait one frame so the player is already in the tree.
	# Held onto before the wait rather than fetched again after it: a phase can
	# end on the frame this HUD is waiting through — the board in the van does
	# exactly that — and the node then resumes already out of the tree, where
	# `get_tree()` is null and reaching through it throws.
	var tree := get_tree()
	if tree == null:
		return
	await tree.process_frame

	# Out of the tree while we waited: the scene we belong to was freed, there is
	# nobody left to wire to, and this HUD goes out with the rest of it.
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
		var cell := slot.get_node(CELL)
		var icon: TextureRect = cell.get_node("Icon")
		var label: BigFontOutlinedLabel = cell.get_node("Name")
		var count: BigFontOutlinedLabel = cell.get_node("Count")
		icon.texture = null if weapon == null else _icon_for(weapon)
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
func _fill_count(label: BigFontOutlinedLabel, weapon: Weapon) -> void:
	var trap := weapon as TrapWeapon
	if trap == null or trap.stock_id.is_empty():
		label.text = ""
		label.hide()
		return
	label.text = str(Stock.count(trap.stock_id))
	label.show()


## The shelf's model is the fallback icon for a weapon that has no authored
## texture. It is held still: the hotbar identifies what is in the player's
## hand, while the store's spinning thumbnails advertise what is for sale.
func _icon_for(weapon: Weapon) -> Texture2D:
	if weapon.icon != null:
		return weapon.icon
	if _model_icons.has(weapon):
		return _model_icons[weapon] as Texture2D
	var item := _item_for(weapon)
	if item == null or item.preview_model == null:
		return null
	var viewport := _model_viewport(item)
	var texture := viewport.get_texture()
	_model_icons[weapon] = texture
	return texture


## Finds the catalogue entry by the same node name the inventory uses to put an
## item into a slot. No second weapon-to-icon table can drift from the shelf.
func _item_for(weapon: Weapon) -> StoreItem:
	for item in ShopManager.catalogue():
		if item.weapon_node == weapon.name:
			return item
	return null


## Renders one shelf model into a square texture. The catalogue's hand pose is
## preserved, but there is deliberately no spin node or per-frame rotation.
func _model_viewport(item: StoreItem) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(32, 32)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.handle_input_locally = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)

	var pose := Node3D.new()
	viewport.add_child(pose)
	var model := item.preview_model.instantiate() as Node3D
	if model == null:
		return viewport
	pose.add_child(model)
	var bounds := _bounds_of(model)
	var extent := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	if extent > 0.0:
		model.scale = Vector3.ONE / extent
		model.position = -bounds.get_center() * model.scale
		# `preview_rotation` is the pose for the model in the store character's
		# hand. In a square icon it can leave a flat item edge-on, producing an
		# apparently empty slot. Put its longest side across the icon instead.
		pose.rotation_degrees = _icon_rotation(bounds.size)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.01
	camera.far = 8.0
	camera.size = 1.4
	camera.position = Vector3(1.0, 1.0, 2.0).normalized() * 3.0
	camera.look_at_from_position(camera.position, Vector3.ZERO, Vector3.UP)
	viewport.add_child(camera)
	var light := OmniLight3D.new()
	light.position = Vector3(1.0, 1.5, 2.0)
	light.light_color = Color(0.847059, 0.913725, 0.815686)
	light.light_specular = 0.0
	light.light_energy = 2.0
	light.omni_range = 15.0
	light.omni_attenuation = 0.420448
	viewport.add_child(light)
	return viewport


## Places every catalogue model broadside to the icon camera. Store preview
## assets do not agree on their authored up axis, so their bounds are the only
## stable way to choose a readable pose.
func _icon_rotation(model_size: Vector3) -> Vector3:
	if model_size.y >= model_size.x and model_size.y >= model_size.z:
		return Vector3(0.0, 0.0, -90.0)
	if model_size.z >= model_size.x and model_size.z >= model_size.y:
		return Vector3(0.0, 90.0, 0.0)
	return Vector3.ZERO


## The rendered model can be a scene full of nested meshes. Its merged bounds
## let every catalogue asset fit the same square despite differing export scales.
func _bounds_of(node: Node3D, so_far := Transform3D.IDENTITY) -> AABB:
	var bounds := AABB()
	var found := false
	if node is MeshInstance3D:
		bounds = so_far * (node as MeshInstance3D).get_aabb()
		found = true
	for child in node.get_children():
		var inner := child as Node3D
		if inner == null:
			continue
		var child_bounds := _bounds_of(inner, so_far * inner.transform)
		if not child_bounds.has_volume():
			continue
		bounds = child_bounds if not found else bounds.merge(child_bounds)
		found = true
	return bounds

## Frames the square in hand. With the hands out the index is no slot
## (`Inventory.HANDS_INDEX`), and it is their own square at the head of the belt
## that lights up instead of one of the bought ones.
func _highlight(index: int) -> void:
	for i in _slots.size():
		_cell(_slots[i]).add_theme_stylebox_override(
			"panel", _picked if i == index else _normal)
	if _hands_cell != null:
		_hands_cell.add_theme_stylebox_override(
			"panel", _picked if index == Inventory.HANDS_INDEX else _normal)

## The bought squares, found by the `Cell` under each of them. The hands' square
## and the gap that sets it apart are skipped: neither is a slot the inventory
## can put anything on.
func _gather_slots() -> Array[Control]:
	var found: Array[Control] = []
	for child in get_children():
		var slot := child as Control
		if slot == null or slot.name == HANDS_SLOT:
			continue
		if slot.get_node_or_null(CELL) is PanelContainer:
			found.append(slot)
	return found

func _cell(slot: Control) -> PanelContainer:
	return slot.get_node(CELL) as PanelContainer

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
