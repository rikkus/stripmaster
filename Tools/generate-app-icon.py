#!/usr/bin/env python3
"""Generate the stripmaster app icon into the asset catalog.

Run with a Python that has Pillow installed. The source artwork is drawn at
4096px and downsampled, which keeps the copper traces and holes crisp at 16px.
"""
from __future__ import annotations

import json
import math
import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Stripmaster" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
SIZE = 4096


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size, size), radius=radius, fill=255)
    return mask


def gradient(size: int) -> Image.Image:
    image = Image.new("RGB", (size, size), (10, 28, 23))
    pixels = image.load()
    assert pixels is not None
    for y in range(size):
        for x in range(0, size, 4):
            t = (x / size) * 0.45 + (y / size) * 0.55
            r = int(8 + 22 * t)
            g = int(30 + 50 * t)
            b = int(24 + 38 * t)
            for dx in range(4):
                if x + dx < size:
                    pixels[x + dx, y] = (r, g, b)
    return image


def draw_board(draw: ImageDraw.ImageDraw, base: Image.Image, box: tuple[float, float, float, float], full_bleed: bool) -> None:
    x0, y0, x1, y1 = box
    # Board shadow.
    if not full_bleed:
        shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        sdraw = ImageDraw.Draw(shadow)
        sdraw.rounded_rectangle(
            (x0 + 40, y0 + 60, x1 + 40, y1 + 60),
            radius=190,
            fill=(0, 0, 0, 150),
        )
        shadow = shadow.filter(ImageFilter.GaussianBlur(55))
        base.alpha_composite(shadow)

    # Board material.
    draw.rounded_rectangle(box, radius=190, fill=(197, 173, 126, 255))
    # A soft warm sheen across the top.
    for index in range(28):
        inset = 24 + index * 5
        alpha = max(0, 22 - index)
        draw.rounded_rectangle(
            (x0 + inset, y0 + inset, x1 - inset, y1 - inset),
            radius=max(12, 170 - inset),
            outline=(255, 240, 200, alpha),
            width=3,
        )
    draw.rounded_rectangle(box, radius=190, outline=(90, 70, 43, 255), width=14)

    rows = 10
    columns = 14
    horizontal_margin = 140
    vertical_margin = 130
    usable_w = (x1 - x0) - horizontal_margin * 2
    usable_h = (y1 - y0) - vertical_margin * 2
    pitch_x = usable_w / (columns - 1)
    pitch_y = usable_h / (rows - 1)

    # Copper strips.
    for row in range(rows):
        y = y0 + vertical_margin + row * pitch_y
        # Deliberate breaks: one cut, and one longer isolated tail.
        for start, end in ((0, 6), (7, columns - 1)) if row in (3, 6) else ((0, columns - 1),):
            left = x0 + horizontal_margin + start * pitch_x - pitch_x * 0.42
            right = x0 + horizontal_margin + end * pitch_x + pitch_x * 0.42
            draw.rounded_rectangle(
                (left, y - pitch_y * 0.30, right, y + pitch_y * 0.30),
                radius=pitch_y * 0.18,
                fill=(202, 126, 57, 255),
            )
            draw.rounded_rectangle(
                (left, y - pitch_y * 0.30, right, y - pitch_y * 0.16),
                radius=pitch_y * 0.10,
                fill=(245, 174, 97, 255),
            )
            draw.rounded_rectangle(
                (left, y + pitch_y * 0.16, right, y + pitch_y * 0.30),
                radius=pitch_y * 0.10,
                fill=(136, 75, 30, 255),
            )

    # Holes.
    for row in range(rows):
        y = y0 + vertical_margin + row * pitch_y
        for column in range(columns):
            x = x0 + horizontal_margin + column * pitch_x
            r = pitch_y * 0.115
            draw.ellipse((x - r - 4, y - r - 4, x + r + 4, y + r + 4), fill=(100, 76, 45, 255))
            draw.ellipse((x - r, y - r, x + r, y + r), fill=(18, 20, 17, 255))
            draw.ellipse(
                (x - r * 0.35, y - r * 0.65, x + r * 0.15, y - r * 0.20),
                fill=(255, 255, 255, 90),
            )

    # A black DIP in the middle-right.
    dip_w = pitch_x * 3.4
    dip_h = pitch_y * 3.0
    dip_x = x0 + horizontal_margin + 8.3 * pitch_x - dip_w / 2
    dip_y = y0 + vertical_margin + 3.8 * pitch_y - dip_h / 2
    draw.rounded_rectangle(
        (dip_x, dip_y, dip_x + dip_w, dip_y + dip_h),
        radius=22,
        fill=(28, 31, 33, 255),
    )
    draw.rounded_rectangle(
        (dip_x, dip_y, dip_x + dip_w, dip_y + dip_h),
        radius=22,
        outline=(8, 9, 10, 255),
        width=8,
    )
    draw.ellipse(
        (
            dip_x + dip_w * 0.13,
            dip_y + dip_h * 0.13,
            dip_x + dip_w * 0.13 + 22,
            dip_y + dip_h * 0.13 + 22,
        ),
        fill=(96, 205, 255, 255),
    )
    for pin in range(4):
        px = dip_x + dip_w * (0.24 + pin * 0.18)
        draw.rectangle((px - 5, dip_y - pitch_y * 0.30, px + 5, dip_y), fill=(205, 210, 216, 255))
        draw.rectangle(
            (px - 5, dip_y + dip_h, px + 5, dip_y + dip_h + pitch_y * 0.30),
            fill=(205, 210, 216, 255),
        )

    # A red cut ring at one broken strip.
    cut_x = x0 + horizontal_margin + 6 * pitch_x + pitch_x / 2
    cut_y = y0 + vertical_margin + 3 * pitch_y
    ring_r = pitch_y * 0.34
    draw.ellipse(
        (cut_x - ring_r, cut_y - ring_r, cut_x + ring_r, cut_y + ring_r),
        outline=(239, 83, 80, 255),
        width=10,
    )
    draw.line(
        (cut_x - ring_r * 0.55, cut_y + ring_r * 0.55, cut_x + ring_r * 0.55, cut_y - ring_r * 0.55),
        fill=(239, 83, 80, 255),
        width=10,
    )

    # A soldered jumper sweeping down the board.
    points = [
        (x0 + horizontal_margin + 1.0 * pitch_x, y0 + vertical_margin + 0.0 * pitch_y),
        (x0 + horizontal_margin + 1.0 * pitch_x, y0 + vertical_margin + 2.0 * pitch_y),
        (x0 + horizontal_margin + 4.0 * pitch_x, y0 + vertical_margin + 2.0 * pitch_y),
        (x0 + horizontal_margin + 4.0 * pitch_x, y0 + vertical_margin + 5.0 * pitch_y),
    ]
    draw.line(points, fill=(226, 230, 235, 255), width=18, joint="curve")
    draw.line(points, fill=(255, 255, 255, 255), width=7, joint="curve")
    for point in (points[0], points[-1]):
        draw.ellipse(
            (point[0] - 30, point[1] - 30, point[0] + 30, point[1] + 30),
            fill=(230, 235, 240, 255),
        )
        draw.ellipse(
            (point[0] - 12, point[1] - 18, point[0] + 2, point[1] - 2),
            fill=(255, 255, 255, 255),
        )


