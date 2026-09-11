extends SceneTree
## Bench for the rubbish strewn across the floor (`scripts/house/litter_scatter.gd`).
##
## Both houses are opened in turn, because the whole point of sampling the
## navigation mesh rather than a hand-drawn box is that the same node works in a
## level nobody configured it for.
##
## Autoloads are fetched off `root` rather than by their global names, and phases
## are written as plain integers, for the reasons `_test_clues.gd` sets out: the
## `MainLoop` script is compiled before the autoloads are in the tree.

var _frame := 0
var _world: Node
var _session: Node
var _failures: Array[String] = []
var _first_house_positions: Array[Vector3] = []

const WORLDS := ["res://scenes/world.tscn", "res://scenes/world_2.tscn"]

## `FloorLitter.BOUNCE_TIME`, written out as a plain number. Naming the class
## would pull `floor_litter.gd` into this script's own compilation, and that file
## reaches for `AudioManager` — an autoload, which has no global identifier until
## it is in the tree, and a `MainLoop` script is compiled before it is. The same
## reason `_test_clues.gd` spells its phases and rat states as integers.
const BOUNCE_TIME := 0.28


func _initialize() -> void:
	Engine.max_fps = 60


func _physics_process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		1:
			_open(WORLDS[0])
		20:
			_check_strewn(WORLDS[0])
			_check_determinism_first_pass()
			_close()
		22:
			_open(WORLDS[1])
		40:
			_check_strewn(WORLDS[1])
			_close()
		42:
			# The same house, the same seed, a second time: the rubbish has to land
			# in exactly the same places or the four machines in a shift are walking
			# different floors.
			_open(WORLDS[0])
		60:
			_check_determinism_second_pass()
			_close()
		62:
			_mount_the_way_the_game_does()
		80:
			_check_mounted_in_the_viewport()
			_finish()
			return true
	return false


func _open(path: String) -> void:
	_session = root.get_node_or_null("SessionManager")
	_session.phase = 2
	_session.random_seed = 12345
	var packed: PackedScene = load(path)
	_world = packed.instantiate()
	root.add_child(_world)


## The house is freed outright rather than queued. A `queue_free` lands at the end
## of the frame, so the previous house's rubbish was still answering to the
## `litter` group while the next house laid its own — which read as a piece that
## had moved between two runs of the same seed, and was a fault in this bench
## rather than in the scattering.
func _close() -> void:
	if _world != null:
		root.remove_child(_world)
		_world.free()
		_world = null


# --- The rubbish ------------------------------------------------------------

func _check_strewn(where: String) -> void:
	var house := where.get_file()
	var litter := get_nodes_in_group("litter")
	_expect(litter.size() > 30,
		"%s is strewn with rubbish, %d pieces" % [house, litter.size()])
	if litter.is_empty():
		return

	# Nothing is hanging in the air. The navigation mesh both houses bake sits a
	# fifth of a metre above the boards, which is exactly what `on_the_boards`
	# exists to undo — and a piece is lifted only by half its own height.
	#
	# Checked against the boards actually underneath each piece rather than against
	# zero: `world.tscn` is a two-storey house, and half its rubbish quite properly
	# rests on an upper floor at y = 3.17. A flat height check called that floating.
	var space := (_world as Node3D).get_world_3d().direct_space_state
	var floating := 0
	var unsupported := 0
	var worst := 0.0
	for node in litter:
		var piece: Sprite3D = node
		var rest := piece.global_position.y - piece.pixel_size \
			* float(piece.texture.get_height()) * 0.5
		var from := piece.global_position + Vector3.UP * 0.5
		var query := PhysicsRayQueryParameters3D.create(from, from - Vector3.UP * 4.0, 1)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			unsupported += 1
			continue
		var gap: float = rest - (hit["position"] as Vector3).y
		worst = maxf(worst, absf(gap))
		if absf(gap) > 0.06:
			floating += 1
	_expect(unsupported == 0,
		"%s: every piece has boards under it, %d over nothing" % [house, unsupported])
	_expect(floating == 0,
		"%s: and all of it rests on them, %d adrift (worst gap %.3f m)"
			% [house, floating, worst])

	# Every piece is drawn at its art's own size — one centimetre to the pixel —
	# rather than scaled to a height written down somewhere. What is checked is
	# that the art is being drawn untouched, and that what comes out is rubbish
	# sized rather than furniture sized.
	var tallest := 0.0
	var shortest := 99.0
	var rescaled := 0
	for node in litter:
		var piece: Sprite3D = node
		if not is_equal_approx(piece.pixel_size, 0.01):
			rescaled += 1
		var drawn := piece.pixel_size * float(piece.texture.get_height())
		tallest = maxf(tallest, drawn)
		shortest = minf(shortest, drawn)
	_expect(rescaled == 0,
		"%s: every piece is drawn at the art's own size, %d rescaled" % [house, rescaled])
	_expect(tallest < 0.6, "%s: nothing is drawn oversized, tallest %.2f m" % [house, tallest])
	_expect(shortest > 0.05, "%s: nor invisibly small, shortest %.2f m" % [house, shortest])

	# All three placeholders are in use, so one bad path cannot pass unnoticed by
	# hiding behind the other two.
	var textures := {}
	for node in litter:
		textures[(node as Sprite3D).texture.resource_path] = true
	_expect(textures.size() == 3,
		"%s: all three kinds of rubbish appear, got %d" % [house, textures.size()])

	# Nobody materialises into it. The crew spawns on the doorstep and a banana
	# skin bouncing under their feet before they have walked anywhere is noise.
	var spawns := get_first_node_in_group("house_spawns") as Node3D
	var doorstep := Vector3.INF
	for child in spawns.get_children():
		var marker := child as Marker3D
		if marker != null:
			doorstep = marker.global_position
			break
	var underfoot := 0
	for node in litter:
		if (node as Node3D).global_position.distance_to(doorstep) < 4.0:
			underfoot += 1
	_expect(underfoot == 0, "%s: the doorstep is clear, %d underfoot" % [house, underfoot])

	# And no two pieces are in the same spot, which would read as one object drawn
	# wrong rather than as two things.
	var stacked := 0
	for i in litter.size():
		for j in range(i + 1, litter.size()):
			if (litter[i] as Node3D).global_position.distance_to(
					(litter[j] as Node3D).global_position) < 0.5:
				stacked += 1
	_expect(stacked == 0, "%s: nothing piled on itself, %d stacked" % [house, stacked])

	_check_litter_is_drawn(house, litter)
	_check_bounce(house, litter)


