#!/usr/bin/env python3
"""Apply the Android setup to a generated Flutter project.

Run it from the project root — the folder that contains pubspec.yaml:

    python3 platform_setup/android_foreground_service/apply_android_setup.py

It does four things, and is safe to run more than once:

  1. copies the two Kotlin files into the right package folder
  2. adds the permissions and the <service> entry to AndroidManifest.xml
  3. prepares app/build.gradle for flutter_local_notifications — core library
     desugaring, and Java and Kotlin aligned on the same JVM target
  4. matches the Kotlin package name to your applicationId
"""

import os
import re
import sys

ROOT = os.getcwd()
SRC_DIR = os.path.join(ROOT, "platform_setup", "android_foreground_service")
MANIFEST = os.path.join(ROOT, "android", "app", "src", "main", "AndroidManifest.xml")

PERMISSIONS = (
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_DATA_SYNC",
    "android.permission.POST_NOTIFICATIONS",
)

SERVICE_BLOCK = (
    "        <service\n"
    '            android:name=".NearlinkForegroundService"\n'
    '            android:exported="false"\n'
    '            android:foregroundServiceType="dataSync" />\n'
)

KOTLIN_FILES = ("NearlinkForegroundService.kt", "MainActivity.kt")

DESUGAR_VERSION = "2.1.4"

# Kotlin's default JVM target follows the JDK toolchain (17 on a current
# machine). Java's does not, so unless they are stated explicitly Gradle fails
# with "Inconsistent JVM Target Compatibility". We pin both to 17.
JVM_TARGET = "17"


def detect_package():
    """Read applicationId from the Gradle file, falling back to the default."""
    for candidate in ("android/app/build.gradle.kts", "android/app/build.gradle"):
        path = os.path.join(ROOT, candidate)
        if not os.path.exists(path):
            continue
        text = open(path, encoding="utf-8").read()
        match = re.search(r'applicationId\s*=?\s*"([^"]+)"', text)
        if match:
            return match.group(1)
    return "com.example.nearlink"


def copy_kotlin(package):
    kotlin_dir = os.path.join(
        ROOT, "android", "app", "src", "main", "kotlin", *package.split(".")
    )
    os.makedirs(kotlin_dir, exist_ok=True)

    for name in KOTLIN_FILES:
        source = os.path.join(SRC_DIR, name)
        if not os.path.exists(source):
            sys.exit("Missing " + source)
        content = open(source, encoding="utf-8").read()
        content = re.sub(
            r"^package\s+\S+",
            "package " + package,
            content,
            count=1,
            flags=re.MULTILINE,
        )
        with open(os.path.join(kotlin_dir, name), "w", encoding="utf-8") as handle:
            handle.write(content)
        print("copied " + name + " -> " + kotlin_dir)


def patch_manifest():
    text = open(MANIFEST, encoding="utf-8").read()
    changes = []

    for permission in PERMISSIONS:
        if permission in text:
            continue
        text = text.replace(
            "<application",
            '    <uses-permission android:name="' + permission + '"/>\n    <application',
            1,
        )
        changes.append(permission)

    if "NearlinkForegroundService" not in text:
        text = text.replace("</application>", SERVICE_BLOCK + "    </application>", 1)
        changes.append("NearlinkForegroundService <service>")

    with open(MANIFEST, "w", encoding="utf-8") as handle:
        handle.write(text)

    if changes:
        print("manifest updated:")
        for change in changes:
            print("  + " + change)
    else:
        print("manifest already up to date")


def patch_gradle():
    kts = os.path.join(ROOT, "android", "app", "build.gradle.kts")
    groovy = os.path.join(ROOT, "android", "app", "build.gradle")

    if os.path.exists(kts):
        path, kotlin_dsl = kts, True
    elif os.path.exists(groovy):
        path, kotlin_dsl = groovy, False
    else:
        print("no android/app/build.gradle found — skipping Gradle setup")
        return

    text = open(path, encoding="utf-8").read()
    changes = []

    # --- core library desugaring, required by flutter_local_notifications
    if "isCoreLibraryDesugaringEnabled" not in text and (
        "coreLibraryDesugaringEnabled" not in text
    ):
        line = (
            "        isCoreLibraryDesugaringEnabled = true"
            if kotlin_dsl
            else "        coreLibraryDesugaringEnabled true"
        )
        if "compileOptions {" in text:
            text = text.replace("compileOptions {", "compileOptions {\n" + line, 1)
        else:
            text = text.replace(
                "android {", "android {\n    compileOptions {\n" + line + "\n    }", 1
            )
        changes.append("core library desugaring enabled")

    if "desugar_jdk_libs" not in text:
        if kotlin_dsl:
            block = (
                "\n\ndependencies {\n"
                '    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:'
                + DESUGAR_VERSION
                + '")\n}\n'
            )
        else:
            block = (
                "\n\ndependencies {\n"
                "    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:"
                + DESUGAR_VERSION
                + "'\n}\n"
            )
        text = text.rstrip() + "\n" + block
        changes.append("desugar_jdk_libs " + DESUGAR_VERSION)

    # --- align Java and Kotlin on one JVM target
    java_pattern = r"(sourceCompatibility|targetCompatibility)\s*=?\s*JavaVersion\.VERSION_\d+"
    text, java_hits = re.subn(
        java_pattern,
        lambda m: "%s = JavaVersion.VERSION_%s" % (m.group(1), JVM_TARGET),
        text,
    )
    if java_hits:
        changes.append("Java target %s" % JVM_TARGET)

    jvm_pattern = (
        r"jvmTarget\s*=?\s*"
        r"(?:JavaVersion\.VERSION_\d+\.toString\(\)|['\"]?\d+['\"]?)"
    )
    text, jvm_hits = re.subn(jvm_pattern, 'jvmTarget = "%s"' % JVM_TARGET, text)
    if jvm_hits:
        changes.append("Kotlin jvmTarget %s" % JVM_TARGET)
    elif "kotlinOptions" not in text:
        # No kotlinOptions block at all: add one so Kotlin cannot drift from Java.
        text = text.replace(
            "android {",
            'android {\n    kotlinOptions {\n        jvmTarget = "%s"\n    }' % JVM_TARGET,
            1,
        )
        changes.append("kotlinOptions jvmTarget %s" % JVM_TARGET)

    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)

    print(
        os.path.basename(path)
        + ": "
        + (", ".join(changes) if changes else "already up to date")
    )


def main():
    if not os.path.exists(MANIFEST):
        sys.exit(
            "Could not find android/app/src/main/AndroidManifest.xml.\n"
            "Run this from the project root (where pubspec.yaml lives)."
        )

    package = detect_package()
    copy_kotlin(package)
    patch_manifest()
    patch_gradle()

    print()
    print("Package name used: " + package)
    print("Now rebuild (a manifest and Gradle change needs a full rebuild):")
    print("  flutter clean && flutter run -d <device>")


if __name__ == "__main__":
    main()
