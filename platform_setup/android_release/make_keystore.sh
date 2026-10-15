#!/usr/bin/env bash
# Generate an Android upload keystore and android/key.properties.
# Run from the project root:  bash platform_setup/android_release/make_keystore.sh
set -euo pipefail

cd "$(dirname "$0")/../.."

if [ -f android/key.properties ]; then
  echo "android/key.properties already exists — not overwriting it."
  echo "Delete it first if you really want to start again."
  exit 0
fi

if ! command -v keytool >/dev/null 2>&1; then
  echo "keytool not found. Install a JDK (17+) and try again." >&2
  exit 1
fi

read -r -p "Keystore password (Enter to generate one): " STORE_PASS
if [ -z "$STORE_PASS" ]; then
  STORE_PASS=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)
  echo
  echo "Generated password: $STORE_PASS"
  echo "Write this down. You need it for every future release, and losing it"
  echo "means you can never update the app on Play again."
  echo
fi

read -r -p "Key alias [upload]: " ALIAS
ALIAS=${ALIAS:-upload}

mkdir -p android/keystore
keytool -genkeypair -v \
  -keystore android/keystore/upload-keystore.jks \
  -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias "$ALIAS" \
  -storepass "$STORE_PASS" \
  -keypass "$STORE_PASS" \
  -dname "CN=Nearlink, OU=Mobile, O=Nearlink, L=City, ST=State, C=IN"

cat > android/key.properties <<PROPS
storePassword=$STORE_PASS
keyPassword=$STORE_PASS
keyAlias=$ALIAS
storeFile=../keystore/upload-keystore.jks
PROPS

echo
echo "Wrote:"
echo "  android/keystore/upload-keystore.jks"
echo "  android/key.properties"
echo
echo "Next: add the signing blocks to android/app/build.gradle.kts — see"
echo "platform_setup/RELEASE.md, step 3."
