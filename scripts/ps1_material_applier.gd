@tool
class_name PS1MaterialApplier
extends Node
## Applies a PS1-style ShaderMaterial to every MeshInstance3D under this node's
## parent. Drop it as a child of any mesh — including instanced GLB/FBX scenes,
## whose inner nodes cannot be edited from the editor.
##
##     Malha (imported scene)
##     └─ PS1MaterialApplier      material = res://materials/ps1.tres
##
## The albedo texture is not configured here: it is read from whatever material
## the surface already had, so imported models keep their own textures and every
## object can share the same ShaderMaterial resource.

## Name of the shader uniform that receives each surface's albedo texture.
const ALBEDO_UNIFORM := "albedo"

## Name of the shader uniform that receives each surface's albedo color. Models
## exported without textures carry all their looks in this color alone.
const ALBEDO_COLOR_UNIFORM := "albedo_color"

## Name of the shader uniform that receives how many times the texture repeats
## over a surface. It is read from the material the surface already had —
## `uv1_scale` on a `StandardMaterial3D`, the same uniform on a `ShaderMaterial`
## — because a floor tiles its concrete and a model with baked UVs does not, and
## that difference belongs to the surface rather than to this node.
const UV_SCALE_UNIFORM := "uv_scale"

## Shader material to apply. Shared by reference, so editing the .tres affects
## every object using it — unless `unique_material` is on.
@export var material: ShaderMaterial:
	set(value):
		material = value
		_apply()

## Applies a private copy of the material to this object, so its shader
## parameters can be tweaked without touching the ones shared by other objects.
@export var unique_material := false:
	set(value):
		unique_material = value
		_apply()

## Turns the applier off without removing it from the scene, restoring whatever
## materials the surfaces had before.
@export var enabled := true:
	set(value):
		enabled = value
		_apply()

## Materials taken from the surfaces before the first apply, so `enabled = false`
## can put them back. Keyed by the MeshInstance3D, each entry holding one
## material per surface (null where the surface had no override).
var _original_materials: Dictionary[MeshInstance3D, Array] = {}

func _ready() -> void:
	# The scene this one replaced has finished being torn down by now, so the
	# materials it left behind can be let go of (`_handed_out`).
	_sweep_handed_out()
	_apply()

	# Meshes that arrive after this point — a rat spawned into the level, a crew
	# member seated on the menu — would otherwise keep the material the importer
	# gave them, since `_apply` has already walked the tree by the time they get
	# here. Watching the whole tree and filtering is cheaper than it looks, and it
	# is the only hook that sees a node buried inside an instanced scene: the
	# per-child signals only fire for direct children.
	if not Engine.is_editor_hint():
		get_tree().node_added.connect(_on_node_added)


## Every material this applier has handed out, kept alive past its own death.
##
## It exists to silence four errors a scene change used to print, and the reason
## is worth writing down because the obvious fix is the wrong one. The materials
## `_apply_to` hands out are duplicates, and the references keeping one alive are
## the surface override and this node's own dictionary. A scene being torn down
## frees its nodes in no guaranteed order, so the applier can go before the
## meshes it dressed do — and the moment it does, the duplicate's last reference
## goes with it, leaving a `MeshInstance3D` pointing at a freed material for as
## long as the frame in flight takes to draw. The rendering server then says so,
## once per thing it wanted to ask:
##
##     material_casts_shadows: Parameter "material" is null.
##     material_is_animated: Parameter "material" is null.
##     material_get_instance_shader_parameters: Parameter "material" is null.
##     material_update_dependency: Parameter "material" is null.
##
## Putting the surfaces back on the way out does not fix it: writing overrides
## into meshes that are themselves being freed is the same race, one step over.
## What does fix it is refusing to be the one holding the last reference —
## the duplicates outlive every mesh that could still be drawn holding one.
##
## Held against the mesh it was put on, so the list can be swept: an entry whose
## mesh has been freed is one nothing can still be drawing, and the material goes
## with it. The sweep runs when an applier comes up rather than when one goes
## down — by then the previous scene's teardown is over, which is exactly the
## moment it is safe to let go. Without it this grows by every surface in every
## scene ever loaded, which over an evening of shifts is a real leak.
static var _handed_out: Array[Dictionary] = []

## Drops the materials whose meshes are gone. See `_handed_out`.
static func _sweep_handed_out() -> void:
	var kept: Array[Dictionary] = []
	for entry in _handed_out:
		if is_instance_valid(entry["mesh"]):
			kept.append(entry)
	_handed_out = kept

## Re-applies the material to the whole subtree. Call it after changing a
## surface's texture. Meshes added at runtime are picked up on their own.
func refresh() -> void:
	_apply()

## A node appeared somewhere in the tree. Ours to dress only if it is a mesh
## sitting under our parent with no nearer applier laying claim to it.
##
## An instanced scene arrives whole — its children are already in place when this
## fires — so an applier packed inside it is visible to `_answers_for` and wins
## the subtree, even though its own `_ready` has not run yet.
func _on_node_added(node: Node) -> void:
	if not enabled or material == null:
		return
	var mesh_instance := node as MeshInstance3D
	if mesh_instance == null or not _answers_for(mesh_instance):
		return
	_remember(mesh_instance)
	_apply_to(mesh_instance)

