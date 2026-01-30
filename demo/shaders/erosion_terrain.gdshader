shader_type spatial;

// options
//#define USE_CIRCLE_MASK // uses less obvious but more wasteful lod blend mask

// do not change
#define MAX_LOD_COUNT 10
#define MAX_TEXTURE_COUNT 32
#define INV_255 0.003921568627450
#define EPSILON 1e-6

#ifdef USE_CIRCLE_MASK
// ratio must be smaller than 1.0 - sqrt(2.0) / 2.0 to avoid lod overlap
uniform float lod_blend_ratio: hint_range(0.0, 0.2928932188134525) = 0.2;
#else
uniform float lod_blend_ratio: hint_range(0.0, 0.5) = 0.2;
#endif

group_uniforms private;
uniform sampler2DArray _albedo_textures: source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2DArray _normal_textures: hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;

// TODO
uniform float[MAX_TEXTURE_COUNT] _normal_depths;
uniform vec2[MAX_TEXTURE_COUNT] _uv_scales;
uniform vec3[MAX_TEXTURE_COUNT] _albedo_colors: source_color;

// repeat creates toroidal coordinate space
uniform highp sampler2DArray _height_maps: hint_default_black, repeat_enable, filter_nearest;
uniform highp sampler2DArray _normal_maps: hint_normal, repeat_enable, filter_nearest;
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
	
	vec2 even_mask = abs(mod(world_position.xz * inv_scale, 2.0));
	
	vec2 texel_scale = scale / vec2(_texels_per_vertex);
	vec2 inv_texel_scale = 1.0 / texel_scale;
	
	vec2 size = vec2(textureSize(_height_maps, 0).xy);
	vec2 target = (world_position.xz - _target_position.xz) * inv_texel_scale;
	
	#ifdef USE_CIRCLE_MASK
	float circle_mask = length(target / (size * 0.5));
	lod_blend_mask = smoothstep(1.0 - lod_blend_ratio, 1.0, circle_mask);
	#else
	vec2 square = abs(target / (size * 0.5));
	float square_mask = max(square.x, square.y);
	lod_blend_mask = smoothstep(1.0 - lod_blend_ratio, 1.0, square_mask);
	#endif
	
	vec2 offset = even_mask * lod_blend_mask;
	
	VERTEX.xz += offset;
	world_position.xz += offset * scale;
	
	UV = world_position.xz * inv_texel_scale;
	UV2 = UV * 0.5;
	
	vec4 weights;
	vec3 coords = gather_coords(size, UV, vertex_lod, weights);
	
	vec3 s = vec3(1.0 / size, 0.0);
	
	vec4 heights = vec4(
		texture(_height_maps, coords + s.zzz).r,
		texture(_height_maps, coords + s.xzz).r,
		texture(_height_maps, coords + s.zyz).r,
		texture(_height_maps, coords + s.xyz).r
	);
	
	VERTEX.y = dot(heights, weights);
	
	debug_albedo = vec3(0.7);
}

