extends SceneTree
## Throwaway: fotografa o menu principal dentro do wrapper de 640x360, do jeito
## que o jogo o desenha, e imprime a geometria dos botões.
##
## Run with: godot --script scratch/_preview_menu.gd

const SHOT := "res://scratch/menu_preview.png"

var _clock := 0


func _initialize() -> void:
	Engine.max_fps = 60


func _physics_process(_delta: float) -> bool:
	_clock += 1
	if _clock == 1:
		var wrapper := (load("res://scenes/game_post_process_wrapper.tscn") as PackedScene).instantiate()
		root.add_child(wrapper)
		return false
	if _clock == 40:
		print("janela ", root.size, "  root viewport ", root.get_visible_rect().size)
		var sub := root.get_node_or_null("GamePostProcessWrapper/Viewport") as SubViewport
		print("subviewport ", sub.size)
		var menu := sub.get_child(sub.get_child_count() - 1)
		for path in ["UI/MarginContainer", "UI/MarginContainer/LocalPlayer",
				"UI/MarginContainer/Center", "UI/MarginContainer/Center/Play",
				"UI/MarginContainer/Center/PublicLobbies",
				"UI/MarginContainer/Center/Settings",
				"UI/MarginContainer/Center/StatusLabel"]:
			var node := menu.get_node_or_null(path) as Control
			if node != null:
				print(path, " ", node.get_global_rect())
		var image := sub.get_texture().get_image()
		image.save_png(SHOT)
		print("saved ", SHOT)
		return true
	return false
