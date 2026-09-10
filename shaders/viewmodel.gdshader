shader_type spatial;

// First-person viewmodel: the hands, the bat, the broom.
//
// It renders with a projection matrix of its own, which is the standard trick
// for held items — the world wants a wide FOV so the player can see the room,
// and a wide FOV makes anything a few centimetres from the camera look
// grotesquely stretched. A narrower FOV here draws the hands at a believable
// shape whatever the world is set to.
render_mode depth_draw_opaque,
	cull_disabled,
	diffuse_lambert,
	shadows_disabled,
	specular_disabled;

#include "res://shaders/common.gdshaderinc"

uniform sampler2D albedo : source_color, hint_default_white, filter_nearest;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float alpha_scissor : hint_range(0.0, 1.0) = 1.0;

uniform float fov : hint_range(20, 120) = 40;
// Pushes the model towards the camera in the depth buffer, so an arm swung at a
// wall does not clip through it.
uniform float depth : hint_range(0, 5) = 0.0;

const float M_PI = 3.14159265359;

void vertex() {
	float scale = 1.0 / tan(fov * 0.5 * M_PI / 180.0);
	PROJECTION_MATRIX[0][0] = scale / (VIEWPORT_SIZE.x / VIEWPORT_SIZE.y);
	PROJECTION_MATRIX[1][1] = -scale;
	POSITION = snap_to_position(VIEWPORT_SIZE, PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	// Pinned in front of everything the world draws.
	POSITION.z = 0.1;
}

void fragment() {
	vec4 texture_color = texture(albedo, UV);
	vec4 combined = COLOR * albedo_color * texture_color;
	ALBEDO = combined.rgb;
	ALPHA = combined.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
	DEPTH = (FRAGCOORD.z + depth) * 0.7;
}

// See `level.gdshader`: no NdotL. The viewmodel sits lowest of the three so the
// hands never wash out against the room behind them.
void light()
{
	DIFFUSE_LIGHT += LIGHT_COLOR * 0.5 * ATTENUATION;
}
