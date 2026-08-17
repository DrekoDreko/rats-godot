shader_type spatial;
// `specular_phong` existia quando este shader foi escrito, mas saiu do Godot na
// 4.4: hoje só restam `specular_schlick_ggx` (o padrão) e `specular_disabled`.
render_mode vertex_lighting, skip_vertex_transform, diffuse_lambert_wrap;

// Os hints também mudaram de nome desde a 3.x: `hint_black` virou
// `hint_default_black`, e o antigo `hint_black_albedo` se desdobrou em
// `source_color` (a conversão de espaço de cor) mais o padrão da textura.
// O albedo cai para branco quando ninguém preenche o uniform, senão todo objeto
// sem textura ficaria preto.
uniform sampler2D albedo: source_color, hint_default_white;
uniform sampler2D specular: hint_default_black;
uniform sampler2D emission: source_color, hint_default_black;

// Cor por cima da textura, como no `StandardMaterial3D`. É o que salva os
// modelos low-poly pintados só com cor sólida — os de kits como Kenney e
// Quaternius, sem textura nenhuma: sem isso o objeto todo sairia branco.
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
	
	vec4 cor = texture(albedo, uv) * albedo_color;
	ALBEDO = cor.rgb;
	ALPHA = cor.a;
	// Na 3.x este built-in se chamava só `ALPHA_SCISSOR`.
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
	EMISSION = texture(emission, uv).rgb;
	SPECULAR = texture(specular, uv).r;
}