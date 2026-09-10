"""CAPRATS - large house generator.

Rebuilds the whole playable house from the constants below and exports it to
`models/house.glb`. Run inside Blender (via MCP) or with:
    blender --background --python blender/build_house.py

The house replaces the small three-room box that came before it. It is a single
storey, 22 x 16 metres, laid out around a corridor that runs the full width so a
crew walking in the front door can reach every room without crossing another
one.

Contracts this file keeps with the Godot side - break one and the house stops
working in the game:

  * `-col` suffix on a mesh name makes the Godot importer build a trimesh
    collision body from it. Walls, floor and ceiling carry it; door leaves do
    not, because `HouseDoors` gives them their own moving collision.
  * Door leaves are named `Door_*` and modelled with the **origin on the
    hinge**, so `HingedDoor` can swing them by rotating the node's own Y.
  * Each leaf carries `closed_deg` / `open_deg` custom properties, which the
    glTF exporter writes as node extras and `HingedDoor._read_poses` reads.
  * Textures are sampled `Closest`, matching the PS1 look the level shader
    draws with.

Axis note: Blender (x, y, z) becomes Godot (x, z, -y). The front wall sits at
Blender +Y, which is Godot -Z - the side the van is parked on.
"""

import math
import os

import bmesh
import bpy
from mathutils import Vector

# ---------------------------------------------------------------------------
# PARAMETERS
# ---------------------------------------------------------------------------

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXPORT_PATH = os.path.join(PROJECT_ROOT, "models", "house.glb")
BLEND_SAVE_PATH = os.path.join(PROJECT_ROOT, "blender", "test_house.blend")
TEXTURE_DIR = os.path.join(PROJECT_ROOT, "assets", "textures", "placeholder")

COLLECTION_NAME = "House"

WALL_HEIGHT = 2.7
WALL_THICKNESS = 0.15
FLOOR_THICKNESS = 0.10
CEILING_THICKNESS = 0.10

DOOR_WIDTH = 0.92
DOOR_HEIGHT = 2.03
DOOR_LEAF_THICKNESS = 0.05

WINDOW_WIDTH = 1.20
WINDOW_HEIGHT = 1.10
WINDOW_SILL = 1.00

# The footprint, in Blender coordinates. +Y is the front (the van's side).
HOUSE_MIN_X = -11.0
HOUSE_MAX_X = 11.0
HOUSE_MIN_Y = -12.0
HOUSE_MAX_Y = 4.0

# Where the internal partitions run. The corridor is the band between
# CORRIDOR_Y_S and CORRIDOR_Y_N, spanning the full width of the house.
CORRIDOR_Y_N = -1.0
CORRIDOR_Y_S = -3.4

# Vertical partitions in the front row (north of the corridor).
FRONT_SPLIT_W = -4.0   # bedroom 1 | hall
FRONT_SPLIT_E = 0.0    # hall | living room

# Vertical partitions in the back row (south of the corridor).
BACK_SPLIT_W = -7.0    # bathroom | bedroom 2
BACK_SPLIT_E = -1.0    # bedroom 2 | kitchen

# How many metres of texture one tile covers. The wall texture is a full
# floor-to-ceiling sheet, so it is scaled to the wall height rather than tiled.
FLOOR_UV_METRES = 2.0
CEILING_UV_METRES = 2.0
WALL_UV_METRES = 2.0

TEXTURES = {
    "M_House_Floor": "wood_floor.png",
    "M_House_Wall": "white_wall_with_baseboard.png",
    "M_House_Wall_Plain": "white_wall.png",
    "M_House_Ceiling": "ceiling.png",
    "M_House_Door": "test_door.png",
    "M_House_Window": "window.png",
}


# ---------------------------------------------------------------------------
# Scene helpers
# ---------------------------------------------------------------------------


def get_collection(name):
    coll = bpy.data.collections.get(name)
    if coll is None:
        coll = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(coll)
    return coll


def clear_collection(coll):
    """Empty the collection so a re-run replaces the house instead of stacking."""
    for obj in list(coll.objects):
        mesh = obj.data if obj.type == "MESH" else None
        bpy.data.objects.remove(obj, do_unlink=True)
        if mesh is not None and mesh.users == 0:
            bpy.data.meshes.remove(mesh)


