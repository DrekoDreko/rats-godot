"""Export the van to GLB for Godot.

Run headless:
    blender -b van.blend --python export_van.py -- ../../models/van_exterior.glb
"""
import sys
import bpy

out = sys.argv[-1]

obj = bpy.data.objects["Van"]

# The game shades everything with the unshaded PS1 shader, which reads the
# albedo texture off whatever material the importer produced. Emission carries
# it through untouched: a Principled base colour would arrive wanting a light.
for material in bpy.data.materials:
    if not material.use_nodes:
        continue
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    tex = next((n for n in nodes if n.type == "TEX_IMAGE"), None)
    bsdf = next((n for n in nodes if n.type == "BSDF_PRINCIPLED"), None)
    if tex is None or bsdf is None:
        continue
    bsdf.inputs["Emission Strength"].default_value = 1.0
    links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])

# Sit the van on the ground and centre it on its own length. The blueprint's
# drop shadow puts the lowest tread a few centimetres above z=0, which in the
# game reads as a van hovering; and an origin at the front bumper makes every
# placement an offset calculation. Both are fixed here rather than in the .blend,
# where the bumper origin is what the texel measurements are written against.
mesh = obj.data
lowest = min((obj.matrix_world @ v.co).z for v in mesh.vertices)
xs = [(obj.matrix_world @ v.co).x for v in mesh.vertices]
centre_x = (min(xs) + max(xs)) / 2.0
for vertex in mesh.vertices:
    vertex.co.x -= centre_x
    vertex.co.z -= lowest
mesh.update()

# Pack the texture so the .glb is one self-contained file, like the other models.
bpy.ops.file.pack_all()

for o in bpy.data.objects:
    o.select_set(o is obj)
bpy.context.view_layer.objects.active = obj

bpy.ops.export_scene.gltf(
    filepath=out,
    export_format="GLB",
    use_selection=True,
    export_apply=True,
    export_yup=True,
    export_texcoords=True,
    export_normals=True,
    export_materials="EXPORT",
    export_cameras=False,
    export_lights=False,
    export_animations=False,
)
print("EXPORTED", out)
