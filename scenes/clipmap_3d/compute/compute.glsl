#[compute]
#version 460

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(r32f, binding = 0) restrict uniform image2DArray height_maps;
layout(rg16f, binding = 1) restrict uniform image2DArray normal_maps;
layout(r32f, binding = 2) restrict uniform image2DArray control_maps;

layout(push_constant, std430) uniform Params {
	vec2 world_origin;
	vec2 vertex_spacing;
	
	int lod;
	int noise_seed; // TODO
	float amplitude;
	float scale;

} params;

#define EPSILON 1e-6
#define TAU 6.28318530717958

vec2 hash21(vec2 p) {
	const vec2 k = vec2(0.3183099, 0.3678794);
	p = p * k + k.yx;
	return -1.0 + 2.0 * fract(16.0 * k * fract( p.x * p.y * (p.x + p.y)));
}

vec2 hash22(vec2 p) {
	vec2 q = vec2(dot(p,vec2(127.1,311.7)), dot(p,vec2(269.5,183.3)));
	return fract(sin(q)*43758.5453);
}

// gradient noise and derivative by IQ https://www.shadertoy.com/view/XdXBRH
vec3 noised(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);

    vec2 u = f*f*f*(f*(f*6.0-15.0)+10.0);
    vec2 du = 30.0*f*f*(f*(f-2.0)+1.0); 
    
    vec2 ga = hash21(i + vec2(0.0, 0.0));
    vec2 gb = hash21(i + vec2(1.0, 0.0));
    vec2 gc = hash21(i + vec2(0.0, 1.0));
    vec2 gd = hash21(i + vec2(1.0, 1.0));
    
    float va = dot(ga, f - vec2(0.0, 0.0));
    float vb = dot(gb, f - vec2(1.0, 0.0));
    float vc = dot(gc, f - vec2(0.0, 1.0));
    float vd = dot(gd, f - vec2(1.0, 1.0));

    return vec3( va + u.x*(vb-va) + u.y*(vc-va) + u.x*u.y*(va-vb-vc+vd),
        ga + u.x*(gb-ga) + u.y*(gc-ga) + u.x*u.y*(ga-gb-gc+gd) +
        du * (u.yx*(va-vb-vc+vd) + vec2(vb,vc) - va));
}

// erosion ridges and analytical derivative
vec3 ridges(vec2 p, vec2 curl) {
	vec2 p_i = floor(p);
	vec2 p_f = fract(p);
	
	vec3 r = vec3(0.0);
	
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 o = vec2(float(i), float(j));
			vec2 d = o - p_f + hash22(p_i + o) * 1.0;
			
			float dd_raw = dot(d, d);
			float dd = min(1.0, dot(d, d));
			
			float w = dd * (dd - 2.0) + 1.0; // quartic interpolant
			vec2 w_d = 4.0 * (1.0 - dd) * d; // derivative
			
			float alignment = dot(d, curl);
			float phase = alignment * TAU;
			
			float c = cos(phase);
			float s = sin(phase);
			
			r += vec3(c * w, TAU * s * curl * w + c * w_d);
		}
	}
	
	return r;
}

// terrain height and derivative
vec3 height_map(vec2 p, vec2 scale) {
    // FBM terrain
	vec3 h = vec3(0.0);
	float h_a = 0.5;
	float h_f = 1.0;
	
	for (int i = 0; i < 6; i++) {
		vec3 n = noised(p * h_f * scale) * h_a;
		h += n * vec3(1.0, h_f * scale); // chain rule
		h_a *= 0.4;
		h_f *= 1.8;
	}
	
	// Erosion
	vec3 e = vec3(0.0);
	float e_a = 0.005;
	float e_f = 20.0;
	
	for (int i = 0; i < 3; i++) {
		vec2 curl = (h.zy + e.zy) * vec2(1.0, -1.0) / scale;
		
		vec3 r = ridges(p * e_f * scale, curl) * e_a;
		e += r * vec3(1.0, e_f * scale); // chain rule
		
		e_a *= 0.5;
		e_f *= 1.8;
	}
	
	h += e;
	h.x += 0.5;
	return h;
}

void main() {
	ivec3 global_id = ivec3(gl_GlobalInvocationID);
	global_id.z += params.lod;
	ivec3 bounds = imageSize(height_maps);
	
	if (any(greaterThanEqual(global_id, bounds))) {
		return;
	}
	
	ivec2 texel = global_id.xy;
	ivec2 size = bounds.xy;
	
	vec2 scale = params.vertex_spacing * float(1 << params.lod);
	vec2 inv_scale = 1.0 / scale;
	
	vec2 centered = vec2(texel - size / 2);
	vec2 origin = floor(params.world_origin * inv_scale + EPSILON);
	vec2 uv = centered + origin;
	
	vec2 sampling_scale = scale * 0.01 * params.scale;
	
	//// analytical
	vec3 h = height_map(uv, sampling_scale) * params.amplitude;
	
	imageStore(height_maps, global_id, vec4(h.x, 0.0, 0.0, 0.0));
	imageStore(normal_maps, global_id, vec4(h.yz, 0.0, 0.0));
	
	//// central difference slop
	// vec3 h_00 = height_map(uv, sampling_scale) * params.amplitude;
	// vec3 h_10 = height_map(uv + vec2(1.0, 0.0), sampling_scale) * params.amplitude;
	// vec3 h_01 = height_map(uv + vec2(0.0, 1.0), sampling_scale) * params.amplitude;
	
	// vec2 d_h = vec2(h_00.x - h_10.x, h_00.x - h_01.x);
	
	// imageStore(height_maps, global_id, vec4(h_00.x, 0.0, 0.0, 0.0));
	// imageStore(normal_maps, global_id, vec4(-d_h, 0.0, 0.0));
	
	imageStore(control_maps, global_id, vec4(0.0, 0.0, 0.0, 0.0));
}
