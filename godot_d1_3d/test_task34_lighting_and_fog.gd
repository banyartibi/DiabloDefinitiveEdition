extends SceneTree

# ==============================================================================
# Test: Task 4 - Forward+ Atmospheric Lighting & Volumetric Fog
# ==============================================================================

func _init():
	print("\n==================================================")
	print(" Testing Task 4: Forward+ Lighting & Volumetric Fog")
	print("==================================================")

	var sandbox_script = load("res://scripts/native_3d_sandbox.gd")
	var sandbox = sandbox_script.new()
	root.add_child(sandbox)
	sandbox.setup_scene_nodes()

	print("\n[1/3] Verifying WorldEnvironment & Post-Processing Setup...")
	assert(sandbox.world_env != null, "ERROR: WorldEnvironment node must exist!")
	assert(sandbox.world_env.environment != null, "ERROR: Environment resource must be assigned!")
	var env = sandbox.world_env.environment
	assert(env.ssao_enabled, "ERROR: Screen-Space Ambient Occlusion (SSAO) must be enabled!")
	assert(env.ssil_enabled, "ERROR: Screen-Space Indirect Lighting (SSIL) must be enabled!")
	assert(env.glow_enabled, "ERROR: Glow/Bloom must be enabled!")
	print("  PASS: SSAO, SSIL, and Glow active on WorldEnvironment!")

	print("\n[2/3] Verifying Dungeon (Level 1) Atmospheric Fog & Contrast...")
	sandbox.update_modular_dungeon_assets(1)
	assert(env.volumetric_fog_enabled, "ERROR: Volumetric Fog must be enabled in Dungeons!")
	assert(env.volumetric_fog_density > 0.001, "ERROR: Volumetric Fog density must be positive!")
	assert(sandbox.dir_light.light_energy < 0.5, "ERROR: Directional sunlight must be suppressed in Dungeons!")
	print("  PASS: Dungeon lighting calibrated: Volumetric Fog active, sunlight suppressed!")

	print("\n[3/3] Verifying Town (Level 0) Daylight Transition...")
	sandbox.update_modular_dungeon_assets(0)
	assert(not env.volumetric_fog_enabled, "ERROR: Volumetric Fog must be disabled in sunny Town!")
	assert(sandbox.dir_light.light_energy >= 1.5, "ERROR: Town must be brightly illuminated by sunlight!")
	assert(sandbox.player_lantern.light_energy == 0.0, "ERROR: Player lantern must be extinguished in Town!")
	print("  PASS: Town daylight transition clean: 0 fog, bright sunlight, lantern off!")

	print("\n==================================================")
	print(" ALL TASK 4 LIGHTING & FOG CHECKS PASSED 100%!   ")
	print("==================================================")
	quit(0)
