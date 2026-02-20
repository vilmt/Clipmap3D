shader_type spatial;
render_mode blend_mix;

// BUG: -1300, y, -1300 with texels_per_vertex 7, 7
// BUG: geomorph overlaps strip on positive coords

/*
Clipmap3D Full Shader

* All maps (height, normal, and control) are built in the compute shader and passed to this shader
* Per texel, the control map packs 2 texture IDs and a float to blend between them

Techniques used:
* Vertex geo-morphing between successive LODs in a circle/square mask
* Bilinear interpolation of normals between vertices
	* NOTE: When _texels_per_vertex is greater than (1, 1), we bilerp between those texels too
* Interpolation of normals between successive LODs using the same mask
* Deduplication of texture IDs obtained from the control map to reduce texture samples
*/

// Options
#define USE_PROJECTION
//#define USE_CIRCLE_MASK
#define ALBEDO_DEFAULT vec4(0.8, 0.8, 0.8, 1.0)
#define NORMAL_DEFAULT vec4(0.5, 0.5, 1.0, 1.0)

// Don't change
#define MAX_TEXTURE_COUNT 32
#define INV_255 0.003921568627450
#define EPSILON 1e-6

#ifdef USE_PROJECTION
uniform float projection_threshold: hint_range(0.0, 1.0) = 0.7;
#endif

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

struct material {
	vec3 albedo;
	float roughness;
	
	vec3 normal;
	float normal_depth;
	float ao;
	float total_weight;
};

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

// texture accumulation largely based on Terrain3D's main shader
void accumulate(inout material mat, mat3 TNB, vec3 normal, uint control, vec2 id_weights, uvec2 ids, inout int samples) {
	vec3 p = world_position;
	vec3 dPdx = dFdxCoarse(p);
	vec3 dPdy = dFdyCoarse(p);
	
	vec2 uv = p.xz;
	vec2 ddx = dPdx.xz;
	vec2 ddy = dPdy.xz;
	mat2 align = mat2(1.0);
	
	#ifdef USE_PROJECTION
	if (normal.y < projection_threshold) {
		// Fast 45 degree snapping https://iquilezles.org/articles/noatan/
		vec2 xz = round(normalize(-normal.xz) * 1.3065629648763765); // sqrt(1.0 + sqrt(0.5))
		xz *= abs(xz.x) + abs(xz.y) > 1.5 ? 0.7071067811865475 : 1.0; // sqrt(0.5)
		xz = vec2(-xz.y, xz.x);
		
		uv = vec2(dot(p.xz, xz), -p.y);
		
		ddx = vec2(dot(ddx, xz), -dPdx.y);
		ddy = vec2(dot(ddy, xz), -dPdy.y);
		
		// Projected normal map alignment matrix
		align = mat2(vec2(normal.z, -normal.x), vec2(normal.x, normal.z));
	}
	#endif
	
	float world_normal = 1.0;
	#define FAST_WORLD_NORMAL(n) fma(TNB[0], vec3(n.x), fma(TNB[2], vec3(n.z), TNB[1] * vec3(n.y)))
	
	// only for branching
	float blend = float(control >> 14u & 0xFFu) * INV_255;
	
	if (blend < 1.0 - EPSILON) {
		int id = int(ids[0]);
		float id_weight = id_weights[0];
		
		vec2 scale = _uv_scales[id];
		
		//ivec3 h = ivec3(ivec2(floor(world_position.xz * scale)), id);
		//
		//float hash = fract(float(h.x * 12321 ^ h.y * 30213 + h.z * 73017) / 2061.13296);
		//
		uint flags = _flags[id];
		bool randomize_rotation = bool(flags & BIT_RANDOMIZE_ROTATION);
		bool randomize_translation = bool(flags & BIT_RANDOMIZE_TRANSLATION);
		
		vec2 id_uv = uv * scale;
		vec2 id_ddx = ddx * scale;
		vec2 id_ddy = ddy * scale;
		
		int albedo_id = _albedo_remap[id];
		int normal_id = _normal_remap[id];
		
		vec4 albedo_r = albedo_id == -1 ? ALBEDO_DEFAULT : textureGrad(_albedo_textures, vec3(id_uv, float(albedo_id)), id_ddx, id_ddy);
		vec4 normal_h_ao = normal_id == -1 ? NORMAL_DEFAULT : textureGrad(_normal_textures, vec3(id_uv, float(normal_id)), id_ddx, id_ddy);
		
		mat.albedo += albedo_r.rgb * _albedo_modulates[id] * id_weight;
		mat.roughness += clamp(albedo_r.a + _roughness_offsets[id], 0.0, 1.0) * id_weight;
		mat.normal_depth += _normal_depths[id] * id_weight;
		
		vec3 n = vec3(normal_h_ao.r, 0.0, normal_h_ao.g) * 2.0 - 1.0;
		n.xz = n.xz * align;
		n.y = sqrt(1.0 - dot(n.xz, n.xz));
		
		
		mat.normal += n * id_weight;
		
		world_normal = FAST_WORLD_NORMAL(n).y;
		
		// TODO: incorporate height in blending
		mat.ao += normal_h_ao.a * id_weight;
		mat.total_weight += id_weight;
		
		samples += 2;
	}
	
	if (blend > EPSILON && ids[0] != ids[1]) {
		int id = int(ids[1]);
		float id_weight = id_weights[1] * world_normal;
		
		vec2 scale = _uv_scales[id];
		
		vec2 id_uv = uv * scale;
		vec2 id_ddx = ddx * scale;
		vec2 id_ddy = ddy * scale;
		
		int albedo_id = _albedo_remap[id];
		int normal_id = _normal_remap[id];
		
		vec4 albedo_r = albedo_id == -1 ? ALBEDO_DEFAULT : textureGrad(_albedo_textures, vec3(id_uv, float(albedo_id)), id_ddx, id_ddy);
		vec4 normal_h_ao = normal_id == -1 ? NORMAL_DEFAULT : textureGrad(_normal_textures, vec3(id_uv, float(normal_id)), id_ddx, id_ddy);
		
		mat.albedo += albedo_r.rgb * _albedo_modulates[id] * id_weight;
		mat.roughness += clamp(albedo_r.a + _roughness_offsets[id], 0.0, 1.0) * id_weight;
		mat.normal_depth += _normal_depths[id] * id_weight;
		
		vec3 n = vec3(normal_h_ao.r, 0.0, normal_h_ao.g) * 2.0 - 1.0;
		n.xz = n.xz * align;
		n.y = sqrt(1.0 - dot(n.xz, n.xz));
		
		
		
		mat.normal += n * id_weight;
		
		// TODO: incorporate height in blending
		mat.ao += normal_h_ao.a * id_weight;
		mat.total_weight += id_weight;
		
		samples += 2;
	}
}

