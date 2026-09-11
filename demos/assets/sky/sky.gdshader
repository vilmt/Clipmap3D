shader_type sky;
render_mode use_quarter_res_pass, use_half_res_pass;

#define H(p)  fract(sin(mod(dot(p, vec2(12.9898, 78.233)),6.283)) * 43758.5453)

const float EPS = 1e-6;
const float INFINITY = 1.0 / 0.0;
const float PLANET_RADIUS = 6371000.0;
const vec3 PLANET_CENTER = vec3(0.0, -PLANET_RADIUS, 0.0);
const float ATMOSPHERE_HEIGHT = 100000.0;
const float RAYLEIGH_HEIGHT = (ATMOSPHERE_HEIGHT * 0.08);
const float MIE_HEIGHT = (ATMOSPHERE_HEIGHT * 0.012);

uniform bool use_debanding = true;

// ATMOSPHERE UNIFORMS
group_uniforms Atmosphere;
uniform int atmosphere_sample_count = 64;

uniform float elevation = 0.0;

uniform float rayleigh_strength : hint_range(0.0, 5.0) = 1.0;
uniform float mie_strength      : hint_range(0.0, 5.0) = 1.0;
uniform float ozone_strength    : hint_range(0.0, 5.0) = 1.0;

const vec3 C_RAYLEIGH = vec3(5.802, 13.558, 33.100) * 1e-6;
const vec3 C_MIE = vec3(3.996,  3.996,  3.996) * 1e-6;
const vec3 C_OZONE = vec3(0.650,  1.881,  0.085) * 1e-6;

uniform float mie_anisotropy_factor = 0.75;

uniform float atmosphere_density: hint_range(0.0, 5.0) = 1.0;
uniform float exposure = 10.0;

uniform float sun_disc_feather: hint_range(0.0, 1.0) = 0.5;
uniform float sundisc_intensity = 100.0;

// STAR UNIFORMS
group_uniforms Stars;
uniform samplerCube stars_hdr : filter_linear, source_color, hint_default_black;
uniform float stars_exposure: hint_range(0.0, 10.0) = 5.0;
uniform mat3 stars_rotation = mat3(1.0);
uniform bool dim_stars_at_day = true;

#define MAX_DIST 10000.0
#define MAX_MARCHES 64
#define SURF_DIST .01

// MOON UNIFORMS
group_uniforms Moons;
uniform float moon_dist[3];
uniform float moon_uv_x_offset[3];
uniform sampler2D moon_textures[3];

// CLOUD UNIFORMS
#define LOWER_PLANE_HEIGHT 3.0

group_uniforms CumulusClouds;
uniform bool hole_in_center = false;
uniform float hole_radius = 5.0;
uniform float hole_feather = 10.0;
uniform float cloud_falloff_coeff: hint_range(0.0, 1.0) = 0.3;
uniform float clouds_alpha_lower_bound = 0.0;
uniform float clouds_alpha_upper_bound = 0.15;

uniform sampler2D cloud_color_texture: hint_default_white;
uniform vec3 cloud_base_color: source_color = vec3(.85, .85, .9);
uniform vec3 cloud_overcast_color: source_color = vec3(.35, .4, .45);

uniform float coverage: hint_range(0.0, 1.0) = 0.35;
uniform float cloud_smoothness: hint_range(0.0, 0.2) = 0.05;

group_uniforms CumulusClouds.RayMarchParameters;
uniform bool apply_stochastic_jitter = false;
uniform float stochastic_jitter_amount: hint_range(0.0, 1.0) = 0.1;
uniform float cloud_base_march_dist = 10.0;
uniform int cloud_marches: hint_range(4, 64, 1) = 64;
uniform float density_coeff: hint_range(0.0, 2.0) = 1.0;

group_uniforms CumulusClouds.Textures;
uniform float cloud_noise_factor: hint_range(0.0, 1.0) = 0.5;
uniform sampler3D cloud_shape : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float cloud_shape_size = 1.0;
uniform vec3 cloud_shape_offset = vec3(0.0);
uniform sampler3D cloud_noise: filter_linear_mipmap_anisotropic, repeat_enable;
uniform float cloud_noise_size = 1.0;
uniform vec3 cloud_noise_offset = vec3(0.0);

