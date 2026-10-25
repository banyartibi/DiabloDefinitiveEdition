# Gothic Valley HUD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

This plan transforms the monolithic rectangular HUD into the modern, high-gothic ARPG "stepped valley" HUD requested by the user, matching `media_1792930015142_2ee8e217.png`.

---

## Architecture Overview

```
                +-----------------------------------------------------------+
                |                  OPEN BATTLEFIELD VALLEY                  |
                |               (Zero obstruction for character)             |
+---------------+                                                           +---------------+
|  LIFE GLOBE   |  +--------------------+                   +---------------+  |  MANA GLOBE   |
|  & GARGOYLE   |  |   LEFT 2x4 GRID    |                   | RIGHT 2x4 GRID|  |  & GARGOYLE   |
|  (Red slosh)  |  | Row 1: Skills 1..4 |   +-----------+   | Row 1: Belt1..4| |  (Blue slosh) |
|   (x: 0..165) |  | Row 2: Q, W, E, T  |   |  XP BAR   |   | Row 2: Belt5..8| |(x: 859..1024) |
|  (y: 15..205) |  | (x: 165..355)      |   | (x:350..674)  | (x: 669..859) |  | (y: 15..205)  |
+---------------+  +--------------------+   +-----------+   +---------------+  +---------------+
```

---

## File Changes

- **Created/Modified:**
  - `assets/hud/hud_gothic_valley_frame.png` - Sculpted gargoyles, carved moldings, cutouts for live liquid globes & XP groove.
  - `assets/hud/hud_gothic_valley_frame_2x.png` - 2048x430 super-sampled version for 1440p/4K displays.
  - `assets/hud/hud_valley_xp_fill.png` & `_hd.png` - Seamless radiant electric violet XP fill texture.
  - `godot_d1_3d/scenes/hud/d1de_hud.tscn` - Scene tree reorganized to stepped valley geometry.
  - `godot_d1_3d/scenes/hud/d1de_hud.gd` - Node bindings, styling, and texture loader.
  - `godot_d1_3d/test_hud_hierarchy.gd` - Hierarchy validation test (PASS).
  - `godot_d1_3d/test_hud_belt_and_bindings.gd` - Input & belt test (PASS).

---

## Tasks

- [x] **Task 1: Generate & Extract High-Resolution Gothic Valley Assets**
  - [x] Write Python extractor `tools/extract_gothic_valley_assets.py` to extract and alpha-mask:
    - Left Gargoyle + Bezel (aperture center at (105, 125), radius 48.5).
    - Right Gargoyle + Bezel (aperture center at (915, 125), radius 48.5).
    - Left and Right Action Box frames (190x145).
    - Center XP Frame with apex brooch and gold "XP" engraving (324x75).
    - Violet glow XP fill texture.
    - Crisp slot frames.
  - [x] Run extraction and verify clean alpha margins and dimensions.

- [x] **Task 2: Restructure `d1de_hud.tscn` to Stepped Valley Hierarchy**
  - [x] Remove monolithic rectangular background and tall center "LV 50" pillar.
  - [x] Position `LifeGlobe` (`ShaderMaterial_life`) at (55, 75) size (100, 100), with `LifeFrame` on top.
  - [x] Position `ManaGlobe` (`ShaderMaterial_mana`) at (865, 75) size (100, 100), with `ManaFrame` on top.
  - [x] Position `LeftGrid` at (165, 46, 188, 142) with 2x4 slots:
    - Row 1: `SkillSlot1`..`SkillSlot4`
    - Row 2: `HealthPotionSlot` (Q), `ManaPotionSlot` (W), `RejuvPotionSlot` (E), `TownPortalSlot` (T)
  - [x] Position `RightGrid` at (669, 46, 188, 142) with 2x4 slots:
    - Row 1: `BeltSlot0`..`BeltSlot3`
    - Row 2: `BeltSlot4`..`BeltSlot7`
  - [x] Position `CenterValley` / `XpBar` at (374, 159, 276, 16) with apex crest and gold "XP".
  - [x] Position clean HP / Mana labels.

- [x] **Task 3: Refine `d1de_hud.gd` & Input Wiring**
  - [x] Update node paths to ensure all elements (`SkillSlots`, `BeltSlots`, `Potions`, `Globes`, `XPBar`) are mapped.
  - [x] Maintain `apply_optimistic_item_delta`, hover tooltips, and level up notifications.
  - [x] Ensure full keyboard hotkey support (`1`..`4`, `Q`, `W`, `E`, `T`, `F1`..`F8`).

- [x] **Task 4: Run Verification Suite**
  - [x] Execute `test_hud_hierarchy.gd` -> PASS.
  - [x] Execute `test_hud_belt_and_bindings.gd` -> PASS.
  - [x] Execute `test_logic_authority.gd` -> PASS.
  - [x] Render visual verification probe and save snapshot to artifact dir -> PASS.
