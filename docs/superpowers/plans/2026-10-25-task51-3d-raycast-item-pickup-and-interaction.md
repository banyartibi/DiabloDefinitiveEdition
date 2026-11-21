# Task 5.1: 3D Raycast Ground Pickup & World Interaction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement 100% native Godot 4.7 3D raycast picking and interaction for ground loot pickup, doors, chests, sarcophagi, and monster targeting, eliminating 2D isometric coordinate guessing and providing responsive ARPG cursor/hover feedback.

**Architecture:** 
1. **DevilutionX Engine Bridge:** Expose explicit action triggers (`InteractWithItem`, `InteractWithObject`, `InteractWithMonster`, `WalkToTile`) via `D1BridgeActionType` and `DiabloBridge` GDExtension, executing directly on the engine thread with `NetSendCmdLocParam1(CMD_GOTOAGETITEM)`, `NetSendCmdLoc(CMD_OPOBJXY)`, `NetSendCmdParam1(CMD_ATTACKID)`, and `NetSendCmdLoc(CMD_WALKXY)`.
2. **3D Raycast Hit Testing in Godot:** In `native_3d_sandbox.gd`, use camera projection and screen-space/3D proximity to detect ground items (`item_instances`), interactive props (`prop_instances`), monsters (`monster_instances`), and ground tiles with pixel-perfect accuracy regardless of 3D camera yaw, pitch, or zoom.
3. **Responsive Visual & Hover Feedback:** Dynamic cursor hover detection updating item label scale and glow, prop highlights, top-center HUD enemy health bar on monster hover, and color-coded 3D waypoint rings (Gold for loot, Cyan for objects/doors, Crimson for monsters, Yellow for ground movement).

**Tech Stack:** Godot 4.7 (Forward+ Vulkan, GDScript), C++17 (DevilutionX, GDExtension), Ninja / CMake.

**Spec:** `docs/superpowers/specs/2026-10-25-aaa-cathedral-kit-spec.md` & `diablo_3d_roadmap.md` (Task 5.1).