def material(name):
    """A flat, nearest-sampled textured material, created once and reused."""
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.blend_method = "HASHED"
    tree = mat.node_tree
    tree.nodes.clear()

    output = tree.nodes.new("ShaderNodeOutputMaterial")
    output.location = (400, 0)
    bsdf = tree.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (100, 0)
    bsdf.inputs["Roughness"].default_value = 1.0
    tex = tree.nodes.new("ShaderNodeTexImage")
    tex.location = (-250, 0)
    tex.interpolation = "Closest"
    tex.extension = "REPEAT"

    filename = TEXTURES[name]
    path = os.path.join(TEXTURE_DIR, filename)
    image = bpy.data.images.get(filename)
    if image is None and os.path.exists(path):
        image = bpy.data.images.load(path)
    tex.image = image

    tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    tree.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    tree.links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    return mat


def new_mesh_object(name, coll):
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    coll.objects.link(obj)
    return obj


# ---------------------------------------------------------------------------
# Geometry building blocks
# ---------------------------------------------------------------------------


def add_box(bm, min_corner, max_corner):
    """Append an axis-aligned box to `bm`, given two opposite corners."""
    x0, y0, z0 = min_corner
    x1, y1, z1 = max_corner
    verts = [
        bm.verts.new((x0, y0, z0)),
        bm.verts.new((x1, y0, z0)),
        bm.verts.new((x1, y1, z0)),
        bm.verts.new((x0, y1, z0)),
        bm.verts.new((x0, y0, z1)),
        bm.verts.new((x1, y0, z1)),
        bm.verts.new((x1, y1, z1)),
        bm.verts.new((x0, y1, z1)),
    ]
    faces = [
        (0, 1, 2, 3),  # bottom
        (7, 6, 5, 4),  # top
        (0, 4, 5, 1),  # -Y
        (1, 5, 6, 2),  # +X
        (2, 6, 7, 3),  # +Y
        (3, 7, 4, 0),  # -X
    ]
    for f in faces:
        bm.faces.new([verts[i] for i in f])


def add_wall_segment(bm, axis, fixed, start, end, z0, z1):
    """One straight run of wall.

    `axis` is the direction the wall runs along: "x" for a wall spanning X at a
    fixed Y, "y" for one spanning Y at a fixed X. `fixed` is the wall's centre
    line on the other axis; the thickness is spread evenly either side of it.
    """
    if end - start <= 1e-6 or z1 - z0 <= 1e-6:
        return
    half = WALL_THICKNESS * 0.5
    if axis == "x":
        add_box(bm, (start, fixed - half, z0), (end, fixed + half, z1))
    else:
        add_box(bm, (fixed - half, start, z0), (fixed + half, end, z1))


def add_wall_with_openings(bm, axis, fixed, start, end, openings):
    """A wall run broken by doorways and windows.

    `openings` is a list of `(centre, width, sill, height)` along the wall's own
    axis. A doorway has `sill` 0, which leaves no panel underneath it; a window
    has a positive sill and gets a panel above and below.
    """
    ordered = sorted(openings, key=lambda o: o[0] - o[1] * 0.5)

    cursor = start
    for centre, width, sill, height in ordered:
        o0 = centre - width * 0.5
        o1 = centre + width * 0.5
        # Full-height wall up to the opening.
        add_wall_segment(bm, axis, fixed, cursor, o0, 0.0, WALL_HEIGHT)
        # Panel under a window; nothing under a door.
        if sill > 0.0:
            add_wall_segment(bm, axis, fixed, o0, o1, 0.0, sill)
        # Lintel above the opening.
        top = sill + height
        if top < WALL_HEIGHT:
            add_wall_segment(bm, axis, fixed, o0, o1, top, WALL_HEIGHT)
        cursor = o1
    add_wall_segment(bm, axis, fixed, cursor, end, 0.0, WALL_HEIGHT)