## **That the art actually reaches the screen.**
##
## This check used to assert that each piece carried a transparent, billboarded
## `material_override`, and it passed on a house where every piece of rubbish drew
## as a plain white rectangle. The assertion was about the wrong object. A
## `Sprite3D` builds its own material out of its `texture`, and a
## `material_override` **replaces** that material wholesale — so the override's own
## albedo was drawn instead, which was untextured white. The sprite had the right
## texture, the right transparency and the right billboard flag, and showed none
## of them.
##
## What is checked now is the thing that was actually wrong: nothing may stand
## between the sprite and its texture. The sprite's own flags carry the look —
## `billboard` for facing the camera, `alpha_cut` for the cut-out, `texture_filter`
## for the hard pixel edges — and the applier at the root of the world leaves it
## alone because it dresses `MeshInstance3D`s and a sprite is not one.
func _check_litter_is_drawn(house: String, litter: Array) -> void:
	var overridden := 0
	var untextured := 0
	var flat := 0
	var washed_out := 0
	for node in litter:
		var piece: Sprite3D = node
		# The one that mattered: an override here means the texture is not drawn.
		if piece.material_override != null:
			overridden += 1
		if piece.texture == null:
			untextured += 1
		# Y-billboard and not the full one. A piece of rubbish spins to face the
		# player as he walks round it, but it stays lying on the boards: under the
		# full billboard it tilted up to meet the camera, so looking down at a
		# banana skin from standing height showed it standing up at you.
		if piece.billboard != BaseMaterial3D.BILLBOARD_FIXED_Y:
			flat += 1
		# And nothing may tint the art away, which is the other road to white.
		if piece.modulate != Color.WHITE or piece.alpha_cut == SpriteBase3D.ALPHA_CUT_DISABLED:
			washed_out += 1
	_expect(overridden == 0,
		"%s: nothing stands between the sprite and its texture, %d overridden"
			% [house, overridden])
	_expect(untextured == 0, "%s: every piece carries its art, %d blank" % [house, untextured])
	_expect(flat == 0,
		"%s: and every piece turns about Y only, %d tilting up" % [house, flat])
	_expect(washed_out == 0,
		"%s: and is drawn as the art, %d washed out" % [house, washed_out])


