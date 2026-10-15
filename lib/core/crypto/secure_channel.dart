import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// An authenticated, end-to-end encrypted channel to a single peer.
///
/// The session key is derived with X25519 ECDH + HKDF-SHA256 from the two
/// devices' agreement key pairs and a random salt, so it is unique per session
/// and never crosses the wire. Every payload is sealed with AES-256-GCM, which
/// provides confidentiality and integrity together.
class SecureChannel {
  SecureChannel._(this.sessionKey, this.peerFingerprint);

  final SecretKey sessionKey;
  final String peerFingerprint;

  static final AesGcm _aes = AesGcm.with256bits();
  static final X25519 _x25519 = X25519();
  static final Hmac _hmac = Hmac.sha256();
  static final Random _random = Random.secure();

  /// 12-byte AES-GCM nonce length.
  static const int nonceLength = 12;

  /// 16-byte GCM authentication tag length.
  static const int macLength = 16;

  /// Derive the shared session key from our agreement key pair, the peer's
  /// public agreement key, and a random salt contributed by both sides.
  static Future<SecretKey> deriveSessionKey({
    required SimpleKeyPair localKeyPair,
    required SimplePublicKey remotePublicKey,
    required List<int> salt,
    String info = 'nearlink/v1/session',
  }) async {
    final shared = await _x25519.sharedSecretKey(
      keyPair: localKeyPair,
      remotePublicKey: remotePublicKey,
    );
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    return hkdf.deriveKey(
      secretKey: shared,
      nonce: salt,
      info: utf8.encode(info),
    );
  }

  static SecureChannel create({
    required SecretKey sessionKey,
    required String peerFingerprint,
  }) =>
      SecureChannel._(sessionKey, peerFingerprint);

  /// 32 random bytes, used as an HKDF salt / handshake nonce.
  static Uint8List randomBytes([int length = 32]) {
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      out[i] = _random.nextInt(256);
    }
    return out;
  }

  /// Encrypt a plaintext blob into a self-contained sealed box
  /// (`nonce || ciphertext || mac`).
  Future<List<int>> seal(List<int> plain) async {
    final box = await _aes.encrypt(plain, secretKey: sessionKey);
    return box.concatenation();
  }

  /// Reverse of [seal]. Throws [SecretBoxAuthenticationError] if the box was
  /// tampered with or the key is wrong.
  Future<List<int>> open(List<int> sealed) async {
    final box = SecretBox.fromConcatenation(
      sealed,
      nonceLength: nonceLength,
      macLength: macLength,
    );
    return _aes.decrypt(box, secretKey: sessionKey);
  }

  Future<String> sealString(String plain) async =>
      base64Encode(await seal(utf8.encode(plain)));

  Future<String> openString(String sealed) async =>
      utf8.decode(await open(base64Decode(sealed)));

  /// A key-confirmation MAC. Both sides compute the same value over the two
  /// device ids and the two handshake nonces; a mismatch aborts the session.
  Future<String> confirmationMac({
    required String localDeviceId,
    required String remoteDeviceId,
    required List<int> localNonce,
    required List<int> remoteNonce,
  }) async {
    final message = [
      localDeviceId,
      remoteDeviceId,
      base64Encode(localNonce),
      base64Encode(remoteNonce),
    ].join('|');
    final mac = await _hmac.calculateMac(utf8.encode(message), secretKey: sessionKey);
    return base64Encode(mac.bytes);
  }
}

/// Frames sealed blobs for streaming: each frame is a 4-byte big-endian length
/// prefix followed by one sealed box.
class FrameCodec {
  FrameCodec._();

  static Uint8List frame(List<int> sealed) {
    final header = ByteData(4)..setUint32(0, sealed.length, Endian.big);
    final out = Uint8List(4 + sealed.length);
    out.setRange(0, 4, header.buffer.asUint8List());
    out.setRange(4, out.length, sealed);
    return out;
  }

  static FrameReader reader() => FrameReader();
}

/// Accumulates bytes off a socket and yields complete frames.
class FrameReader {
  final List<int> _buffer = <int>[];

  void add(List<int> chunk) => _buffer.addAll(chunk);

  /// Returns the next complete frame body, or null if more bytes are needed.
  List<int>? next() {
    if (_buffer.length < 4) return null;
    final header = Uint8List.fromList(_buffer.sublist(0, 4));
    final length = ByteData.sublistView(header).getUint32(0, Endian.big);
    if (_buffer.length < 4 + length) return null;
    final frame = _buffer.sublist(4, 4 + length);
    _buffer.removeRange(0, 4 + length);
    return frame;
  }

  bool get isEmpty => _buffer.isEmpty;
}
