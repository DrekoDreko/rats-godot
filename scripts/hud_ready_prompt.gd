@tool
extends BigFontOutlinedLabel
## The ready instruction above the health bar. It is only shown while the
## current phase accepts a ready vote.

func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	PhaseManager.phase_changed.connect(_on_phase_changed)
	_refresh()


func _on_phase_changed(_previous: Phase.Type, _current: Phase.Type) -> void:
	_refresh()


func _refresh() -> void:
	visible = ReadyManager.is_active()
