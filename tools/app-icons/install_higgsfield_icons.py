#!/usr/bin/env python3
"""Normalize Higgsfield outputs to 1024×1024 RGB and install into AppIcon sets."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "Veloseete/Resources/Assets.xcassets"
SRC = ROOT / "tools/app-icons/higgsfield-output"
SIZE = 1024

MOODS = [
    "chill",
    "proud",
    "fueled",
    "focused",
    "night",
    "dawn",
    "grit",
    "legend",
    "cozy",
]


def write_contents(appiconset: Path, filename: str) -> None:
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


def normalize(path: Path) -> Image.Image:
    im = Image.open(path).convert("RGB")
    if im.size != (SIZE, SIZE):
        im = im.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    return im


def main() -> None:
    for mood in MOODS:
        src = SRC / f"{mood}.png"
        if not src.exists():
            raise FileNotFoundError(src)
        icon = normalize(src)
        if mood == "chill":
            dest_dir = ASSETS / "AppIcon.appiconset"
            dest = dest_dir / "VeloseeteAppIcon.png"
            write_contents(dest_dir, "VeloseeteAppIcon.png")
        else:
            dest_dir = ASSETS / f"AppIcon-{mood}.appiconset"
            dest = dest_dir / "Icon.png"
            write_contents(dest_dir, "Icon.png")
        dest_dir.mkdir(parents=True, exist_ok=True)
        icon.save(dest, format="PNG", optimize=True)
        print(f"installed {mood} → {dest}")


if __name__ == "__main__":
    main()
