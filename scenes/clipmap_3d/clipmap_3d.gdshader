shader_type spatial;

uniform float lod_blend_ratio = 0.2;
uniform float ao_strength = 1.0;
uniform float projection_threshold = 0.8;

uniform float auto_slope = 1.0;
uniform float auto_sharpness = 4.0;
uniform float auto_height_reduction = 0.0;

uniform sampler2D shallow_albedo_height: source_color;
uniform sampler2D shallow_normal_rough;

uniform sampler2D steep_albedo_height: source_color;
uniform sampler2D steep_normal_rough;

group_uniforms private;
uniform highp sampler2DArray _height_maps: repeat_disable, hint_default_black, filter_nearest;
uniform sampler2DArray _normal_maps: repeat_disable, hint_normal, filter_linear;
uniform highp sampler2DArray _control_maps: repeat_disable, hint_default_black, filter_nearest;

//uniform sampler2DArray _albedo_textures: source_color, filter_linear_mipmap_anisotropic, repeat_enable;
//uniform sampler2DArray _normal_textures: hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 _target_position;
uniform vec2 _vertex_spacing;
uniform ivec2 _tile_size;

varying vec3 world_position;
varying flat int vertex_lod;
varying float lod_blend_mask;

varying flat vec3 debug_albedo;

const float EPSILON = 10e-6;

struct Material {
	vec4 albedo_height;
	vec4 normal_rough;
	float normal_map_depth;
	float ao;
	float ao_affect;
	float total_weight;
};

ivec2 to_texel(vec2 world_xz, vec2 inv_scale) {
	ivec2 origin = ivec2(floor((world_xz - _target_position.xz) * inv_scale + EPSILON));
	return origin + textureSize(_height_maps, 0).xy / 2;
	//ivec2 texel = lod_cell - origin + 0.5; // sample vertex center
	//return texel / vec2(textureSize(_height_maps, 0).xy) + 0.5; // center texture
}

float gather_bilerp(sampler2DArray sampler, vec2 uv, float lod) {
	vec2 res = vec2(textureSize(sampler, 0).xy);
	
	vec2 st = uv * res - 0.5;
	vec2 i = floor(st);
	vec2 w = fract(st);
	
	vec4 g = textureGather(sampler, vec3((i + 0.5) / res, lod));
	return mix(mix(g.w, g.z, w.x), mix(g.x, g.y, w.x), w.y);
}

vec4 gather(sampler2DArray sampler, vec2 uv, float lod) {
	vec2 res = vec2(textureSize(sampler, 0).xy);
	
	vec2 st = uv * res - 0.5;
	vec2 i = floor(st);
	vec2 w = fract(st);
	
	return textureGather(sampler, vec3((i + 0.5) / res, lod)).wzxy;
}

vec2 to_uv(vec2 world_xz, vec2 inv_scale) {
	vec2 lod_cell = world_xz * inv_scale;
	vec2 origin = floor(_target_position.xz * inv_scale + EPSILON);
	vec2 texel = lod_cell - origin + 0.5; // sample vertex center
	return texel / vec2(textureSize(_height_maps, 0).xy) + 0.5; // center texture
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
		
	// geo-morph blend vertices on lod boundaries
	vec2 lod_size = fma(vec2(_tile_size), vec2(2.0), vec2(1.0));
	lod_blend_mask = smoothstep(1.0 - lod_blend_ratio, 1.0, length(lod_position / lod_size));
	lod_blend_mask *= float((vertex_lod + 1) < textureSize(_height_maps, 0).z);
	vec2 even_mask = abs(mod(lod_position_snapped, 2.0) - 1.0);
	vec2 offset = even_mask * lod_blend_mask;
	
	world_position.xz += offset * scale;
	VERTEX.xz += offset;
	
	UV = to_uv(world_position.xz, inv_scale);
	UV2 = to_uv(world_position.xz, inv_scale * 0.5);
	
	world_position.y = gather_bilerp(_height_maps, UV, float(vertex_lod));
	VERTEX.y = world_position.y;
	
	//debug_albedo.r = abs(a - b);
	//debug_albedo.r = length(_map_origin - _mesh_origin);
	//debug_albedo.r = float(VERTEX.y > 1.1);
	//debug_albedo.b = float(vertex_lod == 4);
}

// TODO: pass 2 ids, calculate world normal in first, apply to second
void accumulate(vec3 p, vec3 ddx, vec3 ddy, vec3 normal, bool projected, float weight,
				sampler2D albedo_tex, sampler2D normal_tex, inout Material material) {
	vec4 dd = vec4(ddx.xz, ddy.xz);
	mat2 align = mat2(1.);
	vec2 uv = p.xz;
	
	if (projected && normal.y <= projection_threshold) {
		// Projected normal map alignment matrix
		align = mat2(vec2(normal.z, -normal.x), vec2(normal.x, normal.z));
		// Fast 45 degree snapping https://iquilezles.org/articles/noatan/
		vec2 xz = round(normalize(-normal.xz) * 1.3065629648763765); // sqrt(1.0 + sqrt(0.5))
		xz *= abs(xz.x) + abs(xz.y) > 1.5 ? 0.7071067811865475 : 1.0; // sqrt(0.5)
		xz = vec2(-xz.y, xz.x);
		
		uv = vec2(dot(p.xz, xz), -p.y);
		dd.xy = vec2(dot(ddx.xz, xz), -ddx.y);
		dd.zw = vec2(dot(ddy.xz, xz), -ddy.y);
	}
	
	vec4 alb = textureGrad(albedo_tex, uv, dd.xy, dd.zw);
	vec4 nrm = textureGrad(normal_tex, uv, dd.xy, dd.zw);
	
	nrm.xyz = nrm.xzy * 2.0 - 1.0;
	float ao = length(nrm.xyz) * 2.0 - 1.0;
	ao = mix(ao * ao * ao_strength + 1.0 - ao_strength, 1.0, alb.a * alb.a);
	nrm.xyz = normalize(nrm.xyz);

	nrm.xz = fma((nrm.xz * align), vec2(float(projected)), nrm.xz * vec2(float(!projected)));

	material.albedo_height += alb * weight;
	material.normal_rough += nrm * weight;
	material.ao += ao * weight;
	material.total_weight += weight;
}

