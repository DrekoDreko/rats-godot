class_name StoreScreen
extends Control
## The store the crew shops at on the road: the man himself on the left, his
## name and his money over him, and the racks of weapons he can buy on the
## right.
##
## **It is a `Control` and not a `CanvasLayer` any more.** A layer buys ordering
## against the rest of the HUD, and there is no rest of the HUD inside a monitor:
## the viewport holds this and nothing else, at whatever size the glass is.
##
## **It is drawn on the monitor and not over it.** This layer lives inside the
## `SubViewport` painted onto the glass of the totem at the front of the van
## (`scripts/session/store_terminal.gd`), so the racks are pixels on a screen in
## the room rather than a window in front of the room. The terminal walks the
## camera up until the monitor fills the view before showing any of it.
##
## **It does not open itself, and it does not read keys.** Nothing in the window
## reaches a layer inside a `SubViewport`: the terminal owns the camera, the man
## and the keys while the store is up, and hands the mouse through onto the glass
## itself. This screen is only shown, drawn and hidden.
##
## **Only while the wheels are turning.** `ShopManager.is_open()` is the one
## answer, and it is the phase and nothing else: the lobby has not left yet and
## the house has no van in it. The key does nothing in either, the hint does not
## show, and a screen that is up when the phase turns is shut by the phase rather
## than left standing over a van that has parked.
##
## **The rack is drawn from the catalogue, not from the scene.** Everything in
## `resources/store/` is on sale, grouped into columns by its `kind`, and every
## column is padded out to `SLOTS_PER_COLUMN` with empty frames. That padding is
## the point: the weapons are being written one at a time, and a rack that shows
## where the next three are going is a rack nobody has to redraw when they
## arrive. Dropping a `.tres` in the folder fills the next empty frame on every
## machine at once.
##
## **Pressing a tile picks it up; buying is a second press.** A tile puts the
## thing in the man's hand on the left and lights up as chosen, and the money
## only moves when `BUY` is pressed under it. That is two clicks where the rack
## used to take one, and it buys the whole reason the preview is there: a man
## who cannot tell a broom from a bat by its name can turn one over in his hand
## before he pays for it, and a man whose finger slipped on the rack has not
## spent anything yet.
##
## **It decides nothing about money.** Pressing `BUY` asks `ShopManager`, the
## host answers, and the tile is redrawn off what came back — the same round trip
## the shelf took, and for the same reason: a screen that debits its own purse
## and is corrected a moment later is worse than one that takes a beat to be
## right.

## The store was shut. The terminal listens: it is what walks the camera back to
## the man and hands him his legs again.
signal closed

## The monitor's viewport is 640x507, and 14 px is the smallest a letter reads
## at once the glass is a metre away and the whole thing is run through the PS1
## filter. It is not the 8 px the rest of the HUD uses: the HUD is drawn at the
## window's own scale, and this is drawn on a screen inside the room.
const FONT_SIZE := 14
## The size the column headers and the store's own title are set in.
const HEADING_SIZE := 14

## Green while the money is there, red while it is not — the two colours the
## health bar and the old shelf already use.
const AFFORDABLE_COLOR := Color(0.55, 0.85, 0.45)
const DEAR_COLOR := Color(0.95, 0.32, 0.28)
## The blue the headings and the frames are drawn in, off the same palette as
## the rest of the screen.
const ACCENT_COLOR := Color(0.45, 0.72, 0.9)
## And what an empty frame is written in: present, but plainly nothing yet.
const EMPTY_COLOR := Color(0.5, 0.56, 0.62)

## What an empty frame reads.
const EMPTY_TEXT := "—"

## The racks, and which kinds of thing stand on each. The columns are fixed and
## the items find their way into them, rather than the other way round: a column
## per kind would be five narrow strips at this resolution, and a column that
## appears when its first item is written would move every other one sideways.
const COLUMNS: Array[Dictionary] = [
	{"title": "TRAPS", "kinds": [StoreItem.Kind.TRAP]},
	{"title": "WEAPONS", "kinds": [StoreItem.Kind.ONE_HAND, StoreItem.Kind.TWO_HANDS]},
	{"title": "SUPPLIES", "kinds": [StoreItem.Kind.BAIT, StoreItem.Kind.PATCH]},
]

