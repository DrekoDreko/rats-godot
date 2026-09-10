extends NavigationRegion3D
## The navigation mesh the rats walk on.
##
## The scenery is put together by hand in `world.tscn`, so instead of keeping the
## finished mesh inside the scene file — where it would go stale with every
## obstacle that moves — it is baked here, when the map opens, from the static
## bodies in the `scenery` group.
##
## The mesh numbers (in `world.tscn`) are rat measurements: radius 0.24, a little
## more than its body, which is the clearance left between the path and the wall;
## height 0.6, so it never thinks it fits underneath anything; and a maximum
## step of 0.2, which separates the ramp from the platform. The 0.12 cell size
## matches the project map, and the radius is exactly two cells (the same
## effective clearance the baker previously rounded 0.16 up to).

func _ready() -> void:
	# No thread: baking this map costs a few milliseconds and guarantees the rats
	# already find the mesh ready on the first physics tick.
	bake_navigation_mesh(false)
