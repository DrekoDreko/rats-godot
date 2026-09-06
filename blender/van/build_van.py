"""Build a low-poly (PS1-style) cargo van modelled after van_ref_256.png.

Run headless:
    blender -b --factory-startup --python build_van.py

The silhouette is derived from the blueprint's own pixels: the side view spans
136x54 texels for a 5.00 m x 1.985 m van, so every landmark below is written in
texels first and converted to metres through PX_PER_M. UVs are then box-projected
onto the matching blueprint view, which keeps the reference art as the final
texture.
"""

import math
import os

import bmesh
import bpy

# --------------------------------------------------------------------------- #
# Paths
# --------------------------------------------------------------------------- #

HERE = os.path.dirname(os.path.abspath(__file__))
TEXTURE_PATH = os.path.join(HERE, "van_tex_256.png")
OUTPUT_BLEND = os.path.join(HERE, "van.blend")

# --------------------------------------------------------------------------- #
# Blueprint views: tight silhouette rectangles measured from the texture,
# as (u_min, v_min, u_max, v_max) with the origin at the bottom-left.
# --------------------------------------------------------------------------- #

# Each view is stored as the texel rectangle the van's BODY occupies, measured
# by scanning the artwork column by column. They are deliberately the body only:
# the wing mirrors stick out past it in the front view, and the top view is
# narrower still because it excludes the wheel arches.
TEXEL_RECTS = {
    # (x_min, y_min, x_max, y_max) in 256x171 texel space, y down from the top.
    "front": (17.0, 5.0, 68.0, 60.0),
    "rear": (17.0, 62.0, 68.0, 116.0),
    "side_r": (86.0, 6.0, 222.0, 60.0),
    "side_l": (83.0, 62.0, 219.0, 120.0),
    "top": (85.0, 121.0, 218.0, 164.0),
}

TEX_W = 256.0
TEX_H = 171.0


def to_uv_rect(rect):
    """Texel rectangle (y down) -> UV rectangle (v up)."""
    x0, y0, x1, y1 = rect
    return (x0 / TEX_W, 1.0 - y1 / TEX_H, x1 / TEX_W, 1.0 - y0 / TEX_H)


VIEWS = {name: to_uv_rect(rect) for name, rect in TEXEL_RECTS.items()}

# The side view spans 136 texels for the whole van; the front view's body is
# 51 texels wide, and the top view's roof 43.
SIDE_PX_W = 136.0
SIDE_PX_H = 54.0
FRONT_BODY_PX_W = 51.0
ROOF_PX_W = 43.0

LENGTH = 5.00
PX_PER_M = SIDE_PX_W / LENGTH
HEIGHT = SIDE_PX_H / PX_PER_M            # ~1.985 m
WIDTH = FRONT_BODY_PX_W / PX_PER_M       # ~1.875 m
BODY_HALF = WIDTH / 2.0
ROOF_HALF = ROOF_PX_W / PX_PER_M / 2.0   # the roof is narrower than the sills


def x_of(texel):
    """Texel column in the side view -> metres from the front bumper."""
    return texel / PX_PER_M


def z_of(texel_row):
    """Texel row in the side view (0 = roof) -> metres above the ground."""
    return (SIDE_PX_H - texel_row) / PX_PER_M


# --------------------------------------------------------------------------- #
# Landmarks read off the silhouette profile of the side view.
# Columns run 0 (front bumper) .. 135 (rear bumper); rows run 0 (roof) .. 53.
# --------------------------------------------------------------------------- #

X_NOSE = x_of(0.0)          # front bumper face
X_GRILLE = x_of(2.0)        # grille / headlight band
X_HOOD_F = x_of(11.0)       # hood front, where the bonnet flattens
X_COWL = x_of(13.0)         # base of the windshield
X_ROOF_F = x_of(30.0)       # windshield meets the roof
X_CAB_B = x_of(47.0)        # rear of the cab door
X_BODY_B = x_of(128.0)      # rear body panel
X_TAIL = x_of(135.0)        # rear bumper face