void fragment() {
	vec2 size = vec2(textureSize(_height_maps, 0).xy);
	
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
	
	// blend normals with lod + 1
	if (lod_blend_mask > EPSILON) {
		coords_2 = gather_coords(UV2, vertex_lod + 1, size);
		weights_2 = gather_weights(UV2);
		
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
	
	uvec4 controls = floatBitsToUint(textureGather(_control_maps, coords, 0).wzxy);
	
	uvec4 id_0 = controls >> uvec4(27u) & uvec4(0x1Fu);
	uvec4 id_1 = controls >> uvec4(22u) & uvec4(0x1Fu);
	
	vec4 weights_id_1 = vec4(controls >> uvec4(14u) & uvec4(0xFFu)) * INV_255;
	vec4 weights_id_0 = 1.0 - weights_id_1;
	
	weights_id_0 *= weights;
	weights_id_1 *= weights;
	
	uvec2 texture_ids[4];
	vec2 t_weights[4];
	for (int i = 0; i < 4; i++) {
		texture_ids[i] = uvec2(id_0[i], id_1[i]);
		t_weights[i] = vec2(weights_id_0[i], weights_id_1[i]);
	}
	
	//int samples = 0;
	//material mat = material(vec3(0.0), 0.0, vec2(0.0), 0.0, 0.0, 0.0);
	//
	//for (int i = 0; i < 4; i++) {
		//accumulate(mat, normals[i], controls[i], t_weights[i], texture_ids[i], samples);
	//}
	
	t_weights = {vec2(0.0), vec2(0.0), vec2(0.0), vec2(0.0)};
	
	for (int i = 0; i < 4; i++) {
		vec2 w_0 = vec2(weights_id_0[i], weights_id_0[i]);
		vec2 w_1 = vec2(weights_id_1[i], weights_id_1[i]);
		uvec2 id_0 = texture_ids[i].xx;
		uvec2 id_1 = texture_ids[i].yy;
		for (int j = 0; j < 4; j++) {
			t_weights[j] += fma(w_0, vec2(equal(texture_ids[j], id_0)), w_1 * vec2(equal(texture_ids[j], id_1)));
		}
	}
	
	int samples = 0;
	material mat = material(vec3(0.0), 0.0, vec3(0.0), 0.0, 0.0, 0.0);
	
	for (int i = 0; i < 4; i++) {
		// TODO: figure out why bilinear weights are multiplied twice
		accumulate(mat, TNB, normals[i], controls[i], t_weights[i] * weights[i], texture_ids[i], samples);
	}
	
	
	float inv_w = 1.0 / max(mat.total_weight, EPSILON);
	mat.albedo *= inv_w;
	mat.roughness *= inv_w;
	mat.normal *= inv_w;
	mat.ao *= inv_w;
	
	ALBEDO = mat.albedo;
	ROUGHNESS = mat.roughness;
	NORMAL_MAP = fma(mat.normal.xzy, vec3(0.5), vec3(0.5));
	NORMAL_MAP_DEPTH = mat.normal_depth;
	AO = mat.ao;
	
	//ALBEDO = debug_albedo;
	//ALBEDO = vec3(float(samples == 8));
}