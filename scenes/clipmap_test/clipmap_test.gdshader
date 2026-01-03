shader_type spatial;

uniform sampler2D height_map: hint_default_black, repeat_disable;

uniform float amplitude;

uniform ivec2 map_origin;
uniform ivec2 map_offset;

uniform vec2 vertex_spacing;
uniform vec2 snap_origin;

varying vec3 global_position;

//render_mode wireframe;

varying vec3 debug_albedo;

vec4 sample(sampler2D sampler, vec2 world_position) {
	vec2 map_position = world_position * vertex_spacing;
	ivec2 uv = ivec2(round(map_position + 0.5)) + map_offset - map_origin ; /// vec2(textureSize(height_map, 0));
	//return textureLod(sampler, uv, 0.0);
	return texelFetch(sampler, uv, 0);
}

void vertex() {
	global_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	global_position.y = amplitude * sample(height_map, global_position.xy).r;
	
	VERTEX.y = global_position.y;
	
	debug_albedo.rg = VERTEX.xz / 64.0;
}

void fragment() {
	
	ALBEDO = vec3(0.7);
	//ALBEDO = debug_albedo;
}