#!/usr/bin/env python3
import os
import sys
from PIL import Image

REQUIRED_ASSETS = [
    ("assets/hud/hud_gothic_unified.png", (1400, 240)),
    ("assets/hud/frame_orb_left_stone.png", (200, 200)),
    ("assets/hud/frame_orb_right_stone.png", (200, 200)),
    ("assets/hud/pillar_divider.png", (60, 200)),
    ("assets/hud/slot_frame_gothic.png", (64, 64)),
    ("assets/hud/badge_tab_gothic.png", (24, 14)),
    ("assets/hud/xp_bar_frame.png", (800, 14)),
    ("assets/hud/xp_bar_fill.png", (800, 10)),
]

def main():
    failures = 0
    for rel_path, (min_w, min_h) in REQUIRED_ASSETS:
        if not os.path.exists(rel_path):
            print(f"FAIL: Missing asset {rel_path}")
            failures += 1
            continue
        try:
            im = Image.open(rel_path)
            if im.mode != "RGBA":
                print(f"FAIL: {rel_path} mode is {im.mode}, expected RGBA")
                failures += 1
            elif im.width < min_w or im.height < min_h:
                print(f"FAIL: {rel_path} dimensions ({im.width}x{im.height}) smaller than minimum ({min_w}x{min_h})")
                failures += 1
            else:
                print(f"PASS: {rel_path} ({im.width}x{im.height}, {im.mode})")
        except Exception as e:
            print(f"FAIL: Could not open {rel_path}: {e}")
            failures += 1

    if failures > 0:
        print(f"\n{failures} asset checks FAILED.")
        sys.exit(1)
    else:
        print("\nALL ASSET CHECKS PASSED.")
        sys.exit(0)

if __name__ == "__main__":
    main()
