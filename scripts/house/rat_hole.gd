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

## The visual highlight node (dust particles, ring, or mesh) under this hole.
@export var highlight_path: NodePath = ^"Highlight"

## Optional label or burrow name for debugging/tactical identification.
@export var hole_name := "Burrow"

@onready var _highlight: Node3D = get_node_or_null(highlight_path) as Node3D

var _active := false


func _ready() -> void:
	add_to_group("rat_holes")
	_build_default_highlight_if_needed()
	_update_phase_state()

	PhaseManager.phase_changed.connect(_on_phase_changed)


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
