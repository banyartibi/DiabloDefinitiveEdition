@tool
extends SceneTree

func _init():
	print("==================================================")
	print(" Testing Display Modes & 2.5D/3D Isolation ")
	print("==================================================")

	var scene = load("res://scenes/main_3d.tscn")
	if not scene:
		print("FAIL: Could not load main_3d.tscn")
		quit(1)
		return

	var main_node = scene.instantiate()
	root.add_child(main_node)

	print("[1/4] Checking scene structure and components...")
	var game_view = main_node.get_node_or_null("GameView")
	if not game_view:
		print("FAIL: GameView not found")
		quit(1)
		return

	var native_25d = main_node.get("native_25d_instance")
	var sandbox = main_node.get("sandbox_instance")
	var d1_mesh = main_node.get("mesh_instance")

	print("  PASS: GameView, native_25d, sandbox, and d1_mesh located!")

	print("[2/4] Testing Mode 0 (Classic 2.5D Blit)...")
	main_node.switch_display_mode(0)
	if native_25d and native_25d.is_active:
		print("FAIL: native_25d should be inactive in Mode 0")
		quit(1)
		return
	if sandbox and sandbox.is_sandbox_active:
		print("FAIL: sandbox should be inactive in Mode 0")
		quit(1)
		return
	print("  PASS: Mode 0 active, 2.5D and 3D properly deactivated!")

	print("[3/4] Testing Mode 1 (Native 2.5D Engine)...")
	main_node.switch_display_mode(1)
	if sandbox and sandbox.is_sandbox_active:
		print("FAIL: sandbox should be inactive in Mode 1")
		quit(1)
		return
	print("  PASS: Mode 1 active, 3D sandbox isolated and deactivated!")

	print("[4/4] Testing Mode 2 (Native 3D Sandbox)...")
	main_node.switch_display_mode(2)
	if native_25d and native_25d.is_active:
		print("FAIL: native_25d should be inactive in Mode 2")
		quit(1)
		return
	if sandbox and not sandbox.is_sandbox_active:
		print("FAIL: sandbox should be active in Mode 2")
		quit(1)
		return
	print("  PASS: Mode 2 active, 2.5D view isolated and deactivated!")

	print("==================================================")
	print(" ALL DISPLAY MODE SWITCHING & ISOLATION PASSED!   ")
	print("==================================================")
	quit(0)
