shader_type canvas_item;
render_mode blend_mix;

uniform float fill_amount : hint_range(0.0, 1.0) = 1.0;
uniform vec4 liquid_color_primary : source_color = vec4(0.88, 0.04, 0.08, 1.0);     // Vibrant Blood Red / Arcane Cyan
uniform vec4 liquid_color_deep : source_color = vec4(0.22, 0.01, 0.02, 1.0);        // Deep shadow fluid
uniform vec4 liquid_color_surface : source_color = vec4(1.0, 0.35, 0.35, 1.0);     // Meniscus highlight
uniform vec4 glow_color : source_color = vec4(1.8, 0.15, 0.15, 1.0);               // HDR Forward+ Glow
uniform float slosh_speed : hint_range(0.5, 6.0) = 2.8;
uniform float slosh_amplitude : hint_range(0.0, 0.1) = 0.035;
uniform float bubble_intensity : hint_range(0.0, 3.0) = 1.5;
uniform float glass_rim_opacity : hint_range(0.0, 1.0) = 0.65;
uniform float specular_intensity : hint_range(0.0, 2.0) = 1.1;

// Pseudo-random hash
float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// 2D noise for organic fluid turbulence
float fluid_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Procedural rising bubble generator
float calculate_bubbles(vec2 uv, float t, float surface_y) {
    float bubbles = 0.0;
    // Layer 1: medium bubbles
    vec2 b_uv1 = uv * vec2(16.0, 10.0);
    b_uv1.y -= t * 1.8;
    vec2 cell1 = floor(b_uv1);
    vec2 frac1 = fract(b_uv1) - 0.5;
    float h1 = hash21(cell1);
    if (h1 > 0.68) {
        vec2 b_center = vec2((h1 - 0.84) * 0.6 + sin(t * 2.5 + h1 * 6.28) * 0.18, 0.0);
        float d1 = length(frac1 - b_center);
        float radius = mix(0.06, 0.14, fract(h1 * 91.3));
        float bubble = smoothstep(radius, radius - 0.03, d1);
        float highlight = smoothstep(0.04, 0.0, length(frac1 - b_center - vec2(-0.03, -0.03)));
        bubbles += (bubble * 0.7 + highlight * 1.2);
    }
    
    // Layer 2: microscopic fast fizzy bubbles
    vec2 b_uv2 = uv * vec2(28.0, 18.0);
    b_uv2.y -= t * 2.6;
    vec2 cell2 = floor(b_uv2);
    vec2 frac2 = fract(b_uv2) - 0.5;
    float h2 = hash21(cell2 + vec2(7.3, 11.2));
    if (h2 > 0.76) {
        vec2 b_center2 = vec2((h2 - 0.88) * 0.5 + cos(t * 3.2 + h2 * 6.28) * 0.15, 0.0);
        float d2 = length(frac2 - b_center2);
        float radius2 = 0.06;
        bubbles += smoothstep(radius2, radius2 - 0.02, d2) * 0.9;
    }

    return bubbles;
}

