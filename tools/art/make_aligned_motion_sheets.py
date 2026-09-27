#!/usr/bin/env python3
"""Combine the exported action frames into front and side comparison sheets."""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "docs/art/cultivator_aligned_motion_20260927"


def main() -> None:
    for view in ("front", "side"):
        cell_w, cell_h, gap = 360, 480, 10
        width = cell_w * 5 + gap * 6
        height = cell_h * 3 + gap * 4
        sheet = Image.new("RGB", (width, height), (48, 49, 52))
        for row, clip in enumerate(("walk", "run", "jump")):
            for column in range(5):
                source = ART / "frames" / f"{view}_{clip}_{column}.png"
                with Image.open(source) as frame:
                    x = gap + column * (cell_w + gap)
                    y = gap + row * (cell_h + gap)
                    sheet.paste(frame.convert("RGB"), (x, y))
        target = ART / f"{view}_contact_sheet.png"
        sheet.save(target, optimize=True)
        print(target)


if __name__ == "__main__":
    main()
