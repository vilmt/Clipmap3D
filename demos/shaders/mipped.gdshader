shader_type spatial;
render_mode blend_mix;

// BUG: small seams everywhere, seems like precision issue

#define MAX_TEXTURE_COUNT 32
#define INV_255 0.003921568627450
#define ALBEDO_DEFAULT vec4(0.8, 0.8, 0.8, 1.0)
#define NORMAL_DEFAULT vec4(0.5, 0.5, 1.0, 1.0)

#define BIT_RANDOMIZE_TRANSLATION (1u << 0u)
#define BIT_RANDOMIZE_ROTATION (1u << 1u)

uniform bool use_antialiasing = true;

uniform float lod_blend_ratio: hint_range(0.0, 0.2928932188134525) = 0.2;

group_uniforms private;
// densely packed, access using remap index
// RGB: Albedo, A: Roughness
uniform sampler2DArray _albedo_textures: source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform int[MAX_TEXTURE_COUNT] _albedo_remap;
// RG: Normal (OpenGL), B: Height, A: Ambient Occlusion
uniform sampler2DArray _normal_textures: hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform int[MAX_TEXTURE_COUNT] _normal_remap;

// fixed size, access using texture index
uniform vec2[MAX_TEXTURE_COUNT] _uv_scales;
uniform vec3[MAX_TEXTURE_COUNT] _albedo_modulates: source_color;
uniform float[MAX_TEXTURE_COUNT] _roughness_offsets;
uniform float[MAX_TEXTURE_COUNT] _normal_depths;
uniform uint[MAX_TEXTURE_COUNT] _flags;

// repeat creates toroidal coordinate space
uniform highp sampler2DArray _height_buffer: hint_default_black, repeat_enable, filter_nearest;
uniform highp sampler2DArray _gradient_buffer: hint_normal, repeat_enable, filter_nearest;
uniform highp sampler2DArray _control_buffer: hint_default_black, repeat_enable, filter_nearest;

uniform ivec2 _texels_per_vertex;
uniform vec2 _vertex_spacing;
uniform vec3 _target_position;

varying vec3 world_position;
varying float vertex_lod;
varying vec3 debug_albedo;

// Bilinear texture coordinates
vec3 gather_coords(vec2 uv, float lod, vec2 sampler_size) {
	vec2 i = floor(uv);
	return vec3((i + 0.5) / sampler_size, lod);
}

// Bilinear texture weights
vec4 gather_weights(vec2 uv) {
	vec2 w = fract(uv);
	return vec2(1.0 - w.x, w.x).xyxy * vec2(1.0 - w.y, w.y).xxyy;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// scale and lod from transform
	vec2 scale = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[2].xyz));
	vec2 inv_scale = 1.0 / scale;
	vec2 inv_texel_scale = inv_scale * vec2(_texels_per_vertex);
	float lod_floor = round(log2(scale.x / _vertex_spacing.x));
	
	vec2 parity_mask = mod(floor(world_position.xz * inv_scale + 0.5), 2.0);
	vec2 lod_origin = (world_position.xz - _target_position.xz) * inv_texel_scale;
	
	ivec3 full_size = textureSize(_gradient_buffer, 0);
	vec2 half_size = vec2(full_size.xy / 2 - _texels_per_vertex);
	float blend_mask = length(lod_origin / half_size);
	
	float lod_fract = smoothstep(1.0 - lod_blend_ratio, 1.0, blend_mask);
	lod_fract = int(lod_floor) >= full_size.z - 1 ? 0.0 : lod_fract; // ensure outer lod_floor does not blend
	
	vertex_lod = lod_floor + lod_fract;
	
	// geo-morphing offset
	vec2 offset = parity_mask * lod_fract;
	VERTEX.xz += offset;
	world_position.xz += offset * scale;
	
	vec2 uv = world_position.xz * inv_texel_scale;
	
	vec3 coords = gather_coords(uv, lod_floor, vec2(full_size.xy));
	vec4 weights = gather_weights(uv);
	
	// TODO: try texelFetch with imod
	vec3 s = vec3(1.0 / vec2(full_size.xy), 0.0);
	vec4 heights = vec4(
		texture(_height_buffer, coords + s.zzz).r,
		texture(_height_buffer, coords + s.xzz).r,
		texture(_height_buffer, coords + s.zyz).r,
		texture(_height_buffer, coords + s.xyz).r
	);
	
	VERTEX.y = dot(heights, weights);
	world_position.y = VERTEX.y;
}