def uv_unwrap_leaf(obj):
    """Stretch the door texture across the whole leaf, once.

    The other surfaces in the house are tiled materials — plaster, boards,
    ceiling — where the texture repeats every so many metres. A door is not
    that: the image *is* one door, frame to frame, so it has to land on the
    leaf exactly once. Box-projecting it by metres instead would repeat it
    twice up a 2.03 m leaf and cut it off at 0.92 across.

    The two broad faces take the full 0..1 sheet, mirrored so the door reads
    the right way round from both sides. The four edges of the slab get a thin
    sliver of the texture's own edge, which is all a 5 cm border needs.
    """
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    uv_layer = bm.loops.layers.uv.verify()

    for face in bm.faces:
        n = face.normal
        broad = abs(n.y) > 0.5          # the leaf's front and back
        for loop in face.loops:
            co = loop.vert.co
            if broad:
                u = co.x / DOOR_WIDTH
                if n.y > 0.0:            # mirror the back face
                    u = 1.0 - u
                v = co.z / DOOR_HEIGHT
            else:
                # Edges: a sliver taken from the middle of the sheet, so no
                # seam of the door's own frame shows on the slab's sides.
                u = 0.5
                v = co.z / DOOR_HEIGHT
            loop[uv_layer].uv = (u, v)

    bm.to_mesh(mesh)
    bm.free()


def uv_project(obj, metres_per_tile, wall_sheet=False):
    """Box-project UVs so the texture keeps a constant size in world metres.

    Each face is mapped along whichever axis it faces, which is exactly right
    for a house made entirely of axis-aligned boxes and avoids an unwrap that
    would need seams marking by hand.

    `wall_sheet` changes what the vertical axis means. The wall texture is not a
    tile: it is one floor-to-ceiling sheet with the skirting board painted into
    its bottom edge. Tiling it vertically the way the floor tiles would repeat
    the skirting board half way up the wall and cut a second one off at the
    ceiling, so V is stretched to put exactly one sheet across `WALL_HEIGHT`
    and only U repeats along the wall's length.
    """
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    uv_layer = bm.loops.layers.uv.verify()
    scale = 1.0 / metres_per_tile

    for face in bm.faces:
        n = face.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for loop in face.loops:
            co = loop.vert.co
            if az >= ax and az >= ay:
                u, v = co.x * scale, co.y * scale      # floors and ceilings
            elif ax >= ay:
                u = co.y * scale                        # walls facing X
                v = co.z / WALL_HEIGHT if wall_sheet else co.z * scale
            else:
                u = co.x * scale                        # walls facing Y
                v = co.z / WALL_HEIGHT if wall_sheet else co.z * scale
            loop[uv_layer].uv = (u, v)

    bm.to_mesh(mesh)
    bm.free()


def finish(obj, mat, metres_per_tile, wall_sheet=False, leaf=False):
    obj.data.materials.append(mat)
    if leaf:
        uv_unwrap_leaf(obj)
    else:
        uv_project(obj, metres_per_tile, wall_sheet=wall_sheet)
    obj.data.validate()
    obj.data.update()


# ---------------------------------------------------------------------------
# The house
# ---------------------------------------------------------------------------


def build_floor(coll):
    obj = new_mesh_object("House_Floor-col", coll)
    bm = bmesh.new()
    add_box(
        bm,
        (HOUSE_MIN_X - WALL_THICKNESS, HOUSE_MIN_Y - WALL_THICKNESS, -FLOOR_THICKNESS),
        (HOUSE_MAX_X + WALL_THICKNESS, HOUSE_MAX_Y + WALL_THICKNESS, 0.0),
    )
    bm.to_mesh(obj.data)
    bm.free()
    finish(obj, material("M_House_Floor"), FLOOR_UV_METRES)
    return obj


def build_ceiling(coll):
    """The lid. Without it the house is a box read from above and the fog never
    closes in, which is most of what makes an interior feel like one."""
    obj = new_mesh_object("House_Ceiling-col", coll)
    bm = bmesh.new()
    add_box(
        bm,
        (HOUSE_MIN_X - WALL_THICKNESS, HOUSE_MIN_Y - WALL_THICKNESS, WALL_HEIGHT),
        (
            HOUSE_MAX_X + WALL_THICKNESS,
            HOUSE_MAX_Y + WALL_THICKNESS,
            WALL_HEIGHT + CEILING_THICKNESS,
        ),
    )
    bm.to_mesh(obj.data)
    bm.free()
    finish(obj, material("M_House_Ceiling"), CEILING_UV_METRES)
    return obj


