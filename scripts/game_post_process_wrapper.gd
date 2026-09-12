class_name GamePostProcessWrapper
extends Control
## Persistent presentation shell for the game. It owns the low-resolution
## SubViewport while gameplay scenes are replaced inside it.
##
## The whole pipeline is now two steps:
##
##     World3D + HUD   drawn at 640x360, inside the SubViewport
##     upscale         nearest-neighbour, by the SubViewportContainer
##
## There is deliberately no screen-space effect left. The retro look is produced
## entirely by the renderer itself — the near-white ambient, the black distance
## fog and the `adjustment_*` grade on the environment, plus the vertex snap in
## `shaders/common.gdshaderinc` — rather than by a filter pasted over the top.
## A dither or a CRT pass on the gameplay image fights that grade instead of
## adding to it.
##
## The one thing laid over the top is the fade between screens, and it lives here
## because this is the one place every screen change passes through — `Fade` and
## `Snapshot` are outside the SubViewport, so no gameplay scene can see them and
## none of them has to know a transition exists. See `_capture_screen`.

## How long the screen being left takes to sink into black, how long it stays
## off, and how long the one arriving takes to rise back out of it.
##
## The screen is held fully black for a beat in the middle on purpose. A fade
## that turns straight round at the bottom reads as a dip rather than as one
## screen ending and another starting, and the beat is also where the new
## scene's first stuttering frames go.
const FADE_OUT_SECONDS := 0.45
const BLACK_SECONDS := 0.2
const FADE_IN_SECONDS := 0.6

@export var initial_scene: PackedScene

var _game_scene: Node
var _game_scene_path := ""
var _transition: Tween

@onready var _viewport: SubViewport = $GameViewport/Viewport
@onready var _snapshot: TextureRect = $Snapshot
@onready var _fade: ColorRect = $Fade


func _ready() -> void:
	# AudioManager finds the gameplay viewport through this group, so the lookup
	# survives the wrapper being renamed or reparented.
	add_to_group(AudioManager.WRAPPER_GROUP)
	if initial_scene != null:
		change_scene_to_packed(initial_scene)


## Replaces the gameplay scene without replacing this wrapper or its viewport.
## The outgoing scene leaves the tree before the incoming scene is added, so
## groups and autoload signal connections never overlap between scenes.
func change_scene_to_file(path: String) -> Error:
	if path.is_empty():
		return ERR_INVALID_PARAMETER
	var scene := ResourceLoader.load(path) as PackedScene
	if scene == null:
		push_error("GamePostProcessWrapper: could not load %s" % path)
		return ERR_FILE_NOT_FOUND
	return change_scene_to_packed(scene)


func change_scene_to_packed(scene: PackedScene) -> Error:
	if scene == null:
		return ERR_INVALID_PARAMETER
	var incoming := scene.instantiate()
	if incoming == null:
		return ERR_CANT_CREATE
	# The wrapper must keep forwarding input while paused so an always-processing
	# pause menu can receive its resume click. Keep the gameplay scene itself
	# pausable, otherwise it would inherit the wrapper's always mode.
	incoming.process_mode = Node.PROCESS_MODE_PAUSABLE
	# Grabbed while the outgoing scene is still the thing being drawn: it is what
	# the fade out fades, and a frame later there would be nothing left to take
	# it from.
	var last_frame := _capture_screen() if _game_scene != null else null
	if _game_scene != null:
		_viewport.remove_child(_game_scene)
		_game_scene.queue_free()
	_viewport.add_child(incoming)
	_game_scene = incoming
	_game_scene_path = scene.resource_path
	_play_transition(last_frame)
	return OK


func current_game_scene() -> Node:
	return _game_scene


func current_game_scene_path() -> String:
	return _game_scene_path


## The last frame of the outgoing screen, as a picture that outlives the scene
## that drew it.
##
## **The swap itself is not delayed by the fade, and must not be.** The outgoing
## scene is taken out and freed in the same call as always — `PhaseManager`
## waits on exactly that before it announces the new phase, and a scene held on
## screen for another fifth of a second would be a scene still answering signals
## it has no business hearing. So the fade is pixels only: this picture stands in
## for the screen that has already gone, while the one that replaced it is
## alive and hidden underneath it.
func _capture_screen() -> Texture2D:
	# Nothing is drawn with no display, and the read back would only cost a stall
	# and an error in the test benches.
	if DisplayServer.get_name() == "headless":
		return null
	var texture := _viewport.get_texture()
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


## Black over the old screen, then black off the new one. With no picture of the
## old screen to hold — the first scene of the session, or a frame that could not
## be read — there is nothing to fade out of, and the new screen simply rises out
## of black.
func _play_transition(last_frame: Texture2D) -> void:
	if _transition != null and _transition.is_valid():
		_transition.kill()
	_snapshot.texture = last_frame
	_snapshot.visible = last_frame != null
	_fade.color.a = 0.0 if last_frame != null else 1.0
	_transition = create_tween()
	if last_frame != null:
		_transition.tween_property(_fade, "color:a", 1.0, FADE_OUT_SECONDS)
		# Dropped under cover of the fully black screen, so the swap from the old
		# picture to the live scene underneath is never a visible cut.
		_transition.tween_callback(_drop_snapshot)
		_transition.tween_interval(BLACK_SECONDS)
	_transition.tween_property(_fade, "color:a", 0.0, FADE_IN_SECONDS)


func _drop_snapshot() -> void:
	_snapshot.visible = false
	_snapshot.texture = null
