shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Authentic Diablo 1 3D Molten Liquid Shader (Caves Magma & Hellfire Rivers)
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, hint_default_black;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap;
uniform bool is_hell = false;
uniform float flow_speed : hint_range(0.1, 4.0) = 1.35;
uniform float thermal_intensity : hint_range(0.5, 3.0) = 1.65;
uniform float emission_energy : hint_range(0.0, 5.0) = 2.40;

void fragment() {
	vec2 uv = UV;
	// World-space continuous coordinates for seamless multi-tile flow
	vec3 w_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// 1. Dual-phase convective fluid flow (opposing harmonic currents)
	vec2 flow_a = vec2(sin(w_pos.z * 0.38 + TIME * flow_speed * 1.15), cos(w_pos.x * 0.38 + TIME * flow_speed * 0.90)) * 0.038;
	vec2 flow_b = vec2(cos(w_pos.z * 0.28 - TIME * flow_speed * 0.85), sin(w_pos.x * 0.28 + TIME * flow_speed * 1.05)) * 0.038;

	vec4 tex_a = texture(albedo_texture, uv + flow_a);
	vec4 tex_b = texture(albedo_texture, uv + flow_b);
	vec4 base = mix(tex_a, tex_b, 0.5 + 0.5 * sin(TIME * flow_speed * 1.4));

	// 2. Multi-octave convective thermal currents (world-space)
	float f1 = sin(dot(w_pos.xz, vec2(0.42, 0.22)) - TIME * flow_speed * 1.5);
	float f2 = cos(dot(w_pos.xz, vec2(-0.32, 0.38)) + TIME * flow_speed * 1.1);
	float f3 = sin(dot(w_pos.xz, vec2(0.18, -0.45)) - TIME * flow_speed * 1.8);
	float flux = clamp((f1 * 0.45 + f2 * 0.35 + f3 * 0.20) * 0.5 + 0.5, 0.0, 1.0);

	// 3. Thermal spectrum: cooler crust -> hot magma -> searing white-hot molten core
	vec3 cool_magma = is_hell ? vec3(0.75, 0.10, 0.02) : vec3(0.85, 0.25, 0.02);
	vec3 hot_magma  = is_hell ? vec3(1.35, 0.40, 0.06) : vec3(1.50, 0.75, 0.12);
	vec3 sear_magma = is_hell ? vec3(1.70, 0.85, 0.25) : vec3(1.65, 1.30, 0.40);

	vec3 thermal_col = (flux < 0.5)
		? mix(cool_magma, hot_magma, flux * 2.0)
		: mix(hot_magma, sear_magma, (flux - 0.5) * 2.0);

	vec3 lava_rgb = base.rgb * thermal_col * thermal_intensity;

	ALBEDO = lava_rgb;
	// Molten incandescent emission: self-illuminated incandescent glow
	EMISSION = lava_rgb * (0.90 + 0.35 * flux) * emission_energy;
	ROUGHNESS = 0.22;
	METALLIC = 0.08;

	// 4. Undulating liquid normal waves
	float lw1 = cos(dot(w_pos.xz, vec2(0.42, 0.22)) - TIME * flow_speed * 1.5);
	float lw2 = sin(dot(w_pos.xz, vec2(-0.32, 0.38)) + TIME * flow_speed * 1.1);
	vec3 world_wave = vec3((lw1 * 0.42 - lw2 * 0.32) * 0.20, 0.0, (lw1 * 0.22 + lw2 * 0.38) * 0.20);
	NORMAL = normalize(NORMAL + mat3(VIEW_MATRIX) * world_wave);
}