struct Material {
	vec3 albedo;
	float roughness;
	
	vec3 normal;
	float normal_depth;
	float ao;
	float total_weight;
};

void accumulate(inout Material mat, uint id, float id_weight) {
	vec2 uv = world_position.xz * _uv_scales[id];
	// TODO: stochastic sampler based directly on world position. Do not make it dependent on LOD.
	
	// Neighboring samples are already bilinearly interpolated. This would be very useful for texture bombing / projection.
	// However, relying on this is a bad idea since LODs do not have consistent projection.
	// Rather, should use some sort of global method based on the blended normal.
	// Such a global coordinate space would also allow for a consistent stochastic sampler.
	
	int albedo_id = _albedo_remap[id];
	vec4 albedo_r = albedo_id == -1 ? ALBEDO_DEFAULT : texture(_albedo_textures, vec3(uv, float(albedo_id)));
	
	int normal_id = _normal_remap[id];
	vec4 normal_h_ao = normal_id == -1 ? NORMAL_DEFAULT : texture(_normal_textures, vec3(uv, float(normal_id)));
		
	mat.albedo += albedo_r.rgb * _albedo_modulates[id] * id_weight;
	mat.roughness += clamp(albedo_r.a + _roughness_offsets[id], 0.0, 1.0) * id_weight;
	mat.normal_depth += _normal_depths[id] * id_weight;
	
	vec3 n = vec3(normal_h_ao.r, 0.0, normal_h_ao.g) * 2.0 - 1.0;
	n.y = sqrt(1.0 - dot(n.xz, n.xz));
	
	mat.normal += n * id_weight;
	
	mat.ao += normal_h_ao.a * id_weight;
	
	mat.total_weight += id_weight;
}

void combine(uint id, float weight, inout uint ids[8], inout float weights[8], inout int count) {
	// If found, add to existing weight.
	for (int i = 0; i < count; i++) {
		if (ids[i] == id) {
			weights[i] += weight;
			return;
		}
	}
	
	// If not found, initialize.
	ids[count] = id;
	weights[count] = weight;
	count++;
}