## How many frames each rack shows at the least. Anything the catalogue does not
## fill is drawn empty and waiting — see the note at the top.
const SLOTS_PER_COLUMN := 5

## How tall one frame on the rack is, and how far the writing on it stands off
## the frame's own edge.
const TILE_HEIGHT := 44
const TILE_INSET := Vector2(6, 3)

## How long a refused tile flashes for, and how many times. A blink and not a
## colour change, so that a man who pressed twice sees the second refusal as
## well as the first — the same shape the old shelf's price card used.
const FLASH_TIME := 0.1
const FLASH_COUNT := 3

## What the man on the left is doing while he shops: standing still.
const PREVIEW_STATE := PlayerAvatar.State.IDLE

## The bone the selected item is hung from in the preview: the *left* hand of the
## mixamo rig the suit is animated on.
##
## Left and not right because of where the camera stands. The preview is 120 px
## wide with the man filling it, and his right hand is the one against the frame's
## own edge — a bat held there is half cut off by the border. His left is the side
## with room in it, and a shop window is one place where being seen beats being
## handed.
##
## It is named rather than searched for: a rig whose bones are called something
## else is a rig this preview shows empty-handed, which is a great deal better
## than one that guesses wrong and hangs the bat off a foot.
const PREVIEW_HAND_BONE := &"mixamorig_LeftHand"

## What the buy button reads, and how wide it is kept so that the footer does not
## shuffle sideways as the word under it changes.
const BUY_TEXT := "BUY"
const BUY_WIDTH := 76

## How long the button flashes green after a purchase goes through. It is the
## only thing that says "that worked" on a rack where the count on the tile may
## not have moved yet — the tile is redrawn off the host's answer, and this is
## drawn off the same answer at the same moment.
const BOUGHT_FLASH_TIME := 0.35

## The body on the left, and the PS1 dressing that makes it match the one in the
## van. The preview renders in a world of its own, where the van's own applier
## cannot reach it.
const MODEL_SCENE := preload("res://scenes/player_model.tscn")
const PS1_SCENE := preload("res://scenes/ps1.tscn")

@onready var _root: Control = $Root
@onready var _money: Label = $Root/Margin/Rows/Header/Money
@onready var _player_name: Label = $Root/Margin/Rows/Body/Left/PlayerName
@onready var _columns: HBoxContainer = $Root/Margin/Rows/Body/Columns
@onready var _notice: Label = $Root/Margin/Rows/Footer/Notice
@onready var _footer: HBoxContainer = $Root/Margin/Rows/Footer
@onready var _close: Label = $Root/Margin/Rows/Footer/Close
@onready var _preview: SubViewport = $Root/Margin/Rows/Body/Left/Preview/View
@onready var _preview_seat: Node3D = $Root/Margin/Rows/Body/Left/Preview/View/Seat

## Our own character, so the store can take him over while it is up and hand him
## back when it goes. Found by group, like every other piece of the HUD.
var _player: Node3D
## The body in the preview, built once and repainted as the colour changes.
var _model: PlayerModel
## The hand the selected item hangs from, built once with the body. It is square
## to the world rather than to the wrist — see `_build_preview_hand`.
var _preview_hand: Node3D
## The bone itself, which that node follows the position of and nothing else.
var _upright_hand: BoneAttachment3D
## What is in that hand right now, and which item put it there. The model is
## instanced on the selection rather than dressed all at once the way the view
## model does it, because the catalogue is what says which models exist and the
## catalogue is only read at runtime — there is no scene here to dress them in.
var _preview_item: Node3D
## One entry per frame on the racks that has something in it: the item it sells,
## the button that selects it and the two labels on it.
var _tiles: Array[Dictionary] = []
## The item under the man's arm, or null with nothing chosen. It is what `BUY`
## spends on, and it is the one piece of state this screen keeps of its own —
## everything else is redrawn off the purse and the catalogue.
var _selected: StoreItem
## The button that spends the money, built in code so that it wears the same
## frame as the rack it sits under.
var _buy_button: Button
## What we last asked the host for, so that a refusal flashes the tile the man
## actually pressed. The refusal comes back off the wire without the item on it.
var _pending_id := ""
## Whether the screen is up. Kept rather than read off `visible`, because the two
## can part company for a frame while a scene is being changed under us.
var _open := false


