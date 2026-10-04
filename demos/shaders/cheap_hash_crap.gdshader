shader_type spatial;
render_mode blend_mix, skip_vertex_transform;

// TODO: separate geomorph from lod in fragment.
// Geomorph lod should always be gradual, whereas the fragment lod blend region should be as
// small as possible to reduce noise from the stochastic blending technique.

const uint MAX_TEXTURE_COUNT = 32u;

const uint FLAG_STOCHASTIC_OFFSET = 1u << 0u;
const uint FLAG_STOCHASTIC_ROTATION = 1u << 1u;
const uint FLAG_PROJECTED_STOCHASTIC_OFFSET = 1u << 2u;
const uint FLAG_PROJECTED_STOCHASTIC_ROTATION = 1u << 3u;
const uint FLAG_DUAL_SCALING = 1u << 4u;

uniform int dual_scaling_lod: hint_range(0, 10) = 3;
uniform float dual_scaling_factor = 0.2;

uniform sampler2D stochastic_noise: filter_nearest;

uniform float mip_bias: hint_range(-3.0, 3.0) = 0.0;

uniform float lod_blend_ratio: hint_range(0.0, 0.5) = 0.2;

group_uniforms private;

instance uniform int _vertex_lod;

uniform vec3 _target_position;
uniform vec2 _vertex_spacing;
uniform ivec2 _texels_per_vertex;

uniform sampler2DArray _albedo_textures: source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform int[MAX_TEXTURE_COUNT] _albedo_remap;
uniform sampler2DArray _normal_textures: hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform int[MAX_TEXTURE_COUNT] _normal_remap;

uniform vec2[MAX_TEXTURE_COUNT] _uv_scales;
uniform vec3[MAX_TEXTURE_COUNT] _albedo_modulates: source_color;
uniform float[MAX_TEXTURE_COUNT] _roughness_offsets;
uniform float[MAX_TEXTURE_COUNT] _normal_depths;
uniform float[MAX_TEXTURE_COUNT] _height_amplifications;
uniform uint[MAX_TEXTURE_COUNT] _flags;

uniform highp sampler2DArray _height_buffer: hint_default_black, repeat_enable, filter_linear;
uniform highp sampler2DArray _control_buffer: hint_default_black, repeat_enable, filter_nearest;

varying vec3 world_position;

varying float vertex_lod_fract;

varying flat vec3 debug_albedo;

vec2 get_uv(vec2 texel, vec2 sampler_size) {
	return (texel + 0.5) / sampler_size;
}

vec2 get_bilinear_uv(vec2 texel, vec2 sampler_size) {
	return (floor(texel) + 0.5) / sampler_size;
}

vec4 get_bilinear_weights(vec2 texel) {
	vec2 w = fract(texel);
	//w = w * w * (3.0 - 2.0 * w); // smoothstep interpolant
	vec2 w_inv = 1.0 - w;
	return vec4(w_inv.x, w.x, w_inv.x, w.x) * vec4(w_inv.y, w_inv.y, w.y, w.y);
}

