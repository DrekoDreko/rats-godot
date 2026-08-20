shader_type spatial;
// `specular_phong` existed when this shader was written, but it left Godot in
// 4.4: today only `specular_schlick_ggx` (the default) and `specular_disabled`
// remain.
//
// `cull_disabled` is here for the things the player walks *inside*. A model like
// the van is a single shell with its faces looking outwards, so from the cargo
// bay the walls are all back faces and the default culling throws them away: the
// van turns to glass the moment you step into it. Drawing both sides costs a
// little overdraw on geometry this simple and nothing at all on closed shapes,
// which is what everything else in the map is. Lighting on the inside face comes
// out of the outward normal — `vertex_lighting` settles it before anyone knows
// which side is being drawn — and that is exactly the kind of wrong this look was
// after anyway.
render_mode vertex_lighting, skip_vertex_transform, diffuse_lambert_wrap, cull_disabled;

// The hints changed names since 3.x too: `hint_black` became
// `hint_default_black`, and the old `hint_black_albedo` split into
// `source_color` (the colour space conversion) plus the texture default.
// Albedo falls back to white when nobody fills the uniform, otherwise every
// object without a texture would come out black.
uniform sampler2D albedo: source_color, hint_default_white;
uniform sampler2D specular: hint_default_black;
uniform sampler2D emission: source_color, hint_default_black;

// Colour on top of the texture, as in `StandardMaterial3D`. It is what saves the
// low-poly models painted with a solid colour alone — the ones from kits like
// Kenney and Quaternius, with no texture at all: without it the whole object
// would come out white.
uniform vec4 albedo_color: source_color = vec4(1.0);

uniform float jitter: hint_range(0.0, 1.0) = 0.5;
uniform bool jitter_z_coordinate = true;
uniform bool jitter_depth_independent = true;
uniform bool affine_texture_mapping = true;
uniform float alpha_scissor: hint_range(0.0, 1.0) = 1.0;

void vertex() {
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	float z_orig = VERTEX.z;
	float i = (1.0 - jitter) * min(VIEWPORT_SIZE.x, VIEWPORT_SIZE.y) / 2.0;
	
	if (jitter_depth_independent) {
		float w = (PROJECTION_MATRIX * vec4(VERTEX, 1.0)).w;
		VERTEX = round(VERTEX / w * i) / i * w;
	} else {
		VERTEX = round(VERTEX * i) / i;
	}
	
	if (!jitter_z_coordinate) {
		VERTEX.z = z_orig;
	}

	if (affine_texture_mapping) {
		UV *= VERTEX.z;
	}
}

void fragment() {
	vec2 uv = UV;
	
	if (affine_texture_mapping) {
		uv /= VERTEX.z;
	}
	
	vec4 color = texture(albedo, uv) * albedo_color;
	ALBEDO = color.rgb;
	ALPHA = color.a;
	// In 3.x this built-in was called just `ALPHA_SCISSOR`.
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
	EMISSION = texture(emission, uv).rgb;
	SPECULAR = texture(specular, uv).r;
}
