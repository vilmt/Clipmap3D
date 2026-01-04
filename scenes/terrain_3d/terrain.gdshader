shader_type spatial;

//render_mode wireframe;
uniform highp sampler2D height_map: hint_default_black, repeat_disable;

uniform float amplitude;

uniform ivec2 map_origin;

uniform vec2 vertex_spacing;
//uniform vec2 snap_origin;

varying vec3 global_position;

varying vec3 debug_albedo;

ivec2 to_texel(vec2 world_position) {
	ivec2 map_position = ivec2(round(world_position / vertex_spacing));
	return map_position - map_origin + textureSize(height_map, 0) / 2;
}

void vertex() {
	global_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	ivec2 texel = to_texel(global_position.xz);
	global_position.y = amplitude * texelFetch(height_map, texel, 0).r;
	
	VERTEX.y = global_position.y;
	
	debug_albedo.rg = VERTEX.xz / 64.0;
}

void fragment() {
	ivec2 texel = to_texel(global_position.xz);
	
	float h = texelFetch(height_map, texel, 0).r * amplitude;
	float r = texelFetch(height_map, texel + ivec2(0, 1), 0).r * amplitude;
	float u = texelFetch(height_map, texel + ivec2(1, 0), 0).r * amplitude;
	
	float dx = (h - r) / vertex_spacing.x;
	float dy = (h - u) / vertex_spacing.y;
	
	vec3 normal = normalize(vec3(-dx, 1.0, -dy));
	
	vec3 normal_map = normal * 0.5 + 0.5;
	
	NORMAL_MAP = normal_map.xzy;
	
	ALBEDO = vec3(0.7);
	ALBEDO = debug_albedo;
}