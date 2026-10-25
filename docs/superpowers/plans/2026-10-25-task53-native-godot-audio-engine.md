# Task 5.3: Native Godot 4.7 Audio Engine & Teardown Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish a 100% native Godot 4.7 Audio Pipeline (`D1AudioManager`), eliminating the legacy DevilutionX SDL `/dev/dsp` "No such audio device" error, preventing hardware device contention, and ensuring all sound effects, footsteps, monster roars, and ambient music play seamlessly in full 3D spatial sound.

**Architecture:** Under embedded Godot execution (`gbGodotBridgeActive = true`), DevilutionX C++ operates as a pure headless event generator: `snd_init()` uses `Aulib::initWithoutOutput(...)` instead of touching physical audio hardware. This activates `gbSndInited = true` without error, enabling all `PlaySFX` and `PlaySfxLoc` sound events to flow into the `g_AudioEventQueue`. The Godot engine polls these events via `diablo_bridge.poll_audio_events()` and dispatches them to `D1AudioManager`, which manages crossfading music and a pool of `AudioStreamPlayer3D` positional spatializers in the 3D dungeon.

**Tech Stack:** C++17 (DevilutionX, GDExtension), Godot 4.7.2 Forward+ GDScript, `AudioServer`, `AudioStreamWAV`, `AudioStreamPlayer3D`, `AudioEffectReverb`.

---

## Global Constraints

- **Zero SDL Audio Device Conflicts:** DevilutionX must NEVER attempt to open physical audio hardware devices (`/dev/dsp`, ALSA, PulseAudio) directly when running embedded inside Godot.
- **Uncompromised Event Generation:** `gbSndInited` must remain `true` so all game mechanics (weapons, doors, monsters, chests, level-ups) generate audio events.
- **GEMINI.md Rule #6 Inviolability:** All mutating shell commands (builds, scons, cmake) must be evaluated with `evaluate_shell_command` via `laya-decision-engine`.

---

## Implementation Tasks

### Task 1: C++ Audio Subsystem Decoupling in DevilutionX
- [x] In `DevilutionX/Source/engine/sound.cpp`, update `snd_init()`:
  - If `gbGodotBridgeActive` is true, invoke `Aulib::initWithoutOutput(*sgOptions.Audio.sampleRate, *sgOptions.Audio.channels)`.
  - Set `duplicateSoundsMutex.emplace()`, set `gbSndInited = true`, and return cleanly.
  - Eliminate the `Aulib::init` hardware query and the `LogError("Failed to initialize audio (Aulib::init): ...")`.
- [x] In `snd_deinit()`, ensure safe shutdown under `NoOutput` mode with `Aulib::quit()`.
- [x] Build DevilutionX static library (`libdevilutionx.a`).

### Task 2: GDExtension Audio Bridge Rebuild & Verification
- [x] Verify `DiabloBridge::poll_audio_events()` and `DiabloBridge::load_wav_stream()` in `godot_d1_extension/src/diablo_bridge.cpp`.
- [x] Rebuild GDExtension binary (`libdiablo.linux.template_debug.x86_64.so`) with SCons.
- [x] Verify that starting DevilutionX under Godot produces zero "No such audio device" warnings.

### Task 3: Godot 3D Audio Manager & Listener Optimization
- [x] In `godot_d1_3d/scripts/audio_manager.gd`:
  - Enhance `play_sfx()` 3D coordinate mapping to convert Diablo 1 tile offsets to exact Godot 3D world coordinates (`Vector3((dx - dy) * 0.75, 0.5, (dx + dy) * 0.75)` matching `native_3d_sandbox.gd`).
  - Add volume level scaling and distance attenuation curves matching the isometric camera.
- [x] In `godot_d1_3d/scripts/native_3d_sandbox.gd`:
  - Ensure the 3D Camera or Player root holds an active `AudioListener3D`.

### Task 4: Automated Verification Test Suite
- [x] Create headless unit test `godot_d1_3d/test_task53_audio_engine.gd`:
  - Verify `diablo_bridge` starts cleanly without audio device errors.
  - Verify `load_wav_stream` extracts valid `AudioStreamWAV` samples from MPQ (`sfx/items/gold.wav`, `sfx/items/dooropen.wav`).
  - Verify audio event queue polling and dispatch to `audio_mgr`.
  - Verify dual-player music crossfader and 3D positional sound playback.
- [x] Run full test suite to guarantee 100% pass rate.
