shader_type canvas_item;
render_mode blend_mix;

// Diablo: Definitive Edition - 2D Atmospheric Dungeon Fog (Mode 1)
// Realistic layered procedural mist & drifting smoke across the dungeon playfield.

uniform int fog_mode : hint_range(0, 2) = 1; // 0: Off, 1: Crypt Mist, 2: Dense Drift
uniform float density : hint_range(0.0, 1.0) = 0.22;
uniform float speed : hint_range(0.01, 0.5) = 0.06;
uniform vec2 camera_offset = vec2(0.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.55;
	vec2 shift = vec2(100.0);
	mat2 rot = mat2(vec2(cos(0.5), sin(0.5)), vec2(-sin(0.5), cos(0.5)));
	for (int i = 0; i < 3; ++i) {
		v += a * noise(p);
		p = rot * p * 2.05 + shift;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	if (fog_mode == 0) {
		discard;
	}

	// World-anchored parallax UV coordinates so fog drifts naturally over the dungeon
	vec2 base_uv = (UV * 3.5) + (camera_offset * 0.0004);
	float t = TIME * speed;

	// Two opposing drift layers for turbulent fluid swirl
	vec2 uv1 = base_uv + vec2(t * 0.7, t * 0.4);
	vec2 uv2 = base_uv * 1.4 - vec2(t * 0.5, -t * 0.6);

	float n1 = fbm(uv1);
	float n2 = fbm(uv2 + vec2(n1 * 0.5));
	float mist = smoothstep(0.20, 0.85, (n1 * 0.6 + n2 * 0.4));

	vec3 fog_color;
	float effective_density = density;

	if (fog_mode == 1) {
		// Crypt Mist: subtle eerie spectral blue-grey mist
		fog_color = vec3(0.42, 0.48, 0.56);
		effective_density *= 0.48;
	} else {
		// Dense Drift: warm amber/ash hellfire smoke without obscuring hero or loot
		fog_color = vec3(0.55, 0.34, 0.20);
		effective_density *= 0.52;
	}

	float center_dist = length(UV - vec2(0.5, 0.5));
	float center_clarity = mix(0.24, 1.0, smoothstep(0.08, 0.48, center_dist));
	float alpha = clamp(mist * effective_density * center_clarity, 0.0, 0.30);
	COLOR = vec4(fog_color, alpha);
}