void fragment() {
	ivec3 buffer_size = textureSize(_gradient_buffer, 0);
	
	vec2 mip_uv = (world_position.xz * vec2(_texels_per_vertex) + 0.5) / vec2(buffer_size.xy);
	float mip_lod = textureQueryLod(_gradient_buffer, mip_uv).y;
	
	if (!use_antialiasing) mip_lod = vertex_lod;
	
	float lod = clamp(mip_lod, vertex_lod, float(buffer_size.z - 1)) + 1e-5;
	
	// Lod 0 gradient
	float lod_0 = floor(lod);
	vec2 uv_0 = world_position.xz * vec2(_texels_per_vertex) * exp2(-lod_0);
	vec3 coords_0 = gather_coords(uv_0, lod_0, vec2(buffer_size.xy));
	vec4 weights_0 = gather_weights(uv_0);
	vec2 gradient_0 = vec2(
		dot(textureGather(_gradient_buffer, coords_0, 0).wzxy, weights_0),
		dot(textureGather(_gradient_buffer, coords_0, 1).wzxy, weights_0)
	);
	
	// Lod 1 gradient
	float lod_1 = lod_0 + 1.0;
	vec2 uv_1 = uv_0 * 0.5;
	vec3 coords_1 = gather_coords(uv_1, lod_1, vec2(buffer_size.xy));
	vec4 weights_1 = gather_weights(uv_1);
	vec2 gradient_1 = vec2(
		dot(textureGather(_gradient_buffer, coords_1, 0).wzxy, weights_1),
		dot(textureGather(_gradient_buffer, coords_1, 1).wzxy, weights_1)
	);
	
	float lod_fract = fract(lod);

	vec2 gradient = mix(gradient_0, gradient_1, lod_fract);
	
	//vec3[4] normals;
	//for (int i = 0; i < 4; i++) {
		//normals[i] = normalize(vec3(-gradients_r[i], 1.0, -gradients_g[i]));
	//}
	
	vec3 normal = normalize(vec3(-gradient.x, 1.0, -gradient.y));
	vec3 tangent = normalize(cross(normal, vec3(0.0, 0.0, 1.0)));
	vec3 binormal = cross(normal, tangent); // perpendicular, no need to normalize
	
	mat3 TNB = mat3(tangent, normal, binormal);
	
	NORMAL = mat3(VIEW_MATRIX) * normal;
	TANGENT = mat3(VIEW_MATRIX) * tangent;
	BINORMAL = mat3(VIEW_MATRIX) * binormal;
	
	Material mat = Material(vec3(0.0), 0.0, vec3(0.0), 0.0, 0.0, 0.0);
	
	// Lod 0 control
	uvec4 controls_0 = floatBitsToUint(textureGather(_control_buffer, coords_0, 0).wzxy);
	uvec4 id_0_0 = controls_0 >> uvec4(27u) & uvec4(0x1Fu);
	uvec4 id_0_1 = controls_0 >> uvec4(22u) & uvec4(0x1Fu);
	// Start with texture blend weight
	vec4 weights_id_0_1 = vec4(controls_0 >> uvec4(14u) & uvec4(0xFFu)) * INV_255;
	vec4 weights_id_0_0 = 1.0 - weights_id_0_1;
	// Apply bilinear weight and LOD weight
	weights_id_0_0 *= weights_0 * (1.0 - lod_fract);
	weights_id_0_1 *= weights_0 * (1.0 - lod_fract);
	
	uint ids[8];
	float weights[8];
	int count = 0;
	
	//combine(id_0_0.x)
	
	accumulate(mat, id_0_0.x, weights_id_0_0.x);
	accumulate(mat, id_0_1.x, weights_id_0_1.x);
	
	accumulate(mat, id_0_0.y, weights_id_0_0.y);
	accumulate(mat, id_0_1.y, weights_id_0_1.y);
	
	accumulate(mat, id_0_0.z, weights_id_0_0.z);
	accumulate(mat, id_0_1.z, weights_id_0_1.z);
	
	accumulate(mat, id_0_0.w, weights_id_0_0.w);
	accumulate(mat, id_0_1.w, weights_id_0_1.w);
	
	// Lod 1 control
	uvec4 controls_1 = floatBitsToUint(textureGather(_control_buffer, coords_1, 0).wzxy);
	uvec4 id_1_0 = controls_1 >> uvec4(27u) & uvec4(0x1Fu);
	uvec4 id_1_1 = controls_1 >> uvec4(22u) & uvec4(0x1Fu);
	// Start with texture blend weight
	vec4 weights_id_1_1 = vec4(controls_1 >> uvec4(14u) & uvec4(0xFFu)) * INV_255;
	vec4 weights_id_1_0 = 1.0 - weights_id_1_1;
	// Apply bilinear weight and LOD weight
	weights_id_1_0 *= weights_1 * lod_fract;
	weights_id_1_1 *= weights_1 * lod_fract;
	
	accumulate(mat, id_1_0.x, weights_id_1_0.x);
	accumulate(mat, id_1_1.x, weights_id_1_1.x);
	
	accumulate(mat, id_1_0.y, weights_id_1_0.y);
	accumulate(mat, id_1_1.y, weights_id_1_1.y);
	
	accumulate(mat, id_1_0.z, weights_id_1_0.z);
	accumulate(mat, id_1_1.z, weights_id_1_1.z);
	
	accumulate(mat, id_1_0.w, weights_id_1_0.w);
	accumulate(mat, id_1_1.w, weights_id_1_1.w);
	
	float inv_w = 1.0 / max(mat.total_weight, 1e-6);
	mat.albedo *= inv_w;
	mat.roughness *= inv_w;
	mat.normal *= inv_w;
	mat.ao *= inv_w;
	
	ALBEDO = mat.albedo;
	ROUGHNESS = mat.roughness;
	NORMAL_MAP = fma(mat.normal.xzy, vec3(0.5), vec3(0.5));
	NORMAL_MAP_DEPTH = mat.normal_depth;
	AO = mat.ao;
	
}