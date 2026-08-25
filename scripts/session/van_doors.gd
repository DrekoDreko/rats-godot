class_name VanDoors
extends Node3D
## The two rear doors of the van, which stand open for the hunt and are shut the
## rest of the time.
##
## The card asks for the back of the van to be open "during the hunt", and that
## is a statement about two things at once: the doors are open in `HUNT`, and
## they are therefore *not* open in the phases either side of it. So this node
## owns both halves — it swings them out when the rats are loose and pulls them
## back when they are not, rather than the model being frozen in one pose.
##
## Why a script and not a baked-open model: the leaves are their own objects in
## `models/crew_van.py` (`Van_Door_L` and `Van_Door_R`), hung on the jambs, for
## exactly this. Rotating them here costs nothing and means the same `.glb`
## serves the parked van, the moving van and the working van.
##
## It leans on nothing. Given a van whose model has no doors — an older
## `box_van.glb`, a grey box during blocking — every method turns into a no-op
## and the scene still runs. That is deliberate: a van missing its doors should
## look wrong, not crash.
##
## **Not in use yet.** No scene carries this node: the van in the game is
## `models/box_van.glb`, which has no hinged leaves for it to turn, so it would
## sit there doing nothing. It is kept because the phase rule and the swing are
## right and will be wanted the moment the van has doors — see the note at the
## top of `models/crew_van.py` for why that van is on hold.

## Which phases have the doors open. The hunt is the one the card names; survey
## is included because it is the same parked van in the same street and the crew
## is walking in and out of it setting traps, and a door that shuts between
## survey and hunt would shut in their faces.
const OPEN_PHASES: Array[Phase.Type] = [Phase.Type.SURVEY, Phase.Type.HUNT]

## How far a leaf swings when it opens. It matches `DOOR_OPEN_ANGLE` in
## `models/crew_van.py`, which is where the doorway and the hinges come from —
## the model is built with the leaves already at this angle, so this is the
## number that puts them back where the model drew them.
const OPEN_ANGLE := deg_to_rad(86.0)

## How long a leaf takes to swing, and the curve it swings on. Slow enough to be
## a door being opened rather than a door teleporting, fast enough that nobody
## waits on it.
const SWING_TIME := 0.55
const SWING_EASE := Tween.EASE_OUT
const SWING_TRANS := Tween.TRANS_CUBIC

## The names the two leaves are exported under. Kept as constants because they
## are a contract with `models/crew_van.py` rather than something to tune.
const LEAF_NAMES := {
	-1.0: "Van_Door_L",
	1.0: "Van_Door_R",
}

## The leaf nodes, keyed by their side's sign, and the tween currently swinging
## them. Only ever one tween: a phase change mid-swing should redirect the doors,
## not race the previous swing.
var _leaves: Dictionary[float, Node3D] = {}
var _swing: Tween = null


func _ready() -> void:
	_find_leaves()

	# The phase machine is an autoload, and it is reached through the tree rather
	# than by its global name. Two reasons: a test bench run with `--script`
	# compiles before the autoloads are in the tree, so the bare name is not
	# resolvable there; and a van dropped into a scratch scene with no session
	# running should still show its doors in some sensible pose rather than
	# erroring on the first line.
	var phases := get_node_or_null("/root/PhaseManager")
	if phases == null:
		_apply(Phase.Type.LOBBY, false)
		return

	# Snap to the phase we are already in rather than animating into it. A
	# player loading straight into the hunt should find the doors open, not
	# watch them open.
	_apply(phases.current(), false)
	phases.phase_changed.connect(_on_phase_changed)


## Whether the doors are open in this phase. Public because the step outside the
## doorway wants to know too, and because it is the whole rule this node is.
static func open_in(phase: Phase.Type) -> bool:
	return phase in OPEN_PHASES


func _on_phase_changed(_previous: Phase.Type, current: Phase.Type) -> void:
	_apply(current, true)


func _find_leaves() -> void:
	# The leaves are somewhere under the van's imported model, and how deep
	# depends on how the `.glb` was imported — so they are searched for by name
	# rather than reached for by path. `find_child` with `recursive` is the one
	# lookup that survives the importer nesting them differently.
	var van := get_parent()
	if van == null:
		return
	for sign_key: float in LEAF_NAMES:
		var leaf := van.find_child(LEAF_NAMES[sign_key], true, false) as Node3D
		if leaf != null:
			_leaves[sign_key] = leaf


func _apply(phase: Phase.Type, animated: bool) -> void:
	if _leaves.is_empty():
		return

	var open := open_in(phase)
	if _swing != null and _swing.is_valid():
		_swing.kill()
	_swing = null

	if not animated:
		for sign_key: float in _leaves:
			_leaves[sign_key].rotation.y = _target_angle(sign_key, open)
		return

	_swing = create_tween().set_parallel(true)
	for sign_key: float in _leaves:
		_swing.tween_property(_leaves[sign_key], "rotation:y",
			_target_angle(sign_key, open), SWING_TIME) \
			.set_ease(SWING_EASE).set_trans(SWING_TRANS)


## Where a leaf's hinge sits for a given state. Open is `OPEN_ANGLE` away from
## the doorway, and which way away depends on the side: the two leaves swing
## apart, so their angles are mirrored. Shut is flat in the doorway, angle zero,
## which is the pose the leaf's own geometry is drawn around.
func _target_angle(side: float, open: bool) -> float:
	if not open:
		return 0.0
	return side * OPEN_ANGLE
