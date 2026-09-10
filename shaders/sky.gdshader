shader_type sky;

// A three-band vertical gradient, which is all the sky this look needs.
//
// With `fog_sky_affect = 0.0` on the environment the sky stays clean while the
// geometry disappears into black fog — so the horizon reads as distance rather
// than as a wall, and the sky is the only thing in the frame that is not being
// eaten by the dark.

uniform vec3 color_top : source_color;
uniform vec3 color_horizon : source_color;
uniform vec3 color_bottom : source_color;
uniform float exponent_factor_top : hint_range(0, 100) = 1.0;
uniform float exponent_factor_bottom : hint_range(0, 100) = 1.0;
uniform float intensity_amp : hint_range(0, 1) = 1.0;

void sky() {
	float p = EYEDIR.y;
	float p1 = 1.0 - pow(min(1.0, 1.0 - p), exponent_factor_top);
	float p3 = 1.0 - pow(min(1.0, 1.0 + p), exponent_factor_bottom);
	float p2 = 1.0 - p1 - p3;

	COLOR += (color_top * p1 + (color_horizon * p2) * 0.7 + color_bottom * p3) * intensity_amp;
}
