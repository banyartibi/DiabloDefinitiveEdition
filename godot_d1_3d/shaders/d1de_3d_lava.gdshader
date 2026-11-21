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
		// 2. Continuous multi-frequency organic fluid convection flow in world coordinates
		vec2 flow1 = vec2(w_pos.x * 0.45 + TIME * 0.05 * flow_speed, w_pos.z * 0.45 + TIME * 0.03 * flow_speed);
		vec2 flow2 = vec2(w_pos.x * 0.65 - TIME * 0.04 * flow_speed, w_pos.z * 0.65 + TIME * 0.045 * flow_speed);

		float n1 = sin(flow1.x * 3.5 + sin(flow1.y * 2.8)) * cos(flow1.y * 3.2 + cos(flow1.x * 2.5));
		float n2 = sin(flow2.x * 5.2 - flow2.y * 4.1 + TIME * 0.8 * flow_speed);
		float fluid_current = (n1 * 0.6 + n2 * 0.4) * 0.5 + 0.5;

		// Convective boiling centers and bubbling thermal plumes (authentic D1 fluid)
		float bubble = sin(w_pos.x * 6.5 + TIME * 2.2 * flow_speed) * cos(w_pos.z * 6.5 + TIME * 1.8 * flow_speed);
		float hot_crests = smoothstep(0.42, 0.82, fluid_current + bubble * 0.20);
		float molten_flow = smoothstep(0.18, 0.58, fluid_current);

		// 3. Authentic Volcanic Magma Spectrum (matching classic D1 Caves palette in Image 2)
		// Cooled basalt crust -> deep molten magma -> incandescent fiery gold
		vec3 dark_crust = is_hell ? vec3(0.18, 0.04, 0.02) : vec3(0.20, 0.08, 0.03);
		vec3 magma_deep = is_hell ? vec3(0.95, 0.22, 0.03) : vec3(0.98, 0.35, 0.05);
		vec3 molten_core = is_hell ? vec3(1.22, 0.42, 0.05) : vec3(1.28, 0.58, 0.08);
		vec3 searing_gold = is_hell ? vec3(1.38, 0.68, 0.10) : vec3(1.42, 0.82, 0.14);

		// Natural liquid blending: dark crust -> molten magma -> hot crests
		vec3 crust_blend = mix(dark_crust, magma_deep, molten_flow);
		vec3 fluid_core = mix(crust_blend, molten_core, hot_crests * 0.85);
		vec3 procedural_lava = mix(fluid_core, searing_gold, hot_crests * 0.45) * thermal_intensity;

		// 4. Combine procedural fluid with rock shoreline
		ALBEDO = mix(heated_rock, procedural_lava, lava_mask);

		// 5. Forward+ High Dynamic Range Emission & Bloom (Calibrated against over-exposure)
		vec3 core_emission = molten_core * emission_energy * 0.65;
		vec3 crest_emission = searing_gold * hot_crests * emission_energy * 0.45;
		vec3 shore_glow = vec3(0.40, 0.10, 0.02) * rock_heat * 0.35;

		EMISSION = mix(shore_glow, core_emission + crest_emission, lava_mask);

		ROUGHNESS = mix(0.85, mix(0.70, 0.25, hot_crests), lava_mask);
		METALLIC = mix(0.04, 0.06, lava_mask);

		// 6. Dynamic wave normal perturbation for fluid specular reflections
		float lw1 = cos(dot(w_pos.xz, vec2(0.42, 0.22)) - TIME * flow_speed * 1.5);
		float lw2 = sin(dot(w_pos.xz, vec2(-0.32, 0.38)) + TIME * flow_speed * 1.1);
		vec3 world_wave = vec3((lw1 * 0.42 - lw2 * 0.32) * 0.25, 0.0, (lw1 * 0.22 + lw2 * 0.38) * 0.25);
		NORMAL = normalize(NORMAL + mat3(VIEW_MATRIX) * (world_wave * lava_mask));
	}
}
