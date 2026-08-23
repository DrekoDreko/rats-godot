class_name ShopShelf
extends Interactable
## The shelf of goods in the back of the van: the things themselves standing on
## the boards, each with a price on a card under it, and a man reaches out and
## takes one.
##
## **One area, many goods.** The player's reach is a single ray onto a single
## interactable (see `Interactable`), so the shelf is one `Area3D` and works out
## which item he was actually pointing at by where the ray landed on it
## (`_item_under`). That is the same trick the colour panel plays with its eight
## swatches, and it is here for the same reason: it makes a row of separate
## targets out of one, and the prompt changes as he looks along the boards
## rather than reading "browse the shelf" the whole way across.
##
## **There is no menu.** The card asks for a physical shelf, and the difference
## between that and the computer screen the shop used to be (`hud_shop.gd`) is
## the whole point: the money is spent by looking at a thing and pressing `E`,
## in the van, with the crew standing around, and nobody is taken out of the map
## to do it. The old screen is left where it is — the computer in `world.tscn`
## is a different fitting in a different scene, and neither one knows about the
## other.
##
## **It decides nothing.** Pressing an item asks `ShopManager`, the host answers,
## and what comes back is what fills the bag. The round trip is visible — the
## price tag does not go green the instant the key is let go — and that is
## deliberate, for the reason the ready board and the colour panel are built the
## same way: a shelf that hands over goods on the buyer's own say-so and takes
## them back a moment later when the host disagrees is worse than one that takes
## a beat to be right.
##
## **Shut everywhere but the road.** The card says the shelf does not exist in
## the survey and the hunt, and what that means for a fitting bolted into the van
## is that it goes dark and stops answering (`_apply_phase`). It is not hidden:
## a shelf that vanishes is a van that changes shape, and the goods standing on
## the boards are what the crew spent the road buying. The lamp goes out, the
## prices come off and `E` does nothing.
##
## **Nothing here is stored.** What a man has in his pocket lives on
## `SessionManager` and what is on the shelf lives in `resources/store/`, and
## this reads both every time it draws.

## What the prompt reads. It names the item under the ray and what it costs, so
## that a man knows what he is about to spend before he spends it, and says why
## when he cannot.
const PROMPT_IDLE := "browse the shelf"
const PROMPT_BUY := "buy %s — $%d"
const PROMPT_DEAR := "%s — $%d, too dear"
const PROMPT_SHUT := "the shelf is shut"

## The colours a price card is written in: green while the money is there, red
## while it is not. The same two the shop screen and the health bar already use.
const AFFORDABLE_COLOR := Color(0.55, 0.85, 0.45)
const DEAR_COLOR := Color(0.95, 0.32, 0.28)
## And what it goes while the shelf is shut — off, rather than either answer.
const SHUT_COLOR := Color(0.42, 0.4, 0.36)

## How long a refused price card flashes red for, and how many times. The card
## asks for a price tag that blinks when the money is not there, and it is a
## blink and not a colour change so that a man who pressed twice sees the second
## refusal as well as the first.
const FLASH_TIME := 0.12
const FLASH_COUNT := 3

## How the price is written over its board, in metres per pixel the way
## `Label3D` counts, and how far it stands off the shelf.
const PRICE_PIXEL_SIZE := 0.0016
const PRICE_FONT_SIZE := 48
const PRICE_OUTLINE := 14
const PRICE_DROP := 0.115
const PRICE_OFFSET := 0.17

## How bright the shelf's lamp burns while it is open, and while it is not. Low
## either way: a pool of light on the goods rather than a glow over the van, the
## same as every other fitting in it.
const LAMP_ENERGY := 0.55
const LAMP_SHUT := 0.0

## Where the goods stand. Every child `MeshInstance3D` of this node is one item,
## in the order the scene has them, and that order is the shelf's — the first
## child is `ShopManager.at(0)`. Stocking the van is arranging boxes; nothing has
## to be numbered by hand.
@export var goods_path: NodePath = ^"Goods"

## The lamp over the shelf. Optional, like every light in the van: a shelf built
## without one still sells, it just sits in whatever light the van has.
@export var lamp_path: NodePath = ^"Lamp"

