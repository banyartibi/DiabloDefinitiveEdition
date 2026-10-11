#!/usr/bin/env python3
"""
Diablo: Definitive Edition - Full 4X High-Definition 2.5D PBR Dungeon Pipeline
1. Batch upscales raw dungeon tiles 4X using Real-ESRGAN (4x-UltraSharp) on Vulkan GPU (AMD RX 6800 XT).
2. Generates seamless 4X Delighted Albedo maps.
3. Computes 4X Tangent-Space Normal Maps with embedded Height Map in the Alpha channel (for Parallax Occlusion Mapping).
4. Generates combined PBR ORM Maps (R: Ambient Occlusion, G: Roughness, B: Metallic) and specular maps.
5. Preserves exact 256x128 floor and 256x512 wall piece geometry (Butcher room alignment invariant).
"""

import os
import sys
import shutil
import subprocess
import argparse
from pathlib import Path
from PIL import Image
import numpy as np
import concurrent.futures

def delight_image_4x(img_rgba: Image.Image, is_floor: bool, ref_floor_arr: np.ndarray = None) -> Image.Image:
    arr = np.array(img_rgba, dtype=np.uint8).copy()
    # Zero out fringe bleed from Real-ESRGAN outside the tile diamond
    fringe_mask = arr[:, :, 3] < 64
    arr[fringe_mask] = 0

    alpha = arr[:, :, 3]
    mask = alpha > 128
    if not np.any(mask) or not is_floor:
        return Image.fromarray(arr, mode="RGBA")

    import scipy.ndimage as ndimage
    interior_mask = ndimage.binary_erosion(mask, iterations=4)

    lum = 0.299 * arr[:, :, 0] + 0.587 * arr[:, :, 1] + 0.114 * arr[:, :, 2]
    blood_mask = (arr[:, :, 0] > 60) & (arr[:, :, 0].astype(int) > arr[:, :, 1].astype(int) * 1.5)
    shadow_mask = (lum < 24.0) & interior_mask & (~blood_mask)

    shadow_count = int(np.sum(shadow_mask))
    total_valid = int(np.sum(interior_mask))

    if total_valid > 0 and shadow_count >= 450 and (shadow_count / float(total_valid)) < 0.85:
        if ref_floor_arr is not None and ref_floor_arr.shape == arr.shape:
            arr[shadow_mask] = ref_floor_arr[shadow_mask]
        else:
            valid_lit = interior_mask & (~shadow_mask)
            if np.any(valid_lit):
                lit_mean = float(np.mean(lum[valid_lit]))
                factor = np.clip(lit_mean / np.maximum(lum[shadow_mask], 1.0), 1.0, 2.0)
                for c in range(3):
                    arr[shadow_mask, c] = np.clip(arr[shadow_mask, c] * factor, 0, 255).astype(np.uint8)

    return Image.fromarray(arr, mode="RGBA")

