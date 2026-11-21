# Modern ARPG Ground Loot Labels & Diablo IV Tooltip System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform ground loot display into a modern ARPG experience (D2R / D3 / PoE style): ground item labels are always visible in the 3D world with stylized gothic dark slate backgrounds and quality-tinted borders (elevated above corpses at y = 0.85m), and hovering over any dropped item reveals a rich Diablo IV style item tooltip card showing full combat stats, durability, requirements, and gold value.

**Architecture:**
- **DevilutionX Engine Layer (`render_bridge`):** Enrich `D1ItemInfo` with detailed item stats (`itemType`, `minDam`, `maxDam`, `ac`, `durability`, `maxDur`, `reqStr`, `reqDex`, `reqMag`, `value`, `itemTypeDesc`, `magicDesc`).
- **GDExtension Layer (`DiabloBridge`):** Forward rich item stats to Godot via `get_active_items()`.
- **Godot 3D Sandbox Layer (`native_3d_sandbox.gd`):** 
  - Elevate ground item labels to `y = 0.85m` (above corpses and floor clutter).
  - Add dark slate backing quad with quality-colored border (Normal: Silver/White, Magic: Sapphire Blue, Unique: Radiant Gold).
  - Keep labels always visible on ground loot.
  - On mouse hover, scale up with golden radiance.
- **HUD Tooltip Layer (`d1de_hud`):**
  - Implement Diablo IV style item tooltip card with ornate gothic frame, header banner, large primary stats (Damage/Armor), durability, required attributes (highlighted red if unmet), sell value, and `[Left Click to Pick Up]` prompt.

**Tech Stack:** C++17 (DevilutionX & Godot GDExtension), Godot 4.7 GDScript Forward+, Control & Label3D billboards.

---

## Global Constraints
- **GEMINI.md Rule #1 & #2:** Maintain Town (Level 0) isolation. Never load Cathedral PBR or archways in Town.
- **GEMINI.md Rule #4:** Maintain character illumination and Forward+ unshaded sprite compensation.
- **GEMINI.md Rule #6:** Always evaluate mutating/risky shell commands via `evaluate_shell_command` on `laya-decision-engine`.
- **Zero Low-Poly Primitives:** Never introduce generic box placeholders.
- **Thread Safety:** DevilutionX engine thread communicates with Godot main thread strictly via mutex-guarded read states.

---

## Review Focus
1. Are ground item labels always clearly legible and elevated above dead monster corpses and blood decals?
2. Does hovering over a ground item immediately show the Diablo IV style tooltip card with correct stats?
3. Are unmet stat requirements highlighted in red?
4. Does moving the mouse off the item hide the tooltip card smoothly without leaking memory or sticking?
5. Does the test suite run headlessly with 100% pass across all existing regression suites?

---

## Task Structure

### Task 1: C++ Engine Item Data Enrichment (`render_bridge`)

**Files:**
- Modify: `DevilutionX/Source/engine/render_bridge.hpp:660-685`
- Modify: `DevilutionX/Source/engine/render_bridge.cpp:3335-3390`

- [ ] **Step 1.1:** Add detailed stat fields to `D1ItemInfo` in `render_bridge.hpp`:
  ```cpp
  struct D1ItemInfo {
      int id;
      int tileX;
      int tileY;
      int cursId;
      int quality;
      bool identified;
      char name[64];
      int width;
      int height;
      int animFrame;
      char qualityName[16] = { 0 };
      // Rich ARPG Stats (Task 5.4 / D4 Tooltip)
      int itemType = 0;
      int minDam = 0;
      int maxDam = 0;
      int ac = 0;
      int durability = 0;
      int maxDur = 0;
      int reqStr = 0;
      int reqDex = 0;
      int reqMag = 0;
      int value = 0;
      char itemTypeDesc[32] = { 0 };
      char magicDesc[128] = { 0 };
  };
  ```
- [ ] **Step 1.2:** In `GetActiveItemsList()` (`render_bridge.cpp`), extract and populate all stats from `Items[ii]`:
  - `info.itemType = static_cast<int>(item._itype);`
  - `info.minDam = item._iMinDam; info.maxDam = item._iMaxDam;`
  - `info.ac = item._iAC;`
  - `info.durability = item._iDurability; info.maxDur = item._iMaxDur;`
  - `info.reqStr = item._iMinStr; info.reqDex = item._iMinDex; info.reqMag = item._iMinMag;`
  - `info.value = item._ivalue;`
  - Map `itemType` to human-readable description (e.g. `"One-Handed Sword"`, `"Two-Handed Bow"`, `"Body Armor"`, `"Shield"`, `"Potion"`).
- [ ] **Step 1.3:** Rebuild `DevilutionX` with `ninja -C DevilutionX/build`.

---

### Task 2: GDExtension DiabloBridge Binding (`diablo_bridge`)

**Files:**
- Modify: `godot_d1_extension/src/diablo_bridge.cpp:1610-1630`

