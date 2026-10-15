import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nearlink/core/crypto/device_identity.dart';
import 'package:nearlink/core/crypto/secure_channel.dart';

void main() {
  group('DeviceIdentity', () {
    test('round-trips through JSON with a stable fingerprint', () async {
      final identity = await DeviceIdentity.generate('dev-1');
      final restored =
          await DeviceIdentity.fromJson(await identity.toJson());

      expect(restored.deviceId, 'dev-1');
      expect(restored.fingerprint, identity.fingerprint);
      expect(restored.agreementPublicKeyBase64,
          identity.agreementPublicKeyBase64);
      expect(restored.signingPublicKeyBase64, identity.signingPublicKeyBase64);
    });

    test('fingerprint is a 64-character hex digest', () async {
      final identity = await DeviceIdentity.generate('dev-2');
      expect(identity.fingerprint, hasLength(64));
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(identity.fingerprint), isTrue);
    });

    test('signatures verify only for the signed message', () async {
      final identity = await DeviceIdentity.generate('dev-3');
      final message = utf8.encode('transfer-approval');
      final signature = await identity.sign(message);

      expect(
        await DeviceIdentity.verify(
          message: message,
          signature: signature,
          publicKey: identity.signingPublicKey.bytes,
        ),
        isTrue,
      );
      expect(
        await DeviceIdentity.verify(
          message: utf8.encode('different'),
          signature: signature,
          publicKey: identity.signingPublicKey.bytes,
        ),
        isFalse,
      );
    });
  });

  group('SecureChannel', () {
    test('both sides derive the same key and can exchange a secret', () async {
      final a = await DeviceIdentity.generate('a');
      final b = await DeviceIdentity.generate('b');
      final salt = SecureChannel.randomBytes(32);

      final keyA = await SecureChannel.deriveSessionKey(
        localKeyPair: a.agreementKeyPair,
        remotePublicKey: b.agreementPublicKey,
        salt: salt,
      );
      final keyB = await SecureChannel.deriveSessionKey(
        localKeyPair: b.agreementKeyPair,
        remotePublicKey: a.agreementPublicKey,
        salt: salt,
      );

      final channelA = SecureChannel.create(sessionKey: keyA, peerFingerprint: b.fingerprint);
      final channelB = SecureChannel.create(sessionKey: keyB, peerFingerprint: a.fingerprint);

      final sealed = await channelA.seal(utf8.encode('hello nearlink'));
      final opened = await channelB.open(sealed);
      expect(utf8.decode(opened), 'hello nearlink');
    });

    test('a different salt produces a different key', () async {
      final a = await DeviceIdentity.generate('a');
      final b = await DeviceIdentity.generate('b');

      final keyA = await SecureChannel.deriveSessionKey(
        localKeyPair: a.agreementKeyPair,
        remotePublicKey: b.agreementPublicKey,
        salt: SecureChannel.randomBytes(32),
      );
      final keyB = await SecureChannel.deriveSessionKey(
        localKeyPair: b.agreementKeyPair,
        remotePublicKey: a.agreementPublicKey,
        salt: SecureChannel.randomBytes(32),
      );

      final channelA = SecureChannel.create(sessionKey: keyA, peerFingerprint: '');
      final channelB = SecureChannel.create(sessionKey: keyB, peerFingerprint: '');
      final sealed = await channelA.seal(utf8.encode('x'));

      expect(() => channelB.open(sealed), throwsA(anything));
    });

    test('tampered ciphertext is rejected', () async {
      final key = SecretKeyData(List<int>.generate(32, (i) => i));
      final channel = SecureChannel.create(sessionKey: key, peerFingerprint: '');

      final sealed = await channel.seal(utf8.encode('important'));
      sealed[sealed.length - 1] ^= 0xFF;

      expect(() => channel.open(sealed), throwsA(anything));
    });

    test('confirmation MAC agrees across both sides', () async {
      final a = await DeviceIdentity.generate('a');
      final b = await DeviceIdentity.generate('b');
      final salt = SecureChannel.randomBytes(32);

      final keyA = await SecureChannel.deriveSessionKey(
        localKeyPair: a.agreementKeyPair,
        remotePublicKey: b.agreementPublicKey,
        salt: salt,
      );
      final keyB = await SecureChannel.deriveSessionKey(
        localKeyPair: b.agreementKeyPair,
        remotePublicKey: a.agreementPublicKey,
        salt: salt,
      );

      final channelA = SecureChannel.create(sessionKey: keyA, peerFingerprint: '');
      final channelB = SecureChannel.create(sessionKey: keyB, peerFingerprint: '');

      final nonceA = SecureChannel.randomBytes(32);
      final nonceB = SecureChannel.randomBytes(32);

      final macInitiator = await channelA.confirmationMac(
        localDeviceId: 'a',
        remoteDeviceId: 'b',
        localNonce: nonceA,
        remoteNonce: nonceB,
      );
      final macResponder = await channelB.confirmationMac(
        localDeviceId: 'a',
        remoteDeviceId: 'b',
        localNonce: nonceA,
        remoteNonce: nonceB,
      );
      expect(macInitiator, macResponder);
    });
  });

  group('FrameCodec', () {
    test('round-trips multiple frames across arbitrary chunk boundaries', () async {
      final key = SecretKeyData(List<int>.generate(32, (i) => 255 - i));
      final channel = SecureChannel.create(sessionKey: key, peerFingerprint: '');

      final messages = [
        utf8.encode('first'),
        utf8.encode('second message that is a bit longer'),
        utf8.encode('third'),
      ];

      final wire = <int>[];
      for (final message in messages) {
        wire.addAll(FrameCodec.frame(await channel.seal(message)));
      }

      // Feed the wire in awkward 7-byte pieces.
      final reader = FrameCodec.reader();
      final decoded = <String>[];
      for (var i = 0; i < wire.length; i += 7) {
        reader.add(wire.sublist(i, (i + 7).clamp(0, wire.length)));
        List<int>? frame = reader.next();
        while (frame != null) {
          decoded.add(utf8.decode(await channel.open(frame)));
          frame = reader.next();
        }
      }

      expect(decoded, ['first', 'second message that is a bit longer', 'third']);
      expect(reader.isEmpty, isTrue);
    });
  });
}
