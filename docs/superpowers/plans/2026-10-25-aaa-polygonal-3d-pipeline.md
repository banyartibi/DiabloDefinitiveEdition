# AAA Dark Fantasy Polygonal 3D Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace placeholder/primitive toy assets with a professional, AAA-grade dark fantasy 3D polygonal asset and rendering pipeline in Godot 4.7 Forward+, preserving uncompromising Blizzard North grimdark atmosphere at all times.

**Architecture:** A dual-layer 3D engine in Godot 4.7: until a specific game element (wall, prop, monster, hero) possesses a verified, high-fidelity AAA sculpted 3D mesh with PBR materials, the engine gracefully renders the authentic 4K remastered Blizzard North asset with 3D Forward+ lighting and 144Hz camera. Low-poly toy boxes, cardboard slats, and untextured bathtubs are permanently banned. As genuine AAA 3D assets are integrated, they snap into the exact 1.06066m 45°-rotated isometric dungeon grid.

**Tech Stack:** Godot 4.7.2 Forward+ (Vulkan), GDExtension C++, GLTF/GLB PBR Meshes, `Skeleton3D` + `AnimationTree`, `OmniLight3D`, `GPUParticles3D`, `WorldEnvironment` (SSAO, SSIL, Volumetric Fog).

**Spec:** [diablo_3d_roadmap.md](file:///home/biti/.gemini/antigravity/brain/4427fff3-fdfb-47e3-b8be-42adea0050ce/diablo_3d_roadmap.md)

---

## Global Constraints

- **Zero Low-Poly Toy Boxes:** Under no circumstances may 1 KB flat extruded cubes (`wall_ns.glb`, `wall_ew.glb`) or generic toy bathtubs (`sarcophagus.glb`) be displayed in active gameplay.
- **Graceful High-Fidelity Fallback:** Any asset without an approved AAA 3D mesh MUST render its authentic 4K PBR remastered asset with 3D lighting, never an unfinished or ugly placeholder.
- **GEMINI.md Rule #1 & #2 Inviolability:** Town (Level 0) must remain strictly isolated from Cathedral PBR assets and Special CEL archways.
- **GEMINI.md Rule #4 Inviolability:** Unshaded/PBR sprite illumination must maintain balanced values matching torchlight ambient (no darkened character models).
- **GEMINI.md Rule #6 Inviolability:** All mutating shell commands must be evaluated with `evaluate_shell_command` via `laya-decision-engine`.

---

## Review Focus

1. Seamless tile junctions: Ensuring 3D walls meet at corners and T-junctions with zero gaps or light bleeding.
2. Normal map orientation: Verifying OpenGL Y-positive normal map tangents on all 3D meshes to avoid inverted shadow artifacts.
3. Grid alignment: Aligning all 3D mesh pivot origins to the exact $1.06066\text{ m} \times 1.06066\text{ m}$ isometric grid.
4. Scale parity: Ensuring character and monster 3D meshes match the heroic proportions of the classic Diablo sprites.
5. Performance: Maintaining 144+ FPS in Forward+ Vulkan using MultiMeshInstance3D batching and LODs.

---

## Implementation Tasks

### Task 1: Clean Architectural Decoupling & Quality Gating
- [x] Implement asset verification validator in `native_3d_sandbox.gd` (`is_mesh_aaa_certified(path: String) -> bool`).
- [x] Ensure `modular_3d_walls_enabled` and `modular_3d_props_enabled` remain safely gated behind strict quality certification.
- [x] Add unit test `test_3d_quality_gate.gd` verifying that uncertified low-poly test meshes are rejected in favor of 4K PBR scenery.
- [x] Run test suite to verify 100% pass rate.

### Task 2: AAA Gothic Architectural Kit Specification & Integration
- [x] Define the geometric specification file for Cathedral modular pieces ($1.06066\text{ m} \times 1.06066\text{ m}$, $2.4\text{ m}$ height, chamfered mortar edges, stone coping).
- [x] Construct high-detail PBR materials (Albedo, Normal, Roughness, AO) for Cathedral stone walls and archways.
- [x] Integrate first certified AAA Cathedral wall unit with seamless corner joining.
- [x] Verify zero visual seams, zero light leaks, and authentic gothic stone relief under Forward+ PointLight illumination.

### Task 3: AAA Gothic Interactive Props (Sarcophagus, Chest, Braziers)
- [x] Implement authentic carved stone gothic sarcophagus with Crusader knight effigy lid and skull reliefs.
- [x] Connect smooth sliding lid opening animation to DevilutionX `is_open` state.
- [x] Implement heavy dark iron-banded gothic chest with functional hinge opening.
- [x] Integrate dynamic `OmniLight3D` + embers to wall sconces and standing braziers.
- [x] Verify in headless test `test_aaa_props.gd`.

### Task 4: Forward+ Atmospheric Lighting & Volumetric Fog
- [x] Configure `WorldEnvironment` in `native_3d_sandbox.gd`: SSAO (Screen Space Ambient Occlusion), SSIL (Screen Space Indirect Lighting).
- [x] Add subtle volumetric fog (`FogVolume` / `volumetric_fog`) creating moody god-rays around torches and gothic archways.
- [x] Calibrate ambient light levels to preserve Diablo 1's dark, suffocating dungeon atmosphere.

### Task 5: AAA Warrior Hero 3D Skeletal Mesh & Animation Tree
- [x] Integrate high-detail rigged Warrior 3D model (plate mail, heraldic shield, broadsword).
- [x] Setup `AnimationTree` state machine in Godot 4.7 matching DevilutionX player actions (`IDLE`, `WALK`, `ATTACK`, `HIT`, `DEATH`).
- [x] Implement smooth 8-directional rotation and walking blend.
- [x] Verify combat responsiveness and click-to-move parity with DevilutionX logic.

### Task 6: First AAA Monster: The Skeleton Warrior
- [x] Integrate rigged 3D Skeleton Warrior with rusted scimitar and tattered tabard.
- [x] Map DevilutionX monster actions and HP% to 3D skeletal reactions.
- [x] Implement collapse-to-bones physics/animation on death.
- [x] Verify in `test_monster_3d.gd`.
