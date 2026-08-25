extends SceneTree
## The name over a player's head, and how far off it is still worth reading.
##
## The fade lives in `player_avatar.gd` rather than in `player_avatar.tscn`, and
## that is the first thing this bench is here to hold down: a `Label3D` has no
## `distance_fade_*` of its own — those belong to `BaseMaterial3D` — so the
## obvious version of this feature is four lines in the scene file that load
## without a word of complaint and never fade anything. A test that only read
## the scene would have passed on that. This one moves a camera and reads what
## came out.
##
## The avatar is stood up by hand instead of through `PlayerAvatars`, and the
## viewpoint is handed to `fade_tag` rather than moving a `Camera3D` about: a
## camera is only ever current in a viewport that is really drawing, so headless
## there is no camera to move and a fade that read one itself could not be
## measured here at all.

const AVATAR_SCENE := preload("res://scenes/player_avatar.tscn")

## Far enough past the fade's end to be unambiguous, and far enough inside its
## start likewise. Reading exactly on the boundary would make the bench an
## argument about the last decimal place rather than about the behaviour.
const NEAR := 2.0
const FAR := 40.0

var _avatar: PlayerAvatar
var _tag: Label3D
var _failures := 0
var _frames := 0


func _initialize() -> void:
	Engine.max_fps = 60

	var world := Node3D.new()
	world.name = "World"
	root.add_child(world)

	_avatar = AVATAR_SCENE.instantiate()
	_avatar.name = "PlayerX"
	_avatar.peer_id = 2
	_avatar.player_name = "Verminator"
	# Somebody else's body: ours is never drawn, and `_process` — where the fade
	# runs — is switched off on it. Authority is set before the node enters the
	# tree for the same reason the crowd does it there.
	_avatar.set_multiplayer_authority(2)
	world.add_child(_avatar)
	_tag = _avatar.get_node("Name")


func _physics_process(_delta: float) -> bool:
	_frames += 1
	# One frame for `_ready` to have run everywhere before anything is asked.
	if _frames == 1:
		return false
	if _frames == 2:
		_expect(_tag.text == "Verminator", "the name should be written over the body")
		# Nothing is drawn before the first packet lands, so the body is told
		# where it stands the way the wire would have told it.
		_avatar.sync_position = Vector3.ZERO
		_avatar._on_synchronized()
		_expect(_avatar.visible, "and the body should be up once it knows where it stands")
		return false

	if _frames == 3:
		# What the scene was built with. The fade scales these rather than
		# setting them, so "full strength" means "back to what the scene said" —
		# and the outline is deliberately not opaque.
		var full := _avatar._tag_alpha
		var full_outline := _avatar._tag_outline_alpha
		_expect(full_outline < 1.0,
			"the outline should be built part transparent, and is %.2f" % full_outline)

		_avatar.fade_tag(Vector3(0.0, 0.0, NEAR))
		_expect(is_equal_approx(_tag.modulate.a, full),
			"a teammate in the same room should be named at full strength, and is %.2f"
				% _tag.modulate.a)
		_expect(is_equal_approx(_tag.outline_modulate.a, full_outline),
			"and his outline no darker than the scene built it, and is %.2f"
				% _tag.outline_modulate.a)
		_expect(_tag.visible, "and his name drawn")
		_avatar.fade_tag(Vector3(0.0, 0.0, FAR))
		_expect(is_zero_approx(_tag.modulate.a),
			"a man across the map should have no name over him, and has %.2f" % _tag.modulate.a)
		_expect(not _tag.visible, "and nothing drawn at all")
		_expect(is_zero_approx(_tag.outline_modulate.a),
			"the outline should have gone with it, and is %.2f" % _tag.outline_modulate.a)
		# Halfway between the two distances: the point of a fade is the middle.
		_avatar.fade_tag(Vector3(
			0.0, 0.0, (PlayerAvatar.TAG_FULL_DISTANCE + PlayerAvatar.TAG_FADE_DISTANCE) * 0.5
		))
		var half := _tag.modulate.a
		_expect(half > full * 0.1 and half < full * 0.9,
			"between the two it should be part way out, and is %.2f" % half)
		_expect(_tag.visible, "and still drawn while any of it is left")
		print("--- %d frame(s), %d failure(s) ---" % [_frames, _failures])
		quit(1 if _failures > 0 else 0)
	return false


func _expect(condition: bool, what: String) -> void:
	if condition:
		return
	print("FAIL: %s" % what)
	_failures += 1