func _ready() -> void:
	add_to_group("store_screen")
	_root.hide()

	_build_racks()
	_build_preview()
	_build_buy_button()

	ShopManager.item_bought.connect(_on_item_bought)
	ShopManager.request_refused.connect(_on_refused)
	SessionManager.player_changed.connect(_on_player_changed)
	ColorManager.color_changed.connect(_on_color_changed)
	PhaseManager.phase_changed.connect(_on_phase_changed)

	# Wait one frame so the character is already in the tree. Held onto before
	# the wait rather than fetched again after it: a phase can end on the frame
	# this is waiting through — the ready board in the van does exactly that —
	# and the node then resumes already out of the tree, where `get_tree()` is
	# null and reaching through it throws.
	var tree := get_tree()
	if tree == null:
		return
	await tree.process_frame
	if not is_inside_tree():
		return

	_player = get_tree().get_first_node_in_group("player") as Node3D
	_refresh()


## Keeps the thing in his hand *on* his hand. The node it hangs from is
## `top_level`, which is what throws the wrist's rotation away (see
## `_build_preview_hand`) — and the price of that is that its position no longer
## follows the bone either, so it is copied across here every frame.
##
## Only while the store is up and only with something chosen: the rest of the
## time there is nothing to carry and the body is not being drawn.
func _process(_delta: float) -> void:
	if not _open or _preview_hand == null or _upright_hand == null:
		return
	_preview_hand.global_position = _upright_hand.global_position


# --- Opening and closing ----------------------------------------------------

## Puts the racks on the glass. Called by the terminal once the camera has
## arrived, and by the benches directly.
##
## The man himself is not touched here: the terminal took him over before the
## camera moved and hands him back after it has moved again, so that he is not
## walking around the van for the half second the screen is flying home.
func open() -> void:
	if _open:
		return
	_open = true
	_notice.text = ""
	_refresh()
	_root.show()
	_show_rest_of_hud(false)


func close() -> void:
	if not _open:
		return
	_open = false
	# The hand is emptied on the way out rather than left as it was. The store
	# is opened and shut a dozen times over two minutes of road, and a rack that
	# remembered would open on a thing the man chose four stops ago and has
	# since bought — with `BUY` lit under it as though he still meant to.
	_selected = null
	_show_held_item(null)
	_refresh()
	_root.hide()
	_show_rest_of_hud(true)
	closed.emit()


## The crosshair and the prompt have nothing to say while a man is shopping. The
## prompt is the one that does not come back on its own account: he may still be
## standing at a station, and the character announces it again on the next frame.
##
## The HUD is hunted for by name rather than pointed at. This layer is inside the
## monitor's own viewport now, several nodes down a branch of the van, and a
## relative path from in there is one rename away from silently pointing at
## nothing — the map table pays the same toll to find the layer it draws on.
func _show_rest_of_hud(on: bool) -> void:
	# The clock over the road goes with them. It is drawn in the middle of the
	# top of the window, which is exactly where the monitor is while a man is
	# reading it — a phase counter across the racks is the one thing on screen
	# that is neither the van nor the shop.
	var clock := get_tree().get_first_node_in_group("hud_phase") as CanvasLayer
	if clock != null:
		clock.visible = on

	var hud := get_tree().root.find_child("HUD", true, false)
	if hud == null:
		return
	var crosshair := hud.get_node_or_null("Crosshair") as CanvasItem
	if crosshair != null:
		crosshair.visible = on
	if not on:
		var prompt := hud.get_node_or_null("Prompt") as CanvasItem
		if prompt != null:
			prompt.hide()


# --- The racks --------------------------------------------------------------

## The three racks, built once. The catalogue is read off `ShopManager`, which
## scanned the folder on the way up, so every machine builds the same racks in
## the same order without anybody keeping a second list.
func _build_racks() -> void:
	var catalogue := ShopManager.catalogue()
	for column in COLUMNS:
		var kinds: Array = column["kinds"]
		var items: Array[StoreItem] = []
		for item in catalogue:
			if kinds.has(item.kind):
				items.append(item)
		_columns.add_child(_build_column(String(column["title"]), items))


