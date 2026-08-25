class_name MapTable
extends Interactable
## The physical map table standing in the back of the van.
##
## Spreads out the blueprint of the active contract on its surface and allows
## players to step up, interact (`E`), and study the plan in close inspection
## mode (`MapViewer`).
##
## **The only way in.** The blueprint is a van fixture: there is no handheld map
## in the belt, so the crew studies the plan here before the shift and carries
## what it remembers into the house. The interactive inspection logic lives
## inside `MapViewer` (`res://scripts/map/map_viewer.gd`), leaving this station
## as only the 3D furniture that holds it.

const PROMPT_READ := "study the plan"
const PROMPT_LEAVE := "step away from the table"

@export var viewer_scene: PackedScene = preload("res://scenes/map/map_viewer.tscn")
@export var lamp_path: NodePath = ^"Lamp"
@export var sheet_path: NodePath = ^"PlanSurface"
@export var open_sound_path: NodePath = ^"Open"
@export var refused_sound_path: NodePath = ^"Refused"

@onready var _lamp: OmniLight3D = get_node_or_null(lamp_path) as OmniLight3D
@onready var _sheet: MeshInstance3D = get_node_or_null(sheet_path) as MeshInstance3D
@onready var _open_sound: AudioStreamPlayer3D = get_node_or_null(open_sound_path) as AudioStreamPlayer3D
@onready var _refused_sound: AudioStreamPlayer3D = get_node_or_null(refused_sound_path) as AudioStreamPlayer3D

var _reader: Node3D
var _viewer_instance: Control
var _sheet_material: StandardMaterial3D


func _ready() -> void:
	add_to_group("map_station")
	prompt = PROMPT_READ

	_setup_sheet()
	_update_sheet_texture()

	ContractManager.contract_signed.connect(_on_contract_signed)
	PhaseManager.phase_changed.connect(_on_phase_changed)


func use(by: Node3D) -> void:
	super.use(by)
	if _reader != null:
		return
	_open(by)


func _open(by: Node3D) -> void:
	if by == null or not by.has_method("set_ui_open"):
		return
	_reader = by
	_reader.set_ui_open(true)

	if _viewer_instance == null and viewer_scene != null:
		_viewer_instance = viewer_scene.instantiate() as Control
		_hud_layer().add_child(_viewer_instance)
		_viewer_instance.closed.connect(_on_viewer_closed)

	if _viewer_instance != null:
		_viewer_instance.open()

	prompt = PROMPT_LEAVE
	_play(_open_sound)


func _close() -> void:
	if _viewer_instance != null and _viewer_instance.is_open():
		_viewer_instance.close()

	if is_instance_valid(_reader) and _reader.has_method("set_ui_open"):
		_reader.set_ui_open(false)
	_reader = null

	prompt = PROMPT_READ
	_update_sheet_texture()


func is_open() -> bool:
	return _reader != null


func _on_viewer_closed() -> void:
	if _reader != null:
		_close()


func _setup_sheet() -> void:
	if _sheet == null:
		return
	var mat := _sheet.get_active_material(0) as StandardMaterial3D
	_sheet_material = mat.duplicate() if mat != null else StandardMaterial3D.new()
	_sheet_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sheet_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sheet.set_surface_override_material(0, _sheet_material)


func _update_sheet_texture() -> void:
	if _sheet_material == null:
		return
	var contract := ContractManager.current()
	if contract != null and contract.floor_plan != null:
		_sheet_material.albedo_texture = contract.floor_plan
		_sheet_material.albedo_color = Color.WHITE
	else:
		_sheet_material.albedo_texture = null
		_sheet_material.albedo_color = Color(0.12, 0.16, 0.22, 1)


func _on_contract_signed(_id: String) -> void:
	_update_sheet_texture()


func _on_phase_changed(_previous: Phase.Type, _current: Phase.Type) -> void:
	if _reader != null:
		_close()
	_update_sheet_texture()


## The `CanvasLayer` the blueprint is drawn on.
##
## The table is a fixture of two different scenes now — the van on the road and
## the van parked at the job — and each brings its own HUD. Hunting for the layer
## by name is what lets the same table hang the same viewer in both without
## either scene having to point at it. The layer of last resort is a new one:
## a `Control` parented to this `Area3D` would be in the 3D world, where it
## draws nothing at all.
func _hud_layer() -> Node:
	var hud := get_tree().root.find_child("HUD", true, false)
	if hud != null:
		return hud

	var layer := CanvasLayer.new()
	layer.name = "MapLayer"
	get_tree().root.add_child(layer)
	return layer


func _play(player: AudioStreamPlayer3D) -> void:
	if player != null and player.stream != null:
		player.play()
