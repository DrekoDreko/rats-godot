shader_type canvas_item;
render_mode unshaded;

// The CRT filter, drawn at the window's resolution — outside and above the
// 480x270 buffer.
//
// Being outside is not a detail. A scanline is a property of the *display*, not
// of the image: put this inside the low-resolution buffer and each scanline
// becomes a whole game pixel, which the upscale then blows up into a four-pixel
// black bar.
//
// The thing to keep in mind while tuning any of it: the reference look is a
// *sharp* image with artefacts on top, not a soft image. Parking Garage Rally
// Circuit's pixels stay hard and readable; what the filter adds is a faint
// modulation across bright areas and a colour fringe on high-contrast edges.
// Every layer here defaults low for that reason, and each is switched by its
// own uniform — a good share of players want none of it. `RetroFX.PRESETS`
// names the combinations.

// **`filter_nearest` is load-bearing.** The SubViewportContainer upscales the
// game buffer with nearest-neighbour precisely so the pixels stay square, and
// sampling that result linearly here throws it straight back away: every fetch
// blends across the seams between the fat pixels, and the whole image softens.
// A blurry retro filter is the single most common way this look is got wrong.
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;

uniform bool enabled = true;

// Size of the game buffer being displayed. The sideways effects are measured in
// *game* pixels rather than window pixels: a fringe should be a fraction of one
// chunky pixel whatever window the player has, and a window-pixel offset means
// an effect that quietly triples in strength when someone maximises.
uniform vec2 game_resolution = vec2(480.0, 270.0);

// --- Layer 1: scanlines -----------------------------------------------------
// Drawn per row of *game* pixels, not per window pixel. A real CRT's lines
// correspond to the image's lines, and locking them to the game grid keeps them
// stable instead of beating against the upscale ratio into a moiré.
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.08;

// --- Layer 2: chromatic aberration -----------------------------------------
// Composite video carried luma and chroma on one wire and the colour arrived
// slightly behind the brightness, showing as a coloured fringe on a
// high-contrast edge. In the reference this is visible on HUD text and on hard
// object borders and nowhere else, which is what a sub-pixel offset gives:
// inside a flat area all three channels sample the same pixel and no fringe can
// form.
uniform float aberration_strength : hint_range(0.0, 1.0) = 0.30;

// --- Layer 3: horizontal bleed ---------------------------------------------
// Limited chroma bandwidth smeared colour sideways, never vertically. Kept well
// under one game pixel: past that it stops being a bleed and becomes a blur,
// and the pixel grid dissolves.
uniform float bleed_strength : hint_range(0.0, 1.0) = 0.15;

// --- Layer 4: vignette ------------------------------------------------------
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.12;

// --- Layer 5: screen curvature (optional) -----------------------------------
uniform float curvature : hint_range(0.0, 0.5) = 0.0;

// Bends UVs outwards from the centre, as a curved glass tube would. Off by
// default: it costs a little of the image at the edges, and on a modern flat
// panel plenty of people read it as a distraction rather than as nostalgia.
vec2 curve_uv(vec2 uv, float amount) {
	if (amount <= 0.0) {
		return uv;
	}
	vec2 centered = uv * 2.0 - 1.0;
	// Each axis bows by the square of the other, so the corners pull in more
	// than the edge midpoints — the shape a real tube has.
	centered.x *= 1.0 + pow(abs(centered.y) * amount, 2.0);
	centered.y *= 1.0 + pow(abs(centered.x) * amount, 2.0);
	return centered * 0.5 + 0.5;
}

void fragment() {
	if (!enabled) {
		COLOR = texture(screen_texture, SCREEN_UV);
	} else {
		vec2 uv = curve_uv(SCREEN_UV, curvature);

		// Curvature can push a sample past the edge of the buffer. Painting
		// those black is what gives the tube its rounded corners; letting them
		// clamp instead would smear the border pixels outwards.
		if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
			COLOR = vec4(0.0, 0.0, 0.0, 1.0);
		} else {
			// One game pixel, in UV. Everything sideways is measured in these.
			float game_texel = 1.0 / game_resolution.x;

			// Layers 2 and 3 both sample sideways, so they are gathered
			// together: red and blue are fetched offset in opposite directions
			// (aberration) while each channel is averaged with a neighbour
			// (bleed). Both offsets stay a fraction of a game pixel, so a flat
			// area samples the same pixel three times and comes out untouched
			// while an edge picks up its fringe.
			float ab = aberration_strength * game_texel * 0.6;
			float bl = bleed_strength * game_texel * 0.5;

			vec3 c;
			c.r = mix(
				texture(screen_texture, uv + vec2(ab, 0.0)).r,
				texture(screen_texture, uv + vec2(ab + bl, 0.0)).r,
				0.5);
			c.g = texture(screen_texture, uv).g;
			c.b = mix(
				texture(screen_texture, uv - vec2(ab, 0.0)).b,
				texture(screen_texture, uv - vec2(ab + bl, 0.0)).b,
				0.5);

			// Layer 1. Driven by the game row this window pixel falls on, so the
			// line pitch follows the image rather than the monitor.
			if (scanline_strength > 0.0) {
				float game_row = uv.y * game_resolution.y;
				// Every other game row dimmed, which is what a CRT's interlace
				// reads as once the image is this coarse.
				float line = 0.5 - 0.5 * cos(game_row * TAU);
				// Scaled by brightness: a real tube's dark areas have no beam to
				// modulate, so scanlines show in the highlights and vanish in
				// the shadows. Without this the black areas gain grey stripes,
				// which is most of what made the first pass unreadable.
				float luma = dot(c, vec3(0.299, 0.587, 0.114));
				c *= 1.0 - scanline_strength * line * luma;
			}

			// Layer 4.
			if (vignette_strength > 0.0) {
				vec2 v = uv * (1.0 - uv);
				float amount = clamp(v.x * v.y * 16.0, 0.0, 1.0);
				c *= mix(1.0, pow(amount, 0.2), vignette_strength);
			}

			COLOR = vec4(c, 1.0);
		}
	}
}
