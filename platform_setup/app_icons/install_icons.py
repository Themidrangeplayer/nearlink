#!/usr/bin/env python3
"""Copy the generated Nearlink icons into a Flutter project's platform folders.

Run from the project root:

    python3 platform_setup/app_icons/install_icons.py

Optionally pass a different project root as the first argument. Missing
platform folders are skipped, so this is safe on a project that only targets
some platforms.
"""

import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.abspath(
    os.path.join(HERE, "..", "..")
)

ANDROID_DENSITIES = ("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi")

# (source, destination, label)
JOBS = []

for density in ANDROID_DENSITIES:
    JOBS.append((
        os.path.join("android", "mipmap-" + density, "ic_launcher.png"),
        os.path.join("android/app/src/main/res", "mipmap-" + density, "ic_launcher.png"),
        "Android launcher icon (%s)" % density,
    ))
    JOBS.append((
        os.path.join("android", "mipmap-" + density, "ic_launcher_foreground.png"),
        os.path.join(
            "android/app/src/main/res",
            "mipmap-" + density,
            "ic_launcher_foreground.png",
        ),
        "Android adaptive foreground (%s)" % density,
    ))

for density in ANDROID_DENSITIES:
    JOBS.append((
        os.path.join("android", "drawable-" + density, "ic_stat_nearlink.png"),
        os.path.join(
            "android/app/src/main/res",
            "drawable-" + density,
            "ic_stat_nearlink.png",
        ),
        "Android status-bar icon (%s)" % density,
    ))

JOBS.append((
    os.path.join("android", "mipmap-anydpi-v26", "ic_launcher.xml"),
    "android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml",
    "Android adaptive icon",
))
JOBS.append((
    os.path.join("android", "values", "ic_launcher_background.xml"),
    "android/app/src/main/res/values/ic_launcher_background.xml",
    "Android adaptive background colour",
))

for px in (16, 32, 64, 128, 256, 512, 1024):
    JOBS.append((
        os.path.join("macos", "app_icon_%d.png" % px),
        "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_%d.png" % px,
        "macOS app icon (%dpx)" % px,
    ))

IOS_NAMES = (
    "Icon-App-20x20@1x.png",
    "Icon-App-20x20@2x.png",
    "Icon-App-20x20@3x.png",
    "Icon-App-29x29@1x.png",
    "Icon-App-29x29@2x.png",
    "Icon-App-29x29@3x.png",
    "Icon-App-40x40@1x.png",
    "Icon-App-40x40@2x.png",
    "Icon-App-40x40@3x.png",
    "Icon-App-60x60@2x.png",
    "Icon-App-60x60@3x.png",
    "Icon-App-76x76@1x.png",
    "Icon-App-76x76@2x.png",
    "Icon-App-83.5x83.5@2x.png",
    "Icon-App-1024x1024@1x.png",
)
for name in IOS_NAMES:
    JOBS.append((
        os.path.join("ios", name),
        "ios/Runner/Assets.xcassets/AppIcon.appiconset/" + name,
        "iOS app icon " + name,
    ))

JOBS.append((
    os.path.join("windows", "app_icon.ico"),
    "windows/runner/resources/app_icon.ico",
    "Windows app icon",
))


def main():
    if not os.path.exists(os.path.join(ROOT, "pubspec.yaml")):
        sys.exit(
            "No pubspec.yaml in %s — run this from the project root, or pass "
            "the project path as an argument." % ROOT
        )

    installed = 0
    skipped_platforms = set()

    for source_rel, dest_rel, label in JOBS:
        source = os.path.join(HERE, source_rel)
        dest = os.path.join(ROOT, dest_rel)

        if not os.path.exists(source):
            sys.exit("Missing generated icon: %s — run make_icons.py first." % source)

        # Skip platforms this project does not have.
        top = dest_rel.split("/")[0]
        if not os.path.isdir(os.path.join(ROOT, top)):
            skipped_platforms.add(top)
            continue

        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.copyfile(source, dest)
        installed += 1

    print("installed %d icon files into %s" % (installed, ROOT))
    if skipped_platforms:
        print("skipped (no such folder): " + ", ".join(sorted(skipped_platforms)))
    print()
    print("Now rebuild — icons are baked into the app bundle:")
    print("  flutter clean && flutter run -d <device>")


if __name__ == "__main__":
    main()
