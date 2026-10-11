shader_type canvas_item;
render_mode blend_mix;

// Continuous 2.5D GPU Isometric Lightmap & PBR Surface Shader
// Eliminates discrete tile-by-tile checkerboards and blocky cube shadows
// Bilinear hardware GPU filtering interpolates light smoothly across every pixel

uniform sampler2D light_map : filter_linear, repeat_disable;
uniform vec3 light_tint = vec3(1.0, 0.95, 0.88);
uniform float bump_scale : hint_range(0.0, 3.0) = 1.0;
uniform float specular_gloss : hint_range(0.0, 2.0) = 0.50;
uniform bool is_town = false;
uniform bool is_lava_level = false; // Caves (L9-12) & Hell (L13-16) only
uniform int relief_mode : hint_range(0, 4) = 0; // 0: Off, 1: Subtle, 2: Balanced, 3: Deep 3D, 4: Extreme
uniform bool wet_floor = true; // Wet cobblestone PBR reflections & specular gloss

varying vec2 v_world_pos;
varying vec2 v_foot_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	v_foot_pos = MODEL_MATRIX[3].xy;
}
 
void fragment() {
	// Universal 2:1 Isometric Diamond Geometry for ALL Pieces (Floors, Walls, Columns, Scenery):
	// A standard floor row has aspect ratio height = width * 0.5 (2:1 diamond).
	// In normalized UV coordinates:
	float floor_row_h = clamp((TEXTURE_PIXEL_SIZE.y / TEXTURE_PIXEL_SIZE.x) * 0.5, 0.0, 1.0);
	float floor_row_start = 1.0 - floor_row_h;
	bool is_floor_piece = (floor_row_h >= 0.90);
	bool in_floor_row = is_floor_piece || (UV.y >= (floor_row_start - 0.002));

	vec2 final_uv = UV;
	if (relief_mode >= 3 && !is_town) {
		// Parallax Occlusion Mapping (POM) for high-resolution dungeon PBR surfaces
		vec2 view_dir = vec2(0.0, 0.45);
		float h_scale = (relief_mode == 4 ? 0.008 : 0.004) * bump_scale;

		const int pom_steps = 6;
		float step_size = 1.0 / float(pom_steps);
		vec2 step_delta = view_dir * (h_scale / float(pom_steps));

		vec2 curr_uv = UV;
		float curr_depth = 0.0;
		float curr_height = 1.0 - dot(texture(TEXTURE, curr_uv).rgb, vec3(0.299, 0.587, 0.114));

		for (int i = 0; i < pom_steps; i++) {
			if (curr_depth >= curr_height) {
				break;
			}
			vec2 next_uv = curr_uv + step_delta;
			if (texture(TEXTURE, next_uv).a < 0.25) {
				break;
			}
			curr_uv = next_uv;
			curr_depth += step_size;
			curr_height = 1.0 - dot(texture(TEXTURE, curr_uv).rgb, vec3(0.299, 0.587, 0.114));
		}
		final_uv = curr_uv;
	}

	vec4 tex = texture(TEXTURE, final_uv);

	// Universal 2:1 Isometric Diamond Geometry in world coordinates
	vec2 tile_center = v_foot_pos - vec2(0.0, 16.0);
	float d_diamond = (abs(v_world_pos.x - tile_center.x) / 32.0) + (abs(v_world_pos.y - tile_center.y) / 16.0);

	// Discard rules:
	// - Floor pieces (both town & dungeon): allow slight subpixel overlap (d_diamond <= 1.045)
	//   and only discard quad corners if tex.a is low, eliminating black grid lines between tiles.
	// - Tall wall / scenery / tree pieces: preserve natural alpha cutouts (tex.a < 0.15)
	if (is_floor_piece) {
		if (d_diamond > 1.045 && tex.a < 0.50) {
			discard;
		}
		if (tex.a < 0.15) {
			discard;
		}
	} else {
		if (tex.a < 0.15) {
			discard;
		}
	}

	// Authentic un-altered surface color
	vec3 base_rgb = tex.rgb;

	// For floor rows: use per-pixel world_pos for seamless continuous lightmap interpolation.
	// For upper walls: anchor lighting to the base tile center (v_foot_pos - (0, 16)).
	vec2 sample_pos = in_floor_row ? v_world_pos : (v_foot_pos - vec2(0.0, 16.0));

	// Convert isometric world coordinates (wx, wy) -> tile grid coordinates (tx, ty):
	vec2 tile_coord = vec2(sample_pos.x / 64.0 + sample_pos.y / 32.0, sample_pos.y / 32.0 - sample_pos.x / 64.0);
	vec2 uv_light = (tile_coord + vec2(0.5, 0.5)) / 112.0;

	float l = texture(light_map, clamp(uv_light, vec2(0.0), vec2(1.0))).r;

	// For walls: keep bottom 32 world pixels solid when front wall fades transparently
	float effective_a = COLOR.a;
	if (!is_floor_piece && v_world_pos.y >= (v_foot_pos.y - 32.0)) {
		effective_a = 1.0;
	}

	// Floor pieces are 100% solid stone/earth so ground never leaks black background gaps across any zoom level;
	// Upper walls, trees, roofs, fences preserve natural texture alpha:
	float final_a = is_floor_piece ? effective_a : (tex.a * effective_a);

	if (is_town) {
		// Preserves authentic Tristram daytime sunlit ambiance with deep contrast
		base_rgb = pow(clamp(base_rgb, 0.0, 1.0), vec3(0.95));
		vec3 daylight = vec3(1.10, 1.08, 1.02); // Natural warm medieval sunshine

		// Dynamic River Water Flow Simulation (Tristram river)
		// Continuous water detection across riverbed & shoreline pieces
		float water_factor = 0.0;
		if (in_floor_row) {
			float b_excess = base_rgb.b - base_rgb.r * 0.92;
			if (b_excess > 0.005) {
				water_factor = smoothstep(0.005, 0.06, b_excess) * smoothstep(0.04, 0.12, base_rgb.b);
			}
		}

		float flow_t = TIME * 2.0;
		float wave1 = sin(dot(v_world_pos, vec2(0.05, 0.04)) - flow_t);
		float wave2 = cos(dot(v_world_pos, vec2(-0.04, 0.06)) + flow_t * 0.85);

		if (water_factor > 0.001) {
			// Continuous world-pos water flow (flowing southwest along the riverbed)
			float wave3 = sin(dot(v_world_pos, vec2(0.07, -0.05)) - flow_t * 1.3);
			float caustic = clamp(wave1 * 0.35 + wave2 * 0.35 + wave3 * 0.30 + 0.35, 0.0, 1.0);
			float shimmer = pow(caustic, 2.5);

			// Lift deep riverbed color to natural mountain stream azure
			vec3 stream_blue = vec3(0.12, 0.26, 0.45);
			base_rgb = mix(base_rgb, max(base_rgb, stream_blue), water_factor * 0.65);
			base_rgb += vec3(0.05, 0.11, 0.18) * shimmer * water_factor;
		}

		if (relief_mode > 0) {
			float mult = 0.35;
			if (relief_mode == 2) mult = 0.65;
			else if (relief_mode == 3) mult = 1.0;
			else if (relief_mode == 4) mult = 1.5;

			if (water_factor > 0.20) {
				vec2 water_n = vec2(wave1, wave2) * 0.25 * mult;
				NORMAL = normalize(vec3(mix(NORMAL.xy, water_n, water_factor), 1.0));
			} else if (length(NORMAL.xy) > 0.001) {
				NORMAL = normalize(vec3(NORMAL.xy * mult * bump_scale, NORMAL.z));
			} else {
				vec2 texel = TEXTURE_PIXEL_SIZE;
				const vec3 luma = vec3(0.299, 0.587, 0.114);
				float l_c = dot(tex.rgb, luma);

				// Boundary-safe sampling: out-of-bounds or zero-alpha neighbors fall back to center luma (eliminates edge bevels!)
				vec4 s_tl = texture(TEXTURE, final_uv + vec2(-1.0, -1.0) * texel);
				vec4 s_tc = texture(TEXTURE, final_uv + vec2( 0.0, -1.0) * texel);
				vec4 s_tr = texture(TEXTURE, final_uv + vec2( 1.0, -1.0) * texel);
				vec4 s_ml = texture(TEXTURE, final_uv + vec2(-1.0,  0.0) * texel);
				vec4 s_mr = texture(TEXTURE, final_uv + vec2( 1.0,  0.0) * texel);
				vec4 s_bl = texture(TEXTURE, final_uv + vec2(-1.0,  1.0) * texel);
				vec4 s_bc = texture(TEXTURE, final_uv + vec2( 0.0,  1.0) * texel);
				vec4 s_br = texture(TEXTURE, final_uv + vec2( 1.0,  1.0) * texel);

				float l_tl = (s_tl.a > 0.10) ? dot(s_tl.rgb, luma) : l_c;
				float l_tc = (s_tc.a > 0.10) ? dot(s_tc.rgb, luma) : l_c;
				float l_tr = (s_tr.a > 0.10) ? dot(s_tr.rgb, luma) : l_c;
				float l_ml = (s_ml.a > 0.10) ? dot(s_ml.rgb, luma) : l_c;
				float l_mr = (s_mr.a > 0.10) ? dot(s_mr.rgb, luma) : l_c;
				float l_bl = (s_bl.a > 0.10) ? dot(s_bl.rgb, luma) : l_c;
				float l_bc = (s_bc.a > 0.10) ? dot(s_bc.rgb, luma) : l_c;
				float l_br = (s_br.a > 0.10) ? dot(s_br.rgb, luma) : l_c;

				float gx = (l_tr + 2.0 * l_mr + l_br) - (l_tl + 2.0 * l_ml + l_bl);
				float gy = (l_bl + 2.0 * l_bc + l_br) - (l_tl + 2.0 * l_tc + l_tr);

				float strength = 1.0 * mult * bump_scale;
				if (is_floor_piece) {
					// Smoothly fade relief to 0 at the tile perimeter so adjacent floor tiles meet seamlessly with flat normal (0,0,1)
					strength *= smoothstep(1.00, 0.90, d_diamond);
				}
				NORMAL = normalize(vec3(-gx * strength, -gy * strength, 1.0));
			}

			// Directional sunlight relief modulation across Tristram roofs, grass and cobbles
			vec3 sun_dir = normalize(vec3(-0.35, -0.55, 0.75));
			float sun_diff = dot(NORMAL, sun_dir);
			vec3 sun_tint = daylight * (0.90 + 0.10 * sun_diff);
			COLOR = vec4(base_rgb * sun_tint, final_a);
		} else {
			NORMAL = vec3(0.0, 0.0, 1.0);
			COLOR = vec4(base_rgb * daylight, final_a);
		}
	} else {
		// Dungeon lighting: smooth continuous Hermite curve with minimum ambient visibility (matches authentic D1 palette minimum ambient)
		float min_amb = 0.18;
		vec3 lit_tint = mix(vec3(min_amb), light_tint, l);

		// Dynamic Liquid Simulation (Hell blood/lava + Caves molten magma)
		// True incandescent molten lava: high red intensity and dominant over green/blue
		bool is_caves_lava = (base_rgb.r > 0.28 && base_rgb.r > base_rgb.g * 1.10 && base_rgb.b < 0.22);
		bool is_hell_lava = (base_rgb.r > 0.28 && base_rgb.r > base_rgb.g * 1.15 && base_rgb.r > base_rgb.b * 1.45 && base_rgb.b < 0.38);
		bool is_lava = is_lava_level && (is_caves_lava || is_hell_lava);
		if (is_lava) {
			// Continuous fluid convective UV churning (samples flowing liquid motion)
			vec2 flow_a = vec2(sin(v_world_pos.y * 0.045 + TIME * 1.6), cos(v_world_pos.x * 0.045 + TIME * 1.2)) * 0.035;
			vec2 flow_b = vec2(cos(v_world_pos.y * 0.035 - TIME * 1.1), sin(v_world_pos.x * 0.035 + TIME * 1.5)) * 0.035;
			vec4 tex_flow_a = texture(TEXTURE, clamp(final_uv + flow_a, vec2(0.01), vec2(0.99)));
			vec4 tex_flow_b = texture(TEXTURE, clamp(final_uv + flow_b, vec2(0.01), vec2(0.99)));
			vec3 flowing_rgb = mix(tex_flow_a.rgb, tex_flow_b.rgb, 0.5 + 0.5 * sin(TIME * 2.0));

			// Multi-octave convective thermal currents (world-space, 100% gapless across tiles)
			float flow1 = sin(dot(v_world_pos, vec2(0.045, 0.025)) - TIME * 2.4);
			float flow2 = cos(dot(v_world_pos, vec2(-0.035, 0.040)) + TIME * 1.8);
			float flow3 = sin(dot(v_world_pos, vec2(0.020, -0.050)) - TIME * 3.1);

			// Combined convective heat flux: 0.0 (cooler basalt crust) to 1.0 (white-hot molten surge)
			float flux = clamp((flow1 * 0.45 + flow2 * 0.35 + flow3 * 0.20) * 0.5 + 0.5, 0.0, 1.0);

			// Molten thermal color spectrum
			vec3 cool_magma = is_hell_lava ? vec3(0.70, 0.08, 0.02) : vec3(0.75, 0.22, 0.02);
			vec3 hot_magma  = is_hell_lava ? vec3(1.20, 0.30, 0.06) : vec3(1.25, 0.65, 0.10);
			vec3 sear_magma = is_hell_lava ? vec3(1.55, 0.65, 0.20) : vec3(1.50, 1.10, 0.35);

			// Smooth two-phase interpolation across temperature gradient
			vec3 thermal_color = (flux < 0.5)
				? mix(cool_magma, hot_magma, flux * 2.0)
				: mix(hot_magma, sear_magma, (flux - 0.5) * 2.0);

			// Authentic texture modulation with visibly flowing fluid churning
			float lava_intensity = clamp((flowing_rgb.r - flowing_rgb.b) * 1.6, 0.0, 1.0);
			base_rgb = mix(flowing_rgb, flowing_rgb * thermal_color, 0.85 * lava_intensity);

			// Luminous incandescent floor radiance (surges in sync with thermal waves)
			vec3 min_radiance = is_hell_lava ? vec3(0.85, 0.28, 0.12) : vec3(0.80, 0.52, 0.18);
			lit_tint = max(lit_tint, min_radiance * (0.90 + 0.35 * flux));
		}

		COLOR = vec4(base_rgb * lit_tint, final_a);

		if (relief_mode > 0) {
			float mult = 0.35;
			if (relief_mode == 2) mult = 0.65;
			else if (relief_mode == 3) mult = 1.0;
			else if (relief_mode == 4) mult = 1.5;

			if (is_lava) {
				// Dynamic undulating liquid surface normal waves
				float lw1 = cos(dot(v_world_pos, vec2(0.045, 0.025)) - TIME * 2.4);
				float lw2 = sin(dot(v_world_pos, vec2(-0.035, 0.040)) + TIME * 1.8);
				vec2 liquid_norm = vec2(lw1 * 0.045 - lw2 * 0.035, lw1 * 0.025 + lw2 * 0.040) * 8.0 * mult;
				NORMAL = normalize(vec3(NORMAL.xy + liquid_norm, 1.0));
			} else if (length(NORMAL.xy) > 0.001) {
				// Scale pre-baked normal map from CanvasTexture
				NORMAL = normalize(vec3(NORMAL.xy * mult * bump_scale, NORMAL.z));
			} else {
				// Real-time procedural Sobel normal for levels without pre-baked PBR
				vec2 texel = TEXTURE_PIXEL_SIZE;
				const vec3 luma = vec3(0.299, 0.587, 0.114);
				float l_c = dot(tex.rgb, luma);

				// Boundary-safe sampling: out-of-bounds or zero-alpha neighbors fall back to center luma (eliminates edge bevels!)
				vec4 s_tl = texture(TEXTURE, final_uv + vec2(-1.0, -1.0) * texel);
				vec4 s_tc = texture(TEXTURE, final_uv + vec2( 0.0, -1.0) * texel);
				vec4 s_tr = texture(TEXTURE, final_uv + vec2( 1.0, -1.0) * texel);
				vec4 s_ml = texture(TEXTURE, final_uv + vec2(-1.0,  0.0) * texel);
				vec4 s_mr = texture(TEXTURE, final_uv + vec2( 1.0,  0.0) * texel);
				vec4 s_bl = texture(TEXTURE, final_uv + vec2(-1.0,  1.0) * texel);
				vec4 s_bc = texture(TEXTURE, final_uv + vec2( 0.0,  1.0) * texel);
				vec4 s_br = texture(TEXTURE, final_uv + vec2( 1.0,  1.0) * texel);

				float l_tl = (s_tl.a > 0.10) ? dot(s_tl.rgb, luma) : l_c;
				float l_tc = (s_tc.a > 0.10) ? dot(s_tc.rgb, luma) : l_c;
				float l_tr = (s_tr.a > 0.10) ? dot(s_tr.rgb, luma) : l_c;
				float l_ml = (s_ml.a > 0.10) ? dot(s_ml.rgb, luma) : l_c;
				float l_mr = (s_mr.a > 0.10) ? dot(s_mr.rgb, luma) : l_c;
				float l_bl = (s_bl.a > 0.10) ? dot(s_bl.rgb, luma) : l_c;
				float l_bc = (s_bc.a > 0.10) ? dot(s_bc.rgb, luma) : l_c;
				float l_br = (s_br.a > 0.10) ? dot(s_br.rgb, luma) : l_c;

				float gx = (l_tr + 2.0 * l_mr + l_br) - (l_tl + 2.0 * l_ml + l_bl);
				float gy = (l_bl + 2.0 * l_bc + l_br) - (l_tl + 2.0 * l_tc + l_tr);

				float strength = 1.2 * mult * bump_scale;
				NORMAL = normalize(vec3(-gx * strength, -gy * strength, 1.0));
			}
		} else {
			NORMAL = vec3(0.0, 0.0, 1.0);
		}
	}
}

