shader_type spatial;
render_mode blend_mix;

/*
Clipmap3D Grid Shader

Vertices undergoing LOD blending are susceptible to shimmering artifacts
since degenerate triangles cause bad dFdx/dFdy transitions. 

*/

// Options
#define USE_PROJECTION
#define USE_CIRCLE_MASK
#define ALBEDO_DEFAULT vec4(0.8, 0.8, 0.8, 1.0)
#define NORMAL_DEFAULT vec4(0.5, 0.5, 1.0, 1.0)

// Don't change
#define MAX_TEXTURE_COUNT 32
#define INV_255 0.003921568627450
#define EPSILON 1e-6

#ifdef USE_CIRCLE_MASK
// ratio must be smaller than 1.0 - sqrt(2.0) / 2.0 to avoid lod overlap
uniform float lod_blend_ratio: hint_range(0.0, 0.2928932188134525) = 0.2;
#else
uniform float lod_blend_ratio: hint_range(0.0, 0.4) = 0.2;
#endif

group_uniforms private;
// densely packed, access using remap index
// RGB: Albedo, A: Roughness
uniform sampler2DArray _albedo_textures: source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform int[MAX_TEXTURE_COUNT] _albedo_remap;
// RG: Normal (OpenGL), B: Height, A: Ambient Occlusion
uniform sampler2DArray _normal_textures: hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform int[MAX_TEXTURE_COUNT] _normal_remap;

#define BIT_RANDOMIZE_TRANSLATION (1u << 0u)
#define BIT_RANDOMIZE_ROTATION (1u << 1u)

// fixed size, access using texture index
uniform vec2[MAX_TEXTURE_COUNT] _uv_scales;
uniform vec3[MAX_TEXTURE_COUNT] _albedo_modulates: source_color;
uniform float[MAX_TEXTURE_COUNT] _roughness_offsets;
uniform float[MAX_TEXTURE_COUNT] _normal_depths;
uniform uint[MAX_TEXTURE_COUNT] _flags;

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

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// scale and lod from transform
	vec2 scale = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[2].xyz));
	vec2 inv_scale = 1.0 / scale;
	vertex_lod = int(log2(scale.x / _vertex_spacing.x) + EPSILON);
	
	vec2 even_mask = mod(floor(world_position.xz * inv_scale + 0.5), 2.0);
	
	vec2 inv_texel_scale = inv_scale * vec2(_texels_per_vertex);
	vec2 lod_origin = (world_position.xz - _target_position.xz) * inv_texel_scale;
	
	vec2 half_size = vec2(textureSize(_height_maps, 0).xy / 2 - _texels_per_vertex);
	float blend_mask;
	#ifdef USE_CIRCLE_MASK
	blend_mask = length(lod_origin / half_size);
	#else
	vec2 square = abs(lod_origin / half_size);
	blend_mask = max(square.x, square.y);
	#endif
	lod_blend_mask = smoothstep(1.0 - lod_blend_ratio, 1.0, blend_mask);
	
	lod_blend_mask *= float((vertex_lod + 1) < textureSize(_height_maps, 0).z);
	
	// geo-morphing offset
	vec2 offset = even_mask * lod_blend_mask;
	VERTEX.xz += offset;
	world_position.xz += offset * scale;
	
	UV = world_position.xz * inv_texel_scale;
	UV2 = UV * 0.5; // (lod + 1) space which is used for blending
	
	vec2 size = vec2(textureSize(_height_maps, 0).xy);
	
	vec3 coords = gather_coords(UV, vertex_lod, size);
	vec4 weights = gather_weights(UV);
	
	vec3 s = vec3(1.0 / size, 0.0);
	
	// cant use textureGather here since samples may be separated
	vec4 heights = vec4(
		texture(_height_maps, coords + s.zzz).r,
		texture(_height_maps, coords + s.xzz).r,
		texture(_height_maps, coords + s.zyz).r,
		texture(_height_maps, coords + s.xyz).r
	);
	
	VERTEX.y = dot(heights, weights);
	world_position.y = VERTEX.y;
}

// approximate erf(sqrt(PI) * x)
vec2 Z(vec2 p) {
	vec2 a = abs(p);
	vec2 y = a * (a * (a * 0.02116217607 + 0.06389419205) + 0.06263162425) + 1.0;
	y = y * y;
	y = y * y;
	y = y * y;
	y = y * y;
	y = y * y;
	y = 1.0 - 1.0 / y;
	return y * sign(p);
}

// see github.com/vilmt/gaussian-primitives
float grid(vec2 l, vec2 p, vec2 dpdx, vec2 dpdy) {
	vec2 w = max(sqrt(dpdx * dpdx + dpdy * dpdy), 1e-6) / 0.7;
	vec2 inv_w = 1.0 / w, lw = 0.5 * inv_w * l;
	p = inv_w * (p - round(p));
	vec2 r = Z(p + inv_w + lw) - Z(p + inv_w - lw) 
		   + Z(p + lw) - Z(p - lw) 
		   + Z(p - inv_w + lw) - Z(p - inv_w - lw);
	r = 1.0 - mix(0.5 * r, l, smoothstep(1.1, 1.2, w));
	return 1.0 - r.x * r.y;
}

void fragment() {
	vec2 size = vec2(textureSize(_height_maps, 0).xy);
	
	vec3 coords = gather_coords(UV, vertex_lod, size);
	vec4 weights = gather_weights(UV);
	
	vec4 gradients_r = textureGather(_gradient_maps, coords, 0).wzxy;
	vec4 gradients_g = textureGather(_gradient_maps, coords, 1).wzxy;
	
	float gradient_r = dot(gradients_r, weights);
	float gradient_g = dot(gradients_g, weights);
	
	vec3 coords_2;
	vec4 weights_2;
	
	// blend normals with lod + 1
	if (lod_blend_mask > EPSILON) {
		coords_2 = gather_coords(UV2, vertex_lod + 1, size);
		weights_2 = gather_weights(UV2);
		
		vec4 gradients_r_2 = textureGather(_gradient_maps, coords_2, 0).wzxy;
		vec4 gradients_g_2 = textureGather(_gradient_maps, coords_2, 1).wzxy;
		
		gradient_r = mix(gradient_r, dot(gradients_r_2, weights_2), lod_blend_mask);
		gradient_g = mix(gradient_g, dot(gradients_g_2, weights_2), lod_blend_mask);
	}
	
	vec3 normal = normalize(vec3(-gradient_r, 1.0, -gradient_g));
	vec3 tangent = normalize(cross(normal, vec3(0.0, 0.0, 1.0)));
	vec3 binormal = cross(normal, tangent); // perpendicular, no need to normalize
	
	mat3 TNB = mat3(tangent, normal, binormal);
	
	NORMAL = mat3(VIEW_MATRIX) * normal;
	TANGENT = mat3(VIEW_MATRIX) * tangent;
	BINORMAL = mat3(VIEW_MATRIX) * binormal;
	
	vec2 uv = world_position.xz * 0.1;
	vec2 duvdx = dFdx(uv), duvdy = dFdy(uv);
	
	ALBEDO = vec3(grid(vec2(0.02), uv, duvdx, duvdy));
}