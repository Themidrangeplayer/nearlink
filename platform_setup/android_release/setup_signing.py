#!/usr/bin/env python3
"""Set up Android release signing for a generated Flutter project.

Run it from the project root:

    python3 platform_setup/android_release/setup_signing.py

Two steps, and it is safe to run more than once:

  1. generates an upload keystore and android/key.properties (skipped if
     key.properties already exists, or if keytool is not installed)
  2. wires that key into android/app/build.gradle.kts, replacing the default
     "sign it with the debug key" behaviour

KEEP THE KEYSTORE AND ITS PASSWORD. Losing them means you can never update the
app on Play under the same application id.
"""

import os
import re
import shutil
import subprocess
import sys

ROOT = os.getcwd()
ANDROID = os.path.join(ROOT, "android")
KEY_PROPERTIES = os.path.join(ANDROID, "key.properties")
KEYSTORE_DIR = os.path.join(ANDROID, "keystore")
KEYSTORE = os.path.join(KEYSTORE_DIR, "upload-keystore.jks")
GRADLE_KTS = os.path.join(ANDROID, "app", "build.gradle.kts")

IMPORTS = "import java.util.Properties\nimport java.io.FileInputStream\n\n"

LOADER = (
    "val keystoreProperties = Properties()\n"
    'val keystorePropertiesFile = rootProject.file("key.properties")\n'
    "if (keystorePropertiesFile.exists()) {\n"
    "    keystoreProperties.load(FileInputStream(keystorePropertiesFile))\n"
    "}\n\n"
)

SIGNING_CONFIG = (
    "    signingConfigs {\n"
    '        create("release") {\n'
    "            // Guarded so a build with no key.properties (such as CI without\n"
    "            // the keystore secret) still configures cleanly.\n"
    "            if (keystorePropertiesFile.exists()) {\n"
    '                keyAlias = keystoreProperties["keyAlias"] as String\n'
    '                keyPassword = keystoreProperties["keyPassword"] as String\n'
    '                storeFile = keystoreProperties["storeFile"]?.let { file(it) }\n'
    '                storePassword = keystoreProperties["storePassword"] as String\n'
    "            }\n"
    "        }\n"
    "    }\n"
)


def has_keytool():
    return shutil.which("keytool") is not None


def ask_password():
    try:
        import getpass

        return getpass.getpass("Keystore password (Enter to generate one): ")
    except Exception:
        return ""


def generate_keystore():
    if os.path.exists(KEY_PROPERTIES):
        print("android/key.properties already exists — leaving it alone")
        return True

    if not has_keytool():
        print("keytool not found (needs a JDK 17+). Skipping keystore generation.")
        print("Install a JDK, or run platform_setup/android_release/make_keystore.sh")
        print("on a machine that has one, then run this script again.")
        return False

    password = ask_password()
    if not password:
        import secrets
        import string

        alphabet = string.ascii_letters + string.digits
        password = "".join(secrets.choice(alphabet) for _ in range(24))
        print("Generated password: " + password)
        print("Write this down — you need it for every future release.")

    alias = "upload"
    os.makedirs(KEYSTORE_DIR, exist_ok=True)

    result = subprocess.run(
        [
            "keytool",
            "-genkeypair",
            "-v",
            "-keystore",
            KEYSTORE,
            "-storetype",
            "JKS",
            "-keyalg",
            "RSA",
            "-keysize",
            "2048",
            "-validity",
            "10000",
            "-alias",
            alias,
            "-storepass",
            password,
            "-keypass",
            password,
            "-dname",
            "CN=Nearlink, OU=Mobile, O=Nearlink, L=City, ST=State, C=IN",
        ],
        check=False,
    )
    if result.returncode != 0:
        print("keytool failed — not writing key.properties")
        return False

    with open(KEY_PROPERTIES, "w", encoding="utf-8") as handle:
        handle.write(
            "storePassword=%s\n"
            "keyPassword=%s\n"
            "keyAlias=%s\n"
            "storeFile=../keystore/upload-keystore.jks\n"
            % (password, password, alias)
        )

    print("wrote android/keystore/upload-keystore.jks and android/key.properties")
    return True


def patch_gradle():
    if not os.path.exists(GRADLE_KTS):
        print("no android/app/build.gradle.kts found — skipping Gradle wiring")
        return

    text = open(GRADLE_KTS, encoding="utf-8").read()
    changes = []

    if "java.util.Properties" not in text:
        text = IMPORTS + text
        changes.append("imports")

    if "keystoreProperties" not in text:
        text = text.replace("android {", LOADER + "android {", 1)
        changes.append("key.properties loader")

    if 'create("release")' not in text:
        text = text.replace("android {", "android {\n" + SIGNING_CONFIG, 1)
        changes.append("release signingConfig")

    if 'signingConfigs.getByName("debug")' in text:
        text = text.replace(
            'signingConfig = signingConfigs.getByName("debug")',
            "signingConfig = if (keystorePropertiesFile.exists()) {\n"
            '                signingConfigs.getByName("release")\n'
            "            } else {\n"
            '                signingConfigs.getByName("debug")\n'
            "            }",
            1,
        )
        changes.append("release build type uses the upload key, or debug if absent")

    with open(GRADLE_KTS, "w", encoding="utf-8") as handle:
        handle.write(text)

    print(
        "android/app/build.gradle.kts: "
        + (", ".join(changes) if changes else "already up to date")
    )


def main():
    global ROOT, ANDROID, KEY_PROPERTIES, KEYSTORE_DIR, KEYSTORE, GRADLE_KTS

    if len(sys.argv) > 1:
        ROOT = os.path.abspath(sys.argv[1])
        ANDROID = os.path.join(ROOT, "android")
        KEY_PROPERTIES = os.path.join(ANDROID, "key.properties")
        KEYSTORE_DIR = os.path.join(ANDROID, "keystore")
        KEYSTORE = os.path.join(KEYSTORE_DIR, "upload-keystore.jks")
        GRADLE_KTS = os.path.join(ANDROID, "app", "build.gradle.kts")

    if not os.path.exists(os.path.join(ROOT, "pubspec.yaml")):
        sys.exit(
            "No pubspec.yaml here — run this from the project root, or pass the "
            "project path as the first argument."
        )

    generate_keystore()
    patch_gradle()

    print()
    print("Add these to .gitignore if they are not there already:")
    print("  android/key.properties")
    print("  android/keystore/")
    print()
    print("Then build:")
    print("  flutter build appbundle --release    # for Play")
    print("  flutter build apk --release          # for sideloading")


if __name__ == "__main__":
    main()
