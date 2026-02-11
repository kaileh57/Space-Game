shader_type sky;

group_uniforms sky_colors;
uniform vec3 sky_color : source_color = vec3(0.005, 0.005, 0.015);

group_uniforms stars;
uniform float star_density : hint_range(20.0, 200.0) = 80.0;
uniform float star_brightness : hint_range(0.0, 5.0) = 2.5;
uniform float star_size : hint_range(0.02, 0.2) = 0.08;
uniform float twinkle_speed : hint_range(0.0, 5.0) = 1.0;
uniform float twinkle_amount : hint_range(0.0, 1.0) = 0.25;

group_uniforms nebula;
uniform bool nebula_enabled = true;
uniform vec3 nebula_color_a : source_color = vec3(0.12, 0.01, 0.18);
uniform vec3 nebula_color_b : source_color = vec3(0.01, 0.04, 0.15);
uniform float nebula_intensity : hint_range(0.0, 1.0) = 0.12;
uniform float nebula_scale : hint_range(0.5, 5.0) = 1.5;

group_uniforms black_hole;
uniform bool black_hole_enabled = true;
uniform vec3 black_hole_dir = vec3(0.0, 0.3, -1.0);
uniform float black_hole_radius : hint_range(0.02, 0.4) = 0.1;
uniform float warp_strength : hint_range(0.0, 8.0) = 3.0;
uniform float warp_falloff : hint_range(0.1, 3.0) = 0.6;
uniform float disc_inner_mult : hint_range(1.5, 4.0) = 2.0;
uniform float disc_outer_mult : hint_range(3.0, 10.0) = 6.0;
uniform vec3 disc_color_hot : source_color = vec3(1.0, 0.95, 0.8);
uniform vec3 disc_color_mid : source_color = vec3(1.0, 0.6, 0.15);
uniform vec3 disc_color_cool : source_color = vec3(0.7, 0.15, 0.02);
uniform float disc_brightness : hint_range(0.0, 15.0) = 6.0;
uniform float disc_spin_speed : hint_range(0.0, 3.0) = 0.3;
uniform float disc_thickness : hint_range(0.005, 0.1) = 0.02;

group_uniforms ring;
uniform float einstein_ring_brightness : hint_range(0.0, 5.0) = 1.5;
uniform float einstein_ring_width : hint_range(0.001, 0.02) = 0.005;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float a = hash3(i);
	float b = hash3(i + vec3(1.0, 0.0, 0.0));
	float c = hash3(i + vec3(0.0, 1.0, 0.0));
	float d = hash3(i + vec3(1.0, 1.0, 0.0));
	float e = hash3(i + vec3(0.0, 0.0, 1.0));
	float f1 = hash3(i + vec3(1.0, 0.0, 1.0));
	float g = hash3(i + vec3(0.0, 1.0, 1.0));
	float h = hash3(i + vec3(1.0, 1.0, 1.0));

	float k0 = mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
	float k1 = mix(mix(e, f1, f.x), mix(g, h, f.x), f.y);
	return mix(k0, k1, f.z);
}

float fbm(vec3 p) {
	float value = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		value += amp * noise3d(p);
		p *= 2.1;
		amp *= 0.5;
	}
	return value;
}

float stars(vec3 dir) {
	float theta = atan(dir.z, dir.x);
	float phi = asin(clamp(dir.y, -1.0, 1.0));

	vec2 grid = vec2(theta, phi) * star_density;
	vec2 cell = floor(grid);
	vec2 local = fract(grid);

	float b = 0.0;

	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			vec2 offset = vec2(float(x), float(y));
			vec2 cid = cell + offset;

			if (hash(cid + 700.0) > 0.1) continue;

			vec2 star_pos = offset + vec2(hash(cid), hash(cid + 100.0));
			float dist = length(local - star_pos);

			float sz = star_size * (0.5 + hash(cid + 200.0));
			float star = smoothstep(sz, 0.0, dist);

			float phase = hash(cid + 300.0) * 6.28;
			float rate = 0.5 + hash(cid + 400.0) * 2.0;
			float twinkle = 1.0 - twinkle_amount * 0.5
				* (1.0 + sin(TIME * twinkle_speed * rate + phase));

			float brightness_var = 0.4 + hash(cid + 600.0) * 0.6;
			b += star * star_brightness * twinkle * brightness_var;
		}
	}

	return b;
}

vec3 star_color_temp(vec3 dir) {
	// give some stars color
	float theta = atan(dir.z, dir.x);
	float phi = asin(clamp(dir.y, -1.0, 1.0));
	vec2 grid = vec2(theta, phi) * star_density;
	vec2 cell = floor(grid);
	float temp = hash(cell + 800.0);

	if (temp < 0.3) {
		return vec3(0.7, 0.8, 1.0); // blue-white
	} else if (temp < 0.7) {
		return vec3(1.0, 1.0, 0.95); // white
	} else if (temp < 0.9) {
		return vec3(1.0, 0.9, 0.7); // warm
	} else {
		return vec3(1.0, 0.6, 0.4); // orange-red
	}
}

