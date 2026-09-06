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
uniform sampler2D albedo: source_color, hint_default_white, filter_nearest_mipmap;

// Colour on top of the texture, as in `StandardMaterial3D`. It is what saves the
// low-poly models painted with a solid colour alone — the ones from kits like
// Kenney and Quaternius, with no texture at all: without it the whole object
// would come out white.
uniform vec4 albedo_color: source_color = vec4(1.0);

// How many times the texture repeats over the surface's UVs, as
// `StandardMaterial3D`'s `uv1_scale`. A `PlaneMesh` maps its whole surface to
// UV 0..1, so a forty-metre floor would stretch one photograph over forty
// metres without this; the applier leaves it at one, which is what every
// model with baked UVs wants.
uniform vec2 uv_scale = vec2(1.0);

// How coarse the vertex snap is, from zero (off entirely) to one. It is the
// wobble a PS1 has because it had no floating point in its transform unit, and
// the game does not use it: see `affine_strength` for the console this look
// actually aims at now. Left in because it is a look, not a mistake, and
// switching it back on is one number.
//
// **Zero really is off.** The grid it snaps to is `(1 - jitter) * viewport / 2`,
// so a jitter of zero is not a fine grid but still a grid — half a pixel at
// 640x360 — and geometry still crawls on it. Nothing but skipping the snap
// stops it, which is what `vertex()` does at zero.
uniform float jitter: hint_range(0.0, 1.0) = 0.0;

// The snapping grid, when it must not be read off the viewport.
//
// `jitter` alone asks for a grid *relative to the viewport it is drawn in* —
// `(1.0 - jitter) * min(VIEWPORT_SIZE) / 2.0` — which is right for the game and
// wrong for anything rendered in a `SubViewport` small enough to be a panel. A
// 44-pixel icon strip lands on a grid of 14, against the game's 156: eleven
// times coarser, and at that pitch a broom's every vertex collapses onto the
// same point and the model comes out a smear. The store's hand was the tell —
// four fingers snapped into one square.
//
// So a positive value here *is* the grid, whatever size the viewport happens to
// be, and the caller works it out from the resolution the look was tuned at.
// Zero, the default, leaves the viewport-relative rule alone, so every surface
// in the game is untouched by this and only the panels opt in.
uniform float jitter_grid = 0.0;

uniform bool jitter_z_coordinate = true;
uniform bool jitter_depth_independent = true;

// How much of the affine texture swim to keep, from zero (perspective correct,
// the texture stays nailed to the surface however the camera moves) to one (a
// PS1's full error, the texture sliding across every triangle).
//
// **Zero is the game's look, and it is the N64's rather than the PS1's.** Both
// consoles drew the same low-poly flat-shaded world, and the difference the eye
// actually reads is this one: the N64 interpolated texture coordinates with
// perspective correction, so its surfaces hold still. The PS1 did not, and its
// textures crawl — which on the van's lining, a metre from the player's face,
// stopped reading as period charm and started reading as the wall moving.
// Everything else about the look is unchanged: the flat shading, the nearest
// filtering, the 640x360 viewport, the untextured painted surfaces.
//
// In between is a real setting and not a switch, and it is worth knowing how.
// The UVs are scaled by `depth^strength` per vertex and divided by the same
// value per pixel; the divisor is interpolated with perspective correction, so
// each corner's UV ends up weighted by `depth^(strength - 1)`. At one those
// weights are flat, which is exactly the affine error; at zero they are
// `1/depth`, which is exactly correct sampling. The exponent is what makes the
// dial safe — mixing towards one linearly instead passes through zero at some
// depth in front of the camera, and the UVs blow up there.
uniform float affine_strength: hint_range(0.0, 1.0) = 0.0;
uniform float alpha_scissor: hint_range(0.0, 1.0) = 1.0;

// --- Recolouring the suit ---------------------------------------------------
//
// The overalls come out of Blender painted a fixed yellow, and `albedo_color`
// alone cannot repaint them: it multiplies, and multiplication can only ever
// darken. The suit's blue channel is already down at 77/255, so a full-strength
// blue from the palette lands at thirty percent of that and reads as black —
// which is why the tint had to be washed halfway to white to stay visible, and
// why every man came out pastel and hard to tell from the next.
//
// So the hue is *replaced* rather than multiplied. A pixel whose hue is close
// enough to the suit's yellow takes the requested hue and saturation and keeps
// its own value, which is where the fabric's shading and its folds live. A pixel
// outside that window — the cyan gloves, the dark boots, the face — is left
// alone, so recolouring the overalls never touches the parts that are the same
// on every man.
//
// `recolor_strength` at zero switches the whole thing off, which is what every
// other object in the scene runs at.
uniform vec3 recolor_target: source_color = vec3(1.0, 1.0, 1.0);
uniform float recolor_strength: hint_range(0.0, 1.0) = 0.0;
// The hue being replaced, as a 0-1 turn. The suit's yellow sits at 50.6 degrees.
uniform float recolor_hue: hint_range(0.0, 1.0) = 0.1406;
// How far from that hue a pixel may sit and still be treated as suit. Wide
// enough to hold the whole of the fabric including its shaded folds, narrow
// enough to leave the cyan gloves at 190 degrees untouched.
uniform float recolor_hue_range: hint_range(0.0, 0.5) = 0.09;
// Pixels this desaturated are grey rather than yellow — seams, scuffs, the dark
// of a deep fold — and grey has no hue worth matching on. Leaving them out
// keeps the recolour from tinting the dirt.
uniform float recolor_min_saturation: hint_range(0.0, 1.0) = 0.25;

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