void light() {
	float attenuation = LIGHT_COLOR.a;
	if (COLOR.a > 0.01 && attenuation > 0.0001 && !is_town) {
		vec3 light_color = LIGHT_COLOR.rgb * LIGHT_ENERGY;

		// 3D Surface Relief bump modulation
		float relief_factor = 1.0;
		vec3 ldir = (length(LIGHT_DIRECTION) > 0.001) ? normalize(LIGHT_DIRECTION) : vec3(0.0, 1.0, 0.0);
		if (relief_mode > 0 && length(NORMAL.xy) > 0.001) {
			relief_factor = clamp(dot(NORMAL.xy, ldir.xy) * 0.35 + 1.0, 0.70, 1.30);
		}

		// PBR Physical Material Properties from ORM (CanvasTexture.specular_texture)
		// SPECULAR_SHININESS.r = Ambient Occlusion (AO)
		// SPECULAR_SHININESS.g = Roughness
		// SPECULAR_SHININESS.b = Metallic
		vec4 orm = SPECULAR_SHININESS;
		float ao = (orm.r > 0.02) ? orm.r : 1.0;
		float roughness = (orm.g > 0.02) ? clamp(orm.g, 0.10, 1.0) : 0.85;
		float metallic = orm.b;

		// Wet Floor & PBR Specular Highlights
		vec3 pbr_specular = vec3(0.0);
		bool is_floor = (TEXTURE_PIXEL_SIZE.x / TEXTURE_PIXEL_SIZE.y <= 0.55);
		if (wet_floor && is_floor) {
			// Microfacet specular GGX approximation
			vec3 half_vector = normalize(vec3(-ldir.xy * 0.5, 0.85));
			float NdotH = clamp(dot(NORMAL, half_vector), 0.0, 1.0);
			float NdotL = clamp(dot(NORMAL, ldir), 0.0, 1.0);

			float alpha_rough = roughness * roughness;
			float d_denom = (NdotH * NdotH * (alpha_rough * alpha_rough - 1.0) + 1.0);
			float D = (alpha_rough * alpha_rough) / max(3.14159 * d_denom * d_denom, 0.001);

			vec3 f0 = mix(vec3(0.04), COLOR.rgb, metallic);
			vec3 F = f0 + (vec3(1.0) - f0) * pow(clamp(1.0 - dot(half_vector, ldir), 0.0, 1.0), 5.0);

			pbr_specular = (D * F * 0.35) * light_color * NdotL * specular_gloss;
		}

		// Dynamic normal-map surface bump perturbation + warm torch diffuse + PBR specular
		vec3 relief_perturbation = COLOR.rgb * ((relief_factor - 1.0) * 0.4);
		vec3 torch_diffuse = COLOR.rgb * light_color * 0.70;
		LIGHT = vec4((relief_perturbation + torch_diffuse + pbr_specular) * attenuation, COLOR.a);
	} else {
		LIGHT = vec4(0.0);
	}
}
