@tool
extends SceneTree
## Renders the contract floor plans straight out of `scenes/world.tscn`.
##
## The plans used to be hand-drawn rooms that no longer matched anything: the
## house the crew actually walks into is one 64x64 hall with blocks, crates,
## columns and platforms in it, and a plan showing four bedrooms is worse than
## no plan at all — it sends men looking for doors that are not there.
##
## So the drawing is taken off the scene instead of guessed. Every obstacle,
## every rat hole and the van itself is read out of `world.tscn` below and
## projected the same way: world X across, world Z down, so that the top of the
## sheet is -Z in the house and a man reading the plan can turn round and point.
##
## Run it with:
##   godot --headless --script res://scratch/generate_plans.gd

const OUT_DIR := "res://resources/contracts/plans/"

## The house, in metres. The floor mesh is 60x60 and the walls stand at +-32,
## so the sheet is drawn over the full 64x64 the walls enclose.
const WORLD_EXTENT := 32.0

## The sheet, in pixels, and the margin the house is inset by so that the title
## and the legend have somewhere to sit.
const IMAGE_SIZE := 512
const MARGIN := 46
const PLAN_SIZE := IMAGE_SIZE - MARGIN * 2

const BG_COLOR := Color("0b1928")
const GRID_COLOR := Color("142c44")
const WALL_COLOR := Color("d8ebf9")
const WALL_INNER := Color("17324d")
const ROOM_BG := Color("0f2236")
const TEXT_COLOR := Color("e6f2fa")
const ENTRANCE_COLOR := Color("34d399")
const HOLE_COLOR := Color("f87171")
const HOLE_BG := Color("7f1d1d")
const OBSTACLE_COLOR := Color("2b4f75")
const OBSTACLE_EDGE := Color("4d7ea8")
const PLATFORM_COLOR := Color("1d3a58")
## The 8m survey grid, drawn over the floor rather than the sheet, so it needs
## to lift off ROOM_BG rather than off the darker background.
const FLOOR_GRID_COLOR := Color("1b3a56")
const VAN_COLOR := Color("b58a3c")

## Every solid thing standing on the floor of `world.tscn`, as it is placed
## there. `pos` is the world XZ of the node and `size` its footprint in metres,
## both copied from the scene — the mesh sizes are `Mesh_block` 8x8,
## `Mesh_crate_medium` 6x6, `Mesh_crate_small` 3x3, `Mesh_platform` 10x10 and
## `Mesh_ramp` 6x14, and the columns are r=1.5 cylinders.
##
## Note `Block5`: the body sits at x=2 but its mesh and collision are both
## offset by -9.19 on X, so the thing a player walks into is at x=-7.2. The
## plan draws where the wall is, not where the node is.
const OBSTACLES := [
	{ "pos": Vector2(-5, -18), "size": Vector2(8, 8), "kind": "block" },
	{ "pos": Vector2(10, -14), "size": Vector2(8, 8), "kind": "block" },
	{ "pos": Vector2(24, -2), "size": Vector2(8, 8), "kind": "block" },
	{ "pos": Vector2(-22, 8), "size": Vector2(8, 8), "kind": "block" },
	{ "pos": Vector2(-7.2, 21), "size": Vector2(8, 8), "kind": "block" },
	{ "pos": Vector2(23, 20), "size": Vector2(8, 8), "kind": "block" },

	{ "pos": Vector2(-6, 4), "size": Vector2(6, 6), "kind": "crate" },
	{ "pos": Vector2(7, -6), "size": Vector2(6, 6), "kind": "crate" },
	{ "pos": Vector2(0, -10), "size": Vector2(6, 6), "kind": "crate" },
	{ "pos": Vector2(24, 9), "size": Vector2(6, 6), "kind": "crate" },
	{ "pos": Vector2(-6, -26), "size": Vector2(6, 6), "kind": "crate" },
	{ "pos": Vector2(26, -14), "size": Vector2(6, 6), "kind": "crate" },

	{ "pos": Vector2(2, 8), "size": Vector2(3, 3), "kind": "crate" },
	{ "pos": Vector2(-3, -2), "size": Vector2(3, 3), "kind": "crate" },
	{ "pos": Vector2(9, 20), "size": Vector2(3, 3), "kind": "crate" },
	{ "pos": Vector2(-12, 2), "size": Vector2(3, 3), "kind": "crate" },
	{ "pos": Vector2(17, -8), "size": Vector2(3, 3), "kind": "crate" },
	{ "pos": Vector2(-20, 20), "size": Vector2(3, 3), "kind": "crate" },

	{ "pos": Vector2(4, -21), "size": Vector2(3, 3), "kind": "column" },
	{ "pos": Vector2(10, -21), "size": Vector2(3, 3), "kind": "column" },
	{ "pos": Vector2(4, -26), "size": Vector2(3, 3), "kind": "column" },
	{ "pos": Vector2(10, -26), "size": Vector2(3, 3), "kind": "column" },

	{ "pos": Vector2(15, 9), "size": Vector2(10, 10), "kind": "platform" },
	{ "pos": Vector2(-15, -9), "size": Vector2(10, 10), "kind": "platform" },
	{ "pos": Vector2(15, 20.6), "size": Vector2(6, 14), "kind": "ramp" },
	{ "pos": Vector2(-15, -20.6), "size": Vector2(6, 14), "kind": "ramp" },
]

