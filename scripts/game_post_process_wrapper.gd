class_name GamePostProcessWrapper
extends SubViewportContainer
## Persistent presentation shell for the game. It owns the post-process material
## and its SubViewport while gameplay scenes are replaced inside that viewport.

@export var initial_scene: PackedScene

var _game_scene: Node
var _game_scene_path := ""

@onready var _viewport: SubViewport = $Viewport


func _ready() -> void:
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
	if _game_scene != null:
		_viewport.remove_child(_game_scene)
		_game_scene.queue_free()
	_viewport.add_child(incoming)
	_game_scene = incoming
	_game_scene_path = scene.resource_path
	return OK


func current_game_scene() -> Node:
	return _game_scene


func current_game_scene_path() -> String:
	return _game_scene_path
