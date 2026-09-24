shader_type spatial;
render_mode blend_mix, skip_vertex_transform;

/*
TODO:
- Fix gpu sort (increasing max texture count should reduce performance)
- Add height-based blending
- Look at normal-based blending
*/

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
		
	if (blend < 0.99) {
		uint id = ids[0];
		float weight = w * (1.0 - blend);
		
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
		
		//if (bool(flags & FLAG_TRIPLANAR)) {
			//vec2 x_A = -Ps.zy;
			//vec2 x_dAdx = -dPsdx.zy;
			//vec2 x_dAdy = -dPsdy.zy;
			//
			//vec2 x_B = -Ps.zy;
			//vec2 x_dBdx = -dPsdx.zy;
			//vec2 x_dBdy = -dPsdy.zy;
			//
			//vec2 z_A = -Ps.xy;
			//vec2 z_dAdx = -dPsdx.xy;
			//vec2 z_dAdy = -dPsdy.xy;
			//
			//vec2 z_B = -Ps.xy;
			//vec2 z_dBdx = -dPsdx.xy;
			//vec2 z_dBdy = -dPsdy.xy;
			//
			//// NOTE: offsets may have to have their sign flipped for consistency
			//
			//if (bool(flags & FLAG_TRIPLANAR_STOCHASTIC_OFFSET)) {
				//x_A -= offset_A;
				//x_B -= offset_B;
				//
				//z_A -= offset_A;
				//z_B -= offset_B;
			//}
			//
			//if (bool(flags & FLAG_TRIPLANAR_STOCHASTIC_ROTATION)) {
				//x_A *= rotation_A;
				//x_dAdx *= rotation_A;
				//x_dAdy *= rotation_A;
				//x_B *= rotation_B;
				//x_dBdx *= rotation_B;
				//x_dBdy *= rotation_B;
				//
				//z_A *= rotation_A;
				//z_dAdx *= rotation_A;
				//z_dAdy *= rotation_A;
				//z_B *= rotation_B;
				//z_dBdx *= rotation_B;
				//z_dBdy *= rotation_B;
			//}
			//
			//vec4 x_albedo_r_A = textureGrad(_albedo_textures, vec3(x_A, float(albedo_id)), x_dAdx, x_dAdy);
			//vec4 x_normal_h_ao_A = textureGrad(_normal_textures, vec3(x_A, float(normal_id)), x_dAdx, x_dAdy);
			//x_normal_h_ao_A.rg = fma(x_normal_h_ao_A.gr, vec2(2.0), vec2(-1.0));
			//
		    //vec4 x_albedo_r_B = textureGrad(_albedo_textures, vec3(x_B, float(albedo_id)), x_dBdx, x_dBdy);
		    //vec4 x_normal_h_ao_B = textureGrad(_normal_textures, vec3(x_B, float(normal_id)), x_dBdx, x_dBdy);
			//x_normal_h_ao_B.rg = fma(x_normal_h_ao_B.gr, vec2(2.0), vec2(-1.0));
			//
			//vec4 z_albedo_r_A = textureGrad(_albedo_textures, vec3(z_A, float(albedo_id)), z_dAdx, z_dAdy);
			//vec4 z_normal_h_ao_A = textureGrad(_normal_textures, vec3(z_A, float(normal_id)), z_dAdx, z_dAdy);
			//z_normal_h_ao_A.rg = fma(z_normal_h_ao_A.gr, vec2(2.0), vec2(-1.0));
			//
		    //vec4 z_albedo_r_B = textureGrad(_albedo_textures, vec3(z_B, float(albedo_id)), z_dBdx, z_dBdy);
		    //vec4 z_normal_h_ao_B = textureGrad(_normal_textures, vec3(z_B, float(normal_id)), z_dBdx, z_dBdy);
			//z_normal_h_ao_B.rg = fma(z_normal_h_ao_B.gr, vec2(2.0), vec2(-1.0));
			//
			//if (bool(flags & FLAG_TRIPLANAR_STOCHASTIC_ROTATION)) {
				//x_normal_h_ao_A.gr *= rotation_A;
				//x_normal_h_ao_B.gr *= rotation_B;
				//
				//z_normal_h_ao_A.gr *= rotation_A;
				//z_normal_h_ao_B.gr *= rotation_B;
			//}
			//
			//float x_bias = stochastic_blend_bias * dot(x_albedo_r_A.rgb - x_albedo_r_B.rgb, vec3(1.0));
			//float x_blend = smoothstep(0.2, 0.8, blend_AB - x_bias); // TODO: add blend sharpness parameter here
			//
		    //vec4 x_albedo_r = mix(x_albedo_r_A, x_albedo_r_B, x_blend);
			//vec4 x_normal_h_ao = mix(x_normal_h_ao_A, x_normal_h_ao_B, x_blend);
			//
			//float z_bias = stochastic_blend_bias * dot(z_albedo_r_A.rgb - z_albedo_r_B.rgb, vec3(1.0));
			//float z_blend = smoothstep(0.2, 0.8, blend_AB - z_bias); // TODO: add blend sharpness parameter here
			//
		    //vec4 z_albedo_r = mix(z_albedo_r_A, z_albedo_r_B, z_blend);
			//vec4 z_normal_h_ao = mix(z_normal_h_ao_A, z_normal_h_ao_B, z_blend);
			//
			//albedo_r = x_albedo_r * power_normal.x + albedo_r * power_normal.y + z_albedo_r * power_normal.z;
			//normal_h_ao = x_normal_h_ao * power_normal.x + normal_h_ao * power_normal.y + z_normal_h_ao * power_normal.z;
		//}
		
		mat.albedo += albedo_r.rgb * _albedo_modulates[id] * weight;
		mat.roughness += clamp(albedo_r.a + _roughness_offsets[id], 0.0, 1.0) * weight;
		mat.normal_depth += _normal_depths[id] * weight;
		
		vec3 n = vec3(normal_h_ao.r, 0.0, normal_h_ao.g);
		
		mat.normal += n * weight;
		
		mat.ao += normal_h_ao.a * weight;
		
		mat.total_weight += weight;
	}
	
	if (blend > 0.01) {
		uint id = ids[1];
		float weight = w * blend;
		
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
		
		//if (bool(flags & FLAG_TRIPLANAR)) {
			//vec2 x_A = -Ps.zy;
			//vec2 x_dAdx = -dPsdx.zy;
			//vec2 x_dAdy = -dPsdy.zy;
			//
			//vec2 x_B = -Ps.zy;
			//vec2 x_dBdx = -dPsdx.zy;
			//vec2 x_dBdy = -dPsdy.zy;
			//
			//vec2 z_A = -Ps.xy;
			//vec2 z_dAdx = -dPsdx.xy;
			//vec2 z_dAdy = -dPsdy.xy;
			//
			//vec2 z_B = -Ps.xy;
			//vec2 z_dBdx = -dPsdx.xy;
			//vec2 z_dBdy = -dPsdy.xy;
			//
			//// NOTE: offsets may have to have their sign flipped for consistency
			//
			//if (bool(flags & FLAG_TRIPLANAR_STOCHASTIC_OFFSET)) {
				//x_A -= offset_A;
				//x_B -= offset_B;
				//
				//z_A -= offset_A;
				//z_B -= offset_B;
			//}
			//
			//if (bool(flags & FLAG_TRIPLANAR_STOCHASTIC_ROTATION)) {
				//x_A *= rotation_A;
				//x_dAdx *= rotation_A;
				//x_dAdy *= rotation_A;
				//x_B *= rotation_B;
				//x_dBdx *= rotation_B;
				//x_dBdy *= rotation_B;
				//
				//z_A *= rotation_A;
				//z_dAdx *= rotation_A;
				//z_dAdy *= rotation_A;
				//z_B *= rotation_B;
				//z_dBdx *= rotation_B;
				//z_dBdy *= rotation_B;
			//}
			//
			//vec4 x_albedo_r_A = textureGrad(_albedo_textures, vec3(x_A, float(albedo_id)), x_dAdx, x_dAdy);
			//vec4 x_normal_h_ao_A = textureGrad(_normal_textures, vec3(x_A, float(normal_id)), x_dAdx, x_dAdy);
			//x_normal_h_ao_A.rg = fma(x_normal_h_ao_A.gr, vec2(2.0), vec2(-1.0));
			//
		    //vec4 x_albedo_r_B = textureGrad(_albedo_textures, vec3(x_B, float(albedo_id)), x_dBdx, x_dBdy);
		    //vec4 x_normal_h_ao_B = textureGrad(_normal_textures, vec3(x_B, float(normal_id)), x_dBdx, x_dBdy);
			//x_normal_h_ao_B.rg = fma(x_normal_h_ao_B.gr, vec2(2.0), vec2(-1.0));
			//
			//vec4 z_albedo_r_A = textureGrad(_albedo_textures, vec3(z_A, float(albedo_id)), z_dAdx, z_dAdy);
			//vec4 z_normal_h_ao_A = textureGrad(_normal_textures, vec3(z_A, float(normal_id)), z_dAdx, z_dAdy);
			//z_normal_h_ao_A.rg = fma(z_normal_h_ao_A.gr, vec2(2.0), vec2(-1.0));
			//
		    //vec4 z_albedo_r_B = textureGrad(_albedo_textures, vec3(z_B, float(albedo_id)), z_dBdx, z_dBdy);
		    //vec4 z_normal_h_ao_B = textureGrad(_normal_textures, vec3(z_B, float(normal_id)), z_dBdx, z_dBdy);
			//z_normal_h_ao_B.rg = fma(z_normal_h_ao_B.gr, vec2(2.0), vec2(-1.0));
			//
			//if (bool(flags & FLAG_TRIPLANAR_STOCHASTIC_ROTATION)) {
				//x_normal_h_ao_A.gr *= rotation_A;
				//x_normal_h_ao_B.gr *= rotation_B;
				//
				//z_normal_h_ao_A.gr *= rotation_A;
				//z_normal_h_ao_B.gr *= rotation_B;
			//}
			//
			//float x_bias = stochastic_blend_bias * dot(x_albedo_r_A.rgb - x_albedo_r_B.rgb, vec3(1.0));
			//float x_blend = smoothstep(0.2, 0.8, blend_AB - x_bias); // TODO: add blend sharpness parameter here
			//
		    //vec4 x_albedo_r = mix(x_albedo_r_A, x_albedo_r_B, x_blend);
			//vec4 x_normal_h_ao = mix(x_normal_h_ao_A, x_normal_h_ao_B, x_blend);
			//
			//float z_bias = stochastic_blend_bias * dot(z_albedo_r_A.rgb - z_albedo_r_B.rgb, vec3(1.0));
			//float z_blend = smoothstep(0.2, 0.8, blend_AB - z_bias); // TODO: add blend sharpness parameter here
			//
		    //vec4 z_albedo_r = mix(z_albedo_r_A, z_albedo_r_B, z_blend);
			//vec4 z_normal_h_ao = mix(z_normal_h_ao_A, z_normal_h_ao_B, z_blend);
			//
			//albedo_r = x_albedo_r * power_normal.x + albedo_r * power_normal.y + z_albedo_r * power_normal.z;
			//normal_h_ao = x_normal_h_ao * power_normal.x + normal_h_ao * power_normal.y + z_normal_h_ao * power_normal.z;
		//}
		
		mat.albedo += albedo_r.rgb * _albedo_modulates[id] * weight;
		mat.roughness += clamp(albedo_r.a + _roughness_offsets[id], 0.0, 1.0) * weight;
		mat.normal_depth += _normal_depths[id] * weight;
		
		vec3 n = vec3(normal_h_ao.r, 0.0, normal_h_ao.g);
		
		mat.normal += n * weight;
		
		mat.ao += normal_h_ao.a * weight;
		
		mat.total_weight += weight;
	}
	
	
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
	
	// Control lookups
	
	
	
	// Material accumulation from accumulated texture weights
	
	Material mat = Material(vec3(0.0), 0.0, vec3(0.0), 0.0, 0.0, 0.0);
	
	vec3 P = world_position;
	vec3 dPdx = dFdxCoarse(world_position);
	vec3 dPdy = dFdyCoarse(world_position);
	
	// Triplanar
	vec3 power_normal = pow(abs(normal), vec3(triplanar_sharpness));
	power_normal /= dot(power_normal, vec3(1.0));
	
	/* Stochastic sampling
	- A low-frequency noise texture is sampled and scaled to the range (0, 8)
	- Two adjacent indices, A and B, are picked from 0-8 using the noise value
	- These indices are used to seed a random offset and rotation, creating 8
		virtual texture coordinate spaces that cycle with the noise
	- 2 of these coordinate spaces are sampled and blended in accumulate_material()
	
	Implementation notes:
	- The stochastic noise texture should not use mipmaps or else the regions will change with distance
	
	Source: https://iquilezles.org/articles/texturerepetition/, Technique 3
	*/
	
	float random = 8.0 * texture(stochastic_noise, 0.0005 * P.xz).r;
	
	float blend_AB = fract(random);
	blend_AB = 2.0 * min(blend_AB, 1.0 - blend_AB);
	
	float index_A = floor(random + 0.5);
	float index_B = floor(random);
	
	
	// Coordinate space A
	
	vec2 offset_A = sin(vec2(3.0, 13.0) * index_A); // TODO: use better hash. Could use constant table.
	float angle_A = 7.0 * index_A; // TODO: use better hash.
	float sin_A = sin(angle_A), cos_A = cos(angle_A);
	mat2 rotation_A = mat2(vec2(cos_A, sin_A), vec2(-sin_A, cos_A));
	
	// Coordinate space B
	
	vec2 offset_B = sin(vec2(3.0, 13.0) * index_B);
	float angle_B = 7.0 * index_B;
	float sin_B = sin(angle_B), cos_B = cos(angle_B);
	mat2 rotation_B = mat2(vec2(cos_B, sin_B), vec2(-sin_B, cos_B));
	
	
	vec2 bilinear_uv_0 = get_bilinear_uv(texel_0, vec2(buffer_size.xy));
	vec2 bilinear_uv_1 = get_bilinear_uv(texel_1, vec2(buffer_size.xy));
	vec4 weights_0 = get_bilinear_weights(texel_0) * (1.0 - lod_fract);
	vec4 weights_1 = get_bilinear_weights(texel_1) * lod_fract;
	
	uvec4 controls_0 = floatBitsToUint(textureGather(_control_buffer, vec3(bilinear_uv_0, lod_0), 0).wzxy);
	
	
	// Texture weight accumulation from control
	
	vec2 parity = mod(floor(texel_0), 2.0);
	float duplicate = parity.x + 2.0 * parity.y;
	uint d = uint(duplicate);
	
	// NOTE: should not branch due to bilinear samples. Should only branch based on control blend weight.
	
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
	
	for (uint i = 0u; i < 4u; i++) {
		for (uint j = i + 1u; j < 4u; j++) {
			bool eq_i_j = ids_0[i] == ids_0[j];
			
			// There should be a better way to do this.
			float sum = weights_0[i] + weights_0[j];
       		float t = weights_0[j] / sum;
			blend_0[i] = eq_i_j ? mix(blend_0[i], blend_0[j], t) : blend_0[i];
			
			weights_0[i] = fma(weights_0[j], float(eq_i_j), weights_0[i]);
			weights_0[j] *= float(!eq_i_j);
			
			skip |= uint(eq_i_j) << j;
		}
	}
	
	// This branch is good.
	//if (lod_fract > 0.01) {
		//uvec4 controls_1 = floatBitsToUint(textureGather(_control_buffer, vec3(bilinear_uv_1, lod_1), 0).wzxy);
			//
		//uvec4 id_0_1 = controls_1 >> uvec4(27u) & uvec4(0x1Fu);
		//uvec4 id_1_1 = controls_1 >> uvec4(22u) & uvec4(0x1Fu);
		//vec4 blend_1 = vec4(controls_1 >> uvec4(14u) & uvec4(0xFFu)) / 255.0;
		//
		//// This index shit may actually be slower cause of all this indexing
		//uvec4 index = (uvec4(0u, 1u, 2u, 3u) + d) % 4u;
		//
		//uvec2 ids_1[3] = uvec2[3](
			//uvec2(id_0_1[index[1]], id_1_1[index[1]]),
			//uvec2(id_0_1[index[2]], id_1_1[index[2]]),
			//uvec2(id_0_1[index[3]], id_1_1[index[3]])
		//);
		//
		//vec4 dumb_weights1 = weights_1 * lod_fract;
		//
		//vec2 id_weights_1[3] = vec2[3](
			//vec2(dumb_weights1[index[1]], dumb_weights1[index[1]]),
			//vec2(dumb_weights1[index[2]], dumb_weights1[index[2]]),
			//vec2(dumb_weights1[index[3]], dumb_weights1[index[3]])
		//);
		//
		//id_weights_0[d] += vec2(dumb_weights1[index[0]], dumb_weights1[index[0]]);
		//
		//for (uint i = 0u; i < 3u; i++) {
			//for (uint j = i + 1u; j < 3u; j++) {
				//float eq_i_j = float(ids_1[i] == ids_1[j]);
				//id_weights_1[i] += id_weights_1[j] * eq_i_j;
				//id_weights_1[j] *= 1.0 - eq_i_j;
			//}
		//}
	//
		//for (uint i = 0u; i < 3u; i++)
			//accumulate_material(mat, ids_1[i], id_weights_1[i], blend_1[i], P, dPdx, dPdy, power_normal, offset_A, rotation_A, offset_B, rotation_B, blend_AB);
	//}
	
	for (uint i = 0u; i < 4u; i++) {
		if (bool((skip >> i) & 1u))
			continue;
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