shader_type spatial;
// `unshaded` is what makes this look like a PS1 game rather than a modern one:
// the console had no per-pixel lighting and no shadow maps, so surfaces were lit
// once — baked into the texture or the vertex colour — and drawn flat. Skipping
// the light pass entirely means no directional shading, no shadows and no SSAO
// can ever touch these surfaces, whatever the scene puts around them.
//
// `cull_disabled` is here for the things the player walks *inside*. A model like
// the van is a single shell with its faces looking outwards, so from the cargo
// bay the walls are all back faces and the default culling throws them away: the
// van turns to glass the moment you step into it. Drawing both sides costs a
// little overdraw on geometry this simple and nothing at all on closed shapes,
// which is what everything else in the map is.
render_mode unshaded, skip_vertex_transform, cull_disabled;

// The hints changed names since 3.x too: `hint_black` became
// `hint_default_black`, and the old `hint_black_albedo` split into
// `source_color` (the colour space conversion) plus the texture default.
// Albedo falls back to white when nobody fills the uniform, otherwise every
// object without a texture would come out black.
//
// `filter_nearest` is what makes the textures read as pixels rather than as a
// blur, and it has to be said here. A sampler with no filter hint gets Godot's
// default of `filter_linear_mipmap`, and the applier builds this material from
// nothing but the imported one's texture and colour — so a "Nearest" chosen on
// the import or a "Closest" chosen in Blender never reaches the surface. This
// line is the only place in the chain that decides it.
uniform sampler2D albedo: source_color, hint_default_white, filter_nearest;

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
}
