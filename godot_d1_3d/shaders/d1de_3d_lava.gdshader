shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// =============================================================================
// Real Godot 3D Procedural Lava & Molten Magma Surface (Caves & Hell)
// Continuous world-space fluid dynamics, Voronoi tectonic crust plates,
// 3D undulating wave displacement, glowing thermal fissures, and radiant bloom.
// =============================================================================

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, hint_default_black;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap;
uniform bool is_hell = false;
uniform float flow_speed : hint_range(0.1, 4.0) = 1.15;
uniform float thermal_intensity : hint_range(0.5, 3.0) = 1.10;
uniform float emission_energy : hint_range(0.0, 5.0) = 0.50;

// Hash function for procedural Voronoi cell generation
vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453123);
}

// 2-distance Voronoi: returns (closest_cell_dist, second_closest_cell_dist)
vec2 voronoi_cells(vec2 p) {
	vec2 n = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = hash2(n + g);
			// Slow organic tectonic drifting of crust plates
			o = 0.5 + 0.35 * sin(o * 6.2831853 + TIME * 0.65 * flow_speed);
			vec2 r = g + o - f;
			float d = dot(r, r);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec2(sqrt(d1), sqrt(d2));
}

void vertex() {
	vec3 w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Real 3D liquid surface undulating waves and bubbling
	float w1 = sin(w_pos.x * 2.2 + TIME * 1.5 * flow_speed) * cos(w_pos.z * 2.2 + TIME * 1.2 * flow_speed);
	float w2 = sin(w_pos.x * 4.4 - TIME * 2.0 * flow_speed + w_pos.z * 3.0) * 0.45;
	VERTEX.y += (w1 + w2) * 0.032;
}

void fragment() {
	vec2 uv = UV;
	// World-space continuous coordinates: seamless fluid across any tile boundaries
	vec3 w_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// 1. Sample original base tile to distinguish rock shoreline vs molten area
	vec4 base_sample = texture(albedo_texture, uv);

	// Multi-octave continuous world-space shoreline noise
	float shore_noise = sin(w_pos.x * 3.2 + sin(w_pos.z * 2.4)) * cos(w_pos.z * 3.2 + cos(w_pos.x * 2.1)) * 0.08;
	shore_noise += sin(w_pos.x * 7.5 - w_pos.z * 5.8) * 0.035;

	// Chromatic classification: pure lava vs shoreline rock
	float red_diff = base_sample.r - max(base_sample.b * 1.8, 0.04);
	float raw_lava = smoothstep(0.04 + shore_noise, 0.22 + shore_noise, red_diff) * smoothstep(0.10, 0.30, base_sample.r);
	float lava_mask = raw_lava;

	// Radiant heat bleed on rocks bordering the lava pool
	float rock_heat = smoothstep(0.01, 0.16, red_diff) * (1.0 - lava_mask);
	vec3 heated_rock = mix(base_sample.rgb, base_sample.rgb * vec3(1.35, 0.70, 0.40) + vec3(0.10, 0.025, 0.005), rock_heat * 0.75);

	// If this pixel is pure solid rock with no thermal influence, render standard PBR cave rock
	if (lava_mask <= 0.001 && rock_heat <= 0.001) {
		ALBEDO = base_sample.rgb;
		ROUGHNESS = 0.85;
		METALLIC = 0.04;
		EMISSION = vec3(0.0);
	} else {
		// 2. Dual-stream tectonic crust flow in world coordinates
		vec2 flow1 = vec2(w_pos.x * 0.55 + TIME * 0.045 * flow_speed, w_pos.z * 0.55 + TIME * 0.025 * flow_speed);
		vec2 flow2 = vec2(w_pos.x * 0.48 - TIME * 0.035 * flow_speed, w_pos.z * 0.48 + TIME * 0.038 * flow_speed);

		vec2 v1 = voronoi_cells(flow1 * 1.25);
		vec2 v2 = voronoi_cells(flow2 * 1.25 + vec2(17.4, 9.2));

		// Intersecting crust fissure edge distance
		float edge1 = v1.y - v1.x;
		float edge2 = v2.y - v2.x;
		float min_edge = min(edge1, edge2);

		// Fissure detection: where crust plates pull apart, glowing magma erupts
		float fissure_factor = 1.0 - smoothstep(0.02, 0.20, min_edge);
		float deep_core = 1.0 - smoothstep(0.01, 0.10, min_edge);

		// Convective thermal currents in the mantle
		float flux1 = sin(dot(w_pos.xz, vec2(0.38, 0.22)) - TIME * flow_speed * 1.4);
		float flux2 = cos(dot(w_pos.xz, vec2(-0.28, 0.35)) + TIME * flow_speed * 1.0);
		float flux = clamp((flux1 * 0.55 + flux2 * 0.45) * 0.5 + 0.5, 0.0, 1.0);

		// 3. Volcanic thermal color spectrum (Authentic Dark Fantasy Magma)
		// Cooled basalt crust -> incandescent orange -> glowing fiery gold (no blown-out white)
		vec3 dark_crust = is_hell ? vec3(0.10, 0.03, 0.02) : vec3(0.12, 0.05, 0.03);
		vec3 glowing_crust_edge = is_hell ? vec3(0.80, 0.18, 0.03) : vec3(0.85, 0.25, 0.04);
		vec3 magma_orange = is_hell ? vec3(1.25, 0.40, 0.05) : vec3(1.30, 0.55, 0.06);
		vec3 searing_gold = is_hell ? vec3(1.45, 0.70, 0.10) : vec3(1.50, 0.85, 0.12);

		// Composite crust color with thermal edge illumination
		vec3 crust_color = mix(dark_crust, glowing_crust_edge, smoothstep(0.12, 0.32, 1.0 - v1.x));
		// Interior molten fissure color
		vec3 molten_core = mix(magma_orange, searing_gold, deep_core * (0.65 + 0.35 * flux));

		vec3 procedural_lava = mix(crust_color, molten_core, fissure_factor) * thermal_intensity;

		// 4. Combine procedural fluid with rock shoreline
		ALBEDO = mix(heated_rock, procedural_lava, lava_mask);

		// 5. Forward+ High Dynamic Range Emission & Bloom (Calibrated against over-exposure)
		vec3 core_emission = molten_core * emission_energy * 0.75;
		vec3 fissure_emission = magma_orange * fissure_factor * emission_energy * 0.50;
		vec3 shore_glow = vec3(0.40, 0.10, 0.02) * rock_heat * 0.50;

		EMISSION = mix(shore_glow, core_emission * fissure_factor + fissure_emission + glowing_crust_edge * 0.20, lava_mask);

		ROUGHNESS = mix(0.85, mix(0.88, 0.18, fissure_factor), lava_mask);
		METALLIC = mix(0.04, 0.06, lava_mask);

		// 6. Dynamic wave normal perturbation for fluid specular reflections
		float lw1 = cos(dot(w_pos.xz, vec2(0.42, 0.22)) - TIME * flow_speed * 1.5);
		float lw2 = sin(dot(w_pos.xz, vec2(-0.32, 0.38)) + TIME * flow_speed * 1.1);
		vec3 world_wave = vec3((lw1 * 0.42 - lw2 * 0.32) * 0.25, 0.0, (lw1 * 0.22 + lw2 * 0.38) * 0.25);
		NORMAL = normalize(NORMAL + mat3(VIEW_MATRIX) * (world_wave * lava_mask));
	}
}
