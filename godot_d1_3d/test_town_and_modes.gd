@tool
extends SceneTree

func _init():
	print("--- Testing Town 3D Architecture, Dungeon Modular Kit, and Mode Switching ---")

	# Mock bridge
	var bridge_script = GDScript.new()
	bridge_script.source_code = """
extends RefCounted
var cur_level: int = 0 # Town initially
var sol = PackedByteArray()
var grid = PackedInt32Array()
var light = PackedByteArray()

func _init():
	sol.resize(112 * 112)
	sol.fill(1)
	grid.resize(112 * 112)
	grid.fill(2) # Grass path
	light.resize(112 * 112)
	light.fill(0)

	# Place some town scenery at (25, 25): house wall (pid=150), fence (pid=168)
	sol[25 * 112 + 25] = 2
	grid[25 * 112 + 25] = 150 # Scenery piece (th > floor_h)
	sol[25 * 112 + 26] = 2
	grid[25 * 112 + 26] = 168 # Fence piece (th > floor_h)

func get_current_level(): return cur_level
func is_level_loading(): return false
func is_game_running(): return true
func get_dungeon_solidity_grid(): return sol
func get_dungeon_grid(): return grid
func get_dungeon_light_grid(): return light
func get_dungeon_flags_grid(): return PackedByteArray()
func get_dungeon_trans_grid(): return PackedByteArray()
func get_dungeon_trans_mask(): return PackedByteArray()
func get_trans_list(): return PackedByteArray()
func get_dungeon_special_grid(): return PackedInt32Array()
func get_active_monsters_data(): return []
func get_active_objects(): return []
func get_active_lights(): return []
func get_active_items(): return []
func get_player_continuous_pos(): return {"pos_x": 25.0, "pos_y": 25.0, "dir": 0, "anim_frame": 0}
func get_player_sprite_data(): return {"width": 96, "height": 96, "frame": 0, "rgba": PackedByteArray()}

func get_dungeon_piece_texture(pid):
	# Return a 64x128 image for scenery pieces (pid >= 100), 64x32 for floor pieces
	var tw = 64
	var th = 128 if pid >= 100 else 32
	var img = Image.create(tw, th, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.5, 0.2, 1.0))
	return ImageTexture.create_from_image(img)
"""
	var err = bridge_script.reload()
	if err != OK:
		print("Failed to reload bridge script: ", err)
		quit(1)
		return
	var bridge = bridge_script.new()
	var sandbox_scene = load("res://scenes/sandbox/native_3d_sandbox.tscn")
	var sandbox = sandbox_scene.instantiate()
	sandbox.diablo_bridge = bridge
	root.add_child(sandbox)

	print("\n[Step 1: Test Town Mode (Level 0)]")
	sandbox.activate()

	# Verify: In Town, zero brown monolithic boxes extruded
	var wall_count = sandbox.wall_mmi.multimesh.instance_count
	var wall_ns_count = sandbox.wall_ns_mmi.multimesh.instance_count
	var wall_ew_count = sandbox.wall_ew_mmi.multimesh.instance_count
	print("  Town Wall instances count: %d, NS: %d, EW: %d" % [wall_count, wall_ns_count, wall_ew_count])
	assert(wall_count == 0 and wall_ns_count == 0 and wall_ew_count == 0, "ERROR: Town must NOT contain extruded wall boxes!")
	print("  [PASS] Zero extruded wall boxes in Town!")

	# Verify: Town Scenery billboard sprites created and have BILLBOARD_DISABLED (uniform view-plane alignment)
	var scenery_count = sandbox.town_scenery_nodes.size()
	print("  Town Scenery sprites created: %d" % scenery_count)
	assert(scenery_count >= 2, "ERROR: Town scenery (house/fence) must be instantiated as 3D billboard sprites!")
	for spr in sandbox.town_scenery_nodes.values():
		assert(spr.billboard == BaseMaterial3D.BILLBOARD_DISABLED, "ERROR: Town scenery must use BILLBOARD_DISABLED to eliminate domino slicing!")
	print("  [PASS] Town houses, trees, and fences rendered as unified view-plane 3D scenery!")

	# Verify: Orbit camera yaw rotates all scenery sprites in unison
	sandbox.camera_yaw = 45.0
	sandbox.update_camera_transform()
	for spr in sandbox.town_scenery_nodes.values():
		assert(is_equal_approx(spr.rotation.y, deg_to_rad(45.0)), "ERROR: Scenery sprite should match camera yaw uniformly!")
	print("  [PASS] Orbiting rotates all town scenery uniformly in parallel!")

	# Verify: TownBaseGroundPlane exists and is visible in Town
	assert(sandbox.town_base_ground != null, "ERROR: TownBaseGroundPlane must exist!")
	assert(sandbox.town_base_ground.visible, "ERROR: TownBaseGroundPlane must be visible in Level 0!")
	print("  [PASS] TownBaseGroundPlane active (eliminating sky-blue void holes)!")

	# Verify: Diamond floor populated
	assert(sandbox.floor_mmis.size() > 0, "ERROR: Town floor multimeshes must be populated!")
	print("  [PASS] Town diamond floor active with %d unique pieces!" % sandbox.floor_mmis.size())

	print("\n[Step 2: Transition from Town to Cathedral (Level 1)]")
	bridge.cur_level = 1
	# In Cathedral, make (25, 25) a solid wall
	bridge.sol[25 * 112 + 25] = 2
	bridge.grid[25 * 112 + 25] = 168
	sandbox.rebuild_dungeon_if_needed(true)

	assert(not sandbox.town_base_ground.visible, "ERROR: TownBaseGroundPlane must be hidden in dungeons!")
	var d_wall_count = sandbox.wall_mmi.multimesh.instance_count + sandbox.wall_ns_mmi.multimesh.instance_count + sandbox.wall_ew_mmi.multimesh.instance_count
	assert(d_wall_count == 0, "ERROR: Modular wall cubes must remain 0 (replaced by unified billboard scenery)!")
	assert(sandbox.town_scenery_nodes.size() > 0, "ERROR: Unified billboard scenery sprites must be built in Cathedral!")
	print("  [PASS] Clean transition to Cathedral unified billboard scenery (modular cubes disabled)!")

	print("\n[Step 3: Test Mode Switching Deactivation]")
	sandbox.deactivate()
	assert(not sandbox.is_sandbox_active, "ERROR: Sandbox should be inactive after deactivate()!")
	assert(not sandbox.visible, "ERROR: Sandbox should be hidden after deactivate()!")
	assert(not sandbox.town_base_ground.visible, "ERROR: TownBaseGroundPlane must be hidden when deactivated!")
	print("  [PASS] Clean deactivation for mode switching!")

	print("\n[Step 4: Test Native 2.5D View Fast-Path Reactivation]")
	var view_script = load("res://scripts/native_25d_view.gd")
	var view_25d = view_script.new()
	view_25d.diablo_bridge = bridge
	root.add_child(view_25d)
	view_25d.activate()
	assert(view_25d.is_active, "ERROR: Native 2.5D view must be active!")
	var initial_tile_count = view_25d.tile_sprites.size()
	print("  Initial 2.5D tile sprites: %d" % initial_tile_count)
	assert(initial_tile_count > 0, "ERROR: Native 2.5D view must build tiles on first activation!")

	# Simulate deactivation and fast-path reactivation (mode switch 2.5D -> Blit -> 2.5D)
	view_25d.deactivate()
	assert(not view_25d.is_active, "ERROR: Native 2.5D view must be deactivated!")
	view_25d.activate()
	assert(view_25d.is_active, "ERROR: Native 2.5D view must be reactivated!")
	assert(view_25d.tile_sprites.size() == initial_tile_count, "ERROR: Fast-path reactivation must preserve tile sprites without re-wiping!")
	print("  [PASS] Fast-path reactivation preserved %d tiles instantly without wiping textures!" % view_25d.tile_sprites.size())

	view_25d.queue_free()
	sandbox.queue_free()
	print("\n--- All Town, Scenery, Ground Plane & Mode Switch Tests Passed 100%! ---")
	quit(0)
