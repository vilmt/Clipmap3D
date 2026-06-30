shader_type spatial;
render_mode blend_mix;

#define MAX_TEXTURE_COUNT 32
#define INV_255 0.003921568627450

#define BIT_RANDOMIZE_TRANSLATION (1u << 0u)
#define BIT_RANDOMIZE_ROTATION (1u << 1u)

uniform float lod_blend_ratio: hint_range(0.0, 0.2928932188134525) = 0.2;

// repeat creates toroidal coordinate space
uniform highp sampler2DArray _height_maps: hint_default_black, repeat_enable, filter_nearest;
uniform highp sampler2DArray _gradient_maps: hint_normal, repeat_enable, filter_nearest;
uniform highp sampler2DArray _control_maps: hint_default_black, repeat_enable, filter_nearest;

uniform ivec2 _texels_per_vertex;
uniform vec2 _vertex_spacing;
uniform vec3 _target_position;

varying vec3 world_position;
varying flat int vertex_lod;
varying float lod_blend_mask;
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

/*
TODO: 

SAMPLED USING LOD:
* Heightmap (vertex displacement)

SAMPLED USING MIP:
* Gradient (normals)
* Control map

*/

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// scale and lod from transform
	vec2 scale = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[2].xyz));
	vec2 inv_scale = 1.0 / scale;
	vertex_lod = int(log2(scale.x / _vertex_spacing.x) + 1e-6);
	
	vec2 parity_mask = mod(floor(world_position.xz * inv_scale + 0.5), 2.0);
	
	vec2 inv_texel_scale = inv_scale * vec2(_texels_per_vertex);
	vec2 lod_origin = (world_position.xz - _target_position.xz) * inv_texel_scale;
	
	ivec3 full_size = textureSize(_gradient_maps, 0);
	
	
	vec2 half_size = vec2(full_size.xy / 2 - _texels_per_vertex);
	float blend_mask = length(lod_origin / half_size);
	lod_blend_mask = smoothstep(1.0 - lod_blend_ratio, 1.0, blend_mask);
	lod_blend_mask = vertex_lod >= full_size.z - 1 ? 0.0 : lod_blend_mask; // ensure outer lod does not blend
	
	// geo-morphing offset
	vec2 offset = parity_mask * lod_blend_mask;
	VERTEX.xz += offset;
	world_position.xz += offset * scale;
	
	vec2 height_uv = world_position.xz * inv_texel_scale;
	
	//vec2 i = floor(height_uv);
	//vec2 f = fract(height_uv);
	//vec3 coords = vec3((i + 0.5) / vec2(full_size.xy), float(vertex_lod));
	//vec4 weights = vec2(1.0 - f.x, f.x).xyxy * vec2(1.0 - f.y, f.y).xxyy;
	
	UV = world_position.xz * inv_texel_scale;
	
	vec3 coords = gather_coords(UV, vertex_lod, vec2(full_size.xy));
	vec4 weights = gather_weights(UV);
	
	vec3 s = vec3(1.0 / vec2(full_size.xy), 0.0);
	vec4 heights = vec4(
		texture(_height_maps, coords + s.zzz).r,
		texture(_height_maps, coords + s.xzz).r,
		texture(_height_maps, coords + s.zyz).r,
		texture(_height_maps, coords + s.xyz).r
	);
	
	VERTEX.y = dot(heights, weights);
	world_position.y = VERTEX.y;
	
	
}

void fragment() {
	vec2 size = vec2(textureSize(_height_maps, 0).xy);
	
	//float mip_lod = textureQueryLod(_control_maps, (UV + 0.5) / size).y;
	//
	//float mip_lod_0 = floor(mip_lod);
	//float mip_lod_1 = mip_lod_0 + 1.0;
	//float mip_lod_w = fract(mip_lod);
	
	
	//ALBEDO = vec3(mip_lod) * 0.5;
	
	ALBEDO = vec3(lod_blend_mask);
	
	
	vec3 coords = gather_coords(UV, vertex_lod, size);
	vec4 weights = gather_weights(UV);
	
	
	
	vec4 gradients_r = textureGather(_gradient_maps, coords, 0).wzxy;
	vec4 gradients_g = textureGather(_gradient_maps, coords, 1).wzxy;
	
	float gradient_r = dot(gradients_r, weights);
	float gradient_g = dot(gradients_g, weights);
	
	// calculate normals for 4 corners
	vec3[4] normals;
	for (int i = 0; i < 4; i++) {
		normals[i] = normalize(vec3(-gradients_r[i], 1.0, -gradients_g[i]));
	}
	
	vec3 coords_2;
	vec4 weights_2;
	
	vec2 uv2 = UV * 0.5;
	
	if (lod_blend_mask > 1e-6) {
		coords_2 = gather_coords(uv2, vertex_lod + 1, size);
		weights_2 = gather_weights(uv2);
		
		vec4 gradients_r_2 = textureGather(_gradient_maps, coords_2, 0).wzxy;
		vec4 gradients_g_2 = textureGather(_gradient_maps, coords_2, 1).wzxy;
		
		gradient_r = mix(gradient_r, dot(gradients_r_2, weights_2), lod_blend_mask);
		gradient_g = mix(gradient_g, dot(gradients_g_2, weights_2), lod_blend_mask);
		
		// TODO: calculate normals for these too. Needed for blending later
	}
	
	vec3 normal = normalize(vec3(-gradient_r, 1.0, -gradient_g));
	vec3 tangent = normalize(cross(normal, vec3(0.0, 0.0, 1.0)));
	vec3 binormal = cross(normal, tangent); // perpendicular, no need to normalize
	
	mat3 TNB = mat3(tangent, normal, binormal);
	
	NORMAL = mat3(VIEW_MATRIX) * normal;
	TANGENT = mat3(VIEW_MATRIX) * tangent;
	BINORMAL = mat3(VIEW_MATRIX) * binormal;
	
}