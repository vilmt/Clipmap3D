shader_type spatial;
render_mode blend_mix;

/*
Clipmap3D NoLerp Shader

* A shader used to demonstrate clipmap functionality
* No bilinear interpolation apart from geo-morph
*/

#define ALBEDO_DEFAULT vec4(0.8, 0.8, 0.8, 1.0)
#define NORMAL_DEFAULT vec4(0.5, 0.5, 1.0, 1.0)

// Don't change
#define MAX_TEXTURE_COUNT 32
#define INV_255 0.003921568627450
#define EPSILON 1e-6

group_uniforms private;
// densely packed, access using remap index
// RGB: Albedo, A: Roughness
uniform sampler2DArray _albedo_textures: source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform int[MAX_TEXTURE_COUNT] _albedo_remap;
// RG: Normal (OpenGL), B: Height, A: Ambient Occlusion
uniform sampler2DArray _normal_textures: hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform int[MAX_TEXTURE_COUNT] _normal_remap;

#define BIT_PROJECTED (1u << 0u)
#define BIT_RANDOMIZE_TRANSLATION (1u << 1u)
#define BIT_RANDOMIZE_ROTATION (1u << 2u)

// fixed size, access using texture index
uniform vec2[MAX_TEXTURE_COUNT] _uv_scales;
uniform vec3[MAX_TEXTURE_COUNT] _albedo_modulates: source_color;
uniform float[MAX_TEXTURE_COUNT] _roughness_offsets;
uniform float[MAX_TEXTURE_COUNT] _normal_depths;
uniform uint[MAX_TEXTURE_COUNT] _flags;

// repeat creates toroidal coordinate space
uniform highp sampler2DArray _height_maps: hint_default_black, repeat_enable, filter_nearest;
uniform highp sampler2DArray _normal_maps: hint_normal, repeat_enable, filter_nearest;
uniform highp sampler2DArray _control_maps: hint_default_black, repeat_enable, filter_nearest;

uniform ivec2 _texels_per_vertex;
uniform vec2 _vertex_spacing;
uniform vec3 _target_position;

varying vec3 world_position;
varying flat int vertex_lod;
varying vec3 debug_albedo;

struct material {
	vec3 albedo;
	float roughness;
	
	vec2 normal;
	float normal_depth;
	float ao;
	float total_weight;
};

// flat sampling coords
vec3 get_coords(vec2 sampler_size, vec2 texel, int lod) {
	vec2 i = floor(texel);
	return vec3((i + 0.5) / sampler_size, float(lod));
}

// coords for bilinear blend using textureGather
vec3 gather_coords(vec2 sampler_size, vec2 texel, int lod, out vec4 weights) {
	vec2 i = floor(texel);
	vec2 w = fract(texel);
	weights = vec2(1.0 - w.x, w.x).xyxy * vec2(1.0 - w.y, w.y).xxyy;
	return vec3((i + 0.5) / sampler_size, float(lod));
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// scale and lod from transform
	vec2 scale = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[2].xyz));
	vec2 inv_scale = 1.0 / scale;
	vertex_lod = int(log2(scale.x / _vertex_spacing.x) + EPSILON);
	
	vec2 even_mask = mod(floor(world_position.xz * inv_scale + 0.5), 2.0);
	
	vec2 texel_scale = scale / vec2(_texels_per_vertex);
	vec2 inv_texel_scale = 1.0 / texel_scale;
	
	vec2 size = vec2(textureSize(_height_maps, 0).xy);
	vec2 target = (world_position.xz - _target_position.xz) * inv_texel_scale;
	
	vec2 square = abs(target / (size * 0.5));
	float square_mask = max(square.x, square.y);
	float lod_blend_mask = smoothstep(0.8, 1.0, square_mask);
	
	lod_blend_mask *= float((vertex_lod + 1) < textureSize(_height_maps, 0).z);
	
	// geo-morphing offset
	vec2 offset = even_mask * lod_blend_mask;
	// VERTEX.xz is already scaled by vertex spacing and LOD
	VERTEX.xz += offset;
	world_position.xz += offset * scale;
	
	UV = world_position.xz * inv_texel_scale;
	
	vec4 weights;
	vec3 coords = gather_coords(size, UV, vertex_lod, weights);
	
	vec3 s = vec3(1.0 / size, 0.0);
	
	// cant use textureGather here since samples may be separated
	vec4 heights = vec4(
		texture(_height_maps, coords + s.zzz).r,
		texture(_height_maps, coords + s.xzz).r,
		texture(_height_maps, coords + s.zyz).r,
		texture(_height_maps, coords + s.xyz).r
	);
	
	// VERTEX.y always has 1.0 scale
	VERTEX.y = dot(heights, weights);
	world_position.y = VERTEX.y;
	//debug_albedo.rg = VERTEX.xz * (1.0 / 128.0);
}

