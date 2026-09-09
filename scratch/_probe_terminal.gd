extends SceneTree

func _initialize() -> void:
	for path in [
		"res://scenes/terminal_screen.tscn",
		"res://scenes/difficulty_screen.tscn",
		"res://scenes/store_screen.tscn",
		"res://scenes/map/map_viewer.tscn",
		"res://scenes/color_screen.tscn",
		"res://scenes/world.tscn",
		"res://scenes/van_travel.tscn",
		"res://scenes/menu.tscn",
		"res://scenes/menu_player_card.tscn",
	]:
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
