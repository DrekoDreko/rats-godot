extends BigFontOutlinedLabel
## The prompt for the hands: what the player is looking at, and the key that
## uses it.
##
## It keeps no count of its own and asks nobody anything — the player announces
## what is in front of him (`interactable_changed`) and this writes it down. With
## nothing in front of him, and with a rat kicking in his hands, the player
## announces null and the line leaves the screen.

var _interactable: Interactable
var _seated := false

func _ready() -> void:
	super._ready()
	hide()
	# Wait one frame so the player is already in the tree.
	#
	# Awaited on the *tree* signal rather than on `get_tree().process_frame`
	# fetched again after the wait: a phase can end on the frame this HUD is
	# waiting through — the board in the van does exactly that — and the node
	# then resumes already out of the tree, where `get_tree()` is null. Reaching
	# through it for `get_first_node_in_group` is what threw
	# `Parameter "data.tree" is null`.
	var tree := get_tree()
	if tree == null:
		return
	await tree.process_frame

	# Out of the tree while we waited: the scene we belong to was freed, there is
	# nobody left to wire to, and this HUD is on its way out with it.
	if not is_inside_tree():
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	player.interactable_changed.connect(_on_interactable_changed)
	player.seated_changed.connect(_on_seated_changed)
	_on_seated_changed(player.is_seated())

func _on_interactable_changed(interactable: Interactable) -> void:
	_interactable = interactable
	_refresh()


func _on_seated_changed(seated: bool) -> void:
	_seated = seated
	_refresh()


func _refresh() -> void:
	if _seated:
		text = tr("HUD_INTERACT_PROMPT") % tr("PROMPT_STAND_UP")
		show()
		return
	if _interactable == null:
		hide()
		return
	text = tr("HUD_INTERACT_PROMPT") % tr(_interactable.prompt)
	show()
