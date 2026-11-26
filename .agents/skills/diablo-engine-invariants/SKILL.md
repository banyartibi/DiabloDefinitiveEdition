---
name: diablo-engine-invariants
description: >-
  Critical rules, mathematical invariants, and procedural safeguards for Diablo: Definitive Edition.
  Always consult and strictly adhere to this skill when modifying graphics, shaders, dungeon loading,
  PBR tile pipelines, lighting, gamma/brightness, or level transitions in the Diablo 1 codebase.
---

# Diablo: Definitive Edition Engine Invariants & Architecture Runbook

This skill enforces core architectural invariants and procedures to prevent recurring regressions in the Diablo: Definitive Edition engine (Godot 4.7.2 + DevilutionX GDExtension).

## Non-Negotiable Invariants

### 1. Town (Level 0) Must Never Load Pre-Baked PBR Assets
- Diablo 1 piece IDs are **per-theme** (Piece 2 in Cathedral is blood stone floor; Piece 2 in Town is grass).
- Town tiles must ALWAYS come directly from `diablo_bridge.get_dungeon_piece_texture(piece_id)`.
- Never create a folder called `dungeon_pbr_town_4x` with copied Cathedral assets.
- In `native_25d_view.gd`, both `get_pbr_or_base_texture()` and `get_pbr_or_base_special_texture()` must return `base_tex` immediately if `not is_cathedral_level()`.

### 2. Special CEL Archways Must Never Exist in Town
- `dSpecial` indices in Cathedral refer to stone arches, doorways, and columns.
- `dSpecial` indices in Town refer to tree leaf delay drawing (`towns.clx`), NOT archways.
- Special sprites in `native_25d_view.gd` line 825 must be gated by:
  `if special_id > 0 and is_cathedral_level() and (solidity_grid.size() < 112 * 112 or solidity_grid[idx] != 0):`
  NEVER check `last_level_idx == 0` for special archway sprites!

### 3. Butcher Room Walls (Pieces 180, 185..188) Height Requirement
- Cathedral wall pieces 180, 185, 186, 187, 188 are 4-row walls.
- In 1X: width 64, height 128.
- In 4X: width 256, height 512.
- The height must be 512px. Any shorter crop causes vertical shift, breaking door frames and wall alignment.

### 4. Gamma and Brightness Dual Sync
- Global post-processing brightness & gamma live in `view_brightness.gdshader` (driven by `bridge_receiver.gd`).
- The in-game palette in DevilutionX is updated via `diablo_bridge.set_gamma(g)`.
- Whenever gamma is changed in the options menu (`_on_opt_gamma_changed`), both `brightness_host.set_gamma_pct(g)` and `diablo_bridge.set_gamma(g)` must be called.
- Character sprites are unshaded in `entity_hd_upscaler.gdshader`. Therefore, `player_sprite.self_modulate` must provide healthy illumination:
  `Color(1.50, 1.46, 1.38)` in Town, `Color(1.48, 1.44, 1.36)` in Dungeons.

### 5. Transition to 100% Native Godot
- Every new feature and refactoring must move logic into native Godot (GDScript / C++ extension) rather than relying on legacy DevilutionX internals.

### 6. HD Sprite Alpha Must Be Rebuilt From The Raw 1x Silhouette
- HD sprite alpha is **derived, never resampled**. Source of truth: `scratch/raw_sprites/<category>_<folder>/gG_fFFF.png`, whose alpha is strictly binary (0 or 255).
- `tools/repair_hd_sprite_alpha.py` rebuilds alpha: NEAREST upscale of the raw mask (body stays 100% opaque) + one softened pixel ring outside the silhouette. RGB is never touched.
- **Never** derive alpha from the upscaled PNG's own alpha (LANCZOS/BILINEAR). BILINEAR/LANCZOS resampling of a binary mask at 4x mixes neighbouring mask pixels across the whole body (PIL's sampling grid is offset by half a pixel), producing translucent "ghost" characters; a soft outer halo is the other failure mode.
- HD↔raw frame pairing is by `(group, frame)` digit key, disambiguated by mean RGB distance on raw-mask pixels (accept < 90, lowest wins). Shape/IoU gating cannot disambiguate variants, because the corrupted alpha makes every variant's footprint identical.
- Frames with no raw counterpart (gear-independent `player/warrior_*`, padded `items/curs_*` icons) use the self-repair fallback: keep the existing opaque core binary, drop the halo. Do not map them onto a different action's raw mask.
- Gate before declaring any sprite work done: `python3 tools/repair_hd_sprite_alpha.py --check --sample 1000000` must report `translucent max=0.0000 halo max=0.0000` for every category (exit code 2 = fail).
- Pre-repair mirror: `/home/biti/antigravity/hd_x4plus_backup_before_alpha_fix` (hardlinks; restore a category with `rm -rf assets/hd_sprites_x4plus/<cat> && cp -al $BK/<cat> assets/hd_sprites_x4plus/<cat>`).

### 7. Upscale Must Never See Sprite Alpha — Composite First, Then Re-Mask
- Feeding RGBA alpha-on-black straight into RealESRGAN destroys both channels: the net blends the transparent background into the image (body mean drops from ~54 to ~33, sprites render as dark silhouettes) and the alpha channel bleeds outward into a halo of extra opaque near-black pixels.
- `tools/hd_batch_upscale.py` is the only sanctioned deploy path: composite the sprite over that sheet's median background colour, upscale RGB only, then re-apply the hard 4x NEAREST mask taken from the raw 1x alpha. Opaque pixel count must equal `raw_opaque * 16` exactly.
- Deployed names follow the sheets the engine loads (`DevilutionX/Source/player.cpp` `LoadPlrGFX`): dungeon Stand = `as`, dungeon Walk = `aw` (weapon drawn), town = `st`/`wl`. Two sheets must never share one deployed folder name — whichever runs last silently overwrites the other.
- Gate: `python3 tools/audit_hd_vs_raw.py` (exit 2 = fail) checks coverage = 1.0, halo = 0, and HD brightness within 25% of the raw 1x mean per folder.

## Verification
- Alpha gate: `tools/repair_hd_sprite_alpha.py --check` (see invariant 6).
- Brightness/halo gate: `python3 tools/audit_hd_vs_raw.py` (see invariant 7).
- On-screen HD coverage: `tools/godot4/godot4 --path godot_d1_3d --script test_audit_hd_on_screen.gd` → `AUDIT sprite3d_hd` should dominate `sprite3d_1x`, `AUDIT hero ... hd=` must be a size (not `null` — HD frames decode asynchronously, the script pumps the queue before judging), `AUDIT items=… missing_hd=0`.