void fragment() {
    // Center coords in [-1.0, 1.0]
    vec2 p = UV * 2.0 - 1.0;
    float dist = length(p);

    // Hard/Antialiased circular clip for the sphere
    float sphere_edge = 1.0 - smoothstep(0.97, 1.0, dist);
    if (sphere_edge <= 0.001) {
        discard;
    }

    // Sphere 3D pseudo normal for realistic volumetric refraction
    float z = sqrt(max(0.0, 1.0 - dist * dist));
    vec3 normal = vec3(p.x, -p.y, z);

    // Fluid height in coordinate space: fill_amount: 0.0 -> y = 1.0, 1.0 -> y = -1.0
    // (Note: UV y=0 is top, UV y=1 is bottom, so in p space y=-1 is top, y=+1 is bottom)
    float fill_target_y = 1.0 - fill_amount * 2.0;

    // Organic harmonic waves across the liquid surface
    float t = TIME * slosh_speed;
    float wave_amp = slosh_amplitude * (1.0 - abs(p.y) * 0.4);
    float wave_1 = sin(p.x * 5.0 + t) * wave_amp;
    float wave_2 = cos(p.x * 9.5 - t * 1.4) * (wave_amp * 0.45);
    float wave_3 = sin(p.x * 16.0 + t * 2.1) * (wave_amp * 0.2);
    float noise_slosh = (fluid_noise(vec2(p.x * 3.0, t * 0.8)) - 0.5) * wave_amp * 0.6;
    
    // Front wave line
    float fluid_surface_front = fill_target_y + wave_1 + wave_2 + wave_3 + noise_slosh;
    
    // Back wave line (shifted phase and slightly higher for 3D depth illusion)
    float wave_back = sin(p.x * 4.2 - t * 0.9 + 1.5) * (wave_amp * 0.7);
    float fluid_surface_back = fill_target_y + wave_back + 0.035;

    // Fluid presence masks
    // Soft antialiasing on surface boundary
    float front_surface_aa = clamp((p.y - fluid_surface_front) * 40.0 + 0.5, 0.0, 1.0);
    float back_surface_aa = clamp((p.y - fluid_surface_back) * 30.0 + 0.5, 0.0, 1.0);

    // Liquid depth gradient: deeper at bottom of globe, lighter near surface
    float depth_factor = clamp((p.y - fill_target_y) / 1.5, 0.0, 1.0);
    vec3 liquid_body = mix(liquid_color_primary.rgb, liquid_color_deep.rgb, depth_factor * 0.8);

    // Caustics inside fluid
    float caustic = fluid_noise(p * 6.0 + vec2(0.0, TIME * 0.5)) * 0.18;
    liquid_body += caustic * liquid_color_primary.rgb;

    // Bubbles
    if (p.y > fluid_surface_front - 0.05 && dist < 0.92) {
        float b = calculate_bubbles(p, TIME, fluid_surface_front);
        liquid_body += b * bubble_intensity * glow_color.rgb * 0.6;
    }

    // Meniscus surface foam & highlight (the luminous liquid line at the top)
    float meniscus_dist = abs(p.y - fluid_surface_front);
    float meniscus_glow = exp(-meniscus_dist * 40.0) * 1.8;
    vec3 meniscus_color = mix(liquid_color_surface.rgb, glow_color.rgb, 0.5);

    // Back fluid layer showing through transparent glass for 3D fullness
    vec3 back_liquid = liquid_color_deep.rgb * 0.6;

    // Combine fluid layers
    vec3 final_fluid = vec3(0.0);
    float fluid_alpha = 0.0;

    if (p.y >= fluid_surface_back && p.y < fluid_surface_front) {
        // Between back and front surface: 3D fluid top plane view
        final_fluid = mix(back_liquid, meniscus_color, 0.4);
        fluid_alpha = back_surface_aa * 0.75;
    } else if (p.y >= fluid_surface_front) {
        // Inside main front liquid body
        final_fluid = liquid_body + meniscus_color * meniscus_glow;
        fluid_alpha = front_surface_aa;
    }

    // Glass globe background (empty part of globe)
    // Translucent dark crystal glass with volumetric depth and faint ethereal essence glow
    vec3 ambient_essence = mix(liquid_color_deep.rgb * 0.45, liquid_color_primary.rgb * 0.15, 0.35);
    vec3 empty_glass_color = mix(vec3(0.02, 0.025, 0.035), ambient_essence, 0.65);
    float empty_glass_alpha = 0.65;

    // Inner shadow vignette (darkens towards the sphere edges)
    float inner_shadow = smoothstep(0.5, 0.98, dist);
    empty_glass_color = mix(empty_glass_color, vec3(0.01, 0.01, 0.015), inner_shadow * 0.5);

    // Blend fluid over empty glass
    vec3 result_color = mix(empty_glass_color, final_fluid, fluid_alpha);
    float result_alpha = mix(empty_glass_alpha, 0.98, fluid_alpha);

    // Glass specular highlights:
    // Authentic curved spherical glint on top-left (arc reflection)
    float arc_dist = abs(dist - 0.70);
    float arc_angle = atan(-p.y, -p.x); // top-left quadrant is near PI/4
    float angle_diff = abs(arc_angle - 0.785);
    float arc_spec = exp(-arc_dist * 16.0) * exp(-angle_diff * angle_diff * 4.5) * 0.85;

    // Subtle soft secondary highlight
    float pin_spec = exp(-length(p - vec2(-0.40, -0.40)) * 10.0) * 0.45;
    float spec_bottom = smoothstep(0.35, 0.0, length(p - vec2(0.40, 0.40))) * 0.15;

    float total_spec = (arc_spec + pin_spec + spec_bottom) * specular_intensity;
    result_color += vec3(total_spec);

    // Fresnel rim sheen (glass boundary)
    float fresnel = pow(1.0 - z, 3.0) * glass_rim_opacity;
    vec3 rim_glow = mix(vec3(0.5, 0.55, 0.65), glow_color.rgb * 0.5, fluid_alpha);
    result_color += rim_glow * fresnel;

    // Forward+ HDR Bloom boost on liquid and meniscus
    if (fluid_alpha > 0.1) {
        result_color += glow_color.rgb * (fluid_alpha * 0.22 + meniscus_glow * 0.35);
    }

    COLOR = vec4(result_color, result_alpha * sphere_edge);
}