void vertex() {
	ivec3 buffer_size = textureSize(_height_buffer, 0);
	
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// Scale and LOD from transform
	
	// Scale: exp2(lod) * vertex_spacing
	vec2 scale = vec2(MODEL_MATRIX[0][0], MODEL_MATRIX[2][2]);
	
	vec2 target_texel = _target_position.xz * vec2(_texels_per_vertex) / scale;
	vec2 texel = world_position.xz * vec2(_texels_per_vertex) / scale;
	
	// Vertex LOD (LOD transition mask)
	
	vec2 half_size = vec2(buffer_size.xy / 2 - _texels_per_vertex); // Half formula from compute_handler.gd
	vec2 lod_origin = (texel - target_texel) / half_size;
	float blend_mask = max(abs(lod_origin.x), abs(lod_origin.y));
	float lod_fract = smoothstep(1.0 - lod_blend_ratio, 1.0, blend_mask);
	lod_fract = _vertex_lod >= buffer_size.z - 1 ? 0.0 : lod_fract; // Ensure outer LOD does not blend
	lod_fract = max(0.0, lod_fract - 1e-5);
	
	vertex_lod_fract = lod_fract;
	
	// LOD Geo-morphing
	
	vec2 geomorph = lod_fract * mod(floor(world_position.xz / scale + 0.5), 2.0);
	world_position.xz += geomorph * scale;
	texel += geomorph * vec2(_texels_per_vertex);
	
	// Height sampling
	
	vec2 uv = get_uv(texel, vec2(buffer_size.xy));
	world_position.y = texture(_height_buffer, vec3(uv, float(_vertex_lod))).r;
	
	VERTEX = (VIEW_MATRIX * vec4(world_position, 1.0)).xyz;
	
	// Buffer sampling position
	
	UV = world_position.xz * vec2(_texels_per_vertex) / _vertex_spacing;
}

struct Material {
	vec3 albedo;
	float roughness;
	vec2 normal_map;
	float normal_map_depth;
	float ao;
};

