shader_type spatial;

//render_mode wireframe;
uniform float normal_radius = 1.0;
uniform highp sampler2DArray height_maps: repeat_disable, filter_linear;

//uniform highp sampler2D height_map: hint_default_black, repeat_disable, filter_linear_mipmap;
uniform float height_amplitude;

uniform vec2 vertex_spacing;
uniform ivec2 map_origin;

uniform vec2 mesh_origin;
uniform ivec2 tile_size;

varying vec3 world_position;

varying vec3 debug_albedo;

varying flat int vertex_lod;

ivec2 to_texel(vec2 world_xz, int lod) {
	vec2 lod_spacing = vertex_spacing * float(1 << lod);
	ivec2 lod_cell = ivec2(floor(world_xz / lod_spacing));
	return lod_cell - map_origin + textureSize(height_maps, 0).xy / 2;
}

vec2 to_uv(vec2 world_xz, int lod) {
	vec2 lod_spacing = vertex_spacing * float(1 << lod);
	vec2 lod_cell = world_xz / lod_spacing;
	vec2 texel = lod_cell + vec2(-map_origin + textureSize(height_maps, 0).xy / 2) + 0.5;
	return texel / vec2(textureSize(height_maps, 0).xy);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	vec2 scale = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[2].xyz));
	vec2 next_scale = scale * 2.0;
	float texel_size = scale.x / vertex_spacing.x;
	int lod = int(log2(texel_size));
	vertex_lod = lod;
	
	vec2 edge = floor(mesh_origin / scale) - 2.0 * floor(mesh_origin / next_scale);
	
	ivec2 texel = to_texel(world_position.xz, lod);

	vec2 lod_position = floor((world_position.xz - mesh_origin) / scale - 0.0001) + edge;
	
	vec2 edge_mask = step(vec2(tile_size) * 2.0 + 0.5, abs(lod_position));
	vec2 even_mask = abs(mod(lod_position, 2.0) - 1.0);
	ivec2 offset = ivec2(edge_mask.yx * even_mask);
	float h_0 = height_amplitude * texelFetch(height_maps, ivec3(texel - offset, lod), 0).r;
	float h_1 = height_amplitude * texelFetch(height_maps, ivec3(texel + offset, lod), 0).r;
	VERTEX.y = mix(h_0, h_1, 0.5);
	
	debug_albedo.rg = VERTEX.xz / 64.0;
	debug_albedo.rg = edge_mask.yx * even_mask;
	//debug_albedo.rg = edge_mask.yx;
}

void fragment() {
	// central difference
	vec2 uv = to_uv(world_position.xz, vertex_lod);
	vec2 texel_size = 1.0 / vec2(textureSize(height_maps, 0).xy);
	vec2 step_texel = normal_radius / vertex_spacing * texel_size;
	
	float lod = float(vertex_lod);
	float scale = float(1 << vertex_lod);
	float l = texture(height_maps, vec3(uv - vec2(step_texel.x, 0), lod)).r;
	float r = texture(height_maps, vec3(uv + vec2(step_texel.x, 0), lod)).r;
	float d = texture(height_maps, vec3(uv - vec2(0, step_texel.y), lod)).r;
	float u = texture(height_maps, vec3(uv + vec2(0, step_texel.y), lod)).r;

	float dx = (l - r) * height_amplitude / (2.0 * normal_radius * scale);
	float dz = (d - u) * height_amplitude / (2.0 * normal_radius * scale);
 
	NORMAL_MAP = normalize(vec3(-dz, -dx, 1.0)) * 0.5 + 0.5;
	ALBEDO = debug_albedo;
	//ALBEDO.rg = uv;
	//ALBEDO = vec3(0.7);
}