## The burrows, off the `RatHoles` node. The label is what the sheet writes
## beside the marker, shortened to what fits.
const HOLES := [
	{ "pos": Vector2(-29, -22), "label": "PANTRY" },
	{ "pos": Vector2(-12, -29), "label": "SINK PIPE" },
	{ "pos": Vector2(29, -18), "label": "BASEBOARD" },
	{ "pos": Vector2(14, -29), "label": "FLUE" },
	{ "pos": Vector2(-29, 9), "label": "STAIRS" },
	{ "pos": Vector2(29, 16), "label": "VENT" },
]

## Where the crew comes in: the `Spawns` node stands at (7, 27.5) and the van
## is parked just behind it at (2.2, 22).
const ENTRY := Vector2(7, 27.5)
const VAN_POS := Vector2(2.2, 22)
const VAN_SIZE := Vector2(3.2, 7.0)


func _init() -> void:
	var dir := DirAccess.open("res://")
	if not dir.dir_exists("resources/contracts/plans"):
		dir.make_dir_recursive("resources/contracts/plans")

	_render("01_hallow_street_plan.png", "14 HALLOW STREET - GROUND FLOOR")
	_render("02_marrow_lane_plan.png", "8 MARROW LANE - GROCERY REAR")
	_render("03_pell_house_plan.png", "PELL HOUSE - GROUND ESTATE")

	print("Plans generated from world.tscn.")
	quit(0)


## One sheet. All three contracts are played in `world.tscn` today, so all three
## get the same drawing under a different heading — a plan that lies about the
## house is the thing this is here to stop.
func _render(file_name: String, title: String) -> void:
	var img := _base_grid(IMAGE_SIZE, IMAGE_SIZE, title)

	# The floor the walls enclose.
	_draw_rect_filled(img, Rect2i(MARGIN, MARGIN, PLAN_SIZE, PLAN_SIZE), ROOM_BG)

	_draw_scale_grid(img)
	_draw_perimeter(img)

	for obstacle in OBSTACLES:
		_draw_obstacle(img, obstacle)

	_draw_van(img)

	for hole in HOLES:
		var hole_pos: Vector2 = hole["pos"]
		_draw_poi_hole(img, _to_pixels(hole_pos), hole["label"])

	_draw_poi_entrance(img, _to_pixels(ENTRY), "ENTRY")

	_draw_compass(img)
	_draw_legend(img)

	img.save_png(OUT_DIR + file_name)


## World XZ to a pixel on the sheet. X runs across and Z runs down, so that the
## top of the sheet is -Z: the direction a player spawning at the van is facing.
func _to_pixels(world: Vector2) -> Vector2i:
	var u := (world.x + WORLD_EXTENT) / (WORLD_EXTENT * 2.0)
	var v := (world.y + WORLD_EXTENT) / (WORLD_EXTENT * 2.0)
	return Vector2i(
		MARGIN + int(round(u * PLAN_SIZE)),
		MARGIN + int(round(v * PLAN_SIZE))
	)


## Metres to pixels, for a width or a height rather than a position.
func _to_length(metres: float) -> int:
	return maxi(1, int(round(metres / (WORLD_EXTENT * 2.0) * PLAN_SIZE)))


## A footprint centred on a world point, as a pixel rect.
func _footprint(centre: Vector2, size: Vector2) -> Rect2i:
	var top_left := _to_pixels(centre - size * 0.5)
	return Rect2i(top_left, Vector2i(_to_length(size.x), _to_length(size.y)))


