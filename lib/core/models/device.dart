/// Device domain models: the platform a device runs on, a trusted (paired)
/// device, and a peer discovered on the local network.
library;

enum DevicePlatform { android, ios, windows, macos, linux, unknown }

DevicePlatform platformFromString(String? value) {
  switch ((value ?? '').toLowerCase()) {
    case 'android':
      return DevicePlatform.android;
    case 'ios':
      return DevicePlatform.ios;
    case 'windows':
      return DevicePlatform.windows;
    case 'macos':
      return DevicePlatform.macos;
    case 'linux':
      return DevicePlatform.linux;
    default:
      return DevicePlatform.unknown;
  }
}

String platformLabel(DevicePlatform platform) {
  switch (platform) {
    case DevicePlatform.android:
      return 'Android';
    case DevicePlatform.ios:
      return 'iOS';
    case DevicePlatform.windows:
      return 'Windows';
    case DevicePlatform.macos:
      return 'macOS';
    case DevicePlatform.linux:
      return 'Linux';
    case DevicePlatform.unknown:
      return 'Unknown';
  }
}

/// A device that has completed pairing and is stored in the trust store.
class TrustedDevice {
  const TrustedDevice({
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.identityKey,
    required this.agreementKey,
    required this.fingerprint,
    required this.pairedAt,
    this.lastSeen,
    this.model = '',
    this.lastHost,
    this.lastPort,
  });

  final String deviceId;
  final String name;
  final DevicePlatform platform;

  /// Base64 Ed25519 public key (the device's stable identity).
  final String identityKey;

  /// Base64 X25519 public key (used for session key agreement).
  final String agreementKey;

  /// Hex SHA-256 of [identityKey]; the value a user can compare out-of-band.
  final String fingerprint;

  final DateTime pairedAt;
  final DateTime? lastSeen;

  /// A short device descriptor, e.g. "Nothing A001", "MacBookAir10,1",
  /// "Windows 11 Pro" — shown next to the platform.
  final String model;

  /// Last address we saw this device at, so we can try it even when discovery
  /// has not listed it.
  final String? lastHost;
  final int? lastPort;

  TrustedDevice copyWith({
    String? name,
    DateTime? lastSeen,
    String? model,
    String? lastHost,
    int? lastPort,
  }) =>
      TrustedDevice(
        deviceId: deviceId,
        name: name ?? this.name,
        platform: platform,
        identityKey: identityKey,
        agreementKey: agreementKey,
        fingerprint: fingerprint,
        pairedAt: pairedAt,
        lastSeen: lastSeen ?? this.lastSeen,
        model: model ?? this.model,
        lastHost: lastHost ?? this.lastHost,
        lastPort: lastPort ?? this.lastPort,
      );

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'name': name,
        'platform': platform.name,
        'identityKey': identityKey,
        'agreementKey': agreementKey,
        'fingerprint': fingerprint,
        'pairedAt': pairedAt.toIso8601String(),
        'lastSeen': lastSeen?.toIso8601String(),
        'model': model,
        'lastHost': lastHost,
        'lastPort': lastPort,
      };

  factory TrustedDevice.fromJson(Map<String, dynamic> json) => TrustedDevice(
        deviceId: json['deviceId'] as String,
        name: json['name'] as String,
        platform: platformFromString(json['platform'] as String?),
        identityKey: json['identityKey'] as String,
        agreementKey: json['agreementKey'] as String,
        fingerprint: json['fingerprint'] as String,
        pairedAt: DateTime.parse(json['pairedAt'] as String),
        lastSeen: json['lastSeen'] == null
            ? null
            : DateTime.parse(json['lastSeen'] as String),
        model: json['model'] as String? ?? '',
        lastHost: json['lastHost'] as String?,
        lastPort: json['lastPort'] as int?,
      );
}

/// A device currently visible on the local network via mDNS, whether or not it
/// has been paired with.
class NearbyPeer {
  const NearbyPeer({
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.host,
    required this.port,
    required this.fingerprint,
    required this.agreementKey,
    required this.discoveredAt,
    this.model = '',
  });

  final String deviceId;
  final String name;
  final DevicePlatform platform;
  final String host;
  final int port;
  final String fingerprint;
  final String agreementKey;
  final DateTime discoveredAt;
  final String model;

  NearbyPeer copyWith({DateTime? discoveredAt}) => NearbyPeer(
        deviceId: deviceId,
        name: name,
        platform: platform,
        host: host,
        port: port,
        fingerprint: fingerprint,
        agreementKey: agreementKey,
        discoveredAt: discoveredAt ?? this.discoveredAt,
        model: model,
      );

  @override
  bool operator ==(Object other) =>
      other is NearbyPeer && other.deviceId == deviceId;

  @override
  int get hashCode => deviceId.hashCode;
}
