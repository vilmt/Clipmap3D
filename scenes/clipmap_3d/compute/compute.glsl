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
	float pad2;

} params;

#define EPSILON 1e-6

vec2 hash(in vec2 x) {
	const vec2 k = vec2( 0.3183099, 0.3678794 );
	x = x * k + k.yx;
	return -1.0 + 2.0 * fract(16.0 * k * fract( x.x * x.y * (x.x + x.y)));
}

// https://www.shadertoy.com/view/XdXBRH
vec3 noised(in vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);

    vec2 u = f*f*f*(f*(f*6.0-15.0)+10.0);
    vec2 du = 30.0*f*f*(f*(f-2.0)+1.0); 
    
    vec2 ga = hash(i + vec2(0.0, 0.0));
    vec2 gb = hash(i + vec2(1.0, 0.0));
    vec2 gc = hash(i + vec2(0.0, 1.0));
    vec2 gd = hash(i + vec2(1.0, 1.0));
    
    float va = dot(ga, f - vec2(0.0, 0.0));
    float vb = dot(gb, f - vec2(1.0, 0.0));
    float vc = dot(gc, f - vec2(0.0, 1.0));
    float vd = dot(gd, f - vec2(1.0, 1.0));

    return vec3( va + u.x*(vb-va) + u.y*(vc-va) + u.x*u.y*(va-vb-vc+vd),
        ga + u.x*(gb-ga) + u.y*(gc-ga) + u.x*u.y*(ga-gb-gc+gd) +
        du * (u.yx*(va-vb-vc+vd) + vec2(vb,vc) - va));
}

vec3 height_map(vec2 uv, vec2 scale) {
    // FBM terrain
    vec3 h = vec3(0.0);
    float h_f = 1.0;
    float h_a = 0.5;
	
    for (int i = 0; i < 8; i++) {
		vec2 s = scale * h_f;
        h += noised(uv * s) * h_a * vec3(1.0, s);
		h_f *= 1.8;
        h_a *= 0.5;
    }
    
    h.x += 0.5;
	
	// TODO: fake erosion
    
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
	
	vec3 h = height_map(uv, scale * 0.001) * params.amplitude;

	imageStore(height_maps, global_id, vec4(h.x, 0.0, 0.0, 0.0));
	imageStore(normal_maps, global_id, vec4(h.yz, 0.0, 0.0));
	imageStore(control_maps, global_id, vec4(0.0, 0.0, 0.0, 0.0));
}