## The four walls, drawn on the inside edge of the sheet where they stand in the
## scene (+-32, four metres thick).
func _draw_perimeter(img: Image) -> void:
	var thickness := _to_length(4.0)
	var plan := Rect2i(MARGIN, MARGIN, PLAN_SIZE, PLAN_SIZE)

	# Hatched rather than solid: four metres of wall drawn in flat white swamps
	# everything standing inside it, and a blueprint reads a wall as its two
	# faces anyway.
	_draw_rect_filled(img, Rect2i(plan.position.x, plan.position.y, plan.size.x, thickness), WALL_INNER)
	_draw_rect_filled(img, Rect2i(plan.position.x, plan.position.y + plan.size.y - thickness, plan.size.x, thickness), WALL_INNER)
	_draw_rect_filled(img, Rect2i(plan.position.x, plan.position.y, thickness, plan.size.y), WALL_INNER)
	_draw_rect_filled(img, Rect2i(plan.position.x + plan.size.x - thickness, plan.position.y, thickness, plan.size.y), WALL_INNER)

	_draw_rect_outline(img, plan, WALL_COLOR, 2)
	_draw_rect_outline(img, Rect2i(
		plan.position.x + thickness,
		plan.position.y + thickness,
		plan.size.x - thickness * 2,
		plan.size.y - thickness * 2
	), WALL_COLOR, 2)

	# The doorway the crew comes through, cut clean through the south wall above
	# the van — both faces and the fill between them, or the opening reads as a
	# window rather than a door.
	var gap_left := _to_pixels(Vector2(ENTRY.x - 3.0, 0)).x
	var gap_width := _to_length(6.0)
	_draw_rect_filled(img, Rect2i(
		gap_left,
		plan.position.y + plan.size.y - thickness - 2,
		gap_width,
		thickness + 2
	), ROOM_BG)


## The eight-metre survey grid, so that distances on the sheet can be counted
## rather than guessed.
func _draw_scale_grid(img: Image) -> void:
	var step := 8.0
	var metre := -WORLD_EXTENT + step
	while metre < WORLD_EXTENT:
		var p := _to_pixels(Vector2(metre, metre))
		for y in range(MARGIN, MARGIN + PLAN_SIZE):
			_put(img, p.x, y, FLOOR_GRID_COLOR)
		for x in range(MARGIN, MARGIN + PLAN_SIZE):
			_put(img, x, p.y, FLOOR_GRID_COLOR)
		metre += step


## One solid thing on the floor. Platforms and ramps are drawn hollow because a
## man can stand on top of one, and everything else filled because he cannot.
func _draw_obstacle(img: Image, obstacle: Dictionary) -> void:
	var rect := _footprint(obstacle["pos"], obstacle["size"])
	var kind: String = obstacle["kind"]

	if kind == "platform" or kind == "ramp":
		_draw_rect_filled(img, rect, PLATFORM_COLOR)
		_draw_rect_outline(img, rect, OBSTACLE_EDGE, 1)
		return

	_draw_rect_filled(img, rect, OBSTACLE_COLOR)
	_draw_rect_outline(img, rect, OBSTACLE_EDGE, 1)


## The van, parked at the door. Drawn in the amber the unsigned sheet is
## written in, so it does not read as one more crate.
func _draw_van(img: Image) -> void:
	var rect := _footprint(VAN_POS, VAN_SIZE)
	_draw_rect_outline(img, rect, VAN_COLOR, 2)
	_draw_label(img, "VAN", Vector2i(rect.position.x - 2, rect.position.y + rect.size.y + 3), VAN_COLOR)


## The north arrow. North on the sheet is -Z in the house.
func _draw_compass(img: Image) -> void:
	var x := IMAGE_SIZE - MARGIN - 18
	var y := MARGIN + 12
	for i in range(10):
		_put(img, x, y + i, TEXT_COLOR)
	for i in range(5):
		_put(img, x - i, y + i, TEXT_COLOR)
		_put(img, x + i, y + i, TEXT_COLOR)
	_draw_label(img, "N", Vector2i(x - 3, y + 12), TEXT_COLOR)


