# 📊 Status Update – Diablo 1: Resurrected (D1R)

**Datum:** 2026-09-12 · **Hely:** `/home/biti/antigravity/magical-bell`

Ez a dokumentum a teljes kódátvizelés alapján írja le, hogy áll a fejlesztés:
mi kész, mi van vissza. Áttekintés: ~10 500 sor GDScript + ~4 100 sor C++ (bridge),
3 megjelenítési mód (F3): Mode 0 = Classic Blit, Mode 1 = Native Godot 2.5D, Mode 2 = Native 3D Sandbox.

---

## 🟢 Átvilágító: általános állapot

| # | Feladat | Állapot | Becsültés |
|---|---|---|---|
| **Task 1** | DevilutionX C++ + Godot Vulkan megjelenés extra tuningokkal | ✅ **Működik, ~98%** – Esc→Save Game valós játékmenetben is verifikálva | 98% |
| **Task 2** | Godot native 2.5D – lépcsézetes átültetés | 🟢 **Nagy előrehaladás** – megjelenés, PBR, árnyékok és UI rétegek készek; a logika még C++-on | ~85% |
| **Task 3** | Godot 3D megjelenítés (Sandbox) | ✅ **Fejlett 3D Sandbox, ~90%** – Unifikált 4X PBR billboard scenery, interaktív props, szintváltás-izoláció és hősies skálázás | 90% (sandbox) |
| **Task 4** | Minden átültetése 3D-be | ⬜ **Nem kezdett el – a legnagyobb maradvány** | 0% |

A hibrid architektúra (DevilutionX in-process GDExtension + Godot Forward+ Vulkan) **teljesen működik**:
friss build létezik (`libdiablo.linux.template_debug.x86_64.so`),
headless ellenőrzés tiszta indítás/frame-stream/SIGTERM exit-0.

---

## 🆕 Fázis-2: Hotkey-eltávolítás + Pause-menu Settings (2026-09-16)

| # | Munka | Állapot |
|---|---|---|
| 1 | "Settings" → **Game Settings** (HU: JÁTÉK BEÁLLÍTÁSOK, EN: GAME SETTINGS) – főmenü + dialog header | ✅ |
| 2 | Új **„Resurrected”** sub-menu a Game Settings-ben: rebindable key binding (type-4 KeyCapture), Rebind capture UI, diablo.ini persisted | ✅ |
| 3 | **7 effect hotkey eltávolítva** (F9/F10/F11/F12 + Ctrl/Alt variantok) – a settings kizárólag az ESC pause menu Options paneljából állíthatók | ✅ |
| 4 | Mode switch binding: **Ctrl+F12** default, rebindable + ini-persisted (Godot physical keycode + modifier mask) | ✅ |
| 5 | Pause menu (ESC → Options) új sorok: Soft Torchlight, Atmospheric Fog, Color Profile, Engine HDR Glow, Upscaler, 3D Surface Relief, Wet Floor + Display Mode switch + V-Sync ON/OFF + Show FPS ON/OFF – mind kizárólag menüvezreléssel | ✅ |
| 6 | **Build fix:** `OptionEntryKeyCapture` LoadFromIni/SaveToIni átkelve `options.cpp`-be (a header-ben lévő inline bodies a buildet tönkretették) + diablo_bridge bindings hex-verifikálva | ✅ |

**Build:** `ninja -C DevilutionX/build` + `./build_gdextension.sh` – **sikerrel**. Byte-scan: searc=0 mindenhol,
„switch” helyesen írva; GDScript parse-check (`godot --headless --check`) tiszta mind a 3 módosított scripten.

**Következő:** az új build-lel (`./run_d1_godot3d.sh`) futatott játékban verifikálni:
- ESC → Options: a 7 Resurrected toggle + Display Mode cycle + V-Sync/Show FPS ON/OFF működik;
- Game Settings → Resurrected: mode switch rebind (Rebind button) új binding beállítva ini-be;
- Ctrl+F12 (vagy a rebindelt kombináció) mode switch in-game + main menüben.

Minden verifikálva után commit + push (a felhasználó kéri).

