shader_type spatial;
render_mode blend_mix, skip_vertex_transform;

/*
TODO:
- Look at normal-based blending
*/

const uint MAX_TEXTURE_COUNT = 32u;

const uint FLAG_STOCHASTIC_OFFSET = 1u << 0u;
const uint FLAG_STOCHASTIC_ROTATION = 1u << 1u;
const uint FLAG_PROJECTED_STOCHASTIC_OFFSET = 1u << 2u;
const uint FLAG_PROJECTED_STOCHASTIC_ROTATION = 1u << 3u;
const uint FLAG_DUAL_SCALING = 1u << 4u;

uniform int dual_scaling_lod: hint_range(0, 10) = 3;
uniform float dual_scaling_factor = 0.2;

uniform float mip_bias: hint_range(-3.0, 3.0) = 0.0;
uniform float lod_blend_ratio: hint_range(0.0, 0.5) = 0.2;

uniform sampler2D stochastic_noise: filter_nearest;

group_uniforms private;

uniform vec3 _target_position;
uniform vec2 _vertex_spacing;
uniform ivec2 _texels_per_vertex;

uniform sampler2DArray _albedo_textures: source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform int[MAX_TEXTURE_COUNT] _albedo_remap;
uniform sampler2DArray _normal_textures: hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform int[MAX_TEXTURE_COUNT] _normal_remap;

uniform vec2[MAX_TEXTURE_COUNT] _uv_scales;
uniform vec3[MAX_TEXTURE_COUNT] _albedo_modulates: source_color;
uniform float[MAX_TEXTURE_COUNT] _roughness_offsets;
uniform float[MAX_TEXTURE_COUNT] _normal_depths;
uniform float[MAX_TEXTURE_COUNT] _height_amplifications;
uniform uint[MAX_TEXTURE_COUNT] _flags;

uniform highp sampler2DArray _height_buffer: hint_default_black, filter_nearest;
//uniform highp sampler2DArray _gradient_buffer: hint_normal, filter_nearest;
uniform highp sampler2DArray _control_buffer: hint_default_black, filter_nearest;

varying vec3 world_position;

varying flat int vertex_lod;
varying float vertex_lod_fract;

varying flat vec3 debug_albedo;

ivec3 imod(ivec3 x, ivec3 y) {
	uvec3 x_u = uvec3(x), x_s = x_u >> 31u;
	uvec3 y_u = uvec3(y), y_s = y_u >> 31u;
    
	uvec3 x_a = (x_u ^ -x_s) + x_s;
	uvec3 y_a = (y_u ^ -y_s) + y_s;
    
	uvec3 q = x_a / y_a, q_s = x_s ^ y_s;
	q += q_s & uvec3(notEqual(x_a, y_a * q));
	q = (q ^ -q_s) + q_s;
	return x - y * ivec3(q);
}

ivec4 imod(ivec4 x, ivec4 y) {
	uvec4 x_u = uvec4(x), x_s = x_u >> 31u;
	uvec4 y_u = uvec4(y), y_s = y_u >> 31u;
    
	uvec4 x_a = (x_u ^ -x_s) + x_s;
	uvec4 y_a = (y_u ^ -y_s) + y_s;
    
	uvec4 q = x_a / y_a, q_s = x_s ^ y_s;
	q += q_s & uvec4(notEqual(x_a, y_a * q));
	q = (q ^ -q_s) + q_s;
	return x - y * ivec4(q);
}

vec4 get_bilinear_weights(vec2 position) {
	vec2 w = fract(position), w_inv = 1.0 - w;
	return vec4(w_inv.x, w.x, w_inv.x, w.x) * vec4(w_inv.y, w_inv.y, w.y, w.y);
}

