// The outline drawn around a rat the player has in his sights.
//
// It is an *overlay* material and not an override, which is what lets it exist
// at all: the animal's own surfaces already carry the PS1 shader
// (`scripts/ps1_material_applier.gd` writes them as surface overrides), and an
// overlay is the one slot left that draws over the top of them without taking
// anything away.
//
// The trick is the ordinary one: the hull is grown along its own normals and
// drawn inside-out, so what survives is the sliver of grown hull sticking out
// past the real silhouette. Everything that makes it read as a line rather than
// as a swollen rat is in `cull_front` and `unshaded`.
shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled, depth_draw_never;

// How far the hull is pushed out, in **metres of the world**.
//
// It has to be converted before it can be used, and that is the whole of what
// went wrong the first time this was written. The rat's mesh arrives from the
// FBX at a hundredth of its drawn size and is scaled back up by the nodes above
// it (100 on `Rat`, 0.18 on `Mesh`: eighteen times over), so the raw hull this
// shader runs on is about 0.028 units tall. A thickness written straight into
// `VERTEX` is in *those* units — two hundredths of it swallowed the animal whole
// and drew a ball.
//
// So the scale is read back out of the model matrix and divided out below,
// which makes this number mean what it says: 0.004 is four millimetres of world,
// on a rat about half a metre long.
//
// It stays in world metres rather than screen pixels on purpose. A rat two rooms
// away is not a rat the player can grab, so an outline that held its thickness
// on screen at any distance would be advertising a target the click cannot
// reach — this one thins out with distance, which is the honest reading.
uniform float thickness : hint_range(0.0, 0.05) = 0.004;
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Brightness the line pulses between, and how many times a second it does it.
// The pulse is what separates "you may grab this" from a colour the animal
// might simply have been painted.
uniform float pulse_min : hint_range(0.0, 1.0) = 0.65;
uniform float pulse_speed = 4.0;

void vertex() {
	// The scale the nodes above this mesh are about to apply to it, taken off
	// the model matrix a column at a time. Dividing it out is what lets
	// `thickness` be a number in world metres: the line comes out the same
	// width whether the animal is drawn at eighteen times its mesh size on the
	// floor or shrunk again in a hand (`rat.gd: FIRST_PERSON_SCALE`).
	vec3 scale = vec3(
		length(MODEL_MATRIX[0].xyz),
		length(MODEL_MATRIX[1].xyz),
		length(MODEL_MATRIX[2].xyz)
	);
	// A degenerate scale would divide by zero and throw the hull to infinity.
	scale = max(scale, vec3(0.0001));

	// Normalised because a skinned normal does not arrive unit-length, and an
	// un-normalised one would make the line thicker wherever the mesh happens
	// to be denser.
	vec3 direction = normalize(NORMAL);
	VERTEX += direction * thickness / scale;
}

void fragment() {
	float pulse = mix(pulse_min, 1.0, 0.5 + 0.5 * sin(TIME * pulse_speed));
	ALBEDO = outline_color.rgb * pulse;
	ALPHA = outline_color.a;
}