## One rack: its heading, what is on it, and the empty frames under that.
func _build_column(title: String, items: Array[StoreItem]) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The rack fills the glass it is drawn on. The monitor is a 5:4 screen and
	# the frames were sized for a 16:9 HUD, so a rack that kept `TILE_HEIGHT`
	# would hang from the top of the screen with a third of it empty underneath.
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 2)

	var heading := _label(title, HEADING_SIZE)
	heading.add_theme_color_override("font_color", ACCENT_COLOR)
	column.add_child(heading)

	var rule := HSeparator.new()
	rule.add_theme_constant_override("separation", 2)
	column.add_child(rule)

	for item in items:
		column.add_child(_build_tile(item))
	for _i in range(maxi(SLOTS_PER_COLUMN - items.size(), 0)):
		column.add_child(_build_empty_tile())
	return column


## One thing for sale: its name, and under it what it costs and how many of it
## the man already has. The button is the whole tile rather than a corner of it,
## so the mouse only has to land somewhere on the thing being picked up.
##
## Pressing it selects and never buys — the money is spent by the button in the
## footer. See the note at the top for why the rack is two clicks deep.
func _build_tile(item: StoreItem) -> Button:
	var button := _frame()
	button.tooltip_text = item.description
	button.pressed.connect(_select.bind(item))

	var rows := VBoxContainer.new()
	rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rows.offset_left = TILE_INSET.x
	rows.offset_top = TILE_INSET.y
	rows.offset_right = -TILE_INSET.x
	rows.offset_bottom = -TILE_INSET.y
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 0)

	var name_label := _label(item.display_name, FONT_SIZE)
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var price_label := _label("", FONT_SIZE)
	rows.add_child(name_label)
	rows.add_child(price_label)
	button.add_child(rows)

	_tiles.append({"item": item, "button": button, "price": price_label})
	return button


## A frame with nothing in it yet. It is a dead button and not a panel, so that
## the rack keeps one shape as the weapons are written into it one at a time.
func _build_empty_tile() -> Button:
	var button := _frame()
	button.disabled = true
	button.focus_mode = Control.FOCUS_NONE
	button.text = EMPTY_TEXT
	button.add_theme_font_size_override("font_size", FONT_SIZE)
	button.add_theme_color_override("font_disabled_color", EMPTY_COLOR)
	return button


## The frame a slot is drawn in, whether or not there is anything in it: a dark
## panel with a stripe of the store's blue down its left edge, brighter under the
## mouse. Every slot is the same frame so that the empty ones read as *waiting*
## rather than as gaps in the rack — which is the whole reason they are drawn.
func _frame() -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, TILE_HEIGHT)
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button.add_theme_stylebox_override("normal", _frame_style(0.06, 0.4))
	button.add_theme_stylebox_override("hover", _frame_style(0.16, 0.9))
	button.add_theme_stylebox_override("pressed", _frame_style(0.24, 1.0))
	button.add_theme_stylebox_override("focus", _frame_style(0.16, 0.9))
	button.add_theme_stylebox_override("disabled", _frame_style(0.03, 0.18))
	return button


## One of those frames, at a given strength: how much light is in the panel and
## how much is in the stripe.
func _frame_style(fill: float, stripe: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(ACCENT_COLOR, fill)
	style.border_width_left = 2
	style.border_color = Color(ACCENT_COLOR, stripe)
	return style


func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 2)
	return label


## Marks a tile as the one in the man's hand, or unmarks it. The chosen tile is
## drawn as though the mouse were on it and its stripe is thickened all the way
## round, so that "chosen" reads at a glance from across the rack and does not
## depend on the mouse being anywhere in particular.
##
## It is done by swapping the `normal` box rather than by tinting the button,
## because `modulate` is what a refusal blinks with — two things writing to the
## same property would leave a refused tile stuck red or a chosen one plain.
func _mark_selected(button: Button, on: bool) -> void:
	var style := _frame_style(0.16, 1.0) if on else _frame_style(0.06, 0.4)
	if on:
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1
	button.add_theme_stylebox_override("normal", style)


