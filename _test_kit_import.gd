extends SceneTree

func _initialize() -> void:
	var names := ["wall_flat", "wall_door", "wall_window", "corner_inner", "corner_outer", "floor", "ceiling"]
	for n in names:
		var path := "res://assets/models/%s.glb" % n
		var packed := load(path) as PackedScene
		if packed == null:
			print("%s: FAIL to load" % n)
			continue
		var root := packed.instantiate()
		var mesh_inst: MeshInstance3D = null
		for child in root.find_children("*", "MeshInstance3D", true, false):
			mesh_inst = child
			break
		if mesh_inst == null:
			print("%s: no MeshInstance3D" % n)
			continue
		var aabb := mesh_inst.get_aabb()
		var mesh := mesh_inst.mesh
		var arrays := mesh.surface_get_arrays(0)
		var has_uv: bool = arrays[Mesh.ARRAY_TEX_UV] != null
		print("%-13s pos=%s size=%s verts=%d uv=%s surfaces=%d" % [
			n,
			str(aabb.position.snapped(Vector3(0.001, 0.001, 0.001))),
			str(aabb.size.snapped(Vector3(0.001, 0.001, 0.001))),
			arrays[Mesh.ARRAY_VERTEX].size(),
			str(has_uv),
			mesh.get_surface_count(),
		])
		root.free()
	quit()
