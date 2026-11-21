# Design Document: D3/D4 Style Gothic HUD Redesign & Belt Integration

**Date:** 2026-10-18  
**Topic:** Modern Diablo 3/4 Style HUD with Dual 2x4 Consoles & Integrated Belt  
**Status:** In Review (Brainstorming Phase)

---

## 1. Intent & The Why

The current HUD in Diablo: Definitive Edition features separated element boxes (Q, W, E, T quick slots floating beside gargoyle/angel framed orbs) and a single-row center action bar with an inventory that separately displays an 8-slot belt. 

This redesign replaces the fragmented HUD with a unified, high-gothic Diablo 3/4 style lower console:
1. **Visual cohesion:** The HUD becomes a single integrated, architectural stone console anchored by ornate circular stone-framed Life and Mana orbs.
2. **Ergonomic central layout:** The console is divided into two distinct 2x4 grids by a central gothic stone column:
   - **Left 2x4:** Quick Skills (Row 1: 1, 2, 3, 4) + Dedicated Survival/Utility Slots (Row 2: Q Health, W Mana, E Rejuv, T Town Portal).
   - **Right 2x4:** The classic 8-slot Belt (Row 1: slots 1..4, Row 2: slots 5..8) arranged in a Diablo 2 style grid.
3. **Inventory uncluttering:** With the 8-slot belt fully visible, interactive, and prominent on the main HUD at all times, the redundant belt row inside the inventory window (`d1de_inventory.tscn`) is eliminated, giving the backpack and paperdoll a cleaner, cleaner look.

---

## 2. Goals, Non-Goals, and Anti-Goals

### Goals
- **Pristine High-Resolution Modern Aesthetic:** Do NOT simply crop the low-resolution 723x145 mockup. Instead, engineer high-resolution, modern HD gothic assets (sharp on 1080p, 1440p, and 4K displays) matching the mockup's architectural style:
  - Deep-carved stone orb bezels with gothic cross accents for Life and Mana.
  - Carved central gothic pillar separating skills and belt.
  - Crisp, dark gothic slot borders with beveled metallic trim.
  - Sleek glowing amber XP bar with gothic filigree brackets.
- **Ornate Gothic Orbs:** Circular stone frames for Life (Left) and Mana (Right), powered by the existing Forward+ `liquid_globe.gdshader` (preserving slosh, bubbling, and glow).
- **Text readouts:** Prominent "HP [current] / [max]" and "MANA [current] / [max]" text above or flanking the orbs.
- **Top XP Progress Bar:** A sleek amber/gold progress bar running across the top edge of the central console with level readout and hover tooltip.
- **Left Console (2x4):**
  - Top row: 4 Skills bound to hotkeys `1`, `2`, `3`, `4`.
  - Bottom row: 4 dedicated utility items bound to `Q` (Health Potion), `W` (Mana Potion), `E` (Rejuvenation Potion), and `T` (Town Portal).
- **Right Console (2x4 Belt):**
  - 8 belt slots (Top row: 1, 2, 3, 4 bound to `F1`, `F2`, `F3`, `F4`; Bottom row: 5, 6, 7, 8 bound to `F5`, `F6`, `F7`, `F8`).
  - Supports item icon display (HD item fallback), item counts, mouse hover tooltips, and click/drag interaction.
  - Click interaction rules:
    - **Inventory Closed:** LMB or RMB immediately drinks/uses the potion, preventing accidental cursor-item pickup during combat.
    - **Inventory Open:** LMB picks up / drops / swaps items onto the cursor (`pcurs`) as standard drag-and-drop. RMB drinks/uses the potion.
  - Right-click consumes belt items with optimistic HUD updates and logic authority parity verification.
- **Inventory cleanup:** Remove `BeltCells` and redundant belt header from `d1de_inventory.tscn` and `d1de_inventory.gd`.
- **Maintain 100% test pass rate:** Existing tests (`test_logic_authority.gd`, `test_native_consumer.gd`, `test_gate_handover.gd`) must remain green.

### Non-Goals
- Changing DevilutionX C++ underlying belt data structures (the C++ engine continues to store 8 belt slots; the GDExtension bridge functions `get_belt_items()`, `click_belt_slot()`, `use_belt_slot()` remain unchanged).
- Re-architecting the spell selection / spellbook system beyond wiring to the 4 skill slots.

### Anti-Goals
- No loss of responsive scaling: The HUD must remain centered at the bottom of the screen across different display resolutions.
- No regression of `AUTH_NATIVE` optimistic feedback: Clicking potions in either the Q/W/E/T slots or the 2x4 belt must continue to provide instant globe reactions.

---

## 3. Architecture & Component Changes

### 3.1 High-Resolution Asset Generation & Preparation (`assets/hud/`)
Do not use low-res pixel crops from the mockup. Instead, synthesize/generate clean, pixel-crisp modern HD gothic textures (targeted for modern 1080p, 1440p, 4K displays):
- `hud_gothic_d3_frame.png`: High-resolution composite dark gothic stone frame.
- `frame_orb_stone.png`: High-resolution circular gothic stone bezel with carved cross/fleur-de-lis accents.
- `pillar_divider.png`: High-resolution carved gothic stone column separating left and right consoles.
- `slot_frame_gothic.png`: High-resolution beveled gothic stone/metal slot frame.
- `xp_bar_frame.png` & `xp_bar_fill.png`: High-resolution ornamental XP bar styling.

