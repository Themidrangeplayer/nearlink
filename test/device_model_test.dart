import 'package:flutter_test/flutter_test.dart';
import 'package:nearlink/core/models/device.dart';

void main() {
  test('TrustedDevice keeps its model, address and name through JSON', () {
    final device = TrustedDevice(
      deviceId: 'dev-1',
      name: 'Living Room PC',
      platform: DevicePlatform.windows,
      model: 'Windows 11 Pro',
      identityKey: 'a',
      agreementKey: 'b',
      fingerprint: 'c',
      pairedAt: DateTime(2026, 1, 1),
      lastSeen: DateTime(2026, 1, 2),
      lastHost: '192.168.1.30',
      lastPort: 51234,
    );

    final restored = TrustedDevice.fromJson(device.toJson());
    expect(restored.model, 'Windows 11 Pro');
    expect(restored.lastHost, '192.168.1.30');
    expect(restored.lastPort, 51234);
    expect(restored.name, 'Living Room PC');
    expect(restored.platform, DevicePlatform.windows);
  });

  test('older records without a model still load', () {
    final restored = TrustedDevice.fromJson(<String, dynamic>{
      'deviceId': 'dev-2',
      'name': 'Old phone',
      'platform': 'android',
      'identityKey': 'a',
      'agreementKey': 'b',
      'fingerprint': 'c',
      'pairedAt': DateTime(2026, 1, 1).toIso8601String(),
      'lastSeen': null,
    });
    expect(restored.model, '');
    expect(restored.lastHost, isNull);
    expect(restored.name, 'Old phone');
  });

  test('copyWith carries model and address forward', () {
    final device = TrustedDevice(
      deviceId: 'dev-3',
      name: 'Phone',
      platform: DevicePlatform.android,
      model: 'Nothing A001',
      identityKey: 'a',
      agreementKey: 'b',
      fingerprint: 'c',
      pairedAt: DateTime(2026, 1, 1),
    );
    final updated = device.copyWith(lastHost: '10.0.0.5', lastPort: 999);
    expect(updated.model, 'Nothing A001');
    expect(updated.lastHost, '10.0.0.5');
    expect(updated.lastPort, 999);
  });
}
