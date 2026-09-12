extends SceneTree
## Verify the fade between screens: black over the screen being left, black off
## the one arriving, and a scene swap that is still immediate underneath it.

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		_failures += 1


func _make_scene(scene_name: String) -> PackedScene:
	var node := Node.new()
	node.name = scene_name
	var packed := PackedScene.new()
	packed.pack(node)
	node.free()
	return packed


## Runs the wrapper's transition to its end without waiting on real seconds: the
## bench has no frame rate worth speaking of, and a tween left to the tree would
## finish somewhere between two of its frames.
func _step(tween: Tween, seconds: float) -> void:
	tween.pause()
	tween.custom_step(seconds)


func _run() -> void:
	var wrapper: Node = (load("res://scenes/game_post_process_wrapper.tscn") as PackedScene) \
		.instantiate()
	# The menu is not what is under test, and loading it here would drag the whole
	# lobby into a bench about two rectangles.
	wrapper.initial_scene = null
	root.add_child(wrapper)
	await process_frame

	var fade: ColorRect = wrapper.get_node("Fade")
	var snapshot: TextureRect = wrapper.get_node("Snapshot")
	_check(fade.mouse_filter == Control.MOUSE_FILTER_IGNORE
			and snapshot.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"The transition must never swallow a click meant for the screen")

	# First screen of the session: there is no screen being left, so it rises out
	# of black rather than crossing from one.
	var first := _make_scene("First")
	_check(wrapper.change_scene_to_packed(first) == OK, "The first scene must load")
	_check(fade.color.a == 1.0, "The first screen must start out fully black")
	_check(not snapshot.visible, "There is no screen before the first to hold")
	_step(wrapper._transition, wrapper.FADE_IN_SECONDS)
	_check(is_zero_approx(fade.color.a), "The fade in must end on a clear screen")

	# The swap itself is not delayed by the fade: `PhaseManager` waits on the
	# outgoing scene being gone before it announces the new phase.
	var outgoing: Node = wrapper.current_game_scene()
	var second := _make_scene("Second")
	_check(wrapper.change_scene_to_packed(second) == OK, "The second scene must load")
	_check(wrapper.current_game_scene() != outgoing and wrapper.current_game_scene() != null,
		"The scene must be swapped in the same call, fade or no fade")
	_check(outgoing.get_parent() == null, "The outgoing scene must leave the tree at once")
	await process_frame
	_check(not is_instance_valid(outgoing), "The outgoing scene must be freed at once")

	# The way out, driven with a picture of the old screen in hand. The bench has
	# no display to read one off, so one is handed over.
	var image := Image.create_empty(4, 4, false, Image.FORMAT_RGB8)
	image.fill(Color.RED)
	wrapper._play_transition(ImageTexture.create_from_image(image))
	_check(snapshot.visible and is_zero_approx(fade.color.a),
		"The screen being left must still be on show when the fade out starts")
	_step(wrapper._transition, wrapper.FADE_OUT_SECONDS)
	_check(fade.color.a == 1.0, "The fade out must end on a fully black screen")
	_step(wrapper._transition, wrapper.BLACK_SECONDS)
	_check(fade.color.a == 1.0, "The screen must stay off for a beat between the two")
	_check(not snapshot.visible,
		"The picture of the old screen must be dropped under cover of the black")
	_step(wrapper._transition, wrapper.FADE_IN_SECONDS)
	_check(is_zero_approx(fade.color.a), "The fade in must end on a clear screen")

	wrapper.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: fade out, fade in, and an immediate scene swap underneath")
	quit(1 if _failures > 0 else 0)
