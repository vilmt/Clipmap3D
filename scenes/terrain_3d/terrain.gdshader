shader_type spatial;

//render_mode wireframe;
uniform highp sampler2D height_map: hint_default_black, repeat_disable;
uniform sampler2D normal_map: hint_normal, repeat_disable;

uniform float amplitude;
uniform vec2 vertex_spacing;
uniform ivec2 map_origin;

uniform vec2 mesh_origin;
uniform ivec2 mesh_size;

varying vec3 world_position;

varying vec3 debug_albedo;

ivec2 to_texel(vec2 world) {
	ivec2 map = ivec2(round(world / vertex_spacing));
	return map - map_origin + textureSize(height_map, 0) / 2;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	vec2 scale = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[2].xyz));
	vec2 next_scale = scale * 2.0;
	
	vec2 edge = floor(mesh_origin / scale) - 2.0 * floor(mesh_origin / next_scale);
	
	vec2 lod_position = floor((world_position.xz - mesh_origin) / scale) + edge;
	
	vec2 edge_mask = step(vec2(mesh_size) * 2.0 + 0.5, abs(lod_position));
	vec2 even_mask = abs(mod(lod_position, 2.0) - 1.0);

	ivec2 texel = to_texel(world_position.xz);
	
	float texel_size = scale.x / vertex_spacing.x;
	ivec2 offset = ivec2(edge_mask.yx * even_mask * texel_size);
	
	float h_0 = amplitude * texelFetch(height_map, texel - offset, 0).r;
	float h_1 = amplitude * texelFetch(height_map, texel + offset, 0).r;
	VERTEX.y = mix(h_0, h_1, 0.5);
}

void fragment() {
	ivec2 texel = to_texel(world_position.xz);
	
	float h = texelFetch(height_map, texel, 0).r * amplitude;
	float r = texelFetch(height_map, texel + ivec2(0, 1), 0).r * amplitude;
	float u = texelFetch(height_map, texel + ivec2(1, 0), 0).r * amplitude;
	
	float dx = (h - r) / vertex_spacing.x;
	float dy = (h - u) / vertex_spacing.y;
	
	vec3 normal = normalize(vec3(-dx, 1.0, -dy));
	NORMAL_MAP = (normal * 0.5 + 0.5).xzy;
	
	vec3 n = texelFetch(normal_map, texel, 0).rgb;
	NORMAL_MAP = vec3(n.r, 1.0 - n.b, 0.0);
	
	ALBEDO = vec3(0.7);
	//ALBEDO = debug_albedo;
}