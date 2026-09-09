extends SceneTree

func _initialize() -> void:
	for path in ["res://scenes/hud_game.tscn", "res://scenes/world.tscn", "res://scenes/van_travel.tscn"]:
		var packed := load(path) as PackedScene
		if packed == null:
			print("FAIL load ", path)
			continue
		var node := packed.instantiate()
		if node == null:
			print("FAIL instantiate ", path)
			continue
		print("OK ", path, " -> ", node.name)
		node.free()
	quit()
