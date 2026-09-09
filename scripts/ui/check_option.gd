class_name CheckOption
extends Button
## A toggle drawn the way the contract sheets are: a hollow box beside the
## label, filled in once the option is the one picked.
##
## Godot's own `CheckBox` draws its box from a theme icon, and this game has no
## icon to hand it. The box here is a `StyleBoxFlat` instead — the same hollow
## outline the sheets and the rat dots are drawn with — while the label stays
## the button's own `text`, so the pressed, hovered and disabled colours the
## theme already knows about keep working.

## The line colour the vote screen is drawn in. Taken from the card rather than
## written out again here: a box that disagreed with the sheet beside it would
## be the one thing on the screen that looked like a mistake.
const LINE_COLOR := ContractVoteCard.LINE_COLOR

@onready var _box: Panel = $Box


func _ready() -> void:
	toggled.connect(_on_toggled)
	_refresh_box()


func _on_toggled(_pressed: bool) -> void:
	_refresh_box()


func _refresh_box() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = LINE_COLOR if button_pressed else Color(0, 0, 0, 0)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = LINE_COLOR
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	_box.add_theme_stylebox_override("panel", style)
