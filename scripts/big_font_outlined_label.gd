@tool
class_name BigFontOutlinedLabel
extends MarginContainer


@export_range(16, 64, 16) var font_size: int = 16:
    set(value):
        font_size = clampi(roundi(float(value) / 16.0) * 16, 16, 64)
        _apply_font_size()


@export var text: String = "Lorem":
    set(value):
        text = value
        _apply_text()


@export_range(0, 3, 1) var autowrap_mode: int = TextServer.AUTOWRAP_OFF:
    set(value):
        autowrap_mode = value
        _apply_autowrap_mode()



@onready var label: Label = $Label


func _ready() -> void:
    _apply_font_size()
    _apply_text()
    _apply_autowrap_mode()


func _get_label() -> Label:
    if not is_instance_valid(label):
        label = get_node_or_null("Label") as Label
    return label


func _apply_font_size() -> void:
    var target := _get_label()
    if target == null:
        return
    target.add_theme_font_size_override("font_size", font_size)
    target.add_theme_constant_override("outline_size", font_size / 4)


func _apply_text() -> void:
    var target := _get_label()
    if target != null:
        target.text = text


func _apply_autowrap_mode() -> void:
    var target := _get_label()
    if target != null:
        target.autowrap_mode = autowrap_mode
