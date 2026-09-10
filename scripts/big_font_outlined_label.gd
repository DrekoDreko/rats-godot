@tool
class_name BigFontOutlinedLabel
extends MarginContainer


@export_range(8, 64, 1) var font_size: int = 16:
	set(value):
		font_size = clampi(value, 8, 64)
		_apply_font_size()


@export var text: String = "BIG_FONT_DEFAULT":
	set(value):
		text = value
		_apply_text()


## The colour of the text. It has to be a property of this scene rather than a
## `theme_override_colors/font_color` written on the node, because the node is
## the `MarginContainer` and the text belongs to the `Label` inside it — a
## colour override on a container is local to the container and never reaches
## its child, so a screen that set one that way got white text and no warning.
@export var font_color: Color = Color.WHITE:
	set(value):
		font_color = value
		_apply_font_color()


@export_range(0, 3, 1) var autowrap_mode: int = TextServer.AUTOWRAP_OFF:
	set(value):
		autowrap_mode = value
		_apply_autowrap_mode()

@export_range(0, 3, 1) var horizontal_alignment: int = HORIZONTAL_ALIGNMENT_LEFT:
	set(value):
		horizontal_alignment = value
		_apply_alignment()

@export_range(0, 3, 1) var vertical_alignment: int = VERTICAL_ALIGNMENT_TOP:
	set(value):
		vertical_alignment = value
		_apply_alignment()

@export_range(0, 4, 1) var text_overrun_behavior: int = TextServer.OVERRUN_NO_TRIMMING:
	set(value):
		text_overrun_behavior = value
		_apply_text_overrun_behavior()



@onready var label: Label = $Label


func _ready() -> void:
	_apply_font_size()
	_apply_text()
	_apply_font_color()
	_apply_autowrap_mode()
	_apply_alignment()
	_apply_text_overrun_behavior()


func _get_label() -> Label:
	if not is_instance_valid(label):
		label = get_node_or_null("Label") as Label
	return label


func _apply_font_size() -> void:
	var target := _get_label()
	if target == null:
		return
	target.add_theme_font_size_override("font_size", font_size)
	target.add_theme_constant_override("outline_size", int(font_size / 4.0))


func _apply_text() -> void:
	var target := _get_label()
	if target != null:
		target.text = text


func _apply_font_color() -> void:
	var target := _get_label()
	if target != null:
		target.add_theme_color_override("font_color", font_color)


func _apply_autowrap_mode() -> void:
	var target := _get_label()
	if target != null:
		target.autowrap_mode = autowrap_mode as TextServer.AutowrapMode


func _apply_alignment() -> void:
	var target := _get_label()
	if target == null:
		return
	target.horizontal_alignment = horizontal_alignment as HorizontalAlignment
	target.vertical_alignment = vertical_alignment as VerticalAlignment


func _apply_text_overrun_behavior() -> void:
	var target := _get_label()
	if target != null:
		target.text_overrun_behavior = text_overrun_behavior as TextServer.OverrunBehavior
