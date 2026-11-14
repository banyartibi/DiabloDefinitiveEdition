shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, unshaded;

// Diablo: Definitive Edition - 3D Entity & Billboard High-Definition Subpixel Upscaler
// Mode 0: xBRZ (4x/5x Rule-Based Vector Contour Reconstruction)
// Mode 1: SDF Silhouette Smoothing (Signed Distance Field Subpixel Alpha)
// Mode 2: Kuwahara / Fast Bilateral Filter (Edge-Preserving Dither Remover)
// Mode 3: AMD FSR 1.0 (Entity RCAS Local Contrast-Adaptive Sharpening)
// Mode 4: Native 1:1 Direct Retro Pixel-Art (Authentic 1996)

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, hint_default_black;
uniform bool hd_enabled = true;
uniform int upscaler_mode : hint_range(0, 4) = 0; // Default 0: xBRZ
uniform float sharpness : hint_range(0.0, 1.0) = 0.40;
uniform float brightness : hint_range(0.5, 3.0) = 1.0;

float color_dist_sq(vec4 c1, vec4 c2) {
    if (c1.a < 0.1 && c2.a < 0.1) return 0.0;
    if (c1.a < 0.1 || c2.a < 0.1) return 1.0;
    vec3 diff = c1.rgb - c2.rgb;
    float dy = dot(diff, vec3(0.299, 0.587, 0.114));
    return dot(diff, diff) + dy * dy * 2.0;
}

