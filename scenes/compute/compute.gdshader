shader_type spatial;

uniform highp sampler2DArray _height_maps: repeat_disable, hint_default_black, filter_nearest;
uniform sampler2DArray _normal_maps: repeat_disable, hint_normal, filter_nearest;
uniform highp usampler2DArray _control_maps: repeat_disable, hint_default_black, filter_nearest;

varying vec3 world_position;
varying vec3 debug_albedo;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	//float h = texture(_height_maps, vec3(UV, 0.0)).r;
	float h = texture(_height_maps, vec3(UV, 0.0)).r;
	vec2 n = texture(_normal_maps, vec3(UV, 0.0)).rg;
	world_position.y = h * 10.0;
	VERTEX.y = world_position.y;
	
	//debug_albedo = vec3(h);
	debug_albedo.rg = n;
}

void fragment() {
	ALBEDO = debug_albedo;
}