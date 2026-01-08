shader_type spatial;

render_mode cull_disabled, blend_mix;

uniform vec2 wind_velocity = vec2(1.0, 1.0);

uniform vec3 camera_position;

//varying vec4 data;

void vertex() {
	float y = VERTEX.y + 0.5;
	VERTEX.xz *= 1.0 - y;

	//// Brighten tips
	//COLOR = mix(COLOR, vec4(1.0), smoothstep(0.9, 1.0, data[2]));
	//// Darken base, skip is scale is less than threshold, as this means "grow in" is occuring.
	//COLOR *= INSTANCE_CUSTOM[3] < 0.35 ? 1. : mix(1.0, 0.75, smoothstep(0.35, 0.0, data[2]));
	//// Save red/green shift for fragment
	//data.rg = INSTANCE_CUSTOM.rg;
//
	//// World space vertex
	//vec3 w_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	//// Get wind force and scale from process()
	//float scale = pow(INSTANCE_CUSTOM[3] * INSTANCE_CUSTOM[3], 0.707);
	//float force = INSTANCE_CUSTOM[2] * data[2] * scale;
	//// Add some cheap jitter at high wind values
	//force -= fract(force * 256.0) * force * 0.05;
	//// Curve the result
	//force = pow(force, 0.707);
//
	//// These 2 combined result in a decent bend without resorting to matrices or pivot data.
	//// Lateral move and wobble
	float lateral_wobble = sin(TIME);
	VERTEX.xz += wind_velocity * lateral_wobble * y;
	//// Flatten
	//w_vertex.y -= INSTANCE_CUSTOM[2] * force * data[2];
//
	//// Save final wind force value for fragment.
	//data[3] = force;
//
	//VERTEX = (VIEW_MATRIX * vec4(w_vertex, 1.0)).xyz;
	//NORMAL = MODELVIEW_NORMAL_MATRIX * NORMAL;
	//BINORMAL = MODELVIEW_NORMAL_MATRIX * BINORMAL;
	//TANGENT = MODELVIEW_NORMAL_MATRIX * TANGENT;
}

void fragment() {
	//// Hard coded color.
	//ALBEDO = vec3(0.20, 0.22, 0.05) * (data[2] * 0.5 + 0.5);
	//ALBEDO.rg *= (data.rg * 0.3 + 0.9);
	//ALBEDO *= pow(COLOR.rgb, vec3(2.2));
	//// Modify roughness / specular based on wind force for added detail
	//float spec_rough = clamp(max(data[2], data[3]), 0., 1.);
	//ROUGHNESS = 1. - spec_rough;
	//SPECULAR = clamp(spec_rough * 0.25, 0., .15);
//
	//BACKLIGHT = vec3(0.33);
	ALBEDO = vec3(1.0);
}