## The refusal. Only ever heard by the man who was turned down — a buzzer for
## somebody else's empty pocket is noise.
@export var refused_sound_path: NodePath = ^"Refused"
## The hand on the shelf, heard by everybody near it.
@export var press_sound_path: NodePath = ^"Press"

@onready var _goods_root: Node3D = get_node_or_null(goods_path) as Node3D
@onready var _lamp: OmniLight3D = get_node_or_null(lamp_path) as OmniLight3D
@onready var _refused_sound: AudioStreamPlayer3D = \
	get_node_or_null(refused_sound_path) as AudioStreamPlayer3D
@onready var _press_sound: AudioStreamPlayer3D = \
	get_node_or_null(press_sound_path) as AudioStreamPlayer3D

## The boxes on the boards, in shelf order.
var _goods: Array[MeshInstance3D] = []
## The price card hanging under each, built in code — there is one per item and a
## scene file with eight more `Label3D`s in it is a scene file nobody can read.
var _tags: Array[Label3D] = []
## Which item the ray is on, or -1 when it is on none of them. Kept only so that
## the prompt can be rewritten when it moves.
var _aimed := -1
## Whether the van is somewhere a man may buy things. Read from the phase rather
## than assumed, and re-read on every change.
var _open := false


func _ready() -> void:
	add_to_group("shop_station")
	_collect_goods()

	# Everything that can change what is written on the shelf, and nothing that
	# cannot. There is no polling of the purse here: money moves when somebody
	# buys something or a rat is delivered, which is a handful of times on the
	# road, and asking every frame would be eight cards each asking sixty times
	# a second.
	ShopManager.item_bought.connect(_on_item_bought)
	ShopManager.request_refused.connect(_on_refused)
	SessionManager.player_changed.connect(_on_player_changed)
	PhaseManager.phase_changed.connect(_on_phase_changed)

	# The state is read on the way up as well as on every change, for the reason
	# `VanTravel` reads it: the phase machine changes the scene first and the
	# phase *after* it is standing, so a shelf that only reacted to
	# `phase_changed` would be a shelf that missed its own arrival.
	_apply_phase()


## The prompt has to name the thing the player is actually looking at, and that
## changes as he moves his head rather than when anything in the game does. It is
## the one thing here worth a frame of work — and only while the shelf is open at
## all, which is what `set_process` below settles.
func _process(_delta: float) -> void:
	_update_aim()


## Hands on the shelf. `by` is the player who reached out, and it is ignored for
## the reason the colour panel ignores it: the only body that can reach this
## shelf is our own, so the pocket being emptied is always this machine's.
func use(_by: Node3D) -> void:
	super.use(_by)
	if not _open:
		# The shelf is shut and says so rather than doing nothing, so that a man
		# pressing `E` on it in the house can tell a shuttered shelf from a key
		# that is not working.
		_play(_refused_sound)
		return
	var index := _aimed
	if index < 0:
		# He pressed the shelf without being on an item — the housing between two
		# of them, or the edge. Nothing to ask for, and a buzzer would be blaming
		# him for the shelf's own gaps.
		return
	var item := ShopManager.at(index)
	if item == null:
		return
	_play(_press_sound)
	ShopManager.request_buy(_our_steam_id(), item.id)

# --- What is drawn ----------------------------------------------------------

## The whole shelf, from scratch. It is eight cards and cheap enough that working
## out which one changed would cost more than rewriting all of them, and it means
## there is one function to read rather than three that have to agree.
func _redraw() -> void:
	var us := _our_steam_id()
	for index in _tags.size():
		var tag := _tags[index]
		var item := ShopManager.at(index)
		if tag == null or item == null:
			continue
		if not _open:
			tag.text = ""
			tag.modulate = SHUT_COLOR
			continue
		# The count is what a man actually wants off a shelf he has already
		# bought from — "$25" tells him the price and "x3" tells him whether he
		# needs another box.
		var held := Stock.count(item.id)
		tag.text = "$%d" % item.price if held <= 0 else "$%d  x%d" % [item.price, held]
		tag.modulate = AFFORDABLE_COLOR if ShopManager.can_afford(us, item) else DEAR_COLOR
	_update_prompt()


