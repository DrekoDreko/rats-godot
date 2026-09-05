"""CAPRATS - modular house kit generator.

Regenerates the whole modular house kit from the constants declared below.
Run inside Blender (via MCP / socket) or with:
    blender --background --python blender/kit_casa.py

Design rules enforced by this script:
  * Metric units. REF_PLAYER cube kept in the scene for scale reading.
  * Every piece pivots on the lower-left corner of its module footprint,
    never on the centre.
  * Geometry is authored as a flat quad cage plus a Solidify modifier: no
    destructive vertex editing, thickness stays a constant at the top.
  * Transforms stay applied (scale 1,1,1 / rotation 0) because the meshes
    are authored directly in world space.
  * No surface detail: the PSX look comes from the Godot shader.
  * UVs are unwrapped on the export copies, so the modifier stack in the
    source scene stays live and the exported atlas has no overlap.
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

# ---------------------------------------------------------------------------
# PARAMETERS - change these and re-run to regenerate the whole kit
# ---------------------------------------------------------------------------

PROJECT_ROOT = r"C:\Users\Ferrareto\Documents\Lucas\GAMES\rats-godot"

MODULE = 2.0  # horizontal grid step, metres
WALL_HEIGHT = 2.4  # floor-to-ceiling clearance, metres
WALL_THICKNESS = 0.15
FLOOR_THICKNESS = 0.10
CEILING_THICKNESS = 0.10

DOOR_WIDTH = 0.90
DOOR_HEIGHT = 2.05

WINDOW_WIDTH = 1.00
WINDOW_HEIGHT = 1.00
WINDOW_SILL = 1.00  # height of the window bottom edge above the floor

PLAYER_HEIGHT = 1.75
PLAYER_WIDTH = 0.40

# Budgets used by the validation report.
TRI_BUDGET_MODULE = 200
TRI_BUDGET_PROP = (300, 800)

# UV atlas.
UV_ANGLE_LIMIT = math.radians(66.0)
UV_ISLAND_MARGIN = 0.02

MATERIAL_NAME = "M_KitCasa"
MATERIAL_COLOR = (0.62, 0.60, 0.56, 1.0)

COLLECTION_NAME = "KIT_CASA"
EXPORT_COLLECTION_NAME = "KIT_CASA_EXPORT"
REF_NAME = "REF_PLAYER"

# Which pieces to build on this run.
BUILD = [
    "wall_flat",
    "wall_door",
    "wall_window",
    "corner_inner",
    "corner_outer",
    "floor",
    "ceiling",
]

# Preview rendering.
RENDER_PREVIEWS = True
PREVIEW_DIR = os.path.join(PROJECT_ROOT, "blender", "_previews")
PREVIEW_RES = (960, 720)
PREVIEW_MARGIN = 1.35
LAYOUT_SPACING = 3.0  # gap between pieces on the preview row

# Export.
DO_EXPORT = True
EXPORT_DIR = os.path.join(PROJECT_ROOT, "assets", "models")


# ---------------------------------------------------------------------------
# Scene helpers
# ---------------------------------------------------------------------------


def get_collection(name, hide=False):
    coll = bpy.data.collections.get(name)
    if coll is None:
        coll = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(coll)
    if hide:
        layer = bpy.context.view_layer.layer_collection.children.get(name)
        if layer:
            layer.hide_viewport = True
    return coll


def clear_object(name):
    obj = bpy.data.objects.get(name)
    if obj is None:
        return
    mesh = obj.data
    bpy.data.objects.remove(obj, do_unlink=True)
    if mesh and mesh.users == 0:
        bpy.data.meshes.remove(mesh)


def new_object(name, verts, faces, collection):
    """Create a mesh object at the world origin, transform already applied."""
    clear_object(name)
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.validate()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj.location = (0.0, 0.0, 0.0)
    obj.rotation_euler = (0.0, 0.0, 0.0)
    obj.scale = (1.0, 1.0, 1.0)
    return obj


def get_material():
    mat = bpy.data.materials.get(MATERIAL_NAME)
    if mat is None:
        mat = bpy.data.materials.new(MATERIAL_NAME)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        if bsdf:
            bsdf.inputs["Base Color"].default_value = MATERIAL_COLOR
            bsdf.inputs["Roughness"].default_value = 1.0
            bsdf.inputs["Metallic"].default_value = 0.0
    return mat


def assign_material(obj):
    mat = get_material()
    if obj.data.materials:
        obj.data.materials[0] = mat
    else:
        obj.data.materials.append(mat)


def evaluated_bounds(obj):
    deps = bpy.context.evaluated_depsgraph_get()
    eval_obj = obj.evaluated_get(deps)
    mesh = eval_obj.to_mesh()
    lo = Vector((math.inf,) * 3)
    hi = Vector((-math.inf,) * 3)
    for vert in mesh.vertices:
        world = eval_obj.matrix_world @ vert.co
        for i in range(3):
            lo[i] = min(lo[i], world[i])
            hi[i] = max(hi[i], world[i])
    eval_obj.to_mesh_clear()
    return lo, hi


def add_solidify(obj, thickness, grow, even=False):
    """Solidify `obj`, flipping the offset until the shell grows the way
    `grow` asks. `grow` is a list of (axis_index, sign) the result must
    respect. The pivot stays on the module corner either way."""
    mod = obj.modifiers.new("Solidify", "SOLIDIFY")
    mod.thickness = thickness
    mod.offset = -1.0
    mod.use_even_offset = even
    mod.use_rim = True
    mod.use_rim_only = False
    if _grows_wrong_way(obj, grow):
        mod.offset = 1.0
    return mod


def _grows_wrong_way(obj, grow):
    lo, hi = evaluated_bounds(obj)
    for axis, sign in grow:
        if sign > 0 and lo[axis] < -1e-5:
            return True
        if sign < 0 and hi[axis] > 1e-5:
            return True
    return False


def grid_faces(cols, rows, skip):
    """Build a quad grid in a plane from column and row boundaries.

    `skip` lists (col, row) cells left empty, which is how the door and
    window openings are cut without a Boolean.
    Returns index pairs the caller maps into 3D.
    """
    faces = []
    stride = len(cols)
    for r in range(len(rows) - 1):
        for c in range(len(cols) - 1):
            if (c, r) in skip:
                continue
            a = r * stride + c
            faces.append((a, a + 1, a + stride + 1, a + stride))
    return faces


# ---------------------------------------------------------------------------
# Piece builders
# ---------------------------------------------------------------------------


def build_ref_player(collection):
    """1.75 m reference cube, pivot on the floor, standing beside the kit."""
    half = PLAYER_WIDTH * 0.5
    verts = [
        (-half, -half, 0.0),
        (half, -half, 0.0),
        (half, half, 0.0),
        (-half, half, 0.0),
        (-half, -half, PLAYER_HEIGHT),
        (half, -half, PLAYER_HEIGHT),
        (half, half, PLAYER_HEIGHT),
        (-half, half, PLAYER_HEIGHT),
    ]
    faces = [
        (0, 3, 2, 1),
        (4, 5, 6, 7),
        (0, 1, 5, 4),
        (1, 2, 6, 5),
        (2, 3, 7, 6),
        (3, 0, 4, 7),
    ]
    obj = new_object(REF_NAME, verts, faces, collection)
    obj.display_type = "WIRE"
    obj.show_name = True
    return obj


def _wall_panel(name, cols, rows, skip, collection):
    """Vertical wall cage in the XZ plane at y = 0, solidified towards +Y."""
    verts = [(x, 0.0, z) for z in rows for x in cols]
    faces = grid_faces(cols, rows, skip)
    obj = new_object(name, verts, faces, collection)
    add_solidify(obj, WALL_THICKNESS, [(1, 1)])
    return obj


def build_wall_flat(collection):
    """Plain wall panel, MODULE wide, pivot at the module corner."""
    return _wall_panel("wall_flat", [0.0, MODULE], [0.0, WALL_HEIGHT], set(), collection)


def build_wall_door(collection):
    """Wall with a centred DOOR_WIDTH x DOOR_HEIGHT opening."""
    x0 = (MODULE - DOOR_WIDTH) * 0.5
    cols = [0.0, x0, x0 + DOOR_WIDTH, MODULE]
    rows = [0.0, DOOR_HEIGHT, WALL_HEIGHT]
    return _wall_panel("wall_door", cols, rows, {(1, 0)}, collection)


def build_wall_window(collection):
    """Wall with a centred window opening sitting on WINDOW_SILL."""
    x0 = (MODULE - WINDOW_WIDTH) * 0.5
    cols = [0.0, x0, x0 + WINDOW_WIDTH, MODULE]
    rows = [0.0, WINDOW_SILL, WINDOW_SILL + WINDOW_HEIGHT, WALL_HEIGHT]
    return _wall_panel("wall_window", cols, rows, {(1, 1)}, collection)


def _corner(name, plan, grow, collection):
    """L-shaped wall corner built from a plan polyline extruded upwards.

    The mitre comes from an even-offset Solidify, so the leg thickness stays
    WALL_THICKNESS all the way through the bend.
    """
    verts = []
    for x, y in plan:
        verts.append((x, y, 0.0))
    for x, y in plan:
        verts.append((x, y, WALL_HEIGHT))
    count = len(plan)
    faces = [(i, i + 1, count + i + 1, count + i) for i in range(count - 1)]
    obj = new_object(name, verts, faces, collection)
    add_solidify(obj, WALL_THICKNESS, grow, even=True)
    return obj


def build_corner_outer(collection):
    """Convex corner: the two exposed faces meet at the module origin, the
    room sits in the +X / +Y quadrant."""
    plan = [(MODULE, 0.0), (0.0, 0.0), (0.0, MODULE)]
    return _corner("corner_outer", plan, [(0, 1), (1, 1)], collection)


def build_corner_inner(collection):
    """Concave corner: the exposed faces look back at the module origin, and
    the shell grows outwards to fill the module footprint."""
    inset = MODULE - WALL_THICKNESS
    plan = [(0.0, inset), (inset, inset), (inset, 0.0)]
    return _corner("corner_inner", plan, [(0, 1), (1, 1)], collection)


def _slab(name, z_base, thickness, grow_sign, collection):
    verts = [
        (0.0, 0.0, z_base),
        (MODULE, 0.0, z_base),
        (MODULE, MODULE, z_base),
        (0.0, MODULE, z_base),
    ]
    obj = new_object(name, verts, [(0, 1, 2, 3)], collection)
    mod = obj.modifiers.new("Solidify", "SOLIDIFY")
    mod.thickness = thickness
    mod.offset = -1.0
    mod.use_even_offset = False
    lo, hi = evaluated_bounds(obj)
    if grow_sign > 0 and lo.z < z_base - 1e-5:
        mod.offset = 1.0
    if grow_sign < 0 and hi.z > z_base + 1e-5:
        mod.offset = 1.0
    return obj


def build_floor(collection):
    """Floor tile. Walk surface on z = 0, slab hanging below it, so floors
    and walls share the same module origin."""
    return _slab("floor", 0.0, FLOOR_THICKNESS, -1, collection)


def build_ceiling(collection):
    """Ceiling tile. Underside at WALL_HEIGHT, slab growing upwards, pivot
    still on the module corner at z = 0 level in plan."""
    return _slab("ceiling", WALL_HEIGHT, CEILING_THICKNESS, 1, collection)


BUILDERS = {
    "wall_flat": build_wall_flat,
    "wall_door": build_wall_door,
    "wall_window": build_wall_window,
    "corner_inner": build_corner_inner,
    "corner_outer": build_corner_outer,
    "floor": build_floor,
    "ceiling": build_ceiling,
}


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------


def validate(obj, evaluated=True):
    """Report the numbers the art direction cares about, measured on the
    modifier result rather than on the cage."""
    if evaluated:
        deps = bpy.context.evaluated_depsgraph_get()
        source = obj.evaluated_get(deps)
        mesh = source.to_mesh()
    else:
        source = obj
        mesh = obj.data

    bm = bmesh.new()
    bm.from_mesh(mesh)

    ngons = sum(1 for f in bm.faces if len(f.verts) > 4)
    quads = sum(1 for f in bm.faces if len(f.verts) == 4)
    tri_faces = sum(1 for f in bm.faces if len(f.verts) == 3)
    non_manifold = sum(1 for e in bm.edges if len(e.link_faces) != 2)
    loose_verts = sum(1 for v in bm.verts if not v.link_edges)

    # Signed volume: positive means the normals point outwards.
    volume = 0.0
    for face in bm.faces:
        origin = face.verts[0].co
        for i in range(1, len(face.verts) - 1):
            volume += origin.dot(face.verts[i].co.cross(face.verts[i + 1].co)) / 6.0

    uv_overlap = _uv_overlap_count(bm, mesh) if mesh.uv_layers else None

    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    tris = len(bm.faces)
    bm.free()

    has_uv = len(mesh.uv_layers) > 0
    if evaluated:
        source.to_mesh_clear()

    lo, hi = evaluated_bounds(obj)
    size = hi - lo

    return {
        "name": obj.name,
        "tris": tris,
        "quads": quads,
        "tri_faces": tri_faces,
        "ngons": ngons,
        "non_manifold_edges": non_manifold,
        "loose_verts": loose_verts,
        "normals_outward": volume > 0.0,
        "transform_applied": (
            tuple(round(v, 6) for v in obj.scale) == (1.0, 1.0, 1.0)
            and all(abs(a) < 1e-6 for a in obj.rotation_euler)
        ),
        "size": [round(v, 4) for v in size],
        "height_vs_player": round(size.z / PLAYER_HEIGHT, 3),
        "uv": has_uv,
        "uv_overlaps": uv_overlap,
        "within_module_budget": tris <= TRI_BUDGET_MODULE,
    }


EPS = 1e-9


def _signed_area(a, b, c):
    return ((b[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (b[1] - a[1])) * 0.5


def _segments_cross(p, q, r, s):
    d1 = _signed_area(r, s, p)
    d2 = _signed_area(r, s, q)
    d3 = _signed_area(p, q, r)
    d4 = _signed_area(p, q, s)
    # Strict on both sides: segments that merely share an endpoint, as every
    # fan triangulation of a quad does, must not count as a crossing.
    straddles_rs = (d1 > EPS and d2 < -EPS) or (d1 < -EPS and d2 > EPS)
    straddles_pq = (d3 > EPS and d4 < -EPS) or (d3 < -EPS and d4 > EPS)
    return straddles_rs and straddles_pq


def _point_inside(tri, p):
    a = _signed_area(tri[0], tri[1], p)
    b = _signed_area(tri[1], tri[2], p)
    c = _signed_area(tri[2], tri[0], p)
    return (a > EPS and b > EPS and c > EPS) or (a < -EPS and b < -EPS and c < -EPS)


def _tris_overlap(t1, t2):
    for i in range(3):
        for j in range(3):
            if _segments_cross(t1[i], t1[(i + 1) % 3], t2[j], t2[(j + 1) % 3]):
                return True
    return _point_inside(t1, t2[0]) or _point_inside(t2, t1[0])


def uv_triangles(mesh):
    """Fan-triangulated UV coordinates for every face of `mesh`."""
    if not mesh.uv_layers:
        return []
    uvs = mesh.uv_layers.active.data
    tris = []
    for poly in mesh.polygons:
        loops = [tuple(uvs[i].uv) for i in poly.loop_indices]
        for i in range(1, len(loops) - 1):
            tris.append((loops[0], loops[i], loops[i + 1]))
    return tris


def count_uv_overlaps(triangles):
    """Exact overlap count. Bounding boxes are only used to skip pairs that
    cannot touch; the verdict always comes from the triangles themselves."""
    boxes = [
        (
            min(p[0] for p in t),
            min(p[1] for p in t),
            max(p[0] for p in t),
            max(p[1] for p in t),
        )
        for t in triangles
    ]
    hits = 0
    for i in range(len(triangles)):
        for j in range(i + 1, len(triangles)):
            a, b = boxes[i], boxes[j]
            if a[0] >= b[2] or b[0] >= a[2] or a[1] >= b[3] or b[1] >= a[3]:
                continue
            if _tris_overlap(triangles[i], triangles[j]):
                hits += 1
    return hits


def _uv_overlap_count(bm, mesh):
    return count_uv_overlaps(uv_triangles(mesh))


def atlas_report(objects):
    """Whole-set atlas check: every piece must share one 0-1 space without a
    single overlapping triangle."""
    triangles = []
    per_piece = {}
    for obj in objects:
        tris = uv_triangles(obj.data)
        per_piece[obj.name] = [
            round(min(p[0] for t in tris for p in t), 4),
            round(min(p[1] for t in tris for p in t), 4),
            round(max(p[0] for t in tris for p in t), 4),
            round(max(p[1] for t in tris for p in t), 4),
        ] if tris else None
        triangles.extend(tris)
    return {
        "triangles": len(triangles),
        "overlaps": count_uv_overlaps(triangles),
        "inside_0_1": all(
            box and -1e-4 <= box[0] and -1e-4 <= box[1] and box[2] <= 1.0001 and box[3] <= 1.0001
            for box in per_piece.values()
        ),
        "bounds": per_piece,
    }


# ---------------------------------------------------------------------------
# Export copies + shared UV atlas
# ---------------------------------------------------------------------------


def find_view3d():
    for window in bpy.context.window_manager.windows:
        for area in window.screen.areas:
            if area.type == "VIEW_3D":
                region = next((r for r in area.regions if r.type == "WINDOW"), None)
                return window, area, region
    return None, None, None


def build_export_copies(objects, collection):
    """Freeze the modifier stack into standalone meshes sitting back on the
    module origin. The source objects keep their live modifiers."""
    deps = bpy.context.evaluated_depsgraph_get()
    copies = []
    for obj in objects:
        name = obj.name + "_EXPORT"
        clear_object(name)
        eval_obj = obj.evaluated_get(deps)
        mesh = bpy.data.meshes.new_from_object(eval_obj)
        mesh.name = name
        copy = bpy.data.objects.new(name, mesh)
        collection.objects.link(copy)
        copy.location = (0.0, 0.0, 0.0)
        copy.rotation_euler = (0.0, 0.0, 0.0)
        copy.scale = (1.0, 1.0, 1.0)
        assign_material(copy)
        copies.append(copy)
    return copies


def set_collection_hidden(name, hidden):
    layer = bpy.context.view_layer.layer_collection.children.get(name)
    if layer is None:
        return None
    previous = layer.hide_viewport
    layer.hide_viewport = hidden
    return previous


def unwrap_atlas(objects):
    """Smart-project every piece at once so the islands share one atlas and
    are packed against each other instead of stacking.

    Edit mode refuses objects living in a hidden collection, so the export
    collection is revealed for the duration of the unwrap.
    """
    previous = set_collection_hidden(EXPORT_COLLECTION_NAME, False)
    try:
        _unwrap_atlas(objects)
    finally:
        if previous is not None:
            set_collection_hidden(EXPORT_COLLECTION_NAME, previous)


def _unwrap_atlas(objects):
    view_layer = bpy.context.view_layer
    for obj in view_layer.objects:
        obj.select_set(False)
    for obj in objects:
        obj.select_set(True)
    view_layer.objects.active = objects[0]

    window, area, region = find_view3d()
    kwargs = dict(
        angle_limit=UV_ANGLE_LIMIT,
        island_margin=UV_ISLAND_MARGIN,
        correct_aspect=True,
        scale_to_bounds=False,
    )

    def run():
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(**kwargs)
        bpy.ops.uv.select_all(action="SELECT")
        # smart_project packs each object on its own, which would stack every
        # piece on the same corner of the atlas. Repack across the selection.
        bpy.ops.uv.pack_islands(
            rotate=True,
            scale=True,
            margin=UV_ISLAND_MARGIN,
            merge_overlap=False,
        )
        bpy.ops.object.mode_set(mode="OBJECT")

    if area is not None:
        with bpy.context.temp_override(window=window, area=area, region=region):
            run()
    else:
        run()


def export_glb(obj):
    """One GLB per piece, +Y up / -Z forward, Godot 4 preset."""
    os.makedirs(EXPORT_DIR, exist_ok=True)
    path = os.path.join(EXPORT_DIR, obj.name.replace("_EXPORT", "") + ".glb")

    view_layer = bpy.context.view_layer
    for other in view_layer.objects:
        other.select_set(False)
    obj.select_set(True)
    view_layer.objects.active = obj

    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=False,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
        export_extras=False,
    )
    return path


# ---------------------------------------------------------------------------
# Preview rendering
# ---------------------------------------------------------------------------


def layout_row(objects):
    """Spread the pieces along +X so the scene reads in the viewport."""
    cursor = 0.0
    for obj in objects:
        lo, hi = evaluated_bounds(obj)
        obj.location.x += cursor - lo.x
        cursor += (hi.x - lo.x) + LAYOUT_SPACING
    return cursor


def setup_preview_world():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = PREVIEW_RES[0]
    scene.render.resolution_y = PREVIEW_RES[1]
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = "PNG"
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "SINGLE"
    shading.single_color = (0.55, 0.55, 0.58)
    shading.show_cavity = True
    shading.show_object_outline = True
    scene.display.render_aa = "8"


def get_preview_camera():
    cam_data = bpy.data.cameras.get("PREVIEW_CAM")
    if cam_data is None:
        cam_data = bpy.data.cameras.new("PREVIEW_CAM")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.get("PREVIEW_CAM")
    if cam is None:
        cam = bpy.data.objects.new("PREVIEW_CAM", cam_data)
        bpy.context.scene.collection.objects.link(cam)
    cam.data = cam_data
    bpy.context.scene.camera = cam
    return cam


# name: (offset direction, rotation, horizontal axis, vertical axis)
VIEWS = {
    "front": ((0.0, -30.0, 0.0), (math.pi / 2, 0.0, 0.0), 0, 2),
    "side": ((30.0, 0.0, 0.0), (math.pi / 2, 0.0, math.pi / 2), 1, 2),
    "top": ((0.0, 0.0, 30.0), (0.0, 0.0, 0.0), 0, 1),
}


def render_ortho(objects, tag):
    """Three orthographic views framed on `objects`, everything else hidden."""
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    setup_preview_world()
    cam = get_preview_camera()

    keep = {o.name for o in objects}
    hidden = []
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        want = obj.name in keep
        if obj.hide_render != (not want):
            hidden.append((obj, obj.hide_render))
            obj.hide_render = not want

    lo = Vector((math.inf,) * 3)
    hi = Vector((-math.inf,) * 3)
    for obj in objects:
        o_lo, o_hi = evaluated_bounds(obj)
        for i in range(3):
            lo[i] = min(lo[i], o_lo[i])
            hi[i] = max(hi[i], o_hi[i])
    center = (lo + hi) * 0.5
    size = hi - lo
    aspect = PREVIEW_RES[0] / PREVIEW_RES[1]

    written = []
    for view, (offset, rot, h_axis, v_axis) in VIEWS.items():
        cam.location = center + Vector(offset)
        cam.rotation_euler = rot
        cam.data.ortho_scale = max(size[h_axis], size[v_axis] * aspect) * PREVIEW_MARGIN
        path = os.path.join(PREVIEW_DIR, "{}_{}.png".format(tag, view))
        bpy.context.scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        written.append(path)

    for obj, state in hidden:
        obj.hide_render = state
    return written


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main():
    collection = get_collection(COLLECTION_NAME)
    export_collection = get_collection(EXPORT_COLLECTION_NAME, hide=True)

    ref = build_ref_player(collection)
    built = [BUILDERS[name](collection) for name in BUILD if name in BUILDERS]
    for obj in built:
        assign_material(obj)
    layout_row(built)
    ref.location = (-1.4, MODULE * 0.5, 0.0)

    report = {
        "parameters": {
            "MODULE": MODULE,
            "WALL_HEIGHT": WALL_HEIGHT,
            "WALL_THICKNESS": WALL_THICKNESS,
            "FLOOR_THICKNESS": FLOOR_THICKNESS,
            "CEILING_THICKNESS": CEILING_THICKNESS,
            "DOOR": [DOOR_WIDTH, DOOR_HEIGHT],
            "WINDOW": [WINDOW_WIDTH, WINDOW_HEIGHT, WINDOW_SILL],
            "PLAYER_HEIGHT": PLAYER_HEIGHT,
        },
        "source": [validate(obj) for obj in built],
    }

    copies = build_export_copies(built, export_collection)
    unwrap_atlas(copies)
    report["export"] = [validate(obj, evaluated=False) for obj in copies]
    report["atlas"] = atlas_report(copies)

    if DO_EXPORT:
        report["glb"] = [export_glb(obj) for obj in copies]

    if RENDER_PREVIEWS:
        previews = {}
        for obj in built:
            # Park the reference cube just left of the piece being shot.
            lo, hi = evaluated_bounds(obj)
            ref.location = (lo.x - 0.6, (lo.y + hi.y) * 0.5, 0.0)
            previews[obj.name] = render_ortho([obj, ref], obj.name)
        ref.location = (-1.4, MODULE * 0.5, 0.0)
        previews["kit"] = render_ortho(built + [ref], "kit")
        report["previews"] = previews

    return report


if __name__ == "__main__":
    result = main()
    if "--background" in sys.argv or "-b" in sys.argv:
        import pprint

        pprint.pprint(result)
