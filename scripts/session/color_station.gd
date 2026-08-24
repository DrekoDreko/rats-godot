class_name ColorStation
extends Interactable
## The board of paint samples on the wall of the van: eight squares, one per
## colour a crew can wear, and a man walks up and puts his hand on the one he
## wants.
##
## **One area, eight swatches.** The player's reach is a single ray onto a single
## interactable (see `Interactable`), so the panel is one `Area3D` and works out
## which square he was actually pointing at by where the ray landed on it
## (`_swatch_under`). That is what makes eight separate targets out of one, and
## it is why the prompt changes as he looks along the row rather than reading
## "pick your colour" the whole way across.
##
## **It decides nothing.** Pressing a swatch asks `ColorManager`, the host
## answers, and what comes back is what repaints the wall. The round trip is
## visible — the square does not become yours the instant the key is let go — and
## that is deliberate, for the reason the ready board is built the same way: a
## panel that gives you a colour on your own say-so and takes it back a moment
## later when the host disagrees is worse than one that takes a beat to be right.
##
## **A taken swatch is crossed out, not hidden.** A wall that loses a square when
## somebody takes it is a wall that changes shape as the crew fills up, and a man
## reaching for the third square from the left finds a different colour there
## every time somebody joins. So all eight stay where they are: the free ones lit
## in their own colour, the taken ones dulled with a painted X over them, and the
## one that is yours ringed in white so that you can find yourself on the wall.
##
## **Nothing here is stored.** Who is wearing what lives on `SessionManager`, and
## this reads it every time it draws. That is the whole of why the colour picked
## in the van is still on the man in the house — nobody ever copied it onto a
## node that the next scene would throw away.

## The X over a taken swatch, and the ring around our own. Both are meshes built
## in code rather than dressed in the scene, because there are eight of each and
## a scene file with sixteen more nodes in it is a scene file nobody can read.
const CROSS_THICKNESS := 0.028
const CROSS_LENGTH := 0.2
## How far in front of a swatch its mark sits. Enough to clear it and not enough
## to float.
const MARK_OFFSET := 0.022

## How dark a swatch goes once somebody else has it. Not black — a crossed-out
## square should still read as the colour it is, so that a man can see it was the
## green one that went.
const TAKEN_DIM := 0.3

## What a swatch is worth when it is free: full colour, and lit from inside the
## way a PSX panel is rather than lit by the van's lamp.
const FREE_EMISSION := 0.85
## The same for the one we are wearing, brighter so that it stands out of the row
## without anything moving.
const OURS_EMISSION := 1.4
## And for a taken one, which should not glow at all.
const TAKEN_EMISSION := 0.0

## What the prompt reads. It names the colour under the ray, so that a man knows
## what he is about to take before he takes it, and says why when he cannot.
const PROMPT_IDLE := "pick your colour"
const PROMPT_TAKE := "wear %s"
const PROMPT_TAKEN := "%s — taken"
const PROMPT_OURS := "%s — yours"

## The names of the eight, in the order `SessionManager.COLORS` has them. They
## are here rather than beside the colours because they are for reading out on a
## prompt, and the palette is a list of paints, not of words.
const COLOR_NAMES: Array[String] = [
	"red", "blue", "green", "yellow", "orange", "purple", "cyan", "pink",
]

## The row of squares. Every child `MeshInstance3D` of this node is one swatch,
## in the order the scene has them, and that order is the palette's — the first
## child is `COLORS[0]`. Building the wall is arranging eight boxes; nothing has
## to be numbered by hand.
@export var swatches_path: NodePath = ^"Swatches"

## The lamp over the panel. Optional, like every light in the van: a panel built
## without one still works, it just sits in whatever light the van has.
@export var lamp_path: NodePath = ^"Lamp"

## The refusal. Only ever heard by the man who was turned down — a buzzer for
## somebody else's mistake is noise.
@export var refused_sound_path: NodePath = ^"Refused"
## The hand on the panel, heard by everybody near it.
@export var press_sound_path: NodePath = ^"Press"

## How bright the panel's lamp burns. Low, the way the ready board's is: a small
## pool of light on the wall rather than a glow over the van.
const LAMP_ENERGY := 0.5

@onready var _swatches_root: Node3D = get_node_or_null(swatches_path) as Node3D
@onready var _lamp: OmniLight3D = get_node_or_null(lamp_path) as OmniLight3D
@onready var _refused_sound: AudioStreamPlayer3D = \
	get_node_or_null(refused_sound_path) as AudioStreamPlayer3D
@onready var _press_sound: AudioStreamPlayer3D = \
	get_node_or_null(press_sound_path) as AudioStreamPlayer3D

## The squares themselves, in palette order.
var _swatches: Array[MeshInstance3D] = []
## One material per square, private to this panel — see `_own_material`.
var _materials: Array[StandardMaterial3D] = []
## The painted X over each square, shown when somebody else has it.
var _crosses: Array[Node3D] = []
## The ring around each, shown on the one that is ours.
var _rings: Array[MeshInstance3D] = []
## Which square the ray is on, or -1 when it is on none of them. Kept only so
## that the prompt can be rewritten when it moves.
var _aimed := -1


