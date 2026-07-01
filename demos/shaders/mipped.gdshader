shader_type spatial;
render_mode blend_mix;

#define MAX_TEXTURE_COUNT 32
#define INV_255 0.003921568627450

#define BIT_RANDOMIZE_TRANSLATION (1u << 0u)
#define BIT_RANDOMIZE_ROTATION (1u << 1u)

uniform bool use_antialiasing = true;

uniform float lod_blend_ratio: hint_range(0.0, 0.2928932188134525) = 0.2;

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

// bilinear coords and weights
vec3 gather_coords(vec2 uv, int lod, vec2 sampler_size) {
	vec2 i = floor(uv);
	return vec3((i + 0.5) / sampler_size, float(lod));
}

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
	int lod = int(round(log2(scale.x / _vertex_spacing.x)));
	
	vec2 parity_mask = mod(floor(world_position.xz * inv_scale + 0.5), 2.0);
	vec2 lod_origin = (world_position.xz - _target_position.xz) * inv_texel_scale;
	
	ivec3 full_size = textureSize(_gradient_buffer, 0);
	vec2 half_size = vec2(full_size.xy / 2 - _texels_per_vertex);
	float blend_mask = length(lod_origin / half_size);
	
	float lod_fract = smoothstep(1.0 - lod_blend_ratio, 1.0, blend_mask);
	lod_fract = lod >= full_size.z - 1 ? 0.0 : lod_fract; // ensure outer lod does not blend
	
	vertex_lod = float(lod) + lod_fract;
	
	// geo-morphing offset
	vec2 offset = parity_mask * lod_fract;
	VERTEX.xz += offset;
	world_position.xz += offset * scale;
	
	UV = world_position.xz * inv_texel_scale;
	
	vec3 coords = gather_coords(UV, lod, vec2(full_size.xy));
	vec4 weights = gather_weights(UV);
	
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

void accumulate(inout Material material, uvec2 ids, vec2 id_weights) {
	
}

void fragment() {
	ivec3 buffer_size = textureSize(_gradient_buffer, 0);
	
	vec2 mip_uv = (world_position.xz * vec2(_texels_per_vertex) + 0.5) / vec2(buffer_size.xy);
	float mip_lod = textureQueryLod(_gradient_buffer, mip_uv).y;
	
	if (!use_antialiasing) mip_lod = vertex_lod;
	
	float lod = clamp(mip_lod, vertex_lod, float(buffer_size.z - 1));
	
	// Lod 0 gradient
	int lod_0 = int(lod);
	vec2 uv_0 = world_position.xz * vec2(_texels_per_vertex) / float(1 << lod_0);
	vec3 coords_0 = gather_coords(uv_0, lod_0, vec2(buffer_size.xy));
	vec4 weights_0 = gather_weights(uv_0);
	vec2 gradient_0 = vec2(
		dot(textureGather(_gradient_buffer, coords_0, 0).wzxy, weights_0),
		dot(textureGather(_gradient_buffer, coords_0, 1).wzxy, weights_0)
	);
	
	// Lod 1 gradient
	int lod_1 = lod_0 + 1;
	vec2 uv_1 = uv_0 * 0.5;
	vec3 coords_1 = gather_coords(uv_1, lod_1, vec2(buffer_size.xy));
	vec4 weights_1 = gather_weights(uv_1);
	vec2 gradient_1 = vec2(
		dot(textureGather(_gradient_buffer, coords_1, 0).wzxy, weights_1),
		dot(textureGather(_gradient_buffer, coords_1, 1).wzxy, weights_1)
	);
	
	float lod_blend = fract(lod);
	
	vec2 gradient = mix(gradient_0, gradient_1, lod_blend);
	
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
	
	uvec4 controls_0 = floatBitsToUint(textureGather(_control_buffer, coords_0, 0).wzxy);
	uvec4 id_0_0 = controls_0 >> uvec4(27u) & uvec4(0x1Fu);
	uvec4 id_0_1 = controls_0 >> uvec4(22u) & uvec4(0x1Fu);
	vec4 weights_id_1 = vec4(controls_0 >> uvec4(14u) & uvec4(0xFFu)) * INV_255;
	vec4 weights_id_0 = 1.0 - weights_id_1;
	weights_id_0 *= weights_0;
	weights_id_1 *= weights_0;
	
	// Same thing for lod 1.
	uvec4 controls_1 = floatBitsToUint(textureGather(_control_buffer, coords_1, 0).wzxy);
	uvec4 id_1_0 = controls_1 >> uvec4(27u) & uvec4(0x1Fu);
	uvec4 id_1_1 = controls_1 >> uvec4(22u) & uvec4(0x1Fu);
	
	
	//ALBEDO = vec3(lod_blend);
	
}