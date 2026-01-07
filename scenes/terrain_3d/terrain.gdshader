shader_type spatial;

//render_mode wireframe;
uniform float normal_radius = 1.0;

uniform highp sampler2D height_map: hint_default_black, repeat_disable, filter_linear_mipmap;
uniform float height_amplitude;

uniform vec2 vertex_spacing;
uniform ivec2 map_origin;

uniform vec2 mesh_origin;
uniform ivec2 tile_size;

varying vec3 world_position;

varying vec3 debug_albedo;

ivec2 to_texel(vec2 world) {
	ivec2 map = ivec2(round(world / vertex_spacing));
	return map - map_origin + textureSize(height_map, 0) / 2;
}

vec2 to_texel_vec2(vec2 world) {
	vec2 map = world / vertex_spacing;
	vec2 texel = map + vec2(-map_origin + textureSize(height_map, 0) / 2) + 0.5;
	return texel / vec2(textureSize(height_map, 0));
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	vec2 scale = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[2].xyz));
	vec2 next_scale = scale * 2.0;
	
	vec2 edge = floor(mesh_origin / scale) - 2.0 * floor(mesh_origin / next_scale);
	
	vec2 lod_position = floor((world_position.xz - mesh_origin) / scale) + edge;
	
	vec2 edge_mask = step(vec2(tile_size) * 2.0 + 0.5, abs(lod_position));
	vec2 even_mask = abs(mod(lod_position, 2.0) - 1.0);

	ivec2 texel = to_texel(world_position.xz);
	
	float texel_size = scale.x / vertex_spacing.x;
	ivec2 offset = ivec2(edge_mask.yx * even_mask * texel_size);
	
	float h_0 = height_amplitude * texelFetch(height_map, texel - offset, 0).r;
	float h_1 = height_amplitude * texelFetch(height_map, texel + offset, 0).r;
	VERTEX.y = mix(h_0, h_1, 0.5);
}

void fragment() {
	// central difference
	vec2 uv = to_texel_vec2(world_position.xz);
	vec2 texel_size = 1.0 / vec2(textureSize(height_map, 0));
	vec2 step_texel = normal_radius / vertex_spacing * texel_size;
	
	float l = texture(height_map, uv - vec2(step_texel.x, 0)).r;
	float r = texture(height_map, uv + vec2(step_texel.x, 0)).r;
	float d = texture(height_map, uv - vec2(0, step_texel.y)).r;
	float u = texture(height_map, uv + vec2(0, step_texel.y)).r;

	float dx = (l - r) * height_amplitude / (2.0 * normal_radius);
	float dz = (d - u) * height_amplitude / (2.0 * normal_radius);
 
	NORMAL_MAP = normalize(vec3(-dz, -dx, 1.0)) * 0.5 + 0.5;
}