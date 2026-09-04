extends SceneTree
## Throwaway: stands the van up on the road, opens the store and saves a shot of
## it, so the layout can be looked at without playing through the lobby.
##
## Run with: godot --script scratch/_preview_store.gd

const TRAVEL := "res://scenes/van_travel.tscn"
const TRAVEL_PHASE := 1
const SHOT := "res://scratch/store_preview.png"

var _van: Node3D
var _clock := 0


func _initialize() -> void:
	Engine.max_fps = 60


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
		var store := _van.get_node_or_null("StoreScreen")
		if OS.get_environment("STORE_CLOSED").is_empty():
			store.open()

		return false
	if _clock == 40:
		var image := root.get_texture().get_image()
		image.save_png(SHOT)
		print("saved ", SHOT)
		return true
	return false
