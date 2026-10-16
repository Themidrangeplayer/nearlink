# Nearlink

A universal, end-to-end encrypted space for the devices you trust. This is the
real Flutter implementation of the Nearlink prototype: nearby discovery,
account-free secure pairing, a trusted-device panel, file and clipboard
transfer, and transfer activity — on Android, iOS, Windows, macOS and Linux
from one codebase.


---

## Quick start

```bash
# 1. Generate the platform folders (android/, ios/, windows/, macos/, linux/)
#    around the existing lib/ and pubspec.yaml. This does not touch lib/.
flutter create .

# 2. Pull dependencies
flutter pub get

# 3. Run on your current desktop platform
flutter run -d windows     # or: macos | linux

# 4. Run on a device/emulator
flutter run -d <device-id>
```

`tool/bootstrap.sh` does steps 1–2 for you.

Requires **Flutter 3.27 or newer** (Dart 3.6+), which the pubspec enforces.

Before running, apply the small platform permission additions in
[`platform_setup/`](platform_setup/) — mDNS and the camera need them.

---

## What actually works

| Prototype behaviour | Real implementation |
| --- | --- |
| "Nearby and eligible" list | mDNS/DNS-SD advertise + browse (`nsd`), filtered to unpaired peers |
| Pair a nearby device | QR code or 6-digit PIN, verified against the device fingerprint |
| Trusted devices panel + remove | Persisted trust store; removal revokes access immediately |
| Drag-and-drop / file picker | `desktop_drop` + `file_picker`, streamed in 64 KiB encrypted chunks |
| Universal clipboard | AES-GCM sealed text, both directions, with history |
| Transfer activity | Live progress, persisted across restarts |
| "End-to-end encrypted" badge | X25519 ECDH + HKDF session key, AES-256-GCM payloads, MAC confirmation |

## Project layout

```
lib/
  main.dart                     App entry: builds AppState, runs the app
  app.dart                      Responsive shell (sidebar / bottom nav)
  state/app_state.dart          Single source of truth; wires everything together
  core/
    crypto/
      device_identity.dart      Ed25519 identity + X25519 agreement keys, fingerprint
      secure_channel.dart       HKDF session keys, AES-GCM seal/open, frame codec
      pairing_payload.dart      QR/PIN payload encode/decode
    discovery/
      discovery_service.dart    Abstract discovery interface
      nsd_discovery_service.dart  Real mDNS via the nsd plugin
    net/
      nearlink_server.dart      Receiving HTTP server (handshake, pair, upload, clipboard)
      nearlink_client.dart      Sending client (info, handshake, upload, clipboard, pair)
    storage/
      key_vault.dart            Private keys: secure storage, prefs fallback
      trust_store.dart          Trusted devices
      settings_store.dart       Preferences
      history_store.dart        Transfer history
    models/                     Device, TrustedDevice, NearbyPeer, TransferItem
    protocol/protocol.dart      All wire constants in one place
    utils/bytes.dart            Hex / byte helpers
  features/
    control_center/             Overview, trusted devices, send-a-file, clipboard, activity
    pairing/                    QR display + scanner + manual entry
    transfers/                  Full history
    clipboard/                  Compose + clipboard history
    security/                   Fingerprint, privacy toggles, crypto explainer
  theme/app_theme.dart          Palette + typography from the prototype
  widgets/                      Shared cards, tiles, rows, formatters
test/                           Crypto, pairing payload and model unit tests
```

See [`ARCHITECTURE.md`](ARCHITECTURE.md) for the protocol and the crypto in
detail.

---

## Security model

* **Identity** — on first launch each device generates an Ed25519 signing key
  pair and an X25519 agreement key pair. The SHA-256 of the Ed25519 public key
  is the device fingerprint. Private keys never leave the device and live in
  platform secure storage (Keychain / Keystore / DPAPI / libsecret), with a
  preferences fallback where secure storage is unavailable.
* **Pairing** — one device shows a QR code (or a 6-digit PIN and address). The
  code carries public keys, the fingerprint, the address and a single-use,
  five-minute secret. The scanning device connects, presents the secret, and
  both sides store each other. Because the fingerprint travels in the QR code,
  the scanner verifies the responder really is that device — a LAN
  man-in-the-middle cannot impersonate it.
* **Sessions** — every session derives a fresh 256-bit key with X25519 ECDH +
  HKDF-SHA256 from the two agreement keys and a random salt, then both sides
  confirm the key with a keyed MAC before any data moves.
* **Payloads** — files and clipboard text are sealed with AES-256-GCM, chunk by
  chunk, giving confidentiality and integrity together. Encryption is at the
  application layer, so it holds end to end regardless of the transport.

**Deliberate scope choices, stated plainly:**

* Trust is **local-first** — there is no account server, by design. Devices
  pair directly and store keys locally.
* Transfers run over **plain HTTP on the LAN with application-layer
  encryption**, rather than TLS with self-signed certificates. The E2E
  guarantees above do not depend on the transport, and this avoids fragile
  in-Dart X.509 generation. Adding TLS on top is straightforward if you want
  transport-level secrecy for metadata too.
* The **PIN fallback is 6 digits**, so it is inherently low-entropy. It is
  single-use and expires in five minutes; for a production build add
  rate-limiting on the `/pair` endpoint.
* Received files are written to a `Nearlink` folder inside the platform
  downloads directory. Filenames are sanitised, and a declared-size cap guards
  against oversized uploads.

---

## Testing

```bash
flutter test          # crypto, pairing payload and model unit tests
flutter analyze       # static analysis
```

The crypto tests cover identity persistence, signature verification, session
key agreement, tamper detection, MAC confirmation and the streaming frame
codec — the parts where a subtle bug would be a security bug.

---

## Known limitations

* mDNS on Linux needs `avahi-daemon` running; on Windows it uses the built-in
  DNS-SD support. Some corporate or guest Wi-Fi networks block multicast, which
  will hide peers — that is a network property, not a bug.
* QR **scanning** works on Android, iOS, macOS and web. Windows and Linux have
  no camera plugin in `mobile_scanner`, so the app falls back to manual PIN
  entry there (the screen says so).
* If `flutter pub get` reports a version conflict, run `flutter pub upgrade`
  — the dependency pins use caret ranges and resolve to current releases.
