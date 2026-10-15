# Nearlink architecture

## Design goals

1. **One codebase, five platforms.** Android, iOS, Windows, macOS and Linux
   share all application logic. Only discovery and the camera are
   platform-sensitive, and both are behind small abstractions.
2. **No account, no server.** Trust is established device-to-device.
3. **End-to-end encryption as a property of the payload**, not of the network.

## Why mDNS + HTTP

Nearby discovery has three credible designs:

* **Platform-native** (Android Nearby Connections, iOS MultipeerConnectivity)
  gives the best proximity UX but cannot share code across platforms — you
  would write the app twice, and desktop is left out entirely.
* **Bluetooth LE + Wi-Fi Direct** is the most "proximity-true", but BLE
  peripheral support is uneven on desktop and Wi-Fi Direct is effectively
  Android-only.
* **mDNS/DNS-SD for discovery + an HTTP channel for transfer** works on every
  target platform, needs no pairing at the radio layer, and is the approach
  proven by LocalSend and similar tools.

Nearlink takes the third path. Discovery is abstracted behind
`DiscoveryService`, so a native transport can be added later without touching
the rest of the app.

## Discovery

Each device registers an mDNS service of type `_nearlink._tcp` with TXT records
carrying its id, name, platform, fingerprint and agreement public key. Peers
appear as `NearbyPeer`s within a second or two. Discovery only advertises
**public** material; the pairing secret is never broadcast.

## Protocol (v1)

Transport: HTTP/1.1 over the LAN, on an ephemeral port advertised via mDNS.

| Endpoint | Purpose |
| --- | --- |
| `GET /api/v1/ping` | Liveness |
| `GET /api/v1/info` | Device id, name, platform, fingerprint, public keys |
| `POST /api/v1/handshake` | X25519 exchange + key confirmation |
| `POST /api/v1/pair` | Complete pairing with the active secret |
| `POST /api/v1/upload` | Streamed, sealed file |
| `POST /api/v1/clipboard` | Sealed clipboard text |

### Handshake

```
Initiator                                  Responder
  nonce_i  <- 32 random bytes
  POST /handshake {deviceId, agreementKey, identityKey, fingerprint, nonce_i}
                                    -------->
                                             nonce_r <- 32 random bytes
                                             salt = nonce_i || nonce_r
                                             key  = HKDF(X25519(priv_r, pub_i), salt)
                                             mac  = HMAC(key, ids + nonces)
                                    <--------
  salt = nonce_i || nonce_r
  key  = HKDF(X25519(priv_i, pub_r), salt)
  verify mac == HMAC(key, ids + nonces)
```

Both sides reach the same `salt`, so the same key. The MAC proves the
responder holds the matching private key. If `expectedFingerprint` was supplied
(from the pairing payload or the trust store), a mismatch aborts the session.

### File upload

The body is a sequence of frames:

```
[ 4-byte big-endian length ][ nonce(12) || ciphertext || tag(16) ]
```

Each frame is one AES-256-GCM box over up to 64 KiB of plaintext. The server
decrypts frame by frame and writes straight to disk, so memory use stays flat
regardless of file size. The transfer id, name, size and MIME type ride in
headers; the name is base64-encoded so it survives non-ASCII.

### Clipboard

The whole text is one AES-GCM box, base64-encoded into the body.

## Crypto summary

| Concern | Primitive |
| --- | --- |
| Device identity / fingerprint | Ed25519, SHA-256 |
| Key agreement | X25519 |
| Key derivation | HKDF-SHA256 (32-byte output, `info = "nearlink/v1/session"`) |
| Payload encryption | AES-256-GCM (12-byte nonce, 16-byte tag) |
| Key confirmation | HMAC-SHA256 |

All primitives come from the pure-Dart `cryptography` package, so there are no
native crypto dependencies to configure per platform.

## State flow

`AppState` (a `ChangeNotifier`) owns the identity, the trust store, the server,
the client and the discovery service. It implements `NearlinkServerDelegate`,
so incoming files, clipboard payloads and pairing completions flow from the
socket straight into the same store the UI watches. The widget tree reads it
with `provider`; user messages surface as a stream the shell turns into
snackbars.

## Extending it

* **Account sync** — add a server that stores only public keys per account and
  have devices exchange a signed account proof during pairing. The local trust
  store becomes a cache.
* **TLS** — wrap the server with `HttpServer.bindSecure` and pin the peer's
  certificate fingerprint (already exchanged at pairing).
* **Background receiving** — on mobile, run the server in a foreground service
  so transfers complete when the app is backgrounded.