## The button that spends the money, put in the footer between the refusal
## notice and the line about closing — bottom right, under the racks, where a
## man's eye lands after he has picked something off one.
##
## It is built here and not in the scene for the same reason the tiles are: it
## has to wear the same frame they do, and that frame is a handful of
## `StyleBoxFlat`s made in code.
func _build_buy_button() -> void:
	if _footer == null:
		return
	_buy_button = _frame()
	_buy_button.custom_minimum_size.x = BUY_WIDTH
	_buy_button.text = BUY_TEXT
	_buy_button.add_theme_font_size_override("font_size", FONT_SIZE)
	_buy_button.add_theme_color_override("font_color", AFFORDABLE_COLOR)
	_buy_button.add_theme_color_override("font_hover_color", AFFORDABLE_COLOR)
	_buy_button.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
	_buy_button.add_theme_color_override("font_disabled_color", EMPTY_COLOR)
	_buy_button.pressed.connect(_buy_selected)
	_footer.add_child(_buy_button)
	# The line about closing stays the last thing on the row: it belongs to the
	# screen rather than to the shopping, and a key that moves as things are
	# picked up is a key nobody trusts.
	if _close != null:
		_footer.move_child(_close, _footer.get_child_count() - 1)

# --- The man on the left ----------------------------------------------------

## The body in the preview. It renders in a world of its own inside the
## `SubViewport`, so it is lit by that scene's own lamps rather than by whatever
## corner of the van the player happens to be standing in — a shop window and
## not a mirror.
func _build_preview() -> void:
	if _preview_seat == null:
		return
	_model = MODEL_SCENE.instantiate() as PlayerModel
	_preview_seat.add_child(_model)
	# The van dresses its models from an applier at the root of the scene, and
	# that applier cannot see into another world. This one carries its own.
	_model.add_child(PS1_SCENE.instantiate())
	# The pose is set after the model is in the tree: `set_state` reaches for the
	# `AnimationPlayer` through an `@onready`, which is not resolved before then.
	_model.set_state(PREVIEW_STATE)
	_build_preview_hand()


## The hook in the preview's right hand that the selected item hangs from.
##
## It is a `BoneAttachment3D` and not a fixed offset under the body because the
## suit is *animated* while it stands there — the idle breathes, and a bat
## pinned to the model rather than to the hand would hang in the air beside a
## man swaying gently away from it.
##
## A rig without that bone gets no hook and the preview shows an empty hand: the
## body can be swapped for another one without this screen being the thing that
## breaks.
func _build_preview_hand() -> void:
	var skeleton := _model.get_node_or_null("Hazmat/Armature/Skeleton3D") as Skeleton3D
	if skeleton == null or skeleton.find_bone(PREVIEW_HAND_BONE) < 0:
		return
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = PREVIEW_HAND_BONE
	skeleton.add_child(attachment)
	# The item hangs off a second node under the bone rather than off the bone
	# itself, and that node is *unturned*: it takes the hand's position and
	# throws its rotation away, so it stands square to the world however the
	# wrist happens to be twisted at that moment in the idle.
	#
	# That is what makes the numbers in a `.tres` worth writing. On the bone's
	# own axes, "up" is a different direction for every frame of the animation
	# and a different one again in any other rig — a bat stood upright by hand
	# would lie down by the time the man had finished breathing in. Here `+Y`
	# is up, `+Z` is out towards the shopper and `+X` is off to the man's left,
	# for every item and every frame, and the only thing left to write per item
	# is which way its own model happens to point.
	_preview_hand = Node3D.new()
	_preview_hand.top_level = true
	attachment.add_child(_preview_hand)
	_upright_hand = attachment