void accumulate(inout material mat, vec3 normal, uint control, vec2 id_weights, uvec2 ids, inout int samples) {
	vec3 p = world_position;
	vec3 dPdx = dFdxCoarse(p);
	vec3 dPdy = dFdyCoarse(p);
	
	vec2 uv = p.xz;
	vec2 ddx = dPdx.xz;
	vec2 ddy = dPdy.xz;
	mat2 align = mat2(1.0);
	
	vec2 proj_uv = uv;
	vec2 proj_ddx = ddx;
	vec2 proj_ddy = ddy;
	mat2 proj_align = align;
	
	if (normal.y < 0.7071067811865475) { // sqrt(0.5)
		// Projected normal map alignment matrix
		proj_align = mat2(vec2(normal.z, -normal.x), vec2(normal.x, normal.z));
		// Fast 45 degree snapping https://iquilezles.org/articles/noatan/
		vec2 xz = round(normalize(-normal.xz) * 1.3065629648763765); // sqrt(1.0 + sqrt(0.5))
		xz *= abs(xz.x) + abs(xz.y) > 1.5 ? 0.7071067811865475 : 1.0; // sqrt(0.5)
		xz = vec2(-xz.y, xz.x);
		
		proj_uv = vec2(dot(p.xz, xz), -p.y);
		
		proj_ddx = vec2(dot(ddx, xz), -dPdx.y);
		proj_ddy = vec2(dot(ddy, xz), -dPdy.y);
	}
	
	// only for branching
	float blend = float(control >> 14u & 0xFFu) * INV_255;
	
	if (blend < 1.0 - EPSILON) {
		int id = int(ids[0]);
		float id_weight = id_weights[0];
		
		vec2 scale = _uv_scales[id];
		
		uint flags = _flags[id];
		bool projected = bool(flags & BIT_PROJECTED);
		bool randomize_translation = bool(flags & BIT_RANDOMIZE_TRANSLATION);
		bool randomize_rotation = bool(flags & BIT_RANDOMIZE_ROTATION);
		
		// TODO: fma
		vec2 id_uv = (projected ? proj_uv : uv) * scale;
		vec2 id_ddx = (projected ? proj_ddx : ddx) * scale;
		vec2 id_ddy = (projected ? proj_ddy : ddy) * scale;
		mat2 id_align = (projected ? proj_align : align);
		
		int albedo_id = _albedo_remap[id];
		int normal_id = _normal_remap[id];
		
		vec4 albedo_r = albedo_id == -1 ? ALBEDO_DEFAULT : textureGrad(_albedo_textures, vec3(id_uv, float(albedo_id)), id_ddx, id_ddy);
		vec4 normal_h_ao = normal_id == -1 ? NORMAL_DEFAULT : textureGrad(_normal_textures, vec3(id_uv, float(normal_id)), id_ddx, id_ddy);
		
		mat.albedo += albedo_r.rgb * _albedo_modulates[id] * id_weight;
		mat.roughness += clamp(albedo_r.a + _roughness_offsets[id], 0.0, 1.0) * id_weight;
		mat.normal_depth += _normal_depths[id] * id_weight;
		
		mat.normal += (normal_h_ao.rg * 2.0 - 1.0) * id_align * id_weight;
		
		// TODO: incorporate height in blending
		mat.ao += normal_h_ao.a * id_weight;
		mat.total_weight += id_weight;
		
		samples += 2;
	}
	
	if (blend > EPSILON && ids[0] != ids[1]) {
		int id = int(ids[1]);
		float id_weight = id_weights[1];
		
		vec2 scale = _uv_scales[id];
		
		uint flags = _flags[id];
		bool projected = bool(flags & BIT_PROJECTED);
		bool randomize_translation = bool(flags & BIT_RANDOMIZE_TRANSLATION);
		bool randomize_rotation = bool(flags & BIT_RANDOMIZE_ROTATION);
		
		// TODO: fma
		vec2 id_uv = (projected ? proj_uv : uv) * scale;
		vec2 id_ddx = (projected ? proj_ddx : ddx) * scale;
		vec2 id_ddy = (projected ? proj_ddy : ddy) * scale;
		mat2 id_align = (projected ? proj_align : align);
		
		int albedo_id = _albedo_remap[id];
		int normal_id = _normal_remap[id];
		
		vec4 albedo_r = albedo_id == -1 ? ALBEDO_DEFAULT : textureGrad(_albedo_textures, vec3(id_uv, float(albedo_id)), id_ddx, id_ddy);
		vec4 normal_h_ao = normal_id == -1 ? NORMAL_DEFAULT : textureGrad(_normal_textures, vec3(id_uv, float(normal_id)), id_ddx, id_ddy);
		
		mat.albedo += albedo_r.rgb * _albedo_modulates[id] * id_weight;
		mat.roughness += clamp(albedo_r.a + _roughness_offsets[id], 0.0, 1.0) * id_weight;
		mat.normal_depth += _normal_depths[id] * id_weight;
		
		mat.normal += (normal_h_ao.rg * 2.0 - 1.0) * id_align * id_weight;
		
		// TODO: incorporate height in blending
		mat.ao += normal_h_ao.a * id_weight;
		mat.total_weight += id_weight;
		
		samples += 2;
	}
}

