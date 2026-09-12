shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

void fragment() {
	vec3 scene = texture(screen_texture, SCREEN_UV).rgb;
	float gray = dot(scene, vec3(0.2126, 0.7152, 0.0722));
	COLOR = vec4(vec3(gray), 1.0);
}
