extends TextureRect
## The crosshair, and the one thing it has to say beyond where the middle of the
## screen is: whether there is a rat under it.
##
## It keeps no rule of its own and measures nothing. Whether the click would
## reach an animal is the weapon's question and the player asks it every frame
## (`player.gd: _update_target`); this only draws the answer. It is the same
## answer the outline round the rat and the grab prompt are drawn from, which is
## why the three can never disagree.
##
## It used to be a `+` in the HUD font, which said only *here is the middle*. A
## crosshair that goes taut on a target is the cheapest way to tell a player his
## click will land before he spends it — cheaper than the outline, which is on
## the animal and can be behind a crate, and cheaper than the prompt, which is
## words.

## What it looks like at rest, and with a rat in the sights. Exported rather
## than loaded by path so a scene without a target to point at — the van, where
## there are no rats — can leave `active_texture` empty and get a crosshair that
## simply never changes.
@export var idle_texture: Texture2D
@export var active_texture: Texture2D

## How far the crosshair opens out when it finds a rat, as a fraction of its own
## size. It is a small move on a 16 px sprite at a 480x270 viewport — a couple of
## pixels — and it is deliberately small: what carries the change is the swap to
## the active art, and the scale is the flick of movement that makes the eye
## notice the swap happened.
const ACTIVE_SCALE := 1.25
## How fast it settles into either state, in fractions of the remaining distance
## per second. Fast enough to feel like a snap onto the target rather than a
## drift, slow enough to be a movement at all.
const SETTLE := 22.0

var _target := 1.0
var _scale := 1.0


func _ready() -> void:
	# Drawn from its own middle, otherwise growing on a target would push it down
	# and to the right of the point it is supposed to be marking.
	pivot_offset = size * 0.5
	if idle_texture != null:
		texture = idle_texture
	set_process(false)

	var tree := get_tree()
	if tree == null:
		return
	# Wait one frame so the player is already in the tree. Held onto before the
	# wait rather than fetched again after it: a phase can end on the frame this
	# HUD is waiting through, and the node then resumes already out of the tree
	# where `get_tree()` is null.
	await tree.process_frame

	# Out of the tree while we waited: the scene we belong to was freed and this
	# HUD is on its way out with it.
	if not is_inside_tree():
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.has_signal(&"target_changed"):
		return
	player.target_changed.connect(_on_target_changed)


func _process(delta: float) -> void:
	_scale = lerpf(_scale, _target, minf(delta * SETTLE, 1.0))
	scale = Vector2.ONE * _scale
	if is_equal_approx(_scale, _target):
		_scale = _target
		scale = Vector2.ONE * _scale
		set_process(false)


func _on_target_changed(rat: Node3D) -> void:
	var lit := rat != null
	if lit and active_texture != null:
		texture = active_texture
	elif idle_texture != null:
		texture = idle_texture
	_target = ACTIVE_SCALE if lit else 1.0
	set_process(true)
