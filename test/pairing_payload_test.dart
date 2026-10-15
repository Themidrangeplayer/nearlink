import 'package:flutter_test/flutter_test.dart';
import 'package:nearlink/core/crypto/pairing_payload.dart';
import 'package:nearlink/core/models/device.dart';

void main() {
  PairingPayload build() => PairingPayload(
        deviceId: 'dev-42',
        deviceName: "Ari's ThinkPad",
        platform: DevicePlatform.windows,
        agreementKey: 'QUFB',
        identityKey: 'QkJC',
        fingerprint: List.filled(64, 'a').join(),
        host: '192.168.1.24',
        port: 51234,
        token: 'tok-123',
        pin: '004217',
        createdAt: DateTime.now(),
      );

  test('encodes and decodes via QR data', () {
    final payload = build();
    final decoded = PairingPayload.tryDecode(payload.toQrData());

    expect(decoded, isNotNull);
    expect(decoded!.deviceId, 'dev-42');
    expect(decoded.deviceName, "Ari's ThinkPad");
    expect(decoded.platform, DevicePlatform.windows);
    expect(decoded.host, '192.168.1.24');
    expect(decoded.port, 51234);
    expect(decoded.token, 'tok-123');
    expect(decoded.pin, '004217');
  });

  test('tolerates a bare encoded payload without the scheme prefix', () {
    final payload = build();
    final decoded = PairingPayload.tryDecode(payload.encoded);
    expect(decoded?.deviceId, 'dev-42');
  });

  test('returns null for junk', () {
    expect(PairingPayload.tryDecode('not a nearlink code'), isNull);
    expect(PairingPayload.tryDecode(''), isNull);
  });

  test('expires after the configured window', () {
    final old = PairingPayload(
      deviceId: 'dev-1',
      deviceName: 'Old',
      platform: DevicePlatform.linux,
      agreementKey: 'x',
      identityKey: 'y',
      fingerprint: 'z',
      host: '10.0.0.2',
      port: 1234,
      token: 't',
      pin: '000000',
      createdAt: DateTime.now().subtract(const Duration(minutes: 6)),
    );
    expect(old.isExpired(), isTrue);
  });
}
