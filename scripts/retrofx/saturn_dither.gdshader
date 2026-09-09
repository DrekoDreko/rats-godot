shader_type canvas_item;
render_mode unshaded;

// Colour quantisation with an ordered Bayer dither, drawn as the last thing
// inside the 480x270 buffer.
//
// Where it sits in the pipeline is the whole trick. The dither cell has to be
// one *game* pixel, so the checkerboard survives the nearest-neighbour upscale
// as a chunky 4x4 pattern of fat pixels rather than a fine grain the eye reads
// as noise. Run this after the upscale instead and every dot lands on a screen
// pixel: at 1080p that is a quarter the size it should be, and the effect stops
// reading as a Saturn and starts reading as a dirty monitor.
//
// How to check it is right: count the pixels of one dot. In a 1920x1080 window
// showing a 480x270 buffer, one game pixel is four screen pixels across, so a
// single dot of the checkerboard must measure 4x4 screen pixels. Fewer means
// this is running in the wrong buffer.
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;

// The classic 4x4 ordered Bayer matrix. Every value 0..15 appears once, and
// they are arranged so that as a threshold rises, the pixels that switch are
// maximally spread out — which is what makes the pattern read as an even
// texture instead of as clumps.
//
// It is deliberately not a noise texture. Noise gives a different pattern every
// frame or every position, which crawls under motion and destroys the illusion
// of a fixed palette; Bayer is deterministic and locked to the pixel grid, so a
// static surface dithers to a stable, still checkerboard.
const float bayer[16] = float[](
	 0.0,  8.0,  2.0, 10.0,
	12.0,  4.0, 14.0,  6.0,
	 3.0, 11.0,  1.0,  9.0,
	15.0,  7.0, 13.0,  5.0
);

// Levels per channel. 32 is 5 bits, the Saturn's colour depth.
uniform float levels = 32.0;
uniform float dither_strength : hint_range(0.0, 2.0) = 1.0;
uniform bool enabled = true;

void fragment() {
	vec3 c = texture(screen_texture, SCREEN_UV).rgb;

	if (enabled) {
		ivec2 p = ivec2(mod(FRAGCOORD.xy, 4.0));
		float t = ((bayer[p.y * 4 + p.x] / 16.0) - 0.5) * dither_strength;
		// Quantising with the threshold added is what turns banding into a
		// checkerboard: two neighbouring pixels holding the same colour get
		// different thresholds, so one rounds up and the other rounds down, and
		// the pair averages out to a value the palette does not contain.
		//
		// This only ever shows where there is a gradient to work on. A wall of
		// one flat colour lands every pixel on the same level whatever the
		// threshold, and comes out clean — which is correct, and why the
		// lighting and the fog had to exist before this shader was worth
		// writing. A flat wall covered in dots would mean something upstream is
		// adding noise.
		c = floor(c * levels + t) / (levels - 1.0);
	}

	COLOR = vec4(c, 1.0);
}
