# Prompt: replicar o estilo visual do CRUEL (Godot 4.x, Forward+)

Cole o texto abaixo no outro projeto.

---

Quero replicar o estilo visual de um FPS retro tipo PS1/boomer-shooter (referência: CRUEL).
Godot 4.x, renderer **Forward+**. Siga estas especificações exatamente — os valores foram
extraídos de um projeto real e a interação entre eles é o que produz o visual.

## PRINCÍPIO CENTRAL — leia antes de tudo

**A cena NÃO é iluminada por luzes.** É iluminada por *ambient light quase branca*, e as
luzes pontuais só adicionam pontos quentes decorativos por cima. O "escuro" da cena vem de
**fog preto na distância**, não de ausência de luz.

Se você tentar iluminar com luzes de verdade, vai ficar escuro e errado. A ordem é:
1. ambient alta e chapada → base clara uniforme
2. luzes pontuais sem sombra → variação de cor/calor local
3. fog preto → escuridão espacial
4. adjustment brightness 1.4 → levanta tudo no final

## 1. Project Settings

```ini
[display]
window/size/viewport_width=640
window/size/viewport_height=360
window/stretch/mode="viewport"
window/stretch/aspect="keep_height"
; janela real 1920x1080 -> upscale nearest de 640x360

[rendering]
textures/canvas_textures/default_texture_filter=0      ; Nearest
textures/default_filters/anisotropic_filtering_level=0
shading/overrides/force_lambert_over_burley=true
lights_and_shadows/directional_shadow/soft_shadow_filter_quality=0
lights_and_shadows/positional_shadow/soft_shadow_filter_quality=0
environment/defaults/default_clear_color=Color(0.151276, 0.151276, 0.151276, 1)
occlusion_culling/use_occlusion_culling=true

[shader_globals]
vertex_resolution={"type":"float","value":0.3}
```

Importação de TODAS as texturas de nível/props:
`compress/mode=0` (lossless), `mipmaps/generate=false`, `detect_3d/compress_to=0`.
Texturas em resolução baixa (128–512px).

## 2. WorldEnvironment — copie estes valores

```ini
[sub_resource type="Environment"]
background_mode = 2                 ; Sky
ambient_light_source = 2            ; AMBIENT_SOURCE_COLOR — NÃO use Sky nem Disabled
ambient_light_color = Color(0.873298, 0.873298, 0.873298, 1)
ambient_light_energy = 1.1
reflected_light_source = 1          ; disabled
tonemap_mode = 2                    ; FILMIC
tonemap_white = 2.0

fog_enabled = true
fog_light_color = Color(0, 0, 0, 1) ; PRETO — é isto que cria a escuridão
fog_density = 0.03
fog_sky_affect = 0.0
fog_depth_curve = 0.3
fog_depth_begin = 20.0
fog_depth_end = 50.0
volumetric_fog_density = 0.0

adjustment_enabled = true
adjustment_brightness = 1.4         ; +40% no final — não omita
adjustment_contrast = 1.02
adjustment_saturation = 1.2
```

Sem SSAO, sem SSR, sem SDFGI, sem glow, sem CameraAttributes/DoF.

## 3. Snapping de vértice (jitter PS1)

`res://shaders/common.gdshaderinc`:
```glsl
global uniform float vertex_resolution;

vec4 snap_to_position(vec2 resolution, vec4 base_position)
{
	vec4 snapped_position = base_position;
	snapped_position.xyz = base_position.xyz / base_position.w;

	vec2 snap_resulotion = (vec2(resolution) * vertex_resolution);
	snapped_position.x = floor(snap_resulotion.x * snapped_position.x) / snap_resulotion.x;
	snapped_position.y = floor(snap_resulotion.y * snapped_position.y) / snap_resulotion.y;

	snapped_position.xyz *= base_position.w;
	return snapped_position;
}
```

Importante: **não** há affine texture warping (nada de dividir UV por `POSITION.w`).
Só o wobble de vértice. Adicionar warping deixa diferente da referência.

## 4. Shader base de nível — o modelo de luz é o segredo