group_uniforms CumulusClouds.LightPass;
uniform float clouds_anisotropy_factor: hint_range(0.0, 1.0) = 0.25;
uniform int light_marches: hint_range(4, 32, 1) = 8;
uniform float light_max_dist = 5.0;
uniform float light_strength = 15.0;

group_uniforms CirrusClouds;
uniform bool use_cirrus = true;
uniform sampler2D cirrus_texture: hint_default_black;
uniform vec2 cirrus_squish = vec2(4.0, 1.0);
uniform float cirrus_scale = 1.0;
uniform float cirrus_treshold: hint_range(0.0, 1.0) = .75;
uniform float cirrus_feather: hint_range(0.0, 1.0) = .25;
uniform vec2 cirrus_offset = vec2(0.0);
uniform sampler2D cirrus_distortion_texture: hint_default_black;
uniform float cirrus_distortion_scale = 1.0;
uniform float cirrus_distortion_strength = .4;
uniform vec2 cirrus_distortion_offset = vec2(0.0);
uniform sampler2D cirrus_mask_texture: hint_default_white;
uniform float cirrus_mask_scale = 1.0;
uniform float cirrus_mask_treshold: hint_range(0.0, 1.0) = .6;
uniform float cirrus_mask_feather: hint_range(0.0, 1.0) = .4;
uniform float cirrus_opacity: hint_range(0.0, 1.0) = 0.2;

group_uniforms Rainbow;
uniform bool use_rainbow = false;
uniform bool behind_clouds = false;
uniform sampler2D rainbow_gradient: hint_default_white, filter_linear;
uniform float rainbow_width = .05;
uniform float rainbow_offset = .65;
uniform float rainbow_opacity: hint_range(0.0, 1.0) = .1;
uniform bool double_rainbow = true;


#define saturate(a) clamp(a, 0.0, 1.0)

vec2 sphere_intersection (vec3 rayStart, vec3 rayDir, vec3 sphereCenter, float sphereRadius)
{
	rayStart -= sphereCenter;
	float a = dot(rayDir, rayDir);
	float b = 2.0 * dot(rayStart, rayDir);
	float c = dot(rayStart, rayStart) - (sphereRadius * sphereRadius);
	float d = b * b - 4.0 * a * c;
	if (d < 0.0)
	{
		return vec2(-1.0);
	}
	else
	{
		d = sqrt(d);
		return vec2(-b - d, -b + d) / (2.0 * a);
	}
}

vec2 planet_intersection (vec3 rayStart, vec3 rayDir)
{
	return sphere_intersection(rayStart, rayDir, PLANET_CENTER, PLANET_RADIUS);
}

vec2 atmosphere_intersection (vec3 rayStart, vec3 rayDir)
{
	return sphere_intersection(rayStart, rayDir, PLANET_CENTER, PLANET_RADIUS + ATMOSPHERE_HEIGHT);
}

float phase_rayleigh (float costh)
{
	return 3.0 * (1.0 + costh*costh) / (16.0 * PI);
}

float phase_mie (float costh)
{
	float g = min(mie_anisotropy_factor, 0.9381);
	float k = 1.55*g - 0.55*g*g*g;
	float kcosth = k*costh;
	return (1.0 - k*k) / ((4.0 * PI) * (1.0-kcosth) * (1.0-kcosth));
}

float atmosphere_height (vec3 position_world_space) {
	return distance(position_world_space, PLANET_CENTER) - PLANET_RADIUS;
}
float density_rayleigh (float h) {
	return exp(-max(0.0, h / RAYLEIGH_HEIGHT));
}
float density_mie (float h) {
	return exp(-max(0.0, h / MIE_HEIGHT));
}
float density_ozone (float h) {
	return max(0.0, 1.0 - abs(h - 25000.0) / 15000.0);
}
vec3 density_atmosphere (float h) {
	return vec3(density_rayleigh(h), density_mie(h), density_ozone(h));
}

