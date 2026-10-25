# Task 5.2 — Native Combat Events, Floating Combat Text & Hit VFX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement 100% native Godot 4.7 Forward+ 3D combat feedback: real-time combat event streaming from DevilutionX to GDExtension, 3D floating combat text (damage numbers, crits, misses, blocks, XP gains, level-up), visual hit flinching with flash modulate, blood/shard particle bursts, and camera impact micro-shake.

**Architecture:**
- **DevilutionX Engine Layer (`render_bridge`):** Centralized thread-safe `D1CombatEvent` queue (`PushCombatEvent`, `DrainCombatEvents`) capturing damage events in `ApplyMonsterDamage`, `ApplyPlrDamage`, `MonsterDeath`, `NextPlrLevel`, `StartPlrBlock`, and hit/miss evaluation.
- **GDExtension Layer (`DiabloBridge`):** Expose `poll_combat_events() -> Array[Dictionary]` to Godot ClassDB.
- **Godot 3D Sandbox Layer (`native_3d_sandbox.gd`):** Process events in `_process(delta)`:
  - High-performance Floating Combat Text (FCT) 3D billboard pool with parabolic arc motion, color coding (crimson monster damage, gold crits, orange player damage, cyan blocks, gray misses, radiant XP/level-up).
  - Entity hit reaction: instantaneous `HIT` state synchronization on `Monster3DController` and `Warrior3DController`, sprite flash modulate (0.08s white/crimson flash).
  - 3D particle impact bursts: blood splatter for beasts/demons, bone chips for undead, shield sparks for blocks.
  - Camera trauma micro-shake on player heavy damage or critical strikes.

**Tech Stack:** C++17 (DevilutionX & Godot GDExtension), Godot 4.7 GDScript Forward+, GPUParticles3D, Label3D / CanvasItem billboards.

**Spec:** Task 5.2 in `diablo_3d_roadmap.md` and Diablo Engine Invariants (`GEMINI.md`).

---

## Global Constraints
- **GEMINI.md Rule #1 & #2:** Maintain Town (Level 0) isolation. Never load Cathedral PBR or archways in Town.
- **GEMINI.md Rule #4:** Maintain character illumination and Forward+ unshaded sprite compensation.
- **GEMINI.md Rule #6:** Always evaluate mutating/risky shell commands via `evaluate_shell_command` on `laya-decision-engine`.
- **Zero Low-Poly Primitives:** Never introduce generic box placeholders.
- **Thread Safety:** DevilutionX engine thread communicates with Godot main thread strictly via mutex-guarded event queues; never call Godot or SDL functions directly across threads.

---

## Review Focus
1. Does monster damage calculate in integer display points (`damage >> 6`), avoiding fractional 64th internal point discrepancies?
2. Does floating combat text render legibly and billboard correctly at any camera pitch, yaw, and zoom?
3. Are floating text nodes pooled or freed smoothly without leaking memory over extended dungeon combat?
4. Does the overhead monster health bar and HUD top-center boss bar update instantly on damage without waiting for the next polling cycle?
5. Does the test suite run headlessly with zero regressions across all existing test suites?

---

## Task Structure

### Task 1: C++ Engine Combat Event Architecture (`render_bridge`)

**Files:**
- Modify: `DevilutionX/Source/engine/render_bridge.hpp:315-340`
- Modify: `DevilutionX/Source/engine/render_bridge.cpp:1310-1360`
- Modify: `DevilutionX/Source/monster.cpp:3590-3605` (`ApplyMonsterDamage`)
- Modify: `DevilutionX/Source/monster.cpp:3685-3715` (`MonsterDeath`)
- Modify: `DevilutionX/Source/player.cpp:615-630, 2480-2490, 2639-2650, 2843-2860` (`PlrHitMonst`, `NextPlrLevel`, `StartPlrBlock`, `ApplyPlrDamage`)

- [ ] **Step 1.1:** Define `D1CombatEventType` enum and `D1CombatEvent` struct in `render_bridge.hpp`:
  ```cpp
  enum class D1CombatEventType : uint32_t {
      DamageToMonster = 1,
      DamageToPlayer = 2,
      MonsterDeath = 3,
      PlayerDeath = 4,
      PlayerBlock = 5,
      CombatMiss = 6,
      PlayerLevelUp = 7
  };
  struct D1CombatEvent {
      uint32_t type = 0;
      int32_t sourceId = -1;
      int32_t targetId = -1;
      int32_t tileX = 0;
      int32_t tileY = 0;
      int32_t damage = 0;
      int32_t targetHp = 0;
      int32_t targetMaxHp = 0;
      int32_t damageType = 0;
      bool isCrit = false;
      int32_t expGained = 0;
      int32_t newLevel = 0;
  };
  void PushCombatEvent(const D1CombatEvent &event);
  std::vector<D1CombatEvent> DrainCombatEvents();
  ```
- [ ] **Step 1.2:** Implement thread-safe `PushCombatEvent` and `DrainCombatEvents` in `render_bridge.cpp` using a mutex-protected vector.
- [ ] **Step 1.3:** Call `PushCombatEvent` in `ApplyMonsterDamage`:
  - Damage points: `damage >> 6` (minimum 1 if damage > 0).
  - Target HP: `std::max(0, (monster.hitPoints - damage) >> 6)`.
  - Max HP: `monster.maxHitPoints >> 6`.
  - Check for critical strike flag if set by attacker.
- [ ] **Step 1.4:** Call `PushCombatEvent` in `ApplyPlrDamage`:
  - Damage points: `totalDamage >> 6` (minimum 1 if totalDamage > 0).
  - Target HP: `std::max(0, (player._pHitPoints - totalDamage) >> 6)`.
