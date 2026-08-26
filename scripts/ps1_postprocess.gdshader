// Fullscreen post-process that crushes the framebuffer down to a PS1-era colour
// depth, dithering the result to hide the banding that the crush would show.
//
// It is the screen-space half of the PS1 look: `ps1.gdshader` handles the
// per-mesh half (vertex jitter and affine texture mapping). The two are meant to
// run together and never touch the same pass, so neither replaces the other.
//
// **It does not pixelate.** That job belongs to the viewport: the project is set
// to `stretch/mode="viewport"`, so the whole game — the HUD included, which no
// 3D pass can reach — renders at 960x540 and is scaled up to the window with
// nearest filtering. The chunky pixels come from that upscale and from nothing
// else. This pass once had a `resolution_scale` that sampled the buffer in
// blocks, and running it on top of an already-small viewport pixelated twice:
// blocks of blocks, with the 4x4 dither smeared across them. One source of
// pixel size is the whole point, so the block sampling is gone and every texel
// here is read where it sits.
shader_type spatial;
render_mode unshaded, shadows_disabled, depth_test_disabled, depth_draw_never;

/// Bits kept per colour channel. The PlayStation output 5 bits per channel.
uniform int color_depth : hint_range(1, 8) = 5;

/// Whether to dither, trading colour banding for a 4x4 ordered pattern.
uniform bool dithering = true;

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
	// One texel in, one texel out. The viewport is already the size the look
	// wants, so there is no block grid to snap to and no edge case of snapping
	// past the last texel the way sampling in blocks had.
	ivec2 texel = ivec2(FRAGCOORD.xy);
	vec3 color = texelFetch(screen_texture, texel, 0).rgb;

	// The screen buffer is HDR, so a bright pixel can arrive above 1.0 and NaN
	// can arrive too. Both survive the cast to int as garbage that the shift
	// below turns into white, so pin the range down first.
	color = clamp(color, vec3(0.0), vec3(1.0));

	// Convert from [0.0, 1.0] range to [0, 255] range
	ivec3 c = ivec3(round(color * 255.0));
	
	// Apply the dithering pattern
	if (dithering) {
		c += ivec3(dithering_pattern(texel));
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