vec3 integrate_optical_depth (vec3 rayStart, vec3 rayDir)
{
	vec2 intersection = atmosphere_intersection(rayStart, rayDir);
	float  rayLength    = intersection.y;

	int    sampleCount  = 8;
	float  stepSize     = rayLength / float(sampleCount);

	vec3 opticalDepth = vec3(0.0);

	for (int i = 0; i < sampleCount; i++)
	{
		vec3 localPosition = rayStart + rayDir * (float(i) + 0.5) * stepSize;
		float localHeight  = atmosphere_height(localPosition);
		vec3 localDensity  = density_atmosphere(localHeight);

		opticalDepth += localDensity * stepSize;
	}

	return opticalDepth;
}

vec3 absorb (vec3 opticalDepth) {
	return exp(-(
		opticalDepth.x * C_RAYLEIGH * rayleigh_strength +
		opticalDepth.y * C_MIE * mie_strength +
		opticalDepth.z * C_OZONE * ozone_strength
	) * atmosphere_density);
}

vec3 integrate_scattering (vec3 rayStart, vec3 rayDir, float rayLength, vec3 lightDir, vec3 lightColor, out vec3 transmittance)
{
	float  rayHeight = atmosphere_height(rayStart);
	float  sampleDistributionExponent = 1.0 + saturate(1.0 - rayHeight / ATMOSPHERE_HEIGHT) * 8.0;

	vec2 intersection = atmosphere_intersection(rayStart, rayDir);
	rayLength = min(rayLength, intersection.y);
	if (intersection.x > 0.0)
	{
		rayStart += rayDir * intersection.x;
		rayLength -= intersection.x;
	}

	float  costh    = dot(rayDir, lightDir);
	float  phaseR   = phase_rayleigh(costh);
	float  phaseM   = phase_mie(costh);

	vec3 opticalDepth = vec3(0.0);
	vec3 rayleigh     = vec3(0.0);
	vec3 mie          = vec3(0.0);

	float  prevRayTime  = 0.0;

	for (int i = 0; i < atmosphere_sample_count; i++)
	{
		float  rayTime = pow(float(i) / float(atmosphere_sample_count), sampleDistributionExponent) * rayLength;
		float  stepSize = (rayTime - prevRayTime);

		vec3 localPosition = rayStart + rayDir * rayTime;
		float  localHeight   = atmosphere_height(localPosition);
		vec3 localDensity  = density_atmosphere(localHeight);

		opticalDepth += localDensity * stepSize;

		vec3 viewTransmittance = absorb(opticalDepth);

		vec3 opticalDepthlight  = integrate_optical_depth(localPosition, lightDir);
		vec3 lightTransmittance = absorb(opticalDepthlight);

		rayleigh += viewTransmittance * lightTransmittance * phaseR * localDensity.x * stepSize;
		mie      += viewTransmittance * lightTransmittance * phaseM * localDensity.y * stepSize;

		prevRayTime = rayTime;
	}

	transmittance = absorb(opticalDepth);

	return (rayleigh * C_RAYLEIGH * rayleigh_strength + mie * C_MIE * mie_strength) * lightColor * exposure;
}

float sun_disc(vec3 eyedir, vec3 sundir, float theta_r) {
	float cos_angle = dot(eyedir, sundir);
	float cos_inner = cos(theta_r * (1.0 - sun_disc_feather));
	float cos_outer = cos(theta_r * (1.0 + sun_disc_feather));
	return smoothstep(cos_outer, cos_inner, cos_angle);
}

