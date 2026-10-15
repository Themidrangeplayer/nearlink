# Publishing Nearlink on GitHub

Builds for **Android, macOS, Windows and iOS**, attached to a GitHub release.

## The one thing you cannot do from your Mac

**Flutter does not cross-compile. A Windows build can only be produced on
Windows.** There is no flag or workaround — the toolchain is MSVC and it does not
exist on macOS.

The practical answer is the included GitHub Actions workflow: GitHub gives you a
Windows runner for free, so the Windows build happens there. That is why the
workflow exists rather than a set of local build commands.

The same logic, more mildly, applies to iOS: it needs a Mac (you have one), but
distributing it needs a paid Apple Developer account.

## One-time setup

### 1. Generate the platform folders you do not have yet

From the project root:

```bash
flutter create --platforms=windows,ios .
```

This only adds `windows/` and `ios/`; it leaves your existing `macos/` and
`android/` alone. Without it the workflow's Windows and iOS jobs have nothing to
build.

Then install the icons into the new folders:

```bash
python3 platform_setup/app_icons/install_icons.py
```

### 2. Keep secrets out of the repo

Add to `.gitignore` (Flutter's generated one already covers `build/` and
`.dart_tool/`):

```
android/key.properties
android/keystore/
```

### 3. Check what you are about to commit

```bash
git init
git add -A
git status --short | head -40
```

Make sure `build/`, `.dart_tool/`, `android/key.properties` and
`android/keystore/` are **not** listed. If they are, fix `.gitignore` before
committing.

### 4. Push

```bash
git add -A
git commit -m "Nearlink: initial commit"
git branch -M main
git remote add origin git@github.com:YOURNAME/nearlink.git
git push -u origin main
```

## Releasing

Tag a commit and push the tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```

That triggers `.github/workflows/release.yml`, which builds all four platforms
and attaches the results to a GitHub release. You can also run it by hand from
the **Actions** tab (workflow_dispatch) to get the files as workflow artifacts
without creating a release.

## Optional: properly signed Android builds

Without any setup, the APK is signed with the **debug key** — it installs fine
from a GitHub release, but Play will not accept it and Android will refuse to
update over a differently-signed copy.

To sign properly, add four repository secrets (**Settings → Secrets and
variables → Actions**):

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | your keystore, base64-encoded |
| `ANDROID_STORE_PASSWORD` | keystore password |
| `ANDROID_KEY_PASSWORD` | key password |
| `ANDROID_KEY_ALIAS` | key alias |

To produce the base64 value on macOS:

```bash
base64 -i android/keystore/upload-keystore.jks | pbcopy
```

With those set, the workflow uses your real key; without them it falls back to
the debug key rather than failing.

## What you get on each release

| File | Notes |
| --- | --- |
| `app-release.apk` | Android. Debug-signed unless the secrets are set. |
| `app-release.aab` | For Play, if you ever upload it there. |
| `<app>-macos.zip` | **Unsigned.** macOS blocks it on first open — users must right-click → Open, or you need notarisation. |
| `nearlink-windows.zip` | Unzip and run the `.exe`. Unsigned, so SmartScreen will warn. |
| `nearlink-ios-unsigned.ipa` | Cannot be installed normally. Sideload it with Sideloadly or AltStore, or set up signing. |

## Testing on every push

`.github/workflows/test.yml` runs `flutter test` on each push and pull request.
That covers the crypto, protocol, introduction and model tests, plus
`compile_check_test.dart`, which imports the whole app so that any screen failing
to compile breaks the build early — rather than at release time.

## The honest caveats

- **Unsigned builds are a rough experience.** macOS and Windows will both warn
  or block. Proper signing means an Apple Developer account ($99/year) for
  macOS/iOS, and a code-signing certificate for Windows. Neither is required to
  publish the files on GitHub, but users will notice.
- **Nearlink is local-network only.** Both devices must be on the same subnet,
  and it will not work on networks that block multicast and broadcast — guest
  Wi-Fi, many corporate networks, and most mobile hotspots with client
  isolation. Say so in the README, because it is the first thing a user will hit.
- **The first Android build in CI is slow** — Gradle downloads a lot. Later runs
  are much quicker because the Flutter action caches the SDK.
