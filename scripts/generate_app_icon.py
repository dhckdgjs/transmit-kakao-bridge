#!/usr/bin/env python3
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"
ICONSET = ASSETS / "AppIcon.iconset"


def font(path: str, size: int):
    try:
        return ImageFont.truetype(path, size)
    except Exception:
        return ImageFont.load_default()


def rounded(draw, xy, radius, fill, outline=None, width=1):
    draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)


def make_base_icon(size: int = 1024) -> Image.Image:
    scale = size / 1024
    image = Image.new("RGB", (size, size), (28, 33, 40))
    draw = ImageDraw.Draw(image)

    # Opaque full-canvas background. macOS Tahoe adds the outer shape/material,
    # so do not draw a transparent outer card here.
    for y in range(size):
        t = y / max(1, size - 1)
        r = int(24 + 8 * t)
        g = int(30 + 10 * t)
        b = int(38 + 10 * t)
        draw.line((0, y, size, y), fill=(r, g, b))

    # Subtle opaque diagonal depth.
    draw.polygon(
        [(0, 0), (int(190 * scale), 0), (size, int(830 * scale)), (size, size), (int(825 * scale), size), (0, int(178 * scale))],
        fill=(31, 38, 47),
    )

    arial_black = "/System/Library/Fonts/Supplemental/Arial Black.ttf"
    arial_bold = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
    courier = "/System/Library/Fonts/Courier.ttc"

    # Main path panel.
    panel = (
        int(150 * scale),
        int(185 * scale),
        int(874 * scale),
        int(590 * scale),
    )
    rounded(draw, panel, int(76 * scale), (38, 47, 58), (75, 86, 100), max(1, int(3 * scale)))

    path_font = font(courier, int(72 * scale))
    small_font = font(courier, int(42 * scale))
    draw.text((int(220 * scale), int(260 * scale)), "/00", font=path_font, fill=(248, 250, 252))
    rounded(
        draw,
        (int(220 * scale), int(382 * scale), int(784 * scale), int(424 * scale)),
        int(21 * scale),
        (111, 214, 180),
    )
    rounded(
        draw,
        (int(220 * scale), int(475 * scale), int(690 * scale), int(517 * scale)),
        int(21 * scale),
        (244, 205, 71),
    )
    draw.text((int(220 * scale), int(535 * scale)), "path", font=small_font, fill=(213, 221, 230))

    # Chat bubble accent.
    bubble = (
        int(640 * scale),
        int(565 * scale),
        int(850 * scale),
        int(712 * scale),
    )
    rounded(draw, bubble, int(50 * scale), (255, 218, 66))
    tail = [
        (int(700 * scale), int(705 * scale)),
        (int(744 * scale), int(705 * scale)),
        (int(700 * scale), int(772 * scale)),
    ]
    draw.polygon(tail, fill=(255, 218, 66))
    rounded(
        draw,
        (int(693 * scale), int(626 * scale), int(798 * scale), int(653 * scale)),
        int(13 * scale),
        (37, 31, 22),
    )

    # TK mark.
    tk_font = font(arial_black, int(190 * scale))
    text = "TK"
    bbox = draw.textbbox((0, 0), text, font=tk_font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    tx = int((size - tw) / 2)
    ty = int(705 * scale)
    draw.text((tx + int(4 * scale), ty + int(6 * scale)), text, font=tk_font, fill=(0, 0, 0))
    draw.text((tx, ty), text, font=tk_font, fill=(250, 252, 255))

    # Inner highlight for legibility in small sizes.
    highlight_font = font(arial_bold, int(28 * scale))
    draw.text((int(808 * scale), int(816 * scale)), "bridge", font=highlight_font, fill=(166, 178, 190))

    return image


def main():
    ASSETS.mkdir(exist_ok=True)
    ICONSET.mkdir(exist_ok=True)

    base = make_base_icon(1024)
    base.save(ASSETS / "AppIcon-1024.png")

    sizes = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]

    for name, px in sizes:
        base.resize((px, px), Image.Resampling.LANCZOS).save(ICONSET / name)


if __name__ == "__main__":
    main()
