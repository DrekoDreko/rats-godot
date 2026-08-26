@tool
class_name BigFontOutlinedLabel
extends MarginContainer


@export_range(16, 64, 16) var font_size: int = 16:
    set(value):
        font_size = value

        if not is_instance_valid(label):
            label = $Label

        label.add_theme_font_size_override("font_size", font_size)
        label.add_theme_constant_override("outline_size", 4 * (font_size / 16))


@export var text: String = "Lorem":
    set(value):
        text = value

        if not is_instance_valid(label):
            label = $Label

        label.text = text


@onready var label: Label = $Label


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
    pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
    pass