---

## 🆕 Fázis-3: Resurrected Combat VFX – Mode 1-ben is (2026-09-21)

| # | Munka | Állapot |
|---|---|---|
| 1 | **Resurrected Effects ON/OFF** toggle a Pause menu Options panelben (`native_modal_layer.gd` sor) + DevilutionX `Resurrected` options kategóriájának új bool bejegyeje: `resurrectedEffects` (default true, diablo.ini persisted) | ✅ |
| 2 | **Mode 1 Native Godot 2.5D Combat VFX**: vér-spritz (`GPUParticles2D`, canvas_item teardrop shader), csontszilánkok (undead/kő szörnyek), fireball explosion (fractal flame tongues) – tile→world mapping `((x−y)*32, (x+y)*16+16)`, Y-sorting a `world_root`-ban, intenzitáskal + secondary gore burst | ✅ |
| 3 | **C++ gate**: `PushVisualEvent()` early return, ha `resurrectedEffects == false` – minden display mode-ban hat; diablo.ini persist + élő update (újraindítás nélkül) | ✅ |

**Build:** `./build_gdextension.sh` + Godot headless import tiszta (3 canvas_item shader compila, PlaneMesh scenes OK).

**Re-verification (2026-09-21, second agent):** ✅ Clean build (`ninja: no work to do`, core + GDExtension), clean headless import (new `*_2d.tscn` scenes & 3 canvas_item shaders valid resources), és `--check-only` parse-check tiszta a 3 érintett scripten (`one_shot_particles_2d.gd`, `native_25d_view.gd`, `native_modal_layer.gd`). A C++ gate (`PushVisualEvent()` → render_bridge.cpp ~L1108) és az Options row (native_modal_layer.gd L313-614) helyén.

---

## 🆕 Fázis-4: Natív 3D Sandbox & PBR Billboarding, Teleport/Szintváltás Isoláció, Crash Védelem és Skálázás (2026-10-11)

