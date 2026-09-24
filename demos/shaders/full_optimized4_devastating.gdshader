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

uniform bool enable = true;
uniform bool show_texels = true;
uniform bool show_grid_mask = true;


uniform sampler2D stochastic_noise: filter_linear;
uniform float stochastic_blend_bias = 0.1; // TODO: should be material parameter

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
	
	debug_albedo = sin(vec3(lod_floor) * 70.0) * 0.5 + 0.5;
	
	/* LOD Geo-morphing
	- Without any consideration for the transition regions between the clipmap rings N and N+1, there
		will be seams on vertices with odd parity since N has 4x more vertex density than N+1
	- To remove the seams, N must reduce its density to match N+1 in transition regions
	- It is possible to do this without moving N's vertices on the XZ axes. In transition regions, vertices
		with odd parity can simply interpolate between neighboring vertices, producing the same value as N+1
		- However, this would be a form of discrete LOD since the vertices in transition regions either
			match N+1 or not. Discrete LOD causes popping artifacts. We are after smooth LOD.
	- Instead, by moving N's vertices on the XZ axes, N's mesh can be directly morphed into N+1's mesh
	
	Implementation notes:
	- It is important that the offset is also added into the sampling coordinates
	*/
	
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

void accumulate_material(inout Material mat, uint id, float weight, vec3 P, vec3 dPdx, vec3 dPdy, vec3 power_normal,
	vec2 offset_A, mat2 rotation_A, vec2 offset_B, mat2 rotation_B, float blend_AB) {
		
	if (weight < 0.01)
		return;
	
	int albedo_id = _albedo_remap[id];
	int normal_id = _normal_remap[id];
	uint flags = _flags[id];
	vec3 s = _uv_scales[id];
	
	P *= s;
	dPdx *= s;
	dPdy *= s;
	
	vec2 y_A = P.xz;
	vec2 y_dAdx = dPdx.xz;
	vec2 y_dAdy = dPdy.xz;
	
	vec2 y_B = P.xz;
	vec2 y_dBdx = dPdx.xz;
	vec2 y_dBdy = dPdy.xz;
	
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
	
	mat.albedo += albedo_r.rgb * _albedo_modulates[id] * weight;
	mat.roughness += clamp(albedo_r.a + _roughness_offsets[id], 0.0, 1.0) * weight;
	mat.normal_depth += _normal_depths[id] * weight;
	
	vec3 n = vec3(normal_h_ao.r, 0.0, normal_h_ao.g);
	
	mat.normal += n * weight;
	
	mat.ao += normal_h_ao.a * weight;
	
	mat.total_weight += weight;
}

// TODO: optimize
vec2 geomorph(vec2 texel, float mask) {
	float x_f = texel.x * 0.5;
        
    float x_fl = floor(x_f);
    float x_fr = fract(x_f);
	
	if (x_fr - (0.5 + 0.5 * mask) > 0.0) {
        // uv is above the mask
        texel.x += -2.0 * x_fr + 1.0 + (x_fr - (0.5 + mask * 0.5)) / (0.5 - mask * 0.5);
    } else {
        // uv is below the mask
        texel.x += -2.0 * x_fr + x_fr / (0.5 + mask * 0.5);
    }
	
	float y_f = texel.y * 0.5;
    
    float y_fl = floor(y_f);
    float y_fr = fract(y_f);
	
	if (y_fr - (0.5 + 0.5 * mask) > 0.0) {
        // uv is above the mask
        texel.y += -2.0 * y_fr + 1.0 + (y_fr - (0.5 + mask * 0.5)) / (0.5 - mask * 0.5);
    } else {
        // uv is below the mask
        texel.y += -2.0 * y_fr + y_fr / (0.5 + mask * 0.5);
    }
	
	return texel;
}

vec2 inverse_geomorph(vec2 morphed_texel, float mask) {
	return morphed_texel + mask * (1.0 - abs(2.0 * fract(0.5 * morphed_texel) - 1.0));
}