void vertex() {
	ivec3 buffer_size = textureSize(_height_buffer, 0);
	
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// Scale and LOD from transform
	
	vec2 scale = vec2(MODEL_MATRIX[0][0], MODEL_MATRIX[2][2]);
	int lod = int(log2(scale.x / _vertex_spacing.x) + 1e-5);
	
	vec2 target_texel = _target_position.xz * vec2(_texels_per_vertex) / scale;
	vec2 position = world_position.xz * vec2(_texels_per_vertex) / scale;
	
	// Vertex LOD (LOD transition mask)
	
	vec2 half_size = vec2(buffer_size.xy / 2 - _texels_per_vertex); // Half formula from compute_handler.gd
	vec2 lod_origin = (position - target_texel) / half_size;
	float blend_mask = max(abs(lod_origin.x), abs(lod_origin.y));
	float lod_fract = smoothstep(1.0 - lod_blend_ratio, 1.0, blend_mask);
	lod_fract = lod >= buffer_size.z - 1 ? 0.0 : lod_fract; // Ensure outer LOD does not blend
	lod_fract = max(0.0, lod_fract - 1e-5);
	
	vertex_lod = lod;
	vertex_lod_fract = lod_fract;
	
	// LOD Geo-morphing
	
	vec2 geomorph = lod_fract * mod(floor(world_position.xz / scale + 0.5), 2.0);
	world_position.xz += geomorph * scale;
	position += geomorph * vec2(_texels_per_vertex);
	
	// Height sampling
	
	ivec2 texel = ivec2(floor(position));
	vec4 bilinear_weights = get_bilinear_weights(position);
	ivec4 wrapped = imod(ivec4(texel, texel + ivec2(1)), buffer_size.xyxy);
	ivec4 texels_x = wrapped.xzxz;
	ivec4 texels_y = wrapped.yyww;
	
	vec4 heights = vec4(
		texelFetch(_height_buffer, ivec3(texels_x.x, texels_y.x, lod), 0).r,
		texelFetch(_height_buffer, ivec3(texels_x.y, texels_y.y, lod), 0).r,
		texelFetch(_height_buffer, ivec3(texels_x.z, texels_y.z, lod), 0).r,
		texelFetch(_height_buffer, ivec3(texels_x.w, texels_y.w, lod), 0).r
	);
	
	world_position.y = dot(heights, bilinear_weights);
	
	VERTEX = (VIEW_MATRIX * vec4(world_position, 1.0)).xyz;
	
	world_position.xz /= _vertex_spacing;
}

struct Material {
	vec3 albedo;
	float roughness;
	vec2 normal_map;
	float normal_map_depth;
	float ao;
	
	float total_weight;
};

