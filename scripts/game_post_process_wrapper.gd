class_name GamePostProcessWrapper
extends Control
## Persistent presentation shell for the game. It owns the render pipeline and
## its SubViewport while gameplay scenes are replaced inside that viewport.
##
## The order the effects run in is the whole point of this node, and it is the
## part that is easy to get wrong:
##
##     World3D + HUD   drawn at 480x270, inside the SubViewport
##     Dither          drawn at 480x270, inside the SubViewport, above both
##     upscale         nearest-neighbour, by the SubViewportContainer
##     CRT             drawn at the window's resolution, outside everything
##
## Each of the two effects has to be on its own side of the upscale. The dither
## cell must be one game pixel, so it belongs inside; a scanline must be one
## window pixel, so it belongs outside. Swapping them gives a dither so fine it
## reads as grain and scanlines so thick they read as blinds.

## Layer of the CanvasLayer holding the dither. Everything the dither should
## quantise has to be drawn below this.
const DITHER_LAYER := 100

## Layer the HUD is moved to when the player asks for undithered UI: above the
## dither, so the interface keeps exact palette colours while the world behind
## it is quantised. See `RetroFX.ui_dithered`.
const UI_ABOVE_DITHER_LAYER := 150

## Group the gameplay HUD marks itself with, so `ui_dithered` can find it
## whatever scene is loaded and whatever the CanvasLayer is called there.
const HUD_GROUP := "retrofx_hud"

@export var initial_scene: PackedScene

var _game_scene: Node
var _game_scene_path := ""

@onready var _viewport: SubViewport = $GameViewport/Viewport
@onready var _dither: ColorRect = $GameViewport/Viewport/PostProcessLayer/Effects/Dither
@onready var _crt: ColorRect = $CRTLayer/CRT


func _ready() -> void:
	# AudioManager finds the gameplay viewport through this group, so the lookup
	# survives the wrapper being renamed or reparented.
	add_to_group(AudioManager.WRAPPER_GROUP)
	_apply_post_process_settings()
	_apply_retro_fx()
	SettingsManager.ps1_post_process_changed.connect(_apply_post_process_settings)
	RetroFX.changed.connect(_apply_retro_fx)
	if initial_scene != null:
		change_scene_to_packed(initial_scene)


## The player's own switch: whether the retro post-process runs at all.
func _apply_post_process_settings() -> void:
	_dither.visible = SettingsManager.ps1_post_process_enabled


## Pushes every calibration value from `RetroFX` into the two screen materials.
## Cheap enough to do wholesale on any change — there are a dozen uniforms and
## this only runs when a slider moves.
func _apply_retro_fx() -> void:
	var dither_material := _dither.material as ShaderMaterial
	if dither_material != null:
		dither_material.set_shader_parameter("enabled", RetroFX.dither_enabled)
		dither_material.set_shader_parameter("levels", RetroFX.levels)
		dither_material.set_shader_parameter("dither_strength", RetroFX.dither_strength)

	var crt_material := _crt.material as ShaderMaterial
	if crt_material != null:
		crt_material.set_shader_parameter("enabled", RetroFX.crt_enabled)
		crt_material.set_shader_parameter("scanline_strength", RetroFX.scanline_strength)
		# The sideways effects and the scanline pitch are measured in game
		# pixels, so the shader has to know how big the buffer it is showing is.
		crt_material.set_shader_parameter("game_resolution", Vector2(RetroFX.GAME_RESOLUTION))
		crt_material.set_shader_parameter("aberration_strength", RetroFX.aberration_strength)
		crt_material.set_shader_parameter("bleed_strength", RetroFX.bleed_strength)
		crt_material.set_shader_parameter("vignette_strength", RetroFX.vignette_strength)
		crt_material.set_shader_parameter("curvature", RetroFX.curvature)

	_apply_ui_dithering()


## Moves the gameplay HUD to either side of the dither layer.
##
## Both readings are defensible and the difference is only visible in motion, so
## this is a toggle rather than a decision baked into the scene: below the dither
## the HUD is quantised with the world, which is what Parking Garage Rally
## Circuit does and what makes the image read as a single screen; above it the
## HUD keeps exact colours and stays legible at the cost of looking pasted on.
func _apply_ui_dithering() -> void:
	var target := 0 if RetroFX.ui_dithered else UI_ABOVE_DITHER_LAYER
	for node in get_tree().get_nodes_in_group(HUD_GROUP):
		var canvas_layer := node as CanvasLayer
		if canvas_layer != null:
			canvas_layer.layer = target


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
	# The incoming scene brings its own HUD, which has to land on whichever side
	# of the dither the current setting asks for.
	_apply_ui_dithering()
	return OK


func current_game_scene() -> Node:
	return _game_scene


func current_game_scene_path() -> String:
	return _game_scene_path