void fragment() {
    vec2 tex_size = vec2(textureSize(albedo_texture, 0));
    vec2 texel = vec2(1.0) / tex_size;
    vec4 c = texture(albedo_texture, UV);

    // If HD is disabled or Retro mode 4: render 1:1 crisp retro pixels
    if (!hd_enabled || tex_size.x <= 1.0 || tex_size.y <= 1.0 || upscaler_mode == 4) {
        if (c.a < 0.01) {
            discard;
        }
        ALBEDO = c.rgb * COLOR.rgb * brightness;
        ALPHA = c.a * COLOR.a;
        if (ALPHA < 0.01) {
            discard;
        }
    } else if (c.a < 0.005) {
        discard;
    } else {
        // 8-Neighborhood sampling
        vec4 up = texture(albedo_texture, UV + vec2( 0.0, -1.0) * texel);
        vec4 dn = texture(albedo_texture, UV + vec2( 0.0,  1.0) * texel);
        vec4 lf = texture(albedo_texture, UV + vec2(-1.0,  0.0) * texel);
        vec4 rt = texture(albedo_texture, UV + vec2( 1.0,  0.0) * texel);
        vec4 ul = texture(albedo_texture, UV + vec2(-1.0, -1.0) * texel);
        vec4 ur = texture(albedo_texture, UV + vec2( 1.0, -1.0) * texel);
        vec4 bl = texture(albedo_texture, UV + vec2(-1.0,  1.0) * texel);
        vec4 br = texture(albedo_texture, UV + vec2( 1.0,  1.0) * texel);

        vec2 f = fract(UV / texel);
        vec4 sampled = c;
        float edge_alpha = 1.0;

        if (upscaler_mode == 0) {
            // Mode 0: xBRZ (4x/5x Rule-Based Vector Smoothing)
            vec4 blend_col = c;

            // Top-Left Corner
            if (f.x < 0.5 && f.y < 0.5) {
                float d_edge = color_dist_sq(up, lf);
                float d_diag = color_dist_sq(c, ul);
                if (d_edge + 0.002 < d_diag && c.a > 0.5) {
                    float dist_corner = (0.5 - f.x) + (0.5 - f.y);
                    if (dist_corner > 0.35) {
                        blend_col = mix(c, (up + lf) * 0.5, smoothstep(0.35, 0.70, dist_corner));
                    }
                }
            }
            // Top-Right Corner
            else if (f.x >= 0.5 && f.y < 0.5) {
                float d_edge = color_dist_sq(up, rt);
                float d_diag = color_dist_sq(c, ur);
                if (d_edge + 0.002 < d_diag && c.a > 0.5) {
                    float dist_corner = (f.x - 0.5) + (0.5 - f.y);
                    if (dist_corner > 0.35) {
                        blend_col = mix(c, (up + rt) * 0.5, smoothstep(0.35, 0.70, dist_corner));
                    }
                }
            }
            // Bottom-Left Corner
            else if (f.x < 0.5 && f.y >= 0.5) {
                float d_edge = color_dist_sq(dn, lf);
                float d_diag = color_dist_sq(c, bl);
                if (d_edge + 0.002 < d_diag && c.a > 0.5) {
                    float dist_corner = (0.5 - f.x) + (f.y - 0.5);
                    if (dist_corner > 0.35) {
                        blend_col = mix(c, (dn + lf) * 0.5, smoothstep(0.35, 0.70, dist_corner));
                    }
                }
            }
            // Bottom-Right Corner
            else {
                float d_edge = color_dist_sq(dn, rt);
                float d_diag = color_dist_sq(c, br);
                if (d_edge + 0.002 < d_diag && c.a > 0.5) {
                    float dist_corner = (f.x - 0.5) + (f.y - 0.5);
                    if (dist_corner > 0.35) {
                        blend_col = mix(c, (dn + rt) * 0.5, smoothstep(0.35, 0.70, dist_corner));
                    }
                }
            }

            // Subpixel silhouette antialiasing
            float min_dist = 1.0;
            if (up.a < 0.5) min_dist = min(min_dist, f.y);
            if (dn.a < 0.5) min_dist = min(min_dist, 1.0 - f.y);
            if (lf.a < 0.5) min_dist = min(min_dist, f.x);
            if (rt.a < 0.5) min_dist = min(min_dist, 1.0 - f.x);
            edge_alpha = smoothstep(0.05, 0.38, min_dist);

            sampled = blend_col;

        } else if (upscaler_mode == 1) {
            // Mode 1: SDF (Signed Distance Field) Silhouette Smoothing
            vec2 alpha_grad = vec2(
                (ur.a + 2.0 * rt.a + br.a) - (ul.a + 2.0 * lf.a + bl.a),
                (bl.a + 2.0 * dn.a + br.a) - (ul.a + 2.0 * up.a + ur.a)
            ) * 0.125;

            float grad_len = length(alpha_grad);
            if (grad_len > 0.02) {
                vec2 norm = alpha_grad / grad_len;
                vec2 offset = f - vec2(0.5);
                float sdf = (c.a - 0.5) + dot(offset, norm) * grad_len * 2.2;
                edge_alpha = smoothstep(-0.15, 0.35, sdf);

                vec4 interior = (c.a > 0.8) ? c : (up.a > 0.8 ? up : (dn.a > 0.8 ? dn : (lf.a > 0.8 ? lf : rt)));
                sampled = mix(interior, c, clamp(c.a * 1.5, 0.0, 1.0));
            } else {
                edge_alpha = smoothstep(0.05, 0.35, c.a);
                sampled = c;
            }

        } else if (upscaler_mode == 2) {
            // Mode 2: Kuwahara / Fast Bilateral Filter
            float total_weight = 1.0;
            vec3 sum_rgb = c.rgb;

            const float sigma_spatial = 0.85;
            const float sigma_color = 0.14;

            vec4 nbs[8] = vec4[8](up, dn, lf, rt, ul, ur, bl, br);
            vec2 offsets[8] = vec2[8](
                vec2( 0.0, -1.0), vec2( 0.0,  1.0), vec2(-1.0,  0.0), vec2( 1.0,  0.0),
                vec2(-1.0, -1.0), vec2( 1.0, -1.0), vec2(-1.0,  1.0), vec2( 1.0,  1.0)
            );

            for (int i = 0; i < 8; i++) {
                if (nbs[i].a > 0.1) {
                    float spatial_d = length(offsets[i]);
                    float color_d = distance(nbs[i].rgb, c.rgb);
                    float w = exp(-(spatial_d * spatial_d) / (2.0 * sigma_spatial * sigma_spatial)) *
                              exp(-(color_d * color_d) / (2.0 * sigma_color * sigma_color));
                    sum_rgb += nbs[i].rgb * w;
                    total_weight += w;
                }
            }

            vec3 smoothed = sum_rgb / total_weight;
            vec3 sharp = c.rgb + (c.rgb - smoothed) * (sharpness * 0.4);
            sampled = vec4(clamp(mix(smoothed, sharp, 0.25), 0.0, 1.0), c.a);

            float min_dist = 1.0;
            if (up.a < 0.5) min_dist = min(min_dist, f.y);
            if (dn.a < 0.5) min_dist = min(min_dist, 1.0 - f.y);
            if (lf.a < 0.5) min_dist = min(min_dist, f.x);
            if (rt.a < 0.5) min_dist = min(min_dist, 1.0 - f.x);
            edge_alpha = smoothstep(0.04, 0.35, min_dist);

        } else if (upscaler_mode == 3) {
            // Mode 3: AMD FSR 1.0 CAS
            vec3 min_c = min(c.rgb, min(min(up.rgb, dn.rgb), min(lf.rgb, rt.rgb)));
            vec3 max_c = max(c.rgb, max(max(up.rgb, dn.rgb), max(lf.rgb, rt.rgb)));

            vec3 amp = clamp(min(min_c, 2.0 - max_c) / max(max_c, vec3(0.001)), 0.0, 1.0);
            vec3 w = -sqrt(amp) * (sharpness * 0.20);
            vec3 sharp_rgb = (up.rgb * w + dn.rgb * w + c.rgb + lf.rgb * w + rt.rgb * w) / (1.0 + 4.0 * w);
            sampled = vec4(clamp(sharp_rgb, min_c, max_c), c.a);

            float min_dist = 1.0;
            if (up.a < 0.5) min_dist = min(min_dist, f.y);
            if (dn.a < 0.5) min_dist = min(min_dist, 1.0 - f.y);
            if (lf.a < 0.5) min_dist = min(min_dist, f.x);
            if (rt.a < 0.5) min_dist = min(min_dist, 1.0 - f.x);
            edge_alpha = smoothstep(0.04, 0.35, min_dist);
        }

        ALBEDO = sampled.rgb * COLOR.rgb * brightness;
        ALPHA = sampled.a * edge_alpha * COLOR.a;
        if (ALPHA < 0.01) {
            discard;
        }
    }
}
