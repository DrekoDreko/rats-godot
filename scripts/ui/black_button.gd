extends Button
## Shared interaction sounds for the game's black button style.

func _ready() -> void:
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)


func _on_button_down() -> void:
	AudioManager.play_ui("tick")


func _on_button_up() -> void:
	AudioManager.play_ui("tick", 1.08)
