extends Control
## The slow jobs' bar: what the player watches while he stands there with his
## finger down on something that takes time.
##
## It keeps no count of its own and asks nobody anything — the player announces
## the work he started, how far it has got and that it is over (`hold_started` /
## `hold_progress` / `hold_finished`), and this draws it. The same three signals
## whether the job finished or was thrown away one frame short of the end: what
## happened is the player's business, and the bar just leaves.
##
## The prompt goes off the screen while it is up. "E — clean the trap" is an
## instruction for a key that is already down.

## The line this stands in for while the work is going on. It is a path and not a
## direct node reference, for the same reason the strangling prompt reaches the
## crosshair by path: the `world.tscn` HUD is written by hand, and an exported
## node only wires itself up in a scene saved by the editor.
@export var prompt_path := NodePath("../Prompt")

@onready var label: Label = $VBoxContainer/Label
@onready var bar: ProgressBar = $VBoxContainer/Bar
@onready var prompt: Control = get_node_or_null(prompt_path)

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
	player.hold_started.connect(_on_started)
	player.hold_progress.connect(_on_progress)
	player.hold_finished.connect(_on_finished)

func _on_started(interactable: Interactable) -> void:
	label.text = interactable.prompt
	bar.value = 0.0
	show()
	if prompt != null:
		prompt.hide()

func _on_progress(fraction: float) -> void:
	bar.value = fraction

## Whichever way it ended, the bar goes. Putting the line back is the player's
## own doing: he re-announces what is in front of him the moment the work stops
## (`player.gd: _cancel_hold`), so a job let go of halfway brings back the prompt
## to start it again, and one that finished and took its trap off the floor
## announces null instead and leaves the line where it is.
func _on_finished(_completed: bool) -> void:
	hide()