- [ ] **Step 2.1:** In `DiabloBridge::get_active_items()`, populate the Godot Dictionary with:
  - `d["item_type"] = item.itemType;`
  - `d["min_dam"] = item.minDam;`
  - `d["max_dam"] = item.maxDam;`
  - `d["ac"] = item.ac;`
  - `d["durability"] = item.durability;`
  - `d["max_dur"] = item.maxDur;`
  - `d["req_str"] = item.reqStr;`
  - `d["req_dex"] = item.reqDex;`
  - `d["req_mag"] = item.reqMag;`
  - `d["value"] = item.value;`
  - `d["type_desc"] = String::utf8(item.itemTypeDesc);`
  - `d["magic_desc"] = String::utf8(item.magicDesc);`
- [ ] **Step 2.2:** Rebuild GDExtension with `ninja -C godot_d1_extension/build`.

---

### Task 3: Modern 3D ARPG Ground Loot Label Box (Always Visible)

**Files:**
- Modify: `godot_d1_3d/scripts/native_3d_sandbox.gd:2450-2495, 3230-3250`

- [ ] **Step 3.1:** Upgrade `ItemLabel` in `get_or_create_item_node`:
  - Position elevated at `Vector3(0, 0.85, 0)` so it never clips into dead monster corpses or player feet.
  - Create a styled background quad (`MeshInstance3D` with `QuadMesh`, size adjusted to label text width + padding).
  - Material: Unshaded, dark slate translucent background (`Color(0.04, 0.04, 0.06, 0.90)`), with `no_depth_test = true` and `BILLBOARD_ENABLED`.
  - Outline border: Thin colored border matching item quality (`Color(0.85, 0.85, 0.88)` for normal, `Color(0.30, 0.65, 1.0)` for magic, `Color(1.0, 0.82, 0.22)` for unique).
  - Ensure label and background are **always visible** by default.
- [ ] **Step 3.2:** Update `_set_item_hover`:
  - When hovered:
    - Scale surges to 1.15x.
    - Border glows brilliant gold (`Color(1.0, 0.95, 0.50, 1.0)`).
  - When unhovered:
    - Smoothly restores to 1.0x scale and original quality border color.

---

### Task 4: Diablo IV Style Tooltip Card on Hover

**Files:**
- Create: `godot_d1_3d/scenes/hud/d4_item_tooltip.tscn` / `d4_item_tooltip.gd`
- Modify: `godot_d1_3d/scenes/hud/d1de_hud.gd`
- Modify: `godot_d1_3d/scripts/native_3d_sandbox.gd:3200-3235`

- [ ] **Step 4.1:** Create `d4_item_tooltip.gd` (Control):
  - Ornate dark stone panel with filigree border.
  - Header: Item Name (colored by quality) + Item Type subtitle (e.g. `★ TWO-HANDED BOW ★`).
  - Large Primary Stat Block:
    - If weapon: `"DAMAGE: 1 - 4"` in large bold font.
    - If armor: `"ARMOR: 15"`.
  - Durability line: `"Durability: 30 / 30"`.
  - Requirements block:
    - `"Requires: Strength 20, Dexterity 25"`.
    - If player's current strength or dexterity is less than required, highlight in red!
  - Magic / Unique affix lines (if applicable).
  - Value: `"Sell Value: 45 Gold"`.
  - Bottom action hint: `"[ Left Click to Pick Up ]"` in soft gold.
- [ ] **Step 4.2:** Integrate into `d1de_hud`:
  - Instantiate `d4_item_tooltip` as a screen-space overlay node.
  - Provide `show_item_tooltip(item_data: Dictionary, screen_pos: Vector2)` and `hide_item_tooltip()`.
  - Intelligently clamp tooltip position so it stays on screen near the mouse cursor or item position without clipping screen edges.
- [ ] **Step 4.3:** In `native_3d_sandbox.gd:update_hover`:
  - When `hit.type == "ITEM"`: call `hud.show_item_tooltip(hit.data, mouse_pos)`.
  - When mouse leaves item: call `hud.hide_item_tooltip()`.

---

### Task 5: Automated Verification Test Suite

**Files:**
- Create: `godot_d1_3d/test_task_loot_labels_and_d4_tooltip.gd`

- [ ] **Step 5.1:** Create test verifying:
  - Ground items create elevated labels (`y >= 0.80m`) with background quad meshes.
  - Labels and background quads are visible by default (not hidden).
  - Hovering over ground item triggers `_set_item_hover` (scale surge + golden glow).
  - Hovering feeds rich stats to HUD tooltip card.
  - Tooltip card displays correct name, category, damage/armor, durability, and requirements.
  - Unhover hides tooltip card cleanly.
- [x] **Step 5.2:** Run `test_task_loot_labels_and_d4_tooltip.gd` headlessly.
- [x] **Step 5.3:** Run all regression test suites (`test_3d_quality_gate.gd`, `test_task51_3d_interaction.gd`, `test_task52_combat_events.gd`).
- [x] **Step 5.4:** Commit and verify.
