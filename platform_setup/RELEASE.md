# Releasing Nearlink

Two things must change before anything goes to a store, and one of them Play
will reject outright.

## 0. Before you build anything

**Change the application id.** It is currently `com.example.nearlink`, which
Google Play refuses. Pick your own, e.g. `in.yourname.nearlink`, and change it
in **both** places:

- `android/app/build.gradle.kts` → `applicationId`
- `macos/Runner/Configs/AppInfo.xcconfig` → `PRODUCT_BUNDLE_IDENTIFIER`
  (and the same in the iOS `Runner` target if you ship iOS)

The Kotlin package folder can stay as it is — the foreground-service script
matches the `package` line to whatever `applicationId` says.

**Set the version** in `pubspec.yaml`:

```yaml
version: 1.0.0+1
```

The part after `+` is the Android `versionCode` and must increase on every
upload.

**Set the display name** in `android/app/src/main/AndroidManifest.xml`
(`android:label`) and `macos/Runner/Configs/AppInfo.xcconfig`
(`PRODUCT_NAME`).

## 1. Android — generate a signing key

```bash
bash platform_setup/android_release/make_keystore.sh
```

It creates `android/keystore/upload-keystore.jks` and `android/key.properties`,
and prints the password. **Keep both safe and out of version control** — add to
`.gitignore`:

```
android/key.properties
android/keystore/
```

Losing this key means you can never update the app on Play under the same id.

## 2. Android — wire the key into Gradle

The quickest route is the script, which generates the keystore (step 1) and makes
every edit below in one go:

```bash
python3 platform_setup/android_release/setup_signing.py
```

It is safe to run repeatedly and skips anything already present. It also prints
the password it generated, so write it down.

If you would rather do it by hand, the edits are:

In `android/app/build.gradle.kts`, add at the very top, above `plugins {`:

```kotlin
import java.util.Properties
import java.io.FileInputStream
```

Just above the `android {` block:

```kotlin
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
```

Inside `android { }`, add:

```kotlin
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String
        }
    }
```

And in `buildTypes { release { ... } }`, change:

```kotlin
signingConfig = signingConfigs.getByName("debug")
```

to:

```kotlin
signingConfig = signingConfigs.getByName("release")
```

## 3. Android — build

For the Play Store (the `.aab` format Google requires):

```bash
flutter build appbundle --release
```

Output: `build/app/outputs/bundle/release/app-release.aab`

For sideloading an APK:

```bash
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

**If Gradle dies with "build daemon disappeared"**, it ran out of memory —
close Xcode, the simulator and Chrome, then lower the heap:

```bash
sed -i '' 's/^org.gradle.jvmargs=.*/org.gradle.jvmargs=-Xmx2G -XX:MaxMetaspaceSize=1G/' android/gradle.properties
```

## 4. macOS — build

```bash
flutter build macos --release
open build/macos/Build/Products/Release/nearlink.app
```

That runs on **your** Mac. For anyone else, macOS will refuse it: unsigned apps
are blocked by Gatekeeper. Distributing a macOS app properly needs an Apple
Developer account (paid), then Developer ID signing and notarisation:

```bash
codesign --deep --force --options runtime \
  --sign "Developer ID Application: Your Name (TEAMID)" \
  build/macos/Build/Products/Release/nearlink.app

xcrun notarytool submit nearlink.zip --keychain-profile "notary" --wait
xcrun stapler staple build/macos/Build/Products/Release/nearlink.app
```

Without that, the practical route is to hand people the source and let them run
it from Xcode, or just run it locally.

## 5. iOS

Needs a paid Apple Developer account and a Mac with Xcode:

```bash
flutter build ipa --release
```

Then upload via Transporter or Xcode Organizer.

## Store requirements worth knowing early

- **Play** wants a privacy policy URL, a data-safety declaration, and content
  rating. Nearlink collects nothing and has no backend, which makes the
  declarations simple — but you still have to fill them in.
- **Play** now wants an app to target a recent API level; Flutter's default
  `targetSdk` is usually fine.
- Both stores want screenshots at specific sizes.

## Honest limitations to disclose

Nearlink works over the local network with no server. It will not work on
networks that block multicast and broadcast (guest Wi-Fi, some corporate
networks), and it needs both devices on the same subnet. That is worth saying
plainly in the store listing rather than having users discover it.
