#!/usr/bin/env bash
# Generate the platform folders around lib/ and pubspec.yaml, then fetch deps.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter is not on PATH. Install it from https://docs.flutter.dev/get-started/install" >&2
  exit 1
fi

echo "==> Generating platform folders (existing lib/ and pubspec are kept)"
flutter create .

echo "==> Fetching dependencies"
flutter pub get

echo
echo "Done. Next:"
echo "  1. Apply the permissions in platform_setup/README.md"
echo "  2. flutter run"
