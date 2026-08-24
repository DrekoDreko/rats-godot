extends CharacterBody3D
## A stand-in rat for `_test_trap_sync.gd`, and for nothing else.
##
## A mousetrap going off does four things to what it caught — claims the body,
## hits it, and later lets it go — and a bench measuring whether the *catch*
## crossed the wire has no interest in any of them. The real animal would bring
## its own state machine, its own navigation and its own replication into the
## middle of the measurement.
##
## So this answers to the same four calls and records them instead of acting on
## them, which lets the bench ask "did the blow land on this machine?" without
## having a whole rat to ask it of.

## Whether the trap swung at it, and whoever claimed the body before the swing.
var hit := false
var holder: Node3D

func claim_carcass(by: Node3D) -> void:
	holder = by

func release_carcass() -> void:
	holder = null

func take_damage(_amount: int = 1, _origin: Vector3 = Vector3.INF,
		_type: int = 0, _leap: float = 3.0) -> void:
	hit = true

func pin(by: Node3D = null) -> void:
	holder = by

func is_dead() -> bool:
	return hit

func is_captured() -> bool:
	return false

func is_pinned() -> bool:
	return holder != null
