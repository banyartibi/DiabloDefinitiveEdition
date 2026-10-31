shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Authentic Diablo 1 3D Molten Liquid Shader (Caves Magma & Hellfire Rivers)
// Organic world-space shoreline blending: eliminates blocky diamond seams with
// cooling basalt crust, convective harmonic waves, and radiant shore heat bleed.
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, hint_default_black;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap;
uniform bool is_hell = false;
uniform float flow_speed : hint_range(0.1, 4.0) = 1.35;
uniform float thermal_intensity : hint_range(0.5, 3.0) = 1.65;
uniform float emission_energy : hint_range(0.0, 5.0) = 2.40;

void fragment() {
	vec2 uv = UV;
	// World-space continuous coordinates for seamless multi-tile flow & organic shores
	vec3 w_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// 1. Sample original base texture without distortion to compute chromatic signature
	vec4 base_sample = texture(albedo_texture, uv);

	// 2. Continuous world-space harmonic noise to break up rigid diamond borders
	float shore_noise = sin(w_pos.x * 3.8 + sin(w_pos.z * 2.8)) * cos(w_pos.z * 3.8 + cos(w_pos.x * 2.5)) * 0.08;
	shore_noise += sin(w_pos.x * 8.5 - w_pos.z * 6.5) * 0.035;

	// Diamond edge distance in UV coordinates: perimeter is at |uv.x - 0.5| + |uv.y - 0.5| == 0.5
	float diamond_dist = abs(uv.x - 0.5) + abs(uv.y - 0.5);
	float edge_falloff = smoothstep(0.50, 0.42, diamond_dist + shore_noise * 0.4);

	// Per-pixel chromatic discrimination: lava has high red and low blue (R >> B * 1.8), rocks are neutral/gray/brown
	float red_diff = base_sample.r - max(base_sample.b * 1.8, 0.04);
	float raw_lava = smoothstep(0.04 + shore_noise, 0.22 + shore_noise, red_diff) * smoothstep(0.10, 0.30, base_sample.r);
	float lava_mask = raw_lava * edge_falloff;

	// Radiant heat bleed on shoreline rock bordering the molten river
	float rock_heat = smoothstep(0.01, 0.16, red_diff) * (1.0 - lava_mask);
	vec3 heated_rock = mix(base_sample.rgb, base_sample.rgb * vec3(1.35, 0.70, 0.40) + vec3(0.08, 0.02, 0.005), rock_heat * 0.65);

	// If this pixel is pure rock with no thermal influence, render standard PBR cave rock
	if (lava_mask <= 0.001 && rock_heat <= 0.001) {
		ALBEDO = base_sample.rgb;
		ROUGHNESS = 0.85;
		METALLIC = 0.04;
		EMISSION = vec3(0.0);
	} else {
		// 3. Dual-phase convective fluid flow (opposing harmonic currents)
		vec2 flow_a = vec2(sin(w_pos.z * 0.38 + TIME * flow_speed * 1.15), cos(w_pos.x * 0.38 + TIME * flow_speed * 0.90)) * 0.038;
		vec2 flow_b = vec2(cos(w_pos.z * 0.28 - TIME * flow_speed * 0.85), sin(w_pos.x * 0.28 + TIME * flow_speed * 1.05)) * 0.038;

		// Displace UVs strictly scaled by lava_mask so rock boundaries never warp or jitter
		vec4 tex_a = texture(albedo_texture, uv + flow_a * lava_mask);
		vec4 tex_b = texture(albedo_texture, uv + flow_b * lava_mask);
		vec4 flowing_base = mix(tex_a, tex_b, 0.5 + 0.5 * sin(TIME * flow_speed * 1.4));

		// 4. Multi-octave convective thermal currents (world-space continuous)
		float f1 = sin(dot(w_pos.xz, vec2(0.42, 0.22)) - TIME * flow_speed * 1.5);
		float f2 = cos(dot(w_pos.xz, vec2(-0.32, 0.38)) + TIME * flow_speed * 1.1);
		float f3 = sin(dot(w_pos.xz, vec2(0.18, -0.45)) - TIME * flow_speed * 1.8);
		float flux = clamp((f1 * 0.45 + f2 * 0.35 + f3 * 0.20) * 0.5 + 0.5, 0.0, 1.0);

		// 5. Thermal spectrum: cooler crust -> hot magma -> searing white-hot molten core
		vec3 cool_magma = is_hell ? vec3(0.75, 0.10, 0.02) : vec3(0.85, 0.25, 0.02);
		vec3 hot_magma  = is_hell ? vec3(1.35, 0.40, 0.06) : vec3(1.50, 0.75, 0.12);
		vec3 sear_magma = is_hell ? vec3(1.70, 0.85, 0.25) : vec3(1.65, 1.30, 0.40);

		vec3 thermal_col = (flux < 0.5)
			? mix(cool_magma, hot_magma, flux * 2.0)
			: mix(hot_magma, sear_magma, (flux - 0.5) * 2.0);

		vec3 pure_lava = flowing_base.rgb * thermal_col * thermal_intensity;

		// 6. Cooling volcanic basalt crust layer with glowing thermal fissures
		float crust_factor = smoothstep(0.12, 0.55, lava_mask) * (1.0 - smoothstep(0.55, 0.85, lava_mask));
		float fissures = smoothstep(0.68, 0.85, sin(w_pos.x * 14.0 + f1 * 3.0) * cos(w_pos.z * 14.0 + f2 * 3.0));
		vec3 crust_color = mix(vec3(0.09, 0.07, 0.06), hot_magma * 1.8, fissures);

		// 7. Organic composite blending
		vec3 lava_composite = mix(crust_color, pure_lava, smoothstep(0.30, 0.75, lava_mask));
		ALBEDO = mix(heated_rock, lava_composite, lava_mask);

		// Molten incandescent emission with glowing fissures and soft shoreline heat dissipation
		EMISSION = (pure_lava * (0.85 + 0.35 * flux) * emission_energy * smoothstep(0.20, 0.85, lava_mask))
		         + (hot_magma * fissures * crust_factor * emission_energy * 0.8)
		         + (vec3(0.35, 0.08, 0.01) * rock_heat * 0.45);

		ROUGHNESS = mix(0.85, 0.22, lava_mask);
		METALLIC = mix(0.04, 0.08, lava_mask);

		// 8. Undulating liquid normal waves, feathered smoothly towards shore
		float lw1 = cos(dot(w_pos.xz, vec2(0.42, 0.22)) - TIME * flow_speed * 1.5);
		float lw2 = sin(dot(w_pos.xz, vec2(-0.32, 0.38)) + TIME * flow_speed * 1.1);
		vec3 world_wave = vec3((lw1 * 0.42 - lw2 * 0.32) * 0.20, 0.0, (lw1 * 0.22 + lw2 * 0.38) * 0.20);
		NORMAL = normalize(NORMAL + mat3(VIEW_MATRIX) * (world_wave * lava_mask));
	}
}