def build_walls(coll):
    """Every wall in the house, outer shell and partitions, as one mesh.

    One object rather than one per room: the walls are a single collision body
    in Godot and a single draw call, and nothing in the game addresses an
    individual wall by name.
    """
    obj = new_mesh_object("House_Walls-col", coll)
    bm = bmesh.new()

    door = lambda centre: (centre, DOOR_WIDTH, 0.0, DOOR_HEIGHT)
    window = lambda centre: (centre, WINDOW_WIDTH, WINDOW_SILL, WINDOW_HEIGHT)

    # --- Outer shell -------------------------------------------------------
    # Front (north, +Y): the front door, facing the van, plus a window either
    # side of it so the facade reads as a house rather than a shed.
    add_wall_with_openings(
        bm, "x", HOUSE_MAX_Y, HOUSE_MIN_X, HOUSE_MAX_X,
        [door(-2.0), window(-7.0), window(3.0), window(7.5)],
    )
    # Back (south, -Y).
    add_wall_with_openings(
        bm, "x", HOUSE_MIN_Y, HOUSE_MIN_X, HOUSE_MAX_X,
        [window(-8.0), window(-3.0), window(4.0), window(8.5)],
    )
    # West (-X).
    add_wall_with_openings(
        bm, "y", HOUSE_MIN_X, HOUSE_MIN_Y, HOUSE_MAX_Y,
        [window(-9.5), window(-5.0), window(1.5)],
    )
    # East (+X).
    add_wall_with_openings(
        bm, "y", HOUSE_MAX_X, HOUSE_MIN_Y, HOUSE_MAX_Y,
        [window(-9.0), window(-4.5), window(2.0)],
    )

    # --- Corridor walls ----------------------------------------------------
    # The north side of the corridor, broken by the hall's mouth and by the two
    # front rooms' doors. The hall opening is left wide and doorless: it is the
    # junction the front door delivers into.
    add_wall_with_openings(
        bm, "x", CORRIDOR_Y_N, HOUSE_MIN_X, HOUSE_MAX_X,
        [door(-7.0), (-2.0, 3.2, 0.0, WALL_HEIGHT), door(5.0)],
    )
    # The south side, with a door into each of the three back rooms.
    add_wall_with_openings(
        bm, "x", CORRIDOR_Y_S, HOUSE_MIN_X, HOUSE_MAX_X,
        [door(-9.0), door(-4.0), door(5.0)],
    )

    # --- Partitions, front row (between corridor and front wall) -----------
    add_wall_with_openings(
        bm, "y", FRONT_SPLIT_W, CORRIDOR_Y_N, HOUSE_MAX_Y, [],
    )
    add_wall_with_openings(
        bm, "y", FRONT_SPLIT_E, CORRIDOR_Y_N, HOUSE_MAX_Y, [],
    )

    # --- Partitions, back row ---------------------------------------------
    add_wall_with_openings(
        bm, "y", BACK_SPLIT_W, HOUSE_MIN_Y, CORRIDOR_Y_S, [],
    )
    add_wall_with_openings(
        bm, "y", BACK_SPLIT_E, HOUSE_MIN_Y, CORRIDOR_Y_S, [],
    )

    bm.to_mesh(obj.data)
    bm.free()
    finish(obj, material("M_House_Wall"), WALL_UV_METRES, wall_sheet=True)
    return obj


def build_door(coll, name, hinge, rotation_deg, closed_deg, open_deg):
    """One door leaf, modelled from its hinge.

    The leaf occupies x in [0, DOOR_WIDTH] in its own local space, so the origin
    is the hinge and `HingedDoor` can swing it about Y with no offset to
    correct. `closed_deg` / `open_deg` ride to Godot as glTF node extras.
    """
    obj = new_mesh_object(name, coll)
    bm = bmesh.new()
    half = DOOR_LEAF_THICKNESS * 0.5
    add_box(bm, (0.0, -half, 0.0), (DOOR_WIDTH, half, DOOR_HEIGHT))
    bm.to_mesh(obj.data)
    bm.free()
    finish(obj, material("M_House_Door"), 1.0, leaf=True)

    obj.location = Vector(hinge)
    obj.rotation_euler = (0.0, 0.0, math.radians(rotation_deg))
    obj["closed_deg"] = float(closed_deg)
    obj["open_deg"] = float(open_deg)
    return obj