## Global Constraints
- Preserve Town (Level 0) isolation and PBR rules (GEMINI.md Rule #1).
- Never introduce placeholder primitives (GEMINI.md Rule #3).
- Forward+ and gamma/lighting invariants must be preserved (GEMINI.md Rule #4).
- Safe command execution: Mutating shell commands and builds must be checked with `evaluate_shell_command` on `laya-decision-engine` (GEMINI.md Rule #6).
- 100% backward compatibility: Fall back cleanly to `send_click_to_tile` if running on older bridges or mock environments.

## Review Focus
1. **Item Label vs Sprite Click:** Clicking either the 3D item sprite or its floating 3D label must reliably pick up the item.
2. **Camera Orbit Parity:** Raycasting and picking must remain 100% accurate when the camera orbits at any yaw (0°–360°), tilt (25°–75°), or distance.
3. **Door Interaction:** Doors must be selectable both by their 3D door leaf mesh and their gateway tile coordinates.
4. **Thread Safety:** C++ bridge commands dispatched from Godot must be queued through `g_BridgeJobs` and executed on the DevilutionX thread without data races.
5. **Headless & Mock Safety:** `native_3d_sandbox.gd` must run cleanly without errors even when `diablo_bridge` is a GDScript mock in unit tests.

---

## Tasks

### Task 1: C++ Direct Engine Actions in `render_bridge` and `diablo_bridge`

**Files:**
- Modify: `DevilutionX/Source/engine/render_bridge.hpp:50-70, 270-285`
- Modify: `DevilutionX/Source/engine/render_bridge.cpp:480-550, 710-740`
- Modify: `godot_d1_extension/src/diablo_bridge.h:300-315`
- Modify: `godot_d1_extension/src/diablo_bridge.cpp:250-265, 1030-1060`
- Test: `godot_d1_3d/test_display_modes.gd`

- [x] **Step 1.1:** Add `InteractWithItem`, `InteractWithObject`, `InteractWithMonster`, and `WalkToTile` enum values to `D1BridgeActionType` in `render_bridge.hpp`.
- [x] **Step 1.2:** Implement job processing cases in `render_bridge.cpp`:
  - `InteractWithItem`: invokes `NetSendCmdLocParam1(true, invflag ? CMD_GOTOGETITEM : CMD_GOTOAGETITEM, pos, itemIdx)`
  - `InteractWithObject`: invokes `NetSendCmdLoc(MyPlayerId, true, pcurs == CURSOR_DISARM ? CMD_DISARMXY : CMD_OPOBJXY, pos)`
  - `InteractWithMonster`: invokes `NetSendCmdParam1(true, CMD_ATTACKID, monsterId)` (or ranged variant)
  - `WalkToTile`: invokes `NetSendCmdLoc(MyPlayerId, true, CMD_WALKXY, pos)`
- [x] **Step 1.3:** Add bridge sender functions in `render_bridge.cpp`:
  - `void BridgeInteractWithItem(int itemId, int tileX, int tileY);`
  - `void BridgeInteractWithObject(int objectId, int tileX, int tileY);`
  - `void BridgeInteractWithMonster(int monsterId);`
  - `void BridgeWalkToTile(int tileX, int tileY);`
- [x] **Step 1.4:** Expose and bind `interact_with_item`, `interact_with_object`, `interact_with_monster`, and `walk_to_tile` in `DiabloBridge` (`diablo_bridge.h` and `diablo_bridge.cpp`).
- [x] **Step 1.5:** Rebuild DevilutionX static library and GDExtension shared library using Ninja, triaging any compiler warnings.
- [x] **Step 1.6:** Run `test_display_modes.gd` to verify clean load and execution.

---

### Task 2: 3D Raycast & Entity Hit Testing in `native_3d_sandbox.gd`

**Files:**
- Modify: `godot_d1_3d/scripts/native_3d_sandbox.gd:2820-2960`
- Test: `godot_d1_3d/test_task51_3d_interaction.gd`

- [x] **Step 2.1:** Implement `find_entity_under_ray(mouse_pos: Vector2) -> Dictionary` in `native_3d_sandbox.gd`.
- [x] **Step 2.2:** Add item hit detection:
  - Check distance between `mouse_pos` and screen projection (`camera.unproject_position`) of each active item in `item_instances` (threshold ~32px).
  - Also check 3D ray proximity to `item.position + Vector3(0, 0.35, 0)` with radius 0.65m.
- [x] **Step 2.3:** Add prop & door hit detection:
  - Check screen projection and 3D ray proximity to `prop.position + Vector3(0, 0.9, 0)` with radius 0.85m.
  - Check door tile hit if ray intersects the ground tile of a door.
- [x] **Step 2.4:** Add monster hit detection:
  - Check ray against monster cylinder (radius 0.55m, height 1.8m) and screen projection proximity (~36px).
- [x] **Step 2.5:** Add ground plane fallback:
  - Intersect ray with `Plane(Vector3.UP, 0.0)` returning target tile `(tx, ty)`.

---

### Task 3: Interactive Visual Feedback & Hover System

**Files:**
- Modify: `godot_d1_3d/scripts/native_3d_sandbox.gd:2460-2476, 2820-2960`
- Modify: `godot_d1_3d/scenes/hud/d1de_hud.gd:74-88, 1680-1745`
- Test: `godot_d1_3d/test_task51_3d_interaction.gd`

- [x] **Step 3.1:** Implement real-time hover tracking in `native_3d_sandbox.gd`:
  - Track `hovered_entity`, `last_hovered_item`.
- [x] **Step 3.2:** Add item hover visual response:
  - When hovering an item, scale its `ItemLabel` by 1.18x and brighten outline modulate.
- [x] **Step 3.3:** Add monster hover HUD response:
  - When hovering a monster in 3D sandbox, notify HUD `enemy_health_bar` with monster's name, HP, and max HP.
- [x] **Step 3.4:** Add color-coded 3D waypoint ring feedback:
  - Ground move: Yellow `Color(0.95, 0.80, 0.20, 0.85)`
  - Item pickup: Amber/Gold `Color(1.0, 0.85, 0.25, 0.95)`
  - Object/Door: Cyan/Azure `Color(0.20, 0.80, 1.0, 0.95)`
  - Monster attack: Crimson `Color(1.0, 0.22, 0.22, 0.95)`

---

### Task 4: Complete Interaction Execution Pipeline

**Files:**
- Modify: `godot_d1_3d/scripts/native_3d_sandbox.gd:2910-2958`
- Test: `godot_d1_3d/test_task51_3d_interaction.gd`

- [x] **Step 4.1:** In `native_3d_sandbox.gd:handle_input`:
  - When MOUSE_BUTTON_LEFT is pressed, evaluate `find_entity_under_ray(mouse_pos)`.
  - If `type == "ITEM"`: call `diablo_bridge.interact_with_item(hit.id, hit.tile.x, hit.tile.y)`, spawn gold ring.
  - If `type == "OBJECT"`: call `diablo_bridge.interact_with_object(hit.id, hit.tile.x, hit.tile.y)`, spawn cyan ring.
  - If `type == "MONSTER"`: call `diablo_bridge.interact_with_monster(hit.id)`, spawn crimson ring.
  - If `type == "GROUND"`: call `diablo_bridge.walk_to_tile(hit.tile.x, hit.tile.y)` (or `send_click_to_tile`), spawn yellow ring.
- [x] **Step 4.2:** Provide fallback support if running on older bridges (falls back gracefully to `send_click_to_tile`).

---

### Task 5: Automated Verification Test Suite & Quality Gate

**Files:**
- Create: `godot_d1_3d/test_task51_3d_interaction.gd`
- Test: All suites (`test_task51_3d_interaction.gd`, `test_3d_doors_torches_items.gd`, `test_display_modes.gd`, `test_task53_audio_engine.gd`)

- [x] **Step 5.1:** Write `godot_d1_3d/test_task51_3d_interaction.gd` covering:
  - Item raycast picking by sprite and by label.
  - Prop / Door raycast picking.
  - Monster raycast picking and HUD health bar notification.
  - Ground plane raycast navigation.
  - Bridge method dispatch verification with exact parameter checking.
- [x] **Step 5.2:** Run `test_task51_3d_interaction.gd` headlessly and verify 100% pass.
- [x] **Step 5.3:** Run all existing test suites to prevent any regression.
- [x] **Step 5.4:** Commit clean progress to Git.
