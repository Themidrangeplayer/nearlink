# Platform setup

`flutter create .` generates the platform folders. Apply the additions below
afterwards — they are what mDNS discovery and QR scanning need.

## Android

`android/app/src/main/AndroidManifest.xml`, inside `<manifest>`:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE"/>
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES"
    android:usesPermissionFlags="neverForLocation" />
```

`NEARBY_WIFI_DEVICES` is Android 13+ and declares the multicast use without
requesting location. `CAMERA` is only needed for QR scanning.

## iOS

`ios/Runner/Info.plist`:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Nearlink finds your devices on this network to share files and clipboard text.</string>
<key>NSBonjourServices</key>
<array>
  <string>_nearlink._tcp</string>
</array>
<key>NSCameraUsageDescription</key>
<string>Nearlink scans pairing QR codes with the camera.</string>
```

## macOS

Both `macos/Runner/DebugProfile.entitlements` and
`macos/Runner/Release.entitlements` need:

```xml
<key>com.apple.security.network.server</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.device.camera</key>
<true/>
```

And `macos/Runner/Info.plist` needs the same `NSLocalNetworkUsageDescription`
and `NSBonjourServices` entries as iOS (macOS 11+ prompts for local network
access).

## Windows

No manifest changes. Windows Firewall will prompt on first run to allow the
app to accept inbound connections on private networks — allow it, or peers will
not be able to connect.

## Linux

Install and run Avahi:

```bash
sudo apt install avahi-daemon
sudo systemctl enable --now avahi-daemon
```

`flutter_secure_storage` needs `libsecret`:

```bash
sudo apt install libsecret-1-dev libjsoncpp-dev
```

## macOS: deployment target

Flutter's macOS template still stamps `MACOSX_DEPLOYMENT_TARGET = 10.15`, but
recent Xcode refuses anything below 12.0 and the build fails with:

```
The macOS deployment target 'MACOSX_DEPLOYMENT_TARGET' is set to 10.15,
but the range of supported deployment target versions is 12.0 to ...
```

Raise it in two places, then rebuild from clean:

1. `macos/Podfile` — set the platform near the top to `platform :osx, '12.0'`,
   and inside `post_install`, after `flutter_additional_macos_build_settings(target)`,
   force every pod to match:

   ```ruby
   target.build_configurations.each do |c|
     c.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '12.0'
   end
   ```

2. `macos/Runner.xcodeproj/project.pbxproj` — set all three
   `MACOSX_DEPLOYMENT_TARGET = ...;` entries (Debug, Release, Profile) to `12.0`.

```bash
flutter clean
rm -rf macos/Pods macos/Podfile.lock
flutter pub get
flutter run -d macos
```

Bumping to 12.0 drops support for macOS 10.15 and 11 — fine for personal use.

## macOS: receiving files into ~/Downloads

A sandboxed macOS app cannot write to the user's Downloads folder unless it
declares the entitlement. Without it, startup fails with:

```
PathAccessException: Creation failed, path = '.../Data/Downloads/Nearlink'
(OS Error: Operation not permitted, errno = 1)
```

Either add this to both `macos/Runner/*.entitlements` files, or leave it out —
the app now falls back to its own Application Support directory when Downloads
is not writable.

```xml
<key>com.apple.security.files.downloads.read-write</key>
<true/>
```

## macOS: QR scanning crashes the app

Accessing the camera without a usage description makes macOS terminate the app
outright — no Dart exception, it just quits. Add this to
`macos/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Nearlink scans pairing QR codes with the camera.</string>
```

One-liner (run from `macos/Runner`):

```bash
/usr/libexec/PlistBuddy -c "Add :NSCameraUsageDescription string Nearlink scans pairing QR codes with the camera." Info.plist
```

## macOS: "Browse files" does nothing

`file_picker` opens an `NSOpenPanel`, which a sandboxed app cannot use without
the user-selected-files entitlement. Add to both
`macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements`:

```xml
<key>com.apple.security.files.user-selected.read-only</key>
<true/>
```

(Drag-and-drop is unaffected — it goes through a different path, which is why it
kept working.)

