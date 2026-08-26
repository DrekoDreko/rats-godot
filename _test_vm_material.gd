extends Node3D

func _ready() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	var vm: Node = load("res://scenes/player_view_model.tscn").instantiate()
	add_child(vm)
	await get_tree().create_timer(2.0).timeout
	var arms := _find(vm, "Arms")
	if arms is MeshInstance3D:
		var m: ArrayMesh = arms.mesh
		print("ARMS surfaces=", m.get_surface_count(),
			" fmt=", m.surface_get_format(0),
			" mat=", m.surface_get_material(0),
			" override=", arms.get_surface_override_material(0),
			" active=", arms.get_active_material(0))
	else:
		print("NO ARMS")
	get_tree().quit()

func _find(node: Node, name: String) -> Node:
	if node.name == name:
		return node
	for c in node.get_children():
		var f := _find(c, name)
		if f != null:
			return f
	return null
