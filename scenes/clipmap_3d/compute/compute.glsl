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
#define PI 3.14159265358979

vec2 hash21(vec2 p) {
	const vec2 k = vec2(0.3183099, 0.3678794);
	p = p * k + k.yx;
	return -1.0 + 2.0 * fract(16.0 * k * fract( p.x * p.y * (p.x + p.y)));
}

vec2 hash22(vec2 p) {
	vec2 q = vec2(dot(p,vec2(127.1,311.7)), dot(p,vec2(269.5,183.3)));
	return fract(sin(q)*43758.5453);
}

// https://www.shadertoy.com/view/XdXBRH
vec3 noised(in vec2 p) {
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

vec3 ridges(vec2 p, vec2 gradient, vec2 scale) {
	// scaling is wrong
	vec2 curl = gradient.yx * vec2(1.0, -1.0) / scale;
	
	float f = 10.0;
	float a = 1.0;
	
	p *= scale * f;
	
	vec2 p_i = floor(p);
	vec2 p_f = fract(p);
	
	float height = 0.0;
	vec2 d = vec2(0.0);
	
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 offset = vec2(float(i), float(j));
			vec2 displacement = offset - p_f + hash22(p_i + offset) * 1.0;
			float dd = min(1.0, dot(displacement, displacement));
			float weight = dd * (dd - 2.0) + 1.0; // quartic interpolant pa que sepan
			
			float alignment = dot(displacement, curl);
			
			float phase = alignment * 2.0 * PI;
			
			height += cos(phase) * weight;
			//d += -sin(phase) * (displacement + curl) * weight;
			
		}
	}
	
	height *= a;
	
	return vec3(height, d);
}

vec3 fbmd(vec2 p, vec2 scale) {
	float h = 0.0;
	vec2 d = vec2(0.0);
	float a = 0.5;
	float f = 1.0;
	
	for (int i = 0; i < 2; i++) {
		vec3 n = noised(p * f * scale);
		h += a * n.x;
		d += a * n.yz * f * scale;
		a *= 0.5;
		f *= 1.8;
	}
	
	return vec3(h, d);
}

vec3 height_map(vec2 p, vec2 scale) {
    // FBM terrain
    vec3 h = fbmd(p, scale); // all correct
	
	vec3 e = ridges(p, h.yz, scale);

	h.x += e.x * 0.01;
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
	
	vec3 h_00 = height_map(uv, sampling_scale) * params.amplitude;
	vec3 h_10 = height_map(uv + vec2(1.0, 0.0), sampling_scale) * params.amplitude;
	vec3 h_01 = height_map(uv + vec2(0.0, 1.0), sampling_scale) * params.amplitude;
	
	vec2 d_h = vec2(h_00.x - h_10.x, h_00.x - h_01.x);
	
	imageStore(height_maps, global_id, vec4(h_00.x, 0.0, 0.0, 0.0));
	//imageStore(normal_maps, global_id, vec4(h.yz, 0.0, 0.0));
	imageStore(normal_maps, global_id, vec4(-d_h, 0.0, 0.0));
	imageStore(control_maps, global_id, vec4(0.0, 0.0, 0.0, 0.0));
}