## Android: the app pauses when minimised

Android freezes backgrounded processes, which stops the receiving server, mDNS
discovery and clipboard sync. The fix is a foreground service with a persistent
notification — the platform's sanctioned way to stay alive. The Dart side is
already in `lib/core/platform/background_keeper.dart`; add the native half:

**1. Copy the two Kotlin files in.** From `platform_setup/android_foreground_service/`:

```bash
cd ~/Desktop/nearlink
cp platform_setup/android_foreground_service/NearlinkForegroundService.kt \
   android/app/src/main/kotlin/com/example/nearlink/
cp platform_setup/android_foreground_service/MainActivity.kt \
   android/app/src/main/kotlin/com/example/nearlink/
```

(The second replaces the generated `MainActivity.kt`.)

**2. Add to `android/app/src/main/AndroidManifest.xml`**, as direct children of
`<manifest>`:

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```

and inside `<application>`:

```xml
<service
    android:name=".NearlinkForegroundService"
    android:exported="false"
    android:foregroundServiceType="dataSync" />
```

**3. If `NotificationCompat` does not resolve**, add to the `dependencies` block
of `android/app/build.gradle.kts`:

```kotlin
implementation("androidx.core:core-ktx:1.13.1")
```

Then rebuild — a manifest and Kotlin change needs a full rebuild, not a hot
restart. A small "Nearlink is ready" notification will appear while the app is
running; the **Keep receiving in the background** switch under Security turns it
off. On Android 13+, allow notifications for the app if you want that
notification to be visible (the service runs either way).

### One-command alternative

Instead of doing the three steps above by hand, run this from the project root:

```bash
python3 platform_setup/android_foreground_service/apply_android_setup.py
```

It copies both Kotlin files into the correct package folder, adds the three
permissions and the `<service>` entry to `AndroidManifest.xml`, and matches the
Kotlin package name to your `applicationId`. It is safe to run repeatedly — it
skips anything already present. Then `flutter clean && flutter run -d <device>`.

## App icon

The icon matches the in-app brand mark: a lime rounded square with the dark
green navigation arrow the sidebar uses. Everything is generated from one
script, so the design can be tweaked in one place.

**Install it** (from the project root):

```bash
python3 platform_setup/app_icons/install_icons.py
```

That writes 35 files into the right spots:

| Platform | Where |
| --- | --- |
| Android | `res/mipmap-*/ic_launcher.png` plus adaptive foreground + `mipmap-anydpi-v26/ic_launcher.xml` |
| macOS | `macos/Runner/Assets.xcassets/AppIcon.appiconset/` (16 → 1024) |
| iOS | `ios/Runner/Assets.xcassets/AppIcon.appiconset/` (all 15 sizes) |
| Windows | `windows/runner/resources/app_icon.ico` |

Platforms you don't have are skipped, so it is safe to run on a partial project.
Icons are baked into the app bundle, so rebuild afterwards:

```bash
flutter clean && flutter run -d <device>
```

**Change the design** by editing `platform_setup/app_icons/make_icons.py` — the
colours are `LIME` and `DARK` at the top, and the arrow shape is the `ARROW`
tuple — then:

```bash
python3 platform_setup/app_icons/make_icons.py
python3 platform_setup/app_icons/install_icons.py
```

`preview.png` in that folder shows the result at 512px before you install it.

**The icon is not the app name.** The name shown under the icon comes from
`android:label` in `AndroidManifest.xml` and `PRODUCT_NAME` in
`macos/Runner/Configs/AppInfo.xcconfig`.

## Running in the background, per platform

"Background" means something different on each platform, and it is worth being
precise about what actually works.

### Android

The app runs a **foreground service** with a persistent notification, which is
the platform's sanctioned way to stay alive when minimised. Without it, Android
freezes the process and receiving stops.

Set up in two places:

- `lib/core/platform/background_keeper.dart` (already in the project)
- the native half — `platform_setup/android_foreground_service/`, installed by
  `apply_android_setup.py`

The **Keep receiving in the background** switch under Security turns it off.

What it does *not* do: if you force-stop the app from the recents screen or
Android's app settings, nothing runs until you open Nearlink again. Receiving
in the background also requires `POST_NOTIFICATIONS` to be granted on Android
13+, or the notification is invisible (the service still runs).

### macOS and desktop

A Flutter desktop app keeps running while its window is open, even unfocused —
so receiving works while the window is minimised or behind others.

Closing the window, though, quits the app by default. To keep it alive when the
window is closed, add these two overrides to
`macos/Runner/AppDelegate.swift`:

```swift
override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
  return false
}