void accumulate(inout material mat, vec3 p, vec3 ddx, vec3 ddy, vec3 normal, uvec2 ids, float blend, float bilerp_weight, inout int samples) {
	vec2 uv = p.xz;
	
	if (blend < 1.0 - EPSILON) {
		float weight = (1.0 - blend) * bilerp_weight;
		
		uint id = ids[0];
		
		vec2 scale = _uv_scales[int(id)];
		
		vec2 id_uv = uv * scale;
		vec2 id_ddx = ddx.xz * scale;
		vec2 id_ddy = ddy.xz * scale;
		
		vec4 albedo_r = textureGrad(_albedo_textures, vec3(id_uv, float(id)), id_ddx, id_ddy);
		
		vec3 modulate = _albedo_colors[int(id)];
		
		mat.albedo += albedo_r.rgb * modulate * weight;
		mat.roughness += albedo_r.a * weight;
		
		mat.normal_depth += _normal_depths[int(id)] * weight;
		
		vec4 normal_h_ao = textureGrad(_normal_textures, vec3(id_uv, float(id)), id_ddx, id_ddy);
		mat.normal += (normal_h_ao.xyz * 2.0 - 1.0) * weight;
		
		// TODO: incorporate height in blending
		// Can make high parts of secondary stick out of primary
		mat.ao += normal_h_ao.w * weight;
		mat.total_weight += weight;
		
		samples += 2;
	}
	
	if (blend > EPSILON && ids[0] != ids[1]) {
		float weight = blend * bilerp_weight;
		
		uint id = ids[1];
		
		vec2 scale = _uv_scales[int(id)];
		
		vec2 id_uv = uv * scale;
		vec2 id_ddx = ddx.xz * scale;
		vec2 id_ddy = ddy.xz * scale;
		
		vec4 albedo_r = textureGrad(_albedo_textures, vec3(id_uv, float(id)), id_ddx, id_ddy);
		
		vec3 modulate = _albedo_colors[int(id)];
		
		mat.albedo += albedo_r.rgb * modulate * weight;
		mat.roughness += albedo_r.a * weight;
		
		mat.normal_depth += _normal_depths[int(id)] * weight;
		
		vec4 normal_h_ao = textureGrad(_normal_textures, vec3(id_uv, float(id)), id_ddx, id_ddy);
		mat.normal += (normal_h_ao.xyz * 2.0 - 1.0) * weight;
		
		// TODO: incorporate height in blending
		// Can make high parts of secondary stick out of primary
		mat.ao += normal_h_ao.w * weight;
		mat.total_weight += weight;
		
		samples += 2;
	}
}

void fragment() {
	vec2 size = vec2(textureSize(_height_maps, 0).xy);
	
	vec4 weights, weights_2;
	vec3 coords, coords_2;
	coords = gather_coords(size, UV, vertex_lod, weights);
	
	vec2 gradient = vec2(
		dot(textureGather(_normal_maps, coords, 0).wzxy, weights),
		dot(textureGather(_normal_maps, coords, 1).wzxy, weights)
	);
	
	// blend normals with lod + 1
	if (lod_blend_mask > EPSILON) {
		coords_2 = gather_coords(size, UV2, vertex_lod + 1, weights_2);
		
		vec2 gradient_2 = vec2(
			dot(textureGather(_normal_maps, coords_2, 0).wzxy, weights_2),
			dot(textureGather(_normal_maps, coords_2, 1).wzxy, weights_2)
		);
		
		gradient = mix(gradient, gradient_2, lod_blend_mask);
	}
	
	vec3 normal = normalize(vec3(
		-gradient.r,
		1.0,
		-gradient.g
	));
		
	vec3 tangent = normalize(cross(NORMAL, vec3(0.0, 0.0, 1.0)));
	vec3 binormal = cross(NORMAL, tangent); // perpendicular, no need to normalize
	
	NORMAL = mat3(VIEW_MATRIX) * normal;
	TANGENT = mat3(VIEW_MATRIX) * tangent;
	BINORMAL = mat3(VIEW_MATRIX) * binormal;
	
	material mat = material(vec3(0.0), 0.0, vec3(0.0), 0.0, 0.0, 0.0);
	
	vec3 base_p = world_position * 0.1;
	
	vec3 base_ddx = dFdxCoarse(base_p);
	vec3 base_ddy = dFdyCoarse(base_p);
	
	int samples = 0;
	
	uvec4 controls = floatBitsToUint(textureGather(_control_maps, coords, 0).wzxy);
	
	
	//
	//// blend control with LOD + 1
	//if (lod_blend_mask > EPSILON) {
		//
		//
	for (int i = 0; i < 4; i++) {
		uint control = controls[i];
		float weight = weights[i];
		uvec2 ids = uvec2(control >> 27u & 0x1Fu, control >> 22u & 0x1Fu);
		float blend = float(control >> 14u & 0xFFu) * INV_255;
		
		accumulate(mat, base_p, base_ddx, base_ddy, normal, ids, blend, weight, samples);
	}
	//}
	
	float inv_w = 1.0 / max(mat.total_weight, EPSILON);
	mat.albedo *= inv_w;
	mat.roughness *= inv_w;
	mat.normal *= inv_w;
	mat.ao *= inv_w;
	
	ALBEDO = mat.albedo;
	ROUGHNESS = mat.roughness;
	NORMAL_MAP = mat.normal.xyz * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = mat.normal_depth;
	AO = mat.ao;
	
	//ALBEDO = vec3(float(samples) * 1.0 / 32.0);
}