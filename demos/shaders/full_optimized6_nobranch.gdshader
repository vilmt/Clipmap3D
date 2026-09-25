shader_type spatial;
render_mode blend_mix, skip_vertex_transform;

/*
TODO:
- Fix gpu sort (increasing max texture count should reduce performance)
- Add height-based blending
- Look at normal-based blending
*/

uniform bool enable_depth_blending = true;

const uint MAX_TEXTURE_COUNT = 32u;

const uint FLAG_STOCHASTIC_OFFSET = 1u << 0u;
const uint FLAG_STOCHASTIC_ROTATION = 1u << 1u;
const uint FLAG_TRIPLANAR = 1u << 2u;
const uint FLAG_TRIPLANAR_STOCHASTIC_OFFSET = 1u << 3u;
const uint FLAG_TRIPLANAR_STOCHASTIC_ROTATION = 1u << 4u;

uniform sampler2D stochastic_noise: filter_linear;
uniform float stochastic_blend_bias = 0.1; // TODO: should be material parameter

uniform bool use_mip_lod = true;

uniform float mip_bias: hint_range(-3.0, 3.0) = 0.0;
uniform float triplanar_sharpness: hint_range(1.0, 100.0) = 30.0;

uniform float lod_blend_ratio: hint_range(0.0, 0.5) = 0.2;

group_uniforms private;

uniform vec3 _target_position;
uniform vec2 _vertex_spacing;
uniform ivec2 _texels_per_vertex;

uniform sampler2DArray _albedo_textures: source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform int[MAX_TEXTURE_COUNT] _albedo_remap;
uniform sampler2DArray _normal_textures: hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform int[MAX_TEXTURE_COUNT] _normal_remap;

uniform vec3[MAX_TEXTURE_COUNT] _uv_scales;
uniform vec3[MAX_TEXTURE_COUNT] _albedo_modulates: source_color;
uniform float[MAX_TEXTURE_COUNT] _roughness_offsets;
uniform float[MAX_TEXTURE_COUNT] _normal_depths;
uniform float[MAX_TEXTURE_COUNT] _height_amplifications;
uniform uint[MAX_TEXTURE_COUNT] _flags;

uniform highp sampler2DArray _height_buffer: hint_default_black, repeat_enable, filter_linear;
uniform highp sampler2DArray _gradient_buffer: hint_normal, repeat_enable, filter_linear;
uniform highp sampler2DArray _control_buffer: hint_default_black, repeat_enable, filter_nearest;

varying vec3 world_position;

varying flat int vertex_lod_floor;
varying float vertex_lod_fract;

varying flat vec3 debug_albedo;

vec2 get_uv(vec2 texel, vec2 sampler_size) {
	return (texel + 0.5) / sampler_size;
}

vec2 get_bilinear_uv(vec2 texel, vec2 sampler_size) {
	return (floor(texel) + 0.5) / sampler_size;
}

vec4 get_bilinear_weights(vec2 texel) {
	vec2 w = fract(texel), w_inv = 1.0 - w;
	return vec4(w_inv.x, w.x, w_inv.x, w.x) * vec4(w_inv.y, w_inv.y, w.y, w.y);
}

void vertex() {
	ivec3 buffer_size = textureSize(_gradient_buffer, 0);
	
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// Scale and LOD from transform
	
	vec2 scale = vec2(MODEL_MATRIX[0][0], MODEL_MATRIX[2][2]);
	float lod_floor = log2(scale.x / _vertex_spacing.x);
	
	vec2 target_texel = _target_position.xz * vec2(_texels_per_vertex) / scale;
	vec2 texel = world_position.xz * vec2(_texels_per_vertex) / scale;
	
	// Vertex LOD (LOD transition mask)
	
	vec2 half_size = vec2(buffer_size.xy / 2 - _texels_per_vertex); // Half formula from compute_handler.gd
	vec2 lod_origin = (texel - target_texel) / half_size;
	float blend_mask = max(abs(lod_origin.x), abs(lod_origin.y));
	float lod_fract = smoothstep(1.0 - lod_blend_ratio, 1.0, blend_mask);
	lod_fract = int(lod_floor) >= buffer_size.z - 1 ? 0.0 : lod_fract; // Ensure outer LOD does not blend
	lod_fract = max(0.0, lod_fract - 1e-5);
	
	vertex_lod_floor = int(lod_floor + 0.5);
	vertex_lod_fract = lod_fract;
	
	// LOD Geo-morphing
	
	vec2 geomorph = lod_fract * mod(floor(world_position.xz / scale + 0.5), 2.0);
	world_position.xz += geomorph * scale;
	texel += geomorph * vec2(_texels_per_vertex);
	
	// Height sampling
	
	vec2 uv = get_uv(texel, vec2(buffer_size.xy));
	world_position.y = texture(_height_buffer, vec3(uv, lod_floor)).r;
	
	VERTEX = (VIEW_MATRIX * vec4(world_position, 1.0)).xyz;
	
	world_position.xz /= _vertex_spacing;
}

