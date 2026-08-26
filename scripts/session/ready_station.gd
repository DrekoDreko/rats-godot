class_name ReadyStation
extends Interactable
## The board a player slaps to say he is ready: a plate on the wall of the van,
## red until he has said it and green after.
##
## One node for all three phases. The board bolted inside the parked van, the one
## on the road and the button in the hall of the house are the same scene
## (`scenes/ready_station.tscn`) dropped in three places — because it is the same
## question every time, and because a second copy of it would be a second place
## for the answer to be wrong.
##
## **It decides nothing.** Slapping it asks `ReadyManager`, the host answers, and
## what comes back is what turns the plate. That round trip is visible — the
## colour does not move the instant the key is let go — and it is deliberate: a
## plate that goes green on our own say-so and red again a moment later when the host
## disagrees is worse than one that takes a beat to be right. What is drawn here
## is never this machine's opinion, only the host's.
##
## **It draws the whole crew and not only us.** The plate is our own flag, and the
## row of small bulbs beside it is one per player in the crew, in the order they
## walked in — so a man standing at the board can see who he is waiting on
## without opening anything. A bulb is lit in that player's own colour when he is
## ready and left dark when he is not, which is also why the colour station
## (a later card) has nothing to do here: it writes to `SessionManager`, and this
## reads from it like everything else.
##
## **It goes dark where ready means nothing.** Out in the hunt there is no show
## of hands to take, so the board unlights itself and stops offering the prompt
## rather than standing there taking presses that will be refused.
##
## What it does *not* do is check whether the shift may move: that is the host's,
## in `ReadyManager`, and a board that tried to work it out locally would be a
## fourth machine with an opinion about when the van leaves.

## The two colours the board reads in ordinarily. Saturated and few, the way a
## panel with a couple of states on it was in 1998.
const COLOR_WAITING := Color("ff2222")
const COLOR_READY := Color("22ff44")

## And a third, for the one state that is neither: everybody has said it and the
## shift is still standing, because nothing is signed yet
## (`ReadyManager.blocked`). Green there would be a board telling the crew the van
## is about to leave when it is not — the amber is the same one the wall sheet
## prints an unsigned job in, so the two read as the same piece of news.
const COLOR_HELD := Color("ffb229")

## What a crew bulb looks like when its player has not said it yet — near black
## rather than off, so that the row still reads as a row of four and a man can
## count the empty places.
const CREW_DARK := Color("140a0a")

## What the prompt reads in each of the two states. The board says what pressing
## it would do, not what it is: "ready up" on a board that is red.
const PROMPT_READY_UP := "ready up"
const PROMPT_STAND_DOWN := "stand down"

## The plate itself and the row of crew bulbs. Both are optional — a board built
## without either still works, it just says less — which is what lets the button
## in the hall of the house be a bare button.
@export var plate_path: NodePath = ^"Plate"
@export var crew_path: NodePath = ^"Crew"

## The slap and the buzzer. The first plays wherever the board is, for everybody
## in earshot; the second only on the machine that was turned down, because a
## refusal is nobody else's business.
@export var press_sound_path: NodePath = ^"Press"
@export var refused_sound_path: NodePath = ^"Refused"

@onready var _plate: MeshInstance3D = get_node_or_null(plate_path) as MeshInstance3D
@onready var _crew: Node3D = get_node_or_null(crew_path) as Node3D
@onready var _press_sound: AudioStreamPlayer3D = \
	get_node_or_null(press_sound_path) as AudioStreamPlayer3D
@onready var _refused_sound: AudioStreamPlayer3D = \
	get_node_or_null(refused_sound_path) as AudioStreamPlayer3D

## The plate's own material, made private on the way up so that turning this
## board green does not turn every other board in the van green with it.
var _plate_material: StandardMaterial3D

## One material per crew bulb, private for the same reason.
var _crew_materials: Array[StandardMaterial3D] = []


func _ready() -> void:
	add_to_group("ready_station")
	_plate_material = _own_material(_plate)
	for child in _crew_children():
		_crew_materials.append(_own_material(child))

	# Everything that can change what is drawn here, and nothing that cannot.
	# There is no `_process` on this node on purpose: a board that polled the
	# crew every frame would be four boards each asking the same question sixty
	# times a second for an answer that changes twice a minute.
	SessionManager.player_changed.connect(_on_crew_changed)
	SessionManager.player_joined.connect(_on_crew_changed)
	SessionManager.player_left.connect(_on_crew_changed)
	PhaseManager.phase_changed.connect(_on_phase_changed)
	ReadyManager.request_refused.connect(_on_refused)
	# The van being held has nothing to do with the crew, so nothing above says
	# it changed: without this the board would keep drawing green through a
	# signature landing and being torn up again.
	ReadyManager.hold_changed.connect(_on_hold_changed)

	_redraw()