void accumulate_material(inout Material mat, uvec2 ids, float weight, float blend, vec3 N, vec3 P, vec3 dPdx, vec3 dPdy, float seed, int lod) {
	uint flags_0 = _flags[ids[0]];
	uint flags_1 = _flags[ids[1]];
		
	mat2 projection_align = mat2(1.0);
	
	//float offset_mult_0 = float(flags_0 & FLAG_STOCHASTIC_OFFSET);
	//float angle_mult_0 = float(flags_0 & FLAG_STOCHASTIC_ROTATION);
	//
	//float offset_mult_1 = float(flags_1 & FLAG_STOCHASTIC_OFFSET);
	//float angle_mult_1 = float(flags_1 & FLAG_STOCHASTIC_ROTATION);
	
	if (N.y <= 0.7071067811865475) { // sqrt(0.5)
		// Projected normal map alignment matrix
		projection_align = mat2(vec2(N.z, -N.x), vec2(N.x, N.z));
		// Fast 45 degree snapping https://iquilezles.org/articles/noatan/
		vec2 xz = round(normalize(-N.xz) * 1.3065629648763765); // sqrt(1.0 + sqrt(0.5))
		xz *= abs(xz.x) + abs(xz.y) > 1.5 ? 0.7071067811865475 : 1.0; // sqrt(0.5)
		xz = vec2(-xz.y, xz.x);
		
		P.xz = vec2(dot(P.xz, xz), -P.y);
		dPdx.xz = vec2(dot(dPdx.xz, xz), -dPdx.y);
		dPdy.xz = vec2(dot(dPdy.xz, xz), -dPdy.y);
		
		//offset_mult_0 = float(flags_0 & FLAG_PROJECTED_STOCHASTIC_OFFSET);
		//angle_mult_0 = float(flags_0 & FLAG_PROJECTED_STOCHASTIC_ROTATION);
		//
		//offset_mult_1 = float(flags_1 & FLAG_PROJECTED_STOCHASTIC_OFFSET);
		//angle_mult_1 = float(flags_1 & FLAG_PROJECTED_STOCHASTIC_ROTATION);
	}
	
	vec3 albedo_0 = vec3(0.0);
	float roughness_0 = 0.0;
	vec2 normal_map_0 = vec2(0.0);
	float height_0 = 0.0;
	float ao_0 = 0.0;
	float normal_map_depth_0 = 0.0;
	
	if (blend < 0.999) {
		uint id = ids[0];
		
		int albedo_id = _albedo_remap[id];
		int normal_id = _normal_remap[id];
		
		vec2 s = _uv_scales[id];
		s *= lod >= dual_scaling_lod && bool(flags_0 & FLAG_DUAL_SCALING) ? dual_scaling_factor : 1.0;
		
		float angle = 0.0;//seed * TAU * angle_mult_0;
		float angle_cos = cos(angle), angle_sin = sin(angle);
		
		mat2 angle_rot = mat2(vec2(angle_cos, angle_sin), vec2(-angle_sin, angle_cos));
		
		vec2 uv = P.xz * s;
		vec2 duvdx = dPdx.xz * s;
		vec2 duvdy = dPdy.xz * s;
		
		uv = angle_rot * (uv + 0.5) - 0.5;
		duvdx = angle_rot * duvdx;
		duvdy = angle_rot * duvdy;
		
		vec4 al_r = textureGrad(_albedo_textures, vec3(uv, float(albedo_id)), duvdx, duvdy);
		vec4 nr_h_ao = textureGrad(_normal_textures, vec3(uv, float(normal_id)), duvdx, duvdy);
		nr_h_ao.rg = fma(nr_h_ao.rg, vec2(2.0), vec2(-1.0));
		nr_h_ao.rg = nr_h_ao.rg * projection_align;
		nr_h_ao.rg = angle_rot * nr_h_ao.rg;
		
		albedo_0 = al_r.rgb * _albedo_modulates[id];
		roughness_0 = clamp(al_r.a + _roughness_offsets[id], 0.0, 1.0);
		normal_map_0 = nr_h_ao.rg;
		height_0 = nr_h_ao.b;
		ao_0 = nr_h_ao.a;
		normal_map_depth_0 = _normal_depths[id];
	}
	
	vec3 albedo_1 = vec3(0.0);
	float roughness_1 = 0.0;
	vec2 normal_map_1 = vec2(0.0);
	float height_1 = 0.0;
	float ao_1 = 0.0;
	float normal_map_depth_1 = 0.0;
	
	if (blend > 0.001) {
		uint id = ids[1];
		
		int albedo_id = _albedo_remap[id];
		int normal_id = _normal_remap[id];
		
		vec2 s = _uv_scales[id];
		s *= lod >= dual_scaling_lod && bool(flags_1 & FLAG_DUAL_SCALING) ? dual_scaling_factor : 1.0;
		
		float angle = 0.0;//seed * TAU * angle_mult_1;
		float angle_cos = cos(angle), angle_sin = sin(angle);
		
		mat2 angle_rot = mat2(vec2(angle_cos, angle_sin), vec2(-angle_sin, angle_cos));
		
		vec2 uv = P.xz * s;
		vec2 duvdx = dPdx.xz * s;
		vec2 duvdy = dPdy.xz * s;
		
		uv = angle_rot * (uv + 0.5) - 0.5;
		duvdx = angle_rot * duvdx;
		duvdy = angle_rot * duvdy;
		
		vec4 al_r = textureGrad(_albedo_textures, vec3(uv, float(albedo_id)), duvdx, duvdy);
		vec4 nr_h_ao = textureGrad(_normal_textures, vec3(uv, float(normal_id)), duvdx, duvdy);
		nr_h_ao.rg = fma(nr_h_ao.rg, vec2(2.0), vec2(-1.0));
		nr_h_ao.rg = nr_h_ao.rg * projection_align;
		nr_h_ao.rg = angle_rot * nr_h_ao.rg;
		
		albedo_1 = al_r.rgb * _albedo_modulates[id];
		roughness_1 = clamp(al_r.a + _roughness_offsets[id], 0.0, 1.0);
		normal_map_1 = nr_h_ao.rg;
		height_1 = nr_h_ao.b;
		ao_1 = nr_h_ao.a;
		normal_map_depth_1 = _normal_depths[id];
	}
	
	// Height-based texture blending
	
	const float amplify = 3.0;
	const float depth = 0.1;
	
	height_0 = fma(height_0 + 0.5, amplify * _height_amplifications[ids[0]], -0.5);
	height_1 = fma(height_1 + 0.5, amplify * _height_amplifications[ids[1]], -0.5);
	
	float value_0 = height_0 + (1.0 - blend);
	float value_1 = height_1 + blend;
	
	float max_height = max(value_0, value_1);
	float relative_height_0 = max(value_0 - max_height + depth, 0.0);
	float relative_height_1 = max(value_1 - max_height + depth, 0.0);
	
	blend = relative_height_1 / (relative_height_0 + relative_height_1);
	
	// Accumulation
	
	float w0 = (1.0 - blend) * weight;
	float w1 = blend * weight;
	
	mat.albedo = fma(albedo_0, vec3(w0), fma(albedo_1, vec3(w1), mat.albedo));
	mat.roughness = fma(roughness_0, w0, fma(roughness_1, w1, mat.roughness));
	mat.normal_map = fma(normal_map_0, vec2(w0), fma(normal_map_1, vec2(w1), mat.normal_map));
	mat.ao = fma(ao_0, w0, fma(ao_1, w1, mat.ao));
	mat.normal_map_depth = fma(normal_map_depth_0, w0, fma(normal_map_depth_1, w1, mat.normal_map_depth));
}

