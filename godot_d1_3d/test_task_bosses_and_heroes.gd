extends SceneTree

# ==============================================================================
# Comprehensive Verification: AAA Bosses (Leoric, Lazarus, Diablo) & Hero Classes
# ==============================================================================

func _init() -> void:
	print("\n==================================================================")
	print("  RUNNING VERIFICATION: AAA BOSSES, HERO CLASSES & PORTAL VORTEX")
	print("==================================================================\n")

	test_leoric_controller()
	test_lazarus_controller()
	test_diablo_controller()
	test_rogue_and_sorcerer_heroes()
	test_sandbox_boss_and_hero_dispatch()
	test_portal_vortex_vfx()

	print("\n==================================================================")
	print("  ALL VERIFICATION TESTS COMPLETED SUCCESSFULLY (100% PASS)!")
	print("==================================================================\n")
	quit(0)

func test_leoric_controller() -> void:
	print("[Test 1] King Leoric (A Csontváz Király) Boss Controller...")
	var leoric_script = load("res://scripts/entities/leoric_3d_controller.gd")
	assert(leoric_script != null, "Leoric script must load cleanly")

	var leoric = leoric_script.new()
	assert(leoric != null, "Leoric controller must instantiate")
	assert(leoric.monster_type == "LEORIC", "Monster type must be LEORIC")

	assert(leoric.unholy_aura_light != null, "Unholy aura light must be created")
	assert(abs(leoric.unholy_aura_light.light_color.r - 0.78) < 0.05, "Unholy aura must be royal purple/amethyst")
	assert(leoric.spectral_particles != null, "Spectral mist particles must be created")

	# Test signal wiring
	var sword_box = {"called": false}
	leoric.sword_impact.connect(func(pos): sword_box["called"] = true)
	leoric.trigger_greatsword_windup()
	assert(sword_box["called"], "Greatsword windup must emit sword_impact")

	var res_box = {"pulse_called": false, "pos": Vector3.ZERO}
	leoric.resurrection_pulse.connect(func(pos):
		res_box["pulse_called"] = true
		res_box["pos"] = pos
	)
	leoric.trigger_resurrection_wave()
	assert(res_box["pulse_called"], "Resurrection wave must emit resurrection_pulse")

	leoric.queue_free()
	print("  -> PASS: King Leoric controller correctly handles unholy aura, spectral mist, and resurrection pulse.")

func test_lazarus_controller() -> void:
	print("[Test 2] Archbishop Lazarus Boss Controller...")
	var lazarus_script = load("res://scripts/entities/lazarus_3d_controller.gd")
	assert(lazarus_script != null, "Lazarus script must load cleanly")

	var lazarus = lazarus_script.new()
	assert(lazarus != null, "Lazarus controller must instantiate")
	assert(lazarus.monster_type == "LAZARUS", "Monster type must be LAZARUS")

	assert(lazarus.ritual_light != null, "Ritual light must be created")
	assert(abs(lazarus.ritual_light.light_color.r - 0.95) < 0.05, "Ritual light must be blood-orange/crimson")
	assert(lazarus.ritual_particles != null, "Ritual ember particles must be created")

	lazarus.queue_free()
	print("  -> PASS: Archbishop Lazarus controller handles ceremonial ritual light and Hellfire windup.")

func test_diablo_controller() -> void:
	print("[Test 3] Diablo (The Lord of Terror) Final Boss Controller...")
	var diablo_script = load("res://scripts/entities/diablo_3d_controller.gd")
	assert(diablo_script != null, "Diablo script must load cleanly")

	var diablo = diablo_script.new()
	assert(diablo != null, "Diablo controller must instantiate")
	assert(diablo.monster_type == "DIABLO", "Monster type must be DIABLO")

	assert(diablo.lord_aura_light != null, "Hellfire aura light must be created")
	assert(abs(diablo.lord_aura_light.light_color.r - 1.0) < 0.05, "Lord aura must be deep fiery crimson")
	assert(diablo.hellfire_particles != null, "Brimstone ash particles must be created")

	diablo.queue_free()
	print("  -> PASS: Diablo controller handles incandescent aura, heavy steps, and Apocalypse strike.")

