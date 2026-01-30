shader_type spatial;
render_mode blend_add, cull_disabled;

uniform vec4 field_color : source_color = vec4(0.0, 0.5, 1.0, 1.0);
uniform float glow_intensity : hint_range(0.0, 5.0) = 2.0;

void fragment() {
    // Fresnel effect: calculates how much we are looking at the edge of the object
    float fresnel = pow(1.0 - dot(NORMAL, VIEW), 2.0);
    
    ALBEDO = field_color.rgb;
    ALPHA = fresnel * glow_intensity * field_color.a;
    EMISSION = ALBEDO * glow_intensity;
}