void fragment() {
	ivec3 buffer_size = textureSize(_height_buffer, 0);
	
	// LOD selection
	
	vec2 mip_uv = (world_position.xz * vec2(_texels_per_vertex) + 0.5) / vec2(buffer_size.xy);
	float mip_lod = textureQueryLod(_height_buffer, mip_uv).y + mip_bias;
	
	int lod_0 = clamp(int(floor(mip_lod)), vertex_lod, buffer_size.z - 1);
	int lod_1 = lod_0 + 1;
	float lod_fract = fract(clamp(mip_lod, float(vertex_lod) + vertex_lod_fract, float(buffer_size.z - 1)));
	
	// Sampling coordinate space
	
	vec2 position_0 = world_position.xz * vec2(_texels_per_vertex) * exp2(-float(lod_0));
	vec4 bilinear_weights_0 = get_bilinear_weights(position_0);
	ivec2 texel_0 = ivec2(floor(position_0));
	
	// Every fourth sample in lod_1 can be found in lod_0. Reduces samples from 8 -> 7 in a lot of cases
	ivec2 parity = texel_0 & ivec2(1);
	uint duplicate_index = uint(parity.x + 2 * parity.y);
	
	vec2 position_1 = position_0 * 0.5;
	vec4 bilinear_weights_1 = get_bilinear_weights(position_1);
	ivec2 texel_1 = ivec2(floor(position_1));
	
	// Wrapping using integer modulus
	
	
	//ivec4 wrapped_0 = imod(ivec4(texel_0, texel_0 + ivec2(1)), buffer_size.xyxy);
	//ivec4 texels_x_0 = wrapped_0.xzxz;
	//ivec4 texels_y_0 = wrapped_0.yyww;
	//
	//ivec4 wrapped_1 = imod(ivec4(texel_1, texel_1 + ivec2(1)), buffer_size.xyxy);
	//ivec4 texels_x_1 = wrapped_1.xzxz;
	//ivec4 texels_y_1 = wrapped_1.yyww;
	
	// TODO: instead of swizzling here, first determine the parity, then swizzle the offsets themselves.
	// Swizzle to make duplicate index first
	//for (uint i = 0u; i < duplicate_index; i++) {
		//bilinear_weights_1 = bilinear_weights_1.yzwx;
		//texels_x_1 = texels_x_1.yzwx;
		//texels_y_1 = texels_y_1.yzwx;
	//}
	//
	ivec3 texels_x_0 = imod(texel_0.x + ivec3(0, 1, 2), buffer_size.xxx);
	ivec3 texels_y_0 = imod(texel_0.y + ivec3(0, 1, 2), buffer_size.yyy);
	
	ivec3 texels_x_1 = imod(texel_1.x + ivec3(0, 1, 2), buffer_size.xxx);
	ivec3 texels_y_1 = imod(texel_1.y + ivec3(0, 1, 2), buffer_size.yyy);
	
	// Height lookups for normals
	
	// TODO: 8 texturegathers. May be faster for no reason. Also would make swizzling possible.
	
	float height_00_0 = texelFetch(_height_buffer, ivec3(texels_x_0[0], texels_y_0[0], lod_0), 0).r;
	float height_10_0 = texelFetch(_height_buffer, ivec3(texels_x_0[1], texels_y_0[0], lod_0), 0).r;
	float height_01_0 = texelFetch(_height_buffer, ivec3(texels_x_0[0], texels_y_0[1], lod_0), 0).r;
	float height_20_0 = texelFetch(_height_buffer, ivec3(texels_x_0[2], texels_y_0[0], lod_0), 0).r;
	float height_11_0 = texelFetch(_height_buffer, ivec3(texels_x_0[1], texels_y_0[1], lod_0), 0).r;
	float height_02_0 = texelFetch(_height_buffer, ivec3(texels_x_0[0], texels_y_0[2], lod_0), 0).r;
	float height_21_0 = texelFetch(_height_buffer, ivec3(texels_x_0[2], texels_y_0[1], lod_0), 0).r;
	float height_12_0 = texelFetch(_height_buffer, ivec3(texels_x_0[1], texels_y_0[2], lod_0), 0).r;
	
	float height_00_1 = texelFetch(_height_buffer, ivec3(texels_x_1[0], texels_y_1[0], lod_1), 0).r;
	float height_10_1 = texelFetch(_height_buffer, ivec3(texels_x_1[1], texels_y_1[0], lod_1), 0).r;
	float height_01_1 = texelFetch(_height_buffer, ivec3(texels_x_1[0], texels_y_1[1], lod_1), 0).r;
	float height_20_1 = texelFetch(_height_buffer, ivec3(texels_x_1[2], texels_y_1[0], lod_1), 0).r;
	float height_11_1 = texelFetch(_height_buffer, ivec3(texels_x_1[1], texels_y_1[1], lod_1), 0).r;
	float height_02_1 = texelFetch(_height_buffer, ivec3(texels_x_1[0], texels_y_1[2], lod_1), 0).r;
	float height_21_1 = texelFetch(_height_buffer, ivec3(texels_x_1[2], texels_y_1[1], lod_1), 0).r;
	float height_12_1 = texelFetch(_height_buffer, ivec3(texels_x_1[1], texels_y_1[2], lod_1), 0).r;
	
	vec2 gradient_scale_0 = vec2(_texels_per_vertex) * exp2(-float(lod_0)) / _vertex_spacing;
	
	vec2 gradient_scale_1 = vec2(_texels_per_vertex) * exp2(-float(lod_1)) / _vertex_spacing;
	
	vec4 gradients_x_0 = vec4(
		height_10_0 - height_00_0,
		height_20_0 - height_10_0,
		height_11_0 - height_01_0,
		height_21_0 - height_11_0
	) * gradient_scale_0.x;
	vec4 gradients_y_0 = vec4(
		height_01_0 - height_00_0,
		height_11_0 - height_10_0,
		height_02_0 - height_01_0,
		height_12_0 - height_11_0
	) * gradient_scale_0.y;
	
	vec4 gradients_x_1 = vec4(
		height_10_1 - height_00_1,
		height_20_1 - height_10_1,
		height_11_1 - height_01_1,
		height_21_1 - height_11_1
	) * gradient_scale_1.x;
	vec4 gradients_y_1 = vec4(
		height_01_1 - height_00_1,
		height_11_1 - height_10_1,
		height_02_1 - height_01_1,
		height_12_1 - height_11_1
	) * gradient_scale_1.y;
	
	vec2 gradient_0 = vec2(dot(gradients_x_0, bilinear_weights_0), dot(gradients_y_0, bilinear_weights_0));
	vec2 gradient_1 = vec2(dot(gradients_x_1, bilinear_weights_1), dot(gradients_y_1, bilinear_weights_1));
	vec2 gradient = mix(gradient_0, gradient_1, lod_fract);
	
	// Interpolated normal for lighting
	vec3 normal = normalize(vec3(-gradient.x, 1.0, -gradient.y));
	
	// Separate normals for projection
	vec3 normals_0[4] = {
		normalize(vec3(-gradients_x_0.x, 1.0, -gradients_y_0.x)),
		normalize(vec3(-gradients_x_0.y, 1.0, -gradients_y_0.y)),
		normalize(vec3(-gradients_x_0.z, 1.0, -gradients_y_0.z)),
		normalize(vec3(-gradients_x_0.w, 1.0, -gradients_y_0.w))
	};
	
	vec3 normals_1[4] = {
		normalize(vec3(-gradients_x_1.x, 1.0, -gradients_y_1.x)),
		normalize(vec3(-gradients_x_1.y, 1.0, -gradients_y_1.y)),
		normalize(vec3(-gradients_x_1.z, 1.0, -gradients_y_1.z)),
		normalize(vec3(-gradients_x_1.w, 1.0, -gradients_y_1.w))
	};
	
	// TODO: based on the sampling pattern, should be able to replace more LOD N+1 lookups.
	// ^ This is problematic because height-based normals may not be deterministic between LODs
	
	// Total unique cases: 8
	
	vec3 tangent = normalize(cross(normal, vec3(0.0, 0.0, 1.0)));
	vec3 binormal = normalize(cross(normal, tangent));
	
	NORMAL = (VIEW_MATRIX * vec4(normal, 0.0)).xyz;
	TANGENT = (VIEW_MATRIX * vec4(tangent, 0.0)).xyz;
	BINORMAL = (VIEW_MATRIX * vec4(binormal, 0.0)).xyz;
	
	// Separate normals for projection
	
	// Material accumulation from accumulated texture weights
	
	Material mat = Material(vec3(0.0), 0.0, vec2(0.0), 0.0, 0.0, 0.0);
	
	vec3 P = world_position;
	vec3 dPdx = dFdxCoarse(world_position);
	vec3 dPdy = dFdyCoarse(world_position);
	
	// TODO
	vec4 seeds_0 = vec4(0.0);
	vec4 seeds_1 = vec4(0.0);
	
	// Control lookups
	
	uvec4 controls_0 = floatBitsToUint(vec4(
		texelFetch(_control_buffer, ivec3(texels_x_0[0], texels_y_0[0], lod_0), 0).r,
		texelFetch(_control_buffer, ivec3(texels_x_0[1], texels_y_0[0], lod_0), 0).r,
		texelFetch(_control_buffer, ivec3(texels_x_0[0], texels_y_0[1], lod_0), 0).r,
		texelFetch(_control_buffer, ivec3(texels_x_0[1], texels_y_0[1], lod_0), 0).r
	));
	
	uvec4 controls_1 = floatBitsToUint(vec4(
		texelFetch(_control_buffer, ivec3(texels_x_1[0], texels_y_1[0], lod_1), 0).r,
		texelFetch(_control_buffer, ivec3(texels_x_1[1], texels_y_1[0], lod_1), 0).r,
		texelFetch(_control_buffer, ivec3(texels_x_1[0], texels_y_1[1], lod_1), 0).r,
		texelFetch(_control_buffer, ivec3(texels_x_1[1], texels_y_1[1], lod_1), 0).r
	));
	
	//uvec4 controls_1 = uvec4(
		//0u, floatBitsToUint(vec3(
		//texelFetch(_control_buffer, ivec3(texels_x_1.y, texels_y_1.y, lod_1), 0).r,
		//texelFetch(_control_buffer, ivec3(texels_x_1.z, texels_y_1.z, lod_1), 0).r,
		//texelFetch(_control_buffer, ivec3(texels_x_1.w, texels_y_1.w, lod_1), 0).r
	//)));
	
	// Texture weight accumulation from control
	
	uvec4 ids_0_0 = controls_0 >> uvec4(27u) & uvec4(0x1Fu);
	uvec4 ids_1_0 = controls_0 >> uvec4(22u) & uvec4(0x1Fu);
	vec4 blends_0 = vec4(controls_0 >> uvec4(14u) & uvec4(0xFFu)) / 255.0;
	
	uvec2 ids_0[4] = uvec2[4](
		uvec2(ids_0_0[0], ids_1_0[0]),
		uvec2(ids_0_0[1], ids_1_0[1]),
		uvec2(ids_0_0[2], ids_1_0[2]),
		uvec2(ids_0_0[3], ids_1_0[3])
	);
	
	vec4 weights_0 = bilinear_weights_0 * (1.0 - lod_fract);
	
	uvec4 ids_0_1 = controls_1 >> uvec4(27u) & uvec4(0x1Fu);
	uvec4 ids_1_1 = controls_1 >> uvec4(22u) & uvec4(0x1Fu);
	vec4 blends_1 = vec4(controls_1 >> uvec4(14u) & uvec4(0xFFu)) / 255.0;
	
	uvec2 ids_1[4] = uvec2[4](
		uvec2(ids_0_1[0], ids_1_1[0]),
		uvec2(ids_0_1[1], ids_1_1[1]),
		uvec2(ids_0_1[2], ids_1_1[2]),
		uvec2(ids_0_1[3], ids_1_1[3])
	);
	
	vec4 weights_1 = bilinear_weights_1 * lod_fract;

	if (lod_fract > 0.001) {
		accumulate_material(mat, ids_1[0], weights_1[0], blends_1[0], normals_1[0], P, dPdx, dPdy, 0.0, lod_1);
		accumulate_material(mat, ids_1[1], weights_1[1], blends_1[1], normals_1[1], P, dPdx, dPdy, 0.0, lod_1);
		accumulate_material(mat, ids_1[2], weights_1[2], blends_1[2], normals_1[2], P, dPdx, dPdy, 0.0, lod_1);
		accumulate_material(mat, ids_1[3], weights_1[3], blends_1[3], normals_1[3], P, dPdx, dPdy, 0.0, lod_1);
	}
	
	accumulate_material(mat, ids_0[0], weights_0[0], blends_0[0], normals_0[0], P, dPdx, dPdy, 0.0, lod_0);
	accumulate_material(mat, ids_0[1], weights_0[1], blends_0[1], normals_0[1], P, dPdx, dPdy, 0.0, lod_0);
	accumulate_material(mat, ids_0[2], weights_0[2], blends_0[2], normals_0[2], P, dPdx, dPdy, 0.0, lod_0);
	accumulate_material(mat, ids_0[3], weights_0[3], blends_0[3], normals_0[3], P, dPdx, dPdy, 0.0, lod_0);
	
	// PBR
	
	ALBEDO = mat.albedo;
	ROUGHNESS = mat.roughness;
	NORMAL_MAP.rg = fma(mat.normal_map, vec2(0.5), vec2(0.5));
	NORMAL_MAP_DEPTH = mat.normal_map_depth;
	AO = mat.ao;
	
	//ALBEDO = vec3(float(bool(lod_fract > 0.001)));
	//
	//ALBEDO = debug_albedo;
	
	//ALBEDO = vec3(float(accumulations)) * 0.25;
	
	//ALBEDO = vec3(float(seeds_0[0]));
	
}