# ⚔️ Diablo: Definitive Edition – Godot 4 3D Next-Gen Engine

**Diablo: Definitive Edition (D1DE)** is a next-generation hybrid engine that marries the authentic, deterministic logic and gameplay of **DevilutionX** with the modern 3D Vulkan Forward+ rendering pipeline of **Godot Engine 4.7**.

---

## 🌟 Key Features

### 🎮 Native In-Process GDExtension Architecture
* **DevilutionX Core:** High-performance, bug-fixed Diablo 1 gameplay, AI, items, and inventory logic compiled directly in-process via Godot 4.7 GDExtension (`libdiablo.so`), running on a dedicated worker thread with 0 ms IPC latency.
* **Godot 4.7.2 Forward+ Vulkan Renderer:** Fully accelerated 3D scene compositing, dynamic lighting, post-processing, and volumetric atmosphere.
* **3-Mode Display System ([F3]):**
  * **Mode 0:** Classic 2.5D Blit with Tangent-Space 3D Relief & PBR Wet Cobblestone.
  * **Mode 1:** Native Godot 2.5D Engine (Direct Node2D reconstruction, 144Hz smooth camera, front-wall transparency, dynamic PointLight2D, Y-sorted ground loot and corpses).
  * **Mode 2:** Native 3D Sandbox (Procedural 3D dungeon geometry MultiMeshes, animated 3D billboard sprites, Q/E orbit camera & PgUp/PgDn tilt).

### 🔥 3D Next-Gen Visual Enhancements
* **AreaLight3D (Godot 4.7 New Feature):** Soft rectangular area light sources casting cinematic, diffuse amber illumination across dungeon cobblestones and through atmospheric smoke.
* **Procedural 3D Engine Flames & HDR Glow:** Real-time fluid noise fire simulations replacing classic 1996 8-frame torch sprites, radiating blinding HDR bloom into Godot's Forward+ post-processing stack.
* **3D Volumetric Fog:** Multi-layered, density-tuned atmospheric mist and Hellfire smoke drift reacting organically to scene lights.
* **GPUParticles3D:** 3D floating embers, sparks, and dungeon dust drifting dynamically between the camera and playfield.
* **3D Normal Relief & Embossing:** Tangent-space normal mapping giving physical depth, tactile edges, and specular reflections to stone floors, arches, and walls.
* **AMD FidelityFX CAS & 8K Catmull-Rom Splines:** Sub-pixel cubic Hermite vector smoothing and contrast-adaptive sharpening eliminating jagged pixel staircases.

### 🎛️ In-Game Hotkeys & Controls
* **Mouse Scroll Wheel:** Bidirectional in-game zoom:
  * **Scroll UP:** Zoom IN ($1.0\times \to 1.5\times \to 2.0\times \to 2.5\times \to 3.0\times$)
  * **Scroll DOWN:** Zoom OUT ($3.0\times \to 2.5\times \to 2.0\times \to 1.5\times \to 1.0\times$)
* **[F3]:** Cycle Display Modes (Mode 0: Classic Blit / Mode 1: Native 2.5D / Mode 2: Native 3D Sandbox)
* **[F4]:** Toggle V-Sync (Monitor Refresh Rate vs Uncapped Max FPS)
* **[F5]:** Toggle Procedural 3D Engine Torches & HDR Glow
* **[F6]:** Toggle Hero Torch Light
* **[F7]:** Cycle Super-Resolution Upscalers (AMD FSR CAS / Neural Edge / Anime4K / 8K Catmull-Rom Spline / Native)
* **[F8]:** Toggle Real-time FPS Counter
* **[F9]:** Cycle 3D Volumetric Fog Modes (Off / Crypt Mist / Dense Drift)
* **[F10]:** Cycle 3D Color Profiles (Vanilla 1996 / Dark Gothic OLED / Hellish Crimson / Crypt Cyan / Noir)
* **[F11]:** Cycle 3D Surface Relief Modes (Flat / Subtle / Deep 3D / Vector)
* **[F12]:** Toggle Wet Cobblestone Floor PBR Reflections
* **[Q] / [E]:** *(Mode 2)* Camera Orbit Yaw around character
* **[PageUp] / [PgDn]:** *(Mode 2)* Camera Pitch Angle (25° - 75°)
* **[C] / [I] / [Q] / [Tab]:** Modern Diablo IV Character Sheet, Inventory, Quest Log, and Transparent Automap

---

## 📖 Deep Codebase & System Documentation
A complete technical guide covering all C++ bridge methods, thread safety models, GDScript architectures, and shaders can be found in:
👉 **[CODEBASE_DOCUMENTATION.md](file:///home/biti/antigravity/magical-bell/CODEBASE_DOCUMENTATION.md)**

---

## 🚀 Quick Start

### Prerequisites
* Linux (Debian, Ubuntu, Arch, Fedora)
* Vulkan-compatible GPU (e.g. AMD Radeon RX 6000/7000, NVIDIA RTX, Intel Arc)
* Original `diabdat.mpq` (from your legal copy of Diablo 1 or GOG.com) placed in `~/.local/share/diasurgical/devilution/` or the project root.

### Optional HD Sprites & 4X PBR Asset Packs
Pre-upscaled HD sprites (`assets/hd_sprites*`) and 4X PBR dungeon tiles (`assets/dungeon_pbr_*_x4plus`, `_nmkd`, `_omnisr`) are excluded from git and distributed as `.tar.gz` packs under GitHub Release [`assets-v1`](https://github.com/banyartibi/DiabloDefinitiveEdition/releases/tag/assets-v1). To download, SHA-256 verify, and extract all packs into `assets/`:
```bash
./scripts/download_assets.sh
```
For a lighter install without the ~18 GiB hero/legacy player sheets:
```bash
./scripts/download_assets.sh --core-only
```

### Launching the Game
```bash
./run_d1_godot3d.sh
```

---

## 🏗️ Building from Source

To recompile both DevilutionX and the Godot 4.7 GDExtension bridge:
```bash
./build_gdextension.sh
```

---

## 📜 Credits & Licenses
* **DevilutionX Team:** Reverse engineered Diablo 1 engine ([Diasurgical](https://github.com/diasurgical/devilutionX)).
* **Godot Engine:** Open source 2D/3D engine ([Godot Engine](https://godotengine.org)).
* **Blizzard Entertainment:** Original Diablo 1 assets, audio, and game design.