## Puts the chosen item in that hand, or empties it when nothing is chosen.
##
## The model is built on the selection and thrown away on the next one, which is
## the opposite of what the view model does with the same models
## (`PlayerViewModel.set_held_item` dresses them all at once and shows one). The
## difference is that this rack is drawn from the catalogue at runtime: there is
## no scene here in which the models could have been dressed ahead of time, and
## a click on a shop screen is not the frame the view model is protecting.
func _show_held_item(item: StoreItem) -> void:
	if _preview_item != null:
		_preview_item.queue_free()
		_preview_item = null
	if _preview_hand == null or item == null or item.preview_model == null:
		return
	var model := item.preview_model.instantiate() as Node3D
	if model == null:
		return

	# The pivot the item is posed on, and the item hanging under it recentred on
	# its own bounds. The two are separate because the models come from five
	# different exporters and not one of them agrees about where the origin of a
	# thing is: the broom's is eight metres off the bristles, the cheese's is in
	# the middle, the trap's is at a corner. Recentring first means the numbers
	# in a `.tres` describe where the *object* sits in his hand — which is what
	# somebody dropping a sixth model in the folder can reason about — instead
	# of where its exporter happened to leave the origin, which is not.
	_preview_item = Node3D.new()
	_preview_item.position = item.preview_offset
	_preview_item.rotation_degrees = item.preview_rotation
	_preview_hand.add_child(_preview_item)
	_preview_item.add_child(model)

	# And then sized by how tall it should read rather than by a multiplier, for
	# the same reason: a scale of 1 means one thing on a model authored in
	# metres and quite another on one authored in centimetres, and the shopper
	# does not care which. `preview_height` is what he does care about — how big
	# the thing is in the man's hand.
	var bounds := _bounds_of(model)
	var extent := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	if extent > 0.0:
		model.scale = Vector3.ONE * (item.preview_height / extent)
	model.position = -bounds.get_center() * model.scale

	# Same reason the body carries its own: the van's applier cannot reach into
	# this world, so the thing in his hand would be the one unshaded object on
	# the screen without one of these.
	model.add_child(PS1_SCENE.instantiate())


## The box a model fills, in the coordinates of the node it is rooted at, merged
## over every mesh under it. An empty box for a scene with no mesh in it at all,
## which is what keeps the sizing above from dividing by nothing.
##
## It walks the tree carrying the transform down rather than reading world
## positions, because it is called on a model that has only just been instanced
## and is not in the tree yet — where `global_transform` is not answerable.
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
		var box := _bounds_of(inner, so_far * inner.transform)
		if not box.has_volume():
			continue
		bounds = box if not found else bounds.merge(box)
		found = true
	return bounds


## Repaints the man and rewrites his name. Both live on `SessionManager`, put
## there by the host, so there is nothing decided here — only redrawn.
func _refresh_player() -> void:
	var us := _our_steam_id()
	var color := SessionManager.color(us)
	if _model != null:
		_model.set_tint(color)
	var entry := SessionManager.player(us)
	_player_name.text = String(entry.get("name", "PLAYER")).to_upper()
	_player_name.add_theme_color_override("font_color", color)

# --- What is written --------------------------------------------------------

## The whole screen, from the purse and the catalogue and nothing kept here: the
## numbers on the store cannot drift from the ones that survive the van.
func _refresh() -> void:
	var us := _our_steam_id()
	_money.text = "$ %d" % ShopManager.money(us)
	_refresh_player()
	for tile in _tiles:
		var item: StoreItem = tile["item"]
		var price: Label = tile["price"]
		var button: Button = tile["button"]
		# The count is what a man wants off a rack he has already bought from:
		# the price tells him what it costs and the count whether he needs
		# another one.
		var held := Stock.count(item.id)
		price.text = "$%d" % item.price if held <= 0 else "$%d   x%d" % [item.price, held]
		var afford := ShopManager.can_afford(us, item)
		price.add_theme_color_override("font_color",
			AFFORDABLE_COLOR if afford else DEAR_COLOR)
		# Every tile stays pressable, whatever it costs. Picking a thing up is
		# not buying it any more, and a man ought to be able to turn the
		# expensive one over in his hand and decide it is worth saving for —
		# the red price already says he cannot have it yet, and the button in
		# the footer is the one that goes dead.
		_mark_selected(button, item == _selected)
	_refresh_buy_button()


## The button that spends: what it costs to buy the thing in his hand, and
## whether he can. It is the one place affordability is acted on now — the rack
## itself only says the price in red.
func _refresh_buy_button() -> void:
	if _buy_button == null:
		return
	if _selected == null:
		_buy_button.text = BUY_TEXT
		_buy_button.disabled = true
		return
	_buy_button.text = "%s $%d" % [BUY_TEXT, _selected.price]
	_buy_button.disabled = not ShopManager.can_afford(_our_steam_id(), _selected)