def make_icon(full_bleed: bool) -> Image.Image:
    if full_bleed:
        base = gradient(SIZE).convert("RGBA")
    else:
        base = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        glow = gradient(SIZE).convert("RGBA")
        glow.putalpha(rounded_mask(SIZE, 900))
        base.alpha_composite(glow)

    draw = ImageDraw.Draw(base)
    if full_bleed:
        # A full-bleed field for iOS; iOS masks the corners itself.
        draw_board(draw, base, (470, 800, 3626, 3290), full_bleed=True)
    else:
        # macOS icons carry their own rounded silhouette and transparency.
        draw_board(draw, base, (470, 800, 3626, 3290), full_bleed=False)

    # A vignette and inner edge.
    vignette = Image.new("L", (SIZE, SIZE), 0)
    vdraw = ImageDraw.Draw(vignette)
    vdraw.rectangle((0, 0, SIZE, SIZE), fill=70)
    vdraw.ellipse((-SIZE * 0.2, -SIZE * 0.2, SIZE * 1.2, SIZE * 1.2), fill=0)
    shade = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shade.putalpha(vignette.filter(ImageFilter.GaussianBlur(180)))
    base.alpha_composite(shade)

    draw = ImageDraw.Draw(base)
    if not full_bleed:
        draw.rounded_rectangle((0, 0, SIZE, SIZE), radius=900, outline=(255, 255, 255, 38), width=10)
    else:
        # Keep a little dark edge under the iOS system mask.
        draw.rounded_rectangle((0, 0, SIZE, SIZE), radius=940, outline=(255, 255, 255, 24), width=8)
    return base