```glsl
shader_type spatial;

render_mode blend_mix,
	depth_prepass_alpha,
	shadows_disabled,
	specular_disabled;

#include "res://shaders/common.gdshaderinc"

uniform sampler2D albedo : source_color, filter_nearest;

void vertex()
{
	vec4 snapped_position = snap_to_position(VIEWPORT_SIZE, PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	POSITION = snapped_position;
}

void fragment()
{
	vec4 color_base = COLOR;
	vec4 texture_color = texture(albedo, UV);
	ALBEDO = (color_base * texture_color).rgb;
	ALPHA = texture_color.a * color_base.a;
}

// ESSENCIAL: sem NdotL. Luz aplicada igual em todas as faces.
// Isto mata o sombreado direcional e produz o look flat retro.
void light(){
	DIFFUSE_LIGHT += LIGHT_COLOR * 1.0 * ATTENUATION;
}
```

Todo shader espacial do projeto (nível, props, billboards, arma) precisa desse bloco
`light()`. Fatores de rebaixamento manual por categoria:
- geometria de nível: `* 1.0`
- props / billboards / inimigos: `* 0.7`
- viewmodel de arma em primeira pessoa: `* 0.5`

## 5. Luzes — poucas, largas, sem sombra

`OmniLight3D` apenas. **Nunca** setar `shadow_enabled` (deixe false em todas).

Luz de teto padrão:
```ini
light_color = Color(0.807843, 0.745098, 0.670588, 1)   ; quente
light_specular = 0.0
omni_range = 15.0
omni_attenuation = 0.420448    ; curva suave, alcance longo
light_energy = 1.0
```

Variações:
- fluorescente frio: `Color(0.768627, 1, 1, 1)`, `light_energy = 1.0`
- escritório: `Color(0.847059, 0.913725, 0.815686, 1)`, `light_energy = 3.0`, range 15
- vela: `Color(0.968627, 0.623529, 0.407843, 1)`, `light_energy = 1.5`, range 12
- luz de parede: `Color(0.952941, 1, 0.8, 1)`, `omni_range = 7.0`

Densidade: 1 luz de teto a cada 3–4 tiles de chão, nunca em tiles adjacentes.
Luzes de parede: 25% de chance por parede livre.

Flicker: string de padrão tipo `"mmamammmmammamamaaamammma"`, avança 1 char a cada 0.1s,
`m` = on, `a` = off, alternando `light.visible` (ou `light_energy * 0.75`) e trocando o
material emissivo do mesh entre versão acesa/apagada.

## 6. Recolorização por HSV (temas sem duplicar textura)

Autore as texturas em **cinza**, marcando zonas com faixas de hue: hue 0.3–0.6 = superfície
principal, hue 0.6–1.0 = detalhe/rodapé. O shader converte pra cinza e multiplica pela cor do
tema, então uma textura serve infinitos esquemas de cor.

```glsl
instance uniform vec4 colour: source_color;
instance uniform vec4 trim_colour: source_color;

vec3 rgb2hsv(vec3 c)
{
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec4 to_gray(vec4 tex)
{
	float avg = (tex.r + tex.g + tex.b) / 3.0;
	return vec4(vec3(avg), tex.a);
}

// no fragment():
vec3 hsv = rgb2hsv(texture_color.rgb);
if (hsv.r >= 0.3 && hsv.r <= 0.6)
	texture_color = to_gray(texture_color) * colour;
if (hsv.r >= 0.6 && hsv.r <= 1.0)
	texture_color = to_gray(texture_color) * trim_colour;
```

Aplique via `MultiMeshInstance3D.set_instance_shader_parameter("colour", ...)` — assim cada
sala tem seu tema sem material novo.

## 7. Damage triplanar procedural

Ruído: `FastNoiseLite`, `noise_type=0` (Simplex), `frequency=0.033`, `fractal_octaves=10`,
`fractal_lacunarity=2.295`, `fractal_gain=0.405`, textura 2048², `seamless=true`,
`seamless_blend_skirt=0.235`, `generate_mipmaps=false`.

