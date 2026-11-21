#!/usr/bin/env python3
import os
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HUD_DIR = "assets/hud"
os.makedirs(HUD_DIR, exist_ok=True)

def generate_orb_stone_frame(out_path="assets/hud/frame_orb_stone.png", size=(256, 256)):
    """Generate high-res gothic circular stone bezel with cardinal fleur-de-lis / cross accents."""
    w, h = size
    cx, cy = w / 2.0, h / 2.0
    r_outer = w * 0.46
    r_inner = w * 0.355

    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Load base stone texture if available, or generate procedural stone noise
    stone_tex = None
    if os.path.exists("assets/hud/gothic_stone_tile.png"):
        stone_tex = Image.open("assets/hud/gothic_stone_tile.png").convert("RGBA").resize((w, h))

    # Base stone ring mask
    mask = Image.new("L", (w, h), 0)
    d_mask = ImageDraw.Draw(mask)
    d_mask.ellipse([cx - r_outer, cy - r_outer, cx + r_outer, cy + r_outer], fill=255)
    d_mask.ellipse([cx - r_inner, cy - r_inner, cx + r_inner, cy + r_inner], fill=0)

    # Cardinal cross accents at top, bottom, left, right
    accent_r = w * 0.49
    for angle_deg in [0, 45, 90, 135, 180, 225, 270, 315]:
        rad = math.radians(angle_deg)
        is_cardinal = (angle_deg % 90 == 0)
        dist = accent_r if is_cardinal else r_outer * 1.02
        sz = (w * 0.07) if is_cardinal else (w * 0.04)
        ax = cx + dist * math.cos(rad)
        ay = cy + dist * math.sin(rad)
        # diamond accent
        d_mask.polygon([
            (ax, ay - sz),
            (ax + sz * 0.8, ay),
            (ax, ay + sz),
            (ax - sz * 0.8, ay)
        ], fill=255)

    # Draw stone surface
    base_surf = Image.new("RGBA", (w, h), (42, 40, 44, 255))
    if stone_tex:
        base_surf = Image.blend(base_surf, stone_tex, 0.45)

    # Shading and beveling: top-left light, bottom-right shadow
    arr = np.array(base_surf, dtype=np.float32)
    y_coords, x_coords = np.ogrid[:h, :w]
    dx = (x_coords - cx) / r_outer
    dy = (y_coords - cy) / r_outer
    dist_norm = np.sqrt(dx*dx + dy*dy)

    # Bevel highlights
    light_dir_x, light_dir_y = -0.6, -0.8
    dot = (dx * light_dir_x + dy * light_dir_y)
    
    # Ring profile
    ring_profile = np.clip(1.0 - np.abs(dist_norm - (r_inner + r_outer)/(2.0 * r_outer)) * 4.0, 0.0, 1.0)
    shading = 1.0 + 0.35 * dot * ring_profile - 0.25 * (1.0 - ring_profile)
    
    for c in range(3):
        arr[:, :, c] = np.clip(arr[:, :, c] * shading, 0, 255)

    result = Image.fromarray(arr.astype(np.uint8), "RGBA")
    result.putalpha(mask)

    # Add rim outlines for crispness
    overlay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d_over = ImageDraw.Draw(overlay)
    # Outer carved line
    d_over.ellipse([cx - r_outer, cy - r_outer, cx + r_outer, cy + r_outer], outline=(90, 85, 80, 255), width=2)
    # Inner carved line
    d_over.ellipse([cx - r_inner, cy - r_inner, cx + r_inner, cy + r_inner], outline=(20, 18, 20, 255), width=3)
    # Inner gold rim
    d_over.ellipse([cx - (r_inner + 2), cy - (r_inner + 2), cx + (r_inner + 2), cy + (r_inner + 2)], outline=(110, 95, 60, 200), width=1)

    final_orb = Image.alpha_composite(result, overlay)
    final_orb.save(out_path, "PNG")
    print(f"Generated {out_path} ({w}x{h})")

def generate_pillar_divider(out_path="assets/hud/pillar_divider.png", size=(72, 220)):
    """Generate high-res carved gothic stone pillar with capital and base."""
    w, h = size
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Shaft base
    draw.rectangle([6, 20, w - 7, h - 20], fill=(36, 34, 38, 255), outline=(65, 60, 60, 255), width=2)
    
    # Vertical fluting lines
    for fx in [18, 28, 36, 44, 54]:
        draw.line([(fx, 24), (fx, h - 24)], fill=(22, 20, 24, 255), width=2)
        draw.line([(fx + 1, 24), (fx + 1, h - 24)], fill=(65, 62, 65, 180), width=1)

    # Capital at top
    draw.rectangle([2, 4, w - 3, 20], fill=(48, 45, 48, 255), outline=(80, 75, 75, 255), width=2)
    draw.polygon([(0, 4), (w - 1, 4), (w - 8, 0), (7, 0)], fill=(55, 52, 55, 255))
    draw.line([(2, 12), (w - 3, 12)], fill=(20, 18, 20, 255), width=2)

    # Plinth at bottom
    draw.rectangle([2, h - 20, w - 3, h - 4], fill=(48, 45, 48, 255), outline=(80, 75, 75, 255), width=2)
    draw.polygon([(0, h - 4), (w - 1, h - 4), (w - 8, h), (7, h)], fill=(30, 28, 30, 255))
    draw.line([(2, h - 12), (w - 3, h - 12)], fill=(20, 18, 20, 255), width=2)

    # Soft shading
    img = img.filter(ImageFilter.SMOOTH_MORE)
    img.save(out_path, "PNG")
    print(f"Generated {out_path} ({w}x{h})")