func _ready() -> void:
	add_to_group("color_station")
	_collect_swatches()

	# Everything that can change what is painted here, and nothing that cannot.
	# There is no `_process` on this node: the wall changes when somebody takes a
	# colour, which is a handful of times in a lobby, and polling the crew every
	# frame for that would be eight squares each asking sixty times a second.
	ColorManager.color_changed.connect(_on_color_changed)
	ColorManager.request_refused.connect(_on_refused)
	SessionManager.player_joined.connect(_on_crew_changed)
	SessionManager.player_left.connect(_on_crew_changed)

	if _lamp != null:
		_lamp.light_energy = LAMP_ENERGY
	_redraw()


## The prompt has to name the square the player is actually looking at, and that
## changes as he moves his head rather than when anything in the game does. It is
## the one thing here worth a frame of work — and only while somebody is looking
## at the panel at all, which `_aim` settles in a raycast the player already
## paid for.
func _process(_delta: float) -> void:
	_update_aim()


## Hands on a square. `by` is the player who reached out, and it is ignored for
## the reason the ready board ignores it: the only body that can reach this panel
## is our own, so the overalls being painted are always this machine's.
func use(_by: Node3D) -> void:
	super.use(_by)
	var index := _aimed
	if index < 0:
		# He pressed the panel without being on a square — the housing between
		# two of them, or the edge. Nothing to ask for, and a buzzer would be
		# blaming him for the panel's own gaps.
		return
	var us := _our_steam_id()
	if SessionManager.color(us) == ColorManager.color_at(index):
		return
	_play(_press_sound)
	ColorManager.request_color(us, index)

# --- What is drawn ----------------------------------------------------------

## The whole wall, from scratch. It is eight squares and cheap enough that
## working out which one changed would cost more than repainting all of them,
## and it means there is one function to read rather than three that have to
## agree.
func _redraw() -> void:
	var us := _our_steam_id()
	for index in _materials.size():
		var material := _materials[index]
		if material == null:
			continue
		var color := ColorManager.color_at(index)
		var owner_id := ColorManager.owner_of_index(index)
		var ours := owner_id != 0 and owner_id == us
		var taken := owner_id != 0 and not ours

		material.albedo_color = color.darkened(1.0 - TAKEN_DIM) if taken else color
		material.emission = color
		if taken:
			material.emission_energy_multiplier = TAKEN_EMISSION
		elif ours:
			material.emission_energy_multiplier = OURS_EMISSION
		else:
			material.emission_energy_multiplier = FREE_EMISSION

		if index < _crosses.size() and _crosses[index] != null:
			_crosses[index].visible = taken
		if index < _rings.size() and _rings[index] != null:
			_rings[index].visible = ours
	_update_prompt()


## What the prompt reads, from whichever square the ray is on. It names the
## colour in all three cases — free, taken, ours — because "wear green" and
## "green — taken" tell a man both what is under his hand and what would happen,
## and the panel is dark enough that the square alone does not always say.
func _update_prompt() -> void:
	if _aimed < 0:
		prompt = PROMPT_IDLE
		return
	var name_of := _color_name(_aimed)
	var owner_id := ColorManager.owner_of_index(_aimed)
	if owner_id == 0:
		prompt = PROMPT_TAKE % name_of
	elif owner_id == _our_steam_id():
		prompt = PROMPT_OURS % name_of
	else:
		prompt = PROMPT_TAKEN % name_of


## Which square the player's own reach is on, worked out from where his ray meets
## the panel. Nothing is drawn from it but the prompt, so it is allowed to be
## approximate — a swatch is claimed by the box it is drawn in, in the panel's
## own space, which is exact enough for squares this far apart.
func _update_aim() -> void:
	var index := _swatch_under(_reach_point())
	if index == _aimed:
		return
	_aimed = index
	_update_prompt()


## Where our own player is pointing on this panel, in the panel's space, or a
## point far away when he is not pointing at it at all. The ray is the one the
## character already casts to find interactables — this reads its answer rather
## than casting a second one.
func _reach_point() -> Vector3:
	var ray := _reach_ray()
	if ray == null or not ray.is_colliding() or ray.get_collider() != self:
		return Vector3.INF
	return to_local(ray.get_collision_point())


## The square a point on the panel falls in, or -1 for a point on the housing
## between them. Each swatch owns a box its own size around itself, which is
## what makes the gaps real: a man on the edge between two colours is offered
## neither rather than whichever happened to be nearer.
func _swatch_under(point: Vector3) -> int:
	if point == Vector3.INF:
		return -1
	for index in _swatches.size():
		var swatch := _swatches[index]
		if swatch == null:
			continue
		var mesh := swatch.mesh as BoxMesh
		if mesh == null:
			continue
		var at := _swatches_root.transform * swatch.position
		var half := mesh.size * 0.5
		if absf(point.x - at.x) <= half.x and absf(point.y - at.y) <= half.y:
			return index
	return -1

# --- What wakes it up -------------------------------------------------------

func _on_color_changed(_steam_id: int, _color: Color) -> void:
	_redraw()