## What the colours on the sheet mean, along the bottom.
func _draw_legend(img: Image) -> void:
	var y := IMAGE_SIZE - MARGIN + 8

	_draw_rect_filled(img, Rect2i(MARGIN, y, 8, 8), OBSTACLE_COLOR)
	_draw_label(img, "COVER", Vector2i(MARGIN + 12, y), TEXT_COLOR)

	_draw_rect_filled(img, Rect2i(MARGIN + 74, y, 8, 8), PLATFORM_COLOR)
	_draw_rect_outline(img, Rect2i(MARGIN + 74, y, 8, 8), OBSTACLE_EDGE, 1)
	_draw_label(img, "RAISED", Vector2i(MARGIN + 86, y), TEXT_COLOR)

	_draw_rect_filled(img, Rect2i(MARGIN + 158, y, 8, 8), HOLE_COLOR)
	_draw_label(img, "BURROW", Vector2i(MARGIN + 170, y), TEXT_COLOR)

	_draw_rect_filled(img, Rect2i(MARGIN + 250, y, 8, 8), ENTRANCE_COLOR)
	_draw_label(img, "ENTRY", Vector2i(MARGIN + 262, y), TEXT_COLOR)

	_draw_label(img, "GRID 8M", Vector2i(MARGIN + 330, y), Color("64748b"))


func _base_grid(w: int, h: int, title: String) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(BG_COLOR)

	for x in range(0, w, 24):
		for y in range(0, h):
			img.set_pixel(x, y, GRID_COLOR)
	for y in range(0, h, 24):
		for x in range(0, w):
			img.set_pixel(x, y, GRID_COLOR)

	_draw_rect_outline(img, Rect2i(12, 12, w - 24, h - 24), WALL_INNER, 2)
	_draw_rect_outline(img, Rect2i(16, 16, w - 32, h - 32), WALL_COLOR, 1)

	_draw_rect_filled(img, Rect2i(20, 22, w - 40, 16), WALL_INNER)
	_draw_label(img, title, Vector2i(26, 24), TEXT_COLOR)

	return img


