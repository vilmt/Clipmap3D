shader_type spatial;

uniform float lod_blend_ratio = 0.2; // this causes seams > 0.2
uniform float projection_threshold = 0.8;

group_uniforms private;
uniform sampler2DArray _albedo_textures: source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray _normal_textures: hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

uniform highp sampler2DArray _height_maps: repeat_disable, hint_default_black, filter_nearest;
uniform sampler2DArray _normal_maps: repeat_disable, hint_normal, filter_nearest;
uniform highp sampler2DArray _control_maps: repeat_disable, hint_default_black, filter_nearest;

uniform vec3 _target_position;
uniform vec2 _vertex_spacing;
uniform ivec2 _tile_size;

varying vec3 world_position;
varying flat int vertex_lod;
varying float lod_blend_mask;

varying flat vec3 debug_albedo;

#define INV_255 0.003921568627450
#define EPSILON 1e-6
//#define LOD_BLEND
	
struct material {
	vec3 albedo;
	float roughness;
	
	vec3 normal;
	float ao;
	//
	//float normal_depth;
	//float ao_affect;
	float total_weight;
};

vec2 to_uv(vec2 world_xz, vec2 inv_scale) {
	vec2 lod_cell = world_xz * inv_scale;
	vec2 origin = floor(_target_position.xz * inv_scale + EPSILON);
	vec2 texel = lod_cell - origin + 0.5; // sample vertex center
	return texel / vec2(textureSize(_height_maps, 0).xy) + 0.5; // center texture
}

vec3 gather_coords(vec2 sampler_size, vec2 uv, int lod, out vec4 weights) {
	vec2 st = uv * sampler_size - 0.5;
	vec2 i = floor(st);
	vec2 w = fract(st);
	weights = vec2(1.0 - w.x, w.x).xyxy * vec2(1.0 - w.y, w.y).xxyy;
	return vec3((i + 0.5) / sampler_size, float(lod));
}

void vertex() {
	// camera_pos = MAIN_CAM_INV_VIEW_MATRIX[3].xyz;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// scale and lod from transform
	vec2 scale = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[2].xyz));
	vec2 inv_scale = 1.0 / scale;
	vertex_lod = int(log2(scale.x / _vertex_spacing.x) + EPSILON);
	
	vec2 edge = mod(floor(_target_position.xz * inv_scale + EPSILON), 2.0);
	vec2 lod_position = (world_position.xz - _target_position.xz) * inv_scale;
	vec2 lod_position_snapped = floor(lod_position - EPSILON) + edge;

#ifdef LOD_BLEND
	// geo-morph blend vertices on lod boundaries
	vec2 lod_size = fma(vec2(_tile_size), vec2(2.0), vec2(1.0));
	lod_blend_mask = smoothstep(1.0 - lod_blend_ratio, 1.0, length(lod_position / lod_size));
	lod_blend_mask *= float((vertex_lod + 1) < textureSize(_height_maps, 0).z);
	vec2 even_mask = abs(mod(lod_position_snapped, 2.0) - 1.0);
	vec2 offset = even_mask * lod_blend_mask;
	
	world_position.xz += offset * scale;
	VERTEX.xz += offset;
	UV2 = to_uv(world_position.xz, inv_scale * 0.5);
#endif
	
	UV = to_uv(world_position.xz, inv_scale);
	
	vec2 sampler_size = vec2(textureSize(_height_maps, 0).xy);
	
	vec4 weights;
	vec3 coords = gather_coords(sampler_size, UV, vertex_lod, weights);
	world_position.y = dot(textureGather(_height_maps, coords).wzxy, weights);
	VERTEX.y = world_position.y;
}

// TODO: pass 2 ids, calculate world normal in first, apply to second
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
		mat.ao += normal_h_ao.w * weight;
		mat.total_weight += weight;
	}
}

void fragment() {
	vec2 sampler_size = vec2(textureSize(_normal_maps, 0).xy);
	
	vec4 weights, weights_2;
	vec3 coords, coords_2;
	coords = gather_coords(sampler_size, UV, vertex_lod, weights); 
	
	vec2 gradient = vec2(
		dot(textureGather(_normal_maps, coords, 0).wzxy, weights),
		dot(textureGather(_normal_maps, coords, 1).wzxy, weights)
	);

#ifdef LOD_BLEND
	if (lod_blend_mask > EPSILON) {
		coords_2 = gather_coords(sampler_size, UV2, vertex_lod + 1, weights_2);
		
		vec2 gradient_2 = vec2(
			dot(textureGather(_normal_maps, coords_2, 0).wzxy, weights_2),
			dot(textureGather(_normal_maps, coords_2, 1).wzxy, weights_2)
		);
	
		gradient = mix(gradient, gradient_2, lod_blend_mask);
	}
#endif
	
	vec3 normal = normalize(vec3(-gradient.x, 1.0, -gradient.y));
	vec3 tangent = normalize(cross(normal, vec3(0.0, 0.0, 1.0)));
	vec3 binormal = normalize(cross(normal, tangent));
	
	NORMAL = mat3(VIEW_MATRIX) * normal;
	TANGENT = mat3(VIEW_MATRIX) * tangent;
	BINORMAL = mat3(VIEW_MATRIX) * binormal;
	
	material mat = material(vec3(0.0), 0.0, vec3(0.0), 0.0, 0.0);
	
	vec3 base_p = world_position * 0.1;
	
	vec3 base_ddx = dFdxCoarse(base_p);
	vec3 base_ddy = dFdyCoarse(base_p);
	
	uvec4 controls = floatBitsToUint(textureGather(_control_maps, coords, 0).wzxy);
	
	// TODO: blend lod boundaries exactly, similarly to height
	// 
	
	for (int i = 0; i < 4; i++) {
		uint control = controls[i];
		float weight = weights[i] * (1.0 - lod_blend_mask);
		uvec2 ids = uvec2(control >> 27u & 0x1Fu, control >> 22u & 0x1Fu);
		float blend = float(control >> 14u & 0xFFu) * INV_255;
		
		accumulate(mat, base_p, base_ddx, base_ddy, normal, ids, blend, weight);
	}

#ifdef LOD_BLEND
	if (lod_blend_mask > EPSILON) {
		uvec4 controls_2 = floatBitsToUint(textureGather(_control_maps, coords_2, 0).wzxy);
		
		for (int i = 0; i < 4; i++) {
			uint control = controls_2[i];
			float weight = weights_2[i] * lod_blend_mask;
			uvec2 ids = uvec2(control >> 27u & 0x1Fu, control >> 22u & 0x1Fu);
			float blend = float(control >> 14u & 0xFFu) * INV_255;
			
			accumulate(mat, base_p, base_ddx, base_ddy, normal, ids, blend, weight);
		}
	}
#endif
	
	float inv_w = 1.0 / max(mat.total_weight, EPSILON);
	mat.albedo *= inv_w;
	mat.roughness *= inv_w;
	mat.normal *= inv_w;
	mat.ao *= inv_w;
	
	ALBEDO = mat.albedo;
	ROUGHNESS = mat.roughness;
	NORMAL_MAP = mat.normal.xyz * 0.5 + 0.5;
	AO = mat.ao;
}