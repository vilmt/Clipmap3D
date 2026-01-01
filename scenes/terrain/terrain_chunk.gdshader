shader_type spatial;

render_mode wireframe;
render_mode diffuse_burley, specular_schlick_ggx;
// use uniform array for textures

uniform sampler2D height_map: hint_default_black, repeat_disable;
uniform sampler2D normal_map: hint_normal, repeat_disable;

uniform float amplitude;

uniform ivec2 map_origin;
uniform ivec2 map_offset;

uniform vec2 chunk_origin;
uniform vec2 chunk_size;

uniform int max_lod;
const int MAX_RINGS = 20;
uniform int[MAX_RINGS] lods;

varying vec3 global_position;

varying vec3 debug_albedo;

const float EPSILON = 0.00001;

vec4 sample(sampler2D sampler, vec2 world_position) {
	vec2 map_position = world_position * float(1 << max_lod) / chunk_size;
	vec2 uv = (map_position + vec2(map_offset - map_origin) + 0.5) / vec2(textureSize(height_map, 0));
	return textureLod(sampler, uv, 0.0);
}

void vertex() {
	global_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	vec2 chunk = (global_position.xz - chunk_origin) / chunk_size;
	int ring = int(round(max(abs(chunk.x), abs(chunk.y)) + EPSILON));
	int exponent = max(0, max_lod - lods[ring]);
	vec2 subdivision_size = chunk_size / float(1 << exponent);

	vec2 fraction = fract((VERTEX.xz + chunk_size / 2.0) / subdivision_size);
	
	debug_albedo.rgb = vec3(abs(VERTEX.x / 64.0));
	
	global_position.y = amplitude * mix(
		mix(
			sample(height_map, global_position.xz - vec2(fraction.x * subdivision_size.x, 0)).r,
			sample(height_map, global_position.xz + vec2((1.0 - fraction.x) * subdivision_size.x, 0)).r,
			fraction.x
		),
		mix(
			sample(height_map, global_position.xz - vec2(0, fraction.y * subdivision_size.y)).r,
			sample(height_map, global_position.xz + vec2(0, (1.0 - fraction.y) * subdivision_size.y)).r,
			fraction.y
		),
		ceil(fraction.y)
	);
	
	VERTEX.y = global_position.y;
	//NORMAL = sample(normal_map, global_position.xz).rgb * 2.0 - 1.0;
}

void fragment() {
	ALBEDO = debug_albedo;
	vec3 n = sample(normal_map, global_position.xz).rgb;
	NORMAL_MAP = vec3(n.r, 1.0 - n.b, 0.0);
}