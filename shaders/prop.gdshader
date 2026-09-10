shader_type spatial;

// Props, pickups, rats and anything standing in the level rather than being the
// level. Identical to `level.gdshader` except for the light factor: props are
// knocked down to 0.7 so they sit slightly under the geometry around them and
// read as objects in the room rather than as part of the wall.
render_mode blend_mix,
	depth_prepass_alpha,
	shadows_disabled,
	specular_disabled,
	cull_disabled;

#include "res://shaders/common.gdshaderinc"

uniform sampler2D albedo : source_color, hint_default_white, filter_nearest;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec2 uv_scale = vec2(1.0);
uniform float alpha_scissor : hint_range(0.0, 1.0) = 1.0;

// --- Recolouring the crew's overalls ----------------------------------------
//
// The overalls come out of Blender painted a fixed yellow, and a multiply alone
// cannot repaint them: multiplication can only darken, and the suit's blue
// channel is already low enough that a full-strength blue lands at black.
//
// So the hue is *replaced* rather than multiplied. A pixel whose hue is close to
// the suit's yellow takes the requested hue and keeps its own value, which is
// where the fabric's folds live; a pixel outside that window — the gloves, the
// boots, the face — is left alone.
uniform vec3 recolor_target : source_color = vec3(1.0, 1.0, 1.0);
uniform float recolor_strength : hint_range(0.0, 1.0) = 0.0;
// The hue being replaced, as a 0-1 turn. The suit's yellow sits at 50.6 degrees.
uniform float recolor_hue : hint_range(0.0, 1.0) = 0.1406;
// How far from that hue a pixel may sit and still count as suit. Wide enough for
// the shaded folds, narrow enough to leave the cyan gloves at 190 degrees alone.
uniform float recolor_hue_range : hint_range(0.0, 0.5) = 0.09;
// Pixels this desaturated are grey rather than yellow — seams, scuffs, the dark
// of a deep fold — and grey has no hue worth matching on.
uniform float recolor_min_saturation : hint_range(0.0, 1.0) = 0.25;

vec3 rgb_to_hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

// How much of a pixel is suit. It falls off towards the edge of the hue window
// rather than cutting at it, so the border between repainted fabric and
// untouched glove is a gradient and not a jagged line of stray yellow.
float suit_weight(vec3 hsv) {
	// Hue is a wheel: the distance from 0.98 to 0.02 is 0.04, not 0.96.
	float hue_distance = abs(hsv.x - recolor_hue);
	hue_distance = min(hue_distance, 1.0 - hue_distance);
	float in_hue = 1.0 - smoothstep(recolor_hue_range * 0.6, recolor_hue_range, hue_distance);
	float in_saturation = smoothstep(recolor_min_saturation * 0.5, recolor_min_saturation, hsv.y);
	return in_hue * in_saturation;
}

vec3 recolor(vec3 rgb) {
	vec3 hsv = rgb_to_hsv(rgb);
	float weight = suit_weight(hsv) * recolor_strength;
	if (weight <= 0.0) {
		return rgb;
	}
	vec3 target_hsv = rgb_to_hsv(recolor_target);
	// The pixel keeps its own saturation where that is the weaker of the two:
	// taking the target's outright flattens the suit, and the creases stop
	// reading.
	float painted_saturation = mix(hsv.y, target_hsv.y, 0.5) * target_hsv.y;
	vec3 painted = hsv_to_rgb(vec3(target_hsv.x, painted_saturation, hsv.z * target_hsv.z));
	return mix(rgb, painted, weight);
}

void vertex()
{
	vec4 snapped_position = snap_to_position(VIEWPORT_SIZE, PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	POSITION = snapped_position;
}

void fragment()
{
	vec4 color_base = COLOR * albedo_color;
	vec4 texture_color = texture(albedo, UV * uv_scale);
	vec4 combined = color_base * texture_color;
	ALBEDO = recolor(combined.rgb);
	ALPHA = combined.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
}

// See `level.gdshader`: no NdotL, only knocked down so props sit under the
// geometry around them.
void light()
{
	DIFFUSE_LIGHT += LIGHT_COLOR * 0.7 * ATTENUATION;
}
