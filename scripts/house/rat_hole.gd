class_name RatHole
extends Node3D
## A rat hole or escape route in the house walls, skirting boards or floorboards.
##
## During the SURVEY phase (Card 12), the team gets 60 seconds to inspect the house
## before any rats are loose. All burrows, cracks, and escape routes stand out with
## a subtle visual highlight (PSX dust motes or unshaded indicator) so the crew
## can plan trap placement and note escape paths.
##
## When the HUNT phase starts (Card 13), the visual highlight is removed: from then
## on, the crew must rely on what they memorized during the survey.
##
## **A hole is one end of a route and not a dead end.** Holes come in pairs: the
## crack behind the pantry (point A) and the vent in the back room (point B) are
## two mouths of the same run through the walls, and a rat that dives into one
## comes out of the other (`rat.gd::_dive_into`). That is what makes the survey
## worth the minute it costs — a man who noticed which two holes are the same
## hole knows where the animal he just lost is about to appear, and a man who did
## not is standing over an empty skirting board.
##
## The pairing is written once, on either end (`linked_hole`), and read from both
## (`linked`): a hole named by another hole is linked to it whether or not it
## names it back. A hole with no partner is still a nest the rats are put in at
## the top of the hunt; it simply is not a way through.
##
## **A hole sits in a wall and opens into the room.** The node's origin is on the
## wall face at floor level, and the gnawed slit under it
## (`scenes/clues/rat_hole.tscn`) is modelled opening along the node's own
## forward, which is `-Z` — so putting one on the west wall is a matter of
## turning it to face east, and nothing about the model has to know which wall it
## ended up on.
##
## Nothing walks to the origin, though. It is *in* the plaster: the navigation
## mesh stops a rat's radius short of every wall, so a rat sent to the hole
## itself would be sent somewhere it cannot stand. `mouth()` is the pace of floor
## in front of it, and it is what everything that walks — the bolt, the far end
## of a run, the trail of droppings, the nest the animals are put out in — uses
## instead.

## The visual highlight node (dust particles, ring, or mesh) under this hole.
@export var highlight_path: NodePath = ^"Highlight"

## Optional label or burrow name for debugging/tactical identification.
@export var hole_name := "Burrow"

## The other mouth of this run through the walls. It only needs writing on one of
## the two — see the note above — and it is left empty on a hole that leads
## nowhere.
@export var linked_hole: NodePath

## How far out from the wall face the standable pace of floor is. A little more
## than the navigation mesh's own inset from the wall (`agent_radius`, 0.25 in
## `world.tscn`), so that the point is comfortably on the mesh rather than on its
## very edge — the agent counts itself arrived within 0.3 m
## (`target_desired_distance`), and an arrival that has to be exact is an arrival
## that sometimes never happens.
const MOUTH_REACH := 0.7

@onready var _highlight: Node3D = get_node_or_null(highlight_path) as Node3D

var _active := false


func _ready() -> void:
	add_to_group("rat_holes")
	_build_default_highlight_if_needed()
	_update_phase_state()

	PhaseManager.phase_changed.connect(_on_phase_changed)


## The pace of floor in front of the slit: where a rat stands to go in, and where
## it is standing when it comes out. See the note at the top for why this is not
## simply the node's own position.
func mouth() -> Vector3:
	return global_position - global_basis.z * MOUTH_REACH


## The hole at the far end of this run, or null for one that leads nowhere.
##
## Asked both ways round on purpose. The level names the pair once — `HoleKitchen1`
## points at `HoleBackRoom` and nothing else is written — and this is what makes
## the run work from either mouth. Without it every pair would have to be written
## twice in the scene, and the day somebody wrote only one half the rats would
## dive in at one end and never come out anywhere.
func linked() -> RatHole:
	var named := get_node_or_null(linked_hole) as RatHole
	if named != null and named != self:
		return named
	for node in get_tree().get_nodes_in_group("rat_holes"):
		var other := node as RatHole
		if other == null or other == self:
			continue
		if other.get_node_or_null(other.linked_hole) == self:
			return other
	return null


## Whether the visual highlight is currently visible and active.
func is_highlighted() -> bool:
	return _active


## Enables or disables the visual highlight.
func set_highlight(active: bool) -> void:
	_active = active
	if _highlight != null:
		_highlight.visible = active
		if _highlight is CPUParticles3D:
			(_highlight as CPUParticles3D).emitting = active
		elif _highlight is GPUParticles3D:
			(_highlight as GPUParticles3D).emitting = active


func _update_phase_state() -> void:
	# Visible only during the SURVEY phase.
	var is_survey := PhaseManager.current() == Phase.Type.SURVEY
	set_highlight(is_survey)


func _on_phase_changed(_previous: Phase.Type, _current: Phase.Type) -> void:
	_update_phase_state()


## Builds a clean, lightweight PSX-styled dust highlight if none was assigned in the scene.
func _build_default_highlight_if_needed() -> void:
	if _highlight != null:
		return

	# Look for an existing child named Highlight
	var child := get_node_or_null(^"Highlight") as Node3D
	if child != null:
		_highlight = child
		return

	# Construct a lightweight CPUParticles3D with floating dust motes
	var particles := CPUParticles3D.new()
	particles.name = "Highlight"
	particles.amount = 8
	particles.lifetime = 1.6
	particles.preprocess = 0.5
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.25
	particles.gravity = Vector3(0.0, 0.15, 0.0)
	particles.initial_velocity_min = 0.05
	particles.initial_velocity_max = 0.2
	particles.scale_amount_min = 0.03
	particles.scale_amount_max = 0.06

	# PSX unshaded dust material
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.85, 0.75, 0.45, 0.65) # Warm dusty amber
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	particles.material_override = mat

	# Small quad mesh
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.08, 0.08)
	particles.mesh = mesh

	add_child(particles)
	_highlight = particles