override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
  return true
}
```

The first stops the quit; the second reopens the window when you click the Dock
icon. With both, Nearlink keeps receiving after you close the window.

### iOS

There is no background option worth having. iOS suspends local-network traffic
when an app leaves the foreground, so mDNS and the broadcast beacon both stop.
Nearlink has to be open on an iPhone to receive.

## Notifications

When a file, clipboard item, message or pairing request arrives while Nearlink
is not on screen, it posts a system notification. In the foreground you get the
in-app message instead, so you are never told twice.

- Toggle: **Security → Notifications** (on by default).
- Android needs `POST_NOTIFICATIONS` — granted on first launch; if you declined
  it, re-enable it in Android's app settings.
- macOS asks on first launch too; without it, notifications are silently dropped.
- The Android status-bar icon is `ic_stat_nearlink`, generated with the app icon
  by `platform_setup/app_icons/install_icons.py`.

## Introducing devices to each other

If you have paired your phone and your laptop to a desktop, the phone and the
laptop know about the desktop but not about each other. **Connect devices** on
the Control center (next to *+ Add device*) fixes that: pick two or more trusted
devices and Nearlink vouches for each pair.

The consent rule is the point of the feature:

- Every pair is asked **separately** — each device gets its own prompt.
- A pair connects **only when both sides accept**. Neither can complete it alone.
- **If either declines, it is cancelled for both.** The other side is told, and
  if it had already accepted, that acceptance is withdrawn.

Mechanically: the device arranging the introduction generates a single random
secret and gives the same one to both sides. Each side registers it *only when
it consents*, and the pairing call uses it. Without both registrations the call
cannot succeed, so a one-sided pairing is not merely discouraged — it is
impossible. Only the device with the lower id makes the pairing call, so it is
not attempted twice.

Only a device you already trust may introduce anyone, so a stranger on the
network cannot talk your devices into connecting.

The behaviour is covered by `test/intro_test.dart`: it checks that an
introduction is delivered, that the shared secret pairs both sides, that a
decline is delivered, that no pairing happens when only one side consents, and
that an untrusted device cannot offer an introduction at all.

## Android: core library desugaring (required)

`flutter_local_notifications` uses Java 8+ time APIs, so Android refuses to
build without core library desugaring. The symptom is:

```
Dependency ':flutter_local_notifications' requires core library desugaring
to be enabled for :app.
```

Two edits to `android/app/build.gradle.kts`. Inside the existing
`compileOptions { }` block, add:

```kotlin
        isCoreLibraryDesugaringEnabled = true
```

and add a `dependencies` block at the end of the file:

```kotlin
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

Or just re-run the setup script, which does both:

```bash
python3 platform_setup/android_foreground_service/apply_android_setup.py
```

It handles the Kotlin DSL (`.kts`) and the older Groovy `build.gradle`, and
skips anything already present. Then `flutter clean && flutter run -d <device>`.

## Android: "Inconsistent JVM Target Compatibility"

Kotlin's default JVM target follows the JDK toolchain (17 on a current
machine), while Java's comes from `compileOptions`. If only one is stated, they
drift and Gradle fails with:

```
Inconsistent JVM-target compatibility detected for tasks
'compileDebugJavaWithJavac' (11) and 'compileDebugKotlin' (17).
```

Pin both. In `android/app/build.gradle.kts`:

```kotlin
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
```

If the file has no `kotlinOptions` block, add one — that is the usual cause,
because without it Kotlin picks 17 on its own. The setup script does all of
this, including adding the block when it is missing.
