# All 4 Themes Unified 3D Architectural Kit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Simultaneously provide complete, certified, AAA-grade 3D polygonal architectural kits across all 4 dungeon themes (Cathedral, Catacombs, Caves, Hell) in Godot 4.7 Forward+, enforcing the "everything together" unified visual principle with zero patchy or mismatched graphics.

**Architecture:** A comprehensive procedural geometry generator (`build_aaa_all_themes_kit.gd`) builds geometrically rigorous, subterranean-skirted, PBR-mapped ArrayMeshes for all 4 themes adhering to the $1.06066\text{ m}$ isometric grid. `native_3d_sandbox.gd` integrates and activates these kits across all dungeon levels, while the AAA Quality Gate certifies and validates that no low-poly toy boxes or untextured assets ever reach gameplay.

**Tech Stack:** Godot 4.7.2 Forward+ (Vulkan), GDScript `SurfaceTool`, `ArrayMesh`, `StandardMaterial3D`, 4K PBR Texture Maps, `MultiMeshInstance3D`.

**Spec:** [diablo_3d_roadmap.md](file:///home/biti/.gemini/antigravity/brain/4427fff3-fdfb-47e3-b8be-42adea0050ce/diablo_3d_roadmap.md), [2026-10-25-aaa-cathedral-kit-spec.md](file:///home/biti/antigravity/magical-bell/docs/superpowers/specs/2026-10-25-aaa-cathedral-kit-spec.md)

---

## Global Constraints

- **Unified Progression ("Mindent egyszerre"):** All 4 dungeon themes (Cathedral L1..4, Catacombs L5..8, Caves L9..12, Hell L13..16) must receive certified AAA 3D polygonal kits simultaneously. No single theme may be left behind.
- **Zero Low-Poly Toy Boxes:** 1 KB extruded toy cubes (`wall_ns.glb`, `wall_ew.glb`) and generic placeholders are permanently banned from active gameplay.
- **Strict Mathematical Grid Parity:** Every wall segment must span exactly $L = 1.06066017\text{ m}$, with height $H = 2.40\text{ m}$, wall thickness $T = 0.40\text{ m}$, and subterranean light-bleed skirt $\text{SKIRT\_Y} \le -0.05\text{ m}$.
- **GEMINI.md Invariants:** Town (L0) remains 100% isolated from dungeon PBR/archway meshes. Gamma/Brightness and unshaded actor lighting compensations remain intact.
- **Forward+ PBR Material Channels:** Every certified 3D mesh surface must carry verified Albedo, OpenGL normal (+Y up), and Roughness textures.

---

## Review Focus

1. **Junction Gaps:** Walls, corners, pillars, and archways must snap together with $0.00\text{ mm}$ gap across 45°-rotated MultiMesh transforms.
2. **Light Bleeding:** OmniLight3D torches at floor level must not leak light under walls into adjacent rooms due to subterranean skirt overlap.
3. **PBR Normal Map Orientation:** Normal vectors must point outward with valid OpenGL tangents across all sub-faces.
4. **Theme Material Harmony:** Catacombs walls match crypt stone, Caves rock walls match the reddish-brown cavern floors, Hell basalt matches volcanic pavers.
5. **Quality Gate Pass Rate:** Automated test suite `test_task_all_themes_3d_kit.gd` and `test_3d_quality_gate.gd` must pass 100%.

---

## Implementation Tasks

### Task 1: Complete 4-Theme Procedural AAA Geometry Generator
**Files:**
- Create: `godot_d1_3d/scripts/tools/build_aaa_all_themes_kit.gd`
- Output: `assets/models/aaa/cathedral/*.res`, `assets/models/aaa/catacombs/*.res`, `assets/models/aaa/caves/*.res`, `assets/models/aaa/hell/*.res`
- Test: Run headless generator and verify file generation

- [ ] Write `build_aaa_all_themes_kit.gd` extending SceneTree.
- [ ] Implement `build_cathedral_kit()` (Ashlar stone with tracery, pointed arch, octagonal pillar).
- [ ] Implement `build_catacombs_kit()` (Aged crypt masonry, burial niches, Romanesque arch, square pillar).
- [ ] Implement `build_caves_kit()` (Natural jagged rock cliff, organic rock shelves, stalagmite spire pillar, cavern mouth arch).
- [ ] Implement `build_hell_kit()` (Scorched volcanic basalt slabs, demonic iron bevels, obsidian monolithic pillar, horned arch).
- [ ] Enforce subterranean skirts ($\text{SKIRT\_Y} = -0.08\text{ m}$) and exact dimensions ($1.06066\text{ m} \times 2.40\text{ m} \times 0.40\text{ m}$) on all pieces.
- [ ] Apply verified 4K PBR materials (Albedo, Normal, Roughness) per theme.
- [ ] Run generator via `tools/godot4/godot4 --headless --path godot_d1_3d -s res://scripts/tools/build_aaa_all_themes_kit.gd`.

---

### Task 2: Sandbox Modular Dungeon Assets Integration
**Files:**
- Modify: `godot_d1_3d/scripts/native_3d_sandbox.gd:1227-1295`
- Test: Headless asset loading verification

- [ ] In `update_modular_dungeon_assets(level_idx)`:
  - Add theme routing to load `assets/models/aaa/<theme>/wall_ns_<theme>.res`, `wall_ew_<theme>.res`, `wall_corner_<theme>.res`, `pillar_<theme>.res`, and `arch_door_<theme>.res`.
  - When all certified theme meshes exist, call `set_theme_aaa_certified(theme, true)`.
  - Ensure all 4 themes (Cathedral, Catacombs, Caves, Hell) are certified and load their dedicated AAA geometry.
- [ ] In `can_use_modular_3d_walls(theme)`:
  - Maintain Quality Gate protection while allowing all 4 certified dark fantasy themes.

---

### Task 3: Quality Gate Refinement & Multi-Theme Verification Suite
**Files:**
- Modify: `godot_d1_3d/test_3d_quality_gate.gd`
- Create: `godot_d1_3d/test_task_all_themes_3d_kit.gd`

- [ ] Update `test_3d_quality_gate.gd` to test architectural rejection of uncertified test models without falsely banning completed themes.
- [ ] Write `test_task_all_themes_3d_kit.gd` to verify:
  - All 4 themes load certified AAA meshes (5 pieces each = 20 meshes total).
  - Geometry invariant checks: width = 1.06066m, height >= 2.40m, skirt <= -0.05m.
  - PBR channels: Albedo, Normal (enabled), Roughness on all 20 meshes.
  - MultiMesh generation in dungeon levels 1 (Cathedral), 5 (Catacombs), 9 (Caves), and 13 (Hell).
- [ ] Run tests and verify 100% PASS.

---

### Task 4: Visual Polish & Seam Verification Across All Themes
**Files:**
- Test: `test_task_seams_and_foundations.gd`
- Test: `test_task_shadows_and_cave_enclosure.gd`

- [ ] Run existing seam and foundation tests to ensure zero regressions across themes.
- [ ] Confirm no light bleeding or clipping between modular walls and floors.
