extends SceneTree
## Prints where the rats actually land when the hunt starts, and where the
## player is standing when it does.

const HOUSE_SCENE := "res://scenes/world.tscn"
const SURVEY := 2
const HUNT := 3
const ANA := 111

var _phase: Node
var _session: Node
var _contract: Node
var _step := 0
var _clock := 0
var _house: Node


func _initialize() -> void:
	Engine.max_fps = 60
	_session = root.get_node_or_null("SessionManager")
	_phase = root.get_node_or_null("PhaseManager")
	_contract = root.get_node_or_null("ContractManager")


func _physics_process(_delta: float) -> bool:
	_clock += 1
	match _step:
		0:
			_session.reset()
			_session.register_player(ANA, "Ana", true)
			_contract.sign("hallow_street")
			_phase.set_house(HOUSE_SCENE)
			_phase.go_to(SURVEY)
			_step = 1
			_clock = 0
		1:
			if _clock < 8:
				return false
			_house = current_scene
			var player := get_first_node_in_group("player") as Node3D
			print("player at ", player.global_position if player != null else "NONE")
			print("holes:")
			for h in get_nodes_in_group("rat_holes"):
				print("  ", h.name, " ", (h as Node3D).global_position)
			_phase.go_to(HUNT)
			_step = 2
			_clock = 0
		2:
			if _clock < 8:
				return false
			var player := get_first_node_in_group("player") as Node3D
			print("--- hunt started, player at ", player.global_position if player != null else "NONE")
			for r in get_nodes_in_group("rats"):
				var rat := r as Node3D
				var d := 0.0
				if player != null:
					d = rat.global_position.distance_to(player.global_position)
				print("  ", rat.name, " pos=", rat.global_position, " visible=", (rat as Node3D).visible, " dist=", d)
			_step = 3
			_clock = 0
		3:
			if _clock < 120:
				return false
			var player := get_first_node_in_group("player") as Node3D
			print("--- after 2s")
			for r in get_nodes_in_group("rats"):
				var rat := r as Node3D
				print("  ", rat.name, " pos=", rat.global_position)
			quit(0)
	return false
