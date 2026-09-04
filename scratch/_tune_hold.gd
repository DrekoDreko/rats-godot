extends SceneTree
## Throwaway: overrides one item's hold numbers from the environment and saves
## the preview blown up, so the placement can be tried without editing a .tres
## between every attempt.
##
##   STORE_ITEM=broom OFF=0,0,0.1 ROT=0,0,90 SCL=0.06 godot ... --script scratch/_tune_hold.gd

const TRAVEL := "res://scenes/van_travel.tscn"
const TRAVEL_PHASE := 1

var _van: Node3D
var _clock := 0
var _item := ""

func _initialize() -> void:
	Engine.max_fps = 60
	_item = OS.get_environment("STORE_ITEM")
	if _item.is_empty():
		_item = "baseball_bat"

func _vec(name: String, fallback: Vector3) -> Vector3:
	var raw := OS.get_environment(name)
	if raw.is_empty():
		return fallback
	var parts := raw.split(",")
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))

func _physics_process(_delta: float) -> bool:
	_clock += 1
	if _clock == 1:
		var session := root.get_node_or_null("SessionManager")
		var phase := root.get_node_or_null("PhaseManager")
		session.register_player(111, "Lucas", true)
		phase.scenes[TRAVEL_PHASE] = ""
		phase.go_to(TRAVEL_PHASE)
		phase.scenes[TRAVEL_PHASE] = TRAVEL
		_van = (load(TRAVEL) as PackedScene).instantiate() as Node3D
		root.add_child(_van)
		return false
	if _clock == 20:
		var store = _van.get_node_or_null("StoreScreen")
		store.open()
		var shop := root.get_node_or_null("ShopManager")
		var item: StoreItem = shop.find(_item)
		if item == null:
			print("no such item ", _item)
			return true
		item.preview_offset = _vec("OFF", item.preview_offset)
		item.preview_rotation = _vec("ROT", item.preview_rotation)
		var scl := OS.get_environment("SCL")
		if not scl.is_empty():
			item.preview_height = float(scl)
		store._select(item)
		var view: SubViewport = store._preview
		view.size = Vector2i(360, 720)
		return false
	if _clock == 60:
		var store = _van.get_node_or_null("StoreScreen")
		var view: SubViewport = store._preview
		view.get_texture().get_image().save_png("res://scratch/tune_%s.png" % _item)
		print("saved tune_%s.png" % _item)
		return true
	return false
