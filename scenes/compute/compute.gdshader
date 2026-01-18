shader_type spatial;

uniform highp sampler2DArray _height_maps: repeat_disable, hint_default_black, filter_nearest;
uniform sampler2DArray _normal_maps: repeat_disable, hint_normal, filter_linear;
uniform highp sampler2DArray _control_maps: repeat_disable, hint_default_black, filter_nearest;

varying vec3 world_position;
varying vec3 debug_albedo;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	UV += 0.5 / vec2(textureSize(_normal_maps, 0).xy);
	
	float h = texture(_height_maps, vec3(UV, 0.0)).r;
	world_position.y = h;
	VERTEX.y = world_position.y;
	
	debug_albedo = vec3(0.7);
}

void fragment() {
	ALBEDO = debug_albedo;
	
	vec2 grad = texture(_normal_maps, vec3(UV, 0.0)).rg;
	
	vec3 normal = normalize(vec3(grad.x, 1.0, grad.y));
	vec3 tangent = normalize(cross(normal, vec3(0.0, 0.0, 1.0)));
	vec3 binormal = normalize(cross(normal, tangent));
	
	NORMAL = mat3(VIEW_MATRIX) * normal;
	TANGENT = mat3(VIEW_MATRIX) * tangent;
	BINORMAL = mat3(VIEW_MATRIX) * binormal;
	
}