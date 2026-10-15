import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../utils/bytes.dart';

/// The permanent cryptographic identity of this device.
///
/// Two key pairs are generated once, on first launch, and stored locally:
///
/// * an **Ed25519** signing pair, whose public key is the device's stable
///   identity and whose SHA-256 is the human-comparable [fingerprint]; and
/// * an **X25519** agreement pair, used to derive per-session keys with peers.
///
/// Nothing here is ever transmitted as a secret. Only the two public keys and
/// the fingerprint travel the wire; the private halves never leave the device.
class DeviceIdentity {
  DeviceIdentity({
    required this.deviceId,
    required SimpleKeyPair signingKeyPair,
    required SimpleKeyPair agreementKeyPair,
    required this.signingPublicKey,
    required this.agreementPublicKey,
    required this.fingerprint,
  })  : _signingKeyPair = signingKeyPair,
        _agreementKeyPair = agreementKeyPair;

  final String deviceId;
  final SimplePublicKey signingPublicKey;
  final SimplePublicKey agreementPublicKey;
  final String fingerprint;

  final SimpleKeyPair _signingKeyPair;
  final SimpleKeyPair _agreementKeyPair;

  SimpleKeyPair get signingKeyPair => _signingKeyPair;
  SimpleKeyPair get agreementKeyPair => _agreementKeyPair;

  static final Ed25519 _ed25519 = Ed25519();
  static final X25519 _x25519 = X25519();
  static final Sha256 _sha256 = Sha256();

  static Future<DeviceIdentity> generate(String deviceId) async {
    final signing = await _ed25519.newKeyPair();
    final agreement = await _x25519.newKeyPair();
    return _assemble(deviceId, signing, agreement);
  }

  static Future<DeviceIdentity> _assemble(
    String deviceId,
    SimpleKeyPair signing,
    SimpleKeyPair agreement,
  ) async {
    final signingPublic = await signing.extractPublicKey();
    final agreementPublic = await agreement.extractPublicKey();
    final fingerprint = await fingerprintOf(signingPublic);
    return DeviceIdentity(
      deviceId: deviceId,
      signingKeyPair: signing,
      agreementKeyPair: agreement,
      signingPublicKey: signingPublic,
      agreementPublicKey: agreementPublic,
      fingerprint: fingerprint,
    );
  }

  /// SHA-256 of an Ed25519 public key, hex encoded.
  static Future<String> fingerprintOf(SimplePublicKey publicKey) async {
    final hash = await _sha256.hash(publicKey.bytes);
    return hexEncode(hash.bytes);
  }

  String get signingPublicKeyBase64 => base64Encode(signingPublicKey.bytes);
  String get agreementPublicKeyBase64 => base64Encode(agreementPublicKey.bytes);

  /// Sign an arbitrary message with the Ed25519 identity key.
  Future<List<int>> sign(List<int> message) async {
    final signature = await _ed25519.sign(message, keyPair: _signingKeyPair);
    return signature.bytes;
  }

  /// Verify a signature against a peer's Ed25519 public key.
  static Future<bool> verify({
    required List<int> message,
    required List<int> signature,
    required List<int> publicKey,
  }) async {
    return _ed25519.verify(
      message,
      signature: Signature(signature, publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519)),
    );
  }

  /// Serialise the private material for local persistence.
  ///
  /// In production this should be written to platform secure storage
  /// (Keychain / Keystore) rather than plain preferences; see [TrustStore] and
  /// [KeyVault].
  Future<Map<String, dynamic>> toJson() async {
    final signingData = await _signingKeyPair.extract();
    final agreementData = await _agreementKeyPair.extract();
    return {
      'deviceId': deviceId,
      'signingSeed': base64Encode(signingData.bytes),
      'agreementSeed': base64Encode(agreementData.bytes),
    };
  }

  static Future<DeviceIdentity> fromJson(Map<String, dynamic> json) async {
    final signingSeed = base64Decode(json['signingSeed'] as String);
    final agreementSeed = base64Decode(json['agreementSeed'] as String);
    final signing = await _ed25519.newKeyPairFromSeed(signingSeed);
    final agreement = await _x25519.newKeyPairFromSeed(agreementSeed);
    return _assemble(json['deviceId'] as String, signing, agreement);
  }
}
