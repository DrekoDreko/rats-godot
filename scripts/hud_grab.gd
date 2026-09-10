@tool
extends BigFontOutlinedLabel
## The line that says the rat in front of the player is close enough to grab.
##
## It keeps no rule of its own and measures nothing. Whether a rat is within
## reach is the weapon's question and the player is the one who asks it every
## frame (`player.gd: _update_target`); this only writes down the answer, and it
## goes off the screen the moment there is no rat in the sights — the hands got
## full, a screen opened, or he simply looked away.
##
## It is the same answer the outline round the animal is drawn from, which is
## why the two can never disagree.

func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	hide()
	# Wait one frame so the player is already in the tree. Held onto before the
	# wait rather than fetched again after it: a phase can end on the frame this
	# HUD is waiting through, and the node then resumes already out of the tree
	# where `get_tree()` is null.
	var tree := get_tree()
	if tree == null:
		return
	await tree.process_frame

	# Out of the tree while we waited: the scene we belong to was freed and this
	# HUD is on its way out with it.
	if not is_inside_tree():
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	player.target_changed.connect(_on_target_changed)

func _on_target_changed(rat: Node3D) -> void:
	if rat == null:
		hide()
		return
	text = tr("HUD_GRAB_PROMPT")
	show()