def compute_pbr_maps_4x(img_rgba: Image.Image, bump_strength: float = 1.8):
    arr = np.array(img_rgba, dtype=np.float32)
    rgb = arr[:, :, :3]
    alpha_mask = arr[:, :, 3] >= 64.0
    h, w = alpha_mask.shape

    if not np.any(alpha_mask):
        empty = Image.fromarray(np.zeros((h, w, 4), dtype=np.uint8), mode="RGBA")
        return empty, empty, empty, empty

    lum = (0.299 * rgb[:, :, 0] + 0.587 * rgb[:, :, 1] + 0.114 * rgb[:, :, 2]) / 255.0
    mean_lum = float(np.mean(lum[alpha_mask]))
    lum_filled = lum.copy()
    lum_filled[~alpha_mask] = mean_lum

    # Sobel 3x3 gradients
    kx = np.array([[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]], dtype=np.float32) / 8.0
    ky = np.array([[-1, -2, -1], [0, 0, 0], [1, 2, 1]], dtype=np.float32) / 8.0

    pad_lum = np.pad(lum_filled, ((1, 1), (1, 1)), mode='edge')
    gx = (
        pad_lum[0:h, 2:w+2] * kx[0, 2] + pad_lum[1:h+1, 2:w+2] * kx[1, 2] + pad_lum[2:h+2, 2:w+2] * kx[2, 2] +
        pad_lum[0:h, 0:w] * kx[0, 0] + pad_lum[1:h+1, 0:w] * kx[1, 0] + pad_lum[2:h+2, 0:w] * kx[2, 0]
    )
    gy = (
        pad_lum[2:h+2, 0:w] * ky[2, 0] + pad_lum[2:h+2, 1:w+1] * ky[2, 1] + pad_lum[2:h+2, 2:w+2] * ky[2, 2] +
        pad_lum[0:h, 0:w] * ky[0, 0] + pad_lum[0:h, 1:w+1] * ky[0, 1] + pad_lum[0:h, 2:w+2] * ky[0, 2]
    )

    # 1. Normal Map (RGB)
    scale = bump_strength
    nx = -gx * scale
    ny = -gy * scale
    nz = np.ones_like(nx)

    norm = np.sqrt(nx * nx + ny * ny + nz * nz)
    nx /= norm
    ny /= norm
    nz /= norm

    nr = np.clip((nx * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8)
    ng = np.clip((ny * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8)
    nb = np.clip((nz * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8)

    # 2. Height Map (Normal Alpha channel) for Parallax Occlusion Mapping
    edge_gradient = np.sqrt(gx * gx + gy * gy)
    height = np.clip(lum - edge_gradient * 0.40, 0.0, 1.0)
    height_u8 = (np.clip(height, 0.0, 1.0) * 255.0).astype(np.uint8)
    height_u8[~alpha_mask] = 0

    normal_img = Image.fromarray(np.dstack([nr, ng, nb, height_u8]), mode="RGBA")

    # 3. Ambient Occlusion (AO - R channel of ORM)
    # Cavity darkening in deep mortar lines and crevices
    ao = np.clip(1.0 - (edge_gradient * 2.5), 0.20, 1.0)
    ao = np.clip(ao * np.sqrt(np.clip(lum * 1.5, 0.20, 1.0)), 0.15, 1.0)
    ao_u8 = (ao * 255.0).astype(np.uint8)

    # 4. Roughness (G channel of ORM)
    rough = np.clip(0.95 - (lum * 0.40) + edge_gradient * 0.20, 0.40, 0.98)
    # Wet/blood spots are smoothed
    blood_mask = (rgb[:, :, 0] > 60) & (rgb[:, :, 0] > rgb[:, :, 1] * 1.5)
    rough[blood_mask] = 0.25
    rough_u8 = (rough * 255.0).astype(np.uint8)

    # 5. Metallic (B channel of ORM)
    # High for chains, grates, iron rings, gold coins
    sat = np.max(rgb, axis=2) - np.min(rgb, axis=2)
    metallic = np.zeros_like(lum, dtype=np.float32)
    metal_mask = (lum > 0.60) & (sat < 30.0) & (edge_gradient > 0.15)
    gold_mask = (rgb[:, :, 0] > 180) & (rgb[:, :, 1] > 140) & (rgb[:, :, 2] < 70)
    metallic[metal_mask | gold_mask] = 0.85
    metallic_u8 = (metallic * 255.0).astype(np.uint8)

    mask_u8 = (alpha_mask.astype(np.uint8) * 255)

    # ORM Map: R = AO, G = Roughness, B = Metallic, A = Mask
    orm_img = Image.fromarray(np.dstack([ao_u8, rough_u8, metallic_u8, mask_u8]), mode="RGBA")

    # Roughness Map (legacy / Godot inspect)
    rough_img = Image.fromarray(np.dstack([rough_u8, rough_u8, rough_u8, mask_u8]), mode="RGBA")

    # Specular Map for CanvasTexture.specular_texture
    # Encodes ORM directly: RGB = ORM, Alpha = Shininess/Flatness
    shininess_u8 = (np.clip((1.0 - rough) * 255.0, 10, 240)).astype(np.uint8)
    shininess_u8[~alpha_mask] = 0
    spec_img = Image.fromarray(np.dstack([ao_u8, rough_u8, metallic_u8, shininess_u8]), mode="RGBA")

    return normal_img, orm_img, rough_img, spec_img

def process_single_tile_4x(task):
    raw_4x_file, out_dir, ref_floor_arr = task
    stem = raw_4x_file.stem
    img = Image.open(raw_4x_file).convert("RGBA")
    w, h = img.size
    is_floor = (h <= 128) # 32 * 4 = 128 for floor tiles

    # 1. Delighting
    delit_img = delight_image_4x(img, is_floor=is_floor, ref_floor_arr=ref_floor_arr)
    albedo_path = out_dir / "albedo" / f"{stem}.png"
    albedo_path.parent.mkdir(parents=True, exist_ok=True)
    delit_img.save(albedo_path, "PNG", optimize=True)

    # 2. Normal + Height, ORM, Roughness, Specular
    normal_img, orm_img, rough_img, spec_img = compute_pbr_maps_4x(delit_img, bump_strength=1.8)

    normal_path = out_dir / "normal" / f"{stem}_n.png"
    normal_path.parent.mkdir(parents=True, exist_ok=True)
    normal_img.save(normal_path, "PNG", optimize=True)

    orm_path = out_dir / "orm" / f"{stem}_orm.png"
    orm_path.parent.mkdir(parents=True, exist_ok=True)
    orm_img.save(orm_path, "PNG", optimize=True)

    rough_path = out_dir / "roughness" / f"{stem}_r.png"
    rough_path.parent.mkdir(parents=True, exist_ok=True)
    rough_img.save(rough_path, "PNG", optimize=True)

    spec_path = out_dir / "specular" / f"{stem}_s.png"
    spec_path.parent.mkdir(parents=True, exist_ok=True)
    spec_img.save(spec_path, "PNG", optimize=True)

def run_pipeline(raw_1x_dir: Path, out_hd_dir: Path):
    raw_4x_cache = out_hd_dir / "raw"
    raw_4x_cache.mkdir(parents=True, exist_ok=True)

    print(f"\n=======================================================")
    print(f" Processing: {raw_1x_dir.name} -> {out_hd_dir.name}")
    print(f"=======================================================")

    realesrgan_bin = Path("/home/biti/antigravity/magical-bell/tools/realesrgan/realesrgan-ncnn-vulkan")
    models_dir = Path("/home/biti/antigravity/magical-bell/tools/realesrgan/models")

    raw_1x_files = sorted(list(raw_1x_dir.glob("*.png")))
    existing_4x = list(raw_4x_cache.glob("*.png"))

    if len(existing_4x) < len(raw_1x_files):
        print(f"[1/2] Upscaling {len(raw_1x_files)} tiles with Real-ESRGAN (4x-UltraSharp) on Vulkan GPU...")
        cmd = [
            str(realesrgan_bin),
            "-i", str(raw_1x_dir),
            "-o", str(raw_4x_cache),
            "-m", str(models_dir),
            "-n", "4x-UltraSharp",
            "-s", "4",
            "-f", "png"
        ]
        subprocess.run(cmd, check=True)
    else:
        print(f"[1/2] Using {len(existing_4x)} cached 4x raw tiles.")

    print(f"[2/2] Generating Full PBR Package (Delighting, Normals+Height, ORM, Specular)...")
    ref_path = raw_4x_cache / "piece_1.png"
    ref_floor_arr = np.array(Image.open(ref_path).convert("RGBA")) if ref_path.exists() else None

    raw_4x_files = sorted(list(raw_4x_cache.glob("*.png")))
    tasks = [(f, out_hd_dir, ref_floor_arr) for f in raw_4x_files]

    total = len(tasks)
    with concurrent.futures.ProcessPoolExecutor() as executor:
        for idx, _ in enumerate(executor.map(process_single_tile_4x, tasks)):
            if (idx + 1) % 50 == 0 or idx == total - 1:
                print(f"   Processed {idx + 1}/{total} tiles...")

    # Copy occluders.json if present
    occ_src = raw_1x_dir.parent / "occluders.json"
    if occ_src.exists():
        shutil.copy(occ_src, out_hd_dir / "occluders.json")
        print("   Copied occluders.json.")

    print(f"[✔] Completed PBR package for {out_hd_dir.name} ({total} tiles)")

def main():
    parser = argparse.ArgumentParser(description="Generate 4x HD PBR maps for Diablo 1.")
    parser.add_argument("--theme", type=str, default="all", choices=["all", "town", "cathedral", "catacombs", "caves", "hell"])
    parser.add_argument("--raw-dir", type=str, default="")
    parser.add_argument("--out-dir", type=str, default="")
    args = parser.parse_args()

    base_assets = Path("/home/biti/antigravity/magical-bell/godot_d1_3d/assets")

    if args.raw_dir and args.out_dir:
        run_pipeline(Path(args.raw_dir), Path(args.out_dir))
        return

    themes = {
        "town": (base_assets / "dungeon_pbr_town_raw", base_assets / "dungeon_pbr_town_4x"),
        "cathedral": (base_assets / "dungeon_pbr_cathedral_raw", base_assets / "dungeon_pbr_cathedral_4x"),
        "catacombs": (base_assets / "dungeon_pbr_catacombs_raw", base_assets / "dungeon_pbr_catacombs_4x"),
        "caves": (base_assets / "dungeon_pbr_caves_raw", base_assets / "dungeon_pbr_caves_4x"),
        "hell": (base_assets / "dungeon_pbr_hell_raw", base_assets / "dungeon_pbr_hell_4x"),
    }

    if args.theme == "all":
        for th_name, (raw_d, out_d) in themes.items():
            if raw_d.exists():
                run_pipeline(raw_d, out_d)
            else:
                print(f"[!] Warning: Raw directory {raw_d} does not exist. Skipping {th_name}.")
    else:
        raw_d, out_d = themes[args.theme]
        if raw_d.exists():
            run_pipeline(raw_d, out_d)
        else:
            print(f"[!] Error: Raw directory {raw_d} does not exist.")

if __name__ == "__main__":
    main()