void fragment() {
	ivec3 buffer_size = textureSize(_gradient_buffer, 0);
	
	/* LOD selection and trilinear sampling coordinates
	- In the fragment shader, it is important that the LOD used to sample the control and normal buffers
		increases further away from the camera to reduce aliasing
	- Just using the vertex LOD (further clipmap rings have less detail) is not sufficient in attenuating
		aliasing artifacts, especially with higher texels_per_vertex values
	- Using textureQueryLod(), we can directly get the LOD that the texture filtering hardware would have
		used when performing trilinear filtering on a regular texture
	- Then, by using max(mip LOD, vertex LOD) instead of just the vertex LOD, we avoid using the vertex LOD
		on fragments where it would likely cause aliasing
	
	Implementation notes:
	- The LOD must be clamped to not exceed the buffer size
	*/
	
	vec2 mip_uv = (world_position.xz * vec2(_texels_per_vertex) + 0.5) / vec2(buffer_size.xy);
	float mip_lod = textureQueryLod(_gradient_buffer, mip_uv).y;
	
	float vertex_lod = float(vertex_lod_floor) + vertex_lod_fract;
	
	float lod = clamp(mip_lod + mip_bias, vertex_lod, float(buffer_size.z - 1));
	float lod_floor = floor(lod);
	float lod_fract = fract(lod);
	
	vec2 texel = world_position.xz * vec2(_texels_per_vertex) * exp2(-lod_floor);
	
	// Gradient (normal) lookups
	
	vec2 uv = get_uv(texel, vec2(buffer_size.xy));
	
	
	// NOTE: it should be possible to do this in one sample, since we are using bilinear position.
	// This transformation is nonlinear though, which may make this difficult.
	
	// Ok, this will probably not work. Next optimization: reduce control fetches from 8 -> 7, still pretty good.
	
	vec2 texel_morphed = geomorph(texel, lod_fract);
	//
	vec2 corner_0_0 = inverse_geomorph(floor(texel_morphed) + vec2(0.0, 0.0), lod_fract);
	vec2 corner_1_0 = inverse_geomorph(floor(texel_morphed) + vec2(1.0, 0.0), lod_fract);
	vec2 corner_0_1 = inverse_geomorph(floor(texel_morphed) + vec2(0.0, 1.0), lod_fract);
	vec2 corner_1_1 = inverse_geomorph(floor(texel_morphed) + vec2(1.0, 1.0), lod_fract);
	
	// dx0 == dx1, dy0 == dy1. This transformation is affine.
	vec2 dx0 = corner_1_0 - corner_0_0;
	vec2 dx1 = corner_1_1 - corner_0_1;
	vec2 dy0 = corner_0_1 - corner_0_0;
	vec2 dy1 = corner_1_1 - corner_1_0;
	
	vec2 uv_0_0 = get_uv(corner_0_0, vec2(buffer_size.xy));
	vec2 uv_1_0 = get_uv(corner_1_0, vec2(buffer_size.xy));
	vec2 uv_0_1 = get_uv(corner_0_1, vec2(buffer_size.xy));
	vec2 uv_1_1 = get_uv(corner_1_1, vec2(buffer_size.xy));
	
	vec4 bilinear_weights = get_bilinear_weights(texel_morphed);
	
	// Not using texel centers. We are basically taking 4 bilinear samples and doing bilinear interp on them again.
	vec2 grad_0_0 = texture(_gradient_buffer, vec3(uv_0_0, lod_floor)).rg;
	vec2 grad_1_0 = texture(_gradient_buffer, vec3(uv_1_0, lod_floor)).rg;
	vec2 grad_0_1 = texture(_gradient_buffer, vec3(uv_0_1, lod_floor)).rg;
	vec2 grad_1_1 = texture(_gradient_buffer, vec3(uv_1_1, lod_floor)).rg;
	
	// This will not work in the current state because coordinates are not centered on texels 
	//if (use_texelfetch) {
		//grad_0_0 = texelFetch(_gradient_buffer, ivec3(ivec2(corner_0_0) % buffer_size.xy, int(lod_floor)), 0).rg;
		//grad_1_0 = texelFetch(_gradient_buffer, ivec3(ivec2(corner_1_0) % buffer_size.xy, int(lod_floor)), 0).rg;
		//grad_0_1 = texelFetch(_gradient_buffer, ivec3(ivec2(corner_0_1) % buffer_size.xy, int(lod_floor)), 0).rg;
		//grad_1_1 = texelFetch(_gradient_buffer, ivec3(ivec2(corner_1_1) % buffer_size.xy, int(lod_floor)), 0).rg;
	//}
	//
	vec2 gradient = vec2(
		dot(vec4(grad_0_0.x, grad_1_0.x, grad_0_1.x, grad_1_1.x), bilinear_weights),
		dot(vec4(grad_0_0.y, grad_1_0.y, grad_0_1.y, grad_1_1.y), bilinear_weights)
	);
	
	if (enable)
	gradient = texture(_gradient_buffer, vec3(get_uv(texel, vec2(buffer_size.xy)), lod_floor)).rg;
	
	
	// Sample normals on vertex scale
	//vec3 normal_0 = texture(_gradient_buffer)
	
	gradient /= _vertex_spacing;
	
	//gradient *= 2.0;
	
	// Construct normal from gradient
	
	vec3 normal = normalize(vec3(-gradient.x, 1.0, -gradient.y));
	vec3 tangent = normalize(cross(normal, vec3(0.0, 0.0, 1.0)));
	vec3 binormal = normalize(cross(normal, tangent));
	
	NORMAL = (VIEW_MATRIX * vec4(normal, 0.0)).xyz;
	TANGENT = (VIEW_MATRIX * vec4(tangent, 0.0)).xyz;
	BINORMAL = (VIEW_MATRIX * vec4(binormal, 0.0)).xyz;
	
	/* Control lookups
	Control values are actually bitfields, not floats, so they should not be sampled using a linear
	filter. Rather, the closest 4 texels are sampled and the data derived from the bitfield can then
	be manually interpolated.
	
	Implementation notes
	- textureGather() is convenient for sampling the .r channel of the closest four texels
	- The .wzxy swizzle arranges the values into the standard (0, 0), (1, 0), (0, 1), (1, 1) order
	*/ 
	
	vec2 bilinear_uv_0 = get_bilinear_uv(texel, vec2(buffer_size.xy));
	vec4 weights_0 = get_bilinear_weights(texel);
	
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
	
	uvec4 controls_0 = floatBitsToUint(textureGather(_control_buffer, vec3(bilinear_uv_0, lod_floor), 0).wzxy);
	
	// Texture weight accumulation from control
	
	uvec4 id_0_0 = controls_0 >> uvec4(27u) & uvec4(0x1Fu);
	uvec4 id_1_0 = controls_0 >> uvec4(22u) & uvec4(0x1Fu);
	vec4 weights_id_1_0 = vec4(controls_0 >> uvec4(14u) & uvec4(0xFFu)) / 255.0;
	vec4 weights_id_0_0 = 1.0 - weights_id_1_0;
	weights_id_0_0 *= weights_0;// * (1.0 - lod_fract);
	weights_id_1_0 *= weights_0;// * (1.0 - lod_fract);
	
	uvec2 ids_0[4] = uvec2[4](
		uvec2(id_0_0[0], id_1_0[0]),
		uvec2(id_0_0[1], id_1_0[1]),
		uvec2(id_0_0[2], id_1_0[2]),
		uvec2(id_0_0[3], id_1_0[3])
	);
	
	vec2 id_weights_0[4] = vec2[4](
		vec2(weights_id_0_0[0], weights_id_1_0[0]),
		vec2(weights_id_0_0[1], weights_id_1_0[1]),
		vec2(weights_id_0_0[2], weights_id_1_0[2]),
		vec2(weights_id_0_0[3], weights_id_1_0[3])
	);
	
	for (uint i = 0u; i < 4u; i++) {
		for (uint j = i + 1u; j < 4u; j++) {
			// TODO: add a bitmask to skip the samples entirely.
			float eq_i_j = float(ids_0[i] == ids_0[j]);
			id_weights_0[i] += id_weights_0[j] * eq_i_j;
			id_weights_0[j] *= 1.0 - eq_i_j;
		}
	}
	
	for (uint i = 0u; i < 4u; i++) {
		accumulate_material(mat, ids_0[i].x, id_weights_0[i].x, P, dPdx, dPdy, power_normal, offset_A, rotation_A, offset_B, rotation_B, blend_AB);
		accumulate_material(mat, ids_0[i].y, id_weights_0[i].y, P, dPdx, dPdy, power_normal, offset_A, rotation_A, offset_B, rotation_B, blend_AB);
	}
	
	// This is good, but it feels like the sampling strategy could be smarter. We already have a bilinear blend, so maybe the sampling points themselves
	// could be morphed at lod boundaries, similarly to the height sampling. Also, try to use projection. It is better than triplanar in every way.
	
	// Normalize accumulated material
	
	float inv_total_weight = 1.0 / max(mat.total_weight, 1e-5);
	mat.albedo *= inv_total_weight;
	mat.roughness *= inv_total_weight;
	mat.normal_depth *= inv_total_weight;
	mat.normal *= inv_total_weight;
	mat.ao *= inv_total_weight;
	
	// PBR
	
	//ALBEDO = mat.albedo;
	//ROUGHNESS = mat.roughness;
	//NORMAL_MAP = fma(mat.normal.xzy, vec3(0.5), vec3(0.5));
	//NORMAL_MAP_DEPTH = mat.normal_depth;
	//AO = mat.ao;
	
	ALBEDO = vec3(1.0);
	
	if (show_texels) {
		
		ALBEDO = vec3(0.0);
		ALBEDO.r = smoothstep(0.11, 0.1, length(texel - corner_0_0));
		ALBEDO.r = max(ALBEDO.r, smoothstep(0.11, 0.1, length(texel - corner_1_0)));
		ALBEDO.r = max(ALBEDO.r, smoothstep(0.11, 0.1, length(texel - corner_0_1)));
		ALBEDO.r = max(ALBEDO.r, smoothstep(0.11, 0.1, length(texel - corner_1_1)));
		vec2 grid2 = abs(2.0 * fract(texel_morphed - 0.5) - 1.0);
		float grid = min(grid2.x, grid2.y);
		
		ALBEDO.r = max(ALBEDO.r, smoothstep(0.05, 0.0, grid));
		if (show_grid_mask) {
			ALBEDO.r = grid2.y;
			ALBEDO.r = fract(texel_morphed.y);
			//ALBEDO = vec3(0.0);
		}
			
			//ALBEDO.r = grid2.y;
			//ALBEDO.r = fract(texel_0.y * 0.5) * lod_fract;
			//ALBEDO.r = lod_fract * mod(floor(texel_0.y), 2.0) * (1.0 - fract(texel_0.y));
			//ALBEDO.r = fract(texel_shifted.y);
		
		//ALBEDO.b = get_texel_parity_smooth2(texel_0).y * lod_fract;
	}
	
	//ALBEDO.g = 0.0;
	
	//ALBEDO = vec3(geomorph_amount.y, 0.0, 0.0);
	
	//ALBEDO.r = get_texel_parity(floor(texel_0)).y;
	//if (use_offset) {
		//ALBEDO.r = get_texel_parity_smooth(texel_0).y;
	//}
}