Z_ROOF = z_of(0.0)          # 1.985 m
Z_ROOF_CAB = z_of(1.0)
Z_WINDSHIELD_T = z_of(8.0)
Z_COWL = z_of(21.0)         # top of the hood at the windshield base
Z_HOOD = z_of(22.0)         # top of the hood
Z_HEADLIGHT = z_of(38.0)    # nose top: bumper/grille cap
Z_SILL = z_of(45.0)         # bottom of the rear body panels
Z_SILL_CAB = z_of(46.0)     # bottom of the cab / rocker
Z_BUMPER_B = z_of(44.0)     # rear bumper lower edge
Z_GROUND = 0.0

# Wheels: the arches sit at columns 12-27 (front) and 93-109 (rear), so their
# centres land at columns 20 and 101, radius ~7.5 texels.
WHEEL_R = 8.0 / PX_PER_M
WHEEL_W = 0.20
WHEEL_X_F = x_of(20.0)
WHEEL_X_B = x_of(101.0)
WHEEL_SEGMENTS = 10

# Roof-corner chamfer, matching the rounded roof edge drawn in the blueprint.
CHAMFER = 3.0 / PX_PER_M

# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #


def remap(value, src_min, src_max, dst_min, dst_max):
    if src_max - src_min == 0.0:
        return dst_min
    return dst_min + (value - src_min) / (src_max - src_min) * (dst_max - dst_min)


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


# --------------------------------------------------------------------------- #
# Body
# --------------------------------------------------------------------------- #


def build_body():
    """Loft the van shell through cross sections placed along +X.

    Each entry is (x, half_width_factor, z_bottom, z_top); consecutive sections
    are bridged into quads so the mesh stays quad-dominant and cheap.
    """
    sections = [
        (X_NOSE, 0.88, Z_SILL_CAB, Z_HEADLIGHT),
        (X_GRILLE, 0.96, Z_SILL_CAB - 0.05, Z_HOOD + 0.02),
        (X_HOOD_F, 1.00, Z_SILL_CAB - 0.05, Z_HOOD),
        (X_COWL, 1.00, Z_SILL_CAB - 0.05, Z_COWL),
        (X_ROOF_F, 1.00, Z_SILL_CAB - 0.05, Z_ROOF_CAB),
        (X_CAB_B, 1.00, Z_SILL_CAB - 0.05, Z_ROOF),
        (X_BODY_B, 1.00, Z_SILL - 0.05, Z_ROOF),
        (X_TAIL, 0.97, Z_BUMPER_B, Z_ROOF - 0.02),
    ]

    mesh = bpy.data.meshes.new("VanBody")
    obj = bpy.data.objects.new("Van", mesh)
    bpy.context.collection.objects.link(obj)

    bm = bmesh.new()
    rings = []
    for x, factor, z_bottom, z_top in sections:
        half = BODY_HALF * factor
        rings.append(_section_ring(bm, x, half, z_bottom, z_top))

    bm.verts.ensure_lookup_table()

    count = len(rings[0])
    for a, b in zip(rings, rings[1:]):
        for i in range(count):
            j = (i + 1) % count
            bm.faces.new((a[i], a[j], b[j], b[i]))

    bm.faces.new(tuple(reversed(rings[0])))
    bm.faces.new(tuple(rings[-1]))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    return obj


def _section_ring(bm, x, half, z_bottom, z_top):
    """One cross section, walked anticlockwise seen from +X.

    The blueprint's front view is 51 texels across at the sills but only 43 at
    the roof, so each section tapers toward the top instead of being a plain
    box. That taper is also what keeps the roof faces inside the painted top
    view when they are projected.
    """
    roof_half = min(half, ROOF_HALF)
    chamfer_z = min(CHAMFER, (z_top - z_bottom) * 0.3)

    coords = [
        (-half, z_bottom),
        (half, z_bottom),
        (half, z_top - chamfer_z),
        (roof_half, z_top),
        (-roof_half, z_top),
        (-half, z_top - chamfer_z),
    ]
    return [bm.verts.new((x, y, z)) for y, z in coords]