func _on_crew_changed(_steam_id: int) -> void:
	_redraw()


## The host turned us down — the colour went while our packet was in the air.
## Only heard on the machine that asked, so the buzzer plays for the man who
## reached and for nobody else.
func _on_refused(reason: String) -> void:
	_play(_refused_sound)
	print("Colour refused: %s" % reason)

# --- Building the wall ------------------------------------------------------

## The squares, in the order the scene has them, each given a private material
## and its own X and ring. Read once on the way up: the wall does not grow.
##
## A scene with fewer squares than the palette has colours is not an error — it
## is a smaller panel, and the ones past the end simply are not on this wall. The
## other way round would be, so it is said out loud.
func _collect_swatches() -> void:
	if _swatches_root == null:
		push_warning("ColorStation: no swatches under %s." % swatches_path)
		return
	for child in _swatches_root.get_children():
		var mesh := child as MeshInstance3D
		if mesh == null:
			continue
		_swatches.append(mesh)
		_materials.append(_own_material(mesh))
		_crosses.append(_build_cross(mesh))
		_rings.append(_build_ring(mesh))
	if _swatches.size() < ColorManager.count():
		push_warning("ColorStation: %d swatches on the wall for %d colours."
			% [_swatches.size(), ColorManager.count()])


## A private copy of a swatch's material, so that painting one square does not
## paint every square that shares the resource — which, a scene file having one
## `Mat_swatch` for all eight of them, is all of them. The bug it causes costs an
## evening, and the ready board pays the same toll for the same reason.
func _own_material(mesh: MeshInstance3D) -> StandardMaterial3D:
	var source := mesh.get_active_material(0) as StandardMaterial3D
	var copy: StandardMaterial3D = source.duplicate() if source != null \
		else StandardMaterial3D.new()
	# Unshaded and emissive together are what make a paint sample read as a lit
	# panel rather than as a surface somebody is shining a torch on.
	copy.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.set_surface_override_material(0, copy)
	return copy


## The X painted over a taken square: two thin bars crossed, in front of the
## swatch and dark enough to read against every colour in the palette.
func _build_cross(swatch: MeshInstance3D) -> Node3D:
	var cross := Node3D.new()
	cross.position.z = MARK_OFFSET
	cross.visible = false
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("120c0c")
	var mesh := BoxMesh.new()
	mesh.size = Vector3(CROSS_LENGTH, CROSS_THICKNESS, CROSS_THICKNESS)
	mesh.material = material
	for angle in [PI * 0.25, -PI * 0.25]:
		var bar := MeshInstance3D.new()
		bar.mesh = mesh
		bar.rotation.z = angle
		cross.add_child(bar)
	swatch.add_child(cross)
	return cross


## The white ring around the square that is ours: four thin bars round the edge,
## which is a border drawn the only way a box mesh can draw one.
func _build_ring(swatch: MeshInstance3D) -> MeshInstance3D:
	var mesh := swatch.mesh as BoxMesh
	var size := mesh.size if mesh != null else Vector3(0.2, 0.2, 0.03)
	var frame := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.WHITE
	var plate := BoxMesh.new()
	plate.size = Vector3(size.x + CROSS_THICKNESS * 2.0, size.y + CROSS_THICKNESS * 2.0,
		CROSS_THICKNESS)
	plate.material = material
	frame.mesh = plate
	# Behind the swatch rather than around it: a plate a little larger, showing
	# as a white edge on all four sides. One node instead of four, and it cannot
	# be knocked out of square.
	frame.position.z = -MARK_OFFSET
	frame.visible = false
	swatch.add_child(frame)
	return frame

# --- Odds and ends ----------------------------------------------------------

## The ray our own character reaches with, or null when there is no character —
## a bench, or a panel standing in a scene nobody is playing. It is found through
## the group the player is in rather than by path, because the panel is dressed
## into the van and knows nothing about where the player node hangs.
func _reach_ray() -> RayCast3D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0].get_node_or_null(^"Head/Camera/Interact") as RayCast3D


## Whose overalls this panel is painting. Ours, always — see `use`. Falls back to
## the only man in the crew when Steam is not running, which is what makes the
## panel work on a bench and in a solo game where `get_steam_id` answers zero.
## The same answer `ReadyStation._our_steam_id` works out, and worked out the
## same way.
func _our_steam_id() -> int:
	var steam_id := LobbyManager.our_steam_id()
	if steam_id != 0 and SessionManager.has_player(steam_id):
		return steam_id
	var crew := SessionManager.players.keys()
	return crew[0] if crew.size() == 1 else steam_id


## What a colour is called, for the prompt. Falls back to its place on the wall
## rather than to nothing, so that a palette somebody has added a ninth colour to
## still reads as a sentence.
func _color_name(index: int) -> String:
	if index < 0 or index >= COLOR_NAMES.size():
		return "colour %d" % (index + 1)
	return COLOR_NAMES[index]


## A sound, if the panel was built with one. Every one of them is optional, so
## that a panel can be dropped into a grey-box van before there is any audio in
## the project at all.
func _play(player: AudioStreamPlayer3D) -> void:
	if player != null and player.stream != null:
		player.play()