def generate_slot_frame(out_path="assets/hud/slot_frame_gothic.png", size=(128, 128)):
    """Generate high-res beveled gothic square slot frame."""
    w, h = size
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Dark background backing
    draw.rounded_rectangle([4, 4, w - 5, h - 5], radius=6, fill=(18, 16, 20, 240))

    # Outer bevel
    draw.rounded_rectangle([2, 2, w - 3, h - 3], radius=6, outline=(75, 68, 62, 255), width=2)
    # Inner bevel
    draw.rounded_rectangle([8, 8, w - 9, h - 9], radius=4, outline=(30, 27, 32, 255), width=2)

    # Metallic highlight top-left
    draw.line([(6, 4), (w - 8, 4)], fill=(120, 110, 95, 220), width=2)
    draw.line([(4, 6), (4, h - 8)], fill=(120, 110, 95, 220), width=2)

    # Dark shadow bottom-right
    draw.line([(8, h - 5), (w - 6, h - 5)], fill=(10, 9, 12, 240), width=2)
    draw.line([(w - 5, 8), (w - 5, h - 6)], fill=(10, 9, 12, 240), width=2)

    # Corner rivet studs
    studs = [(10, 10), (w - 11, 10), (10, h - 11), (w - 11, h - 11)]
    for sx, sy in studs:
        draw.ellipse([sx - 2, sy - 2, sx + 2, sy + 2], fill=(130, 120, 105, 255))
        draw.point((sx - 1, sy - 1), fill=(200, 190, 175, 255))

    img.save(out_path, "PNG")
    print(f"Generated {out_path} ({w}x{h})")

def generate_xp_bar(frame_path="assets/hud/xp_bar_frame.png", fill_path="assets/hud/xp_bar_fill.png", size=(960, 24)):
    """Generate high-res ornamental XP bar frame and amber glowing fill."""
    w, h = size
    # 1. Frame
    f_img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw_f = ImageDraw.Draw(f_img)
    # Background trough
    draw_f.rounded_rectangle([2, 2, w - 3, h - 3], radius=3, fill=(14, 12, 16, 245), outline=(55, 48, 42, 255), width=2)
    # Metallic gold accent rim
    draw_f.line([(6, 3), (w - 7, 3)], fill=(125, 105, 55, 220), width=1)
    # Filigree brackets at ends
    draw_f.polygon([(0, h // 2), (6, 0), (12, h // 2), (6, h)], fill=(95, 80, 48, 255))
    draw_f.polygon([(w, h // 2), (w - 7, 0), (w - 13, h // 2), (w - 7, h)], fill=(95, 80, 48, 255))
    f_img.save(frame_path, "PNG")
    print(f"Generated {frame_path} ({w}x{h})")

    # 2. Fill (Amber / Gold gradient)
    fill_h = h - 6
    fill_img = Image.new("RGBA", (w - 8, fill_h), (0, 0, 0, 0))
    draw_fill = ImageDraw.Draw(fill_img)
    for y in range(fill_h):
        ratio = y / float(fill_h)
        # Deep amber at bottom (180, 95, 10), bright gold in middle (255, 210, 40), intense crest at top (255, 245, 140)
        if ratio < 0.35:
            r = int(255 * (0.8 + 0.2 * (ratio / 0.35)))
            g = int(210 + 35 * (1.0 - ratio / 0.35))
            b = int(40 + 100 * (1.0 - ratio / 0.35))
        else:
            p = (ratio - 0.35) / 0.65
            r = int(255 - 75 * p)
            g = int(210 - 115 * p)
            b = int(40 - 30 * p)
        draw_fill.line([(0, y), (w - 8, y)], fill=(r, g, b, 255))
    fill_img.save(fill_path, "PNG")
    print(f"Generated {fill_path} ({w-8}x{fill_h})")

def generate_hud_console_frame(out_path="assets/hud/hud_gothic_d3_frame.png", size=(1440, 240)):
    """Generate high-res full gothic console frame background."""
    w, h = size
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Main dark backing
    draw.rounded_rectangle([8, 16, w - 9, h - 9], radius=8, fill=(18, 17, 20, 248), outline=(50, 46, 52, 255), width=3)

    # Top cornice rail (for XP bar seating)
    draw.rectangle([6, 12, w - 7, 28], fill=(32, 30, 35, 255), outline=(72, 66, 75, 255), width=2)
    draw.line([(8, 14), (w - 9, 14)], fill=(110, 100, 85, 200), width=1)

    # Texture with stone tile if available
    if os.path.exists("assets/hud/gothic_stone_tile.png"):
        stone = Image.open("assets/hud/gothic_stone_tile.png").convert("RGBA")
        stone_w, stone_h = stone.size
        for x in range(12, w - 12, stone_w):
            for y in range(30, h - 12, stone_h):
                img.paste(stone, (x, y), stone)

    # Outer gothic framing trim
    draw.rounded_rectangle([4, 10, w - 5, h - 5], radius=10, outline=(85, 78, 72, 255), width=2)

    img.save(out_path, "PNG")
    print(f"Generated {out_path} ({w}x{h})")

def main():
    generate_orb_stone_frame()
    generate_pillar_divider()
    generate_slot_frame()
    generate_xp_bar()
    generate_hud_console_frame()
    print("All HD HUD assets successfully generated!")

if __name__ == "__main__":
    main()
