# Modern D3/D4 Gothic HUD Redesign & 2x4 Belt Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform the bottom HUD into a unified Diablo 3/4 style high-gothic console featuring circular stone-framed orbs, an integrated top XP bar, and two distinct 2x4 grids (Left: 4 Skills + 4 Utility Q/W/E/T slots; Right: 8 Belt slots with F1-F8 hotkeys), while removing the redundant belt row from the inventory window.

**Architecture:** 
1. High-resolution HD gothic asset suite generated into `assets/hud/` for sharp scaling up to 4K.
2. `d1de_inventory` stripped of its middle belt row, freeing layout space for backpack and paperdoll.
3. `d1de_hud.tscn` restructured into a dual 2x4 layout separated by a central gothic stone pillar.
4. `d1de_hud.gd` augmented to manage the 8 HUD belt slots with F1-F8 hotkeys, context-aware LMB (drink if inventory closed, drag/swap if inventory open), and `AUTH_NATIVE` optimistic delta updates.

**Tech Stack:** Godot 4.7.2 Forward+ GDScript & Shaders, GDExtension DiabloBridge, PIL (Python asset synthesis).

**Spec:** [`docs/superpowers/specs/2026-10-18-d3-d4-hud-redesign-design.md`](file:///home/biti/antigravity/magical-bell/docs/superpowers/specs/2026-10-18-d3-d4-hud-redesign-design.md)

---

## Global Constraints

- **Engine Invariants (GEMINI.md):** Town (Level 0) PBR isolation, special CEL archway gating, and 4-row wall geometry must not be affected.
- **Authority Parity:** Belt consumption from the HUD must route through `diablo_bridge.use_belt_slot()`, triggering `_shadow_use()` and `_shadow_verify()` in `D1LogicAuthority` (maintaining promoted `AUTH_NATIVE` status).
- **Asset Quality:** No low-res crops from 723x145 mockups; all new textures must be clean, high-resolution RGBA assets suitable for 1080p, 1440p, and 4K displays.

## Review Focus

1. **F1–F8 Hotkey leakage:** F1–F8 key events must be swallowed by `d1de_hud.gd` `_unhandled_input()` so they do not trigger legacy engine hotkeys or leak into other viewports.
2. **Combat Safety (LMB Item Pickup):** Left-clicking an empty or filled HUD belt slot while the inventory is CLOSED must never pick an item onto the mouse cursor (`pcurs`), as dropping it or swinging a weapon would be blocked in combat.
3. **Optimistic HUD Desync:** Using a belt item from HUD via F1–F8 or click must trigger `apply_optimistic_item_delta()` with proper `seq_at_push`, expiring cleanly when the engine sequence advances.
4. **Resolution Scalability:** The new console layout must remain properly anchored to the bottom-center across viewport aspect ratios (16:9, 16:10, 21:9).
5. **Inventory Backward Compatibility:** Removing the belt from `d1de_inventory.tscn` must not break gold readouts, paperdoll equipment slots, or 40-cell backpack drag/drop interactions.

---

### Task 1: Generate High-Resolution Gothic Asset Suite

**Files:**
- Create: `tools/generate_hud_hd_assets.py`
- Create: `assets/hud/hud_gothic_d3_frame.png`
- Create: `assets/hud/frame_orb_stone.png`
- Create: `assets/hud/pillar_divider.png`
- Create: `assets/hud/slot_frame_gothic.png`
- Create: `assets/hud/xp_bar_frame.png`
- Create: `assets/hud/xp_bar_fill.png`
- Test: `tools/test_hud_assets.py`

**Interfaces:**
- Produces: High-res PNG assets in `assets/hud/` loaded by `d1de_hud.tscn` and `d1de_hud.gd`.

- [ ] **Step 1: Write the failing test**
Create `tools/test_hud_assets.py` checking required PNG files exist, have minimum 256x256 dimensions (or appropriate aspect ratio), and have RGBA mode.

- [ ] **Step 2: Run test to verify it fails**
Run: `python3 tools/test_hud_assets.py`  
Expected: FAIL (files missing).

- [ ] **Step 3: Implement asset synthesis in `tools/generate_hud_hd_assets.py`**
Generate crisp, dark gothic stone textures matching the user's reference:
- Beveled circular stone ring with cross accents for orbs (`frame_orb_stone.png`, 256x256).
- Carved stone column divider (`pillar_divider.png`, 64x256).
- Heavy metallic/stone beveled slot frame (`slot_frame_gothic.png`, 128x128).
- Sleek amber XP bar frame and glowing fill texture (`xp_bar_frame.png`, `xp_bar_fill.png`).
- Console background panel texture (`hud_gothic_d3_frame.png`).

- [ ] **Step 4: Run test to verify it passes**
Run: `python3 tools/generate_hud_hd_assets.py && python3 tools/test_hud_assets.py`  
Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add tools/generate_hud_hd_assets.py tools/test_hud_assets.py assets/hud/*.png
git commit -m "feat(hud): synthesize high-resolution gothic HUD assets"
```

---

### Task 2: Inventory Belt Removal and Layout Re-alignment

**Files:**
- Modify: `godot_d1_3d/scenes/hud/d1de_inventory.tscn`
- Modify: `godot_d1_3d/scenes/hud/d1de_inventory.gd:204-207,290-375,430-455,716-745`
- Test: `godot_d1_3d/test_inventory_cleanup.gd`

**Interfaces:**
- Consumes: Existing bridge paperdoll & backpack methods.
- Produces: Streamlined `d1de_inventory` without internal belt cells.

- [ ] **Step 1: Write the failing test**
Create `godot_d1_3d/test_inventory_cleanup.gd` to instantiate `d1de_inventory.tscn`, asserting that `BeltCells` node does not exist, backpack grid has exactly 40 children, and paperdoll slots remain intact.

- [ ] **Step 2: Run test to verify it fails**
Run: `tools/godot4/godot4 --headless --path godot_d1_3d --script res://test_inventory_cleanup.gd`  
Expected: FAIL (`BeltCells` still exists).

- [ ] **Step 3: Update `d1de_inventory.tscn` and `d1de_inventory.gd`**
- Remove `BeltCells` HBoxContainer and `Belt` title label from `d1de_inventory.tscn`.
- In `d1de_inventory.gd`, remove belt-specific references, initialization, and GUI input handlers that duplicate HUD functionality.
- Adjust vertical layout of `Backpack` container to eliminate the gap left by the removed belt.

- [ ] **Step 4: Run test to verify it passes**
Run: `tools/godot4/godot4 --headless --path godot_d1_3d --script res://test_inventory_cleanup.gd`  
Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add godot_d1_3d/scenes/hud/d1de_inventory.tscn godot_d1_3d/scenes/hud/d1de_inventory.gd godot_d1_3d/test_inventory_cleanup.gd
git commit -m "refactor(inventory): remove redundant belt row and realign layout"
```

---

### Task 3: Restructure HUD Scene Hierarchy (`d1de_hud.tscn`)

**Files:**
- Modify: `godot_d1_3d/scenes/hud/d1de_hud.tscn`
- Test: `godot_d1_3d/test_hud_hierarchy.gd`

**Interfaces:**
- Consumes: Assets from Task 1.
- Produces: New node hierarchy in `d1de_hud.tscn` matching the dual 2x4 console layout.

- [ ] **Step 1: Write the failing test**
Create `godot_d1_3d/test_hud_hierarchy.gd` to instantiate `d1de_hud.tscn` and assert:
- `LifeContainer` has circular stone frame and "HP" label.
- `ManaContainer` has circular stone frame and "MANA" label.
- `CenterPanel` has top `XpBar`.
- Left console contains 4 `SkillSlot` nodes (Row 1) and 4 utility potion slots (`HealthPotionSlot`, `ManaPotionSlot`, `RejuvPotionSlot`, `TownPortalSlot` in Row 2).
- `CenterPillar` node exists.
- Right console contains 8 `BeltSlot` nodes (`BeltSlot0`..`BeltSlot7`).

- [ ] **Step 2: Run test to verify it fails**
Run: `tools/godot4/godot4 --headless --path godot_d1_3d --script res://test_hud_hierarchy.gd`  
Expected: FAIL (Belt slots and pillar not in HUD).

- [ ] **Step 3: Update `d1de_hud.tscn`**
- Replace gargoyle and angel wing frames with `frame_orb_stone.png` circular stone bezels.
- Add `HpLabel` above life orb and `ManaLabel` above mana orb.
- Reorganize `CenterPanel`:
  - Top `XpBar` (TextureProgressBar using `xp_bar_frame.png` & `xp_bar_fill.png`).
  - HBox containing:
    - Left Grid (2 rows x 4 cols): Row 1 SkillSlot1..4, Row 2 Q/W/E/T slots.
    - CenterPillar TextureRect (`pillar_divider.png`).
    - Right Grid (2 rows x 4 cols): BeltSlot0..7 styled with `slot_frame_gothic.png`.

- [ ] **Step 4: Run test to verify it passes**
Run: `tools/godot4/godot4 --headless --path godot_d1_3d --script res://test_hud_hierarchy.gd`  
Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add godot_d1_3d/scenes/hud/d1de_hud.tscn godot_d1_3d/test_hud_hierarchy.gd
git commit -m "feat(hud): restructure scene to dual 2x4 console with integrated belt"
```

---

### Task 4: Implement HUD Belt Slots, F1–F8 Hotkeys, and Input Routing (`d1de_hud.gd`)

**Files:**
- Modify: `godot_d1_3d/scenes/hud/d1de_hud.gd`
- Test: `godot_d1_3d/test_hud_belt_and_bindings.gd`

**Interfaces:**
- Consumes: Bridge `get_belt_items()`, `use_belt_slot()`, `click_belt_slot()`, `D1LogicAuthority`.
- Produces: Full interactive belt slots on HUD with F1-F8 keyboard hotkeys and safe click logic.

- [ ] **Step 1: Write the failing test**
Create `godot_d1_3d/test_hud_belt_and_bindings.gd`:
- Test F1..F8 keypresses trigger belt slot 0..7 consumption.
- Test LMB on belt slot when inventory is closed drinks the potion directly (safe in combat).
- Test LMB on belt slot when inventory is open calls `click_belt_slot` (enables drag-and-drop).
- Test RMB on belt slot triggers optimistic HP/Mana delta and consumes item.

- [ ] **Step 2: Run test to verify it fails**
Run: `tools/godot4/godot4 --headless --path godot_d1_3d --script res://test_hud_belt_and_bindings.gd`  
Expected: FAIL (missing methods / bindings).

- [ ] **Step 3: Implement belt logic in `d1de_hud.gd`**
- Initialize the 8 HUD belt slots (`BeltSlot0`..`BeltSlot7`) with item icons, count labels, and badge labels (`F1`..`F8`).
- In `_unhandled_input(event)`, intercept `KEY_F1` through `KEY_F8`: call `_use_hud_belt_slot(i)` and consume event.
- In `_on_hud_belt_slot_gui_input(idx, event)`:
  - If LMB pressed and inventory tab is open: call `diablo_bridge.click_belt_slot(idx)`.
  - If LMB pressed and inventory tab is closed: call `_use_hud_belt_slot(idx)`.
  - If RMB pressed: call `_use_hud_belt_slot(idx)`.
- In `_use_hud_belt_slot(idx)`:
  - Fetch item data, trigger `_shadow_use(item)`, call `diablo_bridge.use_belt_slot(idx)`, and verify.
- Update `update_health_and_mana()` text formatting to `HP %d / %d` and `MANA %d / %d`.

- [ ] **Step 4: Run test to verify it passes**
Run: `tools/godot4/godot4 --headless --path godot_d1_3d --script res://test_hud_belt_and_bindings.gd`  
Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add godot_d1_3d/scenes/hud/d1de_hud.gd godot_d1_3d/test_hud_belt_and_bindings.gd
git commit -m "feat(hud): wire F1-F8 hotkeys, belt interaction, and optimistic updates"
```

---

### Task 5: End-to-End Regression Testing & Parity Verification

**Files:**
- Test: `godot_d1_3d/test_logic_authority.gd`
- Test: `godot_d1_3d/test_native_consumer.gd`
- Test: `godot_d1_3d/test_gate_handover.gd`
- Test: `godot_d1_3d/test_inventory_cleanup.gd`
- Test: `godot_d1_3d/test_hud_hierarchy.gd`
- Test: `godot_d1_3d/test_hud_belt_and_bindings.gd`

**Interfaces:**
- Verifies: Entire suite passes with zero regressions.

- [ ] **Step 1: Run all test suites**
Run:
```bash
tools/godot4/godot4 --headless --path godot_d1_3d --script res://test_logic_authority.gd
tools/godot4/godot4 --headless --path godot_d1_3d --script res://test_native_consumer.gd
tools/godot4/godot4 --headless --path godot_d1_3d --script res://test_gate_handover.gd
tools/godot4/godot4 --headless --path godot_d1_3d --script res://test_inventory_cleanup.gd
tools/godot4/godot4 --headless --path godot_d1_3d --script res://test_hud_hierarchy.gd
tools/godot4/godot4 --headless --path godot_d1_3d --script res://test_hud_belt_and_bindings.gd
```
Expected: All tests return PASS with exit code 0.

- [ ] **Step 2: Commit verified state**
```bash
git commit --allow-empty -m "test(hud): verify full HUD redesign and belt integration test pass"
```