void fragment() {
	// central difference
	vec2 texel = 1.0 / vec2(textureSize(_height_maps, 0).xy);
	
	float lod = float(vertex_lod);
	
	vec2 grad = texture(_normal_maps, vec3(UV, lod)).rg;
	vec2 scale = 1.0 / float(1 << vertex_lod) / _vertex_spacing;
	vec3 normal = normalize(vec3(grad.x * scale.x, 1.0, grad.y * scale.y));
	
	if (lod_blend_mask > EPSILON) {
		float lod_1 = lod + 1.0;
		vec2 grad_1 = texture(_normal_maps, vec3(UV2, lod_1)).rg;
		vec2 scale_1 = scale * 0.5;
		vec3 normal_1 = normalize(vec3(grad_1.x * scale_1.x, 1.0, grad_1.y * scale_1.y));
	
		normal = mix(normal, normal_1, lod_blend_mask);
	}
	
	vec3 tangent = normalize(cross(normal, vec3(0.0, 0.0, 1.0)));
	vec3 binormal = normalize(cross(normal, tangent));
	
	NORMAL = mat3(VIEW_MATRIX) * normal;
	TANGENT = mat3(VIEW_MATRIX) * tangent;
	BINORMAL = mat3(VIEW_MATRIX) * binormal;
	
	Material material = Material(vec4(0.0), vec4(0.0), 0.0, 0.0, 0.0, 0.0);
	
	uvec4 control = floatBitsToUint(gather(_control_maps, UV, float(vertex_lod)));
	
	ivec4 t_id[2] = {ivec4(control >> uvec4(27u) & uvec4(0x1Fu)), 
		ivec4(control >> uvec4(22u) & uvec4(0x1Fu))};
		
	ivec2 texture_ids[4] = ivec2[4](
		ivec2(t_id[0].x, t_id[1].x),
		ivec2(t_id[0].y, t_id[1].y),
		ivec2(t_id[0].z, t_id[1].z),
		ivec2(t_id[0].w, t_id[1].w));
	
	uint this = control.x;
	float blend = float((this >> 14u) & 0xFFu) / 255.0;
	
	debug_albedo.r = blend;
	//ivec2 this = texture_ids[0];
	//debug_albedo.r = float(this.x == 0);
	
	// Auto blend calculation
	float auto_blend = clamp(fma(auto_slope * 2.0, (normal.y - 1.0), 1.0)
		- auto_height_reduction * 0.01 * world_position.y, 0.0, 1.0);
	
	uvec4 is_auto = control & uvec4(0x1u);
	uint u_auto =
		((uint(0) & 0x1Fu) << 27u) |
		((uint(1) & 0x1Fu) << 22u) |
		((uint(fma(auto_blend, 255.0 , 0.5)) & 0xFFu) << 14u);
	control = control * (1u - is_auto) + u_auto * is_auto;

	
	float slope = clamp(auto_slope * (1.0 - normal.y) - auto_height_reduction * world_position.y * 0.001, 0.0, 1.0);
	// sharpen transition
	float steep_weight = smoothstep(0.4, 0.5, slope);
	float shallow_weight = 1.0 - steep_weight;
	
	vec3 base_p = world_position * 0.02;
	
	vec3 base_ddx = dFdxCoarse(base_p);
	vec3 base_ddy = dFdyCoarse(base_p);
	
	accumulate(base_p, base_ddx, base_ddy, normal, true, steep_weight, steep_albedo_height, steep_normal_rough, material);
	accumulate(base_p, base_ddx, base_ddy, normal, false, shallow_weight, shallow_albedo_height, shallow_normal_rough, material);
	
	float inv_w = 1.0 / max(material.total_weight, 1e-6);
	material.albedo_height *= inv_w;
	material.normal_rough *= inv_w;
	
	ALBEDO = material.albedo_height.rgb;
	ROUGHNESS = material.normal_rough.a;
	AO = material.ao;
	NORMAL_MAP = material.normal_rough.xzy * 0.5 + 0.5;
	
	//vec2 biome_uv = world_position.xz * 0.0001;
	//int biome_count = 5;
	//int biome = int(floor(texture(_control_maps, vec3(UV, lod)).r * float(biome_count) - EPSILON));
	//ALBEDO = vec3(float(biome == 3 || biome == 4));
	
	ALBEDO = debug_albedo;
	//ALBEDO = vec3(0.7);
}