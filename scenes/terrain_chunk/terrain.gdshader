shader_type spatial;

//render_mode wireframe;
render_mode diffuse_burley, specular_schlick_ggx;
// use uniform array for textures

global uniform sampler2D height_map: hint_default_black, repeat_disable;
global uniform float height_map_amplitude;
global uniform sampler2D normal_map: hint_normal, repeat_disable;
global uniform vec3 terrain_position;

global uniform vec2 terrain_chunk_size;
global uniform int terrain_max_lod;
global uniform int terrain_lod_zero_radius;
// TODO: ring thickness

varying vec3 global_position;
varying vec3 triplanar_weights;

//varying vec3 vertex_normal;
varying vec3 debug_albedo;

const float EPSILON = 0.00001;

float height(vec2 world_position) {
	vec2 subdivision_size = terrain_chunk_size / float(1 << terrain_max_lod);
	vec2 texel_pos = world_position / subdivision_size;
	vec2 uv = (texel_pos + 0.5) / vec2(textureSize(height_map, 0)); // sample texel centers
	return texture(height_map, uv + 0.5).r * height_map_amplitude; // arbitrary centering offset
}

vec3 normal(vec2 world_position) {
	vec2 subdivision_size = terrain_chunk_size / float(1 << terrain_max_lod);
	vec2 texel_pos = world_position / subdivision_size;
	vec2 uv = (texel_pos + 0.5) / vec2(textureSize(height_map, 0)); // sample texel centers
	return texture(normal_map, uv + 0.5).rgb * 2.0 - vec3(1.0);
}

void vertex() {
	global_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	vec2 chunk = (global_position - terrain_position).xz / terrain_chunk_size;
	int ring = int(round(max(abs(chunk.x), abs(chunk.y)) + EPSILON));
	ring = max(0, ring - terrain_lod_zero_radius);
	int exponent = max(0, terrain_max_lod - ring);
	vec2 subdivision_size = terrain_chunk_size / float(1 << exponent);

	vec2 fraction = fract((VERTEX.xz + terrain_chunk_size / 2.0) / subdivision_size);

	VERTEX.y = mix(
		mix(
			height(global_position.xz - vec2(fraction.x * subdivision_size.x, 0)),
			height(global_position.xz + vec2((1.0 - fraction.x) * subdivision_size.x, 0)),
			fraction.x
		),
		mix(
			height(global_position.xz - vec2(0, fraction.y * subdivision_size.y)),
			height(global_position.xz + vec2(0, (1.0 - fraction.y) * subdivision_size.y)),
			fraction.y
		),
		ceil(fraction.y)
	);

	global_position.y = VERTEX.y;

	NORMAL = normal(global_position.xz);
}

void fragment() {
	ALBEDO = vec3(0.8);
}