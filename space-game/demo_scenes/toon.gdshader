shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D normal_texture : hint_normal_roughness_texture, filter_nearest;

// sky masking
group_uniforms sky_mask;
uniform float sky_depth_threshold : hint_range(0.99, 1.0) = 0.99;

// outlines
group_uniforms outlines;
uniform bool outline_enabled = true;
uniform float depth_threshold : hint_range(0.0, 10.0) = 1.5;
uniform float normal_threshold : hint_range(0.0, 2.0) = 0.5;
uniform vec3 outline_color : source_color = vec3(0.0);
uniform float outline_opacity : hint_range(0.0, 1.0) = 0.8;

// shading
group_uniforms shading;
uniform bool shade_enabled = true;
uniform int shade_steps : hint_range(2, 6) = 3;
uniform float shade_strength : hint_range(0.0, 1.0) = 0.4;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float edge_detect(vec2 uv, vec2 ps) {
	float d  = texture(depth_texture, uv).r;
	float dl = texture(depth_texture, uv + vec2(-ps.x, 0.0)).r;
	float dr = texture(depth_texture, uv + vec2(ps.x, 0.0)).r;
	float du = texture(depth_texture, uv + vec2(0.0, -ps.y)).r;
	float dd = texture(depth_texture, uv + vec2(0.0, ps.y)).r;
	float depth_edge = abs(dl - d) + abs(dr - d) + abs(du - d) + abs(dd - d);
	depth_edge = smoothstep(0.0, 0.001 * depth_threshold, depth_edge);

	vec3 n  = texture(normal_texture, uv).rgb;
	vec3 nl = texture(normal_texture, uv + vec2(-ps.x, 0.0)).rgb;
	vec3 nr = texture(normal_texture, uv + vec2(ps.x, 0.0)).rgb;
	vec3 nu = texture(normal_texture, uv + vec2(0.0, -ps.y)).rgb;
	vec3 nd = texture(normal_texture, uv + vec2(0.0, ps.y)).rgb;
	float normal_edge = length(nl - n) + length(nr - n) + length(nu - n) + length(nd - n);
	normal_edge = smoothstep(0.0, normal_threshold, normal_edge);

	return clamp(max(depth_edge, normal_edge), 0.0, 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 ps = vec2(1.0) / vec2(textureSize(screen_texture, 0));
	vec3 color = texture(screen_texture, uv).rgb;

	float depth = texture(depth_texture, uv).r;
	bool is_sky = depth >= sky_depth_threshold;

	if (!is_sky && shade_enabled) {
		float lum = dot(color, vec3(0.2126, 0.7152, 0.0722));
		float steps = float(shade_steps);
		float stepped = floor(lum * steps + 0.5) / steps;
		float adjusted = mix(lum, stepped, shade_strength);
		color *= (lum > 0.001) ? adjusted / lum : 1.0;
	}

	if (!is_sky && outline_enabled) {
		float edge = edge_detect(uv, ps);
		color = mix(color, outline_color, edge * outline_opacity);
	}

	ALBEDO = color;
}