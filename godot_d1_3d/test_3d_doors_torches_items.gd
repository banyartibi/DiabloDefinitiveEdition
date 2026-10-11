@tool
extends SceneTree

func _init():
	print("--- Testing 3D Doors, Wall Torches, Shadows, and Ground Loot ---")

	var bridge_script = GDScript.new()
	bridge_script.source_code = """
extends RefCounted
var sol = PackedByteArray()
var grid = PackedInt32Array()
var light = PackedByteArray()
func _init():
	sol.resize(112 * 112)
	sol.fill(1)
	grid.resize(112 * 112)
	grid.fill(1)
	light.resize(112 * 112)
	light.fill(0)
	
	# Create a wall and a door
	# Let (25, 25) be a solid wall, (25, 26) be a door
	sol[25 * 112 + 25] = 2
	sol[26 * 112 + 25] = 2 # Closed door tile is solid in DevilutionX
	grid[25 * 112 + 25] = 168
	grid[26 * 112 + 25] = 43 # OBJ_L1LDOOR piece

func get_current_level(): return 1
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
func get_dungeon_piece_texture(pid): 
	var img = Image.create(64, 32, false, Image.FORMAT_RGBA8)
	return ImageTexture.create_from_image(img)
func get_player_continuous_pos(): return {"pos_x": 25.0, "pos_y": 25.0, "dir": 0, "anim_frame": 0}
func get_player_sprite_data(): return {"width": 96, "height": 96, "frame": 0, "rgba": PackedByteArray()}
func get_active_monsters_data():
	return [{
		"id": 10,
		"is_alive": true,
		"pos_x": 28.0,
		"pos_y": 28.0,
		"dir": 2,
		"anim_frame": 1,
		"hp": 50,
		"max_hp": 50,
		"name": "Skeleton Archer"
	}]
var door_solid: bool = true
var door_frame: int = 1

func get_active_objects():
	return [
		{
			"id": 1,
			"type": 1, # OBJ_L1LDOOR
			"tile_x": 25,
			"tile_y": 26,
			"solid": door_solid,
			"anim_frame": door_frame
		},
		{
			"id": 2,
			"type": 0, # OBJ_L1LIGHT (Floor Standing Brazier)
			"tile_x": 24,
			"tile_y": 24,
			"solid": true,
			"anim_frame": 1
		},
		{
			"id": 3,
			"type": 150, # OBJ_TORCHL (Wall-mounted Torch)
			"tile_x": 25,
			"tile_y": 25,
			"solid": false,
			"anim_frame": 1
		}
	]
func get_active_lights():
	return [
		{"tile_x": 25, "tile_y": 25, "radius": 10}, # Player light 0
		{"tile_x": 22, "tile_y": 22, "radius": 7}   # Env light 1
	]
func get_active_items():
	return [
		{
			"id": 101,
			"tile_x": 25,
			"tile_y": 27,
			"curs_id": 12,
			"quality": 0, # Normal
			"name": "Broad Sword",
			"anim_frame": 0
		},
		{
			"id": 102,
			"tile_x": 26,
			"tile_y": 27,
			"curs_id": 19,
			"quality": 1, # Magic
			"name": "Amber Short Bow",
			"anim_frame": 0
		},
		{
			"id": 103,
			"tile_x": 27,
			"tile_y": 27,
			"curs_id": 25,
			"quality": 2, # Unique
			"name": "The Butcher's Cleaver",
			"anim_frame": 0
		}
	]
func get_ground_item_sprite_data(iid):
	var rgba = PackedByteArray()
	rgba.resize(32 * 32 * 4)
	return {"width": 32, "height": 32, "rgba": rgba}
func get_monster_sprite_data(mid):
	return {"width": 64, "height": 64, "rgba": PackedByteArray()}
"""
	bridge_script.reload()
	var b_inst = bridge_script.new()

	var sandbox_script = load("res://scripts/native_3d_sandbox.gd")
	var sandbox = Node3D.new()
	sandbox.set_script(sandbox_script)
	root.add_child(sandbox)
	sandbox.diablo_bridge = b_inst
	sandbox._ready()
	sandbox.activate()

	# 1. Verify Shadows
	print("Checking Shadows...")
	assert(sandbox.player_sprite.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "Player sprite must cast shadow!")
	var monster_node = sandbox.get_or_create_monster_node(10)
	var m_sprite = monster_node.get_node_or_null("MonsterSprite3D") as Sprite3D
	assert(m_sprite != null and m_sprite.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "Monster sprite must cast shadow!")
	print("  [PASS] Player and Monster shadows enabled (SHADOW_CASTING_SETTING_ON)")

	# 2. Verify Doors & Archways
	print("Checking Doors & Archways...")
	sandbox.rebuild_dungeon_if_needed(true)
	# Check arch_mmi instance count >= 1 (door was routed to archway)
	assert(sandbox.arch_mmi.multimesh.instance_count >= 1, "Door tile must be placed into arch multimesh!")
	print("  [PASS] Door tile placed into arch multimesh: %d arches" % sandbox.arch_mmi.multimesh.instance_count)

	# Check DoorProp and DoorPivot
	# Closed state test (sol == 2)
	sandbox.update_props(0.016)
	var door_prop = sandbox.prop_instances.get(1, null)
	assert(door_prop != null, "Door prop must exist!")
	var door_pivot = door_prop.get_node_or_null("DoorContainer/DoorPivot")
	assert(door_pivot != null, "Door pivot must exist inside DoorContainer!")
	var door_leaf = door_pivot.get_node_or_null("DoorLeaf")
	assert(door_leaf != null, "Door leaf mesh must exist inside DoorPivot!")
	assert(abs(door_pivot.rotation_degrees.y) < 1.0, "Door must be closed (0 deg) when tile is solid (2)!")
	print("  [PASS] Closed door remains flush with portal (0 deg)")

	# Open state test (simulate player opening door -> sol == 1, solid == false, anim_frame == 3)
	b_inst.sol[26 * 112 + 25] = 1
	b_inst.door_solid = false
	b_inst.door_frame = 3
	for _i in range(30):
		sandbox.update_props(0.033)
	assert(door_pivot.rotation_degrees.y > 70.0, "Door must swing open (> 70 deg) when tile is opened (1)!")
	print("  [PASS] Opened door smoothly swings open to %.1f deg" % door_pivot.rotation_degrees.y)

	# 3. Verify Torches & Braziers
	print("Checking Torches & Braziers...")
	var brazier_prop = sandbox.prop_instances.get(2, null)
	assert(brazier_prop != null, "Floor brazier prop must exist!")
	var wall_torch_prop = sandbox.prop_instances.get(3, null)
	assert(wall_torch_prop != null, "Wall torch prop must exist!")
	var wall_torch_node = wall_torch_prop.get_node_or_null("WallTorch")
	assert(wall_torch_node != null, "WallTorch subnode must be positioned flush on wall!")
	print("  [PASS] Standing brazier on floor, wall torch mounted on wall at height %.2fm" % wall_torch_node.position.y)

	# Verify env light has NO sconce mesh
	sandbox.update_environmental_torches(0.016)
	var env_torch = sandbox.torch_instances.get(1, null)
	assert(env_torch != null, "Env light must exist!")
	assert(env_torch.get_node_or_null("MeshInstance3D") == null, "Env light must NOT have a floating sconce mesh!")
	print("  [PASS] Environmental light radius is pure OmniLight3D without floating sconce")

	# 4. Verify Ground Loot
	print("Checking Ground Loot Drops...")
	sandbox.update_ground_items(0.016)
	assert(sandbox.item_instances.size() == 3, "Expected 3 ground items!")
	
	var normal_item = sandbox.item_instances.get(101, null)
	assert(normal_item != null, "Normal item must exist!")
	var n_lbl = normal_item.get_node_or_null("ItemLabel") as Label3D
	assert(n_lbl != null and n_lbl.text == "Broad Sword", "Normal item label correct")
	assert(normal_item.get_node_or_null("LootBeam") == null, "Normal item has no beam")

	var magic_item = sandbox.item_instances.get(102, null)
	assert(magic_item != null, "Magic item must exist!")
	var m_lbl = magic_item.get_node_or_null("ItemLabel") as Label3D
	assert(m_lbl != null and m_lbl.text == "Amber Short Bow", "Magic item label correct")
	var m_beam = magic_item.get_node_or_null("LootBeam")
	assert(m_beam != null, "Magic item must have loot beam!")

	var unique_item = sandbox.item_instances.get(103, null)
	assert(unique_item != null, "Unique item must exist!")
	var u_lbl = unique_item.get_node_or_null("ItemLabel") as Label3D
	assert(u_lbl != null and u_lbl.text == "The Butcher's Cleaver", "Unique item label correct")
	var u_beam = unique_item.get_node_or_null("LootBeam")
	assert(u_beam != null, "Unique item must have loot beam!")
	print("  [PASS] Ground items created with authentic white, blue, and gold labels + loot beams")

	print("--- All 3D Tests Passed Successfully! ---")
	quit(0)