def build_wheel(name, x, y):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=WHEEL_SEGMENTS,
        radius=WHEEL_R,
        depth=WHEEL_W,
        location=(x, y, WHEEL_R),
        rotation=(math.radians(90.0), 0.0, 0.0),
    )
    obj = bpy.context.active_object
    obj.name = name
    return obj


def build_wheels():
    inset = BODY_HALF - WHEEL_W * 0.5
    wheels = []
    for tag, x in (("F", WHEEL_X_F), ("B", WHEEL_X_B)):
        for side, y in (("L", -inset), ("R", inset)):
            wheels.append(build_wheel(f"Wheel_{tag}{side}", x, y))
    return wheels


# --------------------------------------------------------------------------- #
# UV projection
# --------------------------------------------------------------------------- #

# The blueprint views are drawn with rounded corners and slightly tapered ends,
# while the mesh is a straight box, so a plain fit-to-rectangle projection walks
# off the artwork and samples the white page. Pulling each view in by a texel or
# two keeps every face inside the painted silhouette.
TEXEL_U = 1.0 / 256.0
TEXEL_V = 1.0 / 171.0

# A face leaning sideways by more than this is treated as body panel rather
# than roof, which keeps the chamfer strips on the side views.
CHAMFER_NORMAL_Y = 0.35

# The roof chamfer sits a touch above the roof line drawn in the side view, so
# the vertical mapping stops just short of the view's top edge.
ROOF_BLEED = 2.0 / 171.0

# The outermost texel of every view is the drawing's own anti-aliased outline,
# which reads as a bright seam wherever a face lands on it. Pulling the mapping
# in by a texel and a half samples solid body paint instead.
VIEW_INSET_TEXELS = {
    "front": (1.5, 1.5),
    "rear": (1.5, 1.5),
    "side_r": (1.5, 1.5),
    "side_l": (1.5, 1.5),
    "top": (1.5, 1.5),
}


def view_rect(name):
    u0, v0, u1, v1 = VIEWS[name]
    inset_u, inset_v = VIEW_INSET_TEXELS[name]
    du = inset_u * TEXEL_U
    dv = inset_v * TEXEL_V
    return u0 + du, v0 + dv, u1 - du, v1 - dv


def project_body_uvs(obj):
    """Box-project every body face onto the blueprint view it faces."""
    mesh = obj.data
    if not mesh.uv_layers:
        mesh.uv_layers.new(name="UVMap")
    uv_layer = mesh.uv_layers.active.data

    for poly in mesh.polygons:
        normal = poly.normal
        ax, ay, az = abs(normal.x), abs(normal.y), abs(normal.z)

        if ax >= ay and ax >= az:
            view = "rear" if normal.x > 0.0 else "front"
        elif ay > CHAMFER_NORMAL_Y:
            # Anything with a real sideways lean is body panel — including the
            # chamfer strips, which face up as much as out. Sending those to the
            # top view instead would push their UVs off the artwork entirely,
            # onto the blueprint's white page.
            view = "side_r" if normal.y > 0.0 else "side_l"
        else:
            view = "top"

        u0, v0, u1, v1 = view_rect(view)

        for loop_index in poly.loop_indices:
            co = mesh.vertices[mesh.loops[loop_index].vertex_index].co

            if view == "side_r":
                u = remap(co.x, X_NOSE, X_TAIL, u0, u1)
                v = remap(co.z, Z_GROUND, Z_ROOF, v0, v1 - ROOF_BLEED)
            elif view == "side_l":
                # The left-hand view is mirrored: its cab sits on the right.
                u = remap(co.x, X_NOSE, X_TAIL, u1, u0)
                v = remap(co.z, Z_GROUND, Z_ROOF, v0, v1 - ROOF_BLEED)
            elif view == "front":
                u = remap(co.y, -BODY_HALF, BODY_HALF, u1, u0)
                v = remap(co.z, Z_GROUND, Z_ROOF, v0, v1 - ROOF_BLEED)
            elif view == "rear":
                u = remap(co.y, -BODY_HALF, BODY_HALF, u0, u1)
                v = remap(co.z, Z_GROUND, Z_ROOF, v0, v1 - ROOF_BLEED)
            else:  # top
                # The top view is measured across the roof, which is narrower
                # than the body, so it is the roof width that maps to the view.
                u = remap(co.x, X_NOSE, X_TAIL, u0, u1)
                v = remap(co.y, -ROOF_HALF, ROOF_HALF, v0, v1)

            uv_layer[loop_index].uv = (u, v)