## A refused tile, blinking red. It is the whole of the feedback for an empty
## pocket, and it is the tile the man actually pressed rather than a guess: the
## id was remembered on the way out in `_buy`.
func _flash_refused() -> void:
	for tile in _tiles:
		var item: StoreItem = tile["item"]
		if item.id != _pending_id:
			continue
		var button: Button = tile["button"]
		var tween := create_tween()
		for _i in FLASH_COUNT:
			tween.tween_property(button, "modulate", DEAR_COLOR, 0.0)
			tween.tween_interval(FLASH_TIME)
			tween.tween_property(button, "modulate", Color.WHITE, 0.0)
			tween.tween_interval(FLASH_TIME)
		return

# --- Picking up and buying --------------------------------------------------

## Takes a thing off the rack and puts it in the man's hand. Nothing is spent
## and nothing crosses the wire: this is entirely a thing this screen does to
## itself, which is why it does not wait for anybody.
##
## Pressing the tile that is already chosen puts it back on the rack. It costs
## nothing to have, and a rack you cannot let go of is one where the only way to
## empty the hand is to shut the store.
func _select(item: StoreItem) -> void:
	_selected = null if item == _selected else item
	_notice.text = ""
	_show_held_item(_selected)
	_refresh()


## Asks the host for one of whatever is in his hand. Nothing is written here and
## nothing is drawn ahead of the answer — see the note at the top.
##
## The selection survives the purchase. A man buying traps usually wants three,
## and a rack that emptied his hand every time would make him find the tile
## again between each one.
func _buy_selected() -> void:
	if _selected == null:
		return
	_pending_id = _selected.id
	_notice.text = ""
	ShopManager.request_buy(_our_steam_id(), _selected.id)


## The button going green for a moment, which is the whole of what says a
## purchase went through. It is drawn off the host's answer like everything else
## on this screen, so a refusal never flashes it.
func _flash_bought() -> void:
	if _buy_button == null:
		return
	var tween := create_tween()
	tween.tween_property(_buy_button, "modulate", AFFORDABLE_COLOR, 0.0)
	tween.tween_interval(BOUGHT_FLASH_TIME)
	tween.tween_property(_buy_button, "modulate", Color.WHITE, 0.0)

# --- What wakes it up -------------------------------------------------------

## Somebody bought something. Everybody's screen redraws and not only the
## buyer's: what changed for the others is nothing, and the guard would cost more
## than the redraw.
##
## The green flash, on the other hand, is only for the man who paid — the guard
## is worth it there, since a button lighting up on somebody else's purchase
## would read as his own having gone through.
func _on_item_bought(steam_id: int, _item_id: String) -> void:
	_refresh()
	if steam_id == _our_steam_id():
		_flash_bought()


## The host turned us down — an empty pocket, or the van already off the road
## while our packet was in the air. Only heard on the machine that asked.
func _on_refused(reason: String) -> void:
	_notice.text = reason
	_flash_refused()


## A purse moved, or a name arrived. Only our own matters to what is written
## here, since every price is set against our own pocket.
func _on_player_changed(steam_id: int) -> void:
	if steam_id == _our_steam_id():
		_refresh()


func _on_color_changed(steam_id: int, _color: Color) -> void:
	if steam_id == _our_steam_id():
		_refresh_player()


## The van left the road with the store still up. It is shut here rather than
## left standing, for the same reason the shelf went dark: a screen offering
## goods the host will refuse is a screen that lies.
func _on_phase_changed(_previous: Phase.Type, _current: Phase.Type) -> void:
	if not ShopManager.is_open():
		close()

# --- Odds and ends ----------------------------------------------------------

## Whose money this store spends. Ours, always. Falls back to the only man in the
## crew when Steam is not running, which is what makes the store work on a bench
## and in a solo game where `get_steam_id` answers zero — the same answer
## `ShopManager.is_ours` works out, and worked out the same way.
func _our_steam_id() -> int:
	var steam_id := LobbyManager.our_steam_id()
	if steam_id != 0 and SessionManager.has_player(steam_id):
		return steam_id
	var crew := SessionManager.players.keys()
	return crew[0] if crew.size() == 1 else steam_id
