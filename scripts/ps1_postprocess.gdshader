// Fullscreen post-process that crushes the framebuffer down to a PS1-era colour
// depth, dithering the result to hide the banding that the crush would show.
//
// It is the screen-space half of the PS1 look: `ps1.gdshader` handles the
// per-mesh half (vertex jitter and affine texture mapping). The two are meant to
// run together and never touch the same pass, so neither replaces the other.
shader_type spatial;
render_mode unshaded, shadows_disabled, depth_test_disabled, depth_draw_never;

/// Bits kept per colour channel. The PlayStation output 5 bits per channel.
uniform int color_depth : hint_range(1, 8) = 5;

/// Whether to dither, trading colour banding for a 4x4 ordered pattern.
uniform bool dithering = true;

/// Size in pixels of each sampled block, chunking the screen the way the low
/// PS1 framebuffer resolution did.
uniform int resolution_scale : hint_range(1, 16) = 4;

/// The frame rendered so far, which this pass reads back and rewrites.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

int dithering_pattern(ivec2 fragcoord) {
	const int pattern[] = {
		-4, +0, -3, +1, 
		+2, -2, +3, -1, 
		-3, +1, -4, +0, 
		+3, -1, +2, -2
	};
	
	int x = fragcoord.x % 4;
	int y = fragcoord.y % 4;
	
	return pattern[y * 4 + x];
}

// Stretches the mesh over the whole screen, whatever the mesh actually is and
// wherever the node sits. The three corners are written straight in clipped
// space, so no camera, transform or vertex position of the source mesh has any
// say in where this lands — the pass covers the viewport and nothing else.
//
// It wants a mesh of at least 3 vertices; a PlaneMesh or QuadMesh does.
void vertex() {
	// A triangle twice the size of the screen. Cheaper than two triangles for a
	// quad, and it leaves no seam down the diagonal.
	vec2 corner = vec2(
		float((VERTEX_ID << 1) & 2),
		float(VERTEX_ID & 2)
	);
	POSITION = vec4(corner * 2.0 - 1.0, 1.0, 1.0);
}

void fragment() {
	ivec2 uv = ivec2(FRAGCOORD.xy / float(resolution_scale));

	// Snapping the sample up to the block grid can land past the last texel on
	// the right and bottom edges, where texelFetch is undefined and reads white
	// on some drivers. Clamp it back inside the buffer.
	ivec2 last_texel = textureSize(screen_texture, 0) - ivec2(1);
	ivec2 texel = clamp(uv * resolution_scale, ivec2(0), last_texel);
	vec3 color = texelFetch(screen_texture, texel, 0).rgb;

	// The screen buffer is HDR, so a bright pixel can arrive above 1.0 and NaN
	// can arrive too. Both survive the cast to int as garbage that the shift
	// below turns into white, so pin the range down first.
	color = clamp(color, vec3(0.0), vec3(1.0));

	// Convert from [0.0, 1.0] range to [0, 255] range
	ivec3 c = ivec3(round(color * 255.0));
	
	// Apply the dithering pattern
	if (dithering) {
		c += ivec3(dithering_pattern(uv));
	}
	
	// Dithering pushes values past the byte range, and a negative one would
	// shift into garbage, so pull them back before truncating.
	c = clamp(c, ivec3(0), ivec3(255));

	// Truncate from 8 bits to color_depth bits
	c >>= (8 - color_depth);

	// Convert back to [0.0, 1.0] range. The largest value that survives the
	// truncation is the divisor, so white stays white.
	ALBEDO = vec3(c) / float((1 << color_depth) - 1);
}