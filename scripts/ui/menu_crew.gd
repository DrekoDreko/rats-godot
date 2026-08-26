class_name MenuCrew
extends Node3D
## The bodies on the menu screen: one hazmat per player in the lobby, sat in a
## row facing the camera.
##
## It is the menu's answer to `player_avatars.gd`, and it is worth saying how the
## two differ, because the similarity invites the wrong shortcut. There, a body
## is a live thing: it has an owner on the wire, a `MultiplayerSynchronizer`
## feeding it a position twenty times a second, and a handshake to make sure
## nobody's packet arrives before the node that reads it. Here nothing moves and
## nothing crosses the wire. A body is a drawing of a crew entry, and when the
## crew changes the drawing is done again.
##
## **It is told who to draw rather than looking it up.** `menu_screen.gd` is what
## decides, because the answer is not the same in every session: over Steam the
## crew is the lobby's guest list, and alone it is the one man `SessionManager`
## seated who has no guest list at all. Two callers reading that differently is
## exactly the bug where a solo player looks at an empty floor.
##
## That is why this instances `player_model.tscn` and not `player_avatar.tscn`.
## The avatar brings a synchroniser, a capture point and an interpolator, all of
## which would sit idle — and a synchroniser with no authority on a screen with
## no wire is a thing that can only go wrong.
##
## **The seats are nodes, not numbers.** They are `Marker3D`s in the scene so
## that moving somebody is dragging him in the editor, which matters because this
## screen is going to grow scenery around the crew.

## The body. `player_model.tscn` carries its own PS1 applier, so a hazmat put
## here already matches the ones in the van.
const MODEL_SCENE := preload("res://scenes/player_model.tscn")

## What the men are doing while they wait: crouched and still, which
## `player_model.gd` plays as `CrouchIdle`. The crouch animation lowers the body
## on its own — the same thing `player_avatar.gd` relies on — so the seats sit at
## standing height and the pose does the rest.
const SEATED := PlayerAvatar.State.CROUCHING

## Where the seats are, in the order they are filled.
@export var seats_path: NodePath = ^"Seats"

## The bodies on screen, by account. Keyed by Steam ID and not by seat, because
## the seat a man is in changes when somebody ahead of him leaves and his account
## does not.
var _bodies: Dictionary[int, PlayerModel] = {}

## Which seat each account is in, so that a card can find the body it belongs to
## without walking the tree.
var _seats_taken: Dictionary[int, Node3D] = {}

@onready var _seats: Node3D = get_node_or_null(seats_path) as Node3D


func _ready() -> void:
	# The crew list can change while the tree is paused — a friend accepting an
	# invite does not wait for a menu to be looked at.
	process_mode = Node.PROCESS_MODE_ALWAYS

	ColorManager.color_changed.connect(_on_color_changed)
	SessionManager.player_changed.connect(_on_player_changed)


## Draws the crew as it now stands. Bodies for accounts that are gone are freed,
## bodies for accounts that are new are built, and everybody who stayed keeps the
## model he had — rebuilding a hazmat that has not changed would restart its
## animation, and four men blinking every time a fifth knocks is a visible bug.
func rebuild(players: Array[Dictionary]) -> void:
	if _seats == null:
		return

	var seats := _seats.get_children()
	var seen: Dictionary[int, bool] = {}

	for index in mini(players.size(), seats.size()):
		var steam_id := int(players[index]["steam_id"])
		if steam_id == 0:
			continue
		var seat := seats[index] as Node3D
		if seat == null:
			continue
		seen[steam_id] = true
		_seats_taken[steam_id] = seat
		_place(steam_id, seat)

	for steam_id in _bodies.keys():
		if not seen.has(steam_id):
			_bodies[steam_id].queue_free()
			_bodies.erase(steam_id)
			_seats_taken.erase(steam_id)


## Where a player is sitting, or null for one who is not on screen. What the
## floating cards anchor themselves to.
func seat_of(steam_id: int) -> Node3D:
	return _seats_taken.get(steam_id)


## How many bodies are up. For the benches, which need to see that a crew of four
## became four hazmats and not three.
func count() -> int:
	return _bodies.size()


## The model for an account, or null. Also for the benches — the thing worth
## asserting about a body is which animation it is playing and what colour it is,
## and both are read off the model.
func body_of(steam_id: int) -> PlayerModel:
	return _bodies.get(steam_id)

# --- Building and painting --------------------------------------------------

## Puts a man in a seat, building him first if he is new. A body that is already
## in the right seat is left alone but still repainted, since the thing that
## brought us here may have been a colour change.
func _place(steam_id: int, seat: Node3D) -> void:
	var body: PlayerModel = _bodies.get(steam_id)
	if body == null:
		body = MODEL_SCENE.instantiate() as PlayerModel
		_bodies[steam_id] = body
		seat.add_child(body)
		# The pose is set after the model is in the tree: `set_state` reaches for
		# the `AnimationPlayer` through an `@onready`, which is not resolved
		# before then.
		body.set_state(SEATED)
	elif body.get_parent() != seat:
		body.reparent(seat, false)

	body.transform = Transform3D.IDENTITY
	body.set_tint(SessionManager.color(steam_id))


## Repaints one man. The colour lives on `SessionManager` and is put there by the
## host, so there is nothing to decide here — only something to redraw.
func _repaint(steam_id: int) -> void:
	var body: PlayerModel = _bodies.get(steam_id)
	if body != null:
		body.set_tint(SessionManager.color(steam_id))

# --- What the autoloads say -------------------------------------------------


func _on_color_changed(steam_id: int, _color: Color) -> void:
	_repaint(steam_id)


## A crew entry changed — which covers the colour a man is born wearing, written
## straight into `SessionManager` by `register_player` without `ColorManager`
## ever being asked. Without this a body seated before the host confirms the
## palette stays white.
func _on_player_changed(steam_id: int) -> void:
	_repaint(steam_id)
