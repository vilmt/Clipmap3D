shader_type spatial;

// Options
//#define USE_CIRCLE_MASK // uses less obvious but more wasteful lod blend mask

// Don't change
#define MAX_TEXTURE_COUNT 32
#define INV_255 0.003921568627450
#define EPSILON 1e-6

uniform float lod_blend_ratio: hint_range(0.0, 0.5) = 0.2;

group_uniforms private;
uniform sampler2DArray _albedo_textures: source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2DArray _normal_textures: hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;

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

// coords for bilinear blend or textureGather
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
	lod_blend_mask = smoothstep(1.0 - lod_blend_ratio, 1.0, square_mask);
	
	lod_blend_mask *= float((vertex_lod + 1) < textureSize(_height_maps, 0).z);
	
	// geo-morphing offset
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
}

void accumulate(inout material mat, vec3 p, vec3 ddx, vec3 ddy, float weight, uint control, vec2 id_weights, uvec2 ids) {
	vec2 uv = p.xz;
	
	// only for branching
	float blend = float(control >> 14u & 0xFFu) * INV_255;
	
	if (blend < 1.0 - EPSILON) {
		int id = int(ids[0]);
		float id_w = id_weights[0];
		
		vec2 scale = _uv_scales[id];
		
		vec2 id_uv = uv * scale;
		vec2 id_ddx = ddx.xz * scale;
		vec2 id_ddy = ddy.xz * scale;
		
		vec4 albedo_r = textureGrad(_albedo_textures, vec3(id_uv, float(id)), id_ddx, id_ddy);
		
		vec3 modulate = _albedo_colors[id];
		
		float id_weight = id_w * weight;
		mat.albedo += albedo_r.rgb * modulate * id_weight;
		mat.roughness += albedo_r.a * id_weight;
		mat.normal_depth += _normal_depths[id] * id_weight;
		
		vec4 normal_h_ao = textureGrad(_normal_textures, vec3(id_uv, float(id)), id_ddx, id_ddy);
		mat.normal += (normal_h_ao.xyz * 2.0 - 1.0) * id_weight;
		
		// TODO: incorporate height in blending
		mat.ao += normal_h_ao.w * id_weight;
		mat.total_weight += id_weight;
	}
	
	if (blend > EPSILON && ids[0] != ids[1]) {
		int id = int(ids[1]);
		float id_w = id_weights[1];
		
		vec2 scale = _uv_scales[id];
		
		vec2 id_uv = uv * scale;
		vec2 id_ddx = ddx.xz * scale;
		vec2 id_ddy = ddy.xz * scale;
		
		vec4 albedo_r = textureGrad(_albedo_textures, vec3(id_uv, float(id)), id_ddx, id_ddy);
		
		vec3 modulate = _albedo_colors[id];
		
		float id_weight = id_w * weight;
		mat.albedo += albedo_r.rgb * modulate * id_weight;
		mat.roughness += albedo_r.a * id_weight;
		mat.normal_depth += _normal_depths[id] * id_weight;
		
		vec4 normal_h_ao = textureGrad(_normal_textures, vec3(id_uv, float(id)), id_ddx, id_ddy);
		mat.normal += (normal_h_ao.xyz * 2.0 - 1.0) * id_weight;
		
		// TODO: incorporate height in blending
		mat.ao += normal_h_ao.w * id_weight;
		mat.total_weight += id_weight;
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
	
	uvec4 controls = floatBitsToUint(textureGather(_control_maps, coords, 0).wzxy);
	
	uvec4 t_id[2] = {controls >> uvec4(27u) & uvec4(0x1Fu), controls >> uvec4(22u) & uvec4(0x1Fu)};
	
	uvec2 texture_ids[4] = {
		uvec2(t_id[0].x, t_id[1].x),
		uvec2(t_id[0].y, t_id[1].y),
		uvec2(t_id[0].z, t_id[1].z),
		uvec2(t_id[0].w, t_id[1].w)
	};
	
	vec4 weights_id_1 = vec4(controls >> uvec4(14u) & uvec4(0xFFu)) * INV_255;
	vec4 weights_id_0 = 1.0 - weights_id_1;
	
	// bilinear weights
	weights_id_0 *= weights;
	weights_id_1 *= weights;
	
	vec2 t_weights[4] = {vec2(0.0), vec2(0.0), vec2(0.0), vec2(0.0)};
	
	// Terrain3D deduplication loop
	for (int i = 0; i < 4; i++) {
		vec2 w_0 = vec2(weights_id_0[i]);
		vec2 w_1 = vec2(weights_id_1[i]);
		uvec2 id_0 = texture_ids[i].xx;
		uvec2 id_1 = texture_ids[i].yy;
		t_weights[0] += fma(w_0, vec2(equal(texture_ids[0], id_0)), w_1 * vec2(equal(texture_ids[0], id_1)));
		t_weights[1] += fma(w_0, vec2(equal(texture_ids[1], id_0)), w_1 * vec2(equal(texture_ids[1], id_1)));
		t_weights[2] += fma(w_0, vec2(equal(texture_ids[2], id_0)), w_1 * vec2(equal(texture_ids[2], id_1)));
		t_weights[3] += fma(w_0, vec2(equal(texture_ids[3], id_0)), w_1 * vec2(equal(texture_ids[3], id_1)));
	}
	
	for (int i = 0; i < 4; i++) {
		accumulate(mat, base_p, base_ddx, base_ddy, weights[i], controls[i], t_weights[i], texture_ids[i]);
	}
	
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
}