## The hop and the rustle. Stepped by hand rather than waited on: what is being
## checked is the edge — one stir per approach, and a man standing still does not
## keep setting the same rubbish off.
func _check_bounce(house: String, litter: Array) -> void:
	var piece: Sprite3D = litter[0]
	var player := get_first_node_in_group("player") as Node3D
	var rest := piece.position.y

	# Well clear of it: nothing stirs, and the piece is armed.
	player.global_position = piece.global_position + Vector3(30.0, 0.68, 0.0)
	piece._process(1.0 / 60.0)
	_expect(is_equal_approx(piece.position.y, rest),
		"%s: rubbish nobody is near sits still" % house)

	# A man walks into it. It should be in the air on the next frame.
	player.global_position = piece.global_position + Vector3(0.4, 0.68, 0.0)
	piece._process(1.0 / 60.0)
	piece._process(1.0 / 60.0)
	_expect(piece.position.y > rest,
		"%s: walking into it makes it hop, %.3f above rest"
			% [house, piece.position.y - rest])

	# He stands there. The arc finishes and it settles back exactly on its rest
	# height rather than a frame's remainder above it, and it does not fire again.
	var elapsed := 0.0
	while elapsed < BOUNCE_TIME + 0.1:
		elapsed += 1.0 / 60.0
		piece._process(1.0 / 60.0)
	_expect(is_equal_approx(piece.position.y, rest),
		"%s: and it lands back where it was, %.4f vs %.4f"
			% [house, piece.position.y, rest])

	# Still standing on it: nothing more happens. This is the edge.
	for _tick in 20:
		piece._process(1.0 / 60.0)
	_expect(is_equal_approx(piece.position.y, rest),
		"%s: standing over it does not keep setting it off" % house)

	# He leaves and comes back, which rearms it and stirs it again.
	player.global_position = piece.global_position + Vector3(30.0, 0.68, 0.0)
	piece._process(1.0 / 60.0)
	player.global_position = piece.global_position + Vector3(0.4, 0.68, 0.0)
	piece._process(1.0 / 60.0)
	piece._process(1.0 / 60.0)
	_expect(piece.position.y > rest, "%s: walking past it again stirs it again" % house)


# --- The same floor on every machine ----------------------------------------

## Where each piece lies, ignoring how high it happens to be sitting this frame.
##
## The hop is deliberately left out of the comparison. `_check_bounce` above
## stirs the first piece of each house and reads it back mid-arc, so its height is
## whatever the bounce was doing on that frame — which is not something the seed
## decides and not something two machines have to agree about. What the seed
## decides is *where on the floor* the rubbish lies, and that is what is compared.
func _resting_places() -> Array[Vector3]:
	var places: Array[Vector3] = []
	for node in get_nodes_in_group("litter"):
		var at := (node as Node3D).global_position
		places.append(Vector3(at.x, 0.0, at.z))
	return places


func _check_determinism_first_pass() -> void:
	_first_house_positions = _resting_places()


func _check_determinism_second_pass() -> void:
	var second := _resting_places()
	_expect(second.size() == _first_house_positions.size(),
		"the same seed lays the same amount, %d vs %d"
			% [second.size(), _first_house_positions.size()])
	var moved := 0
	for i in mini(second.size(), _first_house_positions.size()):
		if second[i].distance_to(_first_house_positions[i]) > 0.001:
			moved += 1
	_expect(moved == 0, "and in the same places, %d moved" % moved)


# --- Mounted the way the game mounts it -------------------------------------

## **The check that would have caught a house with no rubbish in it at all.**
##
## Every other check in this bench adds the world straight to the root, which is
## the one arrangement the running game never uses: gameplay lives inside the
## `SubViewport` the `GamePostProcessWrapper` owns, and `current_scene` is the
## wrapper. The scattering looked for the navigation region and the house among
## the current scene's children, found neither, laid nothing, and every check here
## still passed — the player walked both houses and found not one piece.
##
## So the last thing this bench does is mount a level the way the game does.
var _viewport_wrapper: Node


func _mount_the_way_the_game_does() -> void:
	_session = root.get_node_or_null("SessionManager")
	_session.phase = 2
	_session.random_seed = 12345
	var packed: PackedScene = load("res://scenes/game_post_process_wrapper.tscn")
	_viewport_wrapper = packed.instantiate()
	root.add_child(_viewport_wrapper)
	# The wrapper being the current scene is the whole point of this check.
	current_scene = _viewport_wrapper
	_viewport_wrapper.change_scene_to_file(WORLDS[0])


func _check_mounted_in_the_viewport() -> void:
	var litter := get_nodes_in_group("litter")
	_expect(litter.size() > 30,
		"mounted in the game's own viewport it is still strewn, %d pieces"
			% litter.size())


# --- Reporting --------------------------------------------------------------

func _expect(condition: bool, what: String) -> void:
	if condition:
		print("  ok   %s" % what)
		return
	_failures.append(what)
	print("  FAIL %s" % what)


func _finish() -> void:
	if _failures.is_empty():
		print("\nlitter: every check passed")
		return
	print("\nlitter: %d FAILED" % _failures.size())
	for failure in _failures:
		print("  - %s" % failure)
