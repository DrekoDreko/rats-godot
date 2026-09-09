extends CanvasLayer
## The scoreboard, held rather than opened: who else is on this shift, how many
## rats each of them has taken and how far away they are.
##
## **It is the pause menu's crew list without the pause.** Same rows, same
## `scripts/ui/crew_list.gd` — a man who has read one has read the other. What is
## different is that the game does not stop for it: he is holding a key with one
## hand in the middle of a hunt, and a tree that stopped for that would be a tree
## that stops sixty times a shift.
##
## **Only where he cannot simply look up and count heads.** On the road and in
## the dark of the house the crew is scattered, and this is the only place their
## colours and their tallies can be read. In the van parked and in the survey
## they are standing in front of him, and a list of names he can already see is a
## list nobody looks at.
##
## The key is watched from `_input` and not `_unhandled_input`, so that the
## release is seen even when the press was swallowed by a screen that had the
## focus — a panel stuck open because a menu ate the key going down would be
## worse than one that never opened. The event is not marked handled: nothing
## else is asked to give it up.

const ACTION := "player_list"
const PHASES: Array[Phase.Type] = [Phase.Type.TRAVEL, Phase.Type.HUNT]

@onready var _panel: Control = $Center
@onready var _crew: CrewList = $Center/Panel/Margin/Rows/Crew

## Whether the key is down. Kept rather than polled, and crossed with the phase
## every time either of them moves.
var _held := false


func _ready() -> void:
	# The key still has to be heard while the tree is stopped, or a press that
	# went down before the pause menu opened would never come back up. What the
	# panel does about a paused tree is `_redraw`'s business, not the key's.
	process_mode = Node.PROCESS_MODE_ALWAYS
	PhaseManager.phase_changed.connect(_on_phase_changed)
	# A phase change while the key is down builds this scene with the key still
	# down, and a press it never saw would leave the panel shut until the player
	# let go and pressed again.
	_held = Input.is_action_pressed(ACTION)
	_redraw()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION, false, true):
		_held = true
		_redraw()
	elif event.is_action_released(ACTION, true):
		_held = false
		_redraw()


func _on_phase_changed(_previous: Phase.Type, _current: Phase.Type) -> void:
	_redraw()


## Up only while the key is down, the phase is one of ours, and nothing else has
## the screen. The pause menu is the "nothing else" — it draws its own copy of
## this list over a dimmed screen, and two of them at once is one too many.
func _redraw() -> void:
	_panel.visible = _held and not get_tree().paused and PHASES.has(PhaseManager.current())