struct Material {
	vec3 albedo;
	float roughness;
	vec3 normal;
	float normal_depth;
	float ao;
	
	float total_weight;
};

void accumulate_material(inout Material mat, uvec2 ids, float w, float blend, vec3 P, vec3 dPdx, vec3 dPdy, vec3 power_normal,
	vec2 offset_A, mat2 rotation_A, vec2 offset_B, mat2 rotation_B, float blend_AB) {
		
	// Material accumulation for the base and overlay id. Only the blend value influences branching.
	
	vec3 albedo_0 = vec3(0.0);
	float roughness_0 = 0.0;
	vec3 normal_0 = vec3(0.0);
	float height_0 = 0.0;
	float ao_0 = 0.0;
	float normal_depth_0 = 0.0;
	
	if (blend < 0.999) {
		uint id = ids[0];
		
		int albedo_id = _albedo_remap[id];
		int normal_id = _normal_remap[id];
		uint flags = _flags[id];
		vec3 s = _uv_scales[id];
		
		vec3 Ps = P * s;
		vec3 dPsdx = dPdx * s;
		vec3 dPsdy = dPdy * s;
		
		vec2 y_A = Ps.xz;
		vec2 y_dAdx = dPsdx.xz;
		vec2 y_dAdy = dPsdy.xz;
		
		vec2 y_B = Ps.xz;
		vec2 y_dBdx = dPsdx.xz;
		vec2 y_dBdy = dPsdy.xz;
		
		if (bool(flags & FLAG_STOCHASTIC_OFFSET)) {
			y_A -= offset_A;
			y_B -= offset_B;
		}
		
		if (bool(flags & FLAG_STOCHASTIC_ROTATION)) {
			y_A *= rotation_A;
			y_dAdx *= rotation_A;
			y_dAdy *= rotation_A;
			y_B *= rotation_B;
			y_dBdx *= rotation_B;
			y_dBdy *= rotation_B;
		}
		
		vec4 y_albedo_r_A = textureGrad(_albedo_textures, vec3(y_A, float(albedo_id)), y_dAdx, y_dAdy);
		vec4 y_normal_h_ao_A = textureGrad(_normal_textures, vec3(y_A, float(normal_id)), y_dAdx, y_dAdy);
		y_normal_h_ao_A.rg = fma(y_normal_h_ao_A.rg, vec2(2.0), vec2(-1.0));
		
		vec4 y_albedo_r_B = textureGrad(_albedo_textures, vec3(y_B, float(albedo_id)), y_dBdx, y_dBdy);
		vec4 y_normal_h_ao_B = textureGrad(_normal_textures, vec3(y_B, float(normal_id)), y_dBdx, y_dBdy);
		y_normal_h_ao_B.rg = fma(y_normal_h_ao_B.rg, vec2(2.0), vec2(-1.0));
		
		if (bool(flags & FLAG_STOCHASTIC_ROTATION)) {
			y_normal_h_ao_A.rg *= rotation_A;
			y_normal_h_ao_B.rg *= rotation_B;
		}
		
		float y_bias = dot(y_normal_h_ao_A.rgb - y_albedo_r_B.rgb, vec3(stochastic_blend_bias));
		float y_blend = smoothstep(0.2, 0.8, blend_AB - y_bias); // TODO: add blend sharpness parameter here
			
		vec4 albedo_r = mix(y_albedo_r_A, y_albedo_r_B, y_blend);
		vec4 normal_h_ao = mix(y_normal_h_ao_A, y_normal_h_ao_B, y_blend);
		
		albedo_0 = albedo_r.rgb * _albedo_modulates[id];
		roughness_0 = clamp(albedo_r.a + _roughness_offsets[id], 0.0, 1.0);
		normal_0 = vec3(normal_h_ao.r, 0.0, normal_h_ao.g);
		//normal_0.y = sqrt(1.0 - dot(normal_0.xz, normal_0.xz));
		height_0 = normal_h_ao.b;
		ao_0 = normal_h_ao.a;
		normal_depth_0 = _normal_depths[id];
	}
	
	vec3 albedo_1 = vec3(0.0);
	float roughness_1 = 0.0;
	vec3 normal_1 = vec3(0.0);
	float height_1 = 0.0;
	float ao_1 = 0.0;
	float normal_depth_1 = 0.0;
	
	if (blend > 0.001) {
		uint id = ids[1];
		
		int albedo_id = _albedo_remap[id];
		int normal_id = _normal_remap[id];
		uint flags = _flags[id];
		vec3 s = _uv_scales[id];
		
		vec3 Ps = P * s;
		vec3 dPsdx = dPdx * s;
		vec3 dPsdy = dPdy * s;
		
		vec2 y_A = Ps.xz;
		vec2 y_dAdx = dPsdx.xz;
		vec2 y_dAdy = dPsdy.xz;
		
		vec2 y_B = Ps.xz;
		vec2 y_dBdx = dPsdx.xz;
		vec2 y_dBdy = dPsdy.xz;
		
		if (bool(flags & FLAG_STOCHASTIC_OFFSET)) {
			y_A -= offset_A;
			y_B -= offset_B;
		}
		
		if (bool(flags & FLAG_STOCHASTIC_ROTATION)) {
			y_A *= rotation_A;
			y_dAdx *= rotation_A;
			y_dAdy *= rotation_A;
			y_B *= rotation_B;
			y_dBdx *= rotation_B;
			y_dBdy *= rotation_B;
		}
		
		vec4 y_albedo_r_A = textureGrad(_albedo_textures, vec3(y_A, float(albedo_id)), y_dAdx, y_dAdy);
		vec4 y_normal_h_ao_A = textureGrad(_normal_textures, vec3(y_A, float(normal_id)), y_dAdx, y_dAdy);
		y_normal_h_ao_A.rg = fma(y_normal_h_ao_A.rg, vec2(2.0), vec2(-1.0));
		
		vec4 y_albedo_r_B = textureGrad(_albedo_textures, vec3(y_B, float(albedo_id)), y_dBdx, y_dBdy);
		vec4 y_normal_h_ao_B = textureGrad(_normal_textures, vec3(y_B, float(normal_id)), y_dBdx, y_dBdy);
		y_normal_h_ao_B.rg = fma(y_normal_h_ao_B.rg, vec2(2.0), vec2(-1.0));
		
		if (bool(flags & FLAG_STOCHASTIC_ROTATION)) {
			y_normal_h_ao_A.rg *= rotation_A;
			y_normal_h_ao_B.rg *= rotation_B;
		}
		
		float y_bias = dot(y_normal_h_ao_A.rgb - y_albedo_r_B.rgb, vec3(stochastic_blend_bias));
		float y_blend = smoothstep(0.2, 0.8, blend_AB - y_bias); // TODO: add blend sharpness parameter here
			
		vec4 albedo_r = mix(y_albedo_r_A, y_albedo_r_B, y_blend);
		vec4 normal_h_ao = mix(y_normal_h_ao_A, y_normal_h_ao_B, y_blend);
		
		albedo_1 = albedo_r.rgb * _albedo_modulates[id];
		roughness_1 = clamp(albedo_r.a + _roughness_offsets[id], 0.0, 1.0);
		normal_1 = vec3(normal_h_ao.r, 0.0, normal_h_ao.g);
		//normal_1.y = sqrt(1.0 - dot(normal_1.xz, normal_1.xz));
		height_1 = normal_h_ao.b;
		ao_1 = normal_h_ao.a;
		normal_depth_1 = _normal_depths[id];
	}
	
	// Height-based texture blending
	
	const float amplify = 20.0;
	const float depth = 0.1;
	
	height_0 = fma(height_0 + 0.5, amplify * _height_amplifications[ids[0]], -0.5);
	height_1 = fma(height_1 + 0.5, amplify * _height_amplifications[ids[1]], -0.5);
	
	float value_0 = height_0 + (1.0 - blend);
	float value_1 = height_1 + blend;
	
	float max_height = max(value_0, value_1);
	float relative_height_0 = max(value_0 - max_height + depth, 0.0);
	float relative_height_1 = max(value_1 - max_height + depth, 0.0);
	
	blend = relative_height_1 / (relative_height_0 + relative_height_1);
	
	mat.albedo += mix(albedo_0, albedo_1, blend) * w;
	mat.roughness += mix(roughness_0, roughness_1, blend) * w;
	mat.normal += mix(normal_0, normal_1, blend) * w;
	mat.ao += mix(ao_0, ao_1, blend) * w;
	mat.normal_depth += mix(normal_depth_0, normal_depth_1, blend) * w;
	
	mat.total_weight += w;
	
}