void accumulate_material(inout Material mat, uvec2 ids, float weight, float blend, vec3 N, vec3 P, vec3 dPdx, vec3 dPdy, float seed, float lod) {
	uint flags_0 = _flags[ids[0]];
	uint flags_1 = _flags[ids[1]];
		
	mat2 projection_align = mat2(1.0);
	
	//float dual_scale
	
	//float offset_mult_0 = float(flags_0 & FLAG_STOCHASTIC_OFFSET);
	//float angle_mult_0 = float(flags_0 & FLAG_STOCHASTIC_ROTATION);
	//
	//float offset_mult_1 = float(flags_1 & FLAG_STOCHASTIC_OFFSET);
	//float angle_mult_1 = float(flags_1 & FLAG_STOCHASTIC_ROTATION);
	
	if (N.y <= 0.7071067811865475) { // sqrt(0.5)
		// Projected normal map alignment matrix
		projection_align = mat2(vec2(N.z, -N.x), vec2(N.x, N.z));
		// Fast 45 degree snapping https://iquilezles.org/articles/noatan/
		vec2 xz = round(normalize(-N.xz) * 1.3065629648763765); // sqrt(1.0 + sqrt(0.5))
		xz *= abs(xz.x) + abs(xz.y) > 1.5 ? 0.7071067811865475 : 1.0; // sqrt(0.5)
		xz = vec2(-xz.y, xz.x);
		
		P.xz = vec2(dot(P.xz, xz), -P.y);
		dPdx.xz = vec2(dot(dPdx.xz, xz), -dPdx.y);
		dPdy.xz = vec2(dot(dPdy.xz, xz), -dPdy.y);
		
		//offset_mult_0 = float(flags_0 & FLAG_PROJECTED_STOCHASTIC_OFFSET);
		//angle_mult_0 = float(flags_0 & FLAG_PROJECTED_STOCHASTIC_ROTATION);
		//
		//offset_mult_1 = float(flags_1 & FLAG_PROJECTED_STOCHASTIC_OFFSET);
		//angle_mult_1 = float(flags_1 & FLAG_PROJECTED_STOCHASTIC_ROTATION);
	}
	
	vec3 albedo_0 = vec3(0.0);
	float roughness_0 = 0.0;
	vec2 normal_map_0 = vec2(0.0);
	float height_0 = 0.0;
	float ao_0 = 0.0;
	float normal_map_depth_0 = 0.0;
	
	if (blend < 0.999) {
		uint id = ids[0];
		
		int albedo_id = _albedo_remap[id];
		int normal_id = _normal_remap[id];
		
		vec2 s = _uv_scales[id];
		s *= lod > float(dual_scaling_lod) - 0.5 && bool(flags_0 & FLAG_DUAL_SCALING) ? dual_scaling_factor : 1.0;
		
		float angle = 0.0;//seed * TAU * angle_mult_0;
		float angle_cos = cos(angle), angle_sin = sin(angle);
		
		mat2 angle_rot = mat2(vec2(angle_cos, angle_sin), vec2(-angle_sin, angle_cos));
		
		vec2 uv = P.xz * s;
		vec2 duvdx = dPdx.xz * s;
		vec2 duvdy = dPdy.xz * s;
		
		uv = angle_rot * (uv + 0.5) - 0.5;
		duvdx = angle_rot * duvdx;
		duvdy = angle_rot * duvdy;
		
		vec4 al_r = textureGrad(_albedo_textures, vec3(uv, float(albedo_id)), duvdx, duvdy);
		vec4 nr_h_ao = textureGrad(_normal_textures, vec3(uv, float(normal_id)), duvdx, duvdy);
		nr_h_ao.rg = fma(nr_h_ao.rg, vec2(2.0), vec2(-1.0));
		nr_h_ao.rg = nr_h_ao.rg * projection_align;
		nr_h_ao.rg = angle_rot * nr_h_ao.rg;
		
		albedo_0 = al_r.rgb * _albedo_modulates[id];
		roughness_0 = clamp(al_r.a + _roughness_offsets[id], 0.0, 1.0);
		normal_map_0 = nr_h_ao.rg;
		height_0 = nr_h_ao.b;
		ao_0 = nr_h_ao.a;
		normal_map_depth_0 = _normal_depths[id];
	}
	
	vec3 albedo_1 = vec3(0.0);
	float roughness_1 = 0.0;
	vec2 normal_map_1 = vec2(0.0);
	float height_1 = 0.0;
	float ao_1 = 0.0;
	float normal_map_depth_1 = 0.0;
	
	if (blend > 0.001) {
		uint id = ids[1];
		
		int albedo_id = _albedo_remap[id];
		int normal_id = _normal_remap[id];
		
		vec2 s = _uv_scales[id];
		s *= lod > float(dual_scaling_lod) - 0.5 && bool(flags_1 & FLAG_DUAL_SCALING) ? dual_scaling_factor : 1.0;
		
		float angle = 0.0;//seed * TAU * angle_mult_1;
		float angle_cos = cos(angle), angle_sin = sin(angle);
		
		mat2 angle_rot = mat2(vec2(angle_cos, angle_sin), vec2(-angle_sin, angle_cos));
		
		vec2 uv = P.xz * s;
		vec2 duvdx = dPdx.xz * s;
		vec2 duvdy = dPdy.xz * s;
		
		uv = angle_rot * (uv + 0.5) - 0.5;
		duvdx = angle_rot * duvdx;
		duvdy = angle_rot * duvdy;
		
		vec4 al_r = textureGrad(_albedo_textures, vec3(uv, float(albedo_id)), duvdx, duvdy);
		vec4 nr_h_ao = textureGrad(_normal_textures, vec3(uv, float(normal_id)), duvdx, duvdy);
		nr_h_ao.rg = fma(nr_h_ao.rg, vec2(2.0), vec2(-1.0));
		nr_h_ao.rg = nr_h_ao.rg * projection_align;
		nr_h_ao.rg = angle_rot * nr_h_ao.rg;
		
		albedo_1 = al_r.rgb * _albedo_modulates[id];
		roughness_1 = clamp(al_r.a + _roughness_offsets[id], 0.0, 1.0);
		normal_map_1 = nr_h_ao.rg;
		height_1 = nr_h_ao.b;
		ao_1 = nr_h_ao.a;
		normal_map_depth_1 = _normal_depths[id];
	}
	
	// Height-based texture blending
	
	const float amplify = 3.0;
	const float depth = 0.1;
	
	height_0 = fma(height_0 + 0.5, amplify * _height_amplifications[ids[0]], -0.5);
	height_1 = fma(height_1 + 0.5, amplify * _height_amplifications[ids[1]], -0.5);
	
	float value_0 = height_0 + (1.0 - blend);
	float value_1 = height_1 + blend;
	
	float max_height = max(value_0, value_1);
	float relative_height_0 = max(value_0 - max_height + depth, 0.0);
	float relative_height_1 = max(value_1 - max_height + depth, 0.0);
	
	blend = relative_height_1 / (relative_height_0 + relative_height_1);
	
	// Accumulation
	
	float w0 = (1.0 - blend) * weight;
	float w1 = blend * weight;
	
	mat.albedo = fma(albedo_0, vec3(w0), fma(albedo_1, vec3(w1), mat.albedo));
	mat.roughness = fma(roughness_0, w0, fma(roughness_1, w1, mat.roughness));
	mat.normal_map = fma(normal_map_0, vec2(w0), fma(normal_map_1, vec2(w1), mat.normal_map));
	mat.ao = fma(ao_0, w0, fma(ao_1, w1, mat.ao));
	mat.normal_map_depth = fma(normal_map_depth_0, w0, fma(normal_map_depth_1, w1, mat.normal_map_depth));
}

