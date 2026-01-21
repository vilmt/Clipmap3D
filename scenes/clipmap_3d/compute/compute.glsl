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

#define PI 3.14159265358979
#define EPSILON 1e-6

#define HEIGHT_FREQUENCY 0.001
#define HEIGHT_OCTAVES 3
#define HEIGHT_GAIN 0.5
#define HEIGHT_LACUNARITY 1.5

#define EROSION_FREQUENCY 0.002
#define EROSION_OCTAVES 3
#define EROSION_GAIN 0.5
#define EROSION_LACUNARITY 2.0

#define EROSION_SLOPE_STRENGTH 2.0 // base slope
#define EROSION_BRANCH_STRENGTH 1.0 // accumulating slope
#define EROSION_STRENGTH 0.04

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

// vec3 erosion(in vec2 p, vec2 slope) {
    // vec2 sideDir = slope.yx * vec2(-1.0, 1.0);
    // vec2 ip = floor(p);
    // vec2 fp = fract(p);
    // float revolution = 2.0 * PI;
    // vec3 va = vec3(0.0);
    // float weightSum = 0.0;
    // for (int i=-2; i<=1; i++)
    // {
        // for (int j=-2; j<=1; j++)
        // {
            // vec2 gridOffset = vec2(i, j);
            // vec2 gridPoint = ip - gridOffset;
            // vec2 randomOffset = hash(gridPoint) * 0.5;
            // vec2 vectorToCellPoint = randomOffset - gridOffset - fp;
            // float sqrDist = dot(vectorToCellPoint, vectorToCellPoint);
            // float weight = exp(-sqrDist * 2.0);
            // weightSum += weight;
            // float waveInput = dot(vectorToCellPoint, sideDir) * revolution;

            // va += vec3(cos(waveInput), sin(waveInput) * sideDir) * weight;
        // }
    // }
    // return va / weightSum;
// }

vec3 erosion(in vec2 p, vec2 dir) {
    vec2 ip = floor(p);
    vec2 fp = fract(p);
    float f = 2.0 * PI;
    vec3 va = vec3(0.0);
    float wt = 0.0;
    for (int i=-2; i<=1; i++)
    {
        for (int j=-2; j<=1; j++)
        {
            vec2 o = vec2(i, j);
            vec2 h = hash(ip - o) * 0.5;
            vec2 pp = fp + o - h;
            float d = dot(pp, pp);
            float w = exp(-d * 2.0);
            wt +=w;
            float mag = dot(pp, dir) * f;
            va += vec3(cos(mag), -sin(mag) * (pp + dir)) * w;
        }
    }
    return va / wt;
}




vec2 height_map(vec2 p) {
	// base fbm terrain, preserves derivatives
	vec2 h_p = p * HEIGHT_FREQUENCY;
	vec3 h = vec3(0.0);
	float h_f = 1.0;
	float h_a = 1.0;
	
	for (int i = 0; i < HEIGHT_OCTAVES; i++) {
		h += noised(h_p * h_f) * h_a * vec3(1.0, h_f, h_f);
		
		h_f *= HEIGHT_LACUNARITY;
		h_a *= HEIGHT_GAIN;
	}
	
	h.x = h.x * 0.5 + 0.5;
	
	vec2 h_dir = h.zy * vec2(1.0, -1.0) * EROSION_SLOPE_STRENGTH;
	
	// erosion, does not preserve derivatives
	vec2 e_p = p * EROSION_FREQUENCY;
	vec3 e = h;
	float e_f = 1.0;
	float e_a = 0.5;
	//e_a *= smoothstep(0.0, 1.0, h.x);
    
    for (int i = 0; i < EROSION_OCTAVES; i++) {
		vec2 e_dir = e.zy * vec2(1.0, -1.0) * EROSION_BRANCH_STRENGTH;
        e += erosion(e_p * e_f, h_dir + e_dir) * e_a * vec3(1.0, e_f, e_f);
		
		e_f *= EROSION_LACUNARITY;
        e_a *= EROSION_GAIN;
    }
	
	e.x = e.x * 0.5 + 0.5;
	
	// TODO: remove - 1.0, arbitrary centering
	return vec2(h.x + e.x * EROSION_STRENGTH, 0.0);
	//return vec2(e.x, 0.0); // debug
}
	
	

void main() {
	ivec3 global_id = ivec3(gl_GlobalInvocationID);
	global_id.z += params.lod;
	ivec3 bounds = imageSize(height_maps);
	
	if (any(greaterThanEqual(global_id, bounds))) {
		return;
	}
	
	ivec2 texel = global_id.xy;
	//int lod = global_id.z;
	int lod = params.lod;
	ivec2 size = bounds.xy;
	
	vec2 scale = params.vertex_spacing * float(1 << lod);
	vec2 inv_scale = 1.0 / scale;
	
	vec2 centered = vec2(texel - size / 2);
	vec2 origin = floor(params.world_origin * inv_scale + EPSILON);
	vec2 uv = (centered + origin) * scale;
	
	vec2 h_00 = height_map(uv);
	vec2 h_10 = height_map(uv + vec2(scale.x, 0.0));
	vec2 h_01 = height_map(uv + vec2(0.0, scale.y));
	
	float h = h_00.x * params.amplitude;
	vec2 d_h = vec2(h_00.x - h_10.x, h_00.x - h_01.x) * params.amplitude;
	
    imageStore(height_maps, global_id, vec4(h, 0.0, 0.0, 0.0));
	imageStore(normal_maps, global_id, vec4(d_h, 0.0, 0.0));
	imageStore(control_maps, global_id, vec4(0.0, 0.0, 0.0, 0.0));
}
