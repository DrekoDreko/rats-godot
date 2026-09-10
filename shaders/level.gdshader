shader_type spatial;

// Level geometry: walls, floors, ceilings, the van's shell, the house.
//
// `shadows_disabled` and `specular_disabled` are not optimisations, they are the
// look. The scene is lit by a near-white ambient and the point lights only add
// warm spots on top; a real shadow or a specular highlight would immediately
// read as a modern renderer.
//
// `cull_disabled` is here for the shells the player walks *inside* — the van is
// a single skin with its faces looking outwards, so from the cargo bay every
// wall is a back face and default culling would turn the van to glass.
render_mode blend_mix,
	depth_prepass_alpha,
	shadows_disabled,
	specular_disabled,
	cull_disabled;

#include "res://shaders/common.gdshaderinc"

uniform sampler2D albedo : source_color, hint_default_white, filter_nearest;
// Tint over the texture, as `StandardMaterial3D.albedo_color`. Models exported
// without a texture carry their whole look in this colour alone.
uniform vec4 albedo_color : source_color = vec4(1.0);
// How many times the texture repeats over the surface's UVs. A `PlaneMesh` maps
// its whole surface to UV 0..1, so a forty-metre floor would stretch a single
// tile across forty metres without this.
uniform vec2 uv_scale = vec2(1.0);

void vertex()
{
	vec4 snapped_position = snap_to_position(VIEWPORT_SIZE, PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	POSITION = snapped_position;
}

void fragment()
{
	vec4 color_base = COLOR * albedo_color;
	vec4 texture_color = texture(albedo, UV * uv_scale);
	ALBEDO = (color_base * texture_color).rgb;
	ALPHA = texture_color.a * color_base.a;
}

// ESSENTIAL: no NdotL. The light is applied equally to every face, whichever way
// it points. This is what kills directional shading and produces the flat retro
// look — a lambert term here would immediately make the scene read as modern.
void light()
{
	DIFFUSE_LIGHT += LIGHT_COLOR * 1.0 * ATTENUATION;
}