## What the prompt reads, from whichever item the ray is on. It names the thing
## and the price in both cases — "buy mousetrap — $25" and "mousetrap — $25, too
## dear" tell a man both what is under his hand and what would happen, and the
## van is dark enough that the box alone does not always say.
func _update_prompt() -> void:
	if not _open:
		prompt = PROMPT_SHUT
		return
	if _aimed < 0:
		prompt = PROMPT_IDLE
		return
	var item := ShopManager.at(_aimed)
	if item == null:
		prompt = PROMPT_IDLE
		return
	if ShopManager.can_afford(_our_steam_id(), item):
		prompt = PROMPT_BUY % [item.display_name, item.price]
	else:
		prompt = PROMPT_DEAR % [item.display_name, item.price]


## Which item the player's own reach is on, worked out from where his ray meets
## the shelf. Nothing is drawn from it but the prompt, so it is allowed to be
## approximate — an item is claimed by the box it is drawn in, in the shelf's own
## space, which is exact enough for boxes this far apart.
func _update_aim() -> void:
	var index := _item_under(_reach_point())
	if index == _aimed:
		return
	_aimed = index
	_update_prompt()


## Where our own player is pointing on this shelf, in the shelf's space, or a
## point far away when he is not pointing at it at all. The ray is the one the
## character already casts to find interactables — this reads its answer rather
## than casting a second one.
func _reach_point() -> Vector3:
	var ray := _reach_ray()
	if ray == null or not ray.is_colliding() or ray.get_collider() != self:
		return Vector3.INF
	return to_local(ray.get_collision_point())


## The item a point on the shelf falls in, or -1 for a point on the boards
## between them. Each box owns a column its own width around itself, which is
## what makes the gaps real: a man on the edge between two boxes is offered
## neither rather than whichever happened to be nearer.
##
## Only the width and the height are asked about, not the depth: the ray lands on
## the *face* of the shelf's reach area, which is a good deal in front of where
## the boxes actually stand, so a depth test would reject every one of them.
func _item_under(point: Vector3) -> int:
	if point == Vector3.INF:
		return -1
	for index in _goods.size():
		var box := _goods[index]
		if box == null:
			continue
		var mesh := box.mesh as BoxMesh
		if mesh == null:
			continue
		var at := _goods_root.transform * box.position
		var half := mesh.size * 0.5
		if absf(point.x - at.x) <= half.x and absf(point.y - at.y) <= half.y:
			return index
	return -1


## The price card of a refused item, flashing red. The card asks for exactly
## this, and it is the whole of the feedback for an empty pocket together with
## the buzzer: the man who pressed sees which card he could not pay for.
##
## It flashes whichever card he was last looking at, because that is the one he
## pressed — the refusal comes back off the wire a moment later and does not
## carry the item with it.
func _flash_refused() -> void:
	if _aimed < 0 or _aimed >= _tags.size():
		return
	var tag := _tags[_aimed]
	if tag == null:
		return
	var tween := create_tween()
	for i in FLASH_COUNT:
		tween.tween_property(tag, "modulate", DEAR_COLOR, 0.0)
		tween.tween_interval(FLASH_TIME)
		tween.tween_property(tag, "modulate", Color(DEAR_COLOR, 0.15), 0.0)
		tween.tween_interval(FLASH_TIME)
	tween.tween_property(tag, "modulate", DEAR_COLOR, 0.0)

# --- The phase --------------------------------------------------------------

## Open on the road and shut everywhere else, with everything that follows from
## it set together: the lamp, the cards, the prompt and whether this node costs a
## frame at all. One function, called on the way up and on every change, so that
## there is no phase the van can arrive in that this has not already handled.
func _apply_phase() -> void:
	_open = ShopManager.is_open()

	# A shut shelf is not an interactable that answers slowly — it is one the
	# ray still finds, so that `use` can say the shelf is shut rather than the
	# player pressing `E` into thin air.
	if _lamp != null:
		_lamp.light_energy = LAMP_ENERGY if _open else LAMP_SHUT

	# Nobody is aiming at a shut shelf, and leaving the last aim standing would
	# have the prompt name an item the moment it opened again.
	if not _open:
		_aimed = -1
	# A shut shelf has nothing to work out every frame, and a van standing in the
	# house should not pay for one.
	set_process(_open)
	_redraw()

