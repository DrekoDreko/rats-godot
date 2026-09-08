class_name ExplosiveCheese
extends Trap
## A bait that destroys every nearby rat when the first one reaches it.
##
## The inherited trap protocol decides the trigger on the host and relays that
## one event to every peer. Only the host damages rats; visual removal runs on
## every replica so the spawned bait disappears consistently.

## The bait is expensive because it clears a small pack rather than one rat.
@export var blast_radius := 4.0
@export var blast_damage := 99
@export var blast_leap := 6.0

const BLAST_TIME := 0.16

var _exploding := false

@onready var model: Node3D = $Model


func _catch_rat(_rat: Node3D) -> void:
	if _exploding:
		return
	_exploding = true
	monitoring = false
	if _is_host_authority():
		_damage_nearby_rats()
	_flash_and_remove()


func _is_host_authority() -> bool:
	return not _on_the_wire() or is_multiplayer_authority()


func _damage_nearby_rats() -> void:
	for node in get_tree().get_nodes_in_group("rats"):
		var rat := node as Node3D
		if rat == null or rat.global_position.distance_to(global_position) > blast_radius:
			continue
		rat.take_damage(blast_damage, global_position, Death.Type.GUNSHOT, blast_leap)


func _flash_and_remove() -> void:
	var tween := create_tween()
	if model != null:
		tween.tween_property(model, "scale", Vector3.ZERO, BLAST_TIME).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)