vec3 get_sky(vec3 dir) {
	vec3 sky = sky_color;

	if (nebula_enabled) {
		float n1 = fbm(dir * nebula_scale + vec3(42.0));
		float n2 = fbm(dir * nebula_scale * 1.5 + vec3(87.0));
		vec3 neb = mix(nebula_color_a, nebula_color_b, n2);
		float mask = smoothstep(0.3, 0.7, n1) * nebula_intensity;
		sky += neb * mask;
	}

	float s = stars(dir);
	vec3 scol = star_color_temp(dir);
	sky += s * scol;

	return sky;
}

// accretion disc sampled in polar coordinates around the black hole
float disc_density(float r, float angle, float inner_r, float outer_r) {
	if (r < inner_r || r > outer_r) {
		return 0.0;
	}

	float radial = smoothstep(inner_r, inner_r + 0.01, r)
		* smoothstep(outer_r, outer_r - 0.02, r);

	// spiral arms
	float spiral = sin(angle * 2.0 - log(max(r, 0.001)) * 8.0 + TIME * disc_spin_speed * 4.0);
	spiral = spiral * 0.3 + 0.7;

	// noise turbulence
	float turb = fbm(vec3(r * 30.0, angle * 2.0 + TIME * disc_spin_speed, TIME * 0.1));
	turb = turb * 0.4 + 0.6;

	// brighter toward inner edge (hotter)
	float heat = 1.0 - smoothstep(inner_r, outer_r, r);
	heat = heat * heat;

	return radial * spiral * turb * (0.5 + heat * 0.5);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 bh = normalize(black_hole_dir);
	float angle_to_bh = acos(clamp(dot(dir, bh), -1.0, 1.0));

	vec3 sky = vec3(0.0);

	if (!black_hole_enabled) {
		sky = get_sky(dir);
	} else {
		// build a local coordinate frame for the black hole
		// disc lies in the plane defined by bh_right and bh_forward
		vec3 world_up = vec3(0.0, 1.0, 0.0);
		// if bh is nearly parallel to up, pick a different reference
		vec3 ref = abs(dot(bh, world_up)) > 0.99 ? vec3(1.0, 0.0, 0.0) : world_up;
		vec3 bh_right = normalize(cross(bh, ref));
		vec3 bh_up = normalize(cross(bh_right, bh));

		// gravitational lensing
		float warp = warp_strength * black_hole_radius / max(angle_to_bh, 0.001);
		warp *= exp(-angle_to_bh / warp_falloff);

		vec3 perp = dir - bh * dot(dir, bh);
		float perp_len = length(perp);
		if (perp_len > 0.001) {
			perp /= perp_len;
		}
		vec3 warped_dir = normalize(dir + perp * warp);

		sky = get_sky(warped_dir);

		// event horizon
		float horizon_edge = smoothstep(black_hole_radius, black_hole_radius * 0.6, angle_to_bh);
		sky *= 1.0 - horizon_edge;

		// shadow darkening near the hole
		float shadow = smoothstep(black_hole_radius * 0.6, black_hole_radius * 3.0, angle_to_bh);
		sky *= 0.3 + 0.7 * shadow;

		// accretion disc
		// project direction into the black hole's local frame
		vec3 offset = dir - bh * dot(dir, bh);
		float disc_x = dot(dir, bh_right);
		float disc_y_height = dot(dir, bh_up); // height above disc plane
		float disc_r = length(offset); // radial distance from bh axis

		float inner_r = black_hole_radius * disc_inner_mult;
		float outer_r = black_hole_radius * disc_outer_mult;

		// thin disc mask
		float plane_mask = exp(-disc_y_height * disc_y_height / (disc_thickness * disc_thickness));

		float disc_angle = atan(disc_x, dot(dir, cross(bh_up, bh_right)));
		float density = disc_density(disc_r, disc_angle, inner_r, outer_r) * plane_mask;

		// color: hot white-yellow inside, orange-red outside
		float radial_t = clamp((disc_r - inner_r) / max(outer_r - inner_r, 0.001), 0.0, 1.0);
		vec3 disc_col = vec3(0.0);
		if (radial_t < 0.3) {
			disc_col = mix(disc_color_hot, disc_color_mid, radial_t / 0.3);
		} else {
			disc_col = mix(disc_color_mid, disc_color_cool, (radial_t - 0.3) / 0.7);
		}

		// doppler shift: one side bluer/brighter, other side redder/dimmer
		float doppler = 1.0 + 0.5 * sin(disc_angle + TIME * disc_spin_speed * 3.0);
		disc_col *= doppler;

		sky += disc_col * density * disc_brightness;

		// einstein ring: bright ring right at the photon sphere
		float ring_r = black_hole_radius * 1.3;
		float ring_dist = abs(angle_to_bh - ring_r);
		float ring = exp(-ring_dist * ring_dist / (einstein_ring_width * einstein_ring_width));
		sky += mix(disc_color_hot, disc_color_mid, 0.3) * ring * einstein_ring_brightness;

		// soft glow halo
		float glow = exp(-angle_to_bh * angle_to_bh / (black_hole_radius * black_hole_radius * 12.0));
		sky += disc_color_cool * glow * 0.1;
	}

	COLOR = sky;
}