# Diablo: Definitive Edition — Engine Invariants & Architecture Rules

> **CRITICAL DIRECTIVE FOR ALL AGENTS WORKING IN THIS CODEBASE:**
> Never violate these architectural invariants. These rules have been verified across extensive testing and represent hard mathematical/engine truths of the Diablo 1 (DevilutionX) + Godot 4.7 architecture. Violating these causes severe graphical regressions (corrupted town tiles, archways on trees, black screens, misaligned Butcher room walls).

---

## 1. Town (Level 0) Isolation & PBR Policy

* **Piece ID Overlap Truth:** In Diablo 1, dungeon tile IDs (`dPiece`) are level-type specific and **not unique** across themes:
  - Cathedral (L1): Piece 2 is bloody stone floor, Piece 168 is a stone wall.
  - Town (L0): Piece 2 is grass/dirt pathway, Piece 168 is wooden fence/path.
* **NEVER Point Town to Cathedral PBR Assets:**
  - Do NOT point Level 0 to `dungeon_pbr_4x` or `dungeon_pbr_cathedral_4x`.
  - Do NOT copy Cathedral tiles into any town folder (e.g. `dungeon_pbr_town_4x`).
  - Town tiles MUST come strictly from the engine bridge: `diablo_bridge.get_dungeon_piece_texture(piece_id)`.
* **In `native_25d_view.gd`:**
  - `get_pbr_or_base_texture(piece_id: int)` MUST contain:
    ```gdscript
    if not hd_graphics_enabled or not is_cathedral_level():
        if base_tex:
            pbr_texture_cache[piece_id] = base_tex
        return base_tex
    ```
  - `get_pbr_or_base_special_texture(special_id: int)` MUST contain:
    ```gdscript
    if not hd_graphics_enabled or not is_cathedral_level():
        if base_tex:
            pbr_special_cache[special_id] = base_tex
        return base_tex
    ```

---

## 2. Special CEL Archways Gating

* **Dungeon vs Town `dSpecial` Truth:**
  - In Cathedral (L1), `dSpecial` (values 1..18) indices reference stone archways, doorways, and column tops (`special_1..18.png`).
  - In Town (L0), `dSpecial` is used by the Diablo engine for tree leaf delay sorting (`towns.clx`), **never archways**.
  - Placing Cathedral archways or columns in Town creates stone arches on grass and trees!
* **Gating Rule:** In `rebuild_dungeon_tiles()` (`native_25d_view.gd`), the instantiation of `special_sprites` MUST strictly enforce:
  ```gdscript
  if special_id > 0 and is_cathedral_level() and (solidity_grid.size() < 112 * 112 or solidity_grid[idx] != 0):
  ```
  **NEVER** allow `last_level_idx == 0` to build special sprites!

---

## 3. Butcher Room Wall Piece Geometry (Pieces 168, 169, 177, 179, 180, 185..188)

* **Aspect Ratio & Height Truth:**
  - Cathedral pieces 180, 185, 186, 187, 188 are 4-row walls (`numRows = 4`).
  - In 1X scale: width 64, height 128 (offset y = -128).
  - In 4X scale: width 256, height 512 (offset y = -128 in world coordinates via `64.0 / width` scale factor).
* **Crop Alignment Invariant:**
  - If a 4-row wall piece is cropped to 256x384 or 256x256, it will shift down by 32 or 64 world pixels, resulting in broken Butcher room door frames and gaping holes.
  - The runtime validation in `get_pbr_or_base_texture` enforces:
    ```gdscript
    var pbr_world_h = int(round(float(alb_img.get_height()) * (64.0 / float(alb_img.get_width()))))
    if abs(pbr_world_h - base_tex.get_height()) > 4:
        pbr_texture_cache[piece_id] = base_tex
        return base_tex
    ```
  - All wall pieces in `dungeon_pbr_cathedral_4x` and `dungeon_pbr_4x` must remain 256x512.

---

## 4. Gamma, Brightness & Lighting Coordination

* **Pipeline Separation:**
  - Global Brightness & Gamma are handled in Godot's Forward+ pipeline via `view_brightness.gdshader` on the composited `GameView` SubViewport.
  - When the user changes Gamma in the native options menu, `_on_opt_gamma_changed(v)` MUST notify both:
    1. `brightness_host.set_gamma_pct(g)` (for the Godot post-process shader).
    2. `diablo_bridge.set_gamma(g)` (for DevilutionX palette recalculation so palette-based sprites update).
* **Character Illumination (Unshaded Sprite Compensation):**
  - Character, monster, and object sprites use `entity_hd_upscaler.gdshader` with `render_mode unshaded`.
  - Because they are unshaded, they do not receive Godot PointLight2D diffuse lighting.
  - In `update_player()`, `player_sprite.self_modulate` must provide healthy illumination:
    - Town: `Color(1.50, 1.46, 1.38)` (matching Town daylight `vec3(1.65, 1.60, 1.48)`).
    - Dungeon: `Color(1.48, 1.44, 1.36)` (matching torchlit ambient diffuse so the character is not dark compared to the surrounding floor).

---

## 5. Decoupling Towards 100% Native Godot

* The long-term architecture moves logic natively into Godot 4.7 GDScript and C++ GDExtension, reducing DevilutionX dependencies over time.
* Never introduce tightly-coupled hacks or hardcode file paths without checking level types.
* Always preserve backward compatibility across all 3 display modes (Mode 0: Classic 2.5D, Mode 1: Native Godot 2.5D, Mode 2: Native 3D Sandbox).

---

## 6. Laya System 1 Decision Engine Routing & Token Optimization

* **Zero Token & Zero GPU Overhead:** Laya runs locally on CPU (`laya-decision-engine` MCP server via `call_mcp_tool`).
* **Shell Command Safety:** All mutating/risky shell commands (file modifications, git actions, builds, package/system changes) MUST be evaluated with `evaluate_shell_command` before running. Simple read-only queries (`cat`, `ls`, `grep`) are exempt.
* **Build Error Triage:** When C++, CMake, SCons, or GDExtension compilation or linker errors occur, call `triage_build_error` to apply mechanical fixes directly and eliminate speculative reasoning.
* **Architectural Decisions:** For multi-option architectural trade-offs, query `make_decision` to select the highest-confidence deterministic path without token waste.
