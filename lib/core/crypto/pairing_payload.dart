import 'dart:convert';

import '../models/device.dart';
import '../protocol/protocol.dart';

/// The information one device hands to another to establish trust.
///
/// Encoded as JSON, base64url-encoded, and embedded in a QR code (or, for the
/// manual path, its [pin] is typed in by hand). It carries only public
/// material plus a short-lived one-time secret — never a password or private
/// key.
class PairingPayload {
  const PairingPayload({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.agreementKey,
    required this.identityKey,
    required this.fingerprint,
    required this.host,
    required this.port,
    required this.token,
    required this.pin,
    required this.createdAt,
    this.model = '',
  });

  final String deviceId;
  final String deviceName;
  final DevicePlatform platform;

  /// Base64 X25519 public key.
  final String agreementKey;

  /// Base64 Ed25519 public key.
  final String identityKey;

  /// Hex SHA-256 of the identity key.
  final String fingerprint;

  final String host;
  final int port;

  /// Strong one-time secret used when pairing via QR.
  final String token;

  /// Six-digit human fallback, used for manual pairing.
  final String pin;

  final DateTime createdAt;

  /// Short device descriptor, e.g. "Nothing A001" or "MacBookAir10,1".
  final String model;

  /// Short-lived: a payload older than this is refused.
  bool isExpired({Duration maxAge = const Duration(minutes: 5)}) =>
      DateTime.now().difference(createdAt) > maxAge;

  PairingPayload copyWith({String? host, int? port}) => PairingPayload(
        deviceId: deviceId,
        deviceName: deviceName,
        platform: platform,
        model: model,
        agreementKey: agreementKey,
        identityKey: identityKey,
        fingerprint: fingerprint,
        host: host ?? this.host,
        port: port ?? this.port,
        token: token,
        pin: pin,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'v': NearlinkProtocol.version,
        'id': deviceId,
        'name': deviceName,
        'platform': platform.name,
        'model': model,
        'key': agreementKey,
        'ik': identityKey,
        'fp': fingerprint,
        'host': host,
        'port': port,
        'token': token,
        'pin': pin,
        'ts': createdAt.toIso8601String(),
      };

  factory PairingPayload.fromJson(Map<String, dynamic> json) => PairingPayload(
        deviceId: json['id'] as String,
        deviceName: json['name'] as String,
        platform: platformFromString(json['platform'] as String?),
        model: json['model'] as String? ?? '',
        agreementKey: json['key'] as String,
        identityKey: json['ik'] as String,
        fingerprint: json['fp'] as String,
        host: json['host'] as String,
        port: json['port'] as int,
        token: json['token'] as String,
        pin: json['pin'] as String,
        createdAt: DateTime.parse(json['ts'] as String),
      );

  /// The string to render as a QR code.
  String toQrData() => '${NearlinkProtocol.qrScheme}://pair/$encoded';

  String get encoded =>
      base64Url.encode(utf8.encode(jsonEncode(toJson())));

  /// Parse a scanned QR string, tolerating a missing scheme prefix.
  static PairingPayload? tryDecode(String raw) {
    var value = raw.trim();
    final prefix = '${NearlinkProtocol.qrScheme}://pair/';
    if (value.startsWith(prefix)) {
      value = value.substring(prefix.length);
    }
    try {
      final json = jsonDecode(utf8.decode(base64Url.decode(value)));
      return PairingPayload.fromJson(json as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
