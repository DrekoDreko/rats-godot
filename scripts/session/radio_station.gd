class_name RadioStation
extends Interactable
## The two-way radio bolted to the wall of the van: the thing a player picks up
## to call somebody else in.
##
## It is Steam's own invite window behind a handset
## (`Steam.activateGameOverlayInviteDialog`), and that is the whole of what it
## does. The card asks for it to be a fitting in the van rather than a button on
## a menu, for the same reason the ready board is a plate on the wall: the lobby
## is a room, and everything the crew does in it should be something done in the
## room.
##
## **It sends nothing over the wire.** The invite is handled by Steam, entirely
## outside the game — the overlay opens, the friend gets a message, and if they
## accept, their machine turns up on the wire and knocks at `JoinGate` like
## anybody else. Nothing about this node is replicated and nothing about it is
## the host's business, which is why there is no request/answer round trip here
## and why every other station in the van has one.
##
## **It knows when it cannot help.** Three ways it can be useless — no Steam, no
## lobby (a solo run), or a shift already under way — and it says which, out
## loud, rather than opening an overlay that will not lead anywhere. The dial
## light is what says it at a glance: lit when there is somebody to call, dark
## when there is not.

## What the handset reads in each state. The prompt says what pressing it would
## do rather than what the thing is, the way the ready board's does.
const PROMPT_CALL := "call for a hand"
const PROMPT_CLOSED := "the line is dead"

## What is printed when the radio cannot do anything. Sentences, because the
## only thing done with them is putting them somewhere a player reads.
const NO_STEAM := "No Steam — there is nobody to call."
const NO_LOBBY := "You are working this one alone."
const FULL_VAN := "The van is full."

## The dial's two colours: warm amber when the line is open, near black when it
## is not. Two flat colours and no in-between, the way a panel with a lamp on it
## was in 1998.
const COLOR_OPEN := Color("ffb229")
const COLOR_DEAD := Color("140f08")

## How bright the dial burns when the line is open, and what it falls to when it
## is not. Not zero: an unlit fitting in a dark van is a fitting nobody finds.
const LAMP_ENERGY := 1.3
const LAMP_ENERGY_OFF := 0.2

## The dial face, the lamp over it and the two sounds. All optional, like every
## other fitting in the van — a radio dropped into a grey-box van before there is
## any audio in the project still works, it just says less.
@export var dial_path: NodePath = ^"Dial"
@export var lamp_path: NodePath = ^"Lamp"
## The handset going up, heard by everybody near it.
@export var press_sound_path: NodePath = ^"Press"
## The line being dead, heard only here — it is this player's own mistake and
## nobody else's business.
@export var refused_sound_path: NodePath = ^"Refused"

@onready var _dial: MeshInstance3D = get_node_or_null(dial_path) as MeshInstance3D
@onready var _lamp: OmniLight3D = get_node_or_null(lamp_path) as OmniLight3D
@onready var _press_sound: AudioStreamPlayer3D = \
	get_node_or_null(press_sound_path) as AudioStreamPlayer3D
@onready var _refused_sound: AudioStreamPlayer3D = \
	get_node_or_null(refused_sound_path) as AudioStreamPlayer3D

## The dial's own material, made private on the way up so that lighting this
## radio does not light every fitting that shares the resource.
var _dial_material: StandardMaterial3D


func _ready() -> void:
	add_to_group("radio_station")
	_dial_material = _own_material(_dial)

	# Everything that can change whether there is anybody to call, and nothing
	# that cannot. No `_process`: the line opens and closes a handful of times in
	# a lobby, and polling Steam for it every frame would be work for an answer
	# that does not move.
	LobbyManager.lobby_entered.connect(_on_lobby_entered)
	LobbyManager.lobby_left.connect(_redraw)
	SessionManager.player_joined.connect(_on_crew_changed)
	SessionManager.player_left.connect(_on_crew_changed)
	PhaseManager.phase_changed.connect(_on_phase_changed)

	_redraw()


## Hands on the handset. `by` is the player who reached out and is ignored, for
## the reason every station in the van ignores it: the only body that can reach a
## fitting is our own.
func use(_by: Node3D) -> void:
	super.use(_by)
	var closed := _closed_reason()
	if not closed.is_empty():
		_play(_refused_sound)
		print("Radio: %s" % closed)
		return
	_play(_press_sound)
	# Steam takes it from here. What comes back — if anything does — is a friend
	# turning up on the wire and knocking at `JoinGate`.
	LobbyManager.invite_friends()

# --- What is drawn ----------------------------------------------------------

## Whether anybody can be called right now, and what to say when they cannot.
## Empty when the line is open. The order matters only in that the most basic
## reason is given first — telling a man the van is full when Steam is not even
## running would be true and useless.
func _closed_reason() -> String:
	if not SteamManager.is_online:
		return NO_STEAM
	if LobbyManager.lobby_id == 0:
		return NO_LOBBY
	# The door itself is the authority on whether a newcomer would be let in, so
	# the radio asks it rather than working the same rules out a second time.
	var refusal := JoinGate.refusal_reason()
	return FULL_VAN if refusal == JoinGate.REFUSAL_FULL else refusal


## The radio, from scratch. It is a lamp and a dial face, cheap enough that
## working out which of the two changed would cost more than doing both.
func _redraw() -> void:
	var open := _closed_reason().is_empty()

	# A dead radio still offers its prompt, so that a player who presses it hears
	# why rather than wondering whether the key is broken — the same bargain the
	# ready board makes out in the hunt.
	prompt = PROMPT_CALL if open else PROMPT_CLOSED

	var color := COLOR_OPEN if open else COLOR_DEAD
	if _lamp != null:
		_lamp.light_color = COLOR_OPEN
		_lamp.light_energy = LAMP_ENERGY if open else LAMP_ENERGY_OFF
	if _dial_material != null:
		_dial_material.albedo_color = color
		# Unshaded and emissive together are what make the dial read as lit from
		# inside rather than as a surface somebody is shining a torch on.
		_dial_material.emission = color
		_dial_material.emission_energy_multiplier = 1.0 if open else 0.0

# --- What wakes it up -------------------------------------------------------

func _on_lobby_entered(_lobby_id: int, _is_host: bool) -> void:
	_redraw()


func _on_crew_changed(_steam_id: int) -> void:
	_redraw()


func _on_phase_changed(_previous: Phase.Type, _current: Phase.Type) -> void:
	_redraw()

# --- Odds and ends ----------------------------------------------------------

## A private copy of a mesh's material, so that lighting this dial does not light
## every mesh sharing the resource. Godot hands out the same `StandardMaterial3D`
## to every instance of a scene otherwise, and the ready board and the colour
## panel pay the same toll for the same reason.
func _own_material(mesh: MeshInstance3D) -> StandardMaterial3D:
	if mesh == null:
		return null
	var source := mesh.get_active_material(0) as StandardMaterial3D
	var copy: StandardMaterial3D = source.duplicate() if source != null \
		else StandardMaterial3D.new()
	copy.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.set_surface_override_material(0, copy)
	return copy


## A sound, if the radio was built with one.
func _play(player: AudioStreamPlayer3D) -> void:
	if player != null and player.stream != null:
		player.play()
