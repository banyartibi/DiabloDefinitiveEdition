shader_type canvas_item;

// Godot-native global brightness & color profile grading applied to the composited GameView render target.
// Driven across all display modes (Mode 0: Classic 2.5D, Mode 1: Native 2.5D, Mode 2: Real 3D).
uniform float brightness : hint_range(0.4, 2.5) = 1.30;
uniform float gamma : hint_range(0.4, 2.5) = 1.30;
uniform int color_profile : hint_range(0, 4) = 0; // 0: Vanilla, 1: Dark Gothic, 2: Hellish Crimson, 3: Crypt Cyan, 4: Noir
uniform int upscaler_mode : hint_range(0, 4) = 0;
uniform float fsr_sharpness : hint_range(0.0, 1.0) = 0.50;
uniform bool is_town = false;

// Distinct, Rich Color Grading Profiles
vec3 apply_color_grading(vec3 c, int profile) {
    if (profile == 0) {
        return c; // Vanilla 1996 Classic 32-bit
    }

    if (profile == 1) {
        if (is_town) {
            // In Town, preserve bright open-air daytime sunlit ambiance instead of dark dungeon crushing
            vec3 col = c;
            col.r = pow(col.r, 0.98) * 1.02; // Warm sunlight golden tint
            col.g = pow(col.g, 0.99) * 1.01;
            col.b = pow(col.b, 1.02) * 0.96; // Tame excessive cold cyan/blue
            return clamp(col, 0.0, 1.0);
        }
        // Dark Gothic: True grimdark dungeon contrast, deep inky shadows, rich torchlit highlights
        vec3 col = c;
        col = (col * (2.8 * col + 0.15)) / (col * (2.8 * col + 0.85) + 0.12);
        col.r = pow(col.r, 1.04) * 0.96;
        col.g = pow(col.g, 1.01) * 0.98;
        col.b = pow(col.b, 0.95) * 1.07;
        return clamp(col, 0.0, 1.0);
    } else if (profile == 2) {
        if (is_town) {
            vec3 col = c;
            col.r = pow(col.r, 0.98) * 1.02;
            return clamp(col, 0.0, 1.0);
        }
        // Hellish Crimson - Warm, rich blood-dungeon ambiance
        vec3 graded = c;
        graded.r = pow(graded.r, 0.91) * 1.12;
        graded.g = pow(graded.g, 1.04) * 0.92;
        graded.b = pow(graded.b, 1.09) * 0.84;
        return clamp(graded, 0.0, 1.0);
    } else if (profile == 3) {
        if (is_town) {
            return c; // In Town, never freeze Tristram daylight into chilling crypt cyan!
        }
        // Crypt Cyan - Chilling, eerie spectral cold dungeon ambiance
        vec3 graded = c;
        graded.r = pow(graded.r, 1.10) * 0.84;
        graded.g = pow(graded.g, 0.96) * 1.04;
        graded.b = pow(graded.b, 0.91) * 1.18;
        return clamp(graded, 0.0, 1.0);
    } else if (profile == 4) {
        if (is_town) {
            return c;
        }
        // Desaturated Noir - Dramatic, stark grimdark monochrome with subtle tint
        float l = dot(c, vec3(0.299, 0.587, 0.114));
        vec3 graded = mix(vec3(l), c, 0.28);
        graded = pow(graded, vec3(1.10)) * 1.08;
        return clamp(graded, 0.0, 1.0);
    }

    return c;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec3 col = tex.rgb;

	// Mode 3: AMD FSR 1.0 (EASU + RCAS Full-Screen Pass)
	if (upscaler_mode == 3) {
		vec2 texel = 1.0 / vec2(textureSize(TEXTURE, 0));
		vec3 n = texture(TEXTURE, UV + vec2(0.0, -1.0) * texel).rgb;
		vec3 s = texture(TEXTURE, UV + vec2(0.0, 1.0) * texel).rgb;
		vec3 w = texture(TEXTURE, UV + vec2(-1.0, 0.0) * texel).rgb;
		vec3 e = texture(TEXTURE, UV + vec2(1.0, 0.0) * texel).rgb;
		vec3 nw = texture(TEXTURE, UV + vec2(-1.0, -1.0) * texel).rgb;
		vec3 ne = texture(TEXTURE, UV + vec2(1.0, -1.0) * texel).rgb;
		vec3 sw = texture(TEXTURE, UV + vec2(-1.0, 1.0) * texel).rgb;
		vec3 se = texture(TEXTURE, UV + vec2(1.0, 1.0) * texel).rgb;

		vec3 dc_dx = (ne + 2.0 * e + se) - (nw + 2.0 * w + sw);
		vec3 dc_dy = (sw + 2.0 * s + se) - (nw + 2.0 * n + ne);
		float len_x = length(dc_dx);
		float len_y = length(dc_dy);
		float edge_strength = clamp(max(len_x, len_y) * 2.0, 0.0, 1.0);

		vec2 dir = (len_x + len_y > 0.001) ? normalize(vec2(len_y, -len_x)) : vec2(0.0, 1.0);
		vec3 along1 = texture(TEXTURE, UV + dir * texel * 0.5).rgb;
		vec3 along2 = texture(TEXTURE, UV - dir * texel * 0.5).rgb;
		vec3 easu = mix(col, (along1 + along2) * 0.5, edge_strength * 0.65);

		// RCAS contrast adaptive sharpening
		vec3 min_c = min(easu, min(min(n, s), min(w, e)));
		vec3 max_c = max(easu, max(max(n, s), max(w, e)));
		vec3 amp = clamp(min(min_c, 2.0 - max_c) / max(max_c, vec3(0.001)), 0.0, 1.0);
		vec3 lobe = -sqrt(amp) * (fsr_sharpness * 0.22);
		col = clamp((n * lobe + s * lobe + easu + w * lobe + e * lobe) / (1.0 + 4.0 * lobe), min_c, max_c);
	}

	// Gamma power curve: lifts shadows and midtones smoothly without blowing out highlights
	if (abs(gamma - 1.0) > 0.005) {
		col = pow(clamp(col, 0.0, 1.0), vec3(1.0 / max(gamma, 0.05)));
	}
	col = col * brightness;
	if (color_profile > 0) {
		col = apply_color_grading(col, color_profile);
	}
	COLOR = vec4(col, tex.a);
}