## Hands on the plate. `by` is the player who reached out, and it is ignored: the
## only body that can reach a board is our own — an avatar of somebody else is a
## capsule on our screen and has no hands here — so the flag being asked after is
## always this machine's own.
func use(_by: Node3D) -> void:
	super.use(_by)
	if not ReadyManager.is_active():
		_play(_refused_sound)
		return
	_play(_press_sound)
	ReadyManager.request_toggle(_our_steam_id())

# --- What is drawn ----------------------------------------------------------

## The board, from scratch. It is cheap enough that working out what exactly
## changed would cost more than doing all of it, and it means there is one
## function to read rather than four that have to agree.
func _redraw() -> void:
	var active := ReadyManager.is_active()
	# `is_ready` and not `ready`, which is a signal on `Node` that a local of
	# that name would shadow for the rest of the function.
	var is_ready := active and ReadyManager.is_ready(_our_steam_id())

	# A board where ready means nothing still offers the prompt it would offer,
	# so that a player who presses it hears why rather than wondering whether
	# the key is broken. What goes is the colour, not the prompt.
	prompt = PROMPT_STAND_DOWN if is_ready else PROMPT_READY_UP

	# Green only when saying it is actually worth something. With the shift held
	# the plate goes amber instead: the flag is up, and the van is not going
	# anywhere until somebody signs a job.
	var held := is_ready and ReadyManager.blocked
	var color := COLOR_WAITING
	if is_ready:
		color = COLOR_HELD if held else COLOR_READY
	if _plate_material != null:
		_plate_material.albedo_color = color if active else CREW_DARK
		# Unshaded and emissive together are what make a PSX panel read as lit
		# from inside rather than as a surface somebody is shining a torch on.
		_plate_material.emission = color
		_plate_material.emission_energy_multiplier = 1.0 if (is_ready and active) else 0.0
	_redraw_crew(active)


## The row of bulbs: one per player in the crew, lit in his own colour when he is
## ready. Bulbs past the end of the crew go dark rather than hidden, so that the
## row keeps the shape of the van — four places, however many of them are filled.
func _redraw_crew(active: bool) -> void:
	var crew := SessionManager.players.keys()
	for index in _crew_materials.size():
		var material := _crew_materials[index]
		if material == null:
			continue
		var lit := active and index < crew.size() and SessionManager.is_ready(crew[index])
		var color: Color = SessionManager.color(crew[index]) if lit else CREW_DARK
		material.albedo_color = color
		material.emission = color
		material.emission_energy_multiplier = 1.0 if lit else 0.0

# --- What wakes it up -------------------------------------------------------

func _on_crew_changed(_steam_id: int) -> void:
	_redraw()


func _on_phase_changed(_previous: Phase.Type, _current: Phase.Type) -> void:
	_redraw()


## The van was held, or let go. Only the plate's own colour moves with it — the
## crew bulbs are flags and not permission.
func _on_hold_changed(_held: bool) -> void:
	_redraw()


## The host turned us down. Only heard on the machine that asked, so the buzzer
## plays for the man who pressed and for nobody else.
func _on_refused(reason: String) -> void:
	_play(_refused_sound)
	print("Ready refused: %s" % reason)

# --- Odds and ends ----------------------------------------------------------

## Whose flag this board is asking after. Ours, always — see `use`. Falls back to
## whatever the crew is when Steam is not running, which is what makes the board
## work on a bench and in a solo game where `get_steam_id` answers zero.
func _our_steam_id() -> int:
	var steam_id := LobbyManager.our_steam_id()
	if steam_id != 0 and SessionManager.has_player(steam_id):
		return steam_id
	# No Steam and one player: he is the only man in the van, so he is the one
	# the board is for. With nobody registered at all there is no flag to move,
	# and zero is what `request_set` throws away.
	var crew := SessionManager.players.keys()
	return crew[0] if crew.size() == 1 else steam_id


## A private copy of a mesh's material, so that a board can be turned green
## without every board sharing the resource turning green with it. Godot hands
## out the same `StandardMaterial3D` to every instance of a scene otherwise, and
## the bug it causes — press one board, watch three light up — costs an evening.
func _own_material(mesh: MeshInstance3D) -> StandardMaterial3D:
	if mesh == null:
		return null
	var source := mesh.get_active_material(0) as StandardMaterial3D
	var copy: StandardMaterial3D = source.duplicate() if source != null \
		else StandardMaterial3D.new()
	copy.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.set_surface_override_material(0, copy)
	return copy


## The bulbs, in the order they sit in the scene. Read once on the way up rather
## than every redraw: the row does not grow.
func _crew_children() -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if _crew == null:
		return found
	for child in _crew.get_children():
		var mesh := child as MeshInstance3D
		if mesh != null:
			found.append(mesh)
	return found


## A sound, if the board was built with one. Every one of them is optional, so
## that a board can be dropped into a grey-box van before there is any audio in
## the project at all.
func _play(player: AudioStreamPlayer3D) -> void:
	if player != null and player.stream != null:
		player.play()