def build_doors(coll):
    """The leaves, one per doorway cut above.

    Every hinge sits on the edge of its opening and every leaf swings into the
    room rather than into the corridor, so an open door never blocks the run a
    crew is using to get past it.
    """
    doors = []
    # Front door, in the north wall, opening into the hall. This is the one the
    # crew walks to from the van.
    doors.append(build_door(
        coll, "Door_Entrada",
        (-2.0 - DOOR_WIDTH * 0.5, HOUSE_MAX_Y, 0.0), 0.0, 0.0, -90.0))

    # Corridor's north side: bedroom 1 and the living room.
    doors.append(build_door(
        coll, "Door_Quarto1",
        (-7.0 - DOOR_WIDTH * 0.5, CORRIDOR_Y_N, 0.0), 0.0, 0.0, -90.0))
    doors.append(build_door(
        coll, "Door_Sala",
        (5.0 + DOOR_WIDTH * 0.5, CORRIDOR_Y_N, 0.0), 180.0, 180.0, 270.0))

    # Corridor's south side: bathroom, bedroom 2, kitchen.
    doors.append(build_door(
        coll, "Door_Banheiro",
        (-9.0 - DOOR_WIDTH * 0.5, CORRIDOR_Y_S, 0.0), 0.0, 0.0, -90.0))
    doors.append(build_door(
        coll, "Door_Quarto2",
        (-4.0 + DOOR_WIDTH * 0.5, CORRIDOR_Y_S, 0.0), 180.0, 180.0, 270.0))
    doors.append(build_door(
        coll, "Door_Cozinha",
        (5.0 + DOOR_WIDTH * 0.5, CORRIDOR_Y_S, 0.0), 180.0, 180.0, 270.0))
    return doors


def build_windows(coll):
    """Glass panes filling the window openings.

    A separate object from the walls because it carries its own texture and
    because it must not be part of the walls' collision - the panes are set
    into openings a rat's navigation mesh should treat as solid wall, which the
    wall panels above and below them already provide.
    """
    obj = new_mesh_object("House_Windows", coll)
    bm = bmesh.new()
    half = 0.02
    z0 = WINDOW_SILL
    z1 = WINDOW_SILL + WINDOW_HEIGHT

    def pane_x(centre, y):
        add_box(bm, (centre - WINDOW_WIDTH * 0.5, y - half, z0),
                (centre + WINDOW_WIDTH * 0.5, y + half, z1))

    def pane_y(centre, x):
        add_box(bm, (x - half, centre - WINDOW_WIDTH * 0.5, z0),
                (x + half, centre + WINDOW_WIDTH * 0.5, z1))

    for c in (-7.0, 3.0, 7.5):
        pane_x(c, HOUSE_MAX_Y)
    for c in (-8.0, -3.0, 4.0, 8.5):
        pane_x(c, HOUSE_MIN_Y)
    for c in (-9.5, -5.0, 1.5):
        pane_y(c, HOUSE_MIN_X)
    for c in (-9.0, -4.5, 2.0):
        pane_y(c, HOUSE_MAX_X)

    bm.to_mesh(obj.data)
    bm.free()
    finish(obj, material("M_House_Window"), 1.0)
    return obj


# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------


def export(coll):
    if bpy.context.object is not None and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")
    for obj in coll.objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = next(iter(coll.objects), None)

    os.makedirs(os.path.dirname(EXPORT_PATH), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=EXPORT_PATH,
        use_selection=True,
        export_format="GLB",
        export_apply=True,
        export_texcoords=True,
        export_materials="EXPORT",
        export_extras=True,
    )
    return EXPORT_PATH


def build(do_export=True, do_save=False):
    coll = get_collection(COLLECTION_NAME)
    clear_collection(coll)

    build_floor(coll)
    build_ceiling(coll)
    build_walls(coll)
    build_doors(coll)
    build_windows(coll)

    result = {
        "objects": [o.name for o in coll.objects],
        "footprint": [HOUSE_MAX_X - HOUSE_MIN_X, HOUSE_MAX_Y - HOUSE_MIN_Y],
    }
    if do_export:
        result["export_path"] = export(coll)
    if do_save:
        bpy.ops.wm.save_as_mainfile(filepath=BLEND_SAVE_PATH)
        result["blend_path"] = BLEND_SAVE_PATH
    return result


if __name__ == "__main__":
    print("Result:", build())
