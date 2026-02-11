shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

// chromatic aberration
group_uniforms chromatic_aberration;
uniform bool chromatic_enabled = true;
uniform float chromatic_amount : hint_range(0.0, 10.0) = 10.0;
uniform bool chromatic_radial = true;

// scanlines / CRT
group_uniforms crt;
uniform bool crt_enabled = true;
uniform float scanline_opacity : hint_range(0.0, 1.0) = 0.15;
uniform float scanline_density : hint_range(100.0, 1500.0) = 400.0;
uniform float crt_curve : hint_range(0.0, 10.0) = 2.0;
uniform float crt_vignette : hint_range(0.0, 1.0) = 0.3;
uniform float noise_intensity : hint_range(0.0, 0.3) = 0.04;
uniform float flicker_intensity : hint_range(0.0, 0.1) = 0.02;

// film grain + color grading
group_uniforms film;
uniform bool film_enabled = true;
uniform float grain_amount : hint_range(0.0, 0.3) = 0.06;
uniform float saturation : hint_range(0.0, 2.0) = 1.1;
uniform float contrast : hint_range(0.5, 2.0) = 1.05;
uniform float brightness : hint_range(-0.2, 0.2) = 0.0;
uniform vec3 color_tint : source_color = vec3(1.0, 0.98, 0.95);

// radial blur
group_uniforms radial_blur;
uniform bool radial_blur_enabled = false;
uniform float blur_strength : hint_range(0.0, 0.05) = 0.01;
uniform int blur_samples : hint_range(2, 16) = 6;
uniform vec2 blur_center = vec2(0.5, 0.5);

// noise helpers
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

vec2 crt_distort(vec2 uv, float amount) {
	uv = uv * 2.0 - 1.0;
	uv *= 1.0 + amount * 0.01 * dot(uv, uv);
	return uv * 0.5 + 0.5;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 ps = SCREEN_PIXEL_SIZE;

	// CRT barrel distortion
	if (crt_enabled && crt_curve > 0.0) {
		uv = crt_distort(uv, crt_curve);
	}

	// radial blur
	vec3 color;
	if (radial_blur_enabled && blur_strength > 0.0) {
		vec3 accum = vec3(0.0);
		vec2 dir = uv - blur_center;
		for (int i = 0; i < blur_samples; i++) {
			float t = float(i) / float(blur_samples);
			vec2 sample_uv = uv - dir * t * blur_strength;
			accum += texture(screen_texture, sample_uv).rgb;
		}
		color = accum / float(blur_samples);
	} else {
		color = texture(screen_texture, uv).rgb;
	}

	// chromatic aberration
	if (chromatic_enabled && chromatic_amount > 0.0) {
		vec2 offset;
		if (chromatic_radial) {
			offset = (uv - vec2(0.5)) * chromatic_amount;
		} else {
			offset = vec2(chromatic_amount, 0.0);
		}
		float r = texture(screen_texture, uv + offset * ps).r;
		float b = texture(screen_texture, uv - offset * ps).b;
		color = vec3(r, color.g, b);
	}

	// CRT effects
	if (crt_enabled) {
		// scanlines
		float scanline = sin(uv.y * scanline_density * 3.14159) * 0.5 + 0.5;
		color *= 1.0 - scanline_opacity * (1.0 - scanline);

		// static noise
		float n = hash(uv * vec2(1000.0) + TIME * 100.0);
		color += (n - 0.5) * noise_intensity;

		// flicker
		float flick = 1.0 + (hash(vec2(TIME * 15.0, 0.0)) - 0.5) * flicker_intensity;
		color *= flick;

		// CRT edge vignette
		vec2 edge = smoothstep(vec2(0.0), vec2(0.05), uv) * (1.0 - smoothstep(vec2(0.95), vec2(1.0), uv));
		color *= mix(1.0, edge.x * edge.y, crt_vignette);

		// black outside curved area
		if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
			color = vec3(0.0);
		}
	}

	// film grain + color grading
	if (film_enabled) {
		// grain
		float grain = (hash(uv * 800.0 + fract(TIME) * 100.0) - 0.5) * grain_amount;
		color += grain;

		// saturation
		float lum = dot(color, vec3(0.2126, 0.7152, 0.0722));
		color = mix(vec3(lum), color, saturation);

		// contrast + brightness
		color = (color - 0.5) * contrast + 0.5 + brightness;

		// tint
		color *= color_tint;
	}

	COLOR = vec4(clamp(color, vec3(0.0), vec3(1.0)), 1.0);
}