def project_wheel_uvs(obj):
    """UV a wheel: the two round caps get the blueprint hub, the tread gets tyre.

    Projecting the whole cylinder from the side would smear the hub across the
    tread, so the side caps are projected and the tread band is pinned to a
    single dark texel instead.
    """
    mesh = obj.data
    if not mesh.uv_layers:
        mesh.uv_layers.new(name="UVMap")
    uv_layer = mesh.uv_layers.active.data

    su0, sv0, su1, sv1 = VIEWS["side_r"]

    # The front wheel is drawn at columns 13..27, rows 39..53 of the side view.
    u0 = remap(13.0, 0.0, SIDE_PX_W, su0, su1)
    u1 = remap(27.0, 0.0, SIDE_PX_W, su0, su1)
    v0 = remap(53.0, SIDE_PX_H, 0.0, sv0, sv1)
    v1 = remap(39.0, SIDE_PX_H, 0.0, sv0, sv1)

    # A flat, dark texel taken from the middle of the cargo panel, for the tread.
    tread_u = remap(80.0, 0.0, SIDE_PX_W, su0, su1)
    tread_v = remap(30.0, SIDE_PX_H, 0.0, sv0, sv1)

    for poly in mesh.polygons:
        is_cap = abs(poly.normal.y) > 0.5
        for loop_index in poly.loop_indices:
            if not is_cap:
                uv_layer[loop_index].uv = (tread_u, tread_v)
                continue
            co = mesh.vertices[mesh.loops[loop_index].vertex_index].co
            u = remap(co.x, -WHEEL_R, WHEEL_R, u0, u1)
            v = remap(co.z, -WHEEL_R, WHEEL_R, v0, v1)
            uv_layer[loop_index].uv = (u, v)


# --------------------------------------------------------------------------- #
# Material
# --------------------------------------------------------------------------- #


def build_material():
    """PS1-flavoured material: blueprint texture sampled with nearest filtering."""
    material = bpy.data.materials.new("VanPS1")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()

    output = nodes.new("ShaderNodeOutputMaterial")
    output.location = (400, 0)

    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (100, 0)
    bsdf.inputs["Roughness"].default_value = 0.85
    bsdf.inputs["Metallic"].default_value = 0.0

    tex = nodes.new("ShaderNodeTexImage")
    tex.location = (-260, 0)
    tex.interpolation = "Closest"
    if os.path.exists(TEXTURE_PATH):
        tex.image = bpy.data.images.load(TEXTURE_PATH)

    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    return material


# --------------------------------------------------------------------------- #
# Entry point
# --------------------------------------------------------------------------- #


def main():
    clear_scene()

    body = build_body()
    project_body_uvs(body)

    # Wheels are bulges on the body itself, added afterwards by fix_wheels.py.
    wheels = []

    material = build_material()
    for obj in [body] + wheels:
        obj.data.materials.append(material)
        for poly in obj.data.polygons:
            poly.use_smooth = False

    for wheel in wheels:
        wheel.parent = body
        wheel.matrix_parent_inverse = body.matrix_world.inverted()

    # Put the origin at the centre of the footprint for a sane Godot import.
    body.location = (-LENGTH / 2.0, 0.0, 0.0)

    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND)

    tris = sum(len(p.vertices) - 2 for o in [body] + wheels for p in o.data.polygons)
    print(f"BUILD_OK tris={tris} size={LENGTH:.2f}x{WIDTH:.2f}x{Z_ROOF:.2f} m")


# Guarded so fix_wheels.py can import the shared projection helpers
# without rebuilding the mesh.
if __name__ == "__main__":
    main()