- [ ] **Step 1.5:** Call `PushCombatEvent` in `MonsterDeath` (with monster XP), `NextPlrLevel` (with new level), and `StartPlrBlock` (block event).
- [ ] **Step 1.6:** Rebuild `DevilutionX` with `ninja -C DevilutionX/build`.

---

### Task 2: GDExtension DiabloBridge Binding (`diablo_bridge`)

**Files:**
- Modify: `godot_d1_extension/src/diablo_bridge.h:180-210`
- Modify: `godot_d1_extension/src/diablo_bridge.cpp:1210-1240`

- [ ] **Step 2.1:** Declare `Array poll_combat_events();` in `diablo_bridge.h`.
- [ ] **Step 2.2:** Implement `poll_combat_events()` in `diablo_bridge.cpp`:
  - Calls `devilution::DrainCombatEvents()`.
  - Iterates and converts each event into a Godot Dictionary with keys: `type`, `source_id`, `target_id`, `tile`, `damage`, `target_hp`, `target_max_hp`, `damage_type`, `is_crit`, `exp_gained`, `new_level`.
- [ ] **Step 2.3:** Bind `poll_combat_events` in `DiabloBridge::_bind_methods()`.
- [ ] **Step 2.4:** Rebuild GDExtension with `ninja -C godot_d1_extension/build`.

---

### Task 3: 3D Floating Combat Text (FCT) Billboard System

**Files:**
- Create: `godot_d1_3d/scripts/floating_combat_text.gd` (FCT Manager & Pooled Label3D/Node3D)
- Modify: `godot_d1_3d/scripts/native_3d_sandbox.gd:650-750`

- [ ] **Step 3.1:** Create `floating_combat_text.gd`:
  - Lightweight `Node3D` containing a configured `Label3D` (billboard mode `BILLBOARD_ENABLED`, fixed size or depth-tested font, double-rendered outline).
  - Types:
    - `MONSTER_DAMAGE`: Crimson red `#ff3333`, font size 38, outline size 12 black, parabolic arc upward and slight left/right spread.
    - `CRITICAL_HIT`: Golden yellow `#ffd700`, font size 52, outline size 16 dark brown, exclamation marks (`"CRIT -48!"`), vertical surge.
    - `PLAYER_DAMAGE`: Vivid orange `#ff8822` with red outline `#880000`, font size 42.
    - `BLOCK`: Cyan `#33ccff`, font size 34 (`"BLOCKED"`).
    - `MISS`: Slate gray `#aaaaaa`, font size 30 (`"MISS"`).
    - `XP_GAIN`: Gold `#ffea60`, font size 36 (`"+120 XP"`).
    - `LEVEL_UP`: Brilliant holy gold `#ffffff` core with `#ffbb00` glow, font size 56 (`"★ LEVEL UP! ★"`).
  - Animation: moves upward with initial velocity, decrescendo arc, alpha fades from 1.0 to 0.0 over 0.85s, then returns to pool or frees.
- [ ] **Step 3.2:** Integrate FCT into `native_3d_sandbox.gd`:
  - Instantiate `FloatingCombatTextManager` as a child node.
  - In `_process(delta)`: Poll `diablo_bridge.poll_combat_events()` and dispatch to `spawn_fct(...)` at the target entity's 3D position.

---

### Task 4: Hit Reactions, Visual Flashing & Particle Bursts

**Files:**
- Modify: `godot_d1_3d/scripts/native_3d_sandbox.gd`
- Modify: `godot_d1_3d/scripts/monster_3d_controller.gd`
- Modify: `godot_d1_3d/scripts/warrior_3d_controller.gd`

- [ ] **Step 4.1:** Add flash modulate effect on hit:
  - When monster is damaged, briefly modulate `Sprite3D` or mesh material to `Color(2.2, 0.5, 0.5, 1.0)` for 0.08s, then smoothly lerp back to original.
  - Trigger `HIT` state on `Monster3DController` immediately.
  - When player is damaged, briefly modulate player sprite and trigger `HIT` state on `Warrior3DController`.
- [ ] **Step 4.2:** 3D Blood & Spark Particle Bursts:
  - Connect to existing `D1VisualEvent` / `D1CombatEvent`:
  - Blood splatter GPUParticles3D for flesh monsters (red directional cone along hit vector).
  - Bone chips GPUParticles3D for skeleton monsters (white jagged shards).
  - Shield spark GPUParticles3D on `PlayerBlock`.
- [ ] **Step 4.3:** Camera Impact Micro-Shake:
  - Add `trauma: float` to Camera3D in `native_3d_sandbox.gd`.
  - When player takes damage > 10% max HP or lands a critical hit, add 0.25 trauma.
  - In `_process(delta)`: apply slight rotational shake based on `trauma * trauma`, decaying linearly.

---

### Task 5: Automated Verification Test Suite

**Files:**
- Create: `godot_d1_3d/test_task52_combat_events.gd`

- [ ] **Step 5.1:** Create headless SceneTree test script verifying:
  - Mock bridge emitting `DamageToMonster` generates crimson FCT with correct damage text and position.
  - Emitting `DamageToPlayer` generates orange FCT.
  - Emitting critical hit generates enlarged golden `"CRIT"` text.
  - Emitting block generates cyan `"BLOCKED"` text.
  - Emitting level-up generates `"LEVEL UP"` FCT.
  - Monster flash modulation and HP bar updates instantly.
  - Memory cleanliness: verify FCT nodes are freed after animation duration.
- [ ] **Step 5.2:** Run `test_task52_combat_events.gd` headlessly.
- [ ] **Step 5.3:** Run all existing quality gate and regression tests (`test_3d_quality_gate.gd`, `test_task51_3d_interaction.gd`, `test_task32_aaa_cathedral_kit.gd`, etc.).
