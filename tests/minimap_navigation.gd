extends SceneTree
## Run with --headless --path . --script tests/minimap_navigation.gd.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := (load("res://scenes/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await physics_frame
	await process_frame
	var navigation := world.get_node("Navigation") as NavigationRegion3D
	var mesh := navigation.navigation_mesh
	assert(mesh.get_polygon_count() > 0, "House navigation must bake")
	assert(is_equal_approx(mesh.cell_size,
		NavigationServer3D.map_get_cell_size(navigation.get_navigation_map())))
	assert(is_equal_approx(mesh.agent_radius / mesh.cell_size, 2.0))
	var minimap = _find_minimap(world)
	assert(minimap != null)
	minimap._update_navigation()
	assert(minimap._map_ready, "Minimap must contain the baked house floor")
	var player: Node3D = minimap._player
	var clipped_count := 0
	var collapsed_count := 0
	# Sweep positions and headings across the floor and outside it. In particular,
	# narrow pieces at the circular rim must never reach polygon rendering.
	for step in 360:
		var angle := deg_to_rad(float(step))
		player.position = Vector3(cos(angle) * 6.0, 1.0, sin(angle) * 5.0)
		player.rotation.y = angle
		for polygon in minimap._walkable_polygons:
			var screen := PackedVector2Array()
			for point in polygon:
				screen.append(minimap._map_to_screen(point,
					minimap._viewer_position(), minimap._viewer_yaw()))
			for piece in Geometry2D.intersect_polygons(screen, minimap._dial()):
				clipped_count += 1
				if Geometry2D.triangulate_polygon(piece).is_empty():
					collapsed_count += 1
		minimap.queue_redraw()
		await process_frame
	assert(clipped_count > 0)
	print("OK: navigation cells and clearance; 360 minimap views, %d pieces, %d collapsed" % [
		clipped_count, collapsed_count])
	world.queue_free()
	await process_frame
	quit()


func _find_minimap(node: Node) -> Node:
	if node.get_script() == load("res://scripts/minimap.gd"):
		return node
	for child in node.get_children():
		var found := _find_minimap(child)
		if found != null:
			return found
	return null
