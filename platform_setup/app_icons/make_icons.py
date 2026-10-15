#!/usr/bin/env python3
"""Generate the Nearlink app icon at every size the platforms need.

The mark matches the in-app brand: a lime rounded square with a dark green
navigation arrow (the same glyph the sidebar uses). Three renders are produced,
because the platforms want different things:

  rounded  - rounded square, transparent corners  (Android legacy, macOS)
  square   - full-bleed opaque square             (iOS)
  glyph    - the arrow alone on transparency      (Android adaptive foreground)

Run it from anywhere:

    python3 platform_setup/app_icons/make_icons.py

Then install the result:

    python3 platform_setup/app_icons/install_icons.py
"""

import os
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:
    sys.exit("Pillow is required:  python3 -m pip install pillow")

HERE = os.path.dirname(os.path.abspath(__file__))

LIME = (200, 241, 74, 255)   # C8F14A
DARK = (24, 59, 48, 255)     # 183B30
LIME_HEX = "#C8F14A"

MASTER = 1024
RESAMPLE = getattr(Image, "Resampling", Image).LANCZOS

# The arrow, in a unit box centred on the origin, pointing up and to the right.
ARROW = ((0.40, -0.44), (-0.46, 0.04), (-0.04, 0.46))


def _arrow_points(size, span, cx=None, cy=None):
    """Map the unit arrow onto a canvas, so it spans `span` of the width."""
    cx = size / 2 if cx is None else cx
    cy = size / 2 if cy is None else cy
    scale = span / 0.92
    return [(cx + px * scale * size, cy + py * scale * size) for px, py in ARROW]


def render_rounded(size=MASTER, radius_frac=0.225, inset=0.0, span=0.60):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    pad = int(size * inset)
    radius = int(size * radius_frac)
    draw.rounded_rectangle(
        [pad, pad, size - 1 - pad, size - 1 - pad],
        radius=radius,
        fill=LIME,
    )
    draw.polygon(_arrow_points(size, span * (1 - 2 * inset)), fill=DARK)
    return img


def render_square(size=MASTER, span=0.60):
    img = Image.new("RGBA", (size, size), LIME)
    ImageDraw.Draw(img).polygon(_arrow_points(size, span), fill=DARK)
    return img


def render_glyph(size=MASTER, span=0.56, colour=DARK):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(img).polygon(_arrow_points(size, span), fill=colour)
    return img


def scaled(master, size):
    return master.resize((size, size), RESAMPLE)


def write(img, *parts):
    path = os.path.join(HERE, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    return path


def write_text(text, *parts):
    path = os.path.join(HERE, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)
    return path


def main():
    rounded = render_rounded()
    square = render_square()
    glyph = render_glyph()

    # A preview so the design can be eyeballed before installing.
    write(scaled(rounded, 512), "preview.png")
    write(rounded, "master_rounded.png")
    write(square, "master_square.png")
    write(glyph, "master_glyph.png")

    made = 0

    # --- Android legacy launcher icons
    for density, px in (
        ("mdpi", 48),
        ("hdpi", 72),
        ("xhdpi", 96),
        ("xxhdpi", 144),
        ("xxxhdpi", 192),
    ):
        write(scaled(rounded, px), "android", "mipmap-" + density, "ic_launcher.png")
        made += 1

    # --- Android adaptive icon foreground (108dp grid)
    for density, px in (
        ("mdpi", 108),
        ("hdpi", 162),
        ("xhdpi", 216),
        ("xxhdpi", 324),
        ("xxxhdpi", 432),
    ):
        write(
            scaled(glyph, px),
            "android",
            "mipmap-" + density,
            "ic_launcher_foreground.png",
        )
        made += 1

    write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        "</adaptive-icon>\n",
        "android",
        "mipmap-anydpi-v26",
        "ic_launcher.xml",
    )
    write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<resources>\n"
        '    <color name="ic_launcher_background">' + LIME_HEX + "</color>\n"
        "</resources>\n",
        "android",
        "values",
        "ic_launcher_background.xml",
    )
    made += 2

    # --- macOS: the squircle is inset a little, as Big Sur icons are
    mac = render_rounded(radius_frac=0.235, inset=0.055, span=0.56)
    for px in (16, 32, 64, 128, 256, 512, 1024):
        write(scaled(mac, px), "macos", "app_icon_%d.png" % px)
        made += 1

    # --- iOS: opaque, full bleed; iOS applies its own mask
    ios = (
        ("Icon-App-20x20@1x.png", 20),
        ("Icon-App-20x20@2x.png", 40),
        ("Icon-App-20x20@3x.png", 60),
        ("Icon-App-29x29@1x.png", 29),
        ("Icon-App-29x29@2x.png", 58),
        ("Icon-App-29x29@3x.png", 87),
        ("Icon-App-40x40@1x.png", 40),
        ("Icon-App-40x40@2x.png", 80),
        ("Icon-App-40x40@3x.png", 120),
        ("Icon-App-60x60@2x.png", 120),
        ("Icon-App-60x60@3x.png", 180),
        ("Icon-App-76x76@1x.png", 76),
        ("Icon-App-76x76@2x.png", 152),
        ("Icon-App-83.5x83.5@2x.png", 167),
        ("Icon-App-1024x1024@1x.png", 1024),
    )
    for name, px in ios:
        flat = Image.new("RGB", (px, px), LIME[:3])
        flat.paste(scaled(square, px), (0, 0), scaled(square, px))
        write(flat, "ios", name)
        made += 1

    # --- Android status-bar (notification) icon: white glyph, no background
    for density, px in (
        ("mdpi", 24),
        ("hdpi", 36),
        ("xhdpi", 48),
        ("xxhdpi", 72),
        ("xxxhdpi", 96),
    ):
        write(
            scaled(render_glyph(span=0.86, colour=(255, 255, 255, 255)), px),
            "android",
            "drawable-" + density,
            "ic_stat_nearlink.png",
        )
        made += 1

    # --- Windows
    ico = os.path.join(HERE, "windows", "app_icon.ico")
    os.makedirs(os.path.dirname(ico), exist_ok=True)
    scaled(rounded, 256).save(
        ico,
        format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )
    made += 1

    print("generated %d icon files under %s" % (made, HERE))
    print("preview: " + os.path.join(HERE, "preview.png"))


if __name__ == "__main__":
    main()
