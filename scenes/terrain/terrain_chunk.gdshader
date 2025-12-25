shader_type spatial;

//render_mode wireframe;
render_mode diffuse_burley, specular_schlick_ggx;
// use uniform array for textures

uniform float amplitude;
uniform sampler2D height_map: hint_default_black, repeat_disable;

uniform sampler2D normal_map: hint_normal, repeat_disable;
uniform vec3 terrain_position;

uniform vec2 chunk_size;
uniform int max_lod;
uniform int[1] lods;

varying vec3 global_position;
varying vec3 triplanar_weights;

//varying vec3 vertex_normal;
varying vec3 debug_albedo;

const float EPSILON = 0.00001;

float height(vec2 world_position) {
	vec2 subdivision_size = chunk_size / float(1 << max_lod);
	vec2 texel_pos = world_position / subdivision_size;
	vec2 uv = (texel_pos + 0.5) / vec2(textureSize(height_map, 0)); // sample texel centers
	return textureLod(height_map, uv + 0.5, 0.0).r * amplitude; // arbitrary centering offset
}

vec3 normal(vec2 world_position) {
	vec2 subdivision_size = chunk_size / float(1 << max_lod);
	vec2 texel_pos = world_position / subdivision_size;
	vec2 uv = (texel_pos + 0.5) / vec2(textureSize(height_map, 0)); // sample texel centers
	return textureLod(normal_map, uv + 0.5, 0.0).rgb * 2.0 - vec3(1.0);
}

void vertex() {
	global_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	vec2 chunk = (global_position - terrain_position).xz / chunk_size;
	int ring = int(round(max(abs(chunk.x), abs(chunk.y)) + EPSILON));
	// TODO TODO TODO
	//ring = max(0, ring - terrain_lod_zero_radius);
	int exponent = max(0, max_lod - ring);
	vec2 subdivision_size = chunk_size / float(1 << exponent);

	vec2 fraction = fract((VERTEX.xz + chunk_size / 2.0) / subdivision_size);
	
	//debug_albedo = vec3(fraction.x, fraction.y, 0.0);

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
	ALBEDO = vec3(0.7);
}