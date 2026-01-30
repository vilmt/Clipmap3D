shader_type spatial;

// options
//#define USE_CIRCLE_MASK // uses less obvious but more wasteful lod blend mask

// do not change
#define MAX_LOD_COUNT 10
#define MAX_TEXTURE_COUNT 32
#define INV_255 0.003921568627450
#define EPSILON 1e-6

#ifdef USE_CIRCLE_MASK
// circle mask: ratio be smaller than 1.0 - sqrt(2.0) / 2.0 to avoid lod overlap
uniform float lod_blend_ratio: hint_range(0.0, 0.2928932188134525) = 0.2;
#else
uniform float lod_blend_ratio: hint_range(0.0, 0.5) = 0.2;
#endif

uniform float projection_threshold = 0.8;

group_uniforms private;
uniform sampler2DArray _albedo_textures: source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray _normal_textures: hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float[MAX_TEXTURE_COUNT] _normal_depths;
uniform vec2[MAX_TEXTURE_COUNT] _uv_scales;
uniform vec3[MAX_TEXTURE_COUNT] _albedo_colors: source_color;

// repeat creates toroidal coordinate space
uniform highp sampler2DArray _height_maps: repeat_enable, hint_default_black, filter_nearest;
uniform sampler2DArray _normal_maps: repeat_enable, hint_normal, filter_nearest;
uniform highp sampler2DArray _control_maps: repeat_enable, hint_default_black, filter_nearest;

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
	float ao;
	//
	//float normal_depth;
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

void accumulate(inout material mat, vec3 p, vec3 ddx, vec3 ddy, vec3 normal, uvec2 texture_ids, float blend, float bilerp_weight) {
	vec4 dd = vec4(ddx.xz, ddy.xz);
	mat2 align = mat2(1.0);
	vec2 uv = p.xz;
	
	// TODO: projection
	//if (normal.y <= projection_threshold) {
		//// Projected normal map alignment matrix
		//align = mat2(vec2(normal.z, -normal.x), vec2(normal.x, normal.z));
		//// Fast 45 degree snapping https://iquilezles.org/articles/noatan/
		//vec2 xz = round(normalize(-normal.xz) * 1.3065629648763765); // sqrt(1.0 + sqrt(0.5))
		//xz *= abs(xz.x) + abs(xz.y) > 1.5 ? 0.7071067811865475 : 1.0; // sqrt(0.5)
		//xz = vec2(-xz.y, xz.x);
		//
		//uv = vec2(dot(p.xz, xz), -p.y);
		//dd.xy = vec2(dot(ddx.xz, xz), -ddx.y);
		//dd.zw = vec2(dot(ddy.xz, xz), -ddy.y);
	//}
	
	// TODO: fix texture ids same edge case
	// skip first sample if both are same
	//blend = min(1.0, blend + float(texture_ids[1] == texture_ids[0]));
	
	// secondary
	if (blend < 1.0 - EPSILON) {
		float weight = (1.0 - blend) * bilerp_weight;
		
		uint id = texture_ids[1];
		
		vec4 albedo_r = textureGrad(_albedo_textures, vec3(uv, float(id)), dd.xy, dd.zw);
		
		mat.albedo += albedo_r.rgb * weight;
		mat.roughness += albedo_r.a * weight;
		
		vec4 normal_h_ao = textureGrad(_normal_textures, vec3(uv, float(id)), dd.xy, dd.zw);
		mat.normal += (normal_h_ao.xyz * 2.0 - 1.0) * weight;
		
		// TODO: incorporate height in blending
		mat.ao += normal_h_ao.w * weight;
		mat.total_weight += weight;
	}
	
	// primary
	if (blend > EPSILON) {
		float weight = blend * bilerp_weight;
		
		uint id = texture_ids[0];
		
		vec4 albedo_r = textureGrad(_albedo_textures, vec3(uv, float(id)), dd.xy, dd.zw);
		
		mat.albedo += albedo_r.rgb * weight;
		mat.roughness += albedo_r.a * weight;
		
		vec4 normal_h_ao = textureGrad(_normal_textures, vec3(uv, float(id)), dd.xy, dd.zw);
		mat.normal += (normal_h_ao.xyz * 2.0 - 1.0) * weight;
		
		// TODO: incorporate height in blending
		// Can make high parts of secondary stick out of primary
		mat.ao += normal_h_ao.w * weight;
		mat.total_weight += weight;
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
	
	material mat = material(vec3(0.0), 0.0, vec3(0.0), 0.0, 0.0);
	
	vec3 base_p = world_position * 0.1;
	
	vec3 base_ddx = dFdxCoarse(base_p);
	vec3 base_ddy = dFdyCoarse(base_p);
	
	uvec4 controls = floatBitsToUint(textureGather(_control_maps, coords, 0).wzxy);
	for (int i = 0; i < 4; i++) {
		uint control = controls[i];
		float weight = weights[i];
		uvec2 ids = uvec2(control >> 27u & 0x1Fu, control >> 22u & 0x1Fu);
		float blend = float(control >> 14u & 0xFFu) * INV_255;
		
		accumulate(mat, base_p, base_ddx, base_ddy, normal, ids, blend, weight);
	}
	
	// lod blend control maps, unnecessary for 4x map res
	//if (lod_blend_mask > EPSILON) {
		//uvec4 controls_2 = floatBitsToUint(textureGather(_control_maps, coords_2, 0).wzxy);
		//
		//for (int i = 0; i < 4; i++) {
			//uint control = controls_2[i];
			//float weight = weights_2[i] * lod_blend_mask;
			//uvec2 ids = uvec2(control >> 27u & 0x1Fu, control >> 22u & 0x1Fu);
			//float blend = float(control >> 14u & 0xFFu) * INV_255;
			//
			//accumulate(mat, base_p, base_ddx, base_ddy, normal, ids, blend, weight);
		//}
	//}
	
	float inv_w = 1.0 / max(mat.total_weight, EPSILON);
	mat.albedo *= inv_w;
	mat.roughness *= inv_w;
	mat.normal *= inv_w;
	mat.ao *= inv_w;
	
	ALBEDO = mat.albedo;
	ROUGHNESS = mat.roughness;
	NORMAL_MAP = mat.normal.xyz * 0.5 + 0.5;
	AO = mat.ao;
	
	//ALBEDO = debug_albedo;
}