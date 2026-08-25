extends Label
## The prompt for the hands: what the player is looking at, and the key that
## uses it.
##
## It keeps no count of its own and asks nobody anything — the player announces
## what is in front of him (`interactable_changed`) and this writes it down. With
## nothing in front of him, and with a rat kicking in his hands, the player
## announces null and the line leaves the screen.

func _ready() -> void:
	hide()
	# Wait one frame so the player is already in the tree.
	await get_tree().process_frame
	# A phase can end on the frame this HUD is waiting through — the board in the
	# van does exactly that — and a node that wakes up under a freed scene has no
	# tree left to look a player up in. There is nobody to wire to in that case,
	# and the HUD is on its way out with the rest of the scene anyway.
	if not is_inside_tree():
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	player.interactable_changed.connect(_on_interactable_changed)

func _on_interactable_changed(interactable: Interactable) -> void:
	if interactable == null:
		hide()
		return
	text = "E — %s" % interactable.prompt
	show()