float rand(vec2 co){
    return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

float sdf_sphere(vec3 ray_origin, vec3 sphere_origin, float sphere_radius) {
	return  length(sphere_origin - ray_origin) - sphere_radius;
}

struct Hit {
	float dist;
	int id;
};

Hit get_dist(vec3 marched_ray) {
	Hit closest = Hit(1e20, -1);

	if (LIGHT1_ENABLED) {
		vec3 moon_pos = LIGHT1_DIRECTION * moon_dist[0];
		float dist = sdf_sphere(marched_ray, moon_pos, LIGHT1_SIZE * 100.0);
		if (dist < closest.dist) {
			closest.dist = dist;
			closest.id = 0;
		}
	}
	if (LIGHT2_ENABLED) {
		vec3 moon_pos = LIGHT2_DIRECTION * moon_dist[1];
		float dist = sdf_sphere(marched_ray, moon_pos, LIGHT2_SIZE * 100.0);
		if (dist < closest.dist) {
			closest.dist = dist;
			closest.id = 1;
		}
	}
	if (LIGHT3_ENABLED) {
		vec3 moon_pos = LIGHT3_DIRECTION * moon_dist[2];
		float dist = sdf_sphere(marched_ray, moon_pos, LIGHT3_SIZE * 100.0);
		if (dist < closest.dist) {
			closest.dist = dist;
			closest.id = 2;
		}
	}

	return closest;
}

Hit raymarch_moons(vec3 ray_direction) {
	Hit distance_so_far = Hit(0.0, 0);

	for (int i = 0; i < MAX_MARCHES; i++) {
		vec3 marched_ray = ray_direction * distance_so_far.dist;
		Hit distance_to_scene = get_dist(marched_ray);
		distance_so_far.dist += distance_to_scene.dist;
		distance_so_far.id = distance_to_scene.id;
		if (distance_to_scene.dist < SURF_DIST || distance_so_far.dist > MAX_DIST) {
			break;
		}
	}

	return distance_so_far;
}

vec3 get_normal(vec3 point) {
	float dist = get_dist(point).dist;

	vec3 normal = dist - vec3(
		get_dist(point - vec3(0.01, 0.0, 0.0)).dist,
		get_dist(point - vec3(0.0, 0.01, 0.0)).dist,
		get_dist(point - vec3(0.0, 0.0, 0.01)).dist
	);

	return normalize(normal);
}

float shade(vec3 light_dir, vec3 point) {
	vec3 normal = get_normal(point);

	float shade = clamp(dot(normal, light_dir), 0.0, 1.0);
	return shade;
}

vec2 spherical_uv_projection(vec3 normal, float shift) {
    float u = 0.5 + atan(normal.z, normal.x) / (2.0 * PI) + shift;
    float v = 0.5 - asin(normal.y) / PI;
    return vec2(u, v);
}

float take_cloud_sample(vec3 coord) {
	float shape_sample = texture(cloud_shape, (coord * cloud_shape_size * 0.01) + cloud_shape_offset).r;
	float noise_sample = texture(cloud_noise, (coord * cloud_noise_size * 0.01) + cloud_noise_offset).r;

	float mixed_sample = shape_sample * (1.0 - cloud_noise_factor) + noise_sample * cloud_noise_factor;

	if (hole_in_center) {
		float hole_factor = smoothstep(hole_radius - hole_feather, hole_radius + hole_feather, length(coord.xz));
		mixed_sample *= hole_factor;
	}

	float invert_coverage = 1.0 - coverage;
	return smoothstep(invert_coverage - cloud_smoothness, invert_coverage + cloud_smoothness, mixed_sample);
}

float henyey_greenstein(float a, float g) {
    float g2 = g*g;
    return (1.0 - g2) / (4.0 * PI * pow(1.0 + g2 - 2.0*g*a, 1.5));
}

float light_march(vec3 ray_origin, vec3 ray_direction, vec3 sun_direction) {
	float optical_depth = 0.0;

	float step_size = light_max_dist / float(light_marches);

	for(float total_dist = 0.0; total_dist < light_max_dist; total_dist += step_size) {
		vec3 coords = ray_origin + sun_direction * total_dist;
		float density_sample = take_cloud_sample(coords);

		optical_depth += density_sample * step_size;
	}

	return exp(-optical_depth);
}

vec4 ray_march_clouds(vec3 start_point, vec3 direction, vec3 ambient_color, vec2 uv) {
	vec3 light_energy = vec3(ambient_color);
	float transmittance = 1.0;

	float march_dist = cloud_base_march_dist
		/ clamp(pow(dot(direction, vec3(0.0, 1.0, 0.0)), cloud_falloff_coeff), 0.05, 1.0);
	float step_size = (march_dist / float(cloud_marches)) - EPS;

	float cos_theta = dot(direction, LIGHT0_DIRECTION);
	float phase_cloud = henyey_greenstein(cos_theta, clouds_anisotropy_factor);

	if (apply_stochastic_jitter) {
		start_point += direction * (H(uv) - 0.5) * stochastic_jitter_amount;
	}

	vec3 cloud_color = vec3(0.0);

	for (float total_dist = 0.0; total_dist < march_dist; total_dist += step_size) {
		vec3 coords = start_point + direction * total_dist;

		float density_sample = take_cloud_sample(coords);

		cloud_color += mix(
			cloud_base_color,
			cloud_overcast_color,
			smoothstep( .4, .8, texture(cloud_color_texture, coords.xz * .01).r)
		);

		if (density_sample > 0.01) {
			transmittance *= exp(-density_sample * density_coeff * step_size);
			float luminance = light_march(coords, direction, LIGHT0_DIRECTION);

			light_energy +=
				density_sample *
				transmittance *
				density_coeff *
				step_size *
				luminance *
				phase_cloud *
				light_strength;
		}
	}

	cloud_color /= float(cloud_marches);
	vec3 cloud_col = cloud_color * light_energy * LIGHT0_COLOR * pow(LIGHT0_ENERGY, 2.0);

	transmittance = clamp(1.0 - transmittance, 0.0, 1.0);

	return vec4(cloud_col, transmittance);
}

vec3 jitter_ray_origin(vec3 origin, vec3 direction, vec2 noise_sample, float amount) {
    vec3 up = abs(direction.y) < 0.999 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent = normalize(cross(up, direction));
    vec3 bitangent = normalize(cross(direction, tangent));

    vec2 offset2D = (noise_sample - 0.5) * amount;
    return origin + tangent * offset2D.x + bitangent * offset2D.y;
}

vec3 rainbow(vec3 eyedir, vec3 transmittance, vec4 clouds) {
	vec3 res = vec3(0.0);
	// Main rainbow
	{
		float lower_bound = rainbow_offset - rainbow_width;
		float upper_bound = rainbow_offset + rainbow_width;
		float lower_mask = smoothstep(lower_bound, lower_bound + .02, eyedir.x);
		float upper_mask = smoothstep(upper_bound, upper_bound - .02, eyedir.x);
		res += texture(
				rainbow_gradient,
				vec2(smoothstep(lower_bound, upper_bound, eyedir.x), 0.0)
			).rgb
			* lower_mask
			* upper_mask
			* rainbow_opacity
			* transmittance
			* (behind_clouds ? (1.0 - clouds.a) : 1.0);
	}

	// Double rainbow
	if (double_rainbow) {
		float lower_bound = rainbow_offset * 0.9 - rainbow_width * 1.5;
		float upper_bound = rainbow_offset * 0.9 + rainbow_width * 1.5;
		float lower_mask = smoothstep(lower_bound, lower_bound + .02, eyedir.x);
		float upper_mask = smoothstep(upper_bound, upper_bound - .02, eyedir.x);
		res += texture(
				rainbow_gradient,
				vec2(smoothstep(lower_bound, upper_bound, eyedir.x), 0.0)
			).rgb
			* lower_mask
			* upper_mask
			* rainbow_opacity * .15
			* transmittance
			* (behind_clouds ? (1.0 - clouds.a) : 1.0);
	}

	return res;
}

void sky() {
	if (AT_CUBEMAP_PASS) {
		vec3 transmittance;
		COLOR = integrate_scattering(vec3(0.0, elevation, 0.0), EYEDIR, INFINITY, LIGHT0_DIRECTION, vec3(1.0, 0.996, 0.98), transmittance);
	} else if (AT_QUARTER_RES_PASS) {
		vec3 transmittance;
		integrate_scattering(vec3(0.0, elevation, 0.0), EYEDIR, INFINITY, LIGHT0_DIRECTION, vec3(1.0, 0.996, 0.98), transmittance);
		COLOR = transmittance;
	} else if (AT_HALF_RES_PASS) {
		COLOR = vec3(0.0);
		ALPHA = 0.0;

		if (EYEDIR.y > 0.0) {
			vec3 lower_plane_point = EYEDIR * (LOWER_PLANE_HEIGHT / EYEDIR.y);

			vec4 clouds = ray_march_clouds(
				lower_plane_point,
				EYEDIR,
				texture(RADIANCE, EYEDIR).rgb,
				SCREEN_UV
			);

			COLOR.rgb = clouds.rgb;
			ALPHA = clouds.a;

			ALPHA *= smoothstep(
				clouds_alpha_lower_bound,
				clouds_alpha_upper_bound,
				dot(EYEDIR, vec3(0.0, 1.0, 0.0))
			);
		}
	} else {
		vec3 transmittance = QUARTER_RES_COLOR.rgb;
		vec3 radiance = texture(RADIANCE, EYEDIR).rgb;

		float sun_mask = sun_disc(EYEDIR, LIGHT0_DIRECTION, LIGHT0_SIZE * 0.5);
		vec3 sundisc = vec3(sun_mask) * transmittance * sundisc_intensity;

		vec3 stars =
			texture(stars_hdr, EYEDIR * stars_rotation).rgb *
			stars_exposure *
			transmittance;

		if (dim_stars_at_day) {
			float stars_mult = smoothstep(
				-0.1,
				0.3,
				dot(LIGHT0_DIRECTION, vec3(0.0, -1.0, 0.0))
			);
			stars *= stars_mult;
		}

		// Moon pass
		float moon_mask = 1.0;
		vec3 moon_diff = vec3(0.0);

		Hit moon_hit = raymarch_moons(EYEDIR);

		if (
			moon_hit.dist < MAX_DIST &&
			get_dist(EYEDIR * moon_hit.dist).dist < SURF_DIST * 128.0
		) {
			moon_mask = 0.0;

			moon_diff = texture(
				moon_textures[moon_hit.id],
				spherical_uv_projection(get_normal(EYEDIR * moon_hit.dist), moon_uv_x_offset[moon_hit.id])
			).rgb;

			moon_diff *= shade(LIGHT0_DIRECTION, EYEDIR * moon_hit.dist);

			switch (moon_hit.id) {
				case 0:
					moon_diff *= LIGHT1_COLOR * LIGHT1_ENERGY;
					break;
				case 1:
					moon_diff *= LIGHT2_COLOR * LIGHT2_ENERGY;
					break;
				case 3:
					moon_diff *= LIGHT3_COLOR * LIGHT3_ENERGY;
					break;
			}

			moon_diff *= transmittance;
		}

		COLOR = radiance + (sundisc + stars) * moon_mask + moon_diff;

		// Cirrus Clouds
		if (EYEDIR.y > 0.0 && use_cirrus) {
			vec2 coords = EYEDIR.xz / EYEDIR.y;

			float cirrus_mask = smoothstep(
				cirrus_mask_treshold - cirrus_mask_feather,
				cirrus_mask_treshold + cirrus_mask_feather,
				texture(cirrus_mask_texture, coords * cirrus_mask_scale).r
			);
			vec2 cirrus_distortion = texture(cirrus_distortion_texture, coords * cirrus_distortion_scale + cirrus_distortion_offset).xy * cirrus_distortion_strength;

			float cirrus = smoothstep(
				cirrus_treshold - cirrus_feather,
				cirrus_treshold + cirrus_feather,
				texture(
					cirrus_texture,
					(coords * cirrus_scale + cirrus_offset) * cirrus_squish + cirrus_distortion
				).r
			) * cirrus_mask * cirrus_opacity * smoothstep(.5, 3.0, length(coords));

			COLOR += cirrus * transmittance * LIGHT0_COLOR * LIGHT0_ENERGY;
		}

		// Cumulus Clouds
		vec4 clouds = HALF_RES_COLOR;
		COLOR = mix(COLOR, clouds.rgb, clouds.a);

		// Rainbows
		if (use_rainbow) {
			COLOR += rainbow(EYEDIR, transmittance, clouds);
		}

		if (use_debanding) {
			COLOR += (rand(SKY_COORDS) - 0.5) * 0.001;
		}
	}
}