def write_images() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    ios_master = make_icon(full_bleed=True)
    mac_master = make_icon(full_bleed=False)

    ios_sizes = {
        "icon-ios-1024.png": 1024,
        "icon-ios-180.png": 180,
        "icon-ios-167.png": 167,
        "icon-ios-152.png": 152,
        "icon-ios-120.png": 120,
        "icon-ios-87.png": 87,
        "icon-ios-80.png": 80,
        "icon-ios-76.png": 76,
        "icon-ios-60.png": 60,
        "icon-ios-58.png": 58,
        "icon-ios-40.png": 40,
        "icon-ios-29.png": 29,
        "icon-ios-20.png": 20,
    }
    for name, px in ios_sizes.items():
        ios_master.resize((px, px), Image.Resampling.LANCZOS).save(OUT / name)

    mac_sizes = {
        "icon-mac-16.png": 16,
        "icon-mac-32.png": 32,
        "icon-mac-64.png": 64,
        "icon-mac-128.png": 128,
        "icon-mac-256.png": 256,
        "icon-mac-512.png": 512,
        "icon-mac-1024.png": 1024,
    }
    for name, px in mac_sizes.items():
        mac_master.resize((px, px), Image.Resampling.LANCZOS).save(OUT / name)

    images = [
        {"idiom": "mac", "scale": "1x", "size": "16x16", "filename": "icon-mac-16.png"},
        {"idiom": "mac", "scale": "2x", "size": "16x16", "filename": "icon-mac-32.png"},
        {"idiom": "mac", "scale": "1x", "size": "32x32", "filename": "icon-mac-32.png"},
        {"idiom": "mac", "scale": "2x", "size": "32x32", "filename": "icon-mac-64.png"},
        {"idiom": "mac", "scale": "1x", "size": "128x128", "filename": "icon-mac-128.png"},
        {"idiom": "mac", "scale": "2x", "size": "128x128", "filename": "icon-mac-256.png"},
        {"idiom": "mac", "scale": "1x", "size": "256x256", "filename": "icon-mac-256.png"},
        {"idiom": "mac", "scale": "2x", "size": "256x256", "filename": "icon-mac-512.png"},
        {"idiom": "mac", "scale": "1x", "size": "512x512", "filename": "icon-mac-512.png"},
        {"idiom": "mac", "scale": "2x", "size": "512x512", "filename": "icon-mac-1024.png"},
        {"idiom": "iphone", "scale": "2x", "size": "20x20", "filename": "icon-ios-40.png"},
        {"idiom": "iphone", "scale": "3x", "size": "20x20", "filename": "icon-ios-60.png"},
        {"idiom": "iphone", "scale": "2x", "size": "29x29", "filename": "icon-ios-58.png"},
        {"idiom": "iphone", "scale": "3x", "size": "29x29", "filename": "icon-ios-87.png"},
        {"idiom": "iphone", "scale": "2x", "size": "40x40", "filename": "icon-ios-80.png"},
        {"idiom": "iphone", "scale": "3x", "size": "40x40", "filename": "icon-ios-120.png"},
        {"idiom": "iphone", "scale": "2x", "size": "60x60", "filename": "icon-ios-120.png"},
        {"idiom": "iphone", "scale": "3x", "size": "60x60", "filename": "icon-ios-180.png"},
        {"idiom": "ipad", "scale": "1x", "size": "20x20", "filename": "icon-ios-20.png"},
        {"idiom": "ipad", "scale": "2x", "size": "20x20", "filename": "icon-ios-40.png"},
        {"idiom": "ipad", "scale": "1x", "size": "29x29", "filename": "icon-ios-29.png"},
        {"idiom": "ipad", "scale": "2x", "size": "29x29", "filename": "icon-ios-58.png"},
        {"idiom": "ipad", "scale": "1x", "size": "40x40", "filename": "icon-ios-40.png"},
        {"idiom": "ipad", "scale": "2x", "size": "40x40", "filename": "icon-ios-80.png"},
        {"idiom": "ipad", "scale": "1x", "size": "76x76", "filename": "icon-ios-76.png"},
        {"idiom": "ipad", "scale": "2x", "size": "76x76", "filename": "icon-ios-152.png"},
        {"idiom": "ipad", "scale": "2x", "size": "83.5x83.5", "filename": "icon-ios-167.png"},
        {"idiom": "ios-marketing", "scale": "1x", "size": "1024x1024", "filename": "icon-ios-1024.png"},
    ]
    contents = {"images": images, "info": {"author": "xcode", "version": 1}}
    (OUT / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


if __name__ == "__main__":
    write_images()
    print(f"Wrote app icon assets to {OUT}")
