#!/usr/bin/env python3
"""
Generate Apple-compliant 1024×1024 app icons from Tracky mood assets.

Guidelines applied:
- Square 1024×1024 PNG, RGB (no alpha channel)
- Full-bleed background colour (iOS applies the squircle mask)
- Face scaled to ~86% with safe margins for corner clipping
- Knock out near-black matte from mood PNGs before compositing

Usage:
  python3 tools/app-icons/generate_tracky_app_icons.py
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "Veloseete/Resources/Assets.xcassets"
SIZE = 1024
FACE_SCALE = 0.86
BLACK_THRESHOLD = 42

# Solid backgrounds — readable at home-screen size, aligned with TrackyFace tints.
MOOD_BACKGROUNDS: dict[str, tuple[int, int, int]] = {
    "chill": (0xD9, 0xFC, 0x55),
    "proud": (0xD9, 0xFC, 0x55),
    "fueled": (0xCF, 0xF8, 0x4A),
    "focused": (0x18, 0x1C, 0x18),
    "night": (0x12, 0x16, 0x0E),
    "dawn": (0xE4, 0xFA, 0x98),
    "grit": (0x22, 0x28, 0x22),
    "legend": (0xE0, 0xFF, 0x62),
    "cozy": (0xC6, 0xEA, 0xB6),
}

ALTERNATE_MOODS = [
    "proud",
    "fueled",
    "focused",
    "night",
    "dawn",
    "grit",
    "legend",
    "cozy",
]


def knock_out_black(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if r <= BLACK_THRESHOLD and g <= BLACK_THRESHOLD and b <= BLACK_THRESHOLD:
                px[x, y] = (0, 0, 0, 0)
    return im


def compose_icon(face_path: Path, bg_rgb: tuple[int, int, int], out_path: Path) -> None:
    face = knock_out_black(Image.open(face_path))
    target = int(SIZE * FACE_SCALE)
    face = face.resize((target, target), Image.Resampling.LANCZOS)

    canvas = Image.new("RGB", (SIZE, SIZE), bg_rgb)
    x = (SIZE - target) // 2
    y = (SIZE - target) // 2
    canvas.paste(face, (x, y), face)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out_path, format="PNG", optimize=True)

    # Belt-and-suspenders: strip alpha if any tool reintroduces it.
    flattened = Image.open(out_path).convert("RGB")
    flattened.save(out_path, format="PNG", optimize=True)


def write_appiconset_contents(appiconset: Path, filename: str) -> None:
    contents = {
        "images": [
            {
                "filename": filename,
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024",
            }
        ],
        "info": {"author": "xcode", "version": 1},
    }
    (appiconset / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def main() -> None:
    chill_src = ASSETS / "tracky-chill.imageset/tracky-chill.png"
    primary_out = ASSETS / "AppIcon.appiconset/VeloseeteAppIcon.png"
    compose_icon(chill_src, MOOD_BACKGROUNDS["chill"], primary_out)
    write_appiconset_contents(ASSETS / "AppIcon.appiconset", "VeloseeteAppIcon.png")
    print(f"✓ Primary (chill) → {primary_out}")

    for mood in ALTERNATE_MOODS:
        src = ASSETS / f"tracky-{mood}.imageset/tracky-{mood}.png"
        if not src.exists():
            raise FileNotFoundError(f"Missing mood asset: {src}")
        appiconset = ASSETS / f"AppIcon-{mood}.appiconset"
        out = appiconset / "Icon.png"
        compose_icon(src, MOOD_BACKGROUNDS[mood], out)
        write_appiconset_contents(appiconset, "Icon.png")
        print(f"✓ AppIcon-{mood} → {out}")

    print("\nDone — all icons are 1024×1024 RGB (no alpha).")


if __name__ == "__main__":
    main()