float hash(ivec3 position) {
	uvec3 v = uvec3(position);

	v = v * 1664525u + 1013904223u;

	v.x += v.y*v.z;
	v.y += v.z*v.x;
	v.z += v.x*v.y;

	v ^= v >> 16u;

	v.x += v.y*v.z;
	v.y += v.z*v.x;
	v.z += v.x*v.y;
	
	return float(v.x) / 4294967296.0;
}

void fragment() {
	ivec3 buffer_size = textureSize(_height_buffer, 0);
	
	// Hash lod selection
	
	// TODO: fix MSAA wrapping seams.
	
	float maxDeriv = max(length(dFdx(world_position)), length(dFdy(world_position)));
	
	const float hash_pixel_scale = 1.5;
	
	float pixScale = 1.0 / (hash_pixel_scale*maxDeriv);
	
	float log2scale = log2(pixScale);
	// Find two nearest log-discretized noise scales
	vec2 pixScales = vec2( exp2(floor(log2scale)), exp2(ceil(log2scale)) );
	// Compute alpha thresholds at our two noise scales
	vec2 alpha = vec2(
		hash(ivec3(floor(pixScales.x*world_position))),
		hash(ivec3(floor(pixScales.y*world_position)))
	);
	// Factor to interpolate lerp with
	float lerpFactor = fract(log2scale);
	// Interpolate alpha threshold from noise at two scales
	float x = mix(alpha.x, alpha.y, lerpFactor);
	// Pass into CDF to compute uniformly distrib threshold
	float a = min(lerpFactor, 1.0 - lerpFactor);
	vec3 cases = vec3( x*x/(2.0*a*(1.0-a)),
	(x-0.5*a)/(1.0-a),
	1.0-((1.0-x)*(1.0-x)/(2.0*a*(1.0-a))) );
	// Find our final, uniformly distributed alpha threshold
	float threshold = (x < (1.0-a)) ? ((x < a) ? cases.x : cases.y) : cases.z;
	
	//
	
	float lod = float(_vertex_lod) + vertex_lod_fract;
	
	lod = vertex_lod_fract > threshold ? ceil(lod) : floor(lod);
	
	vec2 texel = UV * exp2(-lod);
	
	// Sampling space
	
	vec2 bilinear_uv = get_bilinear_uv(texel, vec2(buffer_size.xy));
	vec4 bilinear_weights = get_bilinear_weights(texel);
	
	// Offset is same for both lods since using uv coordinates
	vec2 offset = 1.0 / vec2(buffer_size.xy);
	
	// LOD N gradients
	
	vec4 heights_00 = textureGather(_height_buffer, vec3(bilinear_uv, lod), 0).wzxy;
	vec4 heights_10 = textureGather(_height_buffer, vec3(bilinear_uv + vec2(offset.x, 0.0), lod), 0).wzxy;
	vec4 heights_01 = textureGather(_height_buffer, vec3(bilinear_uv + vec2(0.0, offset.y), lod), 0).wzxy;
	vec4 heights_11 = textureGather(_height_buffer, vec3(bilinear_uv + offset, lod), 0).wzxy;
	
	vec4 h00 = vec4(heights_00.x, heights_10.x, heights_01.x, heights_11.x);
	vec4 h10 = vec4(heights_00.y, heights_10.y, heights_01.y, heights_11.y);
	vec4 h01 = vec4(heights_00.z, heights_10.z, heights_01.z, heights_11.z);
	
	vec2 gradient_scale = vec2(_texels_per_vertex) * exp2(-lod) / _vertex_spacing;
	
	vec4 gradients_x = (h10 - h00) * gradient_scale.x;
	vec4 gradients_y = (h01 - h00) * gradient_scale.y;
	
	vec2 gradient = vec2(dot(gradients_x, bilinear_weights), dot(gradients_y, bilinear_weights));
	
	// Normals for lighting
	
	vec3 normal = normalize(vec3(-gradient.x, 1.0, -gradient.y));
	vec3 tangent = normalize(cross(normal, vec3(0.0, 0.0, 1.0)));
	vec3 binormal = normalize(cross(normal, tangent));
	
	NORMAL = (VIEW_MATRIX * vec4(normal, 0.0)).xyz;
	TANGENT = (VIEW_MATRIX * vec4(tangent, 0.0)).xyz;
	BINORMAL = (VIEW_MATRIX * vec4(binormal, 0.0)).xyz;
	
	// Separate normals for projection
	
	vec3 normals[4] = {
		normalize(vec3(-gradients_x.x, 1.0, -gradients_y.x)),
		normalize(vec3(-gradients_x.y, 1.0, -gradients_y.y)),
		normalize(vec3(-gradients_x.z, 1.0, -gradients_y.z)),
		normalize(vec3(-gradients_x.w, 1.0, -gradients_y.w))
	};
	
	// Texture sampling space
	
	vec3 P = world_position;
	vec3 dPdx = dFdxCoarse(P);
	vec3 dPdy = dFdyCoarse(P);
	
	// Control lookups
	
	uvec4 controls = floatBitsToUint(textureGather(_control_buffer, vec3(bilinear_uv, lod), 0).wzxy);
	
	// Texture weight accumulation from control
	
	uvec4 ids_0 = controls >> uvec4(27u) & uvec4(0x1Fu);
	uvec4 ids_1 = controls >> uvec4(22u) & uvec4(0x1Fu);
	vec4 blends = vec4(controls >> uvec4(14u) & uvec4(0xFFu)) / 255.0;
	
	vec4 weights = bilinear_weights;
	
	uvec2 ids[4] = uvec2[4](
		uvec2(ids_0[0], ids_1[0]),
		uvec2(ids_0[1], ids_1[1]),
		uvec2(ids_0[2], ids_1[2]),
		uvec2(ids_0[3], ids_1[3])
	);
	
	// Material accumulation
	
	Material mat = Material(vec3(0.0), 0.0, vec2(0.0), 0.0, 0.0);
	
	accumulate_material(mat, ids[0], weights[0], blends[0], normals[0], P, dPdx, dPdy, 0.0, lod);
	accumulate_material(mat, ids[1], weights[1], blends[1], normals[1], P, dPdx, dPdy, 0.0, lod);
	accumulate_material(mat, ids[2], weights[2], blends[2], normals[2], P, dPdx, dPdy, 0.0, lod);
	accumulate_material(mat, ids[3], weights[3], blends[3], normals[3], P, dPdx, dPdy, 0.0, lod);
	
	// PBR
	
	ALBEDO = mat.albedo;
	ROUGHNESS = mat.roughness;
	NORMAL_MAP.rg = fma(mat.normal_map, vec2(0.5), vec2(0.5));
	NORMAL_MAP_DEPTH = mat.normal_map_depth;
	AO = mat.ao;
	
	//ALBEDO = vec3(vertex_lod_fract);
}