### 3.2 HUD Scene (`d1de_hud.tscn`)
Restructure `Root/HBox`:
- **Left:** `LifeContainer`
  - Stone orb frame (`frame_orb_stone.png`).
  - `LifeGlobe` (`ColorRect` with `ShaderMaterial_life`).
  - `HpLabel` ("HP 215 / 215") positioned above the orb.
- **Center:** `CenterConsole` (Gothic stone panel with top XP bar):
  - `XpBar`: TextureProgressBar / StyleBoxFlat across the top edge.
  - `ConsoleGridHBox`:
    - `LeftSubgrid` (VBoxContainer / GridContainer, 2 rows x 4 columns):
      - Row 1: `SkillSlot1`..`SkillSlot4` (Badges: 1, 2, 3, 4).
      - Row 2: `HealthPotionSlot` (Q), `ManaPotionSlot` (W), `RejuvPotionSlot` (E), `TownPortalSlot` (T).
    - `CenterPillar`: TextureRect displaying `pillar_divider.png`.
    - `RightSubgrid` (GridContainer, 2 rows x 4 columns):
      - `BeltSlot0`..`BeltSlot3` (Row 1, badges F1..F4 or 1..4 with F1..F4 tooltips/hints).
      - `BeltSlot4`..`BeltSlot7` (Row 2, badges F5..F8 or 5..8 with F5..F8 tooltips/hints).
- **Right:** `ManaContainer`
  - Stone orb frame (`frame_orb_stone.png`).
  - `ManaGlobe` (`ColorRect` with `ShaderMaterial_mana`).
  - `ManaLabel` ("MANA 150 / 150") positioned above the orb.

### 3.3 HUD Script (`d1de_hud.gd`)
- Add wiring and handlers for the 8 belt slots (`BeltSlot0`..`BeltSlot7`).
- Add keyboard hotkey handlers for `F1`..`F8` (F1..F4 trigger belt slots 0..3, F5..F8 trigger belt slots 4..7).
- Update `_update_belt()` to populate icons, quantities, and tooltips on the HUD belt slots.
- Wire GUI input events for HUD belt slots:
  - If inventory is open: LMB picks up/swaps items via bridge `click_belt_slot`.
  - If inventory is closed: LMB or RMB uses/drinks potion via bridge `use_belt_slot` with `_shadow_use`.
  - RMB always drinks/uses potion.
- Adjust HP/Mana label formatting to match the "HP X / Y" and "MANA X / Y" layout.

### 3.4 Inventory Scene & Script (`d1de_inventory.tscn` / `d1de_inventory.gd`)
- Remove the `Belt` label and `BeltCells` container.
- Adjust vertical anchors/offsets so the `Backpack` container cleanly fills the lower half under the `Paperdoll` without dead space.
- Remove redundant belt initialization and update methods from `d1de_inventory.gd` (or delegate them to the HUD).

---

## 4. Input & Keybinding Matrix

| Slot | Default Key | Action |
|------|-------------|--------|
| Skill 1 | `1` | Cast / Select Skill 1 |
| Skill 2 | `2` | Cast / Select Skill 2 |
| Skill 3 | `3` | Cast / Select Skill 3 |
| Skill 4 | `4` | Cast / Select Skill 4 |
| Health Potion | `Q` | Use best healing potion/scroll |
| Mana Potion | `W` | Use best mana potion/scroll |
| Rejuvenation Potion | `E` | Use rejuvenation potion |
| Town Portal | `T` | Cast / Use Town Portal scroll |
| Belt Slot 1 | `F1` / Click | Drink / Interact with Belt Slot 1 |
| Belt Slot 2 | `F2` / Click | Drink / Interact with Belt Slot 2 |
| Belt Slot 3 | `F3` / Click | Drink / Interact with Belt Slot 3 |
| Belt Slot 4 | `F4` / Click | Drink / Interact with Belt Slot 4 |
| Belt Slot 5 | `F5` / Click | Drink / Interact with Belt Slot 5 |
| Belt Slot 6 | `F6` / Click | Drink / Interact with Belt Slot 6 |
| Belt Slot 7 | `F7` / Click | Drink / Interact with Belt Slot 7 |
| Belt Slot 8 | `F8` / Click | Drink / Interact with Belt Slot 8 |

---

## 5. Verification Plan
1. **Automated Unit Tests:**
   - Run `tools/godot4/godot4 --headless --path godot_d1_3d --script res://test_logic_authority.gd` -> MUST PASS.
   - Run `tools/godot4/godot4 --headless --path godot_d1_3d --script res://test_native_consumer.gd` -> MUST PASS.
   - Run `tools/godot4/godot4 --headless --path godot_d1_3d --script res://test_gate_handover.gd` -> MUST PASS.
2. **Visual & Interaction Check:**
   - Launch in debug/headless or in-game mode to verify that the HUD renders without errors, textures are aligned, and HUD belt slots react to inventory item changes.
   - Verify that removing belt from `d1de_inventory` maintains clean spacing and item drag-and-drop functionality between backpack and paperdoll slots.