# --- What wakes it up -------------------------------------------------------

## Somebody bought something. Everybody's shelf redraws and not only the buyer's:
## what changed for the others is nothing on the cards, but the guard in
## `_redraw` is cheaper than working out whether it was us.
func _on_item_bought(_steam_id: int, _item_id: String) -> void:
	_redraw()


## A purse moved — a purchase, or a rat delivered. Only our own matters to what
## is written here, since every card is priced against our own pocket.
func _on_player_changed(steam_id: int) -> void:
	if steam_id == _our_steam_id():
		_redraw()


## The host turned us down — an empty pocket, or the van already off the road
## while our packet was in the air. Only heard on the machine that asked, so the
## buzzer and the flashing card are for the man who reached and for nobody else.
func _on_refused(reason: String) -> void:
	_play(_refused_sound)
	_flash_refused()
	print("Purchase refused: %s" % reason)


func _on_phase_changed(_previous: Phase.Type, _current: Phase.Type) -> void:
	_apply_phase()

# --- Stocking the shelf -----------------------------------------------------

## The boxes, in the order the scene has them, each given a price card. Read once
## on the way up: the shelf does not grow.
##
## A scene with fewer boxes than the folder has items is not an error — it is a
## smaller shelf, and the ones past the end simply are not stocked in this van.
## The other way round would be, so it is said out loud.
func _collect_goods() -> void:
	if _goods_root == null:
		push_warning("ShopShelf: no goods under %s." % goods_path)
		return
	for child in _goods_root.get_children():
		var mesh := child as MeshInstance3D
		if mesh == null:
			continue
		_goods.append(mesh)
		_tags.append(_build_tag(mesh))
	if _goods.size() < ShopManager.count():
		push_warning("ShopShelf: %d boxes on the shelf for %d items on the list."
			% [_goods.size(), ShopManager.count()])


## The price card under a box: a small label standing off the front of the shelf,
## written the way every other number in the game is — bitmap, no antialiasing,
## a heavy outline so that it reads against the box behind it.
func _build_tag(box: MeshInstance3D) -> Label3D:
	var tag := Label3D.new()
	tag.pixel_size = PRICE_PIXEL_SIZE
	tag.font_size = PRICE_FONT_SIZE
	tag.outline_size = PRICE_OUTLINE
	tag.modulate = AFFORDABLE_COLOR
	tag.outline_modulate = Color(0, 0, 0, 1)
	# Lit from inside rather than by the van's lamp, and never sorted behind the
	# box it belongs to.
	tag.shaded = false
	tag.no_depth_test = false
	tag.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	tag.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	tag.position = Vector3(0.0, -PRICE_DROP, PRICE_OFFSET)
	box.add_child(tag)
	return tag

# --- Odds and ends ----------------------------------------------------------

## The ray our own character reaches with, or null when there is no character —
## a bench, or a shelf standing in a scene nobody is playing. It is found through
## the group the player is in rather than by path, because the shelf is dressed
## into the van and knows nothing about where the player node hangs. The same
## shape as `ColorStation._reach_ray`.
func _reach_ray() -> RayCast3D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0].get_node_or_null(^"Head/Camera/Interact") as RayCast3D


## Whose money this shelf spends. Ours, always — see `use`. Falls back to the
## only man in the crew when Steam is not running, which is what makes the shelf
## work on a bench and in a solo game where `get_steam_id` answers zero. The same
## answer `ColorStation._our_steam_id` works out, and worked out the same way.
func _our_steam_id() -> int:
	var steam_id := SteamManager.get_steam_id()
	if steam_id != 0 and SessionManager.has_player(steam_id):
		return steam_id
	var crew := SessionManager.players.keys()
	return crew[0] if crew.size() == 1 else steam_id


## A sound, if the shelf was built with one. Every one of them is optional, so
## that a shelf can be dropped into a grey-box van before there is any audio in
## the project at all.
func _play(player: AudioStreamPlayer3D) -> void:
	if player != null and player.stream != null:
		player.play()