| # | Munka | Állapot |
|---|---|---|
| 1 | **Unifikált 3D Billboard Scenery (Mode 2)**: Moduláris tégla dobozok/piramisok teljes lecserélése autentikus 4X PBR billboard szcenikára minden dungeon témában (Cathedral, Catacombs, Caves, Hell) és Faluban (L0). 100% tömör diamond padló mesh (`transparency = TRANSPARENCY_DISABLED`, +2.5% peremátfedés a fekete rácsvonalak ellen). Párhuzamos kamera-forgatás (orbitingkor minden tereptárgy és fal együtt fordul a kamerával, megszüntetve a fűrészfogas/domínó hatást). | ✅ |
| 2 | **Interaktív 3D Tereptárgyak & Világítás**: Könyvtartók (OBJ_BOOKSTAND), ládák, szarkofágok, hordók, fali fáklyák, álló tüzek, szentélyek teljes bekötése és renderelése 3D-ben. | ✅ |
| 3 | **Szintváltás & Teleport Isoláció (Barlang → Falu)**: Szint szerint kulcsozott gyorsítótárak (`floor_material_cache`, `base_floor_texture_cache`, `scenery_texture_cache`, `scenery_special_cache` kulcsa: `cur_level_piece_id`), megszüntetve a barlangi láva és falu földút azonosítók ütközését (GEMINI.md Rule #1). Azonnali szintváltás detektálás a `_process()`-ben és teljes jelenet-tisztítás (`_on_level_changed()`). Falu (L0) szigorúan védve dungeon PBR és CEL boltívek ellen (Rule #1 & Rule #2). | ✅ |
| 4 | **C++ Crash / SIGSEGV Védelem Szintváltáskor**: `FreeMonsters()` és `FreeTownerGFX()` memóriafelszabadítás után explicite `std::nullopt`-ra nullázza a sprite mutatókat, kizárva a dangling pointereket. `GetMonsterSpriteRgba` és `GetActiveMonstersData` szigorú null/határ/transition védelmet kapott (`g_D1LevelTransitioning.load()`, `ownedAnim.has_value()`, `anim.has_value()`, `m.hitPoints > 0 || mode == Death`). | ✅ |
| 5 | **Karakter- és Tárgyskálázás Finomhangolása**: Varázslás/skill cast közbeni miniatűr méret javítva (`sw > 120` téves HD flag törölve; live sprite mindig `PIXEL_SIZE_1X`). Hősies kiegyensúlyozott méret (`ENTITY_SCALE_MULT = 1.15`). Földön heverő loot 4X HD textúrával (`hd_sprites_x4plus/items/`, `hd_sprites/items/`), +75% méretbónusszal (`item_scale_boost = 1.75`) és 20pt lebegő címkével, kiváló olvashatóságot biztosítva az overhead kamerából. | ✅ |
| 6 | **Automatizált Regressziós Tesztek**: `test_teleport_and_scaling_fixes.gd`, `test_5_user_fixes.gd`, `test_unified_3d_scenery.gd` és `test_town_and_modes.gd` mind 100% PASS! | ✅ |

---

## Task 1 – DevilutionX + Godot Vulkan (extra tuning)

### ✅ Kész és működik
- **In-process GDExtension**: a DevilutionX C++ core közvetlenül a `libdiablo.so`-ban fut
  (`DiabloBridge.init_engine()` → `g_DiabloThread`), SHM legacy kód csupán fallback (run script öli
  standalone processzeket – „single executable” politika betartva).
- **Mode 0 Classic Blit + teljes extra tuning** (`d1_3d_material.gdshader`, ~600+ sor GLSL):
  - Tangent-space normal relief ([F11], 5 mód: flat→extreme) – fragment-level luminance-gradiensből.
  - HDR Glow/Bloom ([F5]: off/1x/2x/3x), Wet Cobblestone PBR tükröződés ([F12]).
  - Felskálázók ([F7]): AMD FidelityFX CAS, Neural Edge Push, Anime4K Thin Lines, 8K Catmull-Rom spline, Native.
  - Volumetrikus köd ([F9]: Off/Crypt Mist/Dense Drift), Színprofilok ([F10]: Vanilla/OLED/Crimson/Cyan/Noir).
  - 5-step egérgörgő zoom (1.0x→3.0x), FPS counter ([F8]), V-Sync toggle ([F4]).
- **Stability fixek (2026 szeptember)**:
  - Indítási SIGABRT root cause (InitGodotBridge/Cleanup race) javítva + SIGINT/SIGTERM handler thread join-nal.
  - Esc→Save Game SIGABRT: minden void mutátor `PushBridgeAction`-ra irányul, drain without-lock pattern.
  - Párhuzamos SDL/heap verseny megszüntetve (14 sorbaűzett mutátor).
- **Esc→Save Game élő verifikálása – RENDBEN**: valós játékmenetben egy mentés végső ellenőrzése megtörtént
  (New Game → dungeon → Esc → Save), fagyás/abort nélkül.

### 🔶 Maradvány
| Előny | Szint | Megjegyzés |
|---|---|---|
| Audió teardown hiba | 🔴 | `Aulib::init` / SDL2↔SDL3 „No such audio device” sandboxban – **megvizsgálatlan**, külön feladat |
| `[D1-DEBUG]` printek | 🟡 | `bridge_receiver.gd` `_dbg_frame_updates` debug nyomozás aktív – productionra eltávolítandó |

---

## Task 2 – Godot Native 2.5D (lépcsézetes)

### Step 1: Először csak megjelenés → ✅ **Kész (100%)**
Mode 1 (`native_25d_view.gd`, 1180 sor):
- Dungeon DPieces rács + Special CELs (boltívek, ajtónyílások, oszlopfejek) kinyerése és izometrikus elhelyezés.
- Frontwall átlátszóság autentikus `dTransVal` / `GetTransList()` alapján.
- Per-tile megvilágítás: dLight rács + Hermite smoothstep interpoláció (éles tile-határ eltűnt).
- Player sprite simított pozíció (`get_player_continuous_pos`) + Y-sorting foot-depth key-szel.
- Animált szörnyek, loot (ritkaság-színes labels), corpses, missiles/spells – mind natív Node2D-ként.
- PointLight2D torch pool + 144Hz Camera2D lerped tracking + zoom steps.

### Step 2: Fokozatos funkcióátültetés → 🔶 **Folyamatban (~75–80%)**
Kész részek (mind natív Godot UI, bridge-adatból):
- **Native Modal Layer** (`native_modal_layer.gd`, 775 sor): Esc gamemenu, NPC dialog/store (árazás),
  death-restart menu, quest qtext + Continue, **Options Panel** (music/sound/gamma/speed sliders + Godot Brightness).
- **Diablo IV HUD** (`diablo4_hud.gd` + 5 subpanel):
  - Health/Mana globes (liquid_globe shader), XP bar, level-up banner.
  - Action bar / belt 8 slot – italok auto-felismerése (HEAL/MANA/REJUV/scroll).
  - Character Sheet ([C]) + stat pont elosztás (`add_attribute_point`).
  - Inventory ([I]): paperdoll equipment + 40-slot backpack, tooltip ritkaság-színekkel.
  - Quest Log ([Q]), Spellbook (tab pages), Stash (page nav + withdraw gold) – mind bridge-kötésű.
- **Audio Manager**: crossfade zenek (2 AudioStreamPlayer), spatial SFX pool (24 AudioStreamPlayer3D).

**Nem kész / C++-on marad (ez a core maradvány):**
- A játékkép logika (AI, items, spells, inventory, RNG) **még DevilutionX C++-ban fut**; Godot csak renderel.
  Mode 1 input routing: mouse world→screen mapping → `send_input()` → C++ motor feldolgoza. Ez by design a hybrid fázisban,
  de „fokozatos átültetés” alatt az **egyik legfontosabb következő lépés**, hogy ezeket a logika-elemeket natív Godot-ba vigyük (pl. inventory/quest/spell UI-hoz már bridge-kapcsolat van).
- Mode 1 **shadow casting**: ✅ **KÉSZ** – Valósághű 2.5D dinamikus sziluett-vetítés (`realistic_25d_shadow.gdshader`), 9-tap Gaussian penumbra + kontakt-árnyék; fali fáklyák dinamikus `PointLight2D` poolja meleg villódzással; **vonalas gerinc-okklúderek** (`occluders.json`), amelyek hibátlanul zárják a fényt a sötét szobák felé, de nem vágnak semmilyen merev csíkot vagy kockát a padlóra.

### Step 3: Normálmap + modern fények/árnyékok → 🟢 **Kész (100%)**
- Mode 0: fragment-level normal relief + wet PBR – **kész** shader-ben.
- Mode 1:
  - **Offline PBR Textúrák & Delighting**: Teljes 224 elemes Cathedral csempekészlet (Normal + Roughness + Delighted Albedo). Az 1996-os beégetett mesterséges fekete árnyékok és halo effektusok automatikus inpaintinggel és normálvektor-generálással felváltva.
  - **Folytonos GPU Bilineáris Lightmap**: A `d2r_25d_pbr.gdshader`-ben hardveres 112×112 R8 szűrés pixel-szintű izometrikus mintavételezéssel, Hermite smoothstep falloff-fal és mély gótikus kripta-ambient sötétítéssel (`mix(dungeon_ambient, light_tint, factor)`).
  - **Dinamikus 2.5D Sziluett-Árnyékok**: Hős és szörnyek vetített árnyékai 9-tap Gaussian penumbra elmosással és láb-kontakt sötétítéssel (`realistic_25d_shadow.gdshader`).
  - **Dinamikus Fáklyák & Gyertyák**: PointLight2D fényforrások köbös Hermite csillapítással (`attenuation`), éles négyszögletes doboz-hatás nélkül.
  - **Tereptárgy Sötétség-kezelés & Culling**: Ajtók (4 szomszédos csempe mintavételezéssel), ládák, hordók, szarkofágok (2 csempés mintavételezéssel) és a földön heverő tárgyak címkéi a felderítetlen sötétségben rejtettek.
- Mode 2 (3D): Megosztott PBR textúrák a natív 3D padló- és falmodellekhez – **kész**.

### Step 4: AI grafika + elemcsere (pl. HUD & HD Sprite/Csempe Pipeline) → 🟢 **Kész (~95%)**
- ✅ **HUD art cserélve**: `assets/hud`-ban gótikus PNG-k – frame_angel/frame_gargoyle panel, potion ikonok
  (heal/mana/oil/rejuv), scroll/skill/slot frame, center bar – mind modern Diablo IV stílusú.
- ✅ **AI upscaler tool**: `tools/upscale_sprites_ai.py` (Lanczos 4x + Unsharp Mask + contrast) +
  `tools/realesrgan/` Real-ESRGAN (4x-UltraSharp Vulkan) pipeline.
- ✅ **4x HD PBR Dungeon csempekészlet**: `tools/generate_hd_dungeon_pbr.py` automatizációval mind a 293 raw csempe 4x felskálázva (`assets/dungeon_pbr_4x/`: 256x512 Albedo, Normal, Roughness és Specular térképek), subpixel igazítással és automatikus mipmap generálással.
- ✅ **Hellfire kiegészítő teljes lefedettség & Lebegésmentes Horgonyzás**: Minden DevilutionX/Hellfire kaszt (Szerzetes/Monk, Barbár, Bárd, Harcos, Íjász, Mágus) és szörny közvetlen élő C++ sprite-streamet használ (`GetPlayerSpriteRgba()`, `GetMonsterSpriteRgba()`), pontos izometrikus talajhorgonyzással (`offset = Vector2(0, -sh * 0.5)`, `scale = Vector2(1.0, 1.0)`), megszüntetve a lebegést és a hibás harcos kaszt kényszerítést.
- ✅ **GPU Neurális Szuper-Felbontás Shader (`entity_hd_upscaler.gdshader`)**: Valós idejű Neural Edge Push kontúregyenesítés, AMD FidelityFX CAS élesítés és szubpixel alpha simítás minden karakterre, Hellfire szörnyre, tereptárgyra (ládák, szarkofágok, hordók, ajtók), földön heverő zsákmányra és varázslat-lövedékre.
- ✅ **Élő Options Menü Váltókapcsoló**: Mode 1-ben az Esc -> Options alatt a "Visuals: Resurrected 4x HD / Authentic 1996" gombbal azonnal, játék közben újraindítás nélkül váltható a retro pixel-art és a modern 4x simított HD látvány (szűrés váltás: NEAREST vs LINEAR_WITH_MIPMAPS, shader bypass vs CAS/Edge Push, 1x vs 4x PBR csempék).

### Step 5: DevilutionX teljes elhagyása → ⬜ **Nem kezdett el (0%)**
- A játék logika (AI, items, spells, inventory, RNG) **még mindig C++-on fut**; Godot jelenleg csak renderel.
- Ez a **legnagyobb maradvány**: az „már ne is számoljon” célállapot – minden gameplay-elem natív Godot-ba kerül.

---

## Task 3 – Godot 3D megjelenítés (Sandbox)

### ✅ Sandbox szinten kész (~80%)
`native_3d_sandbox.gd` (755 sor):
- Procedurális BoxMesh MultiMeshes: padlók/falak/ajtók a szilárdság-rács (`get_dungeon_solidity_grid`) alapján, PBR StandardMaterial + NoiseTexture procedural normal.
- Billboard Sprite3D player + monsters: HP gradient bar (zöld→sárga→piros), Label3D name.
- Kamera: Q/E orbit ±15°, MMB drag, PgUp/PgDn pitch 25–75°, wheel zoom 6–22 m, Home/R reset.
- Raycasting input: `camera.project_ray` → Plane intersect → `world_3d_to_tile()` → `send_input()`.

### 🔶 Sandbox korlátok (production-re)
| Maradvány | Szint |
|---|---|
| Nincs authort 3D asset/mesh/material – minden code-generálva, BoxMesh dobozok helyett | 🟡 |
| Monsters cleanup: `visible=false` helyett nem free-el (small leak risk) | 🔴 |
| Debug printek a rebuild function-ban | 🟡 |
| Fallback default position („pos_x=25”) – nem production-ready | 🟡 |

---

## Task 4 – Minden átültetése 3D-be

### ⬜ Nem kezdett el (0%)
- **Nem létező**: production 3D asset pipeline, authored wall/door/castle mesh material.
- Mode 2 most is BoxMesh + billboard sprites – nem real 3D modellek.
- Mode 2 **nincs** dedicated lighting/shadow system; a World Environment alapérték.
- A teljes gameplay logika C++-on marad – ez a Task 4 fő maradvány, és a Task 2 Step 5 is ugyanazt az irányt jelenti.

---

## 📋 Nyitott kérdések / Maradvány list (prioritási sorrendben)

- ~~Esc→Save Game élő verifikálása~~ – **RENDBEN / KÉSZ** ✅ (valós játékmenetben egy mentés végső ellenőrzése megtörtént, fagyás/abort nélkül)
- ~~Shadow casting & PBR világítás implementáció~~ – **KÉSZ Mode 1-ben** ✅ (Valósághű 2.5D sziluett-vetítés, lágy 9-tap Gaussian penumbra + kontakt-sötétítés, PCF13 fal-okklúderek, dinamikus fáklyafények, folytonos GPU lightmap).
- ~~AI-upscaled sprite & 4x PBR csempék integrálása~~ – **KÉSZ Mode 1-ben** ✅ (4x UltraSharp PBR csempék, HD harcos/szörny pipeline, élő Options váltókapcsoló, automatikus mipmapok).

1. **Audió teardown hiba** (`Aulib::init` / SDL2↔SDL3 „No such audio device”) – megvizsgálatlan, külön feladat a sandboxban.
2. **Task 2 Step 5: DevilutionX teljes elhagyása** – gameplay logika natív Godot-ba (inventory/quest/spell/AI) – **legnagyobb maradvány**.
3. **Task 3 → Task 4**: production 3D asset pipeline + real mesh material + Mode 2 lighting/shadow system + full logic migration to 3D.

### Kisebb cleanup
- `[D1-DEBUG]` printek eltávolítása (`bridge_receiver.gd` `_dbg_frame_updates`) – productionra.
- `native_3d_sandbox.gd`: monsters free-el (visible=false helyett) + debug printek eltávolítása.
- Spellbook/Stash `.tscn` missing `.uid` files – minor inconsistency, de Godot import nem probléma.

---

## 📊 Összegzés

| Feladat | Állapot | Becsültés |
|---|---|---|
| **Task 1** (DevilutionX + Godot Vulkan) | ✅ Működik – Esc→Save Game valós játékmenetben is verifikálva | ~98% |
| **Task 2 Step 1** (Először csak megjelenés) | ✅ Kész | 100% |
| **Task 2 Step 2** (Fokozatos funkcióátültetés) | 🔶 Folyamatban – UI/Modal/HUD kész, logika C++-on | ~75–80% |
| **Task 2 Step 3** (Normálmap + fények/árnyékok) | ✅ Kész – Teljes PBR csempekészlet, folytonos GPU fény, 2.5D árnyékok | 100% |
| **Task 2 Step 4** (AI grafika + elemcsere) | ✅ Kész – 4x HD csempék, HD sprite pipeline, élő Options váltó | ~95% |
| **Task 2 Step 5** (DevilutionX elhagyása) | ⬜ Nem kezdett el | 0% |
| **Task 3** (Godot 3D – Sandbox) | ✅ ~90% – Unifikált 4X PBR billboard scenery, interaktív 3D props, szintváltás-izoláció és hősies skálázás | ~90% (sandbox) |
| **Task 4** (Minden átültetése 3D-be) | ⬜ Nem kezdett el – a legnagyobb maradvány | 0% |

A fejlesztés jelenleg **Task 2 Step 5-re** fókuszál: a gameplay logika natív Godot-ba való átvitele. A Task 3/4 (production 3D) az utolsó nagy fázis.
