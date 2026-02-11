shader_type spatial;
render_mode blend_add, cull_disabled;

uniform float glow_intensity : hint_range(0.0, 5.0) = 0.5;
uniform float scan_speed : hint_range(0.1, 5.0) = 1.5;
uniform float base_alpha : hint_range(0.0, 0.1) = 0.01;
uniform float scan_strength : hint_range(0.0, 1.0) = 0.1;

void fragment() {
    float fresnel = pow(1.0 - dot(NORMAL, VIEW), 3.0);

    // Scan line sweeping across the surface
    float ripple = pow(max(sin(VERTEX.y * 4.0 - TIME * scan_speed), 0.0), 6.0);

    float alpha = base_alpha + fresnel * base_alpha + ripple * scan_strength;

    ALBEDO = vec3(1.0);
    ALPHA = alpha * glow_intensity;
    EMISSION = vec3(1.0) * glow_intensity * (fresnel * 0.3 + ripple * 0.5);
}