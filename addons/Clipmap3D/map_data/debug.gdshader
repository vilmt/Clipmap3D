shader_type canvas_item;

uniform highp sampler2DArray _height_maps: hint_default_black, repeat_enable, filter_nearest;
uniform highp sampler2DArray _gradient_maps: hint_normal, repeat_enable, filter_nearest;
uniform highp sampler2DArray _control_maps: hint_default_black, repeat_enable, filter_nearest;

vec3 rainbow(float t) {
	const vec3 a = vec3(0.5, 0.5, 0.5);
	const vec3 b = vec3(0.5, 0.5, 0.5);
	const vec3 c = vec3(1.0, 1.0, 1.0);
	const vec3 d = vec3(0.00, 0.33, 0.67);
	vec3 x = TAU * (c * t + d);
	return a + b * cos(x) * smoothstep(TAU, 0.0, fwidth(x));
}

void fragment() {
	float layers = float(textureSize(_height_maps, 0).z);
	float layer = UV.x * layers;
	vec3 coords = vec3(fract(layer), UV.y, floor(layer));
	float h = texture(_height_maps, coords).r;
	
	const float l = 0.03;
	vec2 border = max(vec2(0.0), (abs(2.0 * coords.xy - 1.0) - 1.0) / l + 1.0);
	
	float border_s = max(border.x, border.y);
	
	COLOR.rgb = rainbow(h * 0.01 * 1.0 / pow(2.0, floor(layer)));
	
	COLOR.rgb = mix(COLOR.rgb, vec3(0.0), smoothstep(0.0, fwidth(border_s), border_s));
}