void fragment() {
	vec2 size = vec2(textureSize(_height_maps, 0).xy);
	vec3 coords = get_coords(size, UV, vertex_lod);
	
	vec2 gradient = texture(_normal_maps, coords, 0).rg;
	
	vec3 normal = normalize(vec3(-gradient.r, 1.0, -gradient.g));
	vec3 tangent = normalize(cross(normal, vec3(0.0, 0.0, 1.0)));
	vec3 binormal = cross(normal, tangent);
	
	NORMAL = mat3(VIEW_MATRIX) * normal;
	TANGENT = mat3(VIEW_MATRIX) * tangent;
	BINORMAL = mat3(VIEW_MATRIX) * binormal;
	
	material mat = material(vec3(0.0), 0.0, vec2(0.0), 0.0, 0.0, 0.0);
	
	uint control = floatBitsToUint(texture(_control_maps, coords, 0).r);
	uvec2 ids = uvec2(control >> 27u & 0x1Fu, control >> 22u & 0x1Fu);
	vec2 weights = vec2(0.0, float(control >> 14u & 0xFFu) * INV_255);
	weights.x = 1.0 - weights.y;
	
	int samples = 0; // used for profiling
	accumulate(mat, normal, control, weights, ids, samples);
	
	float inv_w = 1.0 / max(mat.total_weight, EPSILON);
	mat.albedo *= inv_w;
	mat.roughness *= inv_w;
	mat.normal *= inv_w;
	mat.ao *= inv_w;
	
	ALBEDO = mat.albedo;
	ROUGHNESS = mat.roughness;
	NORMAL_MAP.rg = mat.normal * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = mat.normal_depth;
	AO = mat.ao;
	
	//ALBEDO = debug_albedo;
	//ALBEDO = vec3(float(samples == 8));
}