// How much of a pixel is suit, from zero (leave it exactly as it is) to one
// (repaint it fully). It falls off towards the edge of the hue window rather
// than cutting at it, so the border between repainted fabric and untouched glove
// is a gradient and not a jagged line of stray yellow.
float suit_weight(vec3 hsv) {
	// Hue is a wheel: the distance from 0.98 to 0.02 is 0.04, not 0.96.
	float hue_distance = abs(hsv.x - recolor_hue);
	hue_distance = min(hue_distance, 1.0 - hue_distance);
	float in_hue = 1.0 - smoothstep(recolor_hue_range * 0.6, recolor_hue_range, hue_distance);
	float in_saturation = smoothstep(recolor_min_saturation * 0.5, recolor_min_saturation, hsv.y);
	return in_hue * in_saturation;
}

// The suit repainted in a requested colour. The pixel keeps its own value, which
// carries the shading, and takes the target's hue and saturation — so a fold
// that was dark yellow becomes dark blue rather than flat blue.
vec3 recolor(vec3 rgb) {
	vec3 hsv = rgb_to_hsv(rgb);
	float weight = suit_weight(hsv) * recolor_strength;
	if (weight <= 0.0) {
		return rgb;
	}
	vec3 target_hsv = rgb_to_hsv(recolor_target);
	// The pixel keeps its own saturation where that is the weaker of the two.
	// Taking the target's outright flattens the suit: a full-strength red from
	// the palette is saturation 1.0 everywhere, and a fold that was a paler
	// yellow than the fabric around it comes out exactly as red as the fabric,
	// so the creases stop reading. Scaling the pixel's own saturation towards
	// the target keeps the fabric's variation under the new colour.
	float painted_saturation = mix(hsv.y, target_hsv.y, 0.5) * target_hsv.y;
	vec3 painted = hsv_to_rgb(vec3(target_hsv.x, painted_saturation, hsv.z * target_hsv.z));
	return mix(rgb, painted, weight);
}

// What the UVs are scaled by in `vertex()` and divided by again in `fragment()`.
//
// It is carried as a varying rather than recomputed from `VERTEX.z` in the
// fragment, and that is load-bearing rather than an optimisation: a varying is
// interpolated with perspective correction, so the fragment divides by
// `interpolate(depth^strength)`. Recomputing `pow(VERTEX.z, strength)` there
// gives `interpolate(depth)^strength` instead, which is a different value
// everywhere except at the vertices — the two disagree by a bulge that reads as
// the wall bending, and at half strength that bulge is worse than the swim it
// was meant to halve.
varying float affine_divisor;

void vertex() {
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// Either dial can ask for the snap, and they ask for different grids: an
	// explicit `jitter_grid` is a panel pinning its own pitch, while `jitter` is
	// the viewport-relative wobble the game itself leaves off. Testing both is
	// what lets the game sit at `jitter = 0.0` without switching the store's
	// preview back to a grid eleven times too coarse.
	if (jitter > 0.0 || jitter_grid > 0.0) {
		float z_orig = VERTEX.z;
		// An explicit grid wins over the viewport-relative one. See `jitter_grid`.
		float i = jitter_grid > 0.0
			? jitter_grid
			: (1.0 - jitter) * min(VIEWPORT_SIZE.x, VIEWPORT_SIZE.y) / 2.0;

		if (jitter_depth_independent) {
			float w = (PROJECTION_MATRIX * vec4(VERTEX, 1.0)).w;
			VERTEX = round(VERTEX / w * i) / i * w;
		} else {
			VERTEX = round(VERTEX * i) / i;
		}

		if (!jitter_z_coordinate) {
			VERTEX.z = z_orig;
		}
	}

	// View space puts what is in front of the camera at negative Z, so the depth
	// is negated before the power — `pow` of a negative base is undefined — and
	// clamped off zero for anything sitting on the near plane.
	affine_divisor = pow(max(-VERTEX.z, 0.001), affine_strength);
	if (affine_strength > 0.0) {
		UV *= affine_divisor;
	}
}

void fragment() {
	vec2 uv = UV;
	
	if (affine_strength > 0.0) {
		uv /= affine_divisor;
	}
	
	vec4 color = texture(albedo, uv * uv_scale) * albedo_color;
	ALBEDO = recolor(color.rgb);
	ALPHA = color.a;
	// In 3.x this built-in was called just `ALPHA_SCISSOR`.
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
}