void fragment() {
	ivec3 buffer_size = textureSize(_gradient_buffer, 0);
	
	// LOD selection
	
	vec2 mip_uv = (world_position.xz * vec2(_texels_per_vertex) + 0.5) / vec2(buffer_size.xy);
	float mip_lod = textureQueryLod(_gradient_buffer, mip_uv).y;
	
	float vertex_lod = float(vertex_lod_floor) + vertex_lod_fract;
	
	float lod = clamp(mip_lod + mip_bias, vertex_lod, float(buffer_size.z - 1));
	float lod_0 = floor(lod);
	float lod_1 = lod_0 + 1.0;
	float lod_fract = fract(lod);
	
	vec2 texel_0 = world_position.xz * vec2(_texels_per_vertex) * exp2(-lod_0);
	vec2 texel_1 = texel_0 * 0.5;
	
	// Gradient (normal) lookups
	
	vec2 uv_0 = get_uv(texel_0, vec2(buffer_size.xy));
	vec2 uv_1 = get_uv(texel_1, vec2(buffer_size.xy));
	
	vec2 gradient_0 = texture(_gradient_buffer, vec3(uv_0, lod_0)).rg;
	vec2 gradient_1 = texture(_gradient_buffer, vec3(uv_1, lod_1)).rg;
	vec2 gradient = mix(gradient_0, gradient_1, lod_fract);
	
	gradient /= _vertex_spacing;
	
	// Construct normal from gradient
	
	vec3 normal = normalize(vec3(-gradient.x, 1.0, -gradient.y));
	vec3 tangent = normalize(cross(normal, vec3(0.0, 0.0, 1.0)));
	vec3 binormal = normalize(cross(normal, tangent));
	
	NORMAL = (VIEW_MATRIX * vec4(normal, 0.0)).xyz;
	TANGENT = (VIEW_MATRIX * vec4(tangent, 0.0)).xyz;
	BINORMAL = (VIEW_MATRIX * vec4(binormal, 0.0)).xyz;
	
	// Material accumulation from accumulated texture weights
	
	Material mat = Material(vec3(0.0), 0.0, vec3(0.0), 0.0, 0.0, 0.0);
	
	vec3 P = world_position;
	vec3 dPdx = dFdxCoarse(world_position);
	vec3 dPdy = dFdyCoarse(world_position);
	
	// Triplanar
	
	vec3 power_normal = pow(abs(normal), vec3(triplanar_sharpness));
	power_normal /= dot(power_normal, vec3(1.0));
	
	// Stochastic sampling. 
	// Technique 3 from https://iquilezles.org/articles/texturerepetition/
	
	float random = 8.0 * texture(stochastic_noise, 0.0005 * P.xz).r;
	
	float blend_AB = fract(random);
	blend_AB = 2.0 * min(blend_AB, 1.0 - blend_AB);
	
	float index_A = floor(random + 0.5);
	float index_B = floor(random);
	
	// Coordinate space A
	
	// TODO: use constant table for offsets and angles. Also profile this change.
	
	vec2 offset_A = sin(vec2(3.0, 13.0) * index_A); // TODO: use better hash. Could use constant table.
	float angle_A = 7.0 * index_A; // TODO: use better hash.
	float sin_A = sin(angle_A), cos_A = cos(angle_A);
	mat2 rotation_A = mat2(vec2(cos_A, sin_A), vec2(-sin_A, cos_A));
	
	// Coordinate space B
	
	vec2 offset_B = sin(vec2(3.0, 13.0) * index_B);
	float angle_B = 7.0 * index_B;
	float sin_B = sin(angle_B), cos_B = cos(angle_B);
	mat2 rotation_B = mat2(vec2(cos_B, sin_B), vec2(-sin_B, cos_B));
	
	// Control lookups
	
	vec2 bilinear_uv_0 = get_bilinear_uv(texel_0, vec2(buffer_size.xy));
	vec4 weights_0 = get_bilinear_weights(texel_0) * (1.0 - lod_fract);
	uvec4 controls_0 = floatBitsToUint(textureGather(_control_buffer, vec3(bilinear_uv_0, lod_0), 0).wzxy);
	
	// Texture weight accumulation from control
	
	uvec4 id_0_0 = controls_0 >> uvec4(27u) & uvec4(0x1Fu);
	uvec4 id_1_0 = controls_0 >> uvec4(22u) & uvec4(0x1Fu);
	vec4 blend_0 = vec4(controls_0 >> uvec4(14u) & uvec4(0xFFu)) / 255.0;
	
	uvec2 ids_0[4] = uvec2[4](
		uvec2(id_0_0[0], id_1_0[0]),
		uvec2(id_0_0[1], id_1_0[1]),
		uvec2(id_0_0[2], id_1_0[2]),
		uvec2(id_0_0[3], id_1_0[3])
	);
	
	uint skip = 0u;
	
	// NOTE: since blend is no longer a linear curve, it cannot be lerped well.
	// However, it is possible to combine blend values deterministically with the right structure.
	// The texture accumulation will always be the same for duplicate IDs. The only problem is the blend
	// value is normalized.
	
	// TODO: maybe have a separate blend weight for both ids. Then they can be accumulated separately without
	// normalization, and then it is also possible to define a deterministic blending algorithm.
	
	//for (uint i = 0u; i < 4u; i++) {
		//for (uint j = i + 1u; j < 4u; j++) {
			//bool eq_i_j = ids_0[i] == ids_0[j];
			//
			//float w_i = weights_0[i];
			//float w_j = weights_0[j];
			//
			//float b_i = blend_0[i];
			//float b_j = blend_0[j];
			//
			//float blend = b_i + (b_j - b_i) * w_j / (w_i + w_j);
			//
			//blend_0[i] = eq_i_j ? blend : blend_0[i];
			//
			//weights_0[i] = fma(weights_0[j], float(eq_i_j), weights_0[i]);
			//weights_0[j] *= float(!eq_i_j);
			//
			//skip |= uint(eq_i_j) << j;
		//}
	//}
	
	// This branch is good.
	if (lod_fract > 0.01) {
		vec2 bilinear_uv_1 = get_bilinear_uv(texel_1, vec2(buffer_size.xy));
		vec4 weights_1 = get_bilinear_weights(texel_1) * lod_fract;
		uvec4 controls_1 = floatBitsToUint(textureGather(_control_buffer, vec3(bilinear_uv_1, lod_1), 0).wzxy);
			
		uvec4 id_0_1 = controls_1 >> uvec4(27u) & uvec4(0x1Fu);
		uvec4 id_1_1 = controls_1 >> uvec4(22u) & uvec4(0x1Fu);
		vec4 blend_1 = vec4(controls_1 >> uvec4(14u) & uvec4(0xFFu)) / 255.0;
		
		uvec2 ids_1[4] = uvec2[4](
			uvec2(id_0_1[0], id_1_1[0]),
			uvec2(id_0_1[1], id_1_1[1]),
			uvec2(id_0_1[2], id_1_1[2]),
			uvec2(id_0_1[3], id_1_1[3])
		);
		
		//uint skip_1 = 0u;
		//
		//for (uint i = 0u; i < 3u; i++) {
			//for (uint j = i + 1u; j < 3u; j++) {
				//bool eq_i_j = ids_1[i] == ids_1[j];
			//
				//float w_i = weights_1[i];
				//float w_j = weights_1[j];
				//
				//float b_i = blend_1[i];
				//float b_j = blend_1[j];
				//
				//float blend = b_i + (b_j - b_i) * w_j / (w_i + w_j);
				//
				//blend_1[i] = eq_i_j ? blend : blend_1[i];
				//
				//weights_1[i] = fma(weights_1[j], float(eq_i_j), weights_1[i]);
				//weights_1[j] *= float(!eq_i_j);
				//
				//skip_1 |= uint(eq_i_j) << j;
			//}
		//}
	
		for (uint i = 0u; i < 4u; i++) {
			//if (bool((skip_1 >> i) & 1u))
				//continue;
			accumulate_material(mat, ids_1[i], weights_1[i], blend_1[i], P, dPdx, dPdy, power_normal, offset_A, rotation_A, offset_B, rotation_B, blend_AB);
		}
	}
	
	for (uint i = 0u; i < 4u; i++) {
		//if (bool((skip >> i) & 1u))
			//continue;
		accumulate_material(mat, ids_0[i], weights_0[i], blend_0[i], P, dPdx, dPdy, power_normal, offset_A, rotation_A, offset_B, rotation_B, blend_AB);
	}
		
	
	
	float inv_total_weight = 1.0 / max(mat.total_weight, 1e-5);
	mat.albedo *= inv_total_weight;
	mat.roughness *= inv_total_weight;
	mat.normal_depth *= inv_total_weight;
	mat.normal *= inv_total_weight;
	mat.ao *= inv_total_weight;
	
	// PBR
	
	ALBEDO = mat.albedo;
	ROUGHNESS = mat.roughness;
	NORMAL_MAP = fma(mat.normal.xzy, vec3(0.5), vec3(0.5));
	NORMAL_MAP_DEPTH = mat.normal_depth;
	AO = mat.ao;
	
	//ALBEDO = vec3(duplicate * 0.25);
	
	//ALBEDO = debug_albedo;
}