## Whether this applier is the one responsible for `mesh_instance`: it lies under
## our parent, and nothing between the two owns it first.
func _answers_for(mesh_instance: MeshInstance3D) -> bool:
	var root := get_parent()
	if root == null:
		return false

	var node: Node = mesh_instance
	while node != null and node != root:
		if _owned_by_another_applier(node):
			return false
		node = node.get_parent()

	return node == root

func _apply() -> void:
	if not is_inside_tree():
		return

	var root := get_parent()
	if root == null:
		return

	for mesh_instance in _collect_meshes(root):
		_remember(mesh_instance)
		if enabled and material != null:
			_apply_to(mesh_instance)
		else:
			_restore(mesh_instance)

## Every MeshInstance3D under `node`, minus the ones another applier answers for.
##
## An applier owns its parent's whole subtree, so finding one among a node's
## children means that node is spoken for and this applier keeps out of it —
## that is what lets a scene-wide applier coexist with the ones already sitting
## inside `rat.tscn` and `box_van.glb`, each keeping its own settings.
func _collect_meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []

	if node is MeshInstance3D:
		found.append(node as MeshInstance3D)

	for child in node.get_children():
		if _owned_by_another_applier(child):
			continue
		found.append_array(_collect_meshes(child))

	return found

## Whether `node` already has an applier of its own among its children.
func _owned_by_another_applier(node: Node) -> bool:
	for child in node.get_children():
		if child is PS1MaterialApplier and child != self:
			return true
	return false

func _apply_to(mesh_instance: MeshInstance3D) -> void:
	for surface in mesh_instance.get_surface_override_material_count():
		var texture := _albedo_of(mesh_instance, surface)
		var color := _albedo_color_of(mesh_instance, surface)

		# One material per surface: each carries its own texture and color, and a
		# model may well have a different pair per surface.
		var surface_material := material.duplicate() as ShaderMaterial
		if texture != null:
			surface_material.set_shader_parameter(ALBEDO_UNIFORM, texture)
		surface_material.set_shader_parameter(ALBEDO_COLOR_UNIFORM, color)
		surface_material.set_shader_parameter(UV_SCALE_UNIFORM, _uv_scale_of(mesh_instance, surface))

		mesh_instance.set_surface_override_material(surface, surface_material)
		# Held past this applier's own lifetime, so that a scene being torn down
		# cannot free the material out from under a mesh still being drawn
		# (`_handed_out`).
		_handed_out.append({"mesh": mesh_instance, "material": surface_material})

## The albedo texture a surface already uses, or null when it has none — plenty
## of low-poly models are painted by color alone.
func _albedo_of(mesh_instance: MeshInstance3D, surface: int) -> Texture2D:
	for source in _sources_of(mesh_instance, surface):
		if source is BaseMaterial3D:
			var texture := (source as BaseMaterial3D).albedo_texture
			if texture != null:
				return texture
		elif source is ShaderMaterial:
			var texture := (source as ShaderMaterial).get_shader_parameter(ALBEDO_UNIFORM) as Texture2D
			if texture != null:
				return texture

	return null

## The albedo color a surface already uses. White when the material carries no
## color of its own, which leaves the texture showing through untinted.
func _albedo_color_of(mesh_instance: MeshInstance3D, surface: int) -> Color:
	for source in _sources_of(mesh_instance, surface):
		if source is BaseMaterial3D:
			return (source as BaseMaterial3D).albedo_color
		elif source is ShaderMaterial:
			var color = (source as ShaderMaterial).get_shader_parameter(ALBEDO_COLOR_UNIFORM)
			if color != null:
				return color

	return Color.WHITE

## How many times a surface's texture repeats over its UVs. One by one for
## everything that arrives with its UVs already laid out, which is every
## imported model — only the untextured primitives built in the editor, a
## forty-metre floor plane among them, ask for more.
func _uv_scale_of(mesh_instance: MeshInstance3D, surface: int) -> Vector2:
	for source in _sources_of(mesh_instance, surface):
		if source is BaseMaterial3D:
			var scale := (source as BaseMaterial3D).uv1_scale
			return Vector2(scale.x, scale.y)
		elif source is ShaderMaterial:
			var scale = (source as ShaderMaterial).get_shader_parameter(UV_SCALE_UNIFORM)
			if scale != null:
				return scale

	return Vector2.ONE

## Where a surface's look can come from, best first: the override set on the
## instance, then the material baked into the mesh by the importer.
func _sources_of(mesh_instance: MeshInstance3D, surface: int) -> Array[Material]:
	return [
		mesh_instance.get_surface_override_material(surface),
		mesh_instance.mesh.surface_get_material(surface) if mesh_instance.mesh != null else null,
	]

func _remember(mesh_instance: MeshInstance3D) -> void:
	if _original_materials.has(mesh_instance):
		return

	var materials: Array[Material] = []
	for surface in mesh_instance.get_surface_override_material_count():
		materials.append(mesh_instance.get_surface_override_material(surface))
	_original_materials[mesh_instance] = materials

func _restore(mesh_instance: MeshInstance3D) -> void:
	var materials: Array = _original_materials.get(mesh_instance, [])
	for surface in mini(materials.size(), mesh_instance.get_surface_override_material_count()):
		mesh_instance.set_surface_override_material(surface, materials[surface])
