extends CanvasLayer
## Local presentation only. PhaseManager owns the shared end of the match.

var _player: Node


func _ready() -> void:
	hide()
	PhaseManager.phase_changed.connect(_on_phase_changed)
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		return
	_player.died.connect(_on_died)
	if _player.is_dead():
		_on_died()


func _on_died() -> void:
	if PhaseManager.current() not in [Phase.Type.SURVEY, Phase.Type.HUNT]:
		return
	for path in [^"../HUD", ^"../HUD_Phase"]:
		var hud := get_node_or_null(path) as CanvasLayer
		if hud != null:
			hud.hide()
	show()


func _on_phase_changed(_previous: Phase.Type, current: Phase.Type) -> void:
	if current not in [Phase.Type.SURVEY, Phase.Type.HUNT] \
			and not PhaseManager.returning_after_team_death:
		hide()