func _put(img: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
		img.set_pixel(x, y, color)


func _draw_rect_filled(img: Image, rect: Rect2i, color: Color) -> void:
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			_put(img, x, y, color)


func _draw_rect_outline(img: Image, rect: Rect2i, color: Color, thickness := 1) -> void:
	for t in range(thickness):
		var r := Rect2i(rect.position.x + t, rect.position.y + t, rect.size.x - t * 2, rect.size.y - t * 2)
		if r.size.x <= 0 or r.size.y <= 0:
			continue
		for x in range(r.position.x, r.position.x + r.size.x):
			_put(img, x, r.position.y, color)
			_put(img, x, r.position.y + r.size.y - 1, color)
		for y in range(r.position.y, r.position.y + r.size.y):
			_put(img, r.position.x, y, color)
			_put(img, r.position.x + r.size.x - 1, y, color)


func _draw_poi_entrance(img: Image, pos: Vector2i, label: String) -> void:
	_draw_rect_filled(img, Rect2i(pos.x - 5, pos.y - 5, 10, 10), ENTRANCE_COLOR)
	_draw_rect_filled(img, Rect2i(pos.x - 2, pos.y - 2, 4, 4), BG_COLOR)
	# The entry sits in the south wall, so its name goes above the marker rather
	# than beside it, where it would be written across the wall band.
	_draw_label(img, label, Vector2i(pos.x - 16, pos.y - 16), ENTRANCE_COLOR)


func _draw_poi_hole(img: Image, pos: Vector2i, label: String) -> void:
	_draw_rect_filled(img, Rect2i(pos.x - 5, pos.y - 5, 10, 10), HOLE_BG)
	_draw_rect_outline(img, Rect2i(pos.x - 5, pos.y - 5, 10, 10), HOLE_COLOR, 1)
	for i in range(-3, 4):
		_put(img, pos.x + i, pos.y, HOLE_COLOR)
		_put(img, pos.x, pos.y + i, HOLE_COLOR)

	# Every burrow sits hard against a wall, so the writing has to be placed
	# away from whichever edge it is on or it runs off the sheet: the ones on
	# the top and bottom walls are labelled above and below, and the rest are
	# labelled on whichever side has room.
	var text_width := label.length() * 8
	var top := MARGIN + 24
	var bottom := IMAGE_SIZE - MARGIN - 24

	if pos.y < top:
		@warning_ignore("integer_division") # Centring on a whole pixel.
		_draw_label(img, label, Vector2i(pos.x - text_width / 2, pos.y + 10), HOLE_COLOR)
		return
	if pos.y > bottom:
		@warning_ignore("integer_division") # Centring on a whole pixel.
		_draw_label(img, label, Vector2i(pos.x - text_width / 2, pos.y - 13), HOLE_COLOR)
		return

	var text_x := pos.x + 8
	if text_x + text_width > IMAGE_SIZE - MARGIN:
		text_x = pos.x - 8 - text_width
	_draw_label(img, label, Vector2i(text_x, pos.y - 3), HOLE_COLOR)


# Simple 5x7 bitmap font rendering for retro PSX blueprint text
const FONT_DATA := {
	"A": [0x1c, 0x22, 0x22, 0x3e, 0x22, 0x22, 0x22],
	"B": [0x3c, 0x22, 0x22, 0x3c, 0x22, 0x22, 0x3c],
	"C": [0x1e, 0x20, 0x20, 0x20, 0x20, 0x20, 0x1e],
	"D": [0x3c, 0x22, 0x22, 0x22, 0x22, 0x22, 0x3c],
	"E": [0x3e, 0x20, 0x20, 0x3c, 0x20, 0x20, 0x3e],
	"F": [0x3e, 0x20, 0x20, 0x3c, 0x20, 0x20, 0x20],
	"G": [0x1e, 0x20, 0x20, 0x2e, 0x22, 0x22, 0x1e],
	"H": [0x22, 0x22, 0x22, 0x3e, 0x22, 0x22, 0x22],
	"I": [0x1c, 0x08, 0x08, 0x08, 0x08, 0x08, 0x1c],
	"J": [0x0e, 0x04, 0x04, 0x04, 0x04, 0x24, 0x18],
	"K": [0x22, 0x24, 0x28, 0x30, 0x28, 0x24, 0x22],
	"L": [0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x3e],
	"M": [0x22, 0x36, 0x2a, 0x22, 0x22, 0x22, 0x22],
	"N": [0x22, 0x32, 0x2a, 0x26, 0x22, 0x22, 0x22],
	"O": [0x1c, 0x22, 0x22, 0x22, 0x22, 0x22, 0x1c],
	"P": [0x3c, 0x22, 0x22, 0x3c, 0x20, 0x20, 0x20],
	"Q": [0x1c, 0x22, 0x22, 0x22, 0x2a, 0x24, 0x1a],
	"R": [0x3c, 0x22, 0x22, 0x3c, 0x28, 0x24, 0x22],
	"S": [0x1e, 0x20, 0x20, 0x1c, 0x02, 0x02, 0x3c],
	"T": [0x3e, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08],
	"U": [0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x1c],
	"V": [0x22, 0x22, 0x22, 0x14, 0x14, 0x08, 0x08],
	"W": [0x22, 0x22, 0x22, 0x2a, 0x2a, 0x36, 0x22],
	"X": [0x22, 0x22, 0x14, 0x08, 0x14, 0x22, 0x22],
	"Y": [0x22, 0x22, 0x14, 0x08, 0x08, 0x08, 0x08],
	"Z": [0x3e, 0x02, 0x04, 0x08, 0x10, 0x20, 0x3e],
	"0": [0x1c, 0x26, 0x2a, 0x32, 0x22, 0x22, 0x1c],
	"1": [0x08, 0x18, 0x08, 0x08, 0x08, 0x08, 0x1c],
	"2": [0x1c, 0x22, 0x02, 0x0c, 0x10, 0x20, 0x3e],
	"3": [0x1c, 0x22, 0x02, 0x0c, 0x02, 0x22, 0x1c],
	"4": [0x04, 0x0c, 0x14, 0x24, 0x3e, 0x04, 0x04],
	"5": [0x3e, 0x20, 0x3c, 0x02, 0x02, 0x22, 0x1c],
	"6": [0x1c, 0x20, 0x3c, 0x22, 0x22, 0x22, 0x1c],
	"7": [0x3e, 0x02, 0x04, 0x08, 0x10, 0x10, 0x10],
	"8": [0x1c, 0x22, 0x22, 0x1c, 0x22, 0x22, 0x1c],
	"9": [0x1c, 0x22, 0x22, 0x1e, 0x02, 0x02, 0x1c],
	"-": [0x00, 0x00, 0x00, 0x3e, 0x00, 0x00, 0x00],
	"?": [0x1c, 0x22, 0x02, 0x0c, 0x08, 0x00, 0x08],
	".": [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0c],
	" ": [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
}

func _draw_label(img: Image, text: String, pos: Vector2i, color := TEXT_COLOR) -> void:
	var cur_x := pos.x
	for i in text.length():
		var ch := text[i].to_upper()
		if FONT_DATA.has(ch):
			var rows: Array = FONT_DATA[ch]
			for y in range(rows.size()):
				var row: int = rows[y]
				for x in range(6):
					if (row & (1 << (5 - x))) != 0:
						_put(img, cur_x + x, pos.y + y, color)
		cur_x += 8