```glsl
uniform sampler2D damageTexture : source_color, filter_nearest;
uniform sampler2D noise_texture : filter_nearest, repeat_enable;
uniform float shadow_amount = 0.1;
uniform bool use_damage_texture = true;
instance uniform float threshold = 0.5;   // 0.6 paredes, 0.5 chão/teto

float noise_sample(vec4 vertex, vec3 normal, float ox, float oy, float oz){
	vec3 adjusted_normal = pow(abs(normal), vec3(8.0));
	vec3 weights = adjusted_normal / (adjusted_normal.x + adjusted_normal.y + adjusted_normal.z) * 3.0;
	float noise_scale = 0.05;
	vec2 uv_x = vertex.zy;
	vec2 uv_y = vertex.xz;
	vec2 uv_z = vertex.xy;
	float use_y_up = float(normal.y > 0.0);
	vec3 color_x = texture(noise_texture, (uv_x + ox) * noise_scale).rgb * weights.x;
	vec3 color_y_up = texture(noise_texture, (uv_y + oy) * noise_scale).rgb * weights.y;
	vec3 color_y_down = texture(noise_texture, (uv_y + oy) * noise_scale).rgb * weights.y;
	vec3 color_z = texture(noise_texture, (uv_z + oz) * noise_scale).rgb * weights.z;
	return ((color_x + mix(color_y_down, color_y_up, use_y_up) + color_z) / 3.0).r;
}

// no fragment(), dentro da faixa de hue da superfície principal:
vec4 damage_text = use_damage_texture ? texture(damageTexture, UV) : texture_color;
vec4 vertex = INV_VIEW_MATRIX * vec4(VERTEX, 1.0);
vec3 normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);

float noise_val  = noise_sample(vertex, normal, 0.0, 0.0, 0.0);
float offset = 0.005;
float shadow_val = noise_sample(vertex, normal, offset, offset, offset);

float damage = step(threshold, noise_val);
float shadow = smoothstep(threshold - 0.05, threshold + shadow_amount, shadow_val);
vec4 damage_col = mix(vec4(0.0, 0.0, 0.0, 1.0), damage_text, shadow);
d_col = mix(texture_color.rgb, damage_col.rgb, damage);
```

O segundo sample deslocado 0.005 cria a borda escura do desgaste — é o que dá volume sem
sombra real.

## 8. Sky em gradiente de 3 faixas

```glsl
shader_type sky;

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
```

Com `fog_sky_affect = 0.0` o céu fica limpo enquanto a geometria some no preto.

## 9. Billboards de inimigos

```glsl
void vertex()
{
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
		MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	POSITION = snap_to_position(VIEWPORT_SIZE, PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
}
```
Y-billboard (trava no eixo vertical, não gira com o pitch da câmera).
`render_mode cull_disabled, depth_prepass_alpha, shadows_disabled, specular_disabled, diffuse_lambert;`
`ALPHA_SCISSOR_THRESHOLD = 0.5;`

## 10. Viewmodel de arma com FOV próprio

```glsl
render_mode depth_draw_opaque, cull_disabled, diffuse_lambert, shadows_disabled, specular_disabled;
uniform float fov : hint_range(20, 120) = 40;
uniform float depth : hint_range(0, 5) = 0.0;
const float M_PI = 3.14159265359;

void vertex() {
	float scale = 1.0 / tan(fov * 0.5 * M_PI / 180.0);
	PROJECTION_MATRIX[0][0] = scale / (VIEWPORT_SIZE.x / VIEWPORT_SIZE.y);
	PROJECTION_MATRIX[1][1] = -scale;
	POSITION = snap_to_position(VIEWPORT_SIZE, PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	POSITION.z = 0.1;
}

void fragment() {
	// ...
	DEPTH = (FRAGCOORD.z + depth) * 0.7;   // evita clipping na parede
}
```

## 11. Post-process (opcional, só em menus na referência)

CRT com curvatura de tela + aberração cromática (offsets ~0.002 por canal RGB) + vinheta
`pow(16*uv.x*uv.y*(1-uv.x)*(1-uv.y), 0.3)`, sobre `hint_screen_texture` com `filter_nearest`.
No gameplay a referência **não** aplica CRT — só nos menus e na pausa.

## Checklist de erros comuns

- [ ] `ambient_light_source` está em **Color** (2), não Sky nem Disabled? Se não, vai ficar escuro.
- [ ] `ambient_light_color` está perto de branco (~0.87) com energy 1.1?
- [ ] `adjustment_brightness = 1.4` ativo?
- [ ] Todo shader espacial tem `void light()` **sem NdotL**?
- [ ] Todas as luzes com `shadow_enabled = false`?
- [ ] `fog_light_color` é **preto** e `fog_sky_affect = 0.0`?
- [ ] Viewport 640x360 com stretch `viewport`, não filtro de pixelização em tela cheia?
- [ ] Texturas sem mipmap, `filter_nearest`, compressão lossless?

