// Shared vertex snapping for the whole retro pipeline.
//
// The PS1 had no floating point in its transform unit: vertices were rounded to
// an integer grid in screen space before rasterisation, and the whole image
// crawls because of it. `snap_to_position` reproduces exactly that, and every
// spatial shader in the project routes its POSITION through it so that the
// geometry all wobbles on the same grid.
//
// The grid is driven by the `vertex_resolution` shader global (project settings,
// [shader_globals]) rather than by a per-material uniform, so the whole game can
// be retuned from one number.

global uniform float vertex_resolution;

vec4 snap_to_position(vec2 resolution, vec4 base_position)
{
	vec4 snapped_position = base_position;
	// Perspective divide by hand: the snap has to happen in normalised device
	// coordinates, which is where the console's own grid lived.
	snapped_position.xyz = base_position.xyz / base_position.w;

	vec2 snap_resulotion = (vec2(resolution) * vertex_resolution);
	snapped_position.x = floor(snap_resulotion.x * snapped_position.x) / snap_resulotion.x;
	snapped_position.y = floor(snap_resulotion.y * snapped_position.y) / snap_resulotion.y;

	// Back into clip space, so the rasteriser can do its own divide as usual.
	snapped_position.xyz *= base_position.w;
	return snapped_position;
}