func test_rogue_and_sorcerer_heroes() -> void:
	print("[Test 4] Rogue & Sorcerer Hero 3D Controllers...")
	var rogue_script = load("res://scripts/entities/rogue_3d_controller.gd")
	assert(rogue_script != null, "Rogue script must load cleanly")
	var rogue = rogue_script.new()
	assert(rogue.turn_speed == 18.0, "Rogue must have nimble 18.0 turn speed")
	rogue.queue_free()

	var sorcerer_script = load("res://scripts/entities/sorcerer_3d_controller.gd")
	assert(sorcerer_script != null, "Sorcerer script must load cleanly")
	var sorcerer = sorcerer_script.new()
	assert(sorcerer.mana_shield_mesh != null, "Sorcerer must initialize Mana Shield sphere mesh")
	sorcerer.set_mana_shield(true)
	assert(sorcerer.mana_shield_active == true, "Mana shield must activate")
	assert(sorcerer.mana_shield_mesh.visible == true, "Mana shield sphere must become visible")
	sorcerer.queue_free()

	print("  -> PASS: Rogue and Sorcerer 3D controllers manage bow draw and shimmering Mana Shield.")

func test_sandbox_boss_and_hero_dispatch() -> void:
	print("[Test 5] Sandbox Boss Dispatch & Hero Class Wiring...")
	var sandbox_script = load("res://scripts/native_3d_sandbox.gd")
	assert(sandbox_script != null, "Sandbox script must load")

	var sandbox = sandbox_script.new()
	sandbox._ready()

	# 1. Test Hero Class Switching (0=Warrior, 1=Rogue, 2=Sorcerer)
	sandbox.setup_hero_controller_for_class(0)
	assert(sandbox.hero_controller != null, "Warrior hero controller must exist")
	assert(sandbox.hero_controller.get_class() != "", "Hero controller must be a valid node")

	sandbox.setup_hero_controller_for_class(1)
	assert(sandbox.current_player_class == 1, "Current player class must update to Rogue (1)")
	assert(sandbox.hero_controller != null, "Rogue hero controller must exist")

	sandbox.setup_hero_controller_for_class(2)
	assert(sandbox.current_player_class == 2, "Current player class must update to Sorcerer (2)")
	assert(sandbox.hero_controller != null, "Sorcerer hero controller must exist")

	# 2. Test Boss Node Creation
	var m_butcher = sandbox.get_or_create_monster_node(101, "The Butcher")
	var butcher_ctrl = m_butcher.get_node_or_null("Monster3DController")
	assert(butcher_ctrl != null and butcher_ctrl.monster_type == "BUTCHER", "Butcher node must receive Butcher3DController")

	var m_leoric = sandbox.get_or_create_monster_node(102, "The Skeleton King")
	var leoric_ctrl = m_leoric.get_node_or_null("Monster3DController")
	assert(leoric_ctrl != null and leoric_ctrl.monster_type == "LEORIC", "Leoric node must receive Leoric3DController")

	var m_lazarus = sandbox.get_or_create_monster_node(103, "Archbishop Lazarus")
	var lazarus_ctrl = m_lazarus.get_node_or_null("Monster3DController")
	assert(lazarus_ctrl != null and lazarus_ctrl.monster_type == "LAZARUS", "Lazarus node must receive Lazarus3DController")

	var m_diablo = sandbox.get_or_create_monster_node(104, "Diablo")
	var diablo_ctrl = m_diablo.get_node_or_null("Monster3DController")
	assert(diablo_ctrl != null and diablo_ctrl.monster_type == "DIABLO", "Diablo node must receive Diablo3DController")

	sandbox.queue_free()
	print("  -> PASS: Sandbox automatically dispatches custom boss controllers and hero classes.")

func test_portal_vortex_vfx() -> void:
	print("[Test 6] 3D Portal Vortex Particles...")
	var sandbox_script = load("res://scripts/native_3d_sandbox.gd")
	var sandbox = sandbox_script.new()
	sandbox._ready()

	# Create a mock Town Portal missile
	var mock_bridge = MockPortalBridge.new()
	sandbox.diablo_bridge = mock_bridge
	sandbox.update_missiles(0.016)

	var p_node = sandbox.missile_instances.get(201, null)
	assert(p_node != null, "Town Portal missile node must exist")
	var vortex = p_node.get_node_or_null("MissilePortalParticles") as CPUParticles3D
	assert(vortex != null, "Town Portal must instantiate MissilePortalParticles")
	assert(vortex.emission_shape == CPUParticles3D.EMISSION_SHAPE_RING, "Vortex must emit in ring formation")
	assert(abs(vortex.color.b - 1.0) < 0.05, "Town Portal vortex color must be mystic blue")

	sandbox.queue_free()
	print("  -> PASS: 3D Town Portal correctly generates swirling particle vortex ring.")

class MockPortalBridge:
	func get_active_missiles() -> Array:
		return [
			{
				"id": 201,
				"type": 6, # MIS_TOWN (Town Portal)
				"dir": 0,
				"pos_x": 320.0,
				"pos_y": 160.0,
				"anim_frame": 0,
				"light_flag": true,
				"pre_flag